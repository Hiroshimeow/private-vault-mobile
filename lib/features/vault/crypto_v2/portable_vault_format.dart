import 'dart:convert';
import 'dart:typed_data';

class PortableVaultFormatV2 {
  const PortableVaultFormatV2._();

  static const int formatVersion = 2;
  static const int kdfIdArgon2id = 1;
  static const int kdfMemoryKiB = 19456;
  static const int kdfIterations = 2;
  static const int kdfParallelism = 1;
  static const int derivedRootKeySize = 64;
  static const int cipherIdAes256Gcm = 1;
  static const int cipherKeySize = 32;
  static const int nonceSize = 12;
  static const int tagSize = 16;
  static const int namespaceSchemeId = 1;
  static const int keyScheduleVersion = 1;
  static const int headerSize = 22;

  static const String argon2Domain = 'PrivateVaultPortableV2\u0000argon2id';
  static const String namespaceDomain = 'PrivateVaultPortableV2/namespace';

  static final Uint8List magic = Uint8List.fromList(ascii.encode('PV2O'));

  static Uint8List buildHeader() {
    final bytes = Uint8List(headerSize);
    bytes.setRange(0, 4, magic);
    final data = ByteData.sublistView(bytes);
    data.setUint8(4, formatVersion);
    data.setUint8(5, kdfIdArgon2id);
    data.setUint32(6, kdfMemoryKiB, Endian.big);
    data.setUint32(10, kdfIterations, Endian.big);
    data.setUint8(14, kdfParallelism);
    data.setUint8(15, derivedRootKeySize);
    data.setUint8(16, cipherIdAes256Gcm);
    data.setUint8(17, cipherKeySize);
    data.setUint8(18, nonceSize);
    data.setUint8(19, tagSize);
    data.setUint8(20, namespaceSchemeId);
    data.setUint8(21, keyScheduleVersion);
    return bytes;
  }

  static void validateHeader(Uint8List header) {
    if (header.length != headerSize) {
      throw const PortableVaultUnsupportedProfileException();
    }
    for (var i = 0; i < magic.length; i++) {
      if (header[i] != magic[i]) {
        throw const PortableVaultUnsupportedProfileException();
      }
    }
    final data = ByteData.sublistView(header);
    if (data.getUint8(4) != formatVersion ||
        data.getUint8(5) != kdfIdArgon2id ||
        data.getUint32(6, Endian.big) != kdfMemoryKiB ||
        data.getUint32(10, Endian.big) != kdfIterations ||
        data.getUint8(14) != kdfParallelism ||
        data.getUint8(15) != derivedRootKeySize ||
        data.getUint8(16) != cipherIdAes256Gcm ||
        data.getUint8(17) != cipherKeySize ||
        data.getUint8(18) != nonceSize ||
        data.getUint8(19) != tagSize ||
        data.getUint8(20) != namespaceSchemeId ||
        data.getUint8(21) != keyScheduleVersion) {
      throw const PortableVaultUnsupportedProfileException();
    }
  }
}

class PortableVaultUnsupportedProfileException implements Exception {
  const PortableVaultUnsupportedProfileException();
}
