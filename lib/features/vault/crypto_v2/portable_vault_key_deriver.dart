import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_format.dart';

class PortableVaultKeyMaterial {
  const PortableVaultKeyMaterial({
    required this.encryptionKey,
    required this.namespaceId,
  });

  final SecretKey encryptionKey;
  final String namespaceId;

  void destroy() => encryptionKey.destroy();
}

/// Portable Vault Format V2 key schedule.
///
/// Identity is intentionally derived only from the PIN so copied ciphertext can
/// be reopened on another implementation. Short PINs permit offline brute-force;
/// this is a documented product tradeoff, not a high-entropy password scheme.
class PortableVaultKeyDeriver {
  const PortableVaultKeyDeriver();

  static const version = PortableVaultFormatV2.formatVersion;
  static const memoryKiB = PortableVaultFormatV2.kdfMemoryKiB;
  static const iterations = PortableVaultFormatV2.kdfIterations;
  static const parallelism = PortableVaultFormatV2.kdfParallelism;
  static const hashLength = PortableVaultFormatV2.derivedRootKeySize;

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
      nonce: utf8.encode(PortableVaultFormatV2.argon2Domain),
    );
    try {
      final bytes = await root.extractBytes();
      final encryptionBytes = Uint8List.fromList(
        bytes.sublist(0, PortableVaultFormatV2.cipherKeySize),
      );
      final namespaceSeed = Uint8List.fromList(
        bytes.sublist(
          PortableVaultFormatV2.cipherKeySize,
          PortableVaultFormatV2.derivedRootKeySize,
        ),
      );
      final encryptionKey = SecretKeyData(
        encryptionBytes,
        overwriteWhenDestroyed: true,
      );
      try {
        final namespaceHash = await Sha256().hash([
          ...utf8.encode(PortableVaultFormatV2.namespaceDomain),
          ...namespaceSeed,
        ]);
        return PortableVaultKeyMaterial(
          encryptionKey: encryptionKey,
          namespaceId: _hex(namespaceHash.bytes.sublist(0, 16)),
        );
      } on Object {
        encryptionKey.destroy();
        rethrow;
      } finally {
        namespaceSeed.fillRange(0, namespaceSeed.length, 0);
      }
    } finally {
      root.destroy();
    }
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class PortableVaultInvalidPin implements Exception {
  const PortableVaultInvalidPin();
}
