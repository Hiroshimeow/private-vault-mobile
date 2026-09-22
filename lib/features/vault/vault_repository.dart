import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/core/storage/secret_store.dart';

enum VaultItemKind { unknown, note, image, video, document }

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

class VaultScanResult {
  const VaultScanResult({
    required this.items,
    this.corruptCount = 0,
    this.unsupportedCount = 0,
    this.foreignCount = 0,
    this.storageFailureCount = 0,
  });

  final List<VaultItem> items;
  final int corruptCount;
  final int unsupportedCount;
  final int foreignCount;
  final int storageFailureCount;

  int get unreadableCount =>
      corruptCount + unsupportedCount + foreignCount + storageFailureCount;
  bool get hasProblems => unreadableCount > 0;
}

abstract interface class StreamingVaultRepository implements VaultRepository {
  Future<VaultItem> addStream(
    Stream<List<int>> bytes, {
    required VaultItemKind kind,
  });
}

abstract interface class VaultThumbnailRepository implements VaultRepository {
  Future<Uint8List?> readThumbnail(String id);
  Future<void> writeThumbnail(String id, Uint8List bytes);
}

abstract interface class VaultScanAwareRepository implements VaultRepository {
  Future<VaultScanResult> scan();
}

abstract interface class PinSessionVaultRepository implements VaultRepository {
  Future<void> openSession(String pin);
  void clearSession();
  bool get hasOpenSession;
}

class VaultScanException implements Exception {
  const VaultScanException(this.result);
  final VaultScanResult result;
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
    if (kind == VaultItemKind.unknown) {
      throw ArgumentError.value(kind, 'kind', 'unknown cannot be persisted');
    }
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
    await _writeEncrypted(
      File(_path(root, id)),
      Uint8List.fromList(clearEnvelope),
      key,
    );
    await _writeMetadata(root, id, kind, createdAt, key);
    return VaultItem(id: id, kind: kind, createdAt: createdAt);
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    final root = await _ensureRoot();
    final key = await _requiredKey();
    final decoded = await _readDecoded(File(_path(root, id)), key);
    final payload = decoded['payload'];
    if (payload is! String) throw const VaultFormatException();

    final metadata = _metadataFromDecoded(decoded);
    late final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Decode(payload));
    } on FormatException {
      throw const VaultFormatException();
    }

    final metadataFile = File(_metadataPath(root, id));
    if (!await metadataFile.exists()) {
      await _writeMetadata(root, id, metadata.kind, metadata.createdAt, key);
    }
    return bytes;
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
      final id = _idFromPath(file.path);
      final metadataFile = File(_metadataPath(root, id));
      if (!await metadataFile.exists()) {
        items.add(
          VaultItem(
            id: id,
            kind: VaultItemKind.unknown,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );
        continue;
      }

      final decoded = await _readDecoded(metadataFile, key);
      final metadata = _metadataFromDecoded(decoded);
      items.add(
        VaultItem(id: id, kind: metadata.kind, createdAt: metadata.createdAt),
      );
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<void> delete(String id) async {
    final root = await _ensureRoot();
    for (final file in [File(_path(root, id)), File(_metadataPath(root, id))]) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _writeMetadata(
    Directory root,
    String id,
    VaultItemKind kind,
    DateTime createdAt,
    SecretKey key,
  ) async {
    final clear = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'kind': kind.name,
          'createdAt': createdAt.toIso8601String(),
        }),
      ),
    );
    await _writeEncrypted(File(_metadataPath(root, id)), clear, key);
  }

  Future<void> _writeEncrypted(
    File file,
    Uint8List clear,
    SecretKey key,
  ) async {
    final sealed = await _crypto.encrypt(clear, key);
    final diskEnvelope = jsonEncode({
      'v': 1,
      'nonce': base64UrlEncode(sealed.nonce),
      'mac': base64UrlEncode(sealed.mac),
      'cipherText': base64Encode(sealed.cipherText),
    });
    await file.writeAsString(diskEnvelope, flush: true);
  }

  _VaultMetadata _metadataFromDecoded(Map<String, Object?> decoded) {
    final kindName = decoded['kind'];
    final createdAtRaw = decoded['createdAt'];
    if (kindName is! String || createdAtRaw is! String) {
      throw const VaultFormatException();
    }
    final kind = VaultItemKind.values
        .where(
          (value) => value != VaultItemKind.unknown && value.name == kindName,
        )
        .firstOrNull;
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (kind == null || createdAt == null) {
      throw const VaultFormatException();
    }
    return _VaultMetadata(kind, createdAt);
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

  String _metadataPath(Directory root, String id) =>
      '${root.path}${Platform.pathSeparator}$id.meta';

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

class _VaultMetadata {
  const _VaultMetadata(this.kind, this.createdAt);

  final VaultItemKind kind;
  final DateTime createdAt;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}
