import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class PickedVaultData {
  const PickedVaultData({required this.bytes, required this.kind});

  final Uint8List bytes;
  final VaultItemKind kind;
}

typedef PickVaultData = Future<PickedVaultData?> Function();
typedef PickVaultDataList = Future<List<PickedVaultData>> Function();
typedef SaveExport = Future<bool> Function(String fileName, Uint8List bytes);

class MediaVaultService {
  factory MediaVaultService({
    required VaultRepository repository,
    required PickVaultData pickImport,
    required PickVaultData capturePhoto,
    required SaveExport saveExport,
    PickVaultDataList? pickImports,
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
  final PickVaultDataList? _pickImports;

  Future<VaultItem?> importFile() async {
    final picked = await _pickImport();
    if (picked == null) return null;
    return _repository.addBytes(picked.bytes, kind: picked.kind);
  }

  Future<List<VaultItem>> importFiles() async {
    final picker = _pickImports;
    final picked = picker != null ? await picker() : [?await _pickImport()];
    final imported = <VaultItem>[];
    for (final item in picked) {
      imported.add(await _repository.addBytes(item.bytes, kind: item.kind));
    }
    return imported;
  }

  Future<VaultItem?> capturePhoto() async {
    final picked = await _capturePhoto();
    if (picked == null) return null;
    return _repository.addBytes(picked.bytes, kind: picked.kind);
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

  static Future<List<PickedVaultData>> pickDeviceFiles() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final result = <PickedVaultData>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      result.add(
        PickedVaultData(
          bytes: Uint8List.fromList(bytes),
          kind: _kindFromName(file.name),
        ),
      );
    }
    return result;
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
