import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class PortableVaultKeyMaterial {
  const PortableVaultKeyMaterial({
    required this.encryptionKey,
    required this.namespaceId,
  });

  final SecretKey encryptionKey;
  final String namespaceId;
}

/// Portable Vault Format V2 key schedule.
///
/// This intentionally derives identity only from the PIN so the same PIN can
/// reopen copied ciphertext on another device. A short PIN therefore permits
/// offline brute-force; callers must not present this as high-entropy storage.
class PortableVaultKeyDeriver {
  const PortableVaultKeyDeriver();

  static const version = 2;
  static const memoryKiB = 19456;
  static const iterations = 2;
  static const parallelism = 1;
  static const hashLength = 64;
  static const _domain = 'PrivateVaultPortableV2\u0000argon2id';

  Future<PortableVaultKeyMaterial> derive(String pin) async {
    if (pin.length < 4 || pin.length > 12 || !RegExp(r'^\d+$').hasMatch(pin)) {
      throw const PortableVaultInvalidPin();
    }

    final algorithm = Argon2id(
      parallelism: parallelism,
      memory: memoryKiB,
      iterations: iterations,
      hashLength: hashLength,
    );
    final root = await algorithm.deriveKeyFromPassword(
      password: pin,
      nonce: utf8.encode(_domain),
    );
    final bytes = await root.extractBytes();

    final encryptionBytes = Uint8List.fromList(bytes.sublist(0, 32));
    final namespaceSeed = bytes.sublist(32, 64);
    final namespaceHash = await Sha256().hash([
      ...utf8.encode('PrivateVaultPortableV2/namespace'),
      ...namespaceSeed,
    ]);

    return PortableVaultKeyMaterial(
      encryptionKey: SecretKey(encryptionBytes),
      namespaceId: _hex(namespaceHash.bytes.sublist(0, 16)),
    );
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class PortableVaultInvalidPin implements Exception {
  const PortableVaultInvalidPin();
}
