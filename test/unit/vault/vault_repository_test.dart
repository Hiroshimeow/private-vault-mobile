import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class MemoryVaultKeyStore implements VaultKeyStore {
  SecretKey? key;

  @override
  Future<SecretKey> getOrCreate() async {
    return key ??= await AesGcm.with256bits().newSecretKey();
  }

  @override
  Future<SecretKey?> read() async => key;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('private-vault-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('add/read/list/delete persists only encrypted payload', () async {
    final keys = MemoryVaultKeyStore();
    final repo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: keys,
      crypto: VaultCrypto(),
    );
    final clear = Uint8List.fromList('fixture-secret-value'.codeUnits);

    final item = await repo.addBytes(clear, kind: VaultItemKind.note);
    expect(await repo.readBytes(item.id), clear);

    final items = await repo.list();
    expect(items, hasLength(1));
    expect(items.single.id, item.id);
    expect(items.single.kind, VaultItemKind.note);

    final rawFile = File(
      '${tempDir.path}${Platform.pathSeparator}${item.id}.vault',
    );
    final raw = await rawFile.readAsString();
    expect(raw, isNot(contains('fixture-secret-value')));

    await repo.delete(item.id);
    expect(await repo.list(), isEmpty);
  });

  test('missing key fails closed for existing ciphertext', () async {
    final keys = MemoryVaultKeyStore();
    final repo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: keys,
      crypto: VaultCrypto(),
    );
    final item = await repo.addBytes(
      Uint8List.fromList([4, 8, 2, 9, 5, 1]),
      kind: VaultItemKind.document,
    );

    final lockedOutRepo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: MemoryVaultKeyStore(),
      crypto: VaultCrypto(),
    );

    expect(
      () => lockedOutRepo.readBytes(item.id),
      throwsA(isA<MissingVaultKeyException>()),
    );
  });

  test(
    'list reads authenticated metadata without touching payload ciphertext',
    () async {
      final keys = MemoryVaultKeyStore();
      final repo = LocalVaultRepository(
        rootDirectory: () async => tempDir,
        keyStore: keys,
        crypto: VaultCrypto(),
      );
      final item = await repo.addBytes(
        Uint8List(2 * 1024 * 1024),
        kind: VaultItemKind.video,
      );
      final payload = File(
        '${tempDir.path}${Platform.pathSeparator}${item.id}.vault',
      );
      await payload.writeAsString(
        'payload-is-intentionally-unreadable',
        flush: true,
      );

      final listed = await repo.list();

      expect(listed, hasLength(1));
      expect(listed.single.id, item.id);
      expect(listed.single.kind, VaultItemKind.video);
      expect(listed.single.createdAt, item.createdAt);
    },
  );

  test('tampered metadata sidecar fails closed', () async {
    final keys = MemoryVaultKeyStore();
    final repo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: keys,
      crypto: VaultCrypto(),
    );
    final item = await repo.addBytes(
      Uint8List.fromList([1, 2, 3]),
      kind: VaultItemKind.document,
    );
    final metadata = File(
      '${tempDir.path}${Platform.pathSeparator}${item.id}.meta',
    );
    final bytes = await metadata.readAsBytes();
    bytes[bytes.length - 2] ^= 1;
    await metadata.writeAsBytes(bytes, flush: true);

    expect(
      () => repo.list(),
      throwsA(
        anyOf(isA<VaultIntegrityException>(), isA<VaultFormatException>()),
      ),
    );
  });

  test(
    'legacy payload is metadata-only listed and sidecar backfilled on open',
    () async {
      final keys = MemoryVaultKeyStore();
      final repo = LocalVaultRepository(
        rootDirectory: () async => tempDir,
        keyStore: keys,
        crypto: VaultCrypto(),
      );
      final clear = Uint8List.fromList('legacy-secret'.codeUnits);
      final item = await repo.addBytes(clear, kind: VaultItemKind.note);
      final metadata = File(
        '${tempDir.path}${Platform.pathSeparator}${item.id}.meta',
      );
      await metadata.delete();

      final beforeOpen = await repo.list();
      expect(beforeOpen.single.kind, VaultItemKind.unknown);
      expect(await metadata.exists(), isFalse);

      expect(await repo.readBytes(item.id), clear);
      expect(await metadata.exists(), isTrue);
      final afterOpen = await repo.list();
      expect(afterOpen.single.kind, VaultItemKind.note);
      expect(afterOpen.single.createdAt, item.createdAt);
    },
  );

  test('failed legacy open does not backfill metadata', () async {
    final keys = MemoryVaultKeyStore();
    final crypto = VaultCrypto();
    final repo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: keys,
      crypto: crypto,
    );
    final item = await repo.addBytes(
      Uint8List.fromList([1]),
      kind: VaultItemKind.note,
    );
    final metadata = File(
      '${tempDir.path}${Platform.pathSeparator}${item.id}.meta',
    );
    await metadata.delete();

    final key = await keys.getOrCreate();
    final sealed = await crypto.encrypt(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'kind': VaultItemKind.note.name,
            'createdAt': item.createdAt.toIso8601String(),
            'payload': 'not-valid-base64%',
          }),
        ),
      ),
      key,
    );
    final payload = File(
      '${tempDir.path}${Platform.pathSeparator}${item.id}.vault',
    );
    await payload.writeAsString(
      jsonEncode({
        'v': 1,
        'nonce': base64UrlEncode(sealed.nonce),
        'mac': base64UrlEncode(sealed.mac),
        'cipherText': base64Encode(sealed.cipherText),
      }),
      flush: true,
    );

    expect(() => repo.readBytes(item.id), throwsA(isA<VaultFormatException>()));
    expect(await metadata.exists(), isFalse);
  });

  test('delete removes payload and metadata sidecar', () async {
    final keys = MemoryVaultKeyStore();
    final repo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: keys,
      crypto: VaultCrypto(),
    );
    final item = await repo.addBytes(
      Uint8List.fromList([9]),
      kind: VaultItemKind.image,
    );

    await repo.delete(item.id);

    expect(
      File('${tempDir.path}${Platform.pathSeparator}${item.id}.vault')
          .existsSync(),
      isFalse,
    );
    expect(
      File('${tempDir.path}${Platform.pathSeparator}${item.id}.meta')
          .existsSync(),
      isFalse,
    );
  });

  test('corrupt ciphertext fails closed', () async {
    final keys = MemoryVaultKeyStore();
    final repo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: keys,
      crypto: VaultCrypto(),
    );
    final item = await repo.addBytes(
      Uint8List.fromList([1, 2, 3, 4]),
      kind: VaultItemKind.image,
    );

    final rawFile = File(
      '${tempDir.path}${Platform.pathSeparator}${item.id}.vault',
    );
    final bytes = await rawFile.readAsBytes();
    bytes[bytes.length - 2] ^= 1;
    await rawFile.writeAsBytes(bytes, flush: true);

    expect(
      () => repo.readBytes(item.id),
      throwsA(
        anyOf(isA<VaultIntegrityException>(), isA<VaultFormatException>()),
      ),
    );
  });
}
