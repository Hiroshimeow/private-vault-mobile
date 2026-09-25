import 'dart:convert';
import 'dart:isolate';
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

    final derived = await Isolate.run(() => _derivePortableVaultBytes(pin));
    final keyBytes = derived.$1;
    try {
      return PortableVaultKeyMaterial(
        encryptionKey: SecretKeyData(
          Uint8List.fromList(keyBytes),
          overwriteWhenDestroyed: true,
        ),
        namespaceId: derived.$2,
      );
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }
}

Future<(Uint8List, String)> _derivePortableVaultBytes(String pin) async {
  final algorithm = Argon2id(
    parallelism: PortableVaultKeyDeriver.parallelism,
    memory: PortableVaultKeyDeriver.memoryKiB,
    iterations: PortableVaultKeyDeriver.iterations,
    hashLength: PortableVaultKeyDeriver.hashLength,
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
    try {
      final namespaceHash = await Sha256().hash([
        ...utf8.encode(PortableVaultFormatV2.namespaceDomain),
        ...namespaceSeed,
      ]);
      final namespaceId = namespaceHash.bytes
          .sublist(0, 16)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      return (encryptionBytes, namespaceId);
    } finally {
      namespaceSeed.fillRange(0, namespaceSeed.length, 0);
    }
  } finally {
    root.destroy();
  }
}

class PortableVaultInvalidPin implements Exception {
  const PortableVaultInvalidPin();
}
