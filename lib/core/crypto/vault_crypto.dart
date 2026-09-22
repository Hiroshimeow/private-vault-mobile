import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class VaultIntegrityException implements Exception {
  const VaultIntegrityException();

  @override
  String toString() => 'VaultIntegrityException';
}

class SealedVaultData {
  const SealedVaultData({
    required this.cipherText,
    required this.nonce,
    required this.mac,
  });

  final Uint8List cipherText;
  final Uint8List nonce;
  final Uint8List mac;

  SealedVaultData copyWith({
    Uint8List? cipherText,
    Uint8List? nonce,
    Uint8List? mac,
  }) => SealedVaultData(
    cipherText: cipherText ?? this.cipherText,
    nonce: nonce ?? this.nonce,
    mac: mac ?? this.mac,
  );
}

class VaultCrypto {
  VaultCrypto({AesGcm? algorithm})
    : _algorithm = algorithm ?? AesGcm.with256bits();

  final AesGcm _algorithm;

  Future<SecretKey> newKey() => _algorithm.newSecretKey();

  Future<SealedVaultData> encrypt(
    Uint8List clearText,
    SecretKey key, {
    List<int> aad = const <int>[],
  }) async {
    final box = await _algorithm.encrypt(clearText, secretKey: key, aad: aad);
    return SealedVaultData(
      cipherText: Uint8List.fromList(box.cipherText),
      nonce: Uint8List.fromList(box.nonce),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> decrypt(
    SealedVaultData sealed,
    SecretKey key, {
    List<int> aad = const <int>[],
  }) async {
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(sealed.cipherText, nonce: sealed.nonce, mac: Mac(sealed.mac)),
        secretKey: key,
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const VaultIntegrityException();
    }
  }
}
