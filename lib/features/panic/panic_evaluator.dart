class PanicEvaluator {
  PanicEvaluator({
    this.shakeThreshold = 2.5,
    this.debounce = const Duration(seconds: 2),
    this.faceDownDelay = const Duration(seconds: 1),
  });

  final double shakeThreshold;
  final Duration debounce;
  final Duration faceDownDelay;

  DateTime? _lastTrigger;
  DateTime? _faceDownSince;

  bool onAccelerationG(double magnitudeG, DateTime now) {
    if (magnitudeG < shakeThreshold || !_canTrigger(now)) return false;
    _lastTrigger = now;
    return true;
  }

  bool onFaceDown(bool isFaceDown, DateTime now) {
    if (!isFaceDown) {
      _faceDownSince = null;
      return false;
    }

    _faceDownSince ??= now;
    if (now.difference(_faceDownSince!) < faceDownDelay || !_canTrigger(now)) {
      return false;
    }

    _lastTrigger = now;
    _faceDownSince = null;
    return true;
  }

  bool _canTrigger(DateTime now) =>
      _lastTrigger == null || now.difference(_lastTrigger!) >= debounce;
}
