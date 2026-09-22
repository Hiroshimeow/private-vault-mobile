import 'dart:io';
import 'dart:typed_data';

abstract interface class PortableVaultRootAccess {
  Future<bool> hasRoot();
  Future<bool> pickRoot();
}

abstract interface class PortableVaultStorage {
  Future<bool> hasAccess();
  Future<List<String>> list(String path);
  Future<Uint8List> read(String path);
  Future<void> write(String path, Uint8List bytes);
  Future<void> delete(String path);
}

typedef PortableVaultRootDirectory = Future<Directory> Function();

class DirectoryPortableVaultStorage implements PortableVaultStorage {
  DirectoryPortableVaultStorage(this.rootDirectory);

  final PortableVaultRootDirectory rootDirectory;

  @override
  Future<bool> hasAccess() async {
    try {
      final root = await rootDirectory();
      if (!await root.exists()) await root.create(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<List<String>> list(String path) async {
    try {
      final directory = await _directory(path);
      if (!await directory.exists()) return const [];
      return await directory
          .list()
          .where((entity) => entity is File)
          .map((entity) => entity.path.split(Platform.pathSeparator).last)
          .toList();
    } on FileSystemException catch (error) {
      throw PortableVaultStorageException(error.message);
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    try {
      final file = await _file(path);
      if (!await file.exists()) {
        throw const PortableVaultStorageNotFoundException();
      }
      return Uint8List.fromList(await file.readAsBytes());
    } on PortableVaultStorageNotFoundException {
      rethrow;
    } on FileSystemException catch (error) {
      throw PortableVaultStorageException(error.message);
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    try {
      final file = await _file(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw PortableVaultStorageException(error.message);
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      final file = await _file(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      throw PortableVaultStorageException(error.message);
    }
  }

  Future<Directory> _directory(String path) async {
    final root = await rootDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    return Directory(_join(root.path, path));
  }

  Future<File> _file(String path) async {
    final root = await rootDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    return File(_join(root.path, path));
  }

  String _join(String root, String relative) {
    final normalized = relative
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .join(Platform.pathSeparator);
    return normalized.isEmpty
        ? root
        : '$root${Platform.pathSeparator}$normalized';
  }
}

class PortableVaultStorageException implements Exception {
  const PortableVaultStorageException(this.message);
  final String message;
}

class PortableVaultStorageNotFoundException
    extends PortableVaultStorageException {
  const PortableVaultStorageNotFoundException() : super('Object not found');
}
