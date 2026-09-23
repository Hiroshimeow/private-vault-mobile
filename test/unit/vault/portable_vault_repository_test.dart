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
    'scan sweeps stale partial writes and reclaims orphan sidecars',
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
      final staleMillis = DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch;
      final partial = File(
        '${objects.path}${Platform.pathSeparator}'
        '${added.id}.pvb.partial-$staleMillis-deadbeef',
      );
      final thumbnail = File(
        '${objects.path}${Platform.pathSeparator}${added.id}.pvt',
      );
      await partial.writeAsBytes([1, 2, 3], flush: true);

      await File('${objects.path}${Platform.pathSeparator}${added.id}.pvb')
          .delete();
      await File('${objects.path}${Platform.pathSeparator}${added.id}.pvm')
          .delete();

      final scan = await repo.scan();

      expect(await partial.exists(), isFalse);
      expect(await thumbnail.exists(), isFalse);
      expect(scan.hasProblems, isFalse);
      expect(scan.orphanedSidecarCount, 1);
    },
  );

  test('scan ignores fresh partial writes that may still be active', () async {
    final repo = await repository('0000');
    final material = repo.session.requireMaterial();
    final objects = Directory(
      '${root.path}${Platform.pathSeparator}${material.namespaceId}'
      '${Platform.pathSeparator}objects',
    );
    await objects.create(recursive: true);
    final freshMillis = DateTime.now().millisecondsSinceEpoch;
    final partial = File(
      '${objects.path}${Platform.pathSeparator}'
      'active.pvb.partial-$freshMillis-live',
    );
    final sidecar = File('${objects.path}${Platform.pathSeparator}active.pvt');
    await partial.writeAsBytes([9, 8, 7], flush: true);
    await sidecar.writeAsBytes([6, 5, 4], flush: true);

    final scan = await repo.scan();

    expect(await partial.exists(), isTrue);
    expect(await sidecar.exists(), isTrue);
    expect(scan.orphanedSidecarCount, 0);
    expect(scan.hasProblems, isFalse);
  });

  test(
    'second repository preserves a stale partial owned by an active writer',
    () async {
      final storage = _StalePartialSharedStorage();
      final firstSession = PortableVaultSession();
      final secondSession = PortableVaultSession();
      await firstSession.open('0000');
      await secondSession.open('0000');
      final first = PortableVaultRepository(
        storage: storage,
        session: firstSession,
      );
      final second = PortableVaultRepository(
        storage: storage,
        session: secondSession,
      );
      final source = StreamController<List<int>>();

      final import = first.addStream(source.stream, kind: VaultItemKind.video);
      await storage.partialCreated.future;
      expect(storage.hasPartial, isTrue);

      final scanDuringWrite = await second.scan();
      expect(storage.hasPartial, isTrue);
      expect(scanDuringWrite.hasProblems, isFalse);

      source.add([1, 2, 3, 4]);
      await source.close();
      final item = await import;

      expect(storage.hasPartial, isFalse);
      expect(await second.readBytes(item.id), Uint8List.fromList([1, 2, 3, 4]));
    },
  );

  test('scan reclaims legacy and future-dated abandoned partials', () async {
    final repo = await repository('0000');
    final material = repo.session.requireMaterial();
    final objects = Directory(
      '${root.path}${Platform.pathSeparator}${material.namespaceId}'
      '${Platform.pathSeparator}objects',
    );
    await objects.create(recursive: true);
    final futureMillis = DateTime.now()
        .add(const Duration(days: 2))
        .millisecondsSinceEpoch;
    final legacy = File(
      '${objects.path}${Platform.pathSeparator}'
      'legacy.pvb.partial-deadbeef',
    );
    final future = File(
      '${objects.path}${Platform.pathSeparator}'
      'future.pvb.partial-$futureMillis-deadbeef',
    );
    await legacy.writeAsBytes([1], flush: true);
    await future.writeAsBytes([2], flush: true);

    final scan = await repo.scan();

    expect(await legacy.exists(), isFalse);
    expect(await future.exists(), isFalse);
    expect(scan.hasProblems, isFalse);
  });

  test(
    'orphan cache cleanup failure does not poison readable vault state',
    () async {
      final session = PortableVaultSession();
      await session.open('0000');
      final delegate = DirectoryPortableVaultStorage(() async => root);
      final storage = _RecordingPortableVaultStorage(delegate);
      final repo = PortableVaultRepository(storage: storage, session: session);
      final material = session.requireMaterial();
      final objects = Directory(
        '${root.path}${Platform.pathSeparator}${material.namespaceId}'
        '${Platform.pathSeparator}objects',
      );
      await objects.create(recursive: true);
      final orphanThumbnail = File(
        '${objects.path}${Platform.pathSeparator}orphan.pvt',
      );
      await orphanThumbnail.writeAsBytes([9, 9, 9], flush: true);
      storage.failSuffix = '.pvt';

      final scan = await repo.scan();

      expect(scan.hasProblems, isFalse);
      expect(scan.orphanedSidecarCount, 1);
      expect(await orphanThumbnail.exists(), isTrue);
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

  test('generation-owned clear cannot erase a newer session', () async {
    final session = PortableVaultSession();
    final firstGeneration = await session.openWithGeneration('0000');
    final firstNamespace = session.requireMaterial().namespaceId;

    final secondGeneration = await session.openWithGeneration('1234');
    final secondNamespace = session.requireMaterial().namespaceId;
    expect(secondNamespace, isNot(firstNamespace));

    session.clearIfGeneration(firstGeneration);
    expect(session.isOpen, isTrue);
    expect(session.generation, secondGeneration);
    expect(session.requireMaterial().namespaceId, secondNamespace);

    session.clearIfGeneration(secondGeneration);
    expect(session.isOpen, isFalse);
  });

  test(
    'PIN identity commit survives a lock boundary without reactivating session',
    () async {
      final session = PortableVaultSession();
      await session.open('0000');
      final repo = PortableVaultRepository(
        storage: DirectoryPortableVaultStorage(() async => root),
        session: session,
      );

      var committed = false;
      final outcome = await repo.switchSession('1234', () async {
        committed = true;
        session.clear();
      });

      expect(committed, isTrue);
      expect(outcome, PinSessionSwitchOutcome.committedSessionClosed);
      expect(session.isOpen, isFalse);
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

class _StalePartialSharedStorage implements PortableVaultStreamingStorage {
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Completer<String> partialCreated = Completer<String>();

  bool get hasPartial => _files.keys.any((path) => path.contains('.partial-'));

  @override
  Future<bool> hasAccess() async => true;

  @override
  Future<List<String>> list(String path) async {
    final prefix = path.isEmpty ? '' : '$path/';
    return _files.keys
        .where((candidate) => candidate.startsWith(prefix))
        .map((candidate) => candidate.substring(prefix.length))
        .where((name) => !name.contains('/'))
        .toList(growable: false);
  }

  @override
  Future<Uint8List> read(String path) async {
    final value = _files[path];
    if (value == null) {
      throw const PortableVaultStorageNotFoundException();
    }
    return Uint8List.fromList(value);
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    _files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }

  @override
  Future<PortableVaultWriteSession> beginWrite(String path) async {
    final staleMillis = DateTime.now()
        .subtract(const Duration(days: 2))
        .millisecondsSinceEpoch;
    final partial = '$path.partial-$staleMillis-shared';
    _files[partial] = Uint8List(0);
    if (!partialCreated.isCompleted) partialCreated.complete(partial);
    return _MemoryWriteSession(
      files: _files,
      targetPath: path,
      partialPath: partial,
    );
  }
}

class _MemoryWriteSession implements PortableVaultWriteSession {
  _MemoryWriteSession({
    required this.files,
    required this.targetPath,
    required this.partialPath,
  });

  final Map<String, Uint8List> files;
  final String targetPath;
  final String partialPath;
  final List<int> _bytes = <int>[];
  bool _closed = false;

  void _ensureOpen() {
    if (_closed) {
      throw const PortableVaultStorageException('Write session is closed');
    }
    if (!files.containsKey(partialPath)) {
      throw const PortableVaultStorageException('Active partial was reclaimed');
    }
  }

  @override
  Future<void> append(List<int> bytes) async {
    _ensureOpen();
    _bytes.addAll(bytes);
    files[partialPath] = Uint8List.fromList(_bytes);
  }

  @override
  Future<void> patch(int offset, List<int> bytes) async {
    _ensureOpen();
    if (offset < 0 || offset + bytes.length > _bytes.length) {
      throw const PortableVaultStorageException('Invalid patch range');
    }
    _bytes.setRange(offset, offset + bytes.length, bytes);
    files[partialPath] = Uint8List.fromList(_bytes);
  }

  @override
  Future<void> commit() async {
    _ensureOpen();
    _closed = true;
    files[targetPath] = Uint8List.fromList(_bytes);
    files.remove(partialPath);
  }

  @override
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    files.remove(partialPath);
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
