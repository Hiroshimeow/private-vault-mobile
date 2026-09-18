import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';

void main() {
  test('encrypt/decrypt round trip and tamper rejection', () async {
    final crypto = VaultCrypto();
    final key = await crypto.newKey();
    final clear = Uint8List.fromList('synthetic secret'.codeUnits);

    final sealed = await crypto.encrypt(clear, key);
    expect(sealed.cipherText, isNot(equals(clear)));
    expect(await crypto.decrypt(sealed, key), clear);

    final tampered = sealed.copyWith(
      cipherText: Uint8List.fromList([
        sealed.cipherText.first ^ 1,
        ...sealed.cipherText.skip(1),
      ]),
    );
    expect(
      () => crypto.decrypt(tampered, key),
      throwsA(isA<VaultIntegrityException>()),
    );
  });

  test('wrong key fails closed', () async {
    final crypto = VaultCrypto();
    final key = await crypto.newKey();
    final otherKey = await crypto.newKey();
    final sealed = await crypto.encrypt(Uint8List.fromList([1, 2, 3]), key);

    expect(
      () => crypto.decrypt(sealed, otherKey),
      throwsA(isA<VaultIntegrityException>()),
    );
  });
}
