import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class PinVerifier {
  const PinVerifier({
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  final String salt;
  final String hash;
  final int iterations;
}

class PinHasher {
  PinHasher({this.iterations = 210000});

  final int iterations;

  Future<PinVerifier> create(String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = await _derive(pin, salt, iterations);
    return PinVerifier(
      salt: base64UrlEncode(salt),
      hash: base64UrlEncode(hash),
      iterations: iterations,
    );
  }

  Future<bool> verify(String pin, PinVerifier verifier) async {
    final expected = base64Url.decode(verifier.hash);
    final actual = await _derive(
      pin,
      base64Url.decode(verifier.salt),
      verifier.iterations,
    );
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  }

  Future<List<int>> _derive(String pin, List<int> salt, int count) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: count,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return key.extractBytes();
  }
}
