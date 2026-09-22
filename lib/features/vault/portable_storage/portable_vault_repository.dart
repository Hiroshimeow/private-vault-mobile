import 'dart:math';
import 'dart:typed_data';

import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_format.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_object_codec.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_session.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_storage.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class PortableVaultRepository
    implements VaultScanAwareRepository, PinSessionVaultRepository {
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
    await storage.write(_objectPath(material.namespaceId, id), encoded);
    return VaultItem(id: id, kind: kind, createdAt: createdAt);
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    await _requireAccess();
    final material = session.requireMaterial();
    final encoded = await storage.read(_objectPath(material.namespaceId, id));
    final object = await objectCodec.decode(encoded, material.encryptionKey);
    _validateObjectIdentity(
      object,
      expectedNamespace: material.namespaceId,
      expectedId: id,
    );
    return object.bytes;
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

    final items = <VaultItem>[];
    var corruptCount = 0;
    var unsupportedCount = 0;
    var foreignCount = 0;
    var storageFailureCount = 0;

    for (final name in names.where((value) => value.endsWith('.pvb'))) {
      final id = name.substring(0, name.length - '.pvb'.length);
      try {
        final encoded = await storage.read('$basePath/$name');
        final object = await objectCodec.decode(
          encoded,
          material.encryptionKey,
        );
        if (object.namespaceId != material.namespaceId) {
          foreignCount += 1;
          continue;
        }
        if (object.fileName != '$id.bin') {
          corruptCount += 1;
          continue;
        }
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
    await storage.delete(_objectPath(material.namespaceId, id));
  }

  Future<void> _requireAccess() async {
    if (!await storage.hasAccess()) {
      throw const PortableVaultRootUnavailableException();
    }
  }

  void _validateObjectIdentity(
    PortableVaultObject object, {
    required String expectedNamespace,
    required String expectedId,
  }) {
    if (object.namespaceId != expectedNamespace ||
        object.fileName != '$expectedId.bin') {
      throw const PortableVaultFormatException();
    }
  }

  String _objectPath(String namespaceId, String id) =>
      '$namespaceId/objects/$id.pvb';

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
