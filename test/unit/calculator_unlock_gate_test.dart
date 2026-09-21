import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/auth/unlock_gate/calculator_unlock_gate.dart';

void main() {
  test('PIN mode triggers only after full PIN and hold of second digit', () {
    fakeAsync((async) {
      final attempts = <CalculatorUnlockAttempt>[];
      final released = <CalculatorUnlockTrigger>[];
      final gate = CalculatorUnlockGateController(
        pinLength: 4,
        mode: CalculatorUnlockMode.pin,
        holdDuration: const Duration(seconds: 2),
        onTriggered: attempts.add,
        onReleased: released.add,
      );

      for (final digit in ['1', '1', '2', '3']) {
        gate.recordDigit(digit);
      }

      gate.keyDown('1');
      async.elapse(const Duration(milliseconds: 1999));
      expect(attempts, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      expect(attempts, hasLength(1));
      expect(attempts.single.candidate, '1123');
      expect(attempts.single.trigger, CalculatorUnlockTrigger.secondPinDigit);

      expect(gate.keyUp('1'), isTrue);
      expect(released, [CalculatorUnlockTrigger.secondPinDigit]);
      expect(gate.digits, isEmpty);
    });
  });

  test('PIN mode ignores wrong hold key and never verifies early', () {
    fakeAsync((async) {
      final attempts = <CalculatorUnlockAttempt>[];
      final gate = CalculatorUnlockGateController(
        pinLength: 10,
        mode: CalculatorUnlockMode.pin,
        holdDuration: const Duration(milliseconds: 700),
        onTriggered: attempts.add,
        onReleased: (_) {},
      );

      for (final digit in '4762178234'.split('')) {
        gate.recordDigit(digit);
      }

      gate.keyDown('4');
      async.elapse(const Duration(seconds: 1));
      gate.keyUp('4');
      expect(attempts, isEmpty);

      gate.keyDown('7');
      async.elapse(const Duration(milliseconds: 700));
      expect(attempts.single.candidate, '4762178234');
      expect(attempts.single.requiresBiometric, isFalse);
    });
  });

  test('biometric mode requires full PIN and hold equals', () {
    fakeAsync((async) {
      final attempts = <CalculatorUnlockAttempt>[];
      final released = <CalculatorUnlockTrigger>[];
      final gate = CalculatorUnlockGateController(
        pinLength: 4,
        mode: CalculatorUnlockMode.biometric,
        holdDuration: const Duration(milliseconds: 900),
        onTriggered: attempts.add,
        onReleased: released.add,
      );

      for (final digit in ['0', '0', '0']) {
        gate.recordDigit(digit);
      }
      gate.keyDown('=');
      async.elapse(const Duration(seconds: 2));
      gate.keyUp('=');
      expect(attempts, isEmpty);

      gate.recordDigit('0');
      gate.keyDown('=');
      async.elapse(const Duration(milliseconds: 900));
      expect(attempts, hasLength(1));
      expect(attempts.single.candidate, '0000');
      expect(attempts.single.requiresBiometric, isTrue);

      gate.keyUp('=');
      expect(released, [CalculatorUnlockTrigger.equals]);
    });
  });

  test('release before hold threshold never triggers', () {
    fakeAsync((async) {
      final attempts = <CalculatorUnlockAttempt>[];
      final gate = CalculatorUnlockGateController(
        pinLength: 4,
        mode: CalculatorUnlockMode.biometric,
        holdDuration: const Duration(seconds: 2),
        onTriggered: attempts.add,
        onReleased: (_) {},
      );

      for (final digit in ['0', '0', '0', '0']) {
        gate.recordDigit(digit);
      }

      gate.keyDown('=');
      async.elapse(const Duration(milliseconds: 400));
      expect(gate.keyUp('='), isFalse);
      async.elapse(const Duration(seconds: 3));
      expect(attempts, isEmpty);
    });
  });

  test(
    'extra digit starts a new candidate instead of verifying continuously',
    () {
      fakeAsync((async) {
        final attempts = <CalculatorUnlockAttempt>[];
        final gate = CalculatorUnlockGateController(
          pinLength: 4,
          mode: CalculatorUnlockMode.pin,
          holdDuration: const Duration(seconds: 1),
          onTriggered: attempts.add,
          onReleased: (_) {},
        );

        for (final digit in ['0', '0', '0', '0', '7']) {
          gate.recordDigit(digit);
        }

        expect(gate.digits, '7');
        async.elapse(const Duration(seconds: 5));
        expect(attempts, isEmpty);
      });
    },
  );
}
