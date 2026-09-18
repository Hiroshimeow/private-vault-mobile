import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/core/storage/secret_store.dart';
import 'package:private_vault_mobile/features/auth/secure_unlock_service.dart';

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('configure persists verifier without plaintext PIN', () async {
    final store = MemorySecretStore();
    final service = SecureUnlockService(store: store, testIterations: 1000);

    await service.configure('482951');

    expect(await service.isConfigured(), isTrue);
    expect(await service.verify('482951'), isTrue);
    expect(await service.verify('111111'), isFalse);
    expect(store.values.values.join(), isNot(contains('482951')));
  });

  test('unconfigured service rejects verification', () async {
    final service = SecureUnlockService(
      store: MemorySecretStore(),
      testIterations: 1000,
    );

    expect(await service.isConfigured(), isFalse);
    expect(await service.verify('482951'), isFalse);
  });
}
