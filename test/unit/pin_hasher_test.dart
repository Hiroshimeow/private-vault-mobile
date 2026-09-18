import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/auth/pin_hasher.dart';

void main() {
  test('verifies correct PIN and rejects wrong PIN', () async {
    final hasher = PinHasher(iterations: 1000);
    final verifier = await hasher.create('482951');

    expect(await hasher.verify('482951', verifier), isTrue);
    expect(await hasher.verify('111111', verifier), isFalse);
    expect(verifier.hash, isNot(contains('482951')));
  });
}
