import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/auth/system_handoff_lifecycle.dart';

void main() {
  test('trusted picker lifecycle is suppressed only inside bounded grace', () {
    fakeAsync((async) {
      var backgrounds = 0;
      var foregrounds = 0;
      final coordinator = SystemHandoffLifecycleCoordinator(
        handoffGrace: const Duration(seconds: 3),
        onBackground: () => backgrounds += 1,
        onForeground: () => foregrounds += 1,
      );

      coordinator.arm();
      coordinator.handle(AppLifecycleState.inactive);
      coordinator.handle(AppLifecycleState.paused);
      coordinator.handle(AppLifecycleState.hidden);
      expect(backgrounds, 0);

      async.elapse(const Duration(seconds: 3));
      expect(backgrounds, 1);

      coordinator.handle(AppLifecycleState.resumed);
      expect(foregrounds, 1);
      expect(coordinator.handoffActive, isFalse);
    });
  });

  test(
    'handoff grace expiry without lifecycle transition stays foreground',
    () {
      fakeAsync((async) {
        var backgrounds = 0;
        var foregrounds = 0;
        final coordinator = SystemHandoffLifecycleCoordinator(
          handoffGrace: const Duration(seconds: 3),
          onBackground: () => backgrounds += 1,
          onForeground: () => foregrounds += 1,
        );

        coordinator.arm();
        async.elapse(const Duration(seconds: 3));

        expect(backgrounds, 0);
        expect(foregrounds, 0);
        expect(coordinator.phase, SystemHandoffLifecyclePhase.none);
      });
    },
  );

  test('quick picker round trip clears grace without fake foreground', () {
    fakeAsync((async) {
      var backgrounds = 0;
      var foregrounds = 0;
      final coordinator = SystemHandoffLifecycleCoordinator(
        onBackground: () => backgrounds += 1,
        onForeground: () => foregrounds += 1,
      );

      coordinator.arm();
      coordinator.handle(AppLifecycleState.inactive);
      coordinator.handle(AppLifecycleState.paused);
      coordinator.handle(AppLifecycleState.resumed);
      async.elapse(const Duration(seconds: 10));

      expect(backgrounds, 0);
      expect(foregrounds, 0);
      expect(coordinator.handoffActive, isFalse);
    });
  });

  test('plugin completion while still paused cannot cancel lock grace', () {
    fakeAsync((async) {
      var backgrounds = 0;
      var foregrounds = 0;
      final coordinator = SystemHandoffLifecycleCoordinator(
        handoffGrace: const Duration(seconds: 3),
        onBackground: () => backgrounds += 1,
        onForeground: () => foregrounds += 1,
      );

      coordinator.arm();
      coordinator.handle(AppLifecycleState.paused);
      coordinator.disarm();
      expect(coordinator.phase, SystemHandoffLifecyclePhase.suspended);

      async.elapse(const Duration(seconds: 3));
      expect(backgrounds, 1);
      expect(coordinator.phase, SystemHandoffLifecyclePhase.backgroundTracked);

      coordinator.handle(AppLifecycleState.resumed);
      expect(foregrounds, 1);
      expect(coordinator.phase, SystemHandoffLifecyclePhase.none);
    });
  });

  test('detached always crosses lock boundary even during handoff', () {
    var backgrounds = 0;
    final coordinator = SystemHandoffLifecycleCoordinator(
      onBackground: () => backgrounds += 1,
      onForeground: () {},
    );
    coordinator.arm();
    coordinator.handle(AppLifecycleState.detached);
    expect(backgrounds, 1);
  });

  test('normal background is tracked once and resumed clears it', () {
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
}
