import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
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
  late LocalVaultRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media-vault-test-');
    repo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: MemoryVaultKeyStore(),
      crypto: VaultCrypto(),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('import encrypts picked bytes into vault', () async {
    final service = MediaVaultService(
      repository: repo,
      pickImport: () async => PickedVaultData(
        bytes: Uint8List.fromList('picked-secret'.codeUnits),
        kind: VaultItemKind.document,
      ),
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    final item = await service.importFile();

    expect(item, isNotNull);
    expect(
      await repo.readBytes(item!.id),
      Uint8List.fromList('picked-secret'.codeUnits),
    );
    expect(
      (await File('${tempDir.path}${Platform.pathSeparator}${item.id}.vault')
          .readAsString()),
      isNot(contains('picked-secret')),
    );
  });

  test('multi import stores every selected file', () async {
    final service = MediaVaultService(
      repository: repo,
      pickImport: () async => null,
      pickImports: () async => [
        PickedVaultData(
          bytes: Uint8List.fromList([1, 2, 3]),
          kind: VaultItemKind.image,
        ),
        PickedVaultData(
          bytes: Uint8List.fromList([4, 5, 6]),
          kind: VaultItemKind.video,
        ),
      ],
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    final items = await service.importFiles();

    expect(items, hasLength(2));
    expect(await repo.readBytes(items[0].id), Uint8List.fromList([1, 2, 3]));
    expect(await repo.readBytes(items[1].id), Uint8List.fromList([4, 5, 6]));
  });

  test('export reads decrypted bytes only after explicit call', () async {
    final item = await repo.addBytes(
      Uint8List.fromList([9, 8, 7]),
      kind: VaultItemKind.image,
    );
    Uint8List? exported;
    final service = MediaVaultService(
      repository: repo,
      pickImport: () async => null,
      capturePhoto: () async => null,
      saveExport: (name, bytes) async {
        expect(name, 'export.bin');
        exported = bytes;
        return true;
      },
    );

    expect(exported, isNull);
    expect(await service.export(item.id, fileName: 'export.bin'), isTrue);
    expect(exported, Uint8List.fromList([9, 8, 7]));
  });
}
