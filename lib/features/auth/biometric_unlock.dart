import 'package:local_auth/local_auth.dart';

abstract interface class BiometricUnlock {
  Future<bool> isAvailable();
  Future<bool> authenticate();
  Future<void> cancel();
}

class DeviceBiometricUnlock implements BiometricUnlock {
  DeviceBiometricUnlock({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _authentication.canCheckBiometrics) return false;
      return (await _authentication.getAvailableBiometrics()).isNotEmpty;
    } on LocalAuthException {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _authentication.authenticate(
        localizedReason: 'Unlock protected workspace',
        biometricOnly: true,
        sensitiveTransaction: true,
      );
    } on LocalAuthException {
      return false;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _authentication.stopAuthentication();
    } on LocalAuthException {
      // Nothing remains to cancel when the platform prompt already closed.
    }
  }
}
