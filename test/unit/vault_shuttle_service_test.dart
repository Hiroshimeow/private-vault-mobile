import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_vault_mobile/features/apps/vault_shuttle_service.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class FakeVaultRepository implements VaultRepository {
  FakeVaultRepository(this.items, this.payloads);

  final List<VaultItem> items;
  final Map<String, Uint8List> payloads;

  @override
  Future<VaultItem> addBytes(Uint8List bytes, {required VaultItemKind kind}) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<VaultItem>> list() async => items;

  @override
  Future<Uint8List> readBytes(String id) async => payloads[id]!;
}

class RecordingVaultShuttleBridge implements VaultShuttleBridge {
  RecordingVaultShuttleBridge({this.failure});

  final Object? failure;
  String? packageName;
  String? stagedFileName;
  String? mimeType;
  String? displayName;

  @override
  Future<void> shareStagedFile({
    required String packageName,
    required String stagedFileName,
    required String mimeType,
    required String displayName,
  }) async {
    this.packageName = packageName;
    this.stagedFileName = stagedFileName;
    this.mimeType = mimeType;
    this.displayName = displayName;
    if (failure != null) throw failure!;
  }
}

void main() {
  late Directory temp;
  late VaultItem image;
  late FakeVaultRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vault-shuttle-test-');
    image = VaultItem(
      id: 'opaque-item',
      kind: VaultItemKind.image,
      createdAt: DateTime.utc(2026, 9, 21),
    );
    repository = FakeVaultRepository(
      [image],
      {
        image.id: Uint8List.fromList([1, 2, 3, 4]),
      },
    );
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test(
    'stages decrypted bytes only in private temp and purges on demand',
    () async {
      final bridge = RecordingVaultShuttleBridge();
      final shuttle = VaultShuttleService(
        repository: repository,
        bridge: bridge,
        tempDirectory: () async => temp,
        stagedTtl: const Duration(minutes: 5),
      );

      await shuttle.shareToIsolatedApp(
        item: image,
        packageName: 'isolated.app',
      );

      final root = Directory(p.join(temp.path, 'vault-shuttle'));
      final staged = await root
          .list()
          .where((entry) => entry is File)
          .cast<File>()
          .toList();

      expect(staged, hasLength(1));
      expect(await staged.single.readAsBytes(), [1, 2, 3, 4]);
      expect(staged.single.path, isNot(contains(image.id)));
      expect(bridge.packageName, 'isolated.app');
      expect(bridge.stagedFileName, staged.single.uri.pathSegments.last);
      expect(bridge.mimeType, 'image/*');
      expect(bridge.displayName, 'vault-image');

      await shuttle.purgeStagedPlaintext();

      expect(await root.list().toList(), isEmpty);
    },
  );

  test('bridge failure deletes plaintext immediately', () async {
    final bridge = RecordingVaultShuttleBridge(failure: StateError('blocked'));
    final shuttle = VaultShuttleService(
      repository: repository,
      bridge: bridge,
      tempDirectory: () async => temp,
    );

    await expectLater(
      shuttle.shareToIsolatedApp(item: image, packageName: 'isolated.app'),
      throwsStateError,
    );

    final root = Directory(p.join(temp.path, 'vault-shuttle'));
    expect(await root.list().toList(), isEmpty);
  });

  test('lists vault items without decrypting them', () async {
    final shuttle = VaultShuttleService(
      repository: repository,
      bridge: RecordingVaultShuttleBridge(),
      tempDirectory: () async => temp,
    );

    expect(await shuttle.listVaultItems(), [image]);
  });
}
