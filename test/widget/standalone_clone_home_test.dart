import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/apps/standalone_clone_client.dart';
import 'package:private_vault_mobile/features/apps/standalone_clone_home.dart';

class _FakeStandaloneCloneClient implements StandaloneCloneClient {
  _FakeStandaloneCloneClient({
    this.buildResult = const StandaloneCloneBuildResult(
      status: 'cancelled',
      supported: false,
      blockers: <String>[],
      warnings: <String>[],
    ),
    List<StandaloneCloneRecord>? records,
    this.listCompleter,
    this.removeStatus = 'removed',
  }) : records = records ?? <StandaloneCloneRecord>[];

  StandaloneCloneBuildResult buildResult;
  final List<StandaloneCloneRecord> records;
  final Completer<List<StandaloneCloneRecord>>? listCompleter;
  final String removeStatus;
  final List<String> installed = <String>[];
  final List<String> launched = <String>[];
  final List<String> removed = <String>[];

  @override
  Future<StandaloneCloneEnvironment> getEnvironment() async =>
      const StandaloneCloneEnvironment(
        route: 'standalone_repackage',
        sdkInt: 36,
        canRequestPackageInstalls: true,
        maxSourceBytes: 512 * 1024 * 1024,
      );

  @override
  Future<List<StandaloneCloneRecord>> listClones() async {
    if (listCompleter != null) return listCompleter!.future;
    return List<StandaloneCloneRecord>.unmodifiable(records);
  }

  @override
  Future<StandaloneCloneBuildResult> pickAndBuildClone() async {
    final clone = buildResult.clone;
    if (buildResult.status == 'artifact_ready' && clone != null) {
      records
        ..removeWhere((record) => record.cloneId == clone.cloneId)
        ..add(clone);
    }
    return buildResult;
  }

  @override
  Future<String> installClone(String cloneId) async {
    installed.add(cloneId);
    return 'install_requested';
  }

  @override
  Future<String> launchClone(String cloneId) async {
    launched.add(cloneId);
    return 'launched';
  }

  @override
  Future<String> removeClone(String cloneId) async {
    removed.add(cloneId);
    if (removeStatus == 'removed') {
      records.removeWhere((record) => record.cloneId == cloneId);
    }
    return removeStatus;
  }
}

const _installedClone = StandaloneCloneRecord(
  cloneId: 'clone-remove',
  sourcePackage: 'com.example.remove',
  clonePackage: 'com.example.remove.pvclone.c123',
  versionCode: 7,
  versionName: '7.0',
  installStatus: 'installed',
);

Widget _host(StandaloneCloneClient client) => MaterialApp(
  home: Scaffold(body: StandaloneCloneHome(client: client)),
);

Future<void> _tapRemove(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remove clone'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows loading until clone inventory resolves', (tester) async {
    final completer = Completer<List<StandaloneCloneRecord>>();
    final client = _FakeStandaloneCloneClient(listCompleter: completer);

    await tester.pumpWidget(_host(client));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const <StandaloneCloneRecord>[]);
    await tester.pumpAndSettle();

    expect(find.text('No clone-lab artifacts yet.'), findsOneWidget);
  });

  testWidgets('unsupported APK shows blocker and never exposes install', (
    tester,
  ) async {
    final client = _FakeStandaloneCloneClient(
      buildResult: const StandaloneCloneBuildResult(
        status: 'unsupported',
        supported: false,
        blockers: <String>['native_libs_unsupported'],
        warnings: <String>[],
      ),
    );

    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('standalone-clone-pick-apk')));
    await tester.pumpAndSettle();

    expect(find.textContaining('native_libs_unsupported'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(client.installed, isEmpty);
  });

  testWidgets('built clone surfaces deep link compatibility warning', (
    tester,
  ) async {
    const clone = StandaloneCloneRecord(
      cloneId: 'clone-warning',
      sourcePackage: 'com.example.links',
      clonePackage: 'com.example.links.pvclone.c123',
      versionCode: 1,
      versionName: '1.0',
      installStatus: 'artifact_ready',
      compatibilityWarnings: <String>['deep_link_degraded'],
    );
    final client = _FakeStandaloneCloneClient(
      buildResult: const StandaloneCloneBuildResult(
        status: 'artifact_ready',
        supported: true,
        blockers: <String>[],
        warnings: <String>['deep_link_degraded'],
        clone: clone,
      ),
    );

    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('standalone-clone-pick-apk')));
    await tester.pumpAndSettle();

    expect(find.textContaining('deep_link_degraded'), findsWidgets);
  });

  testWidgets('built artifact appears and install action dispatches clone id', (
    tester,
  ) async {
    const clone = StandaloneCloneRecord(
      cloneId: 'clone-123',
      sourcePackage: 'com.example.source',
      clonePackage: 'com.example.source.pvclone.c123',
      versionCode: 42,
      versionName: '4.2',
      installStatus: 'artifact_ready',
    );
    final client = _FakeStandaloneCloneClient(
      buildResult: const StandaloneCloneBuildResult(
        status: 'artifact_ready',
        supported: true,
        blockers: <String>[],
        warnings: <String>[],
        clone: clone,
      ),
    );

    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('standalone-clone-pick-apk')));
    await tester.pumpAndSettle();

    expect(find.text('com.example.source'), findsOneWidget);
    expect(
      find.textContaining('com.example.source.pvclone.c123'),
      findsOneWidget,
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install / update'));
    await tester.pumpAndSettle();

    expect(client.installed, <String>['clone-123']);
    expect(find.textContaining('Android installer opened'), findsOneWidget);
  });

  testWidgets('confirmed uninstall removes clone card after native cleanup', (
    tester,
  ) async {
    final client = _FakeStandaloneCloneClient(records: <StandaloneCloneRecord>[_installedClone]);

    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();
    expect(find.text('com.example.remove'), findsOneWidget);

    await _tapRemove(tester);

    expect(client.removed, <String>['clone-remove']);
    expect(find.text('com.example.remove'), findsNothing);
    expect(find.text('No clone-lab artifacts yet.'), findsOneWidget);
    expect(find.textContaining('Clone artifact removed'), findsOneWidget);
  });

  testWidgets('cancelled uninstall preserves clone card and artifact record', (
    tester,
  ) async {
    final client = _FakeStandaloneCloneClient(
      records: <StandaloneCloneRecord>[_installedClone],
      removeStatus: 'uninstall_cancelled',
    );

    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();
    await _tapRemove(tester);

    expect(client.removed, <String>['clone-remove']);
    expect(find.text('com.example.remove'), findsOneWidget);
    expect(find.textContaining('cancelled'), findsOneWidget);
    expect(find.textContaining('artifact was retained'), findsOneWidget);
  });

  testWidgets('failed uninstall preserves clone card and artifact record', (
    tester,
  ) async {
    final client = _FakeStandaloneCloneClient(
      records: <StandaloneCloneRecord>[_installedClone],
      removeStatus: 'uninstall_failed',
    );

    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();
    await _tapRemove(tester);

    expect(client.removed, <String>['clone-remove']);
    expect(find.text('com.example.remove'), findsOneWidget);
    expect(find.textContaining('did not complete'), findsOneWidget);
    expect(find.textContaining('artifact was retained'), findsOneWidget);
  });
}
