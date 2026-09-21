import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:private_vault_mobile/features/vault/vault_repository.dart';
import 'package:private_vault_mobile/platform/generated/work_profile_api.g.dart'
    as native;

abstract interface class VaultShuttle {
  Future<List<VaultItem>> listVaultItems();

  Future<void> shareToIsolatedApp({
    required VaultItem item,
    required String packageName,
  });

  Future<void> purgeStagedPlaintext();
}

abstract interface class VaultShuttleBridge {
  Future<void> shareStagedFile({
    required String packageName,
    required String stagedFileName,
    required String mimeType,
    required String displayName,
  });
}

typedef VaultShuttleTempDirectory = Future<Directory> Function();

class VaultShuttleException implements Exception {
  const VaultShuttleException(this.message);

  final String message;

  @override
  String toString() => 'VaultShuttleException: $message';
}

class PigeonVaultShuttleBridge implements VaultShuttleBridge {
  PigeonVaultShuttleBridge({native.WorkProfileHostApi? api})
    : _api = api ?? native.WorkProfileHostApi();

  final native.WorkProfileHostApi _api;

  @override
  Future<void> shareStagedFile({
    required String packageName,
    required String stagedFileName,
    required String mimeType,
    required String displayName,
  }) async {
    final result = await _api.shareVaultFileToWorkApp(
      packageName,
      stagedFileName,
      mimeType,
      displayName,
    );
    if (!result.ok) {
      throw VaultShuttleException(
        result.message ?? 'Android could not share this vault file.',
      );
    }
  }
}

class VaultShuttleService implements VaultShuttle {
  factory VaultShuttleService({
    required VaultRepository repository,
    required VaultShuttleBridge bridge,
    required VaultShuttleTempDirectory tempDirectory,
    Duration stagedTtl = const Duration(minutes: 5),
  }) => VaultShuttleService._(repository, bridge, tempDirectory, stagedTtl);

  VaultShuttleService._(
    this._repository,
    this._bridge,
    this._tempDirectory,
    this._stagedTtl,
  );

  static const transferDirectoryName = 'vault-shuttle';

  final VaultRepository _repository;
  final VaultShuttleBridge _bridge;
  final VaultShuttleTempDirectory _tempDirectory;
  final Duration _stagedTtl;
  final Random _random = Random.secure();
  final Map<String, Timer> _expiryTimers = {};

  @override
  Future<List<VaultItem>> listVaultItems() => _repository.list();

  @override
  Future<void> shareToIsolatedApp({
    required VaultItem item,
    required String packageName,
  }) async {
    final bytes = await _repository.readBytes(item.id);
    final root = await _transferRoot();
    final file = File(p.join(root.path, _opaqueName()));
    await file.writeAsBytes(bytes, flush: true);

    try {
      await _bridge.shareStagedFile(
        packageName: packageName,
        stagedFileName: p.basename(file.path),
        mimeType: _mimeType(item.kind),
        displayName: _displayName(item.kind),
      );
    } catch (_) {
      await _deleteStaged(file);
      rethrow;
    }

    _expiryTimers[file.path]?.cancel();
    _expiryTimers[file.path] = Timer(
      _stagedTtl,
      () => unawaited(_deleteStaged(file)),
    );
  }

  @override
  Future<void> purgeStagedPlaintext() async {
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();

    final temp = await _tempDirectory();
    final root = Directory(p.join(temp.path, transferDirectoryName));
    if (!await root.exists()) return;

    await for (final entry in root.list(followLinks: false)) {
      if (entry is File) {
        await _deleteFileBestEffort(entry);
      }
    }
  }

  Future<Directory> _transferRoot() async {
    final temp = await _tempDirectory();
    final root = Directory(p.join(temp.path, transferDirectoryName));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<void> _deleteStaged(File file) async {
    _expiryTimers.remove(file.path)?.cancel();
    await _deleteFileBestEffort(file);
  }

  Future<void> _deleteFileBestEffort(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // The staged grant is already bounded by app-private cache and URI access.
      // Lock paths retry by purging the directory again on the next boundary.
    }
  }

  String _opaqueName() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  String _mimeType(VaultItemKind kind) => switch (kind) {
    VaultItemKind.note => 'text/plain',
    VaultItemKind.image => 'image/*',
    VaultItemKind.video => 'video/*',
    VaultItemKind.document ||
    VaultItemKind.unknown => 'application/octet-stream',
  };

  String _displayName(VaultItemKind kind) => switch (kind) {
    VaultItemKind.note => 'vault-note.txt',
    VaultItemKind.image => 'vault-image',
    VaultItemKind.video => 'vault-video',
    VaultItemKind.document => 'vault-document',
    VaultItemKind.unknown => 'vault-item',
  };
}
