import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/auth/unlock_performance_trace.dart';
import 'package:private_vault_mobile/features/cover/calculator_cover.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

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

class TrackingPreparedSession implements PreparedPinSession {
  bool destroyed = false;

  @override
  void destroy() => destroyed = true;
}

class DeferredPreparableRepository
    implements PreparablePinSessionVaultRepository {
  final Completer<PreparedPinSession> preparation =
      Completer<PreparedPinSession>();
  int prepareCalls = 0;
  int activateCalls = 0;
  int _generation = 0;
  bool _open = false;

  @override
  int get sessionGeneration => _generation;

  @override
  bool get hasOpenSession => _open;

  @override
  Future<PreparedPinSession> prepareSession(String pin) {
    prepareCalls += 1;
    return preparation.future;
  }

  @override
  int activatePreparedSession(PreparedPinSession prepared) {
    activateCalls += 1;
    _open = true;
    return ++_generation;
  }

  @override
  Future<void> openSession(String pin) async {
    await openSessionWithGeneration(pin);
  }

  @override
  Future<int> openSessionWithGeneration(String pin) async {
    _open = true;
    return ++_generation;
  }

  @override
  void clearSession() => _open = false;

  @override
  void clearSessionIfGeneration(int generation) {
    if (_generation == generation) _open = false;
  }

  @override
  Future<VaultItem> addBytes(Uint8List bytes, {required VaultItemKind kind}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<List<VaultItem>> list() => throw UnimplementedError();

  @override
  Future<Uint8List> readBytes(String id) => throw UnimplementedError();
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
    'background during eligible hold clears candidate and never verifies',
    (tester) async {
      final lock = LockController();
      final unlock = DeferredUnlockService();
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: unlock,
          initialSettings: const AppSettings.defaults().copyWith(
            biometricsEnabled: true,
          ),
        ),
      );

      for (var index = 0; index < 4; index++) {
        await tester.tap(find.byKey(const Key('calculator-key-0')));
      }
      final equals = find.byKey(const Key('calculator-key-='));
      final gesture = await tester.startGesture(tester.getCenter(equals));
      await tester.pump(const Duration(milliseconds: 500));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 3));

      expect(unlock.verifyCalls, 1);
      expect(lock.isLocked, isTrue);

      await gesture.up();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(unlock.verifyCalls, 1);
    },
  );

  testWidgets(
    'background after PIN threshold invalidates pending unlock and destroys prepared session',
    (tester) async {
      final lock = LockController();
      final unlock = DeferredUnlockService();
      final repository = DeferredPreparableRepository();
      final prepared = TrackingPreparedSession();
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: unlock,
          vaultRepository: repository,
          initialSettings: const AppSettings.defaults().copyWith(
            unlockHoldMs: 700,
          ),
        ),
      );
      await tester.pump();

      for (final digit in '1123'.split('')) {
        await tester.tap(find.byKey(Key('calculator-key-$digit')));
      }
      final trigger = find.byKey(const Key('calculator-key-1'));
      final gesture = await tester.startGesture(tester.getCenter(trigger));
      await tester.pump(const Duration(milliseconds: 700));

      expect(unlock.verifyCalls, 1);
      expect(repository.prepareCalls, 1);
      expect(lock.isLocked, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      unlock.verification.complete(true);
      repository.preparation.complete(prepared);
      await tester.pumpAndSettle();

      await gesture.up();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(lock.isLocked, isTrue);
      expect(repository.activateCalls, 0);
      expect(repository.hasOpenSession, isFalse);
      expect(prepared.destroyed, isTrue);
    },
  );

  testWidgets(
    'biometric focus loss does not cancel the active equals attempt',
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

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(biometric.cancelCalls, 0);

      biometric.authentication.complete(true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(lock.isLocked, isFalse);

      await gesture.up();
    },
  );

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

  testWidgets(
    'PIN release after threshold does not cancel active verification',
    (tester) async {
      final lock = LockController();
      final unlock = DeferredUnlockService();
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: unlock,
          initialSettings: const AppSettings.defaults().copyWith(
            unlockHoldMs: 700,
          ),
        ),
      );
      await tester.pump();

      for (final digit in '1123'.split('')) {
        await tester.tap(find.byKey(Key('calculator-key-$digit')));
      }
      final trigger = find.byKey(const Key('calculator-key-1'));
      final gesture = await tester.startGesture(tester.getCenter(trigger));
      await tester.pump(const Duration(milliseconds: 700));
      expect(unlock.verifyCalls, 1);

      await gesture.up();
      await tester.pump();
      unlock.verification.complete(true);
      await tester.pumpAndSettle();
      expect(lock.isLocked, isFalse);
    },
  );

  testWidgets('touch key executes on pointer down exactly once', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CalculatorCover()));

    final key = find.byKey(const Key('calculator-key-7'));
    final gesture = await tester.startGesture(tester.getCenter(key));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('calculator-display'))).data,
      '7',
    );

    await gesture.up();
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('calculator-display'))).data,
      '7',
    );
  });

  testWidgets(
    'PIN preflight starts on pointer down and commits at threshold without release',
    (tester) async {
      final phases = <String>[];
      UnlockPerformanceTrace.debugSink = (phase, _, _) => phases.add(phase);
      addTearDown(() => UnlockPerformanceTrace.debugSink = null);
      final lock = LockController();
      final unlock = DeferredUnlockService();
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: unlock,
          initialSettings: const AppSettings.defaults().copyWith(
            unlockHoldMs: 700,
          ),
        ),
      );
      await tester.pump();

      for (final digit in '1123'.split('')) {
        await tester.tap(find.byKey(Key('calculator-key-$digit')));
      }
      final trigger = find.byKey(const Key('calculator-key-1'));
      final gesture = await tester.startGesture(tester.getCenter(trigger));
      await tester.pump();

      expect(unlock.verifyCalls, 1);
      expect(lock.isLocked, isTrue);

      unlock.verification.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 699));
      expect(lock.isLocked, isTrue);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(lock.isLocked, isFalse);
      expect(
        phases.indexOf('verification_start'),
        lessThan(phases.indexOf('hold_threshold_fired')),
      );
      expect(
        phases.indexOf('hold_threshold_fired'),
        lessThan(phases.indexOf('unlock_committed')),
      );

      await gesture.up();
    },
  );

  testWidgets('release before threshold invalidates stale PIN success', (
    tester,
  ) async {
    final lock = LockController();
    final unlock = DeferredUnlockService();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: unlock,
        initialSettings: const AppSettings.defaults().copyWith(
          unlockHoldMs: 700,
        ),
      ),
    );
    await tester.pump();

    for (final digit in '1123'.split('')) {
      await tester.tap(find.byKey(Key('calculator-key-$digit')));
    }
    final trigger = find.byKey(const Key('calculator-key-1'));
    final gesture = await tester.startGesture(tester.getCenter(trigger));
    await tester.pump(const Duration(milliseconds: 100));
    expect(unlock.verifyCalls, 1);

    await gesture.up();
    await tester.pump();
    unlock.verification.complete(true);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(lock.isLocked, isTrue);
  });

  testWidgets('quick tap of eligible PIN digit remains a calculator tap', (
    tester,
  ) async {
    var triggered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CalculatorCover(
          holdDuration: const Duration(milliseconds: 700),
          onUnlockTriggered: (_) => triggered += 1,
        ),
      ),
    );

    for (final digit in '1123'.split('')) {
      await tester.tap(find.byKey(Key('calculator-key-$digit')));
    }

    await tester.tap(find.byKey(const Key('calculator-key-1')));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('calculator-display'))).data,
      '11231',
    );
    expect(triggered, 0);
  });

  testWidgets('quick tap of eligible biometric equals executes equals once', (
    tester,
  ) async {
    var triggered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CalculatorCover(
          biometricMode: true,
          holdDuration: const Duration(milliseconds: 700),
          onUnlockTriggered: (_) => triggered += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('calculator-key-8')));
    await tester.tap(find.byKey(const Key('calculator-key-+')));
    for (final digit in '0004'.split('')) {
      await tester.tap(find.byKey(Key('calculator-key-$digit')));
    }

    await tester.tap(find.byKey(const Key('calculator-key-=')));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('calculator-display'))).data,
      '12',
    );
    expect(triggered, 0);
  });

  testWidgets('pre-threshold cancel destroys prepared session material', (
    tester,
  ) async {
    final lock = LockController();
    final unlock = DeferredUnlockService();
    final repository = DeferredPreparableRepository();
    final prepared = TrackingPreparedSession();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: unlock,
        vaultRepository: repository,
        initialSettings: const AppSettings.defaults().copyWith(
          unlockHoldMs: 700,
        ),
      ),
    );
    await tester.pump();

    for (final digit in '1123'.split('')) {
      await tester.tap(find.byKey(Key('calculator-key-$digit')));
    }
    final trigger = find.byKey(const Key('calculator-key-1'));
    final gesture = await tester.startGesture(tester.getCenter(trigger));
    await tester.pump();
    expect(unlock.verifyCalls, 1);
    expect(repository.prepareCalls, 1);

    await gesture.up();
    await tester.pump();
    unlock.verification.complete(true);
    repository.preparation.complete(prepared);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(prepared.destroyed, isTrue);
    expect(repository.activateCalls, 0);
    expect(lock.isLocked, isTrue);
  });
}
