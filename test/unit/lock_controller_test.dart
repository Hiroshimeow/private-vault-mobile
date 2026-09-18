import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';

void main() {
  test('starts locked and panic always returns to locked state', () {
    final lock = LockController();
    expect(lock.isLocked, isTrue);

    lock.unlock();
    expect(lock.isLocked, isFalse);

    lock.panic();
    expect(lock.isLocked, isTrue);
  });

  test('background locks when backgroundLock is enabled', () {
    final lock = LockController(backgroundLock: true)..unlock();
    lock.onBackground();
    expect(lock.isLocked, isTrue);
  });
}
