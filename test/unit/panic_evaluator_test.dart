import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/panic/panic_evaluator.dart';

void main() {
  test('shake fires once then respects debounce', () {
    final panic = PanicEvaluator(
      shakeThreshold: 2.2,
      debounce: const Duration(seconds: 2),
    );
    final t0 = DateTime(2026, 1, 1, 12);

    expect(panic.onAccelerationG(2.3, t0), isTrue);
    expect(
      panic.onAccelerationG(3.0, t0.add(const Duration(milliseconds: 200))),
      isFalse,
    );
    expect(
      panic.onAccelerationG(2.3, t0.add(const Duration(seconds: 3))),
      isTrue,
    );
  });

  test('face down requires configured hold duration', () {
    final panic = PanicEvaluator(faceDownDelay: const Duration(seconds: 1));
    final t0 = DateTime(2026, 1, 1, 12);

    expect(panic.onFaceDown(true, t0), isFalse);
    expect(
      panic.onFaceDown(true, t0.add(const Duration(milliseconds: 900))),
      isFalse,
    );
    expect(
      panic.onFaceDown(true, t0.add(const Duration(milliseconds: 1100))),
      isTrue,
    );
  });
}
