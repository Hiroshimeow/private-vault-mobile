import 'package:flutter/services.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_storage.dart';

class PortableVaultTreeBridge
    implements PortableVaultStreamingStorage, PortableVaultRootAccess {
  PortableVaultTreeBridge({
    this.channel = const MethodChannel('private_vault/portable_tree'),
  });

  final MethodChannel channel;

  @override
  Future<bool> hasRoot() async =>
      await channel.invokeMethod<bool>('hasRoot') ?? false;

  @override
  Future<bool> pickRoot() async =>
      await channel.invokeMethod<bool>('pickRoot') ?? false;

  @override
  Future<bool> hasAccess() => hasRoot();

  @override
  Future<List<String>> list(String path) async {
    try {
      final result = await channel.invokeListMethod<String>('list', {
        'path': path,
      });
      return result ?? const [];
    } on PlatformException catch (error) {
      throw PortableVaultStorageException(error.code);
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    try {
      final result = await channel.invokeMethod<Uint8List>('read', {
        'path': path,
      });
      if (result == null) {
        throw const PortableVaultStorageNotFoundException();
      }
      return result;
    } on PortableVaultStorageNotFoundException {
      rethrow;
    } on PlatformException catch (error) {
      throw PortableVaultStorageException(error.code);
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    try {
      final ok = await channel.invokeMethod<bool>('write', {
        'path': path,
        'bytes': bytes,
      });
      if (ok != true) throw const PortableVaultStorageException('write_failed');
    } on PortableVaultStorageException {
      rethrow;
    } on PlatformException catch (error) {
      throw PortableVaultStorageException(error.code);
    }
  }

  @override
  Future<PortableVaultWriteSession> beginWrite(String path) async {
    try {
      final handle = await channel.invokeMethod<int>('beginWrite', {
        'path': path,
      });
      if (handle == null) {
        throw const PortableVaultStorageException('begin_write_failed');
      }
      return _PortableVaultTreeWriteSession(channel, handle);
    } on PortableVaultStorageException {
      rethrow;
    } on PlatformException catch (error) {
      throw PortableVaultStorageException(error.code);
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      final ok = await channel.invokeMethod<bool>('delete', {'path': path});
      if (ok != true) {
        throw const PortableVaultStorageException('delete_failed');
      }
    } on PortableVaultStorageException {
      rethrow;
    } on PlatformException catch (error) {
      throw PortableVaultStorageException(error.code);
    }
  }
}

class _PortableVaultTreeWriteSession implements PortableVaultWriteSession {
  _PortableVaultTreeWriteSession(this.channel, this.handle);

  final MethodChannel channel;
  final int handle;
  bool _closed = false;

  void _ensureOpen() {
    if (_closed) {
      throw const PortableVaultStorageException('Write session is closed');
    }
  }

  @override
  Future<void> append(List<int> bytes) async {
    if (bytes.isEmpty) return;
    _ensureOpen();
    try {
      final ok = await channel.invokeMethod<bool>('appendWrite', {
        'handle': handle,
        'bytes': Uint8List.fromList(bytes),
      });
      if (ok != true) {
        throw const PortableVaultStorageException('append_write_failed');
      }
    } on PortableVaultStorageException {
      rethrow;
    } on PlatformException catch (error) {
      throw PortableVaultStorageException(error.code);
    }
  }

  @override
  Future<void> patch(int offset, List<int> bytes) async {
    _ensureOpen();
    try {
      final ok = await channel.invokeMethod<bool>('patchWrite', {
        'handle': handle,
        'offset': offset,
        'bytes': Uint8List.fromList(bytes),
      });
      if (ok != true) {
        throw const PortableVaultStorageException('patch_write_failed');
      }
    } on PortableVaultStorageException {
      rethrow;
    } on PlatformException catch (error) {
      throw PortableVaultStorageException(error.code);
    }
  }

  @override
  Future<void> commit() async {
    _ensureOpen();
    try {
      final ok = await channel.invokeMethod<bool>('commitWrite', {
        'handle': handle,
      });
      if (ok != true) {
        throw const PortableVaultStorageException('commit_write_failed');
      }
      _closed = true;
    } on PortableVaultStorageException {
      rethrow;
    } on PlatformException catch (error) {
      throw PortableVaultStorageException(error.code);
    }
  }

  @override
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    try {
      await channel.invokeMethod<bool>('abortWrite', {'handle': handle});
    } on PlatformException {
      // Best effort cleanup. Preserve the original import failure.
    }
  }
}
