import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';

class FakeBiometricUnlock implements BiometricUnlock {
  FakeBiometricUnlock({this.available = true, this.accepted = true});

  final bool available;
  final bool accepted;

  @override
  Future<bool> authenticate() async => accepted;

  @override
  Future<bool> isAvailable() async => available;
}

class FakeUnlockService implements UnlockService {
  FakeUnlockService({this.pin = '482951'});

  final String pin;

  @override
  Future<bool> verify(String candidate) async => candidate == pin;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<void> configure(String pin) async {}
}

void main() {
  testWidgets(
    'locked launch renders calculator cover and no secret workspace text',
    (tester) async {
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: LockController(),
          unlockService: FakeUnlockService(),
        ),
      );

      expect(find.text('Calculator'), findsOneWidget);
      expect(find.byTooltip('Lock now'), findsNothing);
      expect(find.text('Browser'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    },
  );

  testWidgets('calculator cover performs addition while locked', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '2'));
    await tester.tap(find.widgetWithText(FilledButton, '+'));
    await tester.tap(find.widgetWithText(FilledButton, '3'));
    await tester.tap(find.widgetWithText(FilledButton, '='));
    await tester.pump();

    final display = tester.widget<Text>(
      find.byKey(const Key('calculator-display')),
    );
    expect(display.data, '5');
  });

  testWidgets('valid PIN unlocks and panic returns to cover', (tester) async {
    final lock = LockController();
    await tester.pumpWidget(
      PrivateVaultApp(lockController: lock, unlockService: FakeUnlockService()),
    );

    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('unlock-pin')), '482951');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Lock now'), findsOneWidget);

    lock.panic();
    await tester.pumpAndSettle();

    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('enabled biometric unlock can open secret workspace', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(),
        biometricUnlock: FakeBiometricUnlock(),
        initialSettings: const AppSettings.defaults().copyWith(
          biometricsEnabled: true,
        ),
      ),
    );

    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Use biometrics'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Lock now'), findsOneWidget);
  });

  testWidgets('notes cover is functional without exposing secret routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(),
        initialCover: CoverKind.notes,
      ),
    );

    await tester.enterText(find.byKey(const Key('todo-input')), 'Buy milk');
    await tester.tap(find.byKey(const Key('todo-add')));
    await tester.pump();

    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });
}
