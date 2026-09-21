import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';

class _UnlockService implements UnlockService {
  @override
  Future<void> configure(String pin) async {}

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) async => true;
}

class _FakeWorkProfileClient implements WorkProfileClient {
  int capabilityCalls = 0;
  int listCalls = 0;

  @override
  Future<WorkProfileCapability> getCapability() async {
    capabilityCalls += 1;
    return const WorkProfileCapability(
      supported: true,
      provisioningAllowed: true,
      profileState: WorkProfileState.absent,
    );
  }

  @override
  Future<List<ManagedAppState>> listApps() async {
    listCalls += 1;
    return const [];
  }

  @override
  Future<WorkProfileOperationResult> startProvisioning() async =>
      const WorkProfileOperationResult.success();

  @override
  Future<WorkProfileOperationResult> clone(String packageName) async =>
      const WorkProfileOperationResult.success();

  @override
  Future<WorkProfileOperationResult> launch(String packageName) async =>
      const WorkProfileOperationResult.success();

  @override
  Future<WorkProfileOperationResult> setSuspended(
    String packageName,
    bool suspended,
  ) async => const WorkProfileOperationResult.success();

  @override
  Future<WorkProfileOperationResult> setHidden(
    String packageName,
    bool hidden,
  ) async => const WorkProfileOperationResult.success();

  @override
  Future<WorkProfileOperationResult> uninstall(String packageName) async =>
      const WorkProfileOperationResult.success();

  @override
  Future<WorkProfileOperationResult> destroyProfile() async =>
      const WorkProfileOperationResult.success();
}

void main() {
  testWidgets('Android workspace promotes Apps before Browser after unlock', (
    tester,
  ) async {
    final lock = LockController()..unlock();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: _UnlockService(),
        workProfileClient: _FakeWorkProfileClient(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Apps'), findsWidgets);
    expect(find.text('Browser'), findsWidgets);
    final apps = tester.getCenter(find.text('Apps').last).dx;
    final browser = tester.getCenter(find.text('Browser').last).dx;
    expect(apps, lessThan(browser));
  });

  testWidgets('locked cover exposes no Apps or package inventory UI', (
    tester,
  ) async {
    final client = _FakeWorkProfileClient();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: _UnlockService(),
        workProfileClient: client,
      ),
    );

    expect(client.capabilityCalls, 0);
    expect(client.listCalls, 0);
    expect(find.text('Apps'), findsNothing);
    expect(find.textContaining('work profile'), findsNothing);
    expect(find.byIcon(Icons.apps), findsNothing);
  });
}
