import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/vault/vault_home.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class FakeVaultRepository implements VaultRepository {
  FakeVaultRepository({this.failList = false}) {
    final item = VaultItem(
      id: 'fixture-item',
      kind: VaultItemKind.document,
      createdAt: DateTime.utc(2026, 9, 18, 1),
    );
    items.add(item);
    bytesById[item.id] = Uint8List.fromList([1, 2, 3]);
  }

  final items = <VaultItem>[];
  final bytesById = <String, Uint8List>{};
  final bool failList;
  VaultItemKind? lastAddedKind;
  Uint8List? lastAddedBytes;

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    lastAddedKind = kind;
    lastAddedBytes = Uint8List.fromList(bytes);
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
    if (failList) throw StateError('synthetic list failure');
    return List.unmodifiable(items);
  }

  @override
  Future<Uint8List> readBytes(String id) async => bytesById[id]!;
}

void main() {
  testWidgets('new protected note is stored and previewed', (tester) async {
    final repository = FakeVaultRepository();
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultHome(
            repository: repository,
            media: media,
            confirmExport: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('vault-new-note')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vault-note-input')),
      'Synthetic protected note',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.lastAddedKind, VaultItemKind.note);
    expect(
      String.fromCharCodes(repository.lastAddedBytes!),
      'Synthetic protected note',
    );
    expect(find.text('Protected note'), findsOneWidget);

    await tester.tap(find.text('Protected note'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic protected note'), findsOneWidget);
  });

  testWidgets('decrypted note preview is not selectable', (tester) async {
    final repository = FakeVaultRepository();
    await repository.addBytes(
      Uint8List.fromList('Non-copyable secret'.codeUnits),
      kind: VaultItemKind.note,
    );
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultHome(
            repository: repository,
            media: media,
            confirmExport: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Protected note'));
    await tester.pumpAndSettle();

    expect(find.text('Non-copyable secret'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('export confirmation can be disabled explicitly', (tester) async {
    final repository = FakeVaultRepository();
    var exports = 0;
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      capturePhoto: () async => null,
      saveExport: (_, _) async {
        exports++;
        return true;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultHome(
            repository: repository,
            media: media,
            confirmExport: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Protected document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export this item?'), findsNothing);
    expect(exports, 1);
  });

  testWidgets('export confirmation remains the safe default path', (
    tester,
  ) async {
    final repository = FakeVaultRepository();
    var exports = 0;
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      capturePhoto: () async => null,
      saveExport: (_, _) async {
        exports++;
        return true;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultHome(
            repository: repository,
            media: media,
            confirmExport: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Protected document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export this item?'), findsOneWidget);
    expect(exports, 0);
  });

  testWidgets('import menu offers transactional Move to Vault', (tester) async {
    final repository = FakeVaultRepository();
    var sourceDeleted = false;
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      pickImports: () async => [
        PickedVaultSource(
          name: 'move.jpg',
          kind: VaultItemKind.image,
          openRead: () => Stream<List<int>>.value([4, 2]),
          deleteSource: () async => sourceDeleted = true,
        ),
      ],
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultHome(
            repository: repository,
            media: media,
            confirmExport: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vault-import')));
    await tester.pumpAndSettle();
    expect(find.text('Copy to Vault'), findsOneWidget);
    expect(find.text('Move to Vault'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vault-import-move')));
    await tester.pumpAndSettle();

    expect(sourceDeleted, isTrue);
    expect(find.text('Moved 1 item(s).'), findsOneWidget);
  });

  testWidgets('list failure shows only the load error state', (tester) async {
    final repository = FakeVaultRepository(failList: true);
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultHome(
            repository: repository,
            media: media,
            confirmExport: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Protected items could not be loaded.'), findsOneWidget);
    expect(
      find.text('No protected items yet. Import, capture, or create a note.'),
      findsNothing,
    );
  });
}
