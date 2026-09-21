import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:private_vault_mobile/app/private_vault_theme.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class VaultHome extends StatefulWidget {
  const VaultHome({
    super.key,
    required this.repository,
    required this.media,
    required this.confirmExport,
  });

  final VaultRepository repository;
  final MediaVaultService media;
  final bool confirmExport;

  @override
  State<VaultHome> createState() => _VaultHomeState();
}

class _VaultHomeState extends State<VaultHome> {
  List<VaultItem> _items = const [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final items = await widget.repository.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _busy = false;
        _error = null;
      });
    } on MissingVaultKeyException {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _busy = false;
        _error = 'Protected key unavailable. Existing items stay locked.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Protected items could not be loaded.';
      });
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      await widget.media.importFile();
    } finally {
      await _reload();
    }
  }

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      await widget.media.capturePhoto();
    } finally {
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
    try {
      final bytes = await widget.repository.readBytes(item.id);
      if (!mounted) return;
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
      if (item.kind == VaultItemKind.unknown && mounted) {
        await _reload();
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item could not be decrypted.')),
      );
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

    final ok = await widget.media.export(
      item.id,
      fileName: 'private-item-${item.id.substring(0, 8)}.bin',
    );
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
      return const Center(child: CircularProgressIndicator());
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
                      onPressed: _import,
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
          child: Row(
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
                    key: const ValueKey('vault-list'),
                    label: 'Protected item list',
                    container: true,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Card(
                          child: ListTile(
                            onTap: () => _open(item),
                            leading: Icon(_iconFor(item.kind)),
                            title: Text(_labelFor(item.kind)),
                            subtitle: item.kind == VaultItemKind.unknown
                                ? const Text(
                                    'Open once to restore authenticated metadata',
                                  )
                                : Text(_shortTimestamp(item.createdAt)),
                            trailing: const Icon(Icons.chevron_right),
                          ),
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
