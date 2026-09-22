import 'dart:io';
import 'dart:math';
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

abstract interface class PortableVaultWriteSession {
  Future<void> append(List<int> bytes);
  Future<void> patch(int offset, List<int> bytes);
  Future<void> commit();
  Future<void> abort();
}

abstract interface class PortableVaultStreamingStorage
    implements PortableVaultStorage {
  Future<PortableVaultWriteSession> beginWrite(String path);
}

typedef PortableVaultRootDirectory = Future<Directory> Function();

class DirectoryPortableVaultStorage implements PortableVaultStreamingStorage {
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
  Future<PortableVaultWriteSession> beginWrite(String path) async {
    try {
      final target = await _file(path);
      await target.parent.create(recursive: true);
      if (await target.exists()) {
        throw const PortableVaultStorageException('Object already exists');
      }
      final random = Random.secure();
      final suffix = List<int>.generate(
        8,
        (_) => random.nextInt(256),
      ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
      final temporary = File('${target.path}.partial-$suffix');
      final file = await temporary.open(mode: FileMode.write);
      return _DirectoryPortableVaultWriteSession(
        target: target,
        temporary: temporary,
        file: file,
      );
    } on PortableVaultStorageException {
      rethrow;
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

class _DirectoryPortableVaultWriteSession implements PortableVaultWriteSession {
  _DirectoryPortableVaultWriteSession({
    required this.target,
    required this.temporary,
    required this._file,
  });

  final File target;
  final File temporary;
  RandomAccessFile? _file;

  RandomAccessFile _requiredFile() {
    final file = _file;
    if (file == null) {
      throw const PortableVaultStorageException('Write session is closed');
    }
    return file;
  }

  @override
  Future<void> append(List<int> bytes) async {
    if (bytes.isEmpty) return;
    try {
      await _requiredFile().writeFrom(bytes);
    } on FileSystemException catch (error) {
      throw PortableVaultStorageException(error.message);
    }
  }

  @override
  Future<void> patch(int offset, List<int> bytes) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must be non-negative');
    }
    try {
      final file = _requiredFile();
      final end = await file.position();
      if (offset + bytes.length > end) {
        throw const PortableVaultStorageException(
          'Patch exceeds written object length',
        );
      }
      await file.setPosition(offset);
      await file.writeFrom(bytes);
      await file.setPosition(end);
    } on PortableVaultStorageException {
      rethrow;
    } on FileSystemException catch (error) {
      throw PortableVaultStorageException(error.message);
    }
  }

  @override
  Future<void> commit() async {
    final file = _requiredFile();
    _file = null;
    try {
      await file.flush();
      await file.close();
      await temporary.rename(target.path);
    } on FileSystemException catch (error) {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Preserve the original commit failure.
        }
      }
      throw PortableVaultStorageException(error.message);
    }
  }

  @override
  Future<void> abort() async {
    final file = _file;
    _file = null;
    if (file != null) {
      try {
        await file.close();
      } on FileSystemException {
        // Best effort cleanup.
      }
    }
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } on FileSystemException {
        // Best effort cleanup.
      }
    }
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
