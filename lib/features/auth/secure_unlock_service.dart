import 'dart:convert';

import 'package:private_vault_mobile/core/storage/secret_store.dart';
import 'package:private_vault_mobile/features/auth/pin_hasher.dart';

abstract interface class UnlockService {
  Future<bool> isConfigured();
  Future<void> configure(String pin);
  Future<bool> verify(String candidate);
}

abstract interface class PinLengthAwareUnlockService {
  Future<int?> configuredPinLength();
}

class SecureUnlockService
    implements UnlockService, PinLengthAwareUnlockService {
  factory SecureUnlockService({
    required SecretStore store,
    int? testIterations,
  }) => SecureUnlockService._(
    store,
    PinHasher(iterations: testIterations ?? 210000),
  );

  SecureUnlockService._(this._store, this._hasher);

  static const _verifierKey = 'pin_verifier_v1';

  final SecretStore _store;
  final PinHasher _hasher;

  @override
  Future<bool> isConfigured() async => await _store.read(_verifierKey) != null;

  @override
  Future<int?> configuredPinLength() async {
    final encoded = await _store.read(_verifierKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final length = decoded['length'];
      return length is int && length >= 4 && length <= 12 ? length : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> configure(String pin) async {
    if (!_isValidPin(pin)) {
      throw const InvalidPinException();
    }
    final verifier = await _hasher.create(pin);
    await _store.write(
      _verifierKey,
      jsonEncode({
        'salt': verifier.salt,
        'hash': verifier.hash,
        'iterations': verifier.iterations,
        'length': pin.length,
      }),
    );
  }

  @override
  Future<bool> verify(String candidate) async {
    final encoded = await _store.read(_verifierKey);
    if (encoded == null || !_isValidPin(candidate)) return false;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return false;
      final salt = decoded['salt'];
      final hash = decoded['hash'];
      final iterations = decoded['iterations'];
      if (salt is! String || hash is! String || iterations is! int) {
        return false;
      }
      return await _hasher.verify(
        candidate,
        PinVerifier(salt: salt, hash: hash, iterations: iterations),
      );
    } on Object {
      return false;
    }
  }

  bool _isValidPin(String pin) =>
      pin.length >= 4 && pin.length <= 12 && RegExp(r'^\d+$').hasMatch(pin);
}

class InvalidPinException implements Exception {
  const InvalidPinException();
}
