import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_repository.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_session.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_storage.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('portable-vault-repo-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<PortableVaultRepository> repository(String pin) async {
    final session = PortableVaultSession();
    await session.open(pin);
    return PortableVaultRepository(
      storage: DirectoryPortableVaultStorage(() async => root),
      session: session,
    );
  }

  test('same PIN reopens persistent objects', () async {
    final first = await repository('0000');
    final added = await first.addBytes(
      Uint8List.fromList([1, 2, 3, 4]),
      kind: VaultItemKind.image,
    );

    final reopened = await repository('0000');
    final listed = await reopened.list();

    expect(listed.map((item) => item.id), contains(added.id));
    expect(
      await reopened.readBytes(added.id),
      Uint8List.fromList([1, 2, 3, 4]),
    );
  });

  test(
    'different PIN sees independent namespace and switching back restores it',
    () async {
      final repo = await repository('0000');
      final added = await repo.addBytes(
        Uint8List.fromList([9, 9, 9]),
        kind: VaultItemKind.document,
      );

      await repo.openSession('1234');
      expect(await repo.list(), isEmpty);

      await repo.openSession('0000');
      final listed = await repo.list();
      expect(listed.map((item) => item.id), contains(added.id));
    },
  );

  test('copied vault root works on a second filesystem path', () async {
    final first = await repository('0000');
    final added = await first.addBytes(
      Uint8List.fromList([7, 8, 9]),
      kind: VaultItemKind.video,
    );

    final secondRoot = await Directory.systemTemp.createTemp(
      'portable-vault-copy-',
    );
    addTearDown(() async {
      if (await secondRoot.exists()) await secondRoot.delete(recursive: true);
    });
    await _copyDirectory(root, secondRoot);

    final session = PortableVaultSession();
    await session.open('0000');
    final second = PortableVaultRepository(
      storage: DirectoryPortableVaultStorage(() async => secondRoot),
      session: session,
    );
    expect(await second.readBytes(added.id), Uint8List.fromList([7, 8, 9]));
  });

  test('corrupt object is surfaced by scan and list fails closed', () async {
    final repo = await repository('0000');
    final added = await repo.addBytes(
      Uint8List.fromList([1, 2, 3]),
      kind: VaultItemKind.image,
    );
    final material = repo.session.requireMaterial();
    final file = File(
      '${root.path}${Platform.pathSeparator}${material.namespaceId}${Platform.pathSeparator}objects${Platform.pathSeparator}${added.id}.pvb',
    );
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await file.writeAsBytes(bytes, flush: true);

    final scan = await repo.scan();
    expect(scan.items, isEmpty);
    expect(scan.corruptCount, 1);
    await expectLater(repo.list(), throwsA(isA<VaultScanException>()));
  });

  test('closed session cannot read vault', () async {
    final repo = await repository('0000');
    repo.clearSession();
    await expectLater(
      repo.list(),
      throwsA(isA<PortableVaultSessionClosedException>()),
    );
  });
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: true)) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = '${destination.path}${Platform.pathSeparator}$relative';
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    }
  }
}
