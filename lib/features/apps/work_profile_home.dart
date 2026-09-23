import 'dart:async';

import 'package:flutter/material.dart';
import 'package:private_vault_mobile/features/apps/vault_shuttle_service.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/platform/media_source_bridge.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

enum _AppScope { personal, isolated }

class WorkProfileHome extends StatefulWidget {
  const WorkProfileHome({
    super.key,
    required this.client,
    this.vaultShuttle,
    this.mediaService,
    this.importAllowed,
  });

  final WorkProfileClient client;
  final VaultShuttle? vaultShuttle;
  final MediaVaultService? mediaService;
  final ValueGetter<bool>? importAllowed;

  @override
  State<WorkProfileHome> createState() => _WorkProfileHomeState();
}

class _WorkProfileHomeState extends State<WorkProfileHome> {
  WorkProfileCapability? _capability;
  List<ManagedAppState> _apps = const [];
  bool _loading = true;
  String? _message;
  _AppScope _scope = _AppScope.personal;
  Future<void>? _refreshFuture;
  bool _quietRecoveryInFlight = false;
  bool _importInFlight = false;
  final Set<String> _storeFallbackPackages = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() {
    final current = _refreshFuture;
    if (current != null) return current;
    final future = _refreshOnce();
    _refreshFuture = future;
    future.whenComplete(() {
      if (identical(_refreshFuture, future)) {
        _refreshFuture = null;
      }
    });
    return future;
  }

  Future<void> _refreshOnce() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _message = null;
      });
    }
    try {
      final capability = await widget.client.getCapability();
      final apps = capability.profileState == WorkProfileState.ready
          ? await widget.client.listApps()
          : const <ManagedAppState>[];
      if (!mounted) return;
      setState(() {
        _capability = capability;
        _apps = apps;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Unable to read Android work-profile state.';
      });
    }
  }

  Future<void> _provision() async {
    final result = await widget.client.startProvisioning();
    if (!mounted) return;
    if (result.ok) {
      await _refresh();
      return;
    }
    setState(() {
      _message = result.message ?? 'Work-profile provisioning was not allowed.';
    });
  }

  Future<void> _recoverQuietProfile() async {
    if (_quietRecoveryInFlight) return;
    setState(() => _quietRecoveryInFlight = true);
    try {
      final result = await widget.client.requestQuietModeDisabled();
      if (!mounted) return;
      if (!result.ok) {
        setState(() {
          _message =
              result.message ??
              'Turn Work Profile on from Android system settings, then retry.';
        });
        return;
      }
      for (var attempt = 0; attempt < 15 && mounted; attempt++) {
        await _refresh();
        if (!mounted || _capability?.profileState == WorkProfileState.ready) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (mounted) {
        setState(() {
          _message = 'Android has not finished enabling Work Profile. Check system settings and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _quietRecoveryInFlight = false);
    }
  }

  Future<void> _importFromWorkProfile({required bool moveSource}) async {
    final mediaService = widget.mediaService;
    if (mediaService == null || _importInFlight) return;
    setState(() {
      _importInFlight = true;
      _message = 'Choose a Work Profile file…';
    });
    try {
      final picked = await widget.client.pickWorkDocument();
      if (picked == null || !mounted) {
        if (mounted) setState(() => _message = null);
        return;
      }
      final bridge = const PlatformMediaSourceBridge();
      final source = PickedVaultSource(
        name: picked.displayName,
        kind: _kindForWorkDocument(picked),
        openRead: () => _guardedWorkDocumentStream(bridge, picked.uri),
        deleteSource: picked.canDelete
            ? () async {
                _requireImportAllowed();
                await bridge.delete(picked.uri);
              }
            : null,
      );
      final result = await mediaService.importSources([
        source,
      ], moveSource: moveSource);
      if (!mounted) return;
      if (result.imported.isNotEmpty && result.failures.isEmpty) {
        setState(() {
          _message = moveSource
              ? 'Moved ${picked.displayName} into Vault.'
              : 'Copied ${picked.displayName} into Vault.';
        });
      } else if (result.imported.isNotEmpty) {
        setState(() {
          _message =
              'Encrypted copy saved, but the Work Profile source was retained.';
        });
      } else {
        setState(() {
          _message = 'Unable to import ${picked.displayName}. Source retained.';
        });
      }
    } on WorkProfileOperationException catch (error) {
      if (mounted) {
        setState(() {
          _message =
              error.message ??
              'Work Profile import failed (${error.errorCode.name}).';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'Work Profile import failed: $error');
      }
    } finally {
      if (mounted) setState(() => _importInFlight = false);
    }
  }

  bool get _importStillAllowed =>
      mounted && (widget.importAllowed?.call() ?? true);

  void _requireImportAllowed() {
    if (!_importStillAllowed) {
      throw StateError('Vault locked during Work Profile import');
    }
  }

  Stream<List<int>> _guardedWorkDocumentStream(
    PlatformMediaSourceBridge bridge,
    Uri uri,
  ) async* {
    _requireImportAllowed();
    await for (final chunk in bridge.openRead(uri)) {
      _requireImportAllowed();
      yield chunk;
    }
    _requireImportAllowed();
  }

  VaultItemKind _kindForWorkDocument(PickedWorkDocument source) {
    final mime = source.mimeType.toLowerCase();
    if (mime.startsWith('image/')) return VaultItemKind.image;
    if (mime.startsWith('video/')) return VaultItemKind.video;
    if (mime != 'application/octet-stream') return VaultItemKind.document;
    final name = source.displayName.toLowerCase();
    if (RegExp(r'\.(png|jpe?g|gif|webp|heic)$').hasMatch(name)) {
      return VaultItemKind.image;
    }
    if (RegExp(r'\.(mp4|mov|m4v|webm|mkv)$').hasMatch(name)) {
      return VaultItemKind.video;
    }
    return VaultItemKind.document;
  }

  Future<void> _shareVaultFile(ManagedAppState app) async {
    final shuttle = widget.vaultShuttle;
    if (shuttle == null) return;

    List<VaultItem> items;
    try {
      items = await shuttle.listVaultItems();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Unable to read Vault items: $error');
      return;
    }
    if (!mounted) return;

    if (items.isEmpty) {
      setState(() => _message = 'Vault is empty.');
      return;
    }

    final selected = await showModalBottomSheet<VaultItem>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(
              'Share from Vault',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'A temporary read-only copy is created in app-private cache and '
              'removed on lock or timeout.',
            ),
            const SizedBox(height: 12),
            for (final item in items)
              ListTile(
                key: ValueKey('vault-shuttle-${item.id}'),
                leading: Icon(_vaultIcon(item.kind)),
                title: Text(_vaultKindLabel(item.kind)),
                subtitle: Text(_dateLabel(item.createdAt)),
                onTap: () => Navigator.of(sheetContext).pop(item),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _message = 'Opening Vault item in ${app.label}…');
    try {
      await shuttle.shareToIsolatedApp(
        item: selected,
        packageName: app.packageName,
      );
      if (!mounted) return;
      setState(() => _message = 'Vault item shared with ${app.label}.');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Unable to share Vault item: $error');
    }
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _vaultKindLabel(VaultItemKind kind) => switch (kind) {
    VaultItemKind.note => 'Protected note',
    VaultItemKind.image => 'Image',
    VaultItemKind.video => 'Video',
    VaultItemKind.document => 'Document',
    VaultItemKind.unknown => 'Vault item',
  };

  IconData _vaultIcon(VaultItemKind kind) => switch (kind) {
    VaultItemKind.note => Icons.note_outlined,
    VaultItemKind.image => Icons.image_outlined,
    VaultItemKind.video => Icons.video_file_outlined,
    VaultItemKind.document => Icons.description_outlined,
    VaultItemKind.unknown => Icons.insert_drive_file_outlined,
  };

  Future<void> _run(
    ManagedAppState app,
    Future<WorkProfileOperationResult> Function() action,
  ) async {
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        if (result.errorCode == WorkProfileErrorCode.storeFallbackRequired) {
          _storeFallbackPackages.add(app.packageName);
        }
        _message = result.ok
            ? '${app.label} updated.'
            : result.message ?? 'Android rejected this operation.';
      });
      if (result.ok) {
        _storeFallbackPackages.remove(app.packageName);
        unawaited(_refresh());
      }
    } on Object {
      if (!mounted) return;
      setState(() => _message = 'Android work-profile operation failed.');
    }
  }

  Future<void> _openStore(ManagedAppState app) async {
    try {
      final result = await widget.client.openStore(app.packageName);
      if (!mounted) return;
      setState(() {
        _message = result.ok
            ? 'Opened the Work Profile app store for ${app.label}.'
            : result.message ?? 'No managed-profile app store is available.';
      });
      if (result.ok) unawaited(_refresh());
    } on Object {
      if (!mounted) return;
      setState(() => _message = 'Unable to open the Work Profile app store.');
    }
  }

  Future<void> _removeProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove work profile?'),
        content: const Text(
          'This deletes all work-profile app data, accounts, and isolated '
          'app copies from Android. Personal-profile apps are not removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await widget.client.destroyProfile();
      if (!mounted) return;
      setState(() {
        _message = result.ok
            ? 'Android accepted the work-profile removal request.'
            : result.message ?? 'Android did not remove the work profile.';
      });
    } on Object {
      if (!mounted) return;
      setState(() => _message = 'Work-profile removal failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final capability = _capability;
    if (capability == null || !capability.supported) {
      return const _StateMessage(
        icon: Icons.phonelink_erase_outlined,
        title: 'Android work profiles unavailable',
        body:
            'Native app isolation uses Android managed work profiles. '
            'This feature is not emulated on iOS or unsupported devices.',
      );
    }

    if (capability.profileState != WorkProfileState.ready) {
      final (title, body) = switch (capability.profileState) {
        WorkProfileState.absent => (
          'Set up isolated apps',
          'Android will create a managed work profile. App data and accounts '
              'inside that profile are separate from personal apps.',
        ),
        WorkProfileState.provisioning => (
          'Finish Android setup',
          'Complete the system-managed work-profile provisioning flow.',
        ),
        WorkProfileState.quiet => (
          'Isolated apps are paused',
          'Turn Work Profile back on from Android Quick Settings or system '
              'settings, then refresh this page.',
        ),
        WorkProfileState.conflictingProfile => (
          'Existing work profile detected',
          'Another organization or DPC already owns the available managed '
              'profile. Private Vault will not take it over.',
        ),
        WorkProfileState.policyDenied => (
          'Work profile blocked',
          'Android or device policy does not allow a new managed profile.',
        ),
        WorkProfileState.unsupported => (
          'Android work profiles unavailable',
          'This device does not expose managed-user support.',
        ),
        WorkProfileState.ready => ('Isolated apps', ''),
      };
      return _StateMessage(
        icon: Icons.work_outline,
        title: title,
        body: body,
        action: capability.canProvision
            ? FilledButton.icon(
                onPressed: _provision,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Enable isolated apps'),
              )
            : capability.profileState == WorkProfileState.quiet
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: _quietRecoveryInFlight
                        ? null
                        : _recoverQuietProfile,
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: Text(
                      _quietRecoveryInFlight
                          ? 'Turning on…'
                          : 'Turn on Work Profile',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _quietRecoveryInFlight ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check again'),
                  ),
                ],
              )
            : null,
        footer: _message,
      );
    }

    final visibleApps = _apps
        .where(
          (app) => switch (_scope) {
            _AppScope.personal => app.presentPersonal,
            _AppScope.isolated => app.presentWork,
          },
        )
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Isolated apps',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          SegmentedButton<_AppScope>(
            segments: const [
              ButtonSegment(
                value: _AppScope.personal,
                icon: Icon(Icons.phone_android_outlined),
                label: Text('Personal'),
              ),
              ButtonSegment(
                value: _AppScope.isolated,
                icon: Icon(Icons.work_outline),
                label: Text('Isolated'),
              ),
            ],
            selected: {_scope},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              setState(() => _scope = selection.first);
            },
          ),
          const SizedBox(height: 12),
          Text(
            _scope == _AppScope.personal
                ? 'Choose an app to create an isolated Android Work Profile copy.'
                : 'Tap an app to open it. Freeze, hide, and uninstall affect only the isolated copy.',
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (widget.mediaService != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _importInFlight
                      ? null
                      : () => unawaited(
                          _importFromWorkProfile(moveSource: false),
                        ),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Copy from Work Profile'),
                ),
                OutlinedButton.icon(
                  onPressed: _importInFlight
                      ? null
                      : () =>
                            unawaited(_importFromWorkProfile(moveSource: true)),
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('Move from Work Profile'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (visibleApps.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _scope == _AppScope.personal
                      ? 'No launchable personal apps are available to isolate.'
                      : 'No isolated apps yet. Switch to Personal and choose Clone.',
                ),
              ),
            )
          else
            for (final app in visibleApps)
              _AppTile(
                app: app,
                scope: _scope,
                client: widget.client,
                onRun: _run,
                onOpenStore: _openStore,
                storeFallback:
                    _storeFallbackPackages.contains(app.packageName) ||
                    app.cloneEligibility ==
                        CloneEligibility.storeFallbackRequired,
                onShareVault: widget.vaultShuttle == null
                    ? null
                    : _shareVaultFile,
              ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _removeProfile,
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Remove work profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.scope,
    required this.client,
    required this.onRun,
    required this.onOpenStore,
    required this.storeFallback,
    this.onShareVault,
  });

  final ManagedAppState app;
  final _AppScope scope;
  final WorkProfileClient client;
  final Future<void> Function(
    ManagedAppState,
    Future<WorkProfileOperationResult> Function(),
  )
  onRun;
  final Future<void> Function(ManagedAppState app) onOpenStore;
  final bool storeFallback;
  final Future<void> Function(ManagedAppState app)? onShareVault;

  @override
  Widget build(BuildContext context) {
    final isolated = scope == _AppScope.isolated;
    return Card(
      child: ListTile(
        onTap: isolated
            ? () => unawaited(onRun(app, () => client.launch(app.packageName)))
            : null,
        leading: app.iconBytes == null
            ? Icon(isolated ? Icons.work_outline : Icons.apps_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  app.iconBytes!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      Icon(isolated ? Icons.work_outline : Icons.apps_outlined),
                ),
              ),
        title: Text(app.label),
        subtitle: Text(
          isolated
              ? app.suspended
                    ? 'Frozen · tap to open'
                    : app.hidden
                    ? 'Hidden · tap to open'
                    : 'Tap to open'
              : app.presentWork
              ? 'Already isolated'
              : app.installerActionRequired
              ? 'Android will ask you to confirm installation'
              : app.systemApp
              ? 'System app · ready to enable in isolated profile'
              : 'Ready to isolate',
        ),
        trailing: isolated
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'share') {
                    final share = onShareVault;
                    if (share != null) unawaited(share(app));
                  } else if (value == 'suspend') {
                    unawaited(
                      onRun(
                        app,
                        () => client.setSuspended(
                          app.packageName,
                          !app.suspended,
                        ),
                      ),
                    );
                  } else if (value == 'hide') {
                    unawaited(
                      onRun(
                        app,
                        () => client.setHidden(app.packageName, !app.hidden),
                      ),
                    );
                  } else if (value == 'uninstall') {
                    unawaited(
                      onRun(app, () => client.uninstall(app.packageName)),
                    );
                  }
                },
                itemBuilder: (_) => [
                  if (onShareVault != null)
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('Share vault file'),
                    ),
                  PopupMenuItem(
                    value: 'suspend',
                    child: Text(app.suspended ? 'Unfreeze' : 'Freeze'),
                  ),
                  PopupMenuItem(
                    value: 'hide',
                    child: Text(app.hidden ? 'Unhide' : 'Hide'),
                  ),
                  const PopupMenuItem(
                    value: 'uninstall',
                    child: Text('Uninstall'),
                  ),
                ],
              )
            : storeFallback
            ? FilledButton(
                onPressed: () => unawaited(onOpenStore(app)),
                child: const Text('Store'),
              )
            : app.canClone
            ? FilledButton(
                onPressed: () =>
                    unawaited(onRun(app, () => client.clone(app.packageName))),
                child: const Text('Clone'),
              )
            : app.presentWork
            ? const Icon(Icons.check_circle_outline)
            : null,
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(32),
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 20),
            Center(child: action),
          ],
          if (footer != null) ...[
            const SizedBox(height: 12),
            Text(
              footer!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
