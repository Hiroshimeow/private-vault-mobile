import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/app/private_vault_theme.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/cover/calculator_cover.dart';
import 'package:private_vault_mobile/features/cover/notes_cover.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/vault_home.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

const _goldenKey = Key('polish-golden-root');

class _FakeUnlockService implements UnlockService {
  @override
  Future<void> configure(String pin) async {}

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) async => true;
}

class _GoldenVaultRepository implements VaultRepository {
  _GoldenVaultRepository({List<VaultItem>? items, this.failList = false})
    : items = items ?? <VaultItem>[];

  final List<VaultItem> items;
  final bool failList;

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    final item = VaultItem(
      id: 'golden-${items.length}',
      kind: kind,
      createdAt: DateTime.utc(2026, 9, 20, 1, items.length),
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<VaultItem>> list() async {
    if (failList) throw StateError('synthetic list failure');
    return List<VaultItem>.unmodifiable(items);
  }

  @override
  Future<Uint8List> readBytes(String id) async =>
      Uint8List.fromList('golden'.codeUnits);
}

MediaVaultService _media(VaultRepository repository) => MediaVaultService(
  repository: repository,
  pickImport: () async => null,
  capturePhoto: () async => null,
  saveExport: (_, _) async => true,
);

Future<void> _pumpSurface(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: PrivateVaultTheme.light(),
      darkTheme: PrivateVaultTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(key: _goldenKey, child: child),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String filename) async {
  await expectLater(
    find.byKey(_goldenKey),
    matchesGoldenFile('../goldens/$filename'),
  );
}

void main() {
  testWidgets('calculator light golden', (tester) async {
    await _pumpSurface(
      tester,
      CalculatorCover(onUnlockRequested: () {}),
      brightness: Brightness.light,
    );
    await _expectGolden(tester, 'calculator_light.png');
  });

  testWidgets('calculator dark golden', (tester) async {
    await _pumpSurface(
      tester,
      CalculatorCover(onUnlockRequested: () {}),
      brightness: Brightness.dark,
    );
    await _expectGolden(tester, 'calculator_dark.png');
  });

  testWidgets('notes light golden', (tester) async {
    await _pumpSurface(
      tester,
      NotesCover(onUnlockRequested: () {}),
      brightness: Brightness.light,
    );
    await _expectGolden(tester, 'notes_light.png');
  });

  testWidgets('notes dark golden', (tester) async {
    await _pumpSurface(
      tester,
      NotesCover(onUnlockRequested: () {}),
      brightness: Brightness.dark,
    );
    await _expectGolden(tester, 'notes_dark.png');
  });

  testWidgets('vault empty golden', (tester) async {
    final repository = _GoldenVaultRepository();
    await _pumpSurface(
      tester,
      Scaffold(
        body: VaultHome(
          repository: repository,
          media: _media(repository),
          confirmExport: true,
        ),
      ),
      brightness: Brightness.light,
    );
    await _expectGolden(tester, 'vault_empty.png');
  });

  testWidgets('vault populated golden', (tester) async {
    final repository = _GoldenVaultRepository(
      items: [
        VaultItem(
          id: 'note',
          kind: VaultItemKind.note,
          createdAt: DateTime.utc(2026, 9, 20, 1),
        ),
        VaultItem(
          id: 'document',
          kind: VaultItemKind.document,
          createdAt: DateTime.utc(2026, 9, 20),
        ),
      ],
    );
    await _pumpSurface(
      tester,
      Scaffold(
        body: VaultHome(
          repository: repository,
          media: _media(repository),
          confirmExport: true,
        ),
      ),
      brightness: Brightness.light,
    );
    await _expectGolden(tester, 'vault_populated.png');
  });

  testWidgets('vault error golden', (tester) async {
    final repository = _GoldenVaultRepository(failList: true);
    await _pumpSurface(
      tester,
      Scaffold(
        body: VaultHome(
          repository: repository,
          media: _media(repository),
          confirmExport: true,
        ),
      ),
      brightness: Brightness.light,
    );
    await _expectGolden(tester, 'vault_error.png');
  });

  testWidgets('settings grouping dark golden', (tester) async {
    final lock = LockController()..unlock();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _goldenKey,
        child: PrivateVaultApp(
          lockController: lock,
          unlockService: _FakeUnlockService(),
          initialSettings: const AppSettings.defaults().copyWith(
            darkMode: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await _expectGolden(tester, 'settings_dark.png');
  });

  testWidgets('unlock sheet golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _goldenKey,
        child: PrivateVaultApp(
          lockController: LockController(),
          unlockService: _FakeUnlockService(),
        ),
      ),
    );
    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();
    await _expectGolden(tester, 'unlock_sheet_light.png');
  });
}
