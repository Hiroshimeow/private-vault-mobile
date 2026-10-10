import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/apps/clone_profile_client.dart';
import 'package:private_vault_mobile/features/apps/clone_profile_home.dart';

class _FakeCloneClient implements CloneProfileClient {
  _FakeCloneClient({required this.apps, this.slotsAvailable = 2});

  List<CloneProfileApp> apps;
  int slotsAvailable;
  final List<String> launched = <String>[];
  final List<String> removed = <String>[];

  CloneProfileCapability get capability => CloneProfileCapability(
        state: CloneProfileCapabilityState.ready,
        slotsAvailable: slotsAvailable,
        slotsTotal: 2,
      );

  @override
  Future<CloneProfileCapability> getCapability() async => capability;

  @override
  Future<CloneProfileAppList> listApps() async =>
      CloneProfileAppList(capability: capability, apps: apps);

  @override
  Future<CloneProfileOperationResult> clone(String packageName) async =>
      CloneProfileOperationResult(capability: capability, ok: true);

  @override
  Future<CloneProfileOperationResult> launch(String instanceId) async {
    launched.add(instanceId);
    return CloneProfileOperationResult(capability: capability, ok: true);
  }

  @override
  Future<CloneProfileOperationResult> stop(String instanceId) async =>
      CloneProfileOperationResult(capability: capability, ok: true);

  @override
  Future<CloneProfileOperationResult> uninstall(String instanceId) async {
    removed.add(instanceId);
    return CloneProfileOperationResult(capability: capability, ok: true);
  }
}

CloneProfileApp _appWithInstances(int count) => CloneProfileApp(
      packageName: 'example.fixture',
      label: 'Fixture',
      instances: List<CloneInstance>.generate(
        count,
        (index) => CloneInstance(
          instanceId: 'slot$index:example.fixture',
          slot: index,
          state: 'ready',
        ),
      ),
    );

void main() {
  testWidgets('shows instance rows and keeps clone available until both slots are used',
      (tester) async {
    final client = _FakeCloneClient(apps: <CloneProfileApp>[_appWithInstances(1)], slotsAvailable: 1);
    await tester.pumpWidget(MaterialApp(home: CloneProfileHome(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Virtual clones'), findsOneWidget);
    expect(find.text('Instance 1'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Clone'), findsOneWidget);
    expect(find.textContaining('Shizuku'), findsNothing);
    expect(find.textContaining('profile.CLONE'), findsNothing);

    final launch = find.byKey(const ValueKey<String>('clone-launch-slot0:example.fixture'));
    tester.widget<IconButton>(launch).onPressed!();
    await tester.pumpAndSettle();
    expect(client.launched, <String>['slot0:example.fixture']);
  });

  testWidgets('two instances disable a third clone and remove the selected instance',
      (tester) async {
    final client = _FakeCloneClient(apps: <CloneProfileApp>[_appWithInstances(2)], slotsAvailable: 0);
    await tester.pumpWidget(MaterialApp(home: CloneProfileHome(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Instance 1'), findsOneWidget);
    expect(find.text('Instance 2'), findsOneWidget);
    final cloneButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Clone'));
    expect(cloneButton.onPressed, isNull);

    final remove = find.byKey(const ValueKey<String>('clone-remove-slot1:example.fixture'));
    tester.widget<IconButton>(remove).onPressed!();
    await tester.pumpAndSettle();
    expect(client.removed, <String>['slot1:example.fixture']);
  });
}
