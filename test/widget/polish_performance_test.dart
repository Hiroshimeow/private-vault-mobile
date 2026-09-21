import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/platform/disguise_bridge.dart';

class _FakeUnlockService implements UnlockService {
  @override
  Future<void> configure(String pin) async {}

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) async => true;
}

class _BlockingSettingsStorage implements SettingsStorage {
  final Completer<void> gate = Completer<void>();
  int writes = 0;

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String encoded) async {
    writes += 1;
    await gate.future;
  }
}

void main() {
  testWidgets('slider feedback stays local until drag end persistence', (
    tester,
  ) async {
    final lock = LockController()..unlock();
    final storage = _BlockingSettingsStorage();

    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: _FakeUnlockService(),
        settingsStore: AppSettingsStore(storage),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    final finder = find.byKey(const Key('settings-shake-slider'));
    final before = tester.widget<Slider>(finder).value;
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    final duringDrag = tester.widget<Slider>(finder).value;
    expect(duringDrag, isNot(before));
    expect(storage.writes, 0);

    await gesture.up();
    await tester.pump();

    expect(storage.writes, 1);
    expect(tester.widget<Slider>(finder).value, duringDrag);
    expect(storage.gate.isCompleted, isFalse);

    storage.gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('launcher capability lookup is cached across settings rebuilds', (
    tester,
  ) async {
    const channel = MethodChannel('private_vault/platform');
    var capabilityCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getDisguiseCapabilities') {
            capabilityCalls += 1;
            return <String, Object?>{
              'androidLauncherAliases': true,
              'iosAlternateIcons': false,
            };
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final lock = LockController()..unlock();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: _FakeUnlockService(),
        disguiseBridge: PlatformDisguiseBridge(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(capabilityCalls, 1);

    await tester.scrollUntilVisible(find.text('Dark mode'), 180);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();

    expect(capabilityCalls, 1);
  });
}
