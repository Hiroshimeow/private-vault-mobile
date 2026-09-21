import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_repository.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

void main() {
  late Directory root;
  var pin = '0000';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('portable-vault-repo-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  PortableVaultRepository repository() => PortableVaultRepository(
    rootDirectory: () async => root,
    pinProvider: () async => pin,
  );

  test('same PIN reopens copied persistent objects', () async {
    final first = repository();
    final added = await first.addBytes(
      Uint8List.fromList([1, 2, 3, 4]),
      kind: VaultItemKind.image,
    );

    final reopened = repository();
    final listed = await reopened.list();

    expect(listed.map((item) => item.id), contains(added.id));
    expect(
      await reopened.readBytes(added.id),
      Uint8List.fromList([1, 2, 3, 4]),
    );
  });

  test('changing PIN selects an empty independent namespace', () async {
    final first = repository();
    final added = await first.addBytes(
      Uint8List.fromList([9, 9, 9]),
      kind: VaultItemKind.document,
    );

    pin = '1234';
    expect(await repository().list(), isEmpty);

    pin = '0000';
    final listed = await repository().list();
    expect(listed.map((item) => item.id), contains(added.id));
  });

  test('copied vault root works on a second filesystem path', () async {
    final first = repository();
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
    final second = PortableVaultRepository(
      rootDirectory: () async => secondRoot,
      pinProvider: () async => '0000',
    );

    expect(await second.readBytes(added.id), Uint8List.fromList([7, 8, 9]));
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
