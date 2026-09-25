import 'dart:developer' as developer;

class UnlockPerformanceTrace {
  UnlockPerformanceTrace._();

  static final Stopwatch _clock = Stopwatch()..start();

  static void mark(
    String phase, {
    int? attemptId,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final elapsedMicros = _clock.elapsedMicroseconds;
    final arguments = <String, Object?>{
      'elapsed_us': elapsedMicros,
      'attempt_id': ?attemptId,
      ...fields,
    };
    developer.Timeline.instantSync(
      'private_vault.unlock.$phase',
      arguments: arguments,
    );
  }
}
