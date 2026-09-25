import 'package:flutter/widgets.dart';

enum SystemHandoffLifecyclePhase { none, armed, suspended, backgroundTracked }

class SystemHandoffLifecycleCoordinator {
  SystemHandoffLifecycleCoordinator({
    required this.onBackground,
    required this.onForeground,
  });

  final void Function() onBackground;
  final void Function() onForeground;

  int _leaseCount = 0;
  SystemHandoffLifecyclePhase _phase = SystemHandoffLifecyclePhase.none;

  SystemHandoffLifecyclePhase get phase => _phase;
  bool get handoffActive => _leaseCount > 0;
  int get handoffLeaseCount => _leaseCount;

  void arm() {
    _leaseCount += 1;
    if (_phase == SystemHandoffLifecyclePhase.none) {
      _phase = SystemHandoffLifecyclePhase.armed;
    }
  }

  void disarm() {
    if (_leaseCount == 0) return;
    _leaseCount -= 1;
    if (_leaseCount > 0) return;

    if (_phase == SystemHandoffLifecyclePhase.suspended) {
      _trackBackground();
      return;
    }
    if (_phase == SystemHandoffLifecyclePhase.armed) {
      _phase = SystemHandoffLifecyclePhase.none;
    }
  }

  void handle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final wasBackgroundTracked =
          _phase == SystemHandoffLifecyclePhase.backgroundTracked;
      _phase = _leaseCount > 0
          ? SystemHandoffLifecyclePhase.armed
          : SystemHandoffLifecyclePhase.none;
      if (wasBackgroundTracked) {
        onForeground();
      }
      return;
    }

    // Android frequently reports a short inactive transition for focus loss.
    // Treating inactive alone as background makes dialogs and system UI lock
    // the secret workspace even though the app never actually left foreground.
    if (state == AppLifecycleState.inactive) return;

    if (state == AppLifecycleState.detached) {
      // Detach is a confidentiality boundary even if a picker lease is active.
      _leaseCount = 0;
      _trackBackground();
      return;
    }

    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }

    if (_leaseCount > 0) {
      _phase = SystemHandoffLifecyclePhase.suspended;
      return;
    }

    _trackBackground();
  }

  void _trackBackground() {
    if (_phase == SystemHandoffLifecyclePhase.backgroundTracked) return;
    _phase = SystemHandoffLifecyclePhase.backgroundTracked;
    onBackground();
  }

  void dispose() {
    _leaseCount = 0;
    _phase = SystemHandoffLifecyclePhase.none;
  }
}
