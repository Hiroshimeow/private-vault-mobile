import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/app/private_vault_theme.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/cover/notes_cover.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';

class _FakeUnlockService implements UnlockService {
  @override
  Future<void> configure(String pin) async {}

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) async => candidate == '482951';
}

void main() {
  testWidgets('notes cover exposes task semantics and reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivateVaultTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: NotesCover(onUnlockRequested: () {}),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('Task list summary')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Add task')), findsOneWidget);
    expect(
      tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
      Duration.zero,
    );
  });

  testWidgets('settings expose grouped semantic sections', (tester) async {
    final lock = LockController()..unlock();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: _FakeUnlockService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Cover settings')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Concealment settings')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('Access'), 180);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Access settings')), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Appearance'), 180);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Data handling settings')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Appearance settings')),
      findsOneWidget,
    );
  });

  testWidgets('calculator title exposes no PIN management surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: _FakeUnlockService(),
      ),
    );

    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Enter PIN'), findsNothing);
    expect(find.textContaining('access PIN'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsNothing);
  });

  for (final darkMode in <bool>[false, true]) {
    testWidgets('secret workspace follows root theme darkMode=$darkMode', (
      tester,
    ) async {
      final lock = LockController()..unlock();
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: _FakeUnlockService(),
          initialSettings: const AppSettings.defaults().copyWith(
            darkMode: darkMode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(SecretWorkspace));
      expect(
        Theme.of(context).brightness,
        darkMode ? Brightness.dark : Brightness.light,
      );
    });
  }
}
