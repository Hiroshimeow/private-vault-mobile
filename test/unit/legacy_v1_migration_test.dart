import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/vault/legacy_v1_migration.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class MemoryKeyStore implements VaultKeyStore {
  SecretKey? key;

  @override
  Future<SecretKey> getOrCreate() async =>
      key ??= await AesGcm.with256bits().newSecretKey();

  @override
  Future<SecretKey?> read() async => key;
}

class UnreadableSourceRepository implements VaultRepository {
  @override
  Future<VaultItem> addBytes(Uint8List bytes, {required VaultItemKind kind}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<List<VaultItem>> list() async => throw StateError('source unreadable');

  @override
  Future<Uint8List> readBytes(String id) => throw UnimplementedError();
}

class MemoryTargetRepository implements VaultRepository {
  final items = <VaultItem>[];
  final data = <String, Uint8List>{};
  String? failAfterSourceCount;

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    if (failAfterSourceCount != null && items.length == 1) {
      throw StateError('synthetic target failure');
    }
    final id = 'target-${items.length}';
    final item = VaultItem(
      id: id,
      kind: kind,
      createdAt: DateTime.utc(2026, 9, 22),
    );
    items.add(item);
    data[id] = Uint8List.fromList(bytes);
    return item;
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((item) => item.id == id);
    data.remove(id);
  }

  @override
  Future<List<VaultItem>> list() async => List.unmodifiable(items);

  @override
  Future<Uint8List> readBytes(String id) async => data[id]!;
}

void main() {
  late Directory root;
  late MemoryKeyStore keys;
  late LocalVaultRepository source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy-v1-migration-');
    keys = MemoryKeyStore();
    source = LocalVaultRepository(
      rootDirectory: () async => root,
      keyStore: keys,
      crypto: VaultCrypto(),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('copy migration preserves every V1 source object', () async {
    final note = await source.addBytes(
      Uint8List.fromList([1, 2]),
      kind: VaultItemKind.note,
    );
    final image = await source.addBytes(
      Uint8List.fromList([3, 4, 5]),
      kind: VaultItemKind.image,
    );
    final beforePayloads = <String, List<int>>{
      note.id: List<int>.from(await source.readBytes(note.id)),
      image.id: List<int>.from(await source.readBytes(image.id)),
    };
    final target = MemoryTargetRepository();
    final service = LegacyVaultMigrationService(source: source, target: target);

    final preview = await service.inspect();
    final result = await service.copyAll();

    expect(preview.itemCount, 2);
    expect(result.importedCount, 2);
    expect(result.failedCount, 0);
    expect(await source.list(), hasLength(2));
    expect(await source.readBytes(note.id), beforePayloads[note.id]);
    expect(await source.readBytes(image.id), beforePayloads[image.id]);
    expect(
      target.items.map((item) => item.kind),
      containsAll([VaultItemKind.note, VaultItemKind.image]),
    );
  });

  test('missing V1 metadata is recovered without deleting payload', () async {
    final item = await source.addBytes(
      Uint8List.fromList([9, 8, 7]),
      kind: VaultItemKind.document,
    );
    await File('${root.path}${Platform.pathSeparator}${item.id}.meta').delete();
    final target = MemoryTargetRepository();
    final service = LegacyVaultMigrationService(source: source, target: target);

    final result = await service.copyAll();

    expect(result.importedCount, 1);
    expect(result.failedCount, 0);
    expect(await source.readBytes(item.id), Uint8List.fromList([9, 8, 7]));
    expect(target.items.single.kind, VaultItemKind.document);
  });

  test(
    'per-item target failure does not delete V1 source or stop later read',
    () async {
      final first = await source.addBytes(
        Uint8List.fromList([1]),
        kind: VaultItemKind.document,
      );
      final second = await source.addBytes(
        Uint8List.fromList([2]),
        kind: VaultItemKind.video,
      );
      final target = MemoryTargetRepository()..failAfterSourceCount = 'enabled';
      final service = LegacyVaultMigrationService(
        source: source,
        target: target,
      );

      final result = await service.copyAll();

      expect(result.importedCount, 1);
      expect(result.failedCount, 1);
      expect(await source.readBytes(first.id), Uint8List.fromList([1]));
      expect(await source.readBytes(second.id), Uint8List.fromList([2]));
      expect(await source.list(), hasLength(2));
    },
  );

  test(
    'inspect reports generic read failure instead of hiding legacy data',
    () async {
      final service = LegacyVaultMigrationService(
        source: UnreadableSourceRepository(),
        target: MemoryTargetRepository(),
      );

      final preview = await service.inspect();

      expect(preview.itemCount, 0);
      expect(preview.readFailure, isTrue);
      expect(preview.keyUnavailable, isFalse);
      expect(preview.canMigrate, isFalse);
    },
  );

  test(
    'inspect reports missing key without claiming empty readable vault',
    () async {
      await source.addBytes(
        Uint8List.fromList([1, 2, 3]),
        kind: VaultItemKind.document,
      );
      final lockedSource = LocalVaultRepository(
        rootDirectory: () async => root,
        keyStore: MemoryKeyStore(),
        crypto: VaultCrypto(),
      );
      final service = LegacyVaultMigrationService(
        source: lockedSource,
        target: MemoryTargetRepository(),
      );

      final preview = await service.inspect();

      expect(preview.itemCount, 0);
      expect(preview.keyUnavailable, isTrue);
      expect(preview.canMigrate, isFalse);
    },
  );
}
