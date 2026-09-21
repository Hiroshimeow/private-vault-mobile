import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_home.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';

class ProvisioningWorkProfileClient implements WorkProfileClient {
  bool provisioned = false;

  @override
  Future<WorkProfileCapability> getCapability() async => WorkProfileCapability(
    supported: true,
    provisioningAllowed: !provisioned,
    profileState: provisioned
        ? WorkProfileState.ready
        : WorkProfileState.absent,
  );

  @override
  Future<List<ManagedAppState>> listApps() async => const [];

  @override
  Future<WorkProfileOperationResult> startProvisioning() async {
    provisioned = true;
    return const WorkProfileOperationResult.success();
  }

  @override
  Future<WorkProfileOperationResult> clone(String packageName) async =>
      const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> destroyProfile() async =>
      const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> launch(String packageName) async =>
      const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> setHidden(
    String packageName,
    bool hidden,
  ) async => const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> setSuspended(
    String packageName,
    bool suspended,
  ) async => const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> uninstall(String packageName) async =>
      const WorkProfileOperationResult.success();
}

class ReadyWorkProfileClient implements WorkProfileClient {
  int destroyCalls = 0;

  @override
  Future<WorkProfileCapability> getCapability() async =>
      const WorkProfileCapability(
        supported: true,
        provisioningAllowed: false,
        profileState: WorkProfileState.ready,
      );

  @override
  Future<List<ManagedAppState>> listApps() async => const [
    ManagedAppState(
      packageName: 'example.app',
      label: 'Example',
      presentPersonal: true,
      presentWork: true,
      launchableWork: true,
      systemApp: false,
      suspended: false,
      hidden: false,
      cloneEligibility: CloneEligibility.alreadyInstalled,
      installerActionRequired: false,
    ),
    ManagedAppState(
      packageName: 'personal.app',
      label: 'Personal only',
      presentPersonal: true,
      presentWork: false,
      launchableWork: false,
      systemApp: false,
      suspended: false,
      hidden: false,
      cloneEligibility: CloneEligibility.eligible,
      installerActionRequired: true,
    ),
  ];

  @override
  Future<WorkProfileOperationResult> destroyProfile() async {
    destroyCalls += 1;
    return const WorkProfileOperationResult.success();
  }

  @override
  Future<WorkProfileOperationResult> clone(String packageName) async =>
      const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> launch(String packageName) async =>
      const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> setHidden(
    String packageName,
    bool hidden,
  ) async => const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> setSuspended(
    String packageName,
    bool suspended,
  ) async => const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> startProvisioning() async =>
      const WorkProfileOperationResult.success();
  @override
  Future<WorkProfileOperationResult> uninstall(String packageName) async =>
      const WorkProfileOperationResult.success();
}

void main() {
  testWidgets('provisioning success refreshes into ready state', (
    tester,
  ) async {
    final client = ProvisioningWorkProfileClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up work profile'), findsOneWidget);
    await tester.tap(find.text('Set up work profile'));
    await tester.pumpAndSettle();

    expect(find.text('Isolated apps'), findsOneWidget);
    expect(find.text('Remove work profile'), findsOneWidget);
  });

  testWidgets('ordinary personal app exposes confirmation-required state', (
    tester,
  ) async {
    final client = ReadyWorkProfileClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Android confirmation required'),
      findsOneWidget,
    );
  });

  testWidgets('ready app exposes work-profile controls and profile removal', (
    tester,
  ) async {
    final client = ReadyWorkProfileClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remove work profile'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Freeze'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);
  });

  testWidgets('profile removal requires destructive confirmation', (
    tester,
  ) async {
    final client = ReadyWorkProfileClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove work profile'));
    await tester.pumpAndSettle();

    expect(find.textContaining('all work-profile app data'), findsOneWidget);
    expect(client.destroyCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(client.destroyCalls, 1);
  });
}
