import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/browser/browser_download_service.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class MemoryVaultKeyStore implements VaultKeyStore {
  SecretKey? key;

  @override
  Future<SecretKey> getOrCreate() async =>
      key ??= await AesGcm.with256bits().newSecretKey();

  @override
  Future<SecretKey?> read() async => key;
}

void main() {
  late Directory tempDir;
  late LocalVaultRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('browser-download-test-');
    repository = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: MemoryVaultKeyStore(),
      crypto: VaultCrypto(),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('HTTPS download is encrypted directly into vault', () async {
    final service = BrowserDownloadService(
      repository: repository,
      fetch: (uri) async {
        expect(uri, Uri.parse('https://example.test/file.pdf'));
        return Uint8List.fromList('downloaded-fixture'.codeUnits);
      },
    );

    final item = await service.downloadToVault(
      Uri.parse('https://example.test/file.pdf'),
    );

    expect(item.kind, VaultItemKind.document);
    expect(
      await repository.readBytes(item.id),
      Uint8List.fromList('downloaded-fixture'.codeUnits),
    );
  });

  test('non-HTTPS download is rejected', () async {
    final service = BrowserDownloadService(
      repository: repository,
      fetch: (_) async => Uint8List(0),
    );

    expect(
      () => service.downloadToVault(Uri.parse('http://example.test/a.bin')),
      throwsA(isA<BrowserDownloadException>()),
    );
  });
}
