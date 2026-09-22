import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:private_vault_mobile/app/private_vault_theme.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_repository.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';
import 'package:video_player/video_player.dart';

class VaultHome extends StatefulWidget {
  const VaultHome({
    super.key,
    required this.repository,
    required this.media,
    required this.confirmExport,
    this.onSystemHandoffChanged,
  });

  final VaultRepository repository;
  final MediaVaultService media;
  final bool confirmExport;
  final ValueChanged<bool>? onSystemHandoffChanged;

  @override
  State<VaultHome> createState() => _VaultHomeState();
}

class _VaultHomeState extends State<VaultHome> {
  List<VaultItem> _items = const [];
  bool _busy = true;
  String? _error;
  String? _warning;
  VaultImportProgress? _importProgress;
  static const _maxThumbnailCacheEntries = 64;
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _thumbnailFutures.clear();
    _selectedIds.clear();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final repository = widget.repository;
      if (repository is VaultScanAwareRepository) {
        final scan = await repository.scan();
        if (!mounted) return;
        setState(() {
          _items = scan.items;
          _busy = false;
          _error = null;
          _warning = scan.hasProblems
              ? '${scan.unreadableCount} protected item(s) could not be read '
                    '(corrupt: ${scan.corruptCount}, unsupported: '
                    '${scan.unsupportedCount}, access: '
                    '${scan.storageFailureCount}).'
              : null;
        });
        return;
      }

      final items = await repository.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _busy = false;
        _error = null;
        _warning = null;
      });
    } on PortableVaultRootUnavailableException {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _busy = false;
        _warning = null;
        _error = 'Portable Vault folder is not authorized. Choose a shared folder in Settings.';
      });
    } on MissingVaultKeyException {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _busy = false;
        _warning = null;
        _error = 'Protected key unavailable. Existing items stay locked.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _warning = null;
        _error = 'Protected items could not be loaded.';
      });
    }
  }

  Future<Uint8List?>? _thumbnailFor(VaultItem item) {
    if (item.kind != VaultItemKind.image && item.kind != VaultItemKind.video) {
      return null;
    }
    final repository = widget.repository;
    if (repository is! VaultThumbnailRepository) return null;
    final cached = _thumbnailFutures.remove(item.id);
    if (cached != null) {
      _thumbnailFutures[item.id] = cached;
      return cached;
    }
    final future = repository.readThumbnail(item.id);
    _thumbnailFutures[item.id] = future;
    while (_thumbnailFutures.length > _maxThumbnailCacheEntries) {
      _thumbnailFutures.remove(_thumbnailFutures.keys.first);
    }
    return future;
  }

  void _toggleSelection(VaultItem item) {
    setState(() {
      if (!_selectedIds.add(item.id)) {
        _selectedIds.remove(item.id);
      }
    });
  }

  void _clearSelection() {
    if (_selectedIds.isEmpty) return;
    setState(_selectedIds.clear);
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text('Delete $count protected item(s)?'),
        content: const Text(
          'This removes the selected Vault copies. Flash storage does not guarantee forensic secure erase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ids = List<String>.from(_selectedIds);
    var deleted = 0;
    var failed = 0;
    for (final id in ids) {
      try {
        await widget.repository.delete(id);
        _thumbnailFutures.remove(id);
        deleted += 1;
      } on Object {
        failed += 1;
      }
    }
    if (!mounted) return;
    _clearSelection();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Deleted $deleted/${ids.length} item(s).'
                : 'Deleted $deleted/${ids.length} item(s); $failed failed.',
          ),
        ),
      );
  }

  String _exportFileName(VaultItem item) {
    final shortId = item.id.length <= 8 ? item.id : item.id.substring(0, 8);
    return 'private-item-$shortId.bin';
  }

  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty) return;
    if (widget.confirmExport) {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text('Export ${_selectedIds.length} protected item(s)?'),
          content: const Text(
            'Exported copies leave protected app storage and may be visible to other apps.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Export'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final items = _items
        .where((item) => _selectedIds.contains(item.id))
        .toList(growable: false);
    var exported = 0;
    var failed = 0;
    widget.onSystemHandoffChanged?.call(true);
    try {
      for (final item in items) {
        try {
          final saved = await widget.media.export(
            item.id,
            fileName: _exportFileName(item),
          );
          if (saved) {
            exported += 1;
          } else {
            failed += 1;
          }
        } on Object {
          failed += 1;
        }
      }
    } finally {
      widget.onSystemHandoffChanged?.call(false);
    }
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Exported $exported/${items.length} item(s).'
                : 'Exported $exported/${items.length} item(s); $failed not exported.',
          ),
        ),
      );
  }

  Future<void> _chooseImportMode() async {
    final moveSource = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: false,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('vault-import-copy'),
              leading: const Icon(Icons.content_copy_outlined),
              title: const Text('Copy to Vault'),
              subtitle: const Text('Keep the original file after import.'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            ListTile(
              key: const Key('vault-import-move'),
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Move to Vault'),
              subtitle: const Text(
                'Delete the original only after the protected copy is committed.',
              ),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (moveSource == null || !mounted) return;
    await _import(moveSource: moveSource);
  }

  Future<void> _import({required bool moveSource}) async {
    setState(() {
      _busy = true;
      _importProgress = null;
    });
    widget.onSystemHandoffChanged?.call(true);
    late final VaultImportBatchResult result;
    try {
      result = await widget.media.importFiles(
        moveSource: moveSource,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _importProgress = progress);
        },
      );
    } finally {
      widget.onSystemHandoffChanged?.call(false);
      if (mounted) setState(() => _importProgress = null);
      await _reload();
    }
    if (!mounted) return;
    final verb = moveSource ? 'Moved' : 'Imported';
    final message = result.failedCount == 0
        ? '$verb ${result.importedCount} item(s).'
        : '$verb ${result.importedCount} item(s); '
              '${result.failedCount} operation(s) need attention.';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capture() async {
    setState(() => _busy = true);
    widget.onSystemHandoffChanged?.call(true);
    try {
      await widget.media.capturePhoto();
    } finally {
      widget.onSystemHandoffChanged?.call(false);
      await _reload();
    }
  }

  Future<void> _newNote() async {
    var draft = '';
    final note = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New protected note'),
        content: TextField(
          key: const Key('vault-note-input'),
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          maxLength: 20000,
          onChanged: (value) => draft = value,
          decoration: const InputDecoration(
            hintText: 'Write a note stored only in the encrypted vault',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = draft.trim();
              if (trimmed.isNotEmpty) {
                Navigator.pop(dialogContext, trimmed);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note == null) return;

    setState(() => _busy = true);
    try {
      await widget.repository.addBytes(
        Uint8List.fromList(utf8.encode(note)),
        kind: VaultItemKind.note,
      );
    } finally {
      await _reload();
    }
  }

  Future<void> _open(VaultItem item) async {
    File? previewFile;
    try {
      final supportsThumbnail =
          item.kind == VaultItemKind.image || item.kind == VaultItemKind.video;
      final cachedThumbnail = supportsThumbnail
          ? await _thumbnailFor(item)
          : null;
      final bytes = await widget.repository.readBytes(item.id);
      if (!mounted) return;

      if (item.kind == VaultItemKind.image && cachedThumbnail == null) {
        await widget.media.cacheImageThumbnail(item, bytes);
        _thumbnailFutures.remove(item.id);
      }

      if (item.kind == VaultItemKind.video) {
        previewFile = await widget.media.createVideoPreviewFile(item, bytes);
        if (cachedThumbnail == null) {
          await widget.media.cacheVideoThumbnail(
            item,
            Uri.file(previewFile.path),
          );
          _thumbnailFutures.remove(item.id);
        }
      }

      if (!mounted) return;
      if (item.kind == VaultItemKind.image) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => _FullScreenImagePreview(
              bytes: bytes,
              onExport: () => _confirmExport(item),
              onDelete: () => _confirmDelete(item),
            ),
          ),
        );
      } else if (item.kind == VaultItemKind.video && previewFile != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => _FullScreenVideoPreview(
              file: previewFile!,
              onExport: () => _confirmExport(item),
              onDelete: () => _confirmDelete(item),
            ),
          ),
        );
      } else {
        await showModalBottomSheet<void>(
          context: context,
          useRootNavigator: false,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => _VaultPreview(
            item: item,
            bytes: bytes,
            onExport: () => _confirmExport(item),
            onDelete: () => _confirmDelete(item),
          ),
        );
      }
      if (item.kind == VaultItemKind.unknown && mounted) {
        await _reload();
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item could not be decrypted.')),
      );
    } finally {
      final file = previewFile;
      if (file != null) {
        await widget.media.deletePreviewFile(file);
      }
    }
  }

  Future<void> _confirmExport(VaultItem item) async {
    if (widget.confirmExport) {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Export this item?'),
          content: const Text(
            'The exported copy leaves protected app storage and may be visible to other apps.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Export'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    widget.onSystemHandoffChanged?.call(true);
    bool ok;
    try {
      ok = await widget.media.export(item.id, fileName: _exportFileName(item));
    } finally {
      widget.onSystemHandoffChanged?.call(false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Exported' : 'Export canceled')),
    );
  }

  Future<void> _confirmDelete(VaultItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Delete from vault?'),
        content: const Text(
          'This removes the app copy. Flash storage does not guarantee forensic secure erase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.repository.delete(item.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      final progress = _importProgress;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (progress != null) ...[
              const SizedBox(height: 12),
              Text(
                'Importing ${progress.currentIndex}/${progress.total}: '
                '${progress.name}',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('vault-import'),
                      onPressed: _chooseImportMode,
                      icon: const Icon(Icons.add),
                      label: const Text('Import'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('vault-camera'),
                      onPressed: _capture,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('vault-new-note'),
                      onPressed: _newNote,
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('Note'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: _selectedIds.isEmpty
              ? Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Protected items',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${_items.length} items',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedIds.length} selected',
                        key: const Key('vault-selection-count'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      key: const Key('vault-selection-export'),
                      tooltip: 'Export selected',
                      onPressed: _exportSelected,
                      icon: const Icon(Icons.ios_share_outlined),
                    ),
                    IconButton(
                      key: const Key('vault-selection-delete'),
                      tooltip: 'Delete selected',
                      onPressed: _deleteSelected,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    IconButton(
                      key: const Key('vault-selection-clear'),
                      tooltip: 'Clear selection',
                      onPressed: _clearSelection,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
        ),
        if (_warning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: const Text('Some protected items are unreadable'),
                subtitle: Text(_warning!),
              ),
            ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: PrivateVaultTheme.motionDuration(context),
            child: _error != null
                ? Center(
                    key: const ValueKey('vault-error'),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _items.isEmpty
                ? const Center(
                    key: ValueKey('vault-empty'),
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No protected items yet. Import, capture, or create a note.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Semantics(
                    key: const ValueKey('vault-grid'),
                    label: 'Protected item gallery',
                    container: true,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 900
                            ? 4
                            : constraints.maxWidth >= 600
                            ? 3
                            : 2;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.9,
                              ),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final selected = _selectedIds.contains(item.id);
                            return _VaultGridTile(
                              item: item,
                              icon: _iconFor(item.kind),
                              label: _labelFor(item.kind),
                              timestamp: _shortTimestamp(item.createdAt),
                              thumbnail: _thumbnailFor(item),
                              selected: selected,
                              onTap: () => _selectedIds.isEmpty
                                  ? _open(item)
                                  : _toggleSelection(item),
                              onLongPress: () => _toggleSelection(item),
                            );
                          },
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(VaultItemKind kind) => switch (kind) {
    VaultItemKind.unknown => Icons.lock_outline,
    VaultItemKind.note => Icons.note_outlined,
    VaultItemKind.image => Icons.image_outlined,
    VaultItemKind.video => Icons.video_file_outlined,
    VaultItemKind.document => Icons.description_outlined,
  };

  String _labelFor(VaultItemKind kind) => switch (kind) {
    VaultItemKind.unknown => 'Protected legacy item',
    VaultItemKind.note => 'Protected note',
    VaultItemKind.image => 'Protected image',
    VaultItemKind.video => 'Protected video',
    VaultItemKind.document => 'Protected document',
  };

  String _shortTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _VaultGridTile extends StatelessWidget {
  const _VaultGridTile({
    required this.item,
    required this.icon,
    required this.label,
    required this.timestamp,
    required this.thumbnail,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final VaultItem item;
  final IconData icon;
  final String label;
  final String timestamp;
  final Future<Uint8List?>? thumbnail;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget fallback() =>
        Center(child: Icon(icon, size: 42, color: colors.onSurfaceVariant));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('vault-tile-${item.id}'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: colors.surfaceContainerHighest,
                    child: thumbnail == null
                        ? fallback()
                        : FutureBuilder<Uint8List?>(
                            future: thumbnail,
                            builder: (context, snapshot) {
                              final bytes = snapshot.data;
                              if (bytes == null || bytes.isEmpty) {
                                return fallback();
                              }
                              return Image.memory(
                                bytes,
                                key: Key('vault-thumbnail-${item.id}'),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) => fallback(),
                              );
                            },
                          ),
                  ),
                  if (item.kind == VaultItemKind.video)
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(
                            Icons.check,
                            size: 18,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                item.kind == VaultItemKind.unknown ? 'Legacy item' : timestamp,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenImagePreview extends StatelessWidget {
  const _FullScreenImagePreview({
    required this.bytes,
    required this.onExport,
    required this.onDelete,
  });

  final Uint8List bytes;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            key: const Key('vault-image-export'),
            tooltip: 'Export image',
            onPressed: onExport,
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            key: const Key('vault-image-delete'),
            tooltip: 'Delete image',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.memory(
            bytes,
            key: const Key('vault-fullscreen-image'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              'Image data could not be displayed.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenVideoPreview extends StatefulWidget {
  const _FullScreenVideoPreview({
    required this.file,
    required this.onExport,
    required this.onDelete,
  });

  final File file;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  State<_FullScreenVideoPreview> createState() =>
      _FullScreenVideoPreviewState();
}

class _FullScreenVideoPreviewState extends State<_FullScreenVideoPreview> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initialize = _controller.initialize().then((_) {
      if (mounted) {
        unawaited(_controller.play());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            key: const Key('vault-video-export'),
            tooltip: 'Export video',
            onPressed: widget.onExport,
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            key: const Key('vault-video-delete'),
            tooltip: 'Delete video',
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initialize,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Video data could not be played.',
                style: TextStyle(color: Colors.white),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final aspectRatio = _controller.value.aspectRatio > 0
              ? _controller.value.aspectRatio
              : 16 / 9;
          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: VideoPlayer(
                        _controller,
                        key: const Key('vault-video-player'),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => IconButton(
                          key: const Key('vault-video-play-pause'),
                          color: Colors.white,
                          tooltip: _controller.value.isPlaying
                              ? 'Pause video'
                              : 'Play video',
                          onPressed: () {
                            if (_controller.value.isPlaying) {
                              unawaited(_controller.pause());
                            } else {
                              unawaited(_controller.play());
                            }
                          },
                          icon: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            size: 44,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VaultPreview extends StatelessWidget {
  const _VaultPreview({
    required this.item,
    required this.bytes,
    required this.onExport,
    required this.onDelete,
  });

  final VaultItem item;
  final Uint8List bytes;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  String _decodeNote(Uint8List value) {
    try {
      return utf8.decode(value, allowMalformed: false);
    } on FormatException {
      return 'Note data could not be displayed.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.kind == VaultItemKind.image)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Text('Image data could not be displayed.'),
                ),
              )
            else if (item.kind == VaultItemKind.note)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: SingleChildScrollView(
                  child: Text(
                    _decodeNote(bytes),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  '${bytes.length} protected bytes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Export'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
