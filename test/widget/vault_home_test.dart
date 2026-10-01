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
  final thumbnailReadIds = <String>[];
  final failDeleteIds = <String>{};
  final invalidReadIds = <String>{};
  final bool failList;
  VaultItemKind? lastAddedKind;
  Uint8List? lastAddedBytes;
  int readBytesCalls = 0;
  int listCalls = 0;

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
    if (failDeleteIds.contains(id)) {
      throw StateError('synthetic delete failure');
    }
    items.removeWhere((item) => item.id == id);
    bytesById.remove(id);
    thumbnailsById.remove(id);
  }

  @override
  Future<List<VaultItem>> list() async {
    listCalls += 1;
    if (failList) throw StateError('synthetic list failure');
    return List.unmodifiable(items);
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    readBytesCalls += 1;
    if (invalidReadIds.contains(id)) throw VaultItemInvalidException(id);
    return bytesById[id]!;
  }

  @override
  Future<Uint8List?> readThumbnail(String id) async {
    thumbnailReadIds.add(id);
    return thumbnailsById[id];
  }

  @override
  Future<void> writeThumbnail(String id, Uint8List bytes) async {
    thumbnailsById[id] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeThumbnailForAuthenticatedItem(
    VaultItem item,
    Uint8List bytes,
  ) async {
    thumbnailsById[item.id] = Uint8List.fromList(bytes);
  }
}

class ScanAwareFakeVaultRepository extends FakeVaultRepository
    implements VaultScanAwareRepository {
  ScanAwareFakeVaultRepository(this.scanResult);

  final VaultScanResult scanResult;

  @override
  Future<VaultScanResult> scan() async => scanResult;
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

  testWidgets('picker failure is contained and later imports remain usable', (
    tester,
  ) async {
    final repository = FakeVaultRepository();
    var pickerCalls = 0;
    final handoffEvents = <bool>[];
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      pickImports: () async {
        pickerCalls += 1;
        if (pickerCalls == 1) {
          throw StateError('synthetic secret picker failure');
        }
        return [
          PickedVaultSource(
            name: 'picked-$pickerCalls.bin',
            kind: VaultItemKind.document,
            openRead: () => Stream<List<int>>.value([pickerCalls]),
          ),
        ];
      },
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
            onSystemHandoffChanged: handoffEvents.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> importCopy() async {
      await tester.tap(find.byKey(const Key('vault-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault-import-copy')));
      await tester.pumpAndSettle();
    }

    await importCopy();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('vault-import')), findsOneWidget);
    expect(find.text('Import failed. Please try again.'), findsOneWidget);
    expect(
      find.textContaining('synthetic secret picker failure'),
      findsNothing,
    );

    await importCopy();
    expect(tester.takeException(), isNull);
    expect(find.text('Imported 1 item(s).'), findsOneWidget);
    expect(find.byKey(const Key('vault-tile-added-1')), findsOneWidget);
    expect(repository.listCalls, 1);

    await importCopy();
    expect(tester.takeException(), isNull);
    expect(find.text('Imported 1 item(s).'), findsOneWidget);

    expect(pickerCalls, 3);
    expect(handoffEvents, [true, false, true, false, true, false]);
  });

  testWidgets('empty picker result returns to gallery without fake success', (
    tester,
  ) async {
    final repository = FakeVaultRepository();
    var pickerCalls = 0;
    final handoffEvents = <bool>[];
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      pickImports: () async {
        pickerCalls += 1;
        return const [];
      },
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
            onSystemHandoffChanged: handoffEvents.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vault-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vault-import-copy')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(pickerCalls, 1);
    expect(handoffEvents, [true, false]);
    expect(find.byKey(const Key('vault-import')), findsOneWidget);
    expect(find.text('Imported 0 item(s).'), findsNothing);
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
    expect(repository.listCalls, 1);
  });

  testWidgets('successful camera capture updates the grid without a rescan', (
    tester,
  ) async {
    final repository = FakeVaultRepository();
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      capturePhoto: () async => PickedVaultData(
        bytes: Uint8List.fromList([7, 8, 9]),
        kind: VaultItemKind.document,
      ),
      saveExport: (_, _) async => true,
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
    await tester.pumpAndSettle();
    expect(repository.listCalls, 1);

    await tester.tap(find.byKey(const Key('vault-camera')));
    await tester.pumpAndSettle();

    expect(repository.listCalls, 1);
    expect(find.byKey(const Key('vault-tile-added-1')), findsOneWidget);
  });

  testWidgets('cancelled import does not rescan unchanged vault contents', (
    tester,
  ) async {
    final repository = FakeVaultRepository();
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      pickImports: () async => const <PickedVaultSource>[],
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
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
    await tester.pumpAndSettle();
    expect(repository.listCalls, 1);

    await tester.tap(find.byKey(const Key('vault-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vault-import-copy')));
    await tester.pumpAndSettle();

    expect(repository.listCalls, 1);
  });

  testWidgets(
    'cancelled camera capture does not rescan unchanged vault contents',
    (tester) async {
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
              confirmExport: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.listCalls, 1);

      await tester.tap(find.byKey(const Key('vault-camera')));
      await tester.pumpAndSettle();

      expect(repository.listCalls, 1);
    },
  );

  testWidgets(
    'opening an image rebuilds a missing thumbnail from loaded bytes',
    (tester) async {
      final repository = FakeVaultRepository();
      final imageBytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 16, height: 16)),
      );
      final item = await repository.addBytes(
        imageBytes,
        kind: VaultItemKind.image,
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
              confirmExport: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.thumbnailsById[item.id], isNull);
      expect(repository.readBytesCalls, 0);

      await tester.tap(find.byKey(Key('vault-tile-${item.id}')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(repository.readBytesCalls, 1);
      expect(repository.thumbnailsById[item.id], isNotNull);
    },
  );

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

      expect(
        find.byKey(Key('vault-fullscreen-image-${item.id}')),
        findsOneWidget,
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const Key('vault-image-export')), findsOneWidget);
      expect(find.byKey(const Key('vault-image-delete')), findsOneWidget);
      expect(repository.readBytesCalls, 1);
    },
  );

  testWidgets(
    'invalid authenticated image read removes stale tile without rescan',
    (tester) async {
      final repository = FakeVaultRepository();
      repository.items.clear();
      repository.bytesById.clear();
      final item = VaultItem(
        id: 'invalid-image',
        kind: VaultItemKind.image,
        createdAt: DateTime.utc(2026, 9, 18, 3),
      );
      repository.items.add(item);
      repository.bytesById[item.id] = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      repository.invalidReadIds.add(item.id);
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
      expect(repository.listCalls, 1);

      await tester.tap(find.byKey(Key('vault-tile-${item.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Image data could not be displayed.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('vault-image-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('vault-tile-${item.id}')), findsNothing);
      expect(repository.listCalls, 1);
    },
  );

  testWidgets('gallery uses encrypted thumbnail cache for video tiles', (
    tester,
  ) async {
    final repository = FakeVaultRepository();
    final item = await repository.addBytes(
      Uint8List.fromList([0, 1, 2, 3]),
      kind: VaultItemKind.video,
    );
    await repository.writeThumbnail(
      item.id,
      Uint8List.fromList(img.encodeJpg(img.Image(width: 2, height: 2))),
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

    expect(repository.thumbnailReadIds, contains(item.id));
    expect(find.byKey(Key('vault-thumbnail-${item.id}')), findsOneWidget);
    expect(repository.readBytesCalls, 0);
  });

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

  testWidgets('bulk delete continues after one item fails', (tester) async {
    final repository = FakeVaultRepository();
    final second = await repository.addBytes(
      Uint8List.fromList('second'.codeUnits),
      kind: VaultItemKind.note,
    );
    repository.failDeleteIds.add('fixture-item');
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
    await tester.tap(find.byKey(Key('vault-tile-${second.id}')));
    await tester.tap(find.byKey(const Key('vault-selection-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.items.map((item) => item.id), ['fixture-item']);
    expect(find.text('Deleted 1/2 item(s); 1 failed.'), findsOneWidget);
    expect(find.byKey(const Key('vault-selection-count')), findsNothing);
  });

  testWidgets('bulk export continues after one item fails', (tester) async {
    final repository = FakeVaultRepository();
    final second = await repository.addBytes(
      Uint8List.fromList('second'.codeUnits),
      kind: VaultItemKind.note,
    );
    var saveCalls = 0;
    final media = MediaVaultService(
      repository: repository,
      pickImport: () async => null,
      capturePhoto: () async => null,
      saveExport: (_, _) async {
        saveCalls += 1;
        if (saveCalls == 1) throw StateError('synthetic export failure');
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
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('vault-tile-fixture-item')));
    await tester.tap(find.byKey(Key('vault-tile-${second.id}')));
    await tester.tap(find.byKey(const Key('vault-selection-export')));
    await tester.pumpAndSettle();

    expect(saveCalls, 2);
    expect(find.text('Exported 1/2 item(s); 1 not exported.'), findsOneWidget);
    expect(find.byKey(const Key('vault-selection-count')), findsNothing);
  });

  testWidgets('orphaned sidecar cleanup remains visible without failing list', (
    tester,
  ) async {
    final repository = ScanAwareFakeVaultRepository(
      const VaultScanResult(items: [], orphanedSidecarCount: 1),
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

    expect(
      find.textContaining('Found 1 orphaned protected cache record(s)'),
      findsOneWidget,
    );
    expect(find.textContaining('could not be read'), findsNothing);
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

  testWidgets(
    'image viewer has explicit back and swipes between adjacent images',
    (tester) async {
      final repository = FakeVaultRepository();
      repository.items.clear();
      repository.bytesById.clear();
      for (var index = 0; index < 3; index += 1) {
        final item = VaultItem(
          id: 'image-$index',
          kind: VaultItemKind.image,
          createdAt: DateTime.utc(2026, 9, 18, index + 1),
        );
        repository.items.add(item);
        repository.bytesById[item.id] = Uint8List.fromList(
          img.encodePng(img.Image(width: 2, height: 2)),
        );
      }
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
              confirmExport: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('vault-tile-image-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-image-back')), findsOneWidget);
      expect(find.byKey(const Key('vault-image-page-view')), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(repository.readBytesCalls, lessThanOrEqualTo(2));

      await tester.drag(
        find.byKey(const Key('vault-image-page-view')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(repository.readBytesCalls, lessThanOrEqualTo(3));

      await tester.tap(find.byKey(const Key('vault-image-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-image-page-view')), findsNothing);
      expect(find.byKey(const Key('vault-tile-image-0')), findsOneWidget);
    },
  );

  testWidgets('system back pops only the image viewer', (tester) async {
    final repository = FakeVaultRepository();
    repository.items.clear();
    repository.bytesById.clear();
    final item = VaultItem(
      id: 'back-image',
      kind: VaultItemKind.image,
      createdAt: DateTime.utc(2026, 9, 18, 1),
    );
    repository.items.add(item);
    repository.bytesById[item.id] = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
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
            confirmExport: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vault-tile-back-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vault-image-page-view')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vault-image-page-view')), findsNothing);
    expect(find.byKey(const Key('vault-tile-back-image')), findsOneWidget);
  });
}
