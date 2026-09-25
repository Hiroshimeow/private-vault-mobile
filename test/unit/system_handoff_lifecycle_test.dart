import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/auth/system_handoff_lifecycle.dart';

void main() {
  test('picker lease suppresses background indefinitely until released', () {
    var backgrounds = 0;
    var foregrounds = 0;
    final coordinator = SystemHandoffLifecycleCoordinator(
      onBackground: () => backgrounds += 1,
      onForeground: () => foregrounds += 1,
    );

    coordinator.arm();
    coordinator.handle(AppLifecycleState.inactive);
    coordinator.handle(AppLifecycleState.paused);
    coordinator.handle(AppLifecycleState.hidden);
    expect(backgrounds, 0);
    expect(coordinator.phase, SystemHandoffLifecyclePhase.suspended);

    coordinator.disarm();
    expect(backgrounds, 1);
    expect(coordinator.phase, SystemHandoffLifecyclePhase.backgroundTracked);

    coordinator.handle(AppLifecycleState.resumed);
    expect(foregrounds, 1);
    expect(coordinator.phase, SystemHandoffLifecyclePhase.none);
  });

  test('picker cancel after resumed releases without fake lock', () {
    var backgrounds = 0;
    var foregrounds = 0;
    final coordinator = SystemHandoffLifecycleCoordinator(
      onBackground: () => backgrounds += 1,
      onForeground: () => foregrounds += 1,
    );

    coordinator.arm();
    coordinator.handle(AppLifecycleState.paused);
    coordinator.handle(AppLifecycleState.resumed);
    coordinator.disarm();

    expect(backgrounds, 0);
    expect(foregrounds, 0);
    expect(coordinator.handoffActive, isFalse);
    expect(coordinator.phase, SystemHandoffLifecyclePhase.none);
  });

  test('nested leases do not release each other', () {
    var backgrounds = 0;
    final coordinator = SystemHandoffLifecycleCoordinator(
      onBackground: () => backgrounds += 1,
      onForeground: () {},
    );

    coordinator.arm();
    coordinator.arm();
    coordinator.handle(AppLifecycleState.paused);
    coordinator.disarm();
    expect(backgrounds, 0);
    expect(coordinator.handoffLeaseCount, 1);
    coordinator.disarm();
    expect(backgrounds, 1);
  });

  test('inactive alone does not cross lock boundary', () {
    var backgrounds = 0;
    final coordinator = SystemHandoffLifecycleCoordinator(
      onBackground: () => backgrounds += 1,
      onForeground: () {},
    );
    coordinator.handle(AppLifecycleState.inactive);
    expect(backgrounds, 0);
  });

  test('paused or hidden without lease tracks background once', () {
    var backgrounds = 0;
    var foregrounds = 0;
    final coordinator = SystemHandoffLifecycleCoordinator(
      onBackground: () => backgrounds += 1,
      onForeground: () => foregrounds += 1,
    );
    coordinator.handle(AppLifecycleState.paused);
    coordinator.handle(AppLifecycleState.hidden);
    expect(backgrounds, 1);
    coordinator.handle(AppLifecycleState.resumed);
    expect(foregrounds, 1);
  });

  test('detached always crosses lock boundary even during lease', () {
    var backgrounds = 0;
    final coordinator = SystemHandoffLifecycleCoordinator(
      onBackground: () => backgrounds += 1,
      onForeground: () {},
    );
    coordinator.arm();
    coordinator.handle(AppLifecycleState.detached);
    expect(backgrounds, 1);
    expect(coordinator.handoffActive, isFalse);
  });
}
