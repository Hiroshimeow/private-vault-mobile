import 'dart:async';
import 'dart:math' as math;

import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/panic/panic_evaluator.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:sensors_plus/sensors_plus.dart';

class AccelerationSample {
  const AccelerationSample(this.x, this.y, this.z, this.timestamp);

  final double x;
  final double y;
  final double z;
  final DateTime timestamp;
}

class PanicSensorService {
  factory PanicSensorService({
    required LockController lockController,
    required AppSettings settings,
    required Stream<AccelerationSample> samples,
  }) => PanicSensorService._(
    lockController,
    settings,
    samples,
    PanicEvaluator(
      shakeThreshold: settings.shakeThresholdG,
      faceDownDelay: Duration(milliseconds: settings.faceDownDelayMs),
    ),
  );

  PanicSensorService._(
    this.lockController,
    this.settings,
    this._samples,
    this._evaluator,
  );

  final LockController lockController;
  AppSettings settings;
  final Stream<AccelerationSample> _samples;
  PanicEvaluator _evaluator;
  StreamSubscription<AccelerationSample>? _subscription;

  void start() {
    _subscription ??= _samples.listen(_onSample);
  }

  void updateSettings(AppSettings next) {
    settings = next;
    _evaluator = PanicEvaluator(
      shakeThreshold: next.shakeThresholdG,
      faceDownDelay: Duration(milliseconds: next.faceDownDelayMs),
    );
  }

  void _onSample(AccelerationSample sample) {
    if (lockController.isLocked) return;

    final magnitudeG =
        math.sqrt(
          (sample.x * sample.x) + (sample.y * sample.y) + (sample.z * sample.z),
        ) /
        9.80665;

    final shake =
        settings.panicShakeEnabled &&
        _evaluator.onAccelerationG(magnitudeG, sample.timestamp);

    final faceDown =
        settings.panicFaceDownEnabled &&
        _evaluator.onFaceDown(
          sample.z <= -7.5 && sample.x.abs() < 4 && sample.y.abs() < 4,
          sample.timestamp,
        );

    if (shake || faceDown) {
      lockController.panic();
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static Stream<AccelerationSample> deviceSamples() {
    return accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .map(
          (event) =>
              AccelerationSample(event.x, event.y, event.z, event.timestamp),
        );
  }
}
