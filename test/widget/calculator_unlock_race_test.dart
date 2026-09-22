import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';

class DeferredUnlockService
    implements UnlockService, PinLengthAwareUnlockService {
  DeferredUnlockService({this.pinLength = 4});

  final int pinLength;
  final Completer<bool> verification = Completer<bool>();
  int verifyCalls = 0;

  @override
  Future<void> configure(String pin) async {}

  @override
  Future<int?> configuredPinLength() async => pinLength;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) {
    verifyCalls += 1;
    return verification.future;
  }
}

class ControlledBiometric implements BiometricUnlock {
  final Completer<bool> authentication = Completer<bool>();
  int authenticateCalls = 0;
  int cancelCalls = 0;

  @override
  Future<bool> authenticate() {
    authenticateCalls += 1;
    return authentication.future;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  Future<bool> isAvailable() async => true;
}

Future<TestGesture> triggerBiometricHold(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.tap(find.byKey(const Key('calculator-key-0')));
  }
  final equals = find.byKey(const Key('calculator-key-='));
  final gesture = await tester.startGesture(tester.getCenter(equals));
  await tester.pump(const Duration(seconds: 2));
  return gesture;
}

void main() {
  testWidgets('ordinary PIN entry never verifies before valid hold', (
    tester,
  ) async {
    final unlock = DeferredUnlockService();
    await tester.pumpWidget(
      PrivateVaultApp(lockController: LockController(), unlockService: unlock),
    );
    await tester.pump();

    for (final digit in '0000'.split('')) {
      await tester.tap(find.byKey(Key('calculator-key-$digit')));
    }
    await tester.pump();

    expect(unlock.verifyCalls, 0);
  });

  testWidgets('release before PIN verification completes blocks biometric', (
    tester,
  ) async {
    final lock = LockController();
    final unlock = DeferredUnlockService();
    final biometric = ControlledBiometric();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: unlock,
        biometricUnlock: biometric,
        initialSettings: const AppSettings.defaults().copyWith(
          biometricsEnabled: true,
        ),
      ),
    );

    final gesture = await triggerBiometricHold(tester);
    await tester.pump();
    expect(unlock.verifyCalls, 1);

    await gesture.up();
    await tester.pump();
    unlock.verification.complete(true);
    await tester.pumpAndSettle();

    expect(biometric.authenticateCalls, 0);
    expect(lock.isLocked, isTrue);
  });

  testWidgets(
    'release after biometric starts cancels and stale success cannot unlock',
    (tester) async {
      final lock = LockController();
      final unlock = DeferredUnlockService();
      final biometric = ControlledBiometric();
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: unlock,
          biometricUnlock: biometric,
          initialSettings: const AppSettings.defaults().copyWith(
            biometricsEnabled: true,
          ),
        ),
      );

      final gesture = await triggerBiometricHold(tester);
      unlock.verification.complete(true);
      await tester.pump();
      await tester.pump();
      expect(biometric.authenticateCalls, 1);

      await gesture.up();
      await tester.pump();
      expect(biometric.cancelCalls, 1);

      biometric.authentication.complete(true);
      await tester.pumpAndSettle();
      expect(lock.isLocked, isTrue);
    },
  );
}
