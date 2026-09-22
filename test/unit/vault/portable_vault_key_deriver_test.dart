import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_key_deriver.dart';

void main() {
  const deriver = PortableVaultKeyDeriver();

  test('PIN 0000 matches the byte-stable V2 known-answer vector', () async {
    final material = await deriver.derive('0000');
    final key = await material.encryptionKey.extractBytes();
    final keyHex = key
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    expect(
      keyHex,
      'e98c61d8c24120f797656808294c79371e7347c80de28f60f1954298af40be83',
    );
    expect(material.namespaceId, 'd784d2608b4851dd0826bccaf69d7fa6');
  });

  test('same PIN derives same portable key and namespace', () async {
    final first = await deriver.derive('0000');
    final second = await deriver.derive('0000');
    expect(
      await first.encryptionKey.extractBytes(),
      await second.encryptionKey.extractBytes(),
    );
    expect(first.namespaceId, second.namespaceId);
  });

  test('different PIN selects a different portable vault identity', () async {
    final first = await deriver.derive('0000');
    final second = await deriver.derive('1234');
    expect(
      await first.encryptionKey.extractBytes(),
      isNot(await second.encryptionKey.extractBytes()),
    );
    expect(first.namespaceId, isNot(second.namespaceId));
  });

  test('portable KDF parameters are versioned constants', () {
    expect(PortableVaultKeyDeriver.version, 2);
    expect(PortableVaultKeyDeriver.memoryKiB, 19456);
    expect(PortableVaultKeyDeriver.iterations, 2);
    expect(PortableVaultKeyDeriver.parallelism, 1);
    expect(PortableVaultKeyDeriver.hashLength, 64);
  });

  test('rejects PIN outside the supported numeric contract', () async {
    await expectLater(
      deriver.derive('123'),
      throwsA(isA<PortableVaultInvalidPin>()),
    );
    await expectLater(
      deriver.derive('12ab'),
      throwsA(isA<PortableVaultInvalidPin>()),
    );
  });
}
