import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_key_deriver.dart';
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
    final material = reopened.session.requireMaterial();
    expect(
      File(
        '${root.path}${Platform.pathSeparator}${material.namespaceId}'
        '${Platform.pathSeparator}objects${Platform.pathSeparator}'
        '${added.id}.pvm',
      ).existsSync(),
      isTrue,
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

  test(
    'stream import commits authenticated V2 bytes without partial files',
    () async {
      final repo = await repository('0000');
      final item = await repo.addStream(
        Stream<List<int>>.fromIterable([
          [1, 2],
          [3],
          [4, 5, 6],
        ]),
        kind: VaultItemKind.video,
      );

      expect(
        await repo.readBytes(item.id),
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
      );
      final partials = await root
          .list(recursive: true)
          .where((entity) => entity.path.contains('.partial-'))
          .toList();
      expect(partials, isEmpty);
    },
  );

  test('failed stream import aborts partial object', () async {
    final repo = await repository('0000');

    Stream<List<int>> broken() async* {
      yield [1, 2, 3];
      throw StateError('source failed');
    }

    await expectLater(
      repo.addStream(broken(), kind: VaultItemKind.video),
      throwsA(isA<StateError>()),
    );
    final partials = await root
        .list(recursive: true)
        .where((entity) => entity.path.contains('.partial-'))
        .toList();
    expect(partials, isEmpty);
    expect(await repo.list(), isEmpty);
  });

  test(
    'listing uses encrypted sidecar without decrypting large payload',
    () async {
      final repo = await repository('0000');
      final added = await repo.addBytes(
        Uint8List.fromList([1, 2, 3]),
        kind: VaultItemKind.image,
      );
      final material = repo.session.requireMaterial();
      final objects = Directory(
        '${root.path}${Platform.pathSeparator}${material.namespaceId}'
        '${Platform.pathSeparator}objects',
      );
      final payload = File(
        '${objects.path}${Platform.pathSeparator}${added.id}.pvb',
      );
      final bytes = await payload.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await payload.writeAsBytes(bytes, flush: true);

      final scan = await repo.scan();
      expect(scan.items.map((item) => item.id), contains(added.id));
      expect(scan.corruptCount, 0);
      await expectLater(
        repo.readBytes(added.id),
        throwsA(isA<VaultIntegrityException>()),
      );
    },
  );

  test(
    'corrupt payload without sidecar is surfaced and list fails closed',
    () async {
      final repo = await repository('0000');
      final added = await repo.addBytes(
        Uint8List.fromList([1, 2, 3]),
        kind: VaultItemKind.image,
      );
      final material = repo.session.requireMaterial();
      final objects = Directory(
        '${root.path}${Platform.pathSeparator}${material.namespaceId}'
        '${Platform.pathSeparator}objects',
      );
      final payload = File(
        '${objects.path}${Platform.pathSeparator}${added.id}.pvb',
      );
      final metadata = File(
        '${objects.path}${Platform.pathSeparator}${added.id}.pvm',
      );
      await metadata.delete();
      final bytes = await payload.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await payload.writeAsBytes(bytes, flush: true);

      final scan = await repo.scan();
      expect(scan.items, isEmpty);
      expect(scan.corruptCount, 1);
      await expectLater(repo.list(), throwsA(isA<VaultScanException>()));
    },
  );

  test(
    'legacy payload without sidecar is reopened and sidecar is rebuilt',
    () async {
      final repo = await repository('0000');
      final added = await repo.addBytes(
        Uint8List.fromList([4, 5, 6]),
        kind: VaultItemKind.document,
      );
      final material = repo.session.requireMaterial();
      final metadata = File(
        '${root.path}${Platform.pathSeparator}${material.namespaceId}'
        '${Platform.pathSeparator}objects${Platform.pathSeparator}'
        '${added.id}.pvm',
      );
      await metadata.delete();
      expect(await metadata.exists(), isFalse);

      final scan = await repo.scan();

      expect(scan.items.map((item) => item.id), contains(added.id));
      expect(scan.hasProblems, isFalse);
      expect(await metadata.exists(), isTrue);
    },
  );

  test(
    'encrypted thumbnail cache round trips without touching payload',
    () async {
      final repo = await repository('0000');
      final added = await repo.addBytes(
        Uint8List.fromList([10, 20, 30]),
        kind: VaultItemKind.image,
      );
      final thumbnailBytes = Uint8List.fromList([
        0xff,
        0xd8,
        1,
        2,
        3,
        0xff,
        0xd9,
      ]);

      await repo.writeThumbnail(added.id, thumbnailBytes);

      expect(await repo.readThumbnail(added.id), thumbnailBytes);
      final material = repo.session.requireMaterial();
      final thumbnail = File(
        '${root.path}${Platform.pathSeparator}${material.namespaceId}'
        '${Platform.pathSeparator}objects${Platform.pathSeparator}'
        '${added.id}.pvt',
      );
      expect(await thumbnail.exists(), isTrue);
      expect(await thumbnail.readAsBytes(), isNot(contains(thumbnailBytes)));
      expect(await repo.readBytes(added.id), Uint8List.fromList([10, 20, 30]));
    },
  );

  test('corrupt thumbnail is discarded as cache miss', () async {
    final repo = await repository('0000');
    final added = await repo.addBytes(
      Uint8List.fromList([5, 6, 7]),
      kind: VaultItemKind.image,
    );
    await repo.writeThumbnail(
      added.id,
      Uint8List.fromList([0xff, 0xd8, 9, 8, 7, 0xff, 0xd9]),
    );
    final material = repo.session.requireMaterial();
    final thumbnail = File(
      '${root.path}${Platform.pathSeparator}${material.namespaceId}'
      '${Platform.pathSeparator}objects${Platform.pathSeparator}'
      '${added.id}.pvt',
    );
    final bytes = await thumbnail.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await thumbnail.writeAsBytes(bytes, flush: true);

    expect(await repo.readThumbnail(added.id), isNull);
    expect(await thumbnail.exists(), isFalse);
    expect(await repo.readBytes(added.id), Uint8List.fromList([5, 6, 7]));
  });

  test('delete removes payload, metadata, and thumbnail cache', () async {
    final repo = await repository('0000');
    final added = await repo.addBytes(
      Uint8List.fromList([7]),
      kind: VaultItemKind.image,
    );
    await repo.writeThumbnail(
      added.id,
      Uint8List.fromList([0xff, 0xd8, 7, 0xff, 0xd9]),
    );
    final material = repo.session.requireMaterial();
    final objects = Directory(
      '${root.path}${Platform.pathSeparator}${material.namespaceId}'
      '${Platform.pathSeparator}objects',
    );
    final payload = File(
      '${objects.path}${Platform.pathSeparator}${added.id}.pvb',
    );
    final metadata = File(
      '${objects.path}${Platform.pathSeparator}${added.id}.pvm',
    );
    final thumbnail = File(
      '${objects.path}${Platform.pathSeparator}${added.id}.pvt',
    );
    expect(await payload.exists(), isTrue);
    expect(await metadata.exists(), isTrue);
    expect(await thumbnail.exists(), isTrue);

    await repo.delete(added.id);

    expect(await payload.exists(), isFalse);
    expect(await metadata.exists(), isFalse);
    expect(await thumbnail.exists(), isFalse);
  });

  test('session clear and switch destroy replaced encryption keys', () async {
    final session = PortableVaultSession();
    await session.open('0000');
    final firstKey = session.requireMaterial().encryptionKey;
    expect(firstKey.isDestroyed, isFalse);

    await session.open('1234');
    expect(firstKey.isDestroyed, isTrue);
    final secondKey = session.requireMaterial().encryptionKey;
    expect(secondKey.isDestroyed, isFalse);

    session.clear();
    expect(secondKey.isDestroyed, isTrue);
    expect(session.isOpen, isFalse);
  });

  test(
    'failed transactional PIN switch preserves the previous session',
    () async {
      final repo = await repository('0000');
      final previous = repo.session.requireMaterial();
      final previousKey = previous.encryptionKey;

      await expectLater(
        repo.switchSession('1234', () async {
          throw StateError('verifier write failed');
        }),
        throwsA(isA<StateError>()),
      );

      expect(repo.session.requireMaterial().namespaceId, previous.namespaceId);
      expect(previousKey.isDestroyed, isFalse);
    },
  );

  test(
    'delete removes authoritative payload before auxiliary sidecars',
    () async {
      final session = PortableVaultSession();
      await session.open('0000');
      final delegate = DirectoryPortableVaultStorage(() async => root);
      final storage = _RecordingPortableVaultStorage(delegate);
      final repo = PortableVaultRepository(storage: storage, session: session);
      final added = await repo.addBytes(
        Uint8List.fromList([1, 2, 3]),
        kind: VaultItemKind.image,
      );
      await repo.writeThumbnail(
        added.id,
        Uint8List.fromList([0xff, 0xd8, 1, 0xff, 0xd9]),
      );

      storage.deleted.clear();
      storage.failSuffix = '.pvm';
      await repo.delete(added.id);

      expect(storage.deleted.first, endsWith('${added.id}.pvb'));
      final material = session.requireMaterial();
      final payload = File(
        '${root.path}${Platform.pathSeparator}${material.namespaceId}'
        '${Platform.pathSeparator}objects${Platform.pathSeparator}'
        '${added.id}.pvb',
      );
      expect(await payload.exists(), isFalse);
    },
  );

  test(
    'scan sweeps abandoned partial writes and surfaces orphan thumbnails',
    () async {
      final repo = await repository('0000');
      final added = await repo.addBytes(
        Uint8List.fromList([4, 5, 6]),
        kind: VaultItemKind.image,
      );
      await repo.writeThumbnail(
        added.id,
        Uint8List.fromList([0xff, 0xd8, 4, 0xff, 0xd9]),
      );
      final material = repo.session.requireMaterial();
      final objects = Directory(
        '${root.path}${Platform.pathSeparator}${material.namespaceId}'
        '${Platform.pathSeparator}objects',
      );
      final partial = File(
        '${objects.path}${Platform.pathSeparator}'
        '${added.id}.pvb.partial-deadbeef',
      );
      await partial.writeAsBytes([1, 2, 3], flush: true);

      await File('${objects.path}${Platform.pathSeparator}${added.id}.pvb')
          .delete();
      await File('${objects.path}${Platform.pathSeparator}${added.id}.pvm')
          .delete();

      final scan = await repo.scan();

      expect(await partial.exists(), isFalse);
      expect(scan.corruptCount, 1);
    },
  );

  test(
    'clear during in-flight derivation prevents stale key activation',
    () async {
      final deriver = _DeferredPortableVaultKeyDeriver();
      final session = PortableVaultSession(keyDeriver: deriver);
      await session.open('0000');
      final previous = session.requireMaterial();

      final pending = session.open('1234');
      await deriver.secondStarted.future;
      session.clear();
      deriver.releaseSecond.complete();

      await expectLater(
        pending,
        throwsA(isA<PortableVaultSessionChangedException>()),
      );
      expect(session.isOpen, isFalse);
      expect(previous.encryptionKey.isDestroyed, isTrue);
      expect(deriver.secondMaterial?.encryptionKey.isDestroyed, isTrue);
    },
  );

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

class _DeferredPortableVaultKeyDeriver extends PortableVaultKeyDeriver {
  final Completer<void> secondStarted = Completer<void>();
  final Completer<void> releaseSecond = Completer<void>();
  int _calls = 0;
  PortableVaultKeyMaterial? secondMaterial;

  @override
  Future<PortableVaultKeyMaterial> derive(String pin) async {
    _calls += 1;
    final call = _calls;
    if (call == 2) {
      secondStarted.complete();
      await releaseSecond.future;
    }
    final material = await super.derive(pin);
    if (call == 2) secondMaterial = material;
    return material;
  }
}

class _RecordingPortableVaultStorage implements PortableVaultStreamingStorage {
  _RecordingPortableVaultStorage(this.delegate);

  final PortableVaultStreamingStorage delegate;
  final List<String> deleted = <String>[];
  String? failSuffix;

  @override
  Future<bool> hasAccess() => delegate.hasAccess();

  @override
  Future<List<String>> list(String path) => delegate.list(path);

  @override
  Future<Uint8List> read(String path) => delegate.read(path);

  @override
  Future<void> write(String path, Uint8List bytes) =>
      delegate.write(path, bytes);

  @override
  Future<PortableVaultWriteSession> beginWrite(String path) =>
      delegate.beginWrite(path);

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    if (failSuffix != null && path.endsWith(failSuffix!)) {
      throw const PortableVaultStorageException('forced delete failure');
    }
    await delegate.delete(path);
  }
}
