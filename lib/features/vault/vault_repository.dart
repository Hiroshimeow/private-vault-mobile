import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/core/storage/secret_store.dart';

enum VaultItemKind { note, image, video, document }

class VaultItem {
  const VaultItem({
    required this.id,
    required this.kind,
    required this.createdAt,
  });

  final String id;
  final VaultItemKind kind;
  final DateTime createdAt;
}

abstract interface class VaultKeyStore {
  Future<SecretKey> getOrCreate();
  Future<SecretKey?> read();
}

class SecureVaultKeyStore implements VaultKeyStore {
  SecureVaultKeyStore(this._store);

  static const _storageKey = 'vault_master_key_v1';
  final SecretStore _store;

  @override
  Future<SecretKey> getOrCreate() async {
    final existing = await read();
    if (existing != null) return existing;

    final generated = await AesGcm.with256bits().newSecretKey();
    final bytes = await generated.extractBytes();
    await _store.write(_storageKey, base64UrlEncode(bytes));
    return generated;
  }

  @override
  Future<SecretKey?> read() async {
    final encoded = await _store.read(_storageKey);
    if (encoded == null) return null;
    try {
      return SecretKey(base64Url.decode(encoded));
    } on FormatException {
      throw const MissingVaultKeyException();
    }
  }
}

class MissingVaultKeyException implements Exception {
  const MissingVaultKeyException();
}

class VaultFormatException implements Exception {
  const VaultFormatException();
}

abstract interface class VaultRepository {
  Future<VaultItem> addBytes(Uint8List bytes, {required VaultItemKind kind});
  Future<Uint8List> readBytes(String id);
  Future<List<VaultItem>> list();
  Future<void> delete(String id);
}

typedef VaultRootDirectory = Future<Directory> Function();

class LocalVaultRepository implements VaultRepository {
  factory LocalVaultRepository({
    required VaultRootDirectory rootDirectory,
    required VaultKeyStore keyStore,
    required VaultCrypto crypto,
  }) => LocalVaultRepository._(rootDirectory, keyStore, crypto);

  LocalVaultRepository._(this._rootDirectory, this._keyStore, this._crypto);

  final VaultRootDirectory _rootDirectory;
  final VaultKeyStore _keyStore;
  final VaultCrypto _crypto;

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    final root = await _ensureRoot();
    final key = await _keyStore.getOrCreate();
    final createdAt = DateTime.now().toUtc();
    final id = _newId();
    final clearEnvelope = utf8.encode(
      jsonEncode({
        'kind': kind.name,
        'createdAt': createdAt.toIso8601String(),
        'payload': base64Encode(bytes),
      }),
    );
    final sealed = await _crypto.encrypt(
      Uint8List.fromList(clearEnvelope),
      key,
    );
    final diskEnvelope = jsonEncode({
      'v': 1,
      'nonce': base64UrlEncode(sealed.nonce),
      'mac': base64UrlEncode(sealed.mac),
      'cipherText': base64Encode(sealed.cipherText),
    });
    await File(_path(root, id)).writeAsString(diskEnvelope, flush: true);
    return VaultItem(id: id, kind: kind, createdAt: createdAt);
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    final root = await _ensureRoot();
    final key = await _requiredKey();
    final decoded = await _readDecoded(File(_path(root, id)), key);
    final payload = decoded['payload'];
    if (payload is! String) throw const VaultFormatException();
    try {
      return Uint8List.fromList(base64Decode(payload));
    } on FormatException {
      throw const VaultFormatException();
    }
  }

  @override
  Future<List<VaultItem>> list() async {
    final root = await _ensureRoot();
    final files = await root
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.vault'))
        .cast<File>()
        .toList();
    if (files.isEmpty) return const [];

    final key = await _requiredKey();
    final items = <VaultItem>[];
    for (final file in files) {
      final decoded = await _readDecoded(file, key);
      final kindName = decoded['kind'];
      final createdAtRaw = decoded['createdAt'];
      if (kindName is! String || createdAtRaw is! String) {
        throw const VaultFormatException();
      }
      final kind = VaultItemKind.values
          .where((value) => value.name == kindName)
          .firstOrNull;
      final createdAt = DateTime.tryParse(createdAtRaw);
      if (kind == null || createdAt == null) {
        throw const VaultFormatException();
      }
      items.add(
        VaultItem(id: _idFromPath(file.path), kind: kind, createdAt: createdAt),
      );
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<void> delete(String id) async {
    final root = await _ensureRoot();
    final file = File(_path(root, id));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Map<String, Object?>> _readDecoded(File file, SecretKey key) async {
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic> || raw['v'] != 1) {
        throw const VaultFormatException();
      }
      final sealed = SealedVaultData(
        cipherText: Uint8List.fromList(
          base64Decode(raw['cipherText'] as String),
        ),
        nonce: Uint8List.fromList(base64Url.decode(raw['nonce'] as String)),
        mac: Uint8List.fromList(base64Url.decode(raw['mac'] as String)),
      );
      final clear = await _crypto.decrypt(sealed, key);
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, dynamic>) {
        throw const VaultFormatException();
      }
      return decoded.cast<String, Object?>();
    } on VaultIntegrityException {
      rethrow;
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException();
    }
  }

  Future<SecretKey> _requiredKey() async {
    final key = await _keyStore.read();
    if (key == null) throw const MissingVaultKeyException();
    return key;
  }

  Future<Directory> _ensureRoot() async {
    final root = await _rootDirectory();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  String _path(Directory root, String id) =>
      '${root.path}${Platform.pathSeparator}$id.vault';

  String _idFromPath(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.substring(0, name.length - '.vault'.length);
  }

  String _newId() {
    final random = Random.secure();
    final suffix = List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$suffix';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}
