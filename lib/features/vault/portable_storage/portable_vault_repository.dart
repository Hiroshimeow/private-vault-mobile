import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_format.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_key_deriver.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_object_codec.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_session.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_storage.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class PortableVaultRepository
    implements
        VaultScanAwareRepository,
        TransactionalPinSessionVaultRepository,
        PreparablePinSessionVaultRepository,
        StreamingVaultRepository,
        VaultThumbnailRepository {
  PortableVaultRepository({
    required this.storage,
    required this.session,
    PortableVaultObjectCodec? objectCodec,
    this.operationRecorder,
  }) : objectCodec = objectCodec ?? PortableVaultObjectCodec();

  final PortableVaultStorage storage;
  final PortableVaultSession session;
  final PortableVaultObjectCodec objectCodec;
  final VaultOperationRecorder? operationRecorder;

  void _record(VaultOperation operation) => operationRecorder?.call(operation);

  static final Expando<Set<String>> _activeWritesByStorage =
      Expando<Set<String>>('portable-vault-active-writes');

  Set<String> get _activeStreamWriteIds =>
      _activeWritesByStorage[storage] ??= <String>{};

  final Set<String> _catalogReauthenticationPaths = <String>{};

  @override
  bool get hasOpenSession => session.isOpen;

  @override
  int get sessionGeneration => session.generation;

  @override
  Future<void> openSession(String pin) async {
    await openSessionWithGeneration(pin);
  }

  @override
  Future<int> openSessionWithGeneration(String pin) =>
      session.openWithGeneration(pin);

  @override
  Future<PreparedPinSession> prepareSession(String pin) async {
    final expectedGeneration = session.generation;
    final material = await session.prepare(pin);
    if (session.generation != expectedGeneration) {
      material.destroy();
      throw const PortableVaultSessionChangedException();
    }
    return _PortablePreparedPinSession(material, expectedGeneration);
  }

  @override
  int activatePreparedSession(PreparedPinSession prepared) {
    if (prepared is! _PortablePreparedPinSession || prepared.consumed) {
      throw const PortableVaultSessionChangedException();
    }
    prepared.consumed = true;
    return session.activate(
      prepared.material,
      expectedGeneration: prepared.expectedGeneration,
    );
  }

  @override
  void clearSessionIfGeneration(int generation) =>
      session.clearIfGeneration(generation);

  @override
  Future<PinSessionSwitchOutcome> switchSession(
    String pin,
    Future<void> Function() commitIdentity,
  ) async {
    await _requireAccess();
    final expectedGeneration = session.generation;
    final next = await session.prepare(pin);
    try {
      await commitIdentity();
    } on Object {
      next.destroy();
      rethrow;
    }
    try {
      session.activate(next, expectedGeneration: expectedGeneration);
      return PinSessionSwitchOutcome.active;
    } on PortableVaultSessionChangedException {
      // The verifier commit already succeeded. A lock/panic or a newer
      // session owns the generation now, so preserve that boundary and report
      // that the identity changed but requires a fresh unlock.
      return PinSessionSwitchOutcome.committedSessionClosed;
    }
  }

  @override
  void clearSession() => session.clear();

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    if (kind == VaultItemKind.unknown) {
      throw ArgumentError.value(kind, 'kind', 'unknown cannot be persisted');
    }
    await _requireAccess();
    final material = session.requireMaterial();
    final createdAt = DateTime.now().toUtc();
    final id = _newId();
    final encoded = await objectCodec.encode(
      PortableVaultObject(
        fileName: '$id.bin',
        mediaType: _mediaTypeFor(kind),
        createdAtMillis: createdAt.millisecondsSinceEpoch,
        namespaceId: material.namespaceId,
        bytes: bytes,
      ),
      material.encryptionKey,
    );
    await storage.write(_objectPath(material.namespaceId, id), encoded);
    await _upsertCatalogBestEffort(
      namespaceId: material.namespaceId,
      encryptionKey: material.encryptionKey,
      id: id,
      mediaType: _mediaTypeFor(kind),
      createdAtMillis: createdAt.millisecondsSinceEpoch,
    );
    return VaultItem(id: id, kind: kind, createdAt: createdAt);
  }

  @override
  Future<VaultItem> addStream(
    Stream<List<int>> bytes, {
    required VaultItemKind kind,
  }) async {
    if (kind == VaultItemKind.unknown) {
      throw ArgumentError.value(kind, 'kind', 'unknown cannot be persisted');
    }
    await _requireAccess();
    final targetStorage = storage;
    if (targetStorage is! PortableVaultStreamingStorage) {
      throw const PortableVaultStreamingUnsupportedException();
    }

    final material = session.requireMaterial();
    final createdAt = DateTime.now().toUtc();
    final id = _newId();
    final encoded = objectCodec.encodeStream(
      fileName: '$id.bin',
      mediaType: _mediaTypeFor(kind),
      createdAtMillis: createdAt.millisecondsSinceEpoch,
      namespaceId: material.namespaceId,
      payload: bytes,
      key: material.encryptionKey,
    );
    _activeStreamWriteIds.add(id);
    late final PortableVaultWriteSession writer;
    try {
      writer = await targetStorage.beginWrite(
        _objectPath(material.namespaceId, id),
      );
    } on Object {
      _activeStreamWriteIds.remove(id);
      rethrow;
    }
    try {
      try {
        await writer.append(encoded.prefix);
        await for (final chunk in encoded.cipherText) {
          if (chunk.isNotEmpty) await writer.append(chunk);
        }
        final tag = await encoded.tag;
        await writer.patch(encoded.tagOffset, tag);
        await writer.commit();
      } on Object {
        await writer.abort();
        rethrow;
      }
    } finally {
      _activeStreamWriteIds.remove(id);
    }

    await _upsertCatalogBestEffort(
      namespaceId: material.namespaceId,
      encryptionKey: material.encryptionKey,
      id: id,
      mediaType: _mediaTypeFor(kind),
      createdAtMillis: createdAt.millisecondsSinceEpoch,
    );
    return VaultItem(id: id, kind: kind, createdAt: createdAt);
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    await _requireAccess();
    final material = session.requireMaterial();
    try {
      _record(VaultOperation.payloadRead);
      final encoded = await storage.read(_objectPath(material.namespaceId, id));
      _record(VaultOperation.payloadDecrypt);
      final object = await objectCodec.decode(encoded, material.encryptionKey);
      _validatePayloadIdentity(
        object,
        expectedNamespace: material.namespaceId,
        expectedId: id,
      );
      return object.bytes;
    } on PortableVaultStorageNotFoundException {
      await _invalidateCatalogEntry(material, id);
      throw VaultItemInvalidException(id);
    } on PortableVaultUnsupportedProfileException {
      await _invalidateCatalogEntry(material, id);
      throw VaultItemInvalidException(id);
    } on VaultIntegrityException {
      await _invalidateCatalogEntry(material, id);
      throw VaultItemInvalidException(id);
    } on PortableVaultForeignObjectException {
      await _invalidateCatalogEntry(material, id);
      throw VaultItemInvalidException(id);
    } on PortableVaultFormatException {
      await _invalidateCatalogEntry(material, id);
      throw VaultItemInvalidException(id);
    }
  }

  @override
  Future<Uint8List?> readThumbnail(String id) async {
    await _requireAccess();
    final material = session.requireMaterial();
    for (final path in [
      _thumbnailPath(material.namespaceId, id),
      _legacyThumbnailPath(material.namespaceId, id),
    ]) {
      try {
        _record(VaultOperation.thumbnailRead);
        final encoded = await storage.read(path);
        _record(VaultOperation.thumbnailDecrypt);
        final thumbnail = await objectCodec.decode(
          encoded,
          material.encryptionKey,
        );
        if (thumbnail.namespaceId != material.namespaceId ||
            thumbnail.fileName != '$id.thumb' ||
            thumbnail.mediaType != 'image/jpeg' ||
            thumbnail.bytes.isEmpty) {
          throw const PortableVaultFormatException();
        }
        return thumbnail.bytes;
      } on PortableVaultStorageNotFoundException {
        continue;
      } on PortableVaultUnsupportedProfileException {
        await _deleteAuxiliaryBestEffort(path);
      } on VaultIntegrityException {
        await _deleteAuxiliaryBestEffort(path);
      } on PortableVaultFormatException {
        await _deleteAuxiliaryBestEffort(path);
      }
    }
    return null;
  }

  @override
  Future<void> writeThumbnail(String id, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    await _requireAccess();
    final material = session.requireMaterial();
    _record(VaultOperation.payloadRead);
    final payloadEncoded = await storage.read(
      _objectPath(material.namespaceId, id),
    );
    _record(VaultOperation.payloadDecrypt);
    final payload = await objectCodec.decode(
      payloadEncoded,
      material.encryptionKey,
    );
    _validatePayloadIdentity(
      payload,
      expectedNamespace: material.namespaceId,
      expectedId: id,
    );
    await _writeThumbnail(
      material: material,
      id: id,
      createdAtMillis: payload.createdAtMillis,
      bytes: bytes,
    );
  }

  @override
  Future<void> writeThumbnailForAuthenticatedItem(
    VaultItem item,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty) return;
    await _requireAccess();
    final material = session.requireMaterial();
    await _writeThumbnail(
      material: material,
      id: item.id,
      createdAtMillis: item.createdAt.toUtc().millisecondsSinceEpoch,
      bytes: bytes,
    );
  }

  Future<void> _writeThumbnail({
    required PortableVaultKeyMaterial material,
    required String id,
    required int createdAtMillis,
    required Uint8List bytes,
  }) async {
    final encoded = await objectCodec.encode(
      PortableVaultObject(
        fileName: '$id.thumb',
        mediaType: 'image/jpeg',
        createdAtMillis: createdAtMillis,
        namespaceId: material.namespaceId,
        bytes: bytes,
      ),
      material.encryptionKey,
    );
    _record(VaultOperation.thumbnailWrite);
    await storage.write(_thumbnailPath(material.namespaceId, id), encoded);
  }

  @override
  Future<List<VaultItem>> list() async {
    final result = await scan();
    if (result.hasProblems) throw VaultScanException(result);
    return result.items;
  }

  @override
  Future<VaultScanResult> scan() async {
    await _requireAccess();
    final material = session.requireMaterial();
    final basePath = '${material.namespaceId}/objects';

    late final List<String> names;
    var entryMetadata = <String, PortableVaultStorageEntryMetadata>{};
    try {
      final targetStorage = storage;
      if (targetStorage is PortableVaultMetadataStorage) {
        _record(VaultOperation.objectListing);
        _record(VaultOperation.metadataProviderQuery);
        final entries = await (targetStorage as PortableVaultMetadataStorage)
            .listMetadata(basePath);
        entryMetadata = {for (final entry in entries) entry.name: entry};
        names = entryMetadata.keys.toList(growable: false);
      } else {
        _record(VaultOperation.objectListing);
        names = await storage.list(basePath);
      }
    } on PortableVaultStorageException {
      return const VaultScanResult(items: [], storageFailureCount: 1);
    }

    var storageFailureCount = 0;
    final visibleNames = <String>[];
    final survivingPartialIds = <String>{};
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    for (final name in names) {
      if (_isPartialStorageName(name)) {
        final partialId = _partialStorageObjectId(name);
        final active =
            partialId != null && _activeStreamWriteIds.contains(partialId);
        var survives = true;
        if (!active && _isStalePartialStorageName(name, nowMillis)) {
          try {
            await storage.delete('$basePath/$name');
            survives = false;
          } on PortableVaultStorageException {
            // Abandoned temp cleanup is best effort. Preserve matching
            // legacy sidecars while the partial itself still exists.
          }
        }
        if (survives && partialId != null) {
          survivingPartialIds.add(partialId);
        }
        continue;
      }
      visibleNames.add(name);
    }

    final payloadIds = visibleNames
        .where((name) => name.endsWith('.pvb'))
        .map((name) => name.substring(0, name.length - '.pvb'.length))
        .toSet();
    final metadataIds = visibleNames
        .where((name) => name.endsWith('.pvm'))
        .map((name) => name.substring(0, name.length - '.pvm'.length))
        .toSet();
    final legacyThumbnailIds = visibleNames
        .where((name) => name.endsWith('.pvt'))
        .map((name) => name.substring(0, name.length - '.pvt'.length))
        .toSet();
    final thumbnailCachePath = '${material.namespaceId}/cache/thumbnails';
    Set<String> modernThumbnailIds = const <String>{};
    try {
      _record(VaultOperation.objectListing);
      modernThumbnailIds = (await storage.list(thumbnailCachePath))
          .where((name) => name.endsWith('.pvt'))
          .map((name) => name.substring(0, name.length - '.pvt'.length))
          .toSet();
    } on PortableVaultStorageException {
      // Cache discovery is best effort and cannot make payload listing fail.
    }

    final orphanSidecarIds = metadataIds
        .union(legacyThumbnailIds)
        .union(modernThumbnailIds)
        .difference(payloadIds)
        .difference(survivingPartialIds);
    final orphanedSidecarCount = orphanSidecarIds.length;
    for (final id in orphanSidecarIds) {
      _record(VaultOperation.mutationReconciliation);
      if (metadataIds.contains(id)) {
        try {
          await storage.delete('$basePath/$id.pvm');
        } on PortableVaultStorageException {
          // Payload-less metadata is reconstructible compatibility cache.
        }
      }
      if (legacyThumbnailIds.contains(id)) {
        try {
          await storage.delete('$basePath/$id.pvt');
        } on PortableVaultStorageException {
          // Legacy thumbnail cache is reconstructible.
        }
      }
      if (modernThumbnailIds.contains(id)) {
        try {
          await storage.delete('$thumbnailCachePath/$id.pvt');
        } on PortableVaultStorageException {
          // Modern thumbnail cache is equally reconstructible.
        }
      }
    }

    final catalog = await _readCatalog(
      namespaceId: material.namespaceId,
      encryptionKey: material.encryptionKey,
    );
    final resolvedCatalog = <String, _PortableCatalogEntry>{};
    final items = <VaultItem>[];
    var corruptCount = 0;
    var unsupportedCount = 0;
    var foreignCount = 0;

    for (final id in payloadIds) {
      final metadata = entryMetadata['$id.pvb'];
      final cached = catalog[id];
      final objectPath = _objectPath(material.namespaceId, id);
      if (cached != null &&
          metadata != null &&
          cached.matches(metadata) &&
          !_catalogReauthenticationPaths.contains(objectPath)) {
        resolvedCatalog[id] = cached;
        items.add(_catalogItem(cached));
        continue;
      }

      try {
        final object = await _loadListingMetadata(
          namespaceId: material.namespaceId,
          encryptionKey: material.encryptionKey,
          basePath: basePath,
          id: id,
          hasSidecar: metadataIds.contains(id),
        );
        final entry = _PortableCatalogEntry(
          id: id,
          mediaType: object.mediaType,
          createdAtMillis: object.createdAtMillis,
          sizeBytes: metadata?.hasSizeFingerprint == true
              ? metadata!.sizeBytes
              : null,
          modifiedAtMillis: metadata?.hasReliableModificationTime == true
              ? metadata!.modifiedAtMillis
              : null,
        );
        resolvedCatalog[id] = entry;
        items.add(_catalogItem(entry));
      } on PortableVaultForeignObjectException {
        foreignCount += 1;
      } on PortableVaultUnsupportedProfileException {
        unsupportedCount += 1;
      } on VaultIntegrityException {
        corruptCount += 1;
      } on PortableVaultFormatException {
        corruptCount += 1;
      } on PortableVaultStorageException {
        storageFailureCount += 1;
      }
    }

    final catalogChanged =
        catalog.length != resolvedCatalog.length ||
        resolvedCatalog.entries.any(
          (entry) => catalog[entry.key] != entry.value,
        );
    if (catalogChanged) {
      _record(VaultOperation.mutationReconciliation);
      final repaired = await _writeCatalogBestEffort(
        namespaceId: material.namespaceId,
        encryptionKey: material.encryptionKey,
        entries: resolvedCatalog,
      );
      if (repaired) {
        _catalogReauthenticationPaths.removeWhere(
          (path) => path.startsWith('$basePath/'),
        );
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return VaultScanResult(
      items: List.unmodifiable(items),
      corruptCount: corruptCount,
      unsupportedCount: unsupportedCount,
      foreignCount: foreignCount,
      storageFailureCount: storageFailureCount,
      orphanedSidecarCount: orphanedSidecarCount,
    );
  }

  @override
  Future<void> delete(String id) async {
    await _requireAccess();
    final material = session.requireMaterial();
    await storage.delete(_objectPath(material.namespaceId, id));
    await _deleteAuxiliaryBestEffort(_metadataPath(material.namespaceId, id));
    await _deleteAuxiliaryBestEffort(
      _legacyThumbnailPath(material.namespaceId, id),
    );
    await _deleteAuxiliaryBestEffort(_thumbnailPath(material.namespaceId, id));
    await _removeFromCatalogBestEffort(
      namespaceId: material.namespaceId,
      encryptionKey: material.encryptionKey,
      id: id,
    );
  }

  Future<void> _deleteAuxiliaryBestEffort(String path) async {
    try {
      await storage.delete(path);
    } on PortableVaultStorageException {
      // The authoritative payload has already been removed. Sidecars are
      // encrypted/reconstructible and a later scan can reconcile leftovers.
    }
  }

  static const _partialCleanupAge = Duration(hours: 24);

  bool _isPartialStorageName(String name) => name.contains('.partial-');

  String? _partialStorageObjectId(String name) {
    final normalized = name.startsWith('.') ? name.substring(1) : name;
    for (final extension in const ['.pvb', '.pvm', '.pvt']) {
      final marker = normalized.indexOf('$extension.partial-');
      if (marker > 0) return normalized.substring(0, marker);
    }
    return null;
  }

  bool _isStalePartialStorageName(String name, int nowMillis) {
    final marker = name.lastIndexOf('.partial-');
    if (marker < 0) return false;
    final suffix = name.substring(marker + '.partial-'.length);
    final separator = suffix.indexOf('-');
    if (separator <= 0) {
      // Current builds always include a millisecond timestamp. A timestamp-less
      // partial can only be residue from an older build and is not owned by an
      // active current writer.
      return true;
    }
    final createdAtMillis = int.tryParse(suffix.substring(0, separator));
    if (createdAtMillis == null) return true;
    if (createdAtMillis > nowMillis) {
      // Active writes are excluded by _activeStreamWriteIds before this helper
      // is called. A future-dated non-active partial is abandoned clock-skew
      // residue and can be reclaimed safely.
      return true;
    }
    return nowMillis - createdAtMillis >= _partialCleanupAge.inMilliseconds;
  }

  Future<PortableVaultObject> _loadListingMetadata({
    required String namespaceId,
    required SecretKey encryptionKey,
    required String basePath,
    required String id,
    required bool hasSidecar,
  }) async {
    // The .pvb payload is authoritative. Listing caches may accelerate metadata
    // recovery, but they must never make a corrupt payload appear healthy.
    _record(VaultOperation.payloadRead);
    final payloadEncoded = await storage.read('$basePath/$id.pvb');
    _record(VaultOperation.payloadDecrypt);
    final payload = await objectCodec.decode(payloadEncoded, encryptionKey);
    _validatePayloadIdentity(
      payload,
      expectedNamespace: namespaceId,
      expectedId: id,
    );
    final payloadMetadata = PortableVaultObject(
      fileName: '$id.meta',
      mediaType: payload.mediaType,
      createdAtMillis: payload.createdAtMillis,
      namespaceId: payload.namespaceId,
      bytes: Uint8List(0),
    );

    if (hasSidecar) {
      try {
        final encoded = await storage.read('$basePath/$id.pvm');
        final metadata = await objectCodec.decode(encoded, encryptionKey);
        _validateMetadataIdentity(
          metadata,
          expectedNamespace: namespaceId,
          expectedId: id,
        );
        return payloadMetadata;
      } on PortableVaultStorageNotFoundException {
        // Fall through to authenticated payload metadata.
      } on PortableVaultUnsupportedProfileException {
        // A damaged listing cache is recoverable from the authenticated payload.
      } on VaultIntegrityException {
        // A damaged listing cache is recoverable from the authenticated payload.
      } on PortableVaultFormatException {
        // A damaged listing cache is recoverable from the authenticated payload.
      }
    }

    return payloadMetadata;
  }

  static const _catalogMediaType = 'application/vnd.private-vault.catalog+json';

  Future<Map<String, _PortableCatalogEntry>> _readCatalog({
    required String namespaceId,
    required SecretKey encryptionKey,
  }) async {
    try {
      _record(VaultOperation.catalogRead);
      final encoded = await storage.read(_catalogPath(namespaceId));
      _record(VaultOperation.catalogDecrypt);
      final object = await objectCodec.decode(encoded, encryptionKey);
      if (object.namespaceId != namespaceId ||
          object.fileName != 'catalog.json' ||
          object.mediaType != _catalogMediaType) {
        throw const PortableVaultFormatException();
      }
      final decoded = jsonDecode(utf8.decode(object.bytes));
      if (decoded is! List) throw const PortableVaultFormatException();
      final entries = <String, _PortableCatalogEntry>{};
      for (final value in decoded) {
        final entry = _PortableCatalogEntry.fromJson(value);
        entries[entry.id] = entry;
      }
      return entries;
    } on PortableVaultStorageNotFoundException {
      return <String, _PortableCatalogEntry>{};
    } on PortableVaultStorageException {
      return <String, _PortableCatalogEntry>{};
    } on PortableVaultUnsupportedProfileException {
      return <String, _PortableCatalogEntry>{};
    } on VaultIntegrityException {
      return <String, _PortableCatalogEntry>{};
    } on PortableVaultFormatException {
      return <String, _PortableCatalogEntry>{};
    } on FormatException {
      return <String, _PortableCatalogEntry>{};
    }
  }

  Future<bool> _writeCatalogBestEffort({
    required String namespaceId,
    required SecretKey encryptionKey,
    required Map<String, _PortableCatalogEntry> entries,
  }) async {
    try {
      final ordered = entries.values.toList()
        ..sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
      final encoded = await objectCodec.encode(
        PortableVaultObject(
          fileName: 'catalog.json',
          mediaType: _catalogMediaType,
          createdAtMillis: DateTime.now().toUtc().millisecondsSinceEpoch,
          namespaceId: namespaceId,
          bytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode(ordered.map((entry) => entry.toJson()).toList()),
            ),
          ),
        ),
        encryptionKey,
      );
      await storage.write(_catalogPath(namespaceId), encoded);
      return true;
    } on Object {
      // The catalog is a reconstructible cache. Payload commit stays authoritative.
      return false;
    }
  }

  Future<void> _upsertCatalogBestEffort({
    required String namespaceId,
    required SecretKey encryptionKey,
    required String id,
    required String mediaType,
    required int createdAtMillis,
  }) async {
    final entries = await _readCatalog(
      namespaceId: namespaceId,
      encryptionKey: encryptionKey,
    );
    PortableVaultStorageEntryMetadata? metadata;
    final targetStorage = storage;
    if (targetStorage is PortableVaultEntryMetadataStorage) {
      try {
        _record(VaultOperation.metadataProviderQuery);
        metadata = await (targetStorage as PortableVaultEntryMetadataStorage)
            .metadata(_objectPath(namespaceId, id));
      } on PortableVaultStorageException {
        // Payload commit remains authoritative; fingerprint can be learned later.
      }
    }
    entries[id] = _PortableCatalogEntry(
      id: id,
      mediaType: mediaType,
      createdAtMillis: createdAtMillis,
      sizeBytes: metadata?.hasSizeFingerprint == true
          ? metadata!.sizeBytes
          : null,
      modifiedAtMillis: metadata?.hasReliableModificationTime == true
          ? metadata!.modifiedAtMillis
          : null,
    );
    await _writeCatalogBestEffort(
      namespaceId: namespaceId,
      encryptionKey: encryptionKey,
      entries: entries,
    );
  }

  Future<void> _invalidateCatalogEntry(
    PortableVaultKeyMaterial material,
    String id,
  ) async {
    _record(VaultOperation.mutationReconciliation);
    final objectPath = _objectPath(material.namespaceId, id);
    _catalogReauthenticationPaths.add(objectPath);
    final invalidated = await _removeFromCatalogBestEffort(
      namespaceId: material.namespaceId,
      encryptionKey: material.encryptionKey,
      id: id,
    );
    if (invalidated) _catalogReauthenticationPaths.remove(objectPath);
  }

  Future<bool> _removeFromCatalogBestEffort({
    required String namespaceId,
    required SecretKey encryptionKey,
    required String id,
  }) async {
    final entries = await _readCatalog(
      namespaceId: namespaceId,
      encryptionKey: encryptionKey,
    );
    if (entries.remove(id) == null) return false;
    final written = await _writeCatalogBestEffort(
      namespaceId: namespaceId,
      encryptionKey: encryptionKey,
      entries: entries,
    );
    if (written) return true;
    try {
      await storage.delete(_catalogPath(namespaceId));
      return true;
    } on PortableVaultStorageException {
      return false;
    }
  }

  Future<void> _requireAccess() async {
    if (!await storage.hasAccess()) {
      throw const PortableVaultRootUnavailableException();
    }
  }

  void _validatePayloadIdentity(
    PortableVaultObject object, {
    required String expectedNamespace,
    required String expectedId,
  }) {
    if (object.namespaceId != expectedNamespace) {
      throw const PortableVaultForeignObjectException();
    }
    if (object.fileName != '$expectedId.bin') {
      throw const PortableVaultFormatException();
    }
  }

  void _validateMetadataIdentity(
    PortableVaultObject object, {
    required String expectedNamespace,
    required String expectedId,
  }) {
    if (object.namespaceId != expectedNamespace) {
      throw const PortableVaultForeignObjectException();
    }
    if (object.fileName != '$expectedId.meta' || object.bytes.isNotEmpty) {
      throw const PortableVaultFormatException();
    }
  }

  String _catalogPath(String namespaceId) => '$namespaceId/catalog.pvc';

  String _objectPath(String namespaceId, String id) =>
      '$namespaceId/objects/$id.pvb';

  String _metadataPath(String namespaceId, String id) =>
      '$namespaceId/objects/$id.pvm';

  String _thumbnailPath(String namespaceId, String id) =>
      '$namespaceId/cache/thumbnails/$id.pvt';

  String _legacyThumbnailPath(String namespaceId, String id) =>
      '$namespaceId/objects/$id.pvt';

  String _newId() {
    final random = Random.secure();
    final suffix = List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$suffix';
  }

  String _mediaTypeFor(VaultItemKind kind) => switch (kind) {
    VaultItemKind.note => 'text/plain',
    VaultItemKind.image => 'image/*',
    VaultItemKind.video => 'video/*',
    VaultItemKind.document => 'application/octet-stream',
    VaultItemKind.unknown => throw StateError('unknown kind'),
  };

  VaultItem _catalogItem(_PortableCatalogEntry entry) => VaultItem(
    id: entry.id,
    kind: _kindFromMediaType(entry.mediaType),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      entry.createdAtMillis,
      isUtc: true,
    ),
  );

  VaultItemKind _kindFromMediaType(String mediaType) {
    if (mediaType == 'text/plain') return VaultItemKind.note;
    if (mediaType.startsWith('image/')) return VaultItemKind.image;
    if (mediaType.startsWith('video/')) return VaultItemKind.video;
    return VaultItemKind.document;
  }
}

class _PortableCatalogEntry {
  const _PortableCatalogEntry({
    required this.id,
    required this.mediaType,
    required this.createdAtMillis,
    this.sizeBytes,
    this.modifiedAtMillis,
  });

  final String id;
  final String mediaType;
  final int createdAtMillis;
  final int? sizeBytes;
  final int? modifiedAtMillis;

  bool matches(PortableVaultStorageEntryMetadata metadata) {
    if (!metadata.hasSizeFingerprint || sizeBytes != metadata.sizeBytes) {
      return false;
    }
    if (metadata.hasReliableModificationTime) {
      return modifiedAtMillis == metadata.modifiedAtMillis;
    }
    // Weak provider metadata is only a freshness hint for listing. Payload
    // authenticity is enforced when bytes are actually consumed.
    return modifiedAtMillis == null;
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'type': mediaType,
    'created': createdAtMillis,
    'size': ?sizeBytes,
    'modified': ?modifiedAtMillis,
  };

  static _PortableCatalogEntry fromJson(Object? value) {
    if (value is! Map) throw const PortableVaultFormatException();
    final id = value['id'];
    final mediaType = value['type'];
    final createdAtMillis = value['created'];
    final sizeBytes = value['size'];
    final modifiedAtMillis = value['modified'];
    if (id is! String ||
        id.isEmpty ||
        mediaType is! String ||
        mediaType.isEmpty ||
        createdAtMillis is! int ||
        createdAtMillis < 0 ||
        (sizeBytes != null && (sizeBytes is! int || sizeBytes < 0)) ||
        (modifiedAtMillis != null &&
            (modifiedAtMillis is! int || modifiedAtMillis <= 0))) {
      throw const PortableVaultFormatException();
    }
    return _PortableCatalogEntry(
      id: id,
      mediaType: mediaType,
      createdAtMillis: createdAtMillis,
      sizeBytes: sizeBytes as int?,
      modifiedAtMillis: modifiedAtMillis as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _PortableCatalogEntry &&
      other.id == id &&
      other.mediaType == mediaType &&
      other.createdAtMillis == createdAtMillis &&
      other.sizeBytes == sizeBytes &&
      other.modifiedAtMillis == modifiedAtMillis;

  @override
  int get hashCode =>
      Object.hash(id, mediaType, createdAtMillis, sizeBytes, modifiedAtMillis);
}

class _PortablePreparedPinSession implements PreparedPinSession {
  _PortablePreparedPinSession(this.material, this.expectedGeneration);

  final PortableVaultKeyMaterial material;
  final int expectedGeneration;
  bool consumed = false;

  @override
  void destroy() {
    if (consumed) return;
    consumed = true;
    material.destroy();
  }
}

class PortableVaultRootUnavailableException implements Exception {
  const PortableVaultRootUnavailableException();
}

class PortableVaultStreamingUnsupportedException implements Exception {
  const PortableVaultStreamingUnsupportedException();
}

class PortableVaultForeignObjectException implements Exception {
  const PortableVaultForeignObjectException();
}
