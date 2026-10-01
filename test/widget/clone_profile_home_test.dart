import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/apps/clone_profile_client.dart';
import 'package:private_vault_mobile/features/apps/clone_profile_home.dart';

class _FakeCloneClient implements CloneProfileClient {
  _FakeCloneClient({
    required this.listResult,
    this.privilegeGranted = false,
    this.cloneResult,
    this.launchResult,
    this.uninstallResult,
    this.throwOnClone = false,
  });

  CloneProfileAppList listResult;
  bool privilegeGranted;
  CloneProfileOperationResult? cloneResult;
  CloneProfileOperationResult? launchResult;
  CloneProfileOperationResult? uninstallResult;
  bool throwOnClone;

  int listCalls = 0;
  int privilegeCalls = 0;
  int cloneCalls = 0;
  int launchCalls = 0;
  int uninstallCalls = 0;
  String? lastPackage;

  @override
  Future<CloneProfileCapability> getCapability() async => listResult.capability;

  @override
  Future<bool> requestPrivilege() async {
    privilegeCalls += 1;
    return privilegeGranted;
  }

  @override
  Future<CloneProfileAppList> listApps() async {
    listCalls += 1;
    return listResult;
  }

  @override
  Future<CloneProfileOperationResult> clone(String packageName) async {
    cloneCalls += 1;
    lastPackage = packageName;
    if (throwOnClone) {
      throw StateError('boom');
    }
    return cloneResult ??
        CloneProfileOperationResult(
          capability: listResult.capability,
          ok: false,
        );
  }

  @override
  Future<CloneProfileOperationResult> launch(String packageName) async {
    launchCalls += 1;
    lastPackage = packageName;
    return launchResult ??
        CloneProfileOperationResult(
          capability: listResult.capability,
          ok: false,
        );
  }

  @override
  Future<CloneProfileOperationResult> uninstall(String packageName) async {
    uninstallCalls += 1;
    lastPackage = packageName;
    return uninstallResult ??
        CloneProfileOperationResult(
          capability: listResult.capability,
          ok: false,
        );
  }
}

const _ready = CloneProfileCapability(
  state: CloneProfileCapabilityState.ready,
  userId: 10,
);

const _alphaUncloned = CloneProfileApp(
  packageName: 'com.example.alpha',
  label: 'Alpha',
  cloned: false,
);

const _alphaCloned = CloneProfileApp(
  packageName: 'com.example.alpha',
  label: 'Alpha',
  cloned: true,
);

Future<void> _pump(WidgetTester tester, CloneProfileClient client) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: CloneProfileHome(client: client)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('privilege required authorizes once and refreshes on grant', (
    tester,
  ) async {
    final client = _FakeCloneClient(
      listResult: const CloneProfileAppList(
        capability: CloneProfileCapability(
          state: CloneProfileCapabilityState.privilegeRequired,
        ),
        apps: [],
      ),
      privilegeGranted: true,
    );

    await _pump(tester, client);
    expect(find.text('Authorize Shizuku'), findsOneWidget);

    await tester.tap(find.text('Authorize Shizuku'));
    await tester.pumpAndSettle();

    expect(client.privilegeCalls, 1);
    expect(client.listCalls, 2);
    expect(find.textContaining('granted'), findsOneWidget);
  });

  testWidgets('unsupported and conflicting states expose no clone action', (
    tester,
  ) async {
    for (final capability in <CloneProfileCapability>[
      const CloneProfileCapability(
        state: CloneProfileCapabilityState.cloneProfileUnsupportedByOem,
        message: 'unsupported',
      ),
      const CloneProfileCapability(
        state: CloneProfileCapabilityState.conflictingExternalCloneProfile,
        message: 'external clone',
      ),
    ]) {
      final client = _FakeCloneClient(
        listResult: CloneProfileAppList(capability: capability, apps: const []),
      );
      await _pump(tester, client);
      expect(find.text('Clone'), findsNothing);
      expect(find.text('Authorize Shizuku'), findsNothing);
    }
  });

  testWidgets(
    'operation failure remains stable and exposes no fallback action',
    (tester) async {
      final client = _FakeCloneClient(
        listResult: const CloneProfileAppList(
          capability: CloneProfileCapability(
            state: CloneProfileCapabilityState.operationFailed,
            message: 'backend failed',
          ),
          apps: [],
        ),
      );

      await _pump(tester, client);

      expect(find.text('Clone backend unavailable'), findsOneWidget);
      expect(find.text('backend failed'), findsOneWidget);
      expect(find.textContaining('Work Profile'), findsNothing);
    },
  );

  testWidgets('ready uncloned app clones exact package once', (tester) async {
    final client = _FakeCloneClient(
      listResult: const CloneProfileAppList(
        capability: _ready,
        apps: [_alphaUncloned],
      ),
      cloneResult: const CloneProfileOperationResult(
        capability: _ready,
        ok: true,
      ),
    );

    await _pump(tester, client);
    await tester.tap(find.text('Clone'));
    await tester.pumpAndSettle();

    expect(client.cloneCalls, 1);
    expect(client.lastPackage, 'com.example.alpha');
  });

  testWidgets('ready cloned app launches and removes exact package', (
    tester,
  ) async {
    final client = _FakeCloneClient(
      listResult: const CloneProfileAppList(
        capability: _ready,
        apps: [_alphaCloned],
      ),
      launchResult: const CloneProfileOperationResult(
        capability: _ready,
        ok: true,
      ),
      uninstallResult: const CloneProfileOperationResult(
        capability: _ready,
        ok: true,
      ),
    );

    await _pump(tester, client);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(client.launchCalls, 1);
    expect(client.lastPackage, 'com.example.alpha');

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove clone instance'));
    await tester.pumpAndSettle();
    expect(client.uninstallCalls, 1);
    expect(client.lastPackage, 'com.example.alpha');
  });

  testWidgets('unexpected client throw resets in-flight state for retry', (
    tester,
  ) async {
    final client = _FakeCloneClient(
      listResult: const CloneProfileAppList(
        capability: _ready,
        apps: [_alphaUncloned],
      ),
      throwOnClone: true,
    );

    await _pump(tester, client);
    await tester.tap(find.text('Clone'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Clone operation failed'), findsOneWidget);
    expect(find.text('Clone'), findsOneWidget);

    client.throwOnClone = false;
    client.cloneResult = const CloneProfileOperationResult(
      capability: _ready,
      ok: false,
    );
    await tester.tap(find.text('Clone'));
    await tester.pumpAndSettle();
    expect(client.cloneCalls, 2);
  });

  testWidgets('privilege request exception is contained', (tester) async {
    final client = _ThrowPrivilegeClient();

    await _pump(tester, client);
    await tester.tap(find.text('Authorize Shizuku'));
    await tester.pumpAndSettle();

    expect(find.textContaining('authorization failed'), findsOneWidget);
    expect(find.text('Authorize Shizuku'), findsOneWidget);
  });
}

class _ThrowPrivilegeClient implements CloneProfileClient {
  @override
  Future<CloneProfileCapability> getCapability() async =>
      const CloneProfileCapability(
        state: CloneProfileCapabilityState.privilegeRequired,
      );

  @override
  Future<CloneProfileAppList> listApps() async => const CloneProfileAppList(
    capability: CloneProfileCapability(
      state: CloneProfileCapabilityState.privilegeRequired,
    ),
    apps: [],
  );

  @override
  Future<bool> requestPrivilege() async => throw StateError('boom');

  @override
  Future<CloneProfileOperationResult> clone(String packageName) =>
      throw UnimplementedError();

  @override
  Future<CloneProfileOperationResult> launch(String packageName) =>
      throw UnimplementedError();

  @override
  Future<CloneProfileOperationResult> uninstall(String packageName) =>
      throw UnimplementedError();
}
