import 'package:fake_async/fake_async.dart';
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

  test('delayed background lock waits and foreground cancels timer', () {
    fakeAsync((async) {
      final lock = LockController(backgroundLock: true)..unlock();

      lock.onBackground(delay: const Duration(seconds: 30));
      async.elapse(const Duration(seconds: 29));
      expect(lock.isLocked, isFalse);

      lock.onForeground();
      async.elapse(const Duration(seconds: 2));
      expect(lock.isLocked, isFalse);

      lock.onBackground(delay: const Duration(seconds: 30));
      async.elapse(const Duration(seconds: 30));
      expect(lock.isLocked, isTrue);
    });
  });
}
