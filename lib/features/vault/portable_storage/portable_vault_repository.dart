import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_key_deriver.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_object_codec.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

typedef PortableVaultRootDirectory = Future<Directory> Function();
typedef PortableVaultPinProvider = Future<String> Function();

class PortableVaultRepository implements VaultRepository {
  PortableVaultRepository({
    required this.rootDirectory,
    required this.pinProvider,
    this.keyDeriver = const PortableVaultKeyDeriver(),
    PortableVaultObjectCodec? objectCodec,
  }) : objectCodec = objectCodec ?? PortableVaultObjectCodec();

  final PortableVaultRootDirectory rootDirectory;
  final PortableVaultPinProvider pinProvider;
  final PortableVaultKeyDeriver keyDeriver;
  final PortableVaultObjectCodec objectCodec;

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    if (kind == VaultItemKind.unknown) {
      throw ArgumentError.value(kind, 'kind', 'unknown cannot be persisted');
    }
    final context = await _context();
    final createdAt = DateTime.now().toUtc();
    final id = _newId();
    final encoded = await objectCodec.encode(
      PortableVaultObject(
        fileName: '$id.bin',
        mediaType: _mediaTypeFor(kind),
        createdAtMillis: createdAt.millisecondsSinceEpoch,
        bytes: bytes,
      ),
      context.material.encryptionKey,
    );
    await File(_objectPath(context.objectsDirectory, id))
        .writeAsBytes(encoded, flush: true);
    return VaultItem(id: id, kind: kind, createdAt: createdAt);
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    final context = await _context();
    final file = File(_objectPath(context.objectsDirectory, id));
    if (!await file.exists()) throw const VaultFormatException();
    final object = await objectCodec.decode(
      await file.readAsBytes(),
      context.material.encryptionKey,
    );
    return object.bytes;
  }

  @override
  Future<List<VaultItem>> list() async {
    final context = await _context();
    final files = await context.objectsDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.pvb'))
        .cast<File>()
        .toList();
    final items = <VaultItem>[];
    for (final file in files) {
      try {
        final object = await objectCodec.decode(
          await file.readAsBytes(),
          context.material.encryptionKey,
        );
        items.add(
          VaultItem(
            id: _idFromPath(file.path),
            kind: _kindFromMediaType(object.mediaType),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              object.createdAtMillis,
              isUtc: true,
            ),
          ),
        );
      } on Object {
        // Ignore foreign/corrupt objects in the selected namespace.
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<void> delete(String id) async {
    final context = await _context();
    final file = File(_objectPath(context.objectsDirectory, id));
    if (await file.exists()) await file.delete();
  }

  Future<_PortableVaultContext> _context() async {
    final root = await rootDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    final material = await keyDeriver.derive(await pinProvider());
    final namespace = Directory(
      '${root.path}${Platform.pathSeparator}${material.namespaceId}',
    );
    final objects = Directory(
      '${namespace.path}${Platform.pathSeparator}objects',
    );
    if (!await objects.exists()) await objects.create(recursive: true);
    return _PortableVaultContext(material: material, objectsDirectory: objects);
  }

  String _objectPath(Directory objects, String id) =>
      '${objects.path}${Platform.pathSeparator}$id.pvb';

  String _idFromPath(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.substring(0, name.length - '.pvb'.length);
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

class _PortableVaultContext {
  const _PortableVaultContext({
    required this.material,
    required this.objectsDirectory,
  });
  final PortableVaultKeyMaterial material;
  final Directory objectsDirectory;
}
