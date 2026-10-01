import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/startup_bootstrap.dart';

void main() {
  testWidgets('renders a non-secret frame before startup completes', (
    tester,
  ) async {
    final pending = Completer<Widget>();

    await tester.pumpWidget(StartupBootstrap(initialize: () => pending.future));
    await tester.pump();

    expect(find.byKey(const Key('startup-locked-shell')), findsOneWidget);
    expect(find.text('Calculator'), findsOneWidget);

    pending.complete(const MaterialApp(home: Text('ready')));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('startup failure stays locked and exposes retry', (tester) async {
    var attempts = 0;
    Future<Widget> initialize() async {
      attempts += 1;
      if (attempts == 1) throw StateError('synthetic secret-store failure');
      return const MaterialApp(home: Text('ready'));
    }

    await tester.pumpWidget(StartupBootstrap(initialize: initialize));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startup-locked-shell')), findsOneWidget);
    expect(find.text('Startup unavailable'), findsOneWidget);
    expect(find.textContaining('synthetic'), findsNothing);

    await tester.tap(find.byKey(const Key('startup-retry')));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('hung startup is bounded and remains non-secret', (tester) async {
    final pending = Completer<Widget>();

    await tester.pumpWidget(
      StartupBootstrap(
        initialize: () => pending.future,
        timeout: const Duration(milliseconds: 100),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(find.byKey(const Key('startup-locked-shell')), findsOneWidget);
    expect(find.text('Startup unavailable'), findsOneWidget);
    expect(find.byKey(const Key('startup-retry')), findsOneWidget);
  });

  testWidgets('initializer starts only after bootstrap frame exists', (
    tester,
  ) async {
    var shellVisibleWhenStarted = false;
    await tester.pumpWidget(
      StartupBootstrap(
        initialize: () async {
          shellVisibleWhenStarted = find
              .byKey(const Key('startup-locked-shell'))
              .evaluate()
              .isNotEmpty;
          return const MaterialApp(home: Text('ready'));
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(shellVisibleWhenStarted, isTrue);
  });

  testWidgets('bootstrap copy is cover-neutral on loading and failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupBootstrap(
        initialize: () async =>
            throw StateError('secret path /tmp/private key PIN'),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' ')
        .toLowerCase();
    expect(text, isNot(contains('vault')));
    expect(text, isNot(contains('pin')));
    expect(text, isNot(contains('key')));
    expect(text, isNot(contains('/tmp')));
  });

  test('startup stage runner times out an individual hung stage', () async {
    final runner = StartupStageRunner(
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      runner.run('settings', () => Completer<void>().future),
      throwsA(isA<TimeoutException>()),
    );
  });
}
