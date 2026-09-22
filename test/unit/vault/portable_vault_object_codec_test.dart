import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_format.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_key_deriver.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_object_codec.dart';

void main() {
  const deriver = PortableVaultKeyDeriver();
  final codec = PortableVaultObjectCodec();

  test(
    'portable object round trips authenticated metadata and bytes',
    () async {
      final material = await deriver.derive('0000');
      final source = PortableVaultObject(
        fileName: 'photo.jpg',
        mediaType: 'image/jpeg',
        createdAtMillis: 1789990000000,
        namespaceId: material.namespaceId,
        bytes: Uint8List.fromList([0, 1, 2, 3, 255]),
      );

      final encoded = await codec.encode(source, material.encryptionKey);
      final decoded = await codec.decode(encoded, material.encryptionKey);

      expect(decoded.fileName, source.fileName);
      expect(decoded.mediaType, source.mediaType);
      expect(decoded.createdAtMillis, source.createdAtMillis);
      expect(decoded.namespaceId, source.namespaceId);
      expect(decoded.bytes, source.bytes);
      expect(String.fromCharCodes(encoded), isNot(contains('photo.jpg')));
    },
  );

  test('different PIN cannot decrypt a portable object', () async {
    final first = await deriver.derive('0000');
    final second = await deriver.derive('1234');
    final encoded = await codec.encode(
      PortableVaultObject(
        fileName: 'hidden.bin',
        mediaType: 'application/octet-stream',
        createdAtMillis: 1,
        namespaceId: first.namespaceId,
        bytes: Uint8List.fromList([7, 8, 9]),
      ),
      first.encryptionKey,
    );

    await expectLater(
      codec.decode(encoded, second.encryptionKey),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('tampering is rejected by AES-GCM authentication', () async {
    final material = await deriver.derive('0000');
    final encoded = await codec.encode(
      PortableVaultObject(
        fileName: 'video.mp4',
        mediaType: 'video/mp4',
        createdAtMillis: 1,
        namespaceId: material.namespaceId,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      ),
      material.encryptionKey,
    );
    encoded[encoded.length - 1] ^= 1;

    await expectLater(
      codec.decode(encoded, material.encryptionKey),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('profile header mutation is rejected before decrypt', () async {
    final material = await deriver.derive('0000');
    final encoded = await codec.encode(
      PortableVaultObject(
        fileName: 'doc.bin',
        mediaType: 'application/octet-stream',
        createdAtMillis: 1,
        namespaceId: material.namespaceId,
        bytes: Uint8List.fromList([1]),
      ),
      material.encryptionKey,
    );
    encoded[6] ^= 1;

    await expectLater(
      codec.decode(encoded, material.encryptionKey),
      throwsA(isA<PortableVaultUnsupportedProfileException>()),
    );
  });

  test('stream failure completes MAC future with a format error', () async {
    final material = await deriver.derive('0000');
    final payload = Stream<List<int>>.multi((controller) {
      controller.add([1, 2, 3]);
      controller.addError(StateError('synthetic payload failure'));
      controller.close();
    });
    final encoded = codec.encodeStream(
      fileName: 'broken.bin',
      mediaType: 'application/octet-stream',
      createdAtMillis: 1,
      namespaceId: material.namespaceId,
      payload: payload,
      key: material.encryptionKey,
    );

    await expectLater(
      encoded.cipherText.drain<void>(),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      encoded.tag.timeout(const Duration(seconds: 1)),
      throwsA(isA<PortableVaultFormatException>()),
    );
  });
}
