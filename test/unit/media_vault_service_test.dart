import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class RecordingStreamingRepository implements StreamingVaultRepository {
  final List<List<List<int>>> importedChunks = [];
  int addBytesCalls = 0;

  @override
  Future<VaultItem> addStream(
    Stream<List<int>> bytes, {
    required VaultItemKind kind,
  }) async {
    final chunks = <List<int>>[];
    await for (final chunk in bytes) {
      chunks.add(List<int>.from(chunk));
    }
    importedChunks.add(chunks);
    return VaultItem(
      id: 'stream-${importedChunks.length}',
      kind: kind,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    addBytesCalls += 1;
    throw StateError('streaming path should not call addBytes');
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<VaultItem>> list() async => const [];

  @override
  Future<Uint8List> readBytes(String id) async => Uint8List(0);
}

class ThumbnailRecordingRepository
    implements VaultRepository, VaultThumbnailRepository {
  final Map<String, Uint8List> payloads = {};
  final Map<String, Uint8List> thumbnails = {};
  var _nextId = 0;

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    final id = 'item-${_nextId++}';
    payloads[id] = Uint8List.fromList(bytes);
    return VaultItem(
      id: id,
      kind: kind,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Future<void> delete(String id) async {
    payloads.remove(id);
    thumbnails.remove(id);
  }

  @override
  Future<List<VaultItem>> list() async => const [];

  @override
  Future<Uint8List> readBytes(String id) async => payloads[id]!;

  @override
  Future<Uint8List?> readThumbnail(String id) async => thumbnails[id];

  @override
  Future<void> writeThumbnail(String id, Uint8List bytes) async {
    thumbnails[id] = Uint8List.fromList(bytes);
  }
}

class MemoryVaultKeyStore implements VaultKeyStore {
  SecretKey? key;

  @override
  Future<SecretKey> getOrCreate() async {
    return key ??= await AesGcm.with256bits().newSecretKey();
  }

  @override
  Future<SecretKey?> read() async => key;
}

void main() {
  late Directory tempDir;
  late LocalVaultRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media-vault-test-');
    repo = LocalVaultRepository(
      rootDirectory: () async => tempDir,
      keyStore: MemoryVaultKeyStore(),
      crypto: VaultCrypto(),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('import encrypts picked bytes into vault', () async {
    final service = MediaVaultService(
      repository: repo,
      pickImport: () async => PickedVaultData(
        bytes: Uint8List.fromList('picked-secret'.codeUnits),
        kind: VaultItemKind.document,
      ),
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    final item = await service.importFile();

    expect(item, isNotNull);
    expect(
      await repo.readBytes(item!.id),
      Uint8List.fromList('picked-secret'.codeUnits),
    );
    expect(
      (await File('${tempDir.path}${Platform.pathSeparator}${item.id}.vault')
          .readAsString()),
      isNot(contains('picked-secret')),
    );
  });

  test('image import stores a bounded thumbnail cache', () async {
    final repository = ThumbnailRecordingRepository();
    final original = img.Image(width: 800, height: 400);
    final originalBytes = Uint8List.fromList(img.encodePng(original));
    final service = MediaVaultService(
      repository: repository,
      pickImport: () async =>
          PickedVaultData(bytes: originalBytes, kind: VaultItemKind.image),
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    final item = await service.importFile();

    expect(item, isNotNull);
    final thumbnailBytes = repository.thumbnails[item!.id];
    expect(thumbnailBytes, isNotNull);
    final thumbnail = img.decodeImage(thumbnailBytes!);
    expect(thumbnail, isNotNull);
    expect(thumbnail!.width, lessThanOrEqualTo(384));
    expect(thumbnail.height, lessThan(original.height));
    expect(repository.payloads[item.id], originalBytes);
  });

  test('multi import loads and commits selected files sequentially', () async {
    final events = <String>[];
    var activeReaders = 0;
    var maxActiveReaders = 0;

    Stream<List<int>> read(String name, List<int> bytes) async* {
      events.add('read:$name');
      activeReaders += 1;
      if (activeReaders > maxActiveReaders) {
        maxActiveReaders = activeReaders;
      }
      await Future<void>.delayed(Duration.zero);
      yield Uint8List.fromList(bytes);
      activeReaders -= 1;
    }

    final service = MediaVaultService(
      repository: repo,
      pickImport: () async => null,
      pickImports: () async => [
        PickedVaultSource(
          name: 'first.jpg',
          kind: VaultItemKind.image,
          openRead: () => read('first', [1, 2, 3]),
        ),
        PickedVaultSource(
          name: 'second.mp4',
          kind: VaultItemKind.video,
          openRead: () => read('second', [4, 5, 6]),
        ),
      ],
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    expect(events, isEmpty);
    final result = await service.importFiles();

    expect(result.failedCount, 0);
    expect(result.importedCount, 2);
    expect(maxActiveReaders, 1);
    expect(events, ['read:first', 'read:second']);
    expect(
      await repo.readBytes(result.imported[0].id),
      Uint8List.fromList([1, 2, 3]),
    );
    expect(
      await repo.readBytes(result.imported[1].id),
      Uint8List.fromList([4, 5, 6]),
    );
  });

  test('streaming repository receives source chunks directly', () async {
    final streamingRepo = RecordingStreamingRepository();
    final service = MediaVaultService(
      repository: streamingRepo,
      pickImport: () async => null,
      pickImports: () async => [
        PickedVaultSource(
          name: 'large.mp4',
          kind: VaultItemKind.video,
          openRead: () async* {
            yield [1, 2];
            yield [3, 4, 5];
          },
        ),
      ],
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    final result = await service.importFiles();

    expect(result.importedCount, 1);
    expect(result.failedCount, 0);
    expect(streamingRepo.addBytesCalls, 0);
    expect(streamingRepo.importedChunks, [
      [
        [1, 2],
        [3, 4, 5],
      ],
    ]);
  });

  test(
    'multi import continues after one source fails and reports it',
    () async {
      var laterSourceRead = false;
      final service = MediaVaultService(
        repository: repo,
        pickImport: () async => null,
        pickImports: () async => [
          PickedVaultSource(
            name: 'broken.mp4',
            kind: VaultItemKind.video,
            openRead: () async* {
              throw StateError('unreadable source');
            },
          ),
          PickedVaultSource(
            name: 'healthy.jpg',
            kind: VaultItemKind.image,
            openRead: () async* {
              laterSourceRead = true;
              yield Uint8List.fromList([7, 8, 9]);
            },
          ),
        ],
        capturePhoto: () async => null,
        saveExport: (_, _) async => true,
      );

      final result = await service.importFiles();

      expect(laterSourceRead, isTrue);
      expect(result.importedCount, 1);
      expect(result.failedCount, 1);
      expect(result.failures.single.name, 'broken.mp4');
      expect(
        await repo.readBytes(result.imported.single.id),
        Uint8List.fromList([7, 8, 9]),
      );
    },
  );

  test('move deletes source only after encrypted vault commit', () async {
    var deleteSawCommittedItem = false;
    final service = MediaVaultService(
      repository: repo,
      pickImport: () async => null,
      pickImports: () async => [
        PickedVaultSource(
          name: 'move-me.jpg',
          kind: VaultItemKind.image,
          openRead: () => Stream<List<int>>.value([4, 2]),
          deleteSource: () async {
            final items = await repo.list();
            if (items.isEmpty) return;
            final bytes = await repo.readBytes(items.last.id);
            deleteSawCommittedItem = bytes.length == 2;
          },
        ),
      ],
      capturePhoto: () async => null,
      saveExport: (_, _) async => true,
    );

    final result = await service.importFiles(moveSource: true);

    expect(result.importedCount, 1);
    expect(result.failedCount, 0);
    expect(deleteSawCommittedItem, isTrue);
    expect(
      await repo.readBytes(result.imported.single.id),
      Uint8List.fromList([4, 2]),
    );
  });

  test(
    'move deletion failure preserves committed vault item and reports it',
    () async {
      final service = MediaVaultService(
        repository: repo,
        pickImport: () async => null,
        pickImports: () async => [
          PickedVaultSource(
            name: 'undeletable.mp4',
            kind: VaultItemKind.video,
            openRead: () => Stream<List<int>>.value([8, 8, 8]),
            deleteSource: () async => throw StateError('delete denied'),
          ),
        ],
        capturePhoto: () async => null,
        saveExport: (_, _) async => true,
      );

      final result = await service.importFiles(moveSource: true);

      expect(result.importedCount, 1);
      expect(result.failedCount, 1);
      expect(result.failures.single.name, 'undeletable.mp4');
      expect(
        await repo.readBytes(result.imported.single.id),
        Uint8List.fromList([8, 8, 8]),
      );
    },
  );

  test('export reads decrypted bytes only after explicit call', () async {
    final item = await repo.addBytes(
      Uint8List.fromList([9, 8, 7]),
      kind: VaultItemKind.image,
    );
    Uint8List? exported;
    final service = MediaVaultService(
      repository: repo,
      pickImport: () async => null,
      capturePhoto: () async => null,
      saveExport: (name, bytes) async {
        expect(name, 'export.bin');
        exported = bytes;
        return true;
      },
    );

    expect(exported, isNull);
    expect(await service.export(item.id, fileName: 'export.bin'), isTrue);
    expect(exported, Uint8List.fromList([9, 8, 7]));
  });
}
