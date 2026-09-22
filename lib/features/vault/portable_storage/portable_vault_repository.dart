import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_format.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_object_codec.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_session.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_storage.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class PortableVaultRepository
    implements
        VaultScanAwareRepository,
        PinSessionVaultRepository,
        StreamingVaultRepository,
        VaultThumbnailRepository {
  PortableVaultRepository({
    required this.storage,
    required this.session,
    PortableVaultObjectCodec? objectCodec,
  }) : objectCodec = objectCodec ?? PortableVaultObjectCodec();

  final PortableVaultStorage storage;
  final PortableVaultSession session;
  final PortableVaultObjectCodec objectCodec;

  @override
  bool get hasOpenSession => session.isOpen;

  @override
  Future<void> openSession(String pin) => session.open(pin);

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
    final payloadPath = _objectPath(material.namespaceId, id);
    await storage.write(payloadPath, encoded);
    try {
      await _writeMetadata(
        namespaceId: material.namespaceId,
        encryptionKey: material.encryptionKey,
        id: id,
        mediaType: _mediaTypeFor(kind),
        createdAt: createdAt,
      );
    } on Object {
      try {
        await storage.delete(payloadPath);
      } on Object {
        // A later scan will surface any orphan payload.
      }
      rethrow;
    }
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
    final writer = await targetStorage.beginWrite(
      _objectPath(material.namespaceId, id),
    );
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

    final payloadPath = _objectPath(material.namespaceId, id);
    try {
      await _writeMetadata(
        namespaceId: material.namespaceId,
        encryptionKey: material.encryptionKey,
        id: id,
        mediaType: _mediaTypeFor(kind),
        createdAt: createdAt,
      );
    } on Object {
      try {
        await storage.delete(payloadPath);
      } on Object {
        // A later scan will surface any orphan payload.
      }
      rethrow;
    }
    return VaultItem(id: id, kind: kind, createdAt: createdAt);
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    await _requireAccess();
    final material = session.requireMaterial();
    final encoded = await storage.read(_objectPath(material.namespaceId, id));
    final object = await objectCodec.decode(encoded, material.encryptionKey);
    _validatePayloadIdentity(
      object,
      expectedNamespace: material.namespaceId,
      expectedId: id,
    );
    return object.bytes;
  }

  @override
  Future<Uint8List?> readThumbnail(String id) async {
    await _requireAccess();
    final material = session.requireMaterial();
    try {
      final encoded = await storage.read(
        _thumbnailPath(material.namespaceId, id),
      );
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
      return null;
    } on PortableVaultUnsupportedProfileException {
      await _deleteThumbnailBestEffort(material.namespaceId, id);
      return null;
    } on VaultIntegrityException {
      await _deleteThumbnailBestEffort(material.namespaceId, id);
      return null;
    } on PortableVaultFormatException {
      await _deleteThumbnailBestEffort(material.namespaceId, id);
      return null;
    }
  }

  @override
  Future<void> writeThumbnail(String id, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    await _requireAccess();
    final material = session.requireMaterial();
    final metadataEncoded = await storage.read(
      _metadataPath(material.namespaceId, id),
    );
    final metadata = await objectCodec.decode(
      metadataEncoded,
      material.encryptionKey,
    );
    _validateMetadataIdentity(
      metadata,
      expectedNamespace: material.namespaceId,
      expectedId: id,
    );
    final encoded = await objectCodec.encode(
      PortableVaultObject(
        fileName: '$id.thumb',
        mediaType: 'image/jpeg',
        createdAtMillis: metadata.createdAtMillis,
        namespaceId: material.namespaceId,
        bytes: bytes,
      ),
      material.encryptionKey,
    );
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
    try {
      names = await storage.list(basePath);
    } on PortableVaultStorageException {
      return const VaultScanResult(items: [], storageFailureCount: 1);
    }

    final payloadIds = names
        .where((name) => name.endsWith('.pvb'))
        .map((name) => name.substring(0, name.length - '.pvb'.length))
        .toSet();
    final metadataIds = names
        .where((name) => name.endsWith('.pvm'))
        .map((name) => name.substring(0, name.length - '.pvm'.length))
        .toSet();

    final items = <VaultItem>[];
    var corruptCount = metadataIds.difference(payloadIds).length;
    var unsupportedCount = 0;
    var foreignCount = 0;
    var storageFailureCount = 0;

    for (final id in payloadIds) {
      try {
        final object = await _loadListingMetadata(
          namespaceId: material.namespaceId,
          encryptionKey: material.encryptionKey,
          basePath: basePath,
          id: id,
          hasSidecar: metadataIds.contains(id),
        );
        items.add(
          VaultItem(
            id: id,
            kind: _kindFromMediaType(object.mediaType),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              object.createdAtMillis,
              isUtc: true,
            ),
          ),
        );
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

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return VaultScanResult(
      items: List.unmodifiable(items),
      corruptCount: corruptCount,
      unsupportedCount: unsupportedCount,
      foreignCount: foreignCount,
      storageFailureCount: storageFailureCount,
    );
  }

  @override
  Future<void> delete(String id) async {
    await _requireAccess();
    final material = session.requireMaterial();
    await storage.delete(_thumbnailPath(material.namespaceId, id));
    await storage.delete(_metadataPath(material.namespaceId, id));
    await storage.delete(_objectPath(material.namespaceId, id));
  }

  Future<PortableVaultObject> _loadListingMetadata({
    required String namespaceId,
    required SecretKey encryptionKey,
    required String basePath,
    required String id,
    required bool hasSidecar,
  }) async {
    if (hasSidecar) {
      try {
        final encoded = await storage.read('$basePath/$id.pvm');
        final metadata = await objectCodec.decode(encoded, encryptionKey);
        _validateMetadataIdentity(
          metadata,
          expectedNamespace: namespaceId,
          expectedId: id,
        );
        return metadata;
      } on PortableVaultStorageNotFoundException {
        // Fall through to payload recovery.
      } on PortableVaultUnsupportedProfileException {
        // A damaged listing cache is recoverable from the authenticated payload.
      } on VaultIntegrityException {
        // A damaged listing cache is recoverable from the authenticated payload.
      } on PortableVaultFormatException {
        // A damaged listing cache is recoverable from the authenticated payload.
      }
    }

    final encoded = await storage.read('$basePath/$id.pvb');
    final payload = await objectCodec.decode(encoded, encryptionKey);
    _validatePayloadIdentity(
      payload,
      expectedNamespace: namespaceId,
      expectedId: id,
    );
    try {
      await _writeMetadata(
        namespaceId: namespaceId,
        encryptionKey: encryptionKey,
        id: id,
        mediaType: payload.mediaType,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          payload.createdAtMillis,
          isUtc: true,
        ),
      );
    } on Object {
      // Listing metadata is a cache. A readable payload remains authoritative.
    }
    return PortableVaultObject(
      fileName: '$id.meta',
      mediaType: payload.mediaType,
      createdAtMillis: payload.createdAtMillis,
      namespaceId: payload.namespaceId,
      bytes: Uint8List(0),
    );
  }

  Future<void> _writeMetadata({
    required String namespaceId,
    required SecretKey encryptionKey,
    required String id,
    required String mediaType,
    required DateTime createdAt,
  }) async {
    final encoded = await objectCodec.encode(
      PortableVaultObject(
        fileName: '$id.meta',
        mediaType: mediaType,
        createdAtMillis: createdAt.millisecondsSinceEpoch,
        namespaceId: namespaceId,
        bytes: Uint8List(0),
      ),
      encryptionKey,
    );
    await storage.write(_metadataPath(namespaceId, id), encoded);
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

  String _objectPath(String namespaceId, String id) =>
      '$namespaceId/objects/$id.pvb';

  String _metadataPath(String namespaceId, String id) =>
      '$namespaceId/objects/$id.pvm';

  String _thumbnailPath(String namespaceId, String id) =>
      '$namespaceId/objects/$id.pvt';

  Future<void> _deleteThumbnailBestEffort(String namespaceId, String id) async {
    try {
      await storage.delete(_thumbnailPath(namespaceId, id));
    } on Object {
      // Thumbnail cache is reconstructible; preserve the primary read result.
    }
  }

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

  VaultItemKind _kindFromMediaType(String mediaType) {
    if (mediaType == 'text/plain') return VaultItemKind.note;
    if (mediaType.startsWith('image/')) return VaultItemKind.image;
    if (mediaType.startsWith('video/')) return VaultItemKind.video;
    return VaultItemKind.document;
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
