import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/panic/panic_sensor_service.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';

void main() {
  test('shake above threshold locks an unlocked vault', () async {
    final events = StreamController<AccelerationSample>();
    final lock = LockController()..unlock();
    final service = PanicSensorService(
      lockController: lock,
      settings: const AppSettings.defaults(),
      samples: events.stream,
    );
    service.start();

    final t0 = DateTime(2026, 9, 18, 10);
    events.add(AccelerationSample(30, 0, 0, t0));
    await Future<void>.delayed(Duration.zero);

    expect(lock.isLocked, isTrue);
    await service.dispose();
    await events.close();
  });

  test('face-down requires enablement and configured hold delay', () async {
    final events = StreamController<AccelerationSample>();
    final lock = LockController()..unlock();
    final service = PanicSensorService(
      lockController: lock,
      settings: const AppSettings(
        cover: CoverPreference.calculator,
        panicShakeEnabled: false,
        panicFaceDownEnabled: true,
        shakeThresholdG: 3,
        faceDownDelayMs: 1000,
        autoLockSeconds: 0,
        biometricsEnabled: false,
        browserClearOnClose: true,
        confirmExport: true,
        darkMode: false,
      ),
      samples: events.stream,
    );
    service.start();

    final t0 = DateTime(2026, 9, 18, 10);
    events.add(AccelerationSample(0, 0, -9.4, t0));
    events.add(
      AccelerationSample(0, 0, -9.4, t0.add(const Duration(milliseconds: 900))),
    );
    await Future<void>.delayed(Duration.zero);
    expect(lock.isLocked, isFalse);

    events.add(
      AccelerationSample(
        0,
        0,
        -9.4,
        t0.add(const Duration(milliseconds: 1100)),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(lock.isLocked, isTrue);

    await service.dispose();
    await events.close();
  });

  test('updated settings take effect without rebuilding the service', () async {
    final events = StreamController<AccelerationSample>();
    final lock = LockController()..unlock();
    final service = PanicSensorService(
      lockController: lock,
      settings: const AppSettings.defaults(),
      samples: events.stream,
    );
    service.start();
    service.updateSettings(
      const AppSettings.defaults().copyWith(panicShakeEnabled: false),
    );

    events.add(AccelerationSample(35, 0, 0, DateTime(2026, 9, 18, 10)));
    await Future<void>.delayed(Duration.zero);

    expect(lock.isLocked, isFalse);
    await service.dispose();
    await events.close();
  });

  test('ordinary motion does not false-trigger', () async {
    final events = StreamController<AccelerationSample>();
    final lock = LockController()..unlock();
    final service = PanicSensorService(
      lockController: lock,
      settings: const AppSettings.defaults(),
      samples: events.stream,
    );
    service.start();

    final t0 = DateTime(2026, 9, 18, 10);
    for (var i = 0; i < 20; i++) {
      events.add(
        AccelerationSample(
          0.5,
          0.4,
          9.7,
          t0.add(Duration(milliseconds: i * 100)),
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(lock.isLocked, isFalse);
    await service.dispose();
    await events.close();
  });
}
