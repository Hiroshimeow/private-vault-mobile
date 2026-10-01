import 'dart:async';

import 'package:private_vault_mobile/features/auth/unlock_performance_trace.dart';

enum CalculatorUnlockMode { pin, biometric }

enum CalculatorUnlockTrigger { secondPinDigit, equals }

class CalculatorUnlockAttempt {
  const CalculatorUnlockAttempt({
    required this.candidate,
    required this.trigger,
  });

  final String candidate;
  final CalculatorUnlockTrigger trigger;

  bool get requiresBiometric => trigger == CalculatorUnlockTrigger.equals;
}

class CalculatorUnlockGateController {
  CalculatorUnlockGateController({
    required this.pinLength,
    required this.mode,
    required this.holdDuration,
    this.onStarted,
    required this.onTriggered,
    required this.onReleased,
  });

  int pinLength;
  CalculatorUnlockMode mode;
  Duration holdDuration;
  final void Function(CalculatorUnlockAttempt attempt)? onStarted;
  final void Function(CalculatorUnlockAttempt attempt) onTriggered;
  final void Function(CalculatorUnlockTrigger trigger) onReleased;

  String _digits = '';
  Timer? _holdTimer;
  Timer? _idleTimer;
  String? _heldKey;
  CalculatorUnlockTrigger? _activeTrigger;
  bool _triggered = false;

  String get digits => _digits;

  void update({
    required int pinLength,
    required CalculatorUnlockMode mode,
    required Duration holdDuration,
  }) {
    if (this.pinLength == pinLength &&
        this.mode == mode &&
        this.holdDuration == holdDuration) {
      return;
    }
    cancelHold();
    this.pinLength = pinLength;
    this.mode = mode;
    this.holdDuration = holdDuration;
    clear();
  }

  void recordDigit(String digit) {
    if (digit.length != 1 || !RegExp(r'^\d$').hasMatch(digit)) return;
    _digits = _digits.length >= pinLength ? digit : '$_digits$digit';
    _armIdleReset();
  }

  void clear() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _digits = '';
  }

  bool keyDown(String key) {
    cancelHold(notifyRelease: true);
    final trigger = _eligibleTrigger(key);
    if (trigger == null) return false;

    _idleTimer?.cancel();
    _idleTimer = null;
    _heldKey = key;
    _activeTrigger = trigger;
    final attempt = CalculatorUnlockAttempt(
      candidate: _digits,
      trigger: trigger,
    );
    UnlockPerformanceTrace.mark(
      'hold_pointer_down',
      fields: {'trigger': trigger.name, 'hold_ms': holdDuration.inMilliseconds},
    );
    onStarted?.call(attempt);
    _holdTimer = Timer(holdDuration, () {
      if (_heldKey != key || _activeTrigger != trigger) return;
      _triggered = true;
      UnlockPerformanceTrace.mark(
        'hold_threshold_fired',
        fields: {'trigger': trigger.name},
      );
      onTriggered(attempt);
    });
    return true;
  }

  bool keyUp(String key) {
    final trigger = _activeTrigger;
    final suppressTap = _triggered && _heldKey == key;

    _holdTimer?.cancel();
    _holdTimer = null;
    _heldKey = null;
    _activeTrigger = null;

    if (trigger != null) {
      onReleased(trigger);
      if (_triggered) {
        clear();
      } else if (_digits.isNotEmpty) {
        _armIdleReset();
      }
    } else if (_digits.isNotEmpty) {
      _armIdleReset();
    }
    _triggered = false;
    return suppressTap;
  }

  void cancelHold({bool notifyRelease = false}) {
    final trigger = _activeTrigger;
    final wasTriggered = _triggered;

    _holdTimer?.cancel();
    _holdTimer = null;
    _heldKey = null;
    _activeTrigger = null;
    _triggered = false;

    if (trigger != null && notifyRelease) {
      onReleased(trigger);
      if (wasTriggered) {
        clear();
      } else if (_digits.isNotEmpty && _idleTimer == null) {
        _armIdleReset();
      }
    } else if (_digits.isNotEmpty && _idleTimer == null) {
      _armIdleReset();
    }
  }

  CalculatorUnlockTrigger? _eligibleTrigger(String key) {
    if (_digits.length != pinLength || pinLength < 2) return null;
    if (mode == CalculatorUnlockMode.biometric) {
      return key == '=' ? CalculatorUnlockTrigger.equals : null;
    }
    return key == _digits[1] ? CalculatorUnlockTrigger.secondPinDigit : null;
  }

  void _armIdleReset() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 8), clear);
  }

  void dispose() {
    _holdTimer?.cancel();
    _idleTimer?.cancel();
  }
}
