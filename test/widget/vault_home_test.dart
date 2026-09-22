import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/vault/vault_home.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class FakeVaultRepository implements VaultRepository, VaultThumbnailRepository {
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
  final thumbnailsById = <String, Uint8List>{};
  final bool failList;
  VaultItemKind? lastAddedKind;
  Uint8List? lastAddedBytes;
  int readBytesCalls = 0;

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
    thumbnailsById.remove(id);
  }

  @override
  Future<List<VaultItem>> list() async {
    if (failList) throw StateError('synthetic list failure');
    return List.unmodifiable(items);
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    readBytesCalls += 1;
    return bytesById[id]!;
  }

  @override
  Future<Uint8List?> readThumbnail(String id) async => thumbnailsById[id];

  @override
  Future<void> writeThumbnail(String id, Uint8List bytes) async {
    thumbnailsById[id] = Uint8List.fromList(bytes);
  }
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

  testWidgets(
    'gallery uses encrypted thumbnail cache before original payload',
    (tester) async {
      final repository = FakeVaultRepository();
      final originalBytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 8, height: 8)),
      );
      final item = await repository.addBytes(
        originalBytes,
        kind: VaultItemKind.image,
      );
      final thumbnailBytes = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 2, height: 2)),
      );
      await repository.writeThumbnail(item.id, thumbnailBytes);
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

      expect(find.byKey(Key('vault-thumbnail-${item.id}')), findsOneWidget);
      expect(repository.readBytesCalls, 0);

      await tester.tap(find.byKey(Key('vault-tile-${item.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vault-fullscreen-image')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const Key('vault-image-export')), findsOneWidget);
      expect(find.byKey(const Key('vault-image-delete')), findsOneWidget);
      expect(repository.readBytesCalls, 1);
    },
  );

  testWidgets('gallery long press enables multi-select bulk actions', (
    tester,
  ) async {
    final repository = FakeVaultRepository();
    final second = await repository.addBytes(
      Uint8List.fromList('second'.codeUnits),
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

    await tester.longPress(find.byKey(const Key('vault-tile-fixture-item')));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(const Key('vault-selection-export')), findsOneWidget);
    expect(find.byKey(const Key('vault-selection-delete')), findsOneWidget);

    await tester.tap(find.byKey(Key('vault-tile-${second.id}')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vault-selection-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.items, isEmpty);
    expect(find.byKey(const Key('vault-selection-count')), findsNothing);
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
