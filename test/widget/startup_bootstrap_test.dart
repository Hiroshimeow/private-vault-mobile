import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/startup_bootstrap.dart';

void main() {
  testWidgets('renders a non-secret frame before startup completes', (tester) async {
    final pending = Completer<Widget>();

    await tester.pumpWidget(StartupBootstrap(initialize: () => pending.future));
    await tester.pump();

    expect(find.byKey(const Key('startup-locked-shell')), findsOneWidget);
    expect(find.text('Private Vault'), findsOneWidget);

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
}
