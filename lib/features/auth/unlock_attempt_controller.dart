enum CalculatorUnlockAttemptPhase {
  verifyingPin,
  checkingBiometrics,
  authenticating,
  completed,
  cancelled,
}

class CalculatorUnlockAttemptState {
  CalculatorUnlockAttemptState(this.id);

  final int id;
  CalculatorUnlockAttemptPhase phase =
      CalculatorUnlockAttemptPhase.verifyingPin;

  bool get biometricStarted =>
      phase == CalculatorUnlockAttemptPhase.authenticating;

  bool get isTerminal =>
      phase == CalculatorUnlockAttemptPhase.cancelled ||
      phase == CalculatorUnlockAttemptPhase.completed;
}

class CalculatorUnlockAttemptController {
  int _nextId = 0;
  CalculatorUnlockAttemptState? _current;

  CalculatorUnlockAttemptState? tryBegin() {
    final current = _current;
    if (current != null && !current.isTerminal) {
      return null;
    }
    final state = CalculatorUnlockAttemptState(++_nextId);
    _current = state;
    return state;
  }

  bool isCurrent(CalculatorUnlockAttemptState state) {
    return identical(_current, state) && !state.isTerminal;
  }

  bool beginBiometricCheck(CalculatorUnlockAttemptState state) {
    if (!isCurrent(state)) return false;
    state.phase = CalculatorUnlockAttemptPhase.checkingBiometrics;
    return true;
  }

  bool markBiometricStarted(CalculatorUnlockAttemptState state) {
    if (!isCurrent(state)) return false;
    state.phase = CalculatorUnlockAttemptPhase.authenticating;
    return true;
  }

  bool cancelCurrent() {
    final state = _current;
    if (state == null) return false;
    final biometricStarted = state.biometricStarted;
    state.phase = CalculatorUnlockAttemptPhase.cancelled;
    _current = null;
    return biometricStarted;
  }

  void complete(CalculatorUnlockAttemptState state) {
    if (!identical(_current, state)) return;
    state.phase = CalculatorUnlockAttemptPhase.completed;
    _current = null;
  }

  void dispose() {
    cancelCurrent();
  }
}
