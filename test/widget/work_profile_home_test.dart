import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/apps/vault_shuttle_service.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_home.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

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
  Future<WorkProfileOperationResult> requestQuietModeDisabled() async =>
      const WorkProfileOperationResult.success();

  @override
  Future<PickedWorkDocument?> pickWorkDocument() async => null;

  @override
  Future<WorkProfileOperationResult> openStore(String packageName) async =>
      const WorkProfileOperationResult.success();

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

class RecordingVaultShuttle implements VaultShuttle {
  RecordingVaultShuttle(this.items);

  final List<VaultItem> items;
  int purgeCalls = 0;
  String? sharedPackage;
  VaultItem? sharedItem;

  @override
  Future<List<VaultItem>> listVaultItems() async => items;

  @override
  Future<void> purgeStagedPlaintext() async {
    purgeCalls += 1;
  }

  @override
  Future<void> shareToIsolatedApp({
    required VaultItem item,
    required String packageName,
  }) async {
    sharedItem = item;
    sharedPackage = packageName;
  }
}

class ReadyWorkProfileClient implements WorkProfileClient {
  int destroyCalls = 0;
  int cloneCalls = 0;
  int launchCalls = 0;
  int capabilityCalls = 0;
  int listCalls = 0;
  int openStoreCalls = 0;
  String? lastPackage;

  @override
  Future<WorkProfileCapability> getCapability() async {
    capabilityCalls += 1;
    return const WorkProfileCapability(
      supported: true,
      provisioningAllowed: false,
      profileState: WorkProfileState.ready,
    );
  }

  @override
  Future<List<ManagedAppState>> listApps() async {
    listCalls += 1;
    return const [
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
  }

  @override
  Future<WorkProfileOperationResult> requestQuietModeDisabled() async =>
      const WorkProfileOperationResult.success();

  @override
  Future<PickedWorkDocument?> pickWorkDocument() async => null;

  @override
  Future<WorkProfileOperationResult> openStore(String packageName) async {
    openStoreCalls += 1;
    lastPackage = packageName;
    return const WorkProfileOperationResult.success();
  }

  @override
  Future<WorkProfileOperationResult> destroyProfile() async {
    destroyCalls += 1;
    return const WorkProfileOperationResult.success();
  }

  @override
  Future<WorkProfileOperationResult> clone(String packageName) async {
    cloneCalls += 1;
    lastPackage = packageName;
    return const WorkProfileOperationResult.success();
  }

  @override
  Future<WorkProfileOperationResult> launch(String packageName) async {
    launchCalls += 1;
    lastPackage = packageName;
    return const WorkProfileOperationResult.success();
  }

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

class QuietRecoveryWorkProfileClient extends ReadyWorkProfileClient {
  QuietRecoveryWorkProfileClient({this.recoveryGate});

  final Completer<WorkProfileOperationResult>? recoveryGate;
  WorkProfileState state = WorkProfileState.quiet;
  int recoveryCalls = 0;

  @override
  Future<WorkProfileCapability> getCapability() async {
    capabilityCalls += 1;
    return WorkProfileCapability(
      supported: true,
      provisioningAllowed: false,
      profileState: state,
    );
  }

  @override
  Future<List<ManagedAppState>> listApps() async {
    if (state != WorkProfileState.ready) {
      listCalls += 1;
      return const [];
    }
    return super.listApps();
  }

  @override
  Future<WorkProfileOperationResult> requestQuietModeDisabled() async {
    recoveryCalls += 1;
    final result = recoveryGate == null
        ? const WorkProfileOperationResult.success()
        : await recoveryGate!.future;
    if (result.ok) state = WorkProfileState.ready;
    return result;
  }
}

class StoreFallbackWorkProfileClient extends ReadyWorkProfileClient {
  @override
  Future<WorkProfileOperationResult> clone(String packageName) async {
    cloneCalls += 1;
    lastPackage = packageName;
    return const WorkProfileOperationResult.failure(
      WorkProfileErrorCode.storeFallbackRequired,
      message: 'Install this app from the Work Profile store.',
    );
  }
}

class IconWorkProfileClient extends ReadyWorkProfileClient {
  IconWorkProfileClient(this.iconBytes);

  final Uint8List iconBytes;

  @override
  Future<List<ManagedAppState>> listApps() async {
    listCalls += 1;
    return [
      ManagedAppState(
        packageName: 'icon.app',
        label: 'Icon app',
        presentPersonal: true,
        presentWork: false,
        launchableWork: false,
        systemApp: false,
        suspended: false,
        hidden: false,
        cloneEligibility: CloneEligibility.eligible,
        installerActionRequired: true,
        iconBytes: iconBytes,
      ),
    ];
  }
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

    expect(find.text('Enable isolated apps'), findsOneWidget);
    await tester.tap(find.text('Enable isolated apps'));
    await tester.pumpAndSettle();

    expect(find.text('Isolated apps'), findsOneWidget);
    expect(find.text('Remove work profile'), findsOneWidget);
  });

  testWidgets('personal view exposes one-tap clone action', (tester) async {
    final client = ReadyWorkProfileClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Isolated'), findsOneWidget);
    expect(find.text('Personal only'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Clone'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Clone'));
    await tester.pumpAndSettle();

    expect(client.cloneCalls, 1);
    expect(client.lastPackage, 'personal.app');
  });

  testWidgets('quiet recovery is single-flight and refreshes to ready', (
    tester,
  ) async {
    final gate = Completer<WorkProfileOperationResult>();
    final client = QuietRecoveryWorkProfileClient(recoveryGate: gate);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn on Work Profile'), findsOneWidget);
    await tester.tap(find.text('Turn on Work Profile'));
    await tester.tap(find.text('Turn on Work Profile'));
    expect(client.recoveryCalls, 1);

    gate.complete(const WorkProfileOperationResult.success());
    await tester.pumpAndSettle();

    expect(client.recoveryCalls, 1);
    expect(find.text('Turn on Work Profile'), findsNothing);
    expect(find.text('Isolated apps'), findsOneWidget);
  });

  testWidgets('blocked clone exposes managed-profile Store action', (
    tester,
  ) async {
    final client = StoreFallbackWorkProfileClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clone'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Store'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Store'));
    await tester.pumpAndSettle();

    expect(client.openStoreCalls, 1);
    expect(client.lastPackage, 'personal.app');
    expect(find.widgetWithText(FilledButton, 'Store'), findsOneWidget);
  });

  testWidgets('managed app renders a bounded native icon payload', (
    tester,
  ) async {
    final icon = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final client = IconWorkProfileClient(icon);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Icon app'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt managed app icon falls back without failing inventory', (
    tester,
  ) async {
    final client = IconWorkProfileClient(Uint8List.fromList([1, 2, 3]));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Icon app'), findsOneWidget);
    expect(find.byIcon(Icons.apps_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('isolated view opens app by tapping its row', (tester) async {
    final client = ReadyWorkProfileClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Isolated'));
    await tester.pumpAndSettle();

    expect(find.text('Example'), findsOneWidget);
    expect(find.text('Personal only'), findsNothing);

    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();

    expect(client.launchCalls, 1);
    expect(client.lastPackage, 'example.app');
  });

  testWidgets('isolated app exposes lifecycle controls and profile removal', (
    tester,
  ) async {
    final client = ReadyWorkProfileClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkProfileHome(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Isolated'));
    await tester.pumpAndSettle();
    expect(find.text('Remove work profile'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Freeze'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);
  });

  testWidgets('isolated app can receive a selected Vault item', (tester) async {
    final client = ReadyWorkProfileClient();
    final item = VaultItem(
      id: 'vault-image',
      kind: VaultItemKind.image,
      createdAt: DateTime.utc(2026, 9, 21, 3, 0),
    );
    final shuttle = RecordingVaultShuttle([item]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkProfileHome(client: client, vaultShuttle: shuttle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Isolated'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share vault file'));
    await tester.pumpAndSettle();

    expect(find.text('Share from Vault'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('vault-shuttle-vault-image')));
    await tester.pumpAndSettle();

    expect(shuttle.sharedPackage, 'example.app');
    expect(shuttle.sharedItem?.id, 'vault-image');
    expect(
      find.textContaining('Vault item shared with Example'),
      findsOneWidget,
    );
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
