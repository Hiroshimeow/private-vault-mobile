import 'package:flutter/services.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_storage.dart';

class PortableVaultTreeBridge
    implements PortableVaultStorage, PortableVaultRootAccess {
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
