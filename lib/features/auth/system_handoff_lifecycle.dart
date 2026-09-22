import 'dart:async';

import 'package:flutter/widgets.dart';

enum SystemHandoffLifecyclePhase {
  none,
  armed,
  suspended,
  backgroundTracked,
}

class SystemHandoffLifecycleCoordinator {
  SystemHandoffLifecycleCoordinator({
    required this.onBackground,
    required this.onForeground,
    this.handoffGrace = const Duration(seconds: 3),
  });

  final void Function() onBackground;
  final void Function() onForeground;
  final Duration handoffGrace;

  Timer? _graceTimer;
  SystemHandoffLifecyclePhase _phase = SystemHandoffLifecyclePhase.none;

  SystemHandoffLifecyclePhase get phase => _phase;

  bool get handoffActive =>
      _phase == SystemHandoffLifecyclePhase.armed ||
      _phase == SystemHandoffLifecyclePhase.suspended;

  void arm() {
    _graceTimer?.cancel();
    _phase = SystemHandoffLifecyclePhase.armed;
    _graceTimer = Timer(handoffGrace, _expireHandoff);
  }

  void disarm() {
    if (_phase == SystemHandoffLifecyclePhase.armed) {
      _clearHandoff();
    }
    // If a lifecycle transition was already observed, keep the bounded grace
    // alive until either resumed or expiry. A plugin future can complete while
    // the app is still backgrounded and must not disable the lock boundary.
  }

  void handle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final wasBackgroundTracked =
          _phase == SystemHandoffLifecyclePhase.backgroundTracked;
      _clearHandoff();
      if (wasBackgroundTracked) {
        onForeground();
      }
      return;
    }

    if (!_isBackgroundState(state)) return;

    if (state == AppLifecycleState.detached) {
      _trackBackground();
      return;
    }

    if (_phase == SystemHandoffLifecyclePhase.armed ||
        _phase == SystemHandoffLifecyclePhase.suspended) {
      _phase = SystemHandoffLifecyclePhase.suspended;
      return;
    }

    _trackBackground();
  }

  void _expireHandoff() {
    _graceTimer = null;
    if (_phase != SystemHandoffLifecyclePhase.armed &&
        _phase != SystemHandoffLifecyclePhase.suspended) {
      return;
    }
    _trackBackground();
  }

  void _trackBackground() {
    _graceTimer?.cancel();
    _graceTimer = null;
    if (_phase == SystemHandoffLifecyclePhase.backgroundTracked) return;
    _phase = SystemHandoffLifecyclePhase.backgroundTracked;
    onBackground();
  }

  void _clearHandoff() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _phase = SystemHandoffLifecyclePhase.none;
  }

  bool _isBackgroundState(AppLifecycleState state) {
    return state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
  }

  void dispose() {
    _clearHandoff();
  }
}
