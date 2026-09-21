import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const packageName = String.fromEnvironment('WORK_PROFILE_SMOKE_PACKAGE');

  testWidgets('managed profile clone lifecycle uses the native bridge', (
    tester,
  ) async {
    expect(
      packageName,
      isNotEmpty,
      reason:
          'WORK_PROFILE_SMOKE_PACKAGE must be provided by the CI bootstrap.',
    );

    final client = PigeonWorkProfileClient();
    final capability = await client.getCapability();
    expect(capability.supported, isTrue);
    expect(capability.profileState, WorkProfileState.ready);

    final before = await client.listApps();
    final beforeWork = before
        .where((app) => app.packageName == packageName && app.presentWork)
        .toList(growable: false);
    expect(
      beforeWork,
      isEmpty,
      reason: '$packageName must start absent from the managed profile.',
    );

    final cloned = await client.clone(packageName);
    expect(cloned.ok, isTrue, reason: cloned.message);

    await tester.pump(const Duration(milliseconds: 500));
    var state = (await client.listApps()).firstWhere(
      (app) => app.packageName == packageName,
    );
    expect(state.presentWork, isTrue);
    expect(state.systemApp, isTrue);

    final frozen = await client.setSuspended(packageName, true);
    expect(frozen.ok, isTrue, reason: frozen.message);
    await tester.pump(const Duration(milliseconds: 250));
    state = (await client.listApps()).firstWhere(
      (app) => app.packageName == packageName,
    );
    expect(state.suspended, isTrue);

    final unfrozen = await client.setSuspended(packageName, false);
    expect(unfrozen.ok, isTrue, reason: unfrozen.message);
    await tester.pump(const Duration(milliseconds: 250));
    state = (await client.listApps()).firstWhere(
      (app) => app.packageName == packageName,
    );
    expect(state.suspended, isFalse);

    final hidden = await client.setHidden(packageName, true);
    expect(hidden.ok, isTrue, reason: hidden.message);
    await tester.pump(const Duration(milliseconds: 250));
    state = (await client.listApps()).firstWhere(
      (app) => app.packageName == packageName,
    );
    expect(state.hidden, isTrue);

    final visible = await client.setHidden(packageName, false);
    expect(visible.ok, isTrue, reason: visible.message);
    await tester.pump(const Duration(milliseconds: 250));
    state = (await client.listApps()).firstWhere(
      (app) => app.packageName == packageName,
    );
    expect(state.hidden, isFalse);

    final launched = await client.launch(packageName);
    expect(launched.ok, isTrue, reason: launched.message);
  });
}
