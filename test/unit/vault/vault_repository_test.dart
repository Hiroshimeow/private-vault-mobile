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
