import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';
import 'package:private_vault_mobile/platform/media_source_bridge.dart';

class PickedVaultData {
  const PickedVaultData({required this.bytes, required this.kind});

  final Uint8List bytes;
  final VaultItemKind kind;
}

class PickedVaultSource {
  const PickedVaultSource({
    required this.name,
    required this.kind,
    required this.openRead,
    this.deleteSource,
    this.buildThumbnail,
  });

  final String name;
  final VaultItemKind kind;
  final Stream<List<int>> Function() openRead;
  final Future<void> Function()? deleteSource;
  final Future<Uint8List?> Function()? buildThumbnail;
}

class VaultImportFailure {
  const VaultImportFailure({required this.name, required this.error});

  final String name;
  final Object error;
}

class VaultImportProgress {
  const VaultImportProgress({
    required this.currentIndex,
    required this.total,
    required this.name,
    required this.importedCount,
    required this.failedCount,
  });

  final int currentIndex;
  final int total;
  final String name;
  final int importedCount;
  final int failedCount;
}

class VaultImportBatchResult {
  const VaultImportBatchResult({
    required this.imported,
    required this.failures,
  });

  final List<VaultItem> imported;
  final List<VaultImportFailure> failures;

  int get importedCount => imported.length;
  int get failedCount => failures.length;
}

typedef PickVaultData = Future<PickedVaultData?> Function();
typedef PickVaultSourceList = Future<List<PickedVaultSource>> Function();
typedef SaveExport = Future<bool> Function(String fileName, Uint8List bytes);
typedef VaultImportProgressCallback = void Function(
  VaultImportProgress progress,
);

class MediaVaultService {
  factory MediaVaultService({
    required VaultRepository repository,
    required PickVaultData pickImport,
    required PickVaultData capturePhoto,
    required SaveExport saveExport,
    PickVaultSourceList? pickImports,
  }) => MediaVaultService._(
    repository,
    pickImport,
    capturePhoto,
    saveExport,
    pickImports,
  );

  MediaVaultService._(
    this._repository,
    this._pickImport,
    this._capturePhoto,
    this._saveExport,
    this._pickImports,
  );

  final VaultRepository _repository;
  final PickVaultData _pickImport;
  final PickVaultData _capturePhoto;
  final SaveExport _saveExport;
  final PickVaultSourceList? _pickImports;

  Future<VaultItem?> importFile() async {
    final picked = await _pickImport();
    if (picked == null) return null;
    final item = await _repository.addBytes(picked.bytes, kind: picked.kind);
    await _cacheThumbnail(
      item,
      picked.kind == VaultItemKind.image
          ? () => Isolate.run(() => _buildImageThumbnail(picked.bytes))
          : null,
    );
    return item;
  }

  Future<VaultImportBatchResult> importFiles({
    VaultImportProgressCallback? onProgress,
    bool moveSource = false,
  }) async {
    final picker = _pickImports;
    late final List<PickedVaultSource> sources;
    if (picker != null) {
      sources = await picker();
    } else {
      final picked = await _pickImport();
      sources = picked == null
          ? const []
          : [
              PickedVaultSource(
                name: 'selected-file',
                kind: picked.kind,
                openRead: () => Stream<List<int>>.value(picked.bytes),
              ),
            ];
    }

    final imported = <VaultItem>[];
    final failures = <VaultImportFailure>[];
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      onProgress?.call(
        VaultImportProgress(
          currentIndex: index + 1,
          total: sources.length,
          name: source.name,
          importedCount: imported.length,
          failedCount: failures.length,
        ),
      );
      try {
        final item = await _importSource(source);
        imported.add(item);
        if (moveSource) {
          final deleteSource = source.deleteSource;
          if (deleteSource == null) {
            throw StateError('Source cannot be deleted after import');
          }
          await deleteSource();
        }
      } on Object catch (error) {
        failures.add(VaultImportFailure(name: source.name, error: error));
      }
    }
    return VaultImportBatchResult(
      imported: List.unmodifiable(imported),
      failures: List.unmodifiable(failures),
    );
  }

  Future<VaultItem> _importSource(PickedVaultSource source) async {
    final repository = _repository;
    final VaultItem item;
    if (repository is StreamingVaultRepository) {
      item = await repository.addStream(source.openRead(), kind: source.kind);
    } else {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in source.openRead()) {
        if (chunk.isNotEmpty) builder.add(chunk);
      }
      item = await repository.addBytes(builder.takeBytes(), kind: source.kind);
    }
    await _cacheThumbnail(item, source.buildThumbnail);
    return item;
  }

  Future<void> _cacheThumbnail(
    VaultItem item,
    Future<Uint8List?> Function()? buildThumbnail,
  ) async {
    final repository = _repository;
    if (repository is! VaultThumbnailRepository || buildThumbnail == null) {
      return;
    }
    try {
      final thumbnail = await buildThumbnail();
      if (thumbnail != null && thumbnail.isNotEmpty) {
        await repository.writeThumbnail(item.id, thumbnail);
      }
    } on Object {
      // Thumbnail data is a reconstructible cache; import success is authoritative.
    }
  }

  Future<void> cacheImageThumbnail(VaultItem item, Uint8List bytes) async {
    if (item.kind != VaultItemKind.image) return;
    await _cacheThumbnail(
      item,
      () => Isolate.run(() => _buildImageThumbnail(bytes)),
    );
  }

  Future<VaultItem?> capturePhoto() async {
    final picked = await _capturePhoto();
    if (picked == null) return null;
    final item = await _repository.addBytes(picked.bytes, kind: picked.kind);
    await _cacheThumbnail(
      item,
      picked.kind == VaultItemKind.image
          ? () => Isolate.run(() => _buildImageThumbnail(picked.bytes))
          : null,
    );
    return item;
  }

  Future<bool> export(String id, {required String fileName}) async {
    final bytes = await _repository.readBytes(id);
    return _saveExport(fileName, bytes);
  }

  static Future<PickedVaultData?> pickDeviceFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();

    return PickedVaultData(
      bytes: Uint8List.fromList(bytes),
      kind: _kindFromName(picked.name),
    );
  }

  static Future<List<PickedVaultSource>> pickDeviceFiles({
    Future<void> Function(Uri uri)? deleteUri,
    Future<Uint8List?> Function(Uri uri)? videoThumbnail,
  }) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      androidOptions: const FilePickerAndroidOptions(
        safOptions: AndroidSAFOptions(
          accessMode: AndroidSAFAccessMode.readWrite,
          grant: AndroidSAFGrant.transient,
          persistGrant: false,
        ),
      ),
    );
    final mediaBridge = const PlatformMediaSourceBridge();
    final deleteSourceUri = deleteUri ?? mediaBridge.delete;
    final videoThumbnailLoader = videoThumbnail ?? mediaBridge.videoThumbnail;
    final sources = <PickedVaultSource>[];
    for (final file in picked) {
      final kind = _kindFromName(file.name);
      final uri = file is AndroidPlatformFile
          ? file.safHandle?.uri ?? file.uri
          : file.uri;
      sources.add(
        PickedVaultSource(
          name: file.name,
          kind: kind,
          openRead: () => file.readAsByteStream(),
          buildThumbnail: switch (kind) {
            VaultItemKind.image => () async {
              final bytes = Uint8List.fromList(await file.readAsBytes());
              return Isolate.run(() => _buildImageThumbnail(bytes));
            },
            VaultItemKind.video when Platform.isAndroid =>
              () => videoThumbnailLoader(uri),
            _ => null,
          },
          deleteSource: () => deleteSourceUri(uri),
        ),
      );
    }
    return List.unmodifiable(sources);
  }

  static Future<PickedVaultData?> captureDevicePhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
      requestFullMetadata: false,
    );
    if (image == null) return null;

    final bytes = await image.readAsBytes();
    final temporary = File(image.path);
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } on FileSystemException {
        // Best effort only: mobile camera plugins may own the temp lifecycle.
      }
    }
    return PickedVaultData(
      bytes: Uint8List.fromList(bytes),
      kind: VaultItemKind.image,
    );
  }

  static Future<bool> saveDeviceExport(String fileName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    return uri != null;
  }

  static Uint8List? _buildImageThumbnail(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final width = oriented.width > 384 ? 384 : oriented.width;
    final thumbnail = width == oriented.width
        ? oriented
        : img.copyResize(oriented, width: width);
    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 78));
  }

  static VaultItemKind _kindFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic')) {
      return VaultItemKind.image;
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm')) {
      return VaultItemKind.video;
    }
    return VaultItemKind.document;
  }
}
