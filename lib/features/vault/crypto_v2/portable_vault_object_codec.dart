import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_format.dart';

class PortableVaultObject {
  const PortableVaultObject({
    required this.fileName,
    required this.mediaType,
    required this.createdAtMillis,
    required this.namespaceId,
    required this.bytes,
  });

  final String fileName;
  final String mediaType;
  final int createdAtMillis;
  final String namespaceId;
  final Uint8List bytes;
}

class PortableVaultEncryptedStream {
  const PortableVaultEncryptedStream({
    required this.prefix,
    required this.tagOffset,
    required this.cipherText,
    required this.tag,
  });

  final Uint8List prefix;
  final int tagOffset;
  final Stream<List<int>> cipherText;
  final Future<Uint8List> tag;
}

class PortableVaultObjectCodec {
  PortableVaultObjectCodec({VaultCrypto? crypto})
    : _crypto = crypto ?? VaultCrypto();

  final VaultCrypto _crypto;

  Future<Uint8List> encode(PortableVaultObject object, SecretKey key) async {
    final metadata = _metadataBytes(
      fileName: object.fileName,
      mediaType: object.mediaType,
      createdAtMillis: object.createdAtMillis,
      namespaceId: object.namespaceId,
    );
    final clear = BytesBuilder(copy: false)
      ..add(_u32(metadata.length))
      ..add(metadata)
      ..add(object.bytes);
    final header = PortableVaultFormatV2.buildHeader();
    final sealed = await _crypto.encrypt(clear.takeBytes(), key, aad: header);

    if (sealed.nonce.length != PortableVaultFormatV2.nonceSize ||
        sealed.mac.length != PortableVaultFormatV2.tagSize) {
      throw const PortableVaultFormatException();
    }

    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(sealed.nonce)
          ..add(sealed.mac)
          ..add(sealed.cipherText))
        .takeBytes();
  }

  PortableVaultEncryptedStream encodeStream({
    required String fileName,
    required String mediaType,
    required int createdAtMillis,
    required String namespaceId,
    required Stream<List<int>> payload,
    required SecretKey key,
  }) {
    final metadata = _metadataBytes(
      fileName: fileName,
      mediaType: mediaType,
      createdAtMillis: createdAtMillis,
      namespaceId: namespaceId,
    );
    final header = PortableVaultFormatV2.buildHeader();
    final algorithm = AesGcm.with256bits();
    final nonce = Uint8List.fromList(algorithm.newNonce());
    if (nonce.length != PortableVaultFormatV2.nonceSize) {
      throw const PortableVaultFormatException();
    }

    final tagCompleter = Completer<Uint8List>();
    final rawCipherText = algorithm.encryptStream(
      _clearStream(metadata, payload),
      secretKey: key,
      nonce: nonce,
      aad: header,
      onMac: (mac) {
        if (tagCompleter.isCompleted) return;
        final bytes = Uint8List.fromList(mac.bytes);
        if (bytes.length != PortableVaultFormatV2.tagSize) {
          tagCompleter.completeError(const PortableVaultFormatException());
          return;
        }
        tagCompleter.complete(bytes);
      },
    );
    final cipherText = _guardMacCompletion(rawCipherText, tagCompleter);

    final tagOffset =
        PortableVaultFormatV2.headerSize + PortableVaultFormatV2.nonceSize;
    final prefix =
        (BytesBuilder(copy: false)
              ..add(header)
              ..add(nonce)
              ..add(Uint8List(PortableVaultFormatV2.tagSize)))
            .takeBytes();

    return PortableVaultEncryptedStream(
      prefix: prefix,
      tagOffset: tagOffset,
      cipherText: cipherText,
      tag: tagCompleter.future,
    );
  }

  Future<PortableVaultObject> decode(Uint8List encoded, SecretKey key) async {
    final prefixLength =
        PortableVaultFormatV2.headerSize +
        PortableVaultFormatV2.nonceSize +
        PortableVaultFormatV2.tagSize;
    if (encoded.length < prefixLength + 4) {
      throw const PortableVaultFormatException();
    }

    final header = Uint8List.fromList(
      encoded.sublist(0, PortableVaultFormatV2.headerSize),
    );
    PortableVaultFormatV2.validateHeader(header);

    final nonceStart = PortableVaultFormatV2.headerSize;
    final tagStart = nonceStart + PortableVaultFormatV2.nonceSize;
    final cipherStart = tagStart + PortableVaultFormatV2.tagSize;
    final clear = await _crypto.decrypt(
      SealedVaultData(
        nonce: Uint8List.fromList(encoded.sublist(nonceStart, tagStart)),
        mac: Uint8List.fromList(encoded.sublist(tagStart, cipherStart)),
        cipherText: Uint8List.fromList(encoded.sublist(cipherStart)),
      ),
      key,
      aad: header,
    );
    if (clear.length < 4) throw const PortableVaultFormatException();

    final metadataLength = _readU32(clear, 0);
    if (metadataLength <= 0 || 4 + metadataLength > clear.length) {
      throw const PortableVaultFormatException();
    }

    try {
      final raw = jsonDecode(utf8.decode(clear.sublist(4, 4 + metadataLength)));
      if (raw is! Map<String, dynamic> ||
          raw['v'] != PortableVaultFormatV2.formatVersion ||
          raw['name'] is! String ||
          raw['type'] is! String ||
          raw['created'] is! int ||
          raw['namespace'] is! String) {
        throw const PortableVaultFormatException();
      }
      return PortableVaultObject(
        fileName: raw['name'] as String,
        mediaType: raw['type'] as String,
        createdAtMillis: raw['created'] as int,
        namespaceId: raw['namespace'] as String,
        bytes: Uint8List.fromList(clear.sublist(4 + metadataLength)),
      );
    } on FormatException {
      throw const PortableVaultFormatException();
    }
  }

  Stream<List<int>> _guardMacCompletion(
    Stream<List<int>> source,
    Completer<Uint8List> tagCompleter,
  ) async* {
    await for (final chunk in source) {
      yield chunk;
    }
    if (!tagCompleter.isCompleted) {
      tagCompleter.completeError(const PortableVaultFormatException());
    }
  }

  Stream<List<int>> _clearStream(
    Uint8List metadata,
    Stream<List<int>> payload,
  ) async* {
    yield _u32(metadata.length);
    yield metadata;
    await for (final chunk in payload) {
      if (chunk.isNotEmpty) yield chunk;
    }
  }

  Uint8List _metadataBytes({
    required String fileName,
    required String mediaType,
    required int createdAtMillis,
    required String namespaceId,
  }) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'v': PortableVaultFormatV2.formatVersion,
          'name': fileName,
          'type': mediaType,
          'created': createdAtMillis,
          'namespace': namespaceId,
        }),
      ),
    );
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
