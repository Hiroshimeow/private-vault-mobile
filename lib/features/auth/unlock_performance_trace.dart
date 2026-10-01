import 'dart:developer' as developer;

typedef UnlockPerformanceTraceSink = void Function(
  String phase,
  int? attemptId,
  Map<String, Object?> fields,
);

class UnlockPerformanceTrace {
  UnlockPerformanceTrace._();

  static final Stopwatch _clock = Stopwatch()..start();
  static UnlockPerformanceTraceSink? debugSink;

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
    debugSink?.call(phase, attemptId, Map.unmodifiable(arguments));
    developer.Timeline.instantSync(
      'private_vault.unlock.$phase',
      arguments: arguments,
    );
  }
}
