import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';

class PortableVaultObject {
  const PortableVaultObject({
    required this.fileName,
    required this.mediaType,
    required this.createdAtMillis,
    required this.bytes,
  });

  final String fileName;
  final String mediaType;
  final int createdAtMillis;
  final Uint8List bytes;
}

class PortableVaultObjectCodec {
  PortableVaultObjectCodec({VaultCrypto? crypto})
    : _crypto = crypto ?? VaultCrypto();

  static final Uint8List _magic = Uint8List.fromList(ascii.encode('PV2O'));

  final VaultCrypto _crypto;

  Future<Uint8List> encode(PortableVaultObject object, SecretKey key) async {
    final metadata = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'v': 2,
          'name': object.fileName,
          'type': object.mediaType,
          'created': object.createdAtMillis,
        }),
      ),
    );
    final clear = BytesBuilder(copy: false)
      ..add(_u32(metadata.length))
      ..add(metadata)
      ..add(object.bytes);
    final sealed = await _crypto.encrypt(clear.takeBytes(), key);

    return (BytesBuilder(copy: false)
          ..add(_magic)
          ..add(sealed.nonce)
          ..add(sealed.mac)
          ..add(sealed.cipherText))
        .takeBytes();
  }

  Future<PortableVaultObject> decode(Uint8List encoded, SecretKey key) async {
    const prefixLength = 4 + 12 + 16;
    if (encoded.length < prefixLength + 4 ||
        !_matchesMagic(encoded.sublist(0, 4))) {
      throw const PortableVaultFormatException();
    }

    final clear = await _crypto.decrypt(
      SealedVaultData(
        nonce: Uint8List.fromList(encoded.sublist(4, 16)),
        mac: Uint8List.fromList(encoded.sublist(16, 32)),
        cipherText: Uint8List.fromList(encoded.sublist(32)),
      ),
      key,
    );
    if (clear.length < 4) throw const PortableVaultFormatException();

    final metadataLength = _readU32(clear, 0);
    if (metadataLength <= 0 || 4 + metadataLength > clear.length) {
      throw const PortableVaultFormatException();
    }

    try {
      final raw = jsonDecode(utf8.decode(clear.sublist(4, 4 + metadataLength)));
      if (raw is! Map<String, dynamic> ||
          raw['v'] != 2 ||
          raw['name'] is! String ||
          raw['type'] is! String ||
          raw['created'] is! int) {
        throw const PortableVaultFormatException();
      }
      return PortableVaultObject(
        fileName: raw['name'] as String,
        mediaType: raw['type'] as String,
        createdAtMillis: raw['created'] as int,
        bytes: Uint8List.fromList(clear.sublist(4 + metadataLength)),
      );
    } on FormatException {
      throw const PortableVaultFormatException();
    }
  }

  bool _matchesMagic(List<int> candidate) {
    if (candidate.length != _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (candidate[i] != _magic[i]) return false;
    }
    return true;
  }

  Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  int _readU32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);
}

class PortableVaultFormatException implements Exception {
  const PortableVaultFormatException();
}
