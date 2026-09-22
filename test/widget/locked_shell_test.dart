import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/features/apps/vault_shuttle_service.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/cover/calculator_cover.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/legacy_v1_migration.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class FakeBiometricUnlock implements BiometricUnlock {
  FakeBiometricUnlock({this.available = true, this.accepted = true});

  final bool available;
  final bool accepted;
  int authenticateCalls = 0;
  int cancelCalls = 0;

  @override
  Future<bool> authenticate() async {
    authenticateCalls += 1;
    return accepted;
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }
}

class BoundaryVaultRepository implements VaultRepository {
  BoundaryVaultRepository() {
    final note = VaultItem(
      id: 'note-fixture',
      kind: VaultItemKind.note,
      createdAt: DateTime.utc(2026, 9, 18),
    );
    final document = VaultItem(
      id: 'document-fixture',
      kind: VaultItemKind.document,
      createdAt: DateTime.utc(2026, 9, 18, 1),
    );
    items.addAll([note, document]);
    bytesById[note.id] = Uint8List.fromList('Secret preview text'.codeUnits);
    bytesById[document.id] = Uint8List.fromList([1, 2, 3]);
  }

  final items = <VaultItem>[];
  final bytesById = <String, Uint8List>{};
  int listCalls = 0;

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    final item = VaultItem(
      id: 'added-${items.length}',
      kind: kind,
      createdAt: DateTime.utc(2026, 9, 18, 2),
    );
    items.add(item);
    bytesById[item.id] = Uint8List.fromList(bytes);
    return item;
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((item) => item.id == id);
    bytesById.remove(id);
  }

  @override
  Future<List<VaultItem>> list() async {
    listCalls += 1;
    return List.unmodifiable(items);
  }

  @override
  Future<Uint8List> readBytes(String id) async => bytesById[id]!;
}

MediaVaultService boundaryMedia(BoundaryVaultRepository repository) {
  return MediaVaultService(
    repository: repository,
    pickImport: () async => null,
    capturePhoto: () async => null,
    saveExport: (_, _) async => true,
  );
}

class RecordingVaultShuttle implements VaultShuttle {
  int purgeCalls = 0;

  @override
  Future<List<VaultItem>> listVaultItems() async => const [];

  @override
  Future<void> purgeStagedPlaintext() async {
    purgeCalls += 1;
  }

  @override
  Future<void> shareToIsolatedApp({
    required VaultItem item,
    required String packageName,
  }) async {}
}

class CountingSettingsStorage implements SettingsStorage {
  int writes = 0;
  String? encoded;

  @override
  Future<String?> read() async => encoded;

  @override
  Future<void> write(String value) async {
    writes += 1;
    encoded = value;
  }
}

class FakeUnlockService implements UnlockService, PinLengthAwareUnlockService {
  FakeUnlockService({this.pin = '482951'});

  final String pin;

  @override
  Future<bool> verify(String candidate) async => candidate == pin;

  @override
  Future<int?> configuredPinLength() async => pin.length;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<void> configure(String pin) async {}
}

class DeferredManualUnlockService
    implements UnlockService, PinLengthAwareUnlockService {
  final Completer<bool> verification = Completer<bool>();
  int verifyCalls = 0;

  @override
  Future<void> configure(String pin) async {}

  @override
  Future<int?> configuredPinLength() async => 4;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) {
    verifyCalls += 1;
    return verification.future;
  }
}

class GenerationAwareTestVaultRepository
    implements TransactionalPinSessionVaultRepository {
  GenerationAwareTestVaultRepository({
    this.failOpen = false,
    this.switchOutcome = PinSessionSwitchOutcome.active,
  });

  final bool failOpen;
  final PinSessionSwitchOutcome switchOutcome;
  final List<int> clearGenerationCalls = <int>[];
  int _generation = 7;
  bool _hasOpenSession = false;

  @override
  bool get hasOpenSession => _hasOpenSession;

  @override
  int get sessionGeneration => _generation;

  @override
  Future<void> openSession(String pin) async {
    await openSessionWithGeneration(pin);
  }

  @override
  Future<int> openSessionWithGeneration(String pin) async {
    if (failOpen) throw StateError('synthetic open failure');
    _hasOpenSession = true;
    _generation += 1;
    return _generation;
  }

  @override
  void clearSessionIfGeneration(int generation) {
    clearGenerationCalls.add(generation);
    if (generation != _generation) return;
    _hasOpenSession = false;
    _generation += 1;
  }

  @override
  void clearSession() {
    _hasOpenSession = false;
    _generation += 1;
  }

  @override
  Future<PinSessionSwitchOutcome> switchSession(
    String pin,
    Future<void> Function() commitIdentity,
  ) async {
    await commitIdentity();
    if (switchOutcome == PinSessionSwitchOutcome.active) {
      _hasOpenSession = true;
      _generation += 1;
    } else {
      _hasOpenSession = false;
      _generation += 1;
    }
    return switchOutcome;
  }

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async => VaultItem(
    id: 'test-item',
    kind: kind,
    createdAt: DateTime.utc(2026, 9, 22),
  );

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<VaultItem>> list() async => const [];

  @override
  Future<Uint8List> readBytes(String id) async => Uint8List(0);
}

Future<void> pumpCalculatorCover(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(home: CalculatorCover()),
    ),
  );
  await tester.pump();
}

void main() {
  for (final width in <double>[360, 390, 412]) {
    testWidgets('calculator keypad stays aligned and reachable at $width px', (
      tester,
    ) async {
      await pumpCalculatorCover(tester, size: Size(width, 800));

      const labels = <String>[
        '7',
        '8',
        '9',
        '÷',
        '4',
        '5',
        '6',
        '×',
        '1',
        '2',
        '3',
        '-',
        'C',
        '0',
        '=',
        '+',
      ];
      final rects = <Rect>[];
      for (final label in labels) {
        final finder = find.byKey(Key('calculator-key-$label'));
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        rects.add(rect);
      }
      for (var row = 0; row < 4; row++) {
        final rowRects = rects.skip(row * 4).take(4).toList();
        expect(rowRects.map((rect) => rect.center.dy).toSet().length, 1);
      }
      for (var column = 0; column < 4; column++) {
        final centers = <double>[
          for (var row = 0; row < 4; row++) rects[(row * 4) + column].center.dx,
        ];
        expect(centers.toSet().length, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('calculator remains contained at 360 px and 1.3 text scale', (
    tester,
  ) async {
    await pumpCalculatorCover(
      tester,
      size: const Size(360, 800),
      textScale: 1.3,
    );

    final displayRect = tester.getRect(
      find.byKey(const Key('calculator-display')),
    );
    expect(displayRect.left, greaterThanOrEqualTo(0));
    expect(displayRect.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculator cover exposes no private workspace terminology', (
    tester,
  ) async {
    await pumpCalculatorCover(tester, size: const Size(390, 800));

    for (final forbidden in <String>[
      'Vault',
      'Private',
      'Browser',
      'Settings',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  testWidgets('calculator remains usable in a compact landscape viewport', (
    tester,
  ) async {
    await pumpCalculatorCover(tester, size: const Size(800, 360));

    for (final label in <String>[
      '7',
      '8',
      '9',
      '÷',
      '4',
      '5',
      '6',
      '×',
      '1',
      '2',
      '3',
      '-',
      'C',
      '0',
      '=',
      '+',
    ]) {
      final rect = tester.getRect(
        find.byKey(Key(<String>['calculator-key-', label].join())),
      );
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.bottom, lessThanOrEqualTo(360));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculator display scrolls long values instead of clipping', (
    tester,
  ) async {
    await pumpCalculatorCover(
      tester,
      size: const Size(360, 800),
      textScale: 1.3,
    );

    for (var index = 0; index < 14; index++) {
      await tester.tap(find.byKey(const Key('calculator-key-9')));
    }
    await tester.pump();

    final viewport = tester.getRect(
      find.byKey(const Key('calculator-display-viewport')),
    );
    expect(viewport.left, greaterThanOrEqualTo(0));
    expect(viewport.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculator operators expose accessible semantic labels', (
    tester,
  ) async {
    await pumpCalculatorCover(tester, size: const Size(390, 800));

    expect(find.bySemanticsLabel('Divide'), findsOneWidget);
    expect(find.bySemanticsLabel('Multiply'), findsOneWidget);
    expect(find.bySemanticsLabel('Subtract'), findsOneWidget);
    expect(find.bySemanticsLabel('Add'), findsOneWidget);
    expect(find.bySemanticsLabel('Equals'), findsOneWidget);
    expect(find.bySemanticsLabel('Clear'), findsOneWidget);
  });

  testWidgets('calculator key roles use distinct themed surfaces', (
    tester,
  ) async {
    await pumpCalculatorCover(tester, size: const Size(390, 800));

    Color? backgroundFor(String label) {
      final button = tester.widget<FilledButton>(
        find.byKey(Key(<String>['calculator-key-', label].join())),
      );
      return button.style?.backgroundColor?.resolve(<WidgetState>{});
    }

    final number = backgroundFor('7');
    final operator = backgroundFor('+');
    final destructive = backgroundFor('C');
    final equals = backgroundFor('=');
    expect({number, operator, destructive, equals}.length, 4);
  });

  testWidgets(
    'locked launch renders calculator cover and no secret workspace text',
    (tester) async {
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: LockController(),
          unlockService: FakeUnlockService(),
        ),
      );

      expect(find.text('Calculator'), findsOneWidget);
      expect(find.byTooltip('Lock now'), findsNothing);
      expect(find.text('Browser'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    },
  );

  testWidgets('calculator cover performs addition while locked', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '2'));
    await tester.tap(find.widgetWithText(FilledButton, '+'));
    await tester.tap(find.widgetWithText(FilledButton, '3'));
    await tester.tap(find.widgetWithText(FilledButton, '='));
    await tester.pump();

    final display = tester.widget<Text>(
      find.byKey(const Key('calculator-display')),
    );
    expect(display.data, '5');
  });

  testWidgets('valid PIN unlocks and panic returns to cover', (tester) async {
    final lock = LockController();
    await tester.pumpWidget(
      PrivateVaultApp(lockController: lock, unlockService: FakeUnlockService()),
    );
    await tester.pumpAndSettle();

    for (final digit in '482951'.split('')) {
      await tester.tap(find.byKey(Key('calculator-key-$digit')));
    }
    final trigger = find.byKey(const Key('calculator-key-8'));
    final gesture = await tester.startGesture(tester.getCenter(trigger));
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Lock now'), findsOneWidget);

    lock.panic();
    await tester.pumpAndSettle();

    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('calculator PIN silently triggers biometric and unlocks', (
    tester,
  ) async {
    final biometric = FakeBiometricUnlock();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(pin: '0000'),
        biometricUnlock: biometric,
        initialSettings: const AppSettings.defaults().copyWith(
          biometricsEnabled: true,
        ),
      ),
    );

    for (var index = 0; index < 4; index++) {
      await tester.tap(find.byKey(const Key('calculator-key-0')));
    }
    final equals = find.byKey(const Key('calculator-key-='));
    final gesture = await tester.startGesture(tester.getCenter(equals));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(biometric.authenticateCalls, 1);
    expect(find.byTooltip('Lock now'), findsOneWidget);
    expect(find.text('Enter PIN'), findsNothing);
    expect(find.text('Use biometrics'), findsNothing);
  });

  testWidgets('wrong calculator PIN reveals nothing and skips biometric', (
    tester,
  ) async {
    final biometric = FakeBiometricUnlock();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(pin: '0000'),
        biometricUnlock: biometric,
        initialSettings: const AppSettings.defaults().copyWith(
          biometricsEnabled: true,
        ),
      ),
    );

    for (final digit in ['0', '0', '0', '1']) {
      await tester.tap(find.byKey(Key('calculator-key-$digit')));
    }
    final equals = find.byKey(const Key('calculator-key-='));
    final gesture = await tester.startGesture(tester.getCenter(equals));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(biometric.authenticateCalls, 0);
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Enter PIN'), findsNothing);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('biometric rejection keeps concealed calculator locked', (
    tester,
  ) async {
    final biometric = FakeBiometricUnlock(accepted: false);
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(pin: '0000'),
        biometricUnlock: biometric,
        initialSettings: const AppSettings.defaults().copyWith(
          biometricsEnabled: true,
        ),
      ),
    );

    for (var index = 0; index < 4; index++) {
      await tester.tap(find.byKey(const Key('calculator-key-0')));
    }
    final equals = find.byKey(const Key('calculator-key-='));
    final gesture = await tester.startGesture(tester.getCenter(equals));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(biometric.authenticateCalls, 1);
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('fallback unlock requires PIN before biometric', (tester) async {
    final biometric = FakeBiometricUnlock();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(pin: '0000'),
        biometricUnlock: biometric,
        initialSettings: const AppSettings.defaults().copyWith(
          biometricsEnabled: true,
        ),
      ),
    );

    for (var index = 0; index < 4; index++) {
      await tester.tap(find.byKey(const Key('calculator-key-0')));
    }
    final equals = find.byKey(const Key('calculator-key-='));
    final gesture = await tester.startGesture(tester.getCenter(equals));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(biometric.authenticateCalls, 1);
    expect(find.byTooltip('Lock now'), findsOneWidget);
  });

  testWidgets('visited Vault state survives tab switches', (tester) async {
    final lock = LockController();
    final repository = BoundaryVaultRepository();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        vaultRepository: repository,
        mediaService: boundaryMedia(repository),
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    expect(repository.listCalls, 1);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vault').last);
    await tester.pumpAndSettle();

    expect(repository.listCalls, 1);
  });

  testWidgets('visited Settings state survives tab switches', (tester) async {
    final lock = LockController();
    await tester.pumpWidget(
      PrivateVaultApp(lockController: lock, unlockService: FakeUnlockService()),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final settingsElement = tester.element(
      find.byKey(const ValueKey('settings-home')),
    );

    await tester.tap(find.text('Vault').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(
      identical(
        settingsElement,
        tester.element(find.byKey(const ValueKey('settings-home'))),
      ),
      isTrue,
    );
  });

  testWidgets('settings slider persists once when drag ends', (tester) async {
    final lock = LockController();
    final storage = CountingSettingsStorage();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        settingsStore: AppSettingsStore(storage),
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    final slider = find.byType(Slider).first;
    await tester.drag(slider, const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(storage.writes, 1);
  });

  testWidgets(
    'manual lock purges decrypted preview and it does not resurrect after unlock',
    (tester) async {
      final lock = LockController();
      final repository = BoundaryVaultRepository();
      final shuttle = RecordingVaultShuttle();
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: FakeUnlockService(),
          vaultRepository: repository,
          mediaService: boundaryMedia(repository),
          vaultShuttle: shuttle,
        ),
      );

      lock.unlock();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Protected note'));
      await tester.pumpAndSettle();
      expect(find.text('Secret preview text'), findsOneWidget);

      lock.lock();
      await tester.pumpAndSettle();
      expect(find.text('Calculator'), findsOneWidget);
      expect(find.text('Secret preview text'), findsNothing);
      expect(shuttle.purgeCalls, 1);

      lock.unlock();
      await tester.pumpAndSettle();
      expect(find.text('Protected note'), findsOneWidget);
      expect(find.text('Secret preview text'), findsNothing);
    },
  );

  testWidgets('panic lock purges new-note text entry dialog', (tester) async {
    final lock = LockController();
    final repository = BoundaryVaultRepository();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        vaultRepository: repository,
        mediaService: boundaryMedia(repository),
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vault-new-note')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vault-note-input')), findsOneWidget);

    lock.panic();
    await tester.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.byKey(const Key('vault-note-input')), findsNothing);
  });

  testWidgets('background lock purges export confirmation', (tester) async {
    final lock = LockController();
    final repository = BoundaryVaultRepository();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        vaultRepository: repository,
        mediaService: boundaryMedia(repository),
        initialSettings: const AppSettings.defaults().copyWith(
          autoLockSeconds: 0,
        ),
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Protected document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(find.text('Export this item?'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(lock.isLocked, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Export this item?'), findsNothing);
  });

  testWidgets('manual lock purges delete confirmation', (tester) async {
    final lock = LockController();
    final repository = BoundaryVaultRepository();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        vaultRepository: repository,
        mediaService: boundaryMedia(repository),
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Protected document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete from vault?'), findsOneWidget);

    lock.lock();
    await tester.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Delete from vault?'), findsNothing);
  });

  testWidgets('legacy V1 migration is explicit copy-only from Settings', (
    tester,
  ) async {
    final lock = LockController();
    final source = BoundaryVaultRepository();
    final target = BoundaryVaultRepository();
    final sourceCount = source.items.length;
    final targetCount = target.items.length;
    final migration = LegacyVaultMigrationService(
      source: source,
      target: target,
    );

    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        vaultRepository: target,
        mediaService: boundaryMedia(target),
        legacyVaultMigration: migration,
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings-legacy-v1-migration')),
      findsOneWidget,
    );
    expect(
      find.text(
        '$sourceCount legacy item(s) can be copied into the current Portable Vault. Originals stay untouched.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings-migrate-legacy')));
    await tester.pumpAndSettle();
    expect(find.text('Copy legacy Vault data?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-migrate-legacy-confirm')));
    await tester.pumpAndSettle();

    expect(source.items, hasLength(sourceCount));
    expect(target.items, hasLength(targetCount + sourceCount));
    expect(
      find.text(
        'Copied $sourceCount legacy item(s). Original V1 data was kept.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'failed generation-aware unlock clears only the captured generation',
    (tester) async {
      final lock = LockController();
      final repository = GenerationAwareTestVaultRepository(failOpen: true);
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: FakeUnlockService(pin: '0000'),
          vaultRepository: repository,
          initialCover: CoverKind.notes,
        ),
      );

      await tester.longPress(find.byKey(const Key('cover-title')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('unlock-pin')), '0000');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(repository.clearGenerationCalls, [7]);
      expect(lock.isLocked, isTrue);
      expect(find.text('Protected storage unavailable'), findsOneWidget);
    },
  );

  testWidgets(
    'PIN switch committed during lock reports that a fresh unlock is needed',
    (tester) async {
      final lock = LockController();
      final repository = GenerationAwareTestVaultRepository(
        switchOutcome: PinSessionSwitchOutcome.committedSessionClosed,
      );
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: FakeUnlockService(pin: '0000'),
          vaultRepository: repository,
        ),
      );

      lock.unlock();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      final switchPin = find.text('Switch Vault PIN');
      await tester.scrollUntilVisible(
        switchPin,
        320,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(switchPin);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settings-new-pin')), '1234');
      await tester.enterText(
        find.byKey(const Key('settings-confirm-pin')),
        '1234',
      );
      await tester.tap(find.byKey(const Key('settings-save-pin')));
      await tester.pumpAndSettle();

      expect(
        find.text('PIN changed. Unlock again with the new PIN.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('manual unlock suppresses concurrent submit attempts', (
    tester,
  ) async {
    final lock = LockController();
    final unlock = DeferredManualUnlockService();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: unlock,
        initialCover: CoverKind.notes,
      ),
    );

    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('unlock-pin')), '0000');

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(unlock.verifyCalls, 1);
    expect(lock.isLocked, isTrue);

    unlock.verification.complete(true);
    await tester.pumpAndSettle();

    expect(lock.isLocked, isFalse);
  });

  testWidgets('notes cover is functional without exposing secret routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(),
        initialCover: CoverKind.notes,
      ),
    );

    await tester.enterText(find.byKey(const Key('todo-input')), 'Buy milk');
    await tester.tap(find.byKey(const Key('todo-add')));
    await tester.pump();

    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });
}
