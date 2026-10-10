import 'dart:async';

import 'package:flutter/material.dart';
import 'package:private_vault_mobile/features/apps/standalone_clone_client.dart';

class StandaloneCloneHome extends StatefulWidget {
  const StandaloneCloneHome({super.key, required this.client});

  final StandaloneCloneClient client;

  @override
  State<StandaloneCloneHome> createState() => _StandaloneCloneHomeState();
}

class _StandaloneCloneHomeState extends State<StandaloneCloneHome> {
  List<StandaloneCloneRecord> _clones = const [];
  StandaloneCloneEnvironment? _environment;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait<Object>([
        widget.client.getEnvironment(),
        widget.client.listClones(),
      ]);
      if (!mounted) return;
      setState(() {
        _environment = values[0] as StandaloneCloneEnvironment;
        _clones = values[1] as List<StandaloneCloneRecord>;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Standalone clone backend unavailable: $error';
      });
    }
  }

  Future<void> _buildClone() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.client.pickAndBuildClone();
      if (!mounted) return;
      setState(() {
        _message = switch (result.status) {
          'artifact_ready' =>
            result.warnings.isEmpty
                ? 'Clone APK built and signed. Install remains a normal Android user-approved action.'
                : 'Clone APK built and signed. Compatibility warning: ${result.warnings.join(', ')}. Install remains a normal Android user-approved action.',
          'cancelled' => 'APK selection cancelled.',
          'unsupported' =>
            'Unsupported for safe Phase-1 cloning: ${result.blockers.join(', ')}',
          _ =>
            result.errorCode == null
                ? result.error ?? 'Clone build failed.'
                : '${result.errorCode}: ${result.error ?? 'Clone build failed.'}',
        };
      });
      if (result.status == 'artifact_ready') await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runCloneAction(
    StandaloneCloneRecord record,
    Future<String> Function() action,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final status = await action();
      if (!mounted) return;
      setState(() {
        _message = switch (status) {
          'unknown_sources_required' => 'Allow installs from this app in Android settings, then tap Install again.',
          'install_requested' =>
            'Android installer opened. Confirm installation there.',
          'uninstall_requested' => 'Android uninstall confirmation opened.',
          'uninstall_cancelled' =>
            'Android uninstall was cancelled. Clone artifact was retained.',
          'uninstall_failed' =>
            'Android uninstall did not complete. Clone artifact was retained.',
          'removed' => 'Clone artifact removed from clone-lab.',
          'launched' => 'Clone launched.',
          _ => 'Clone action status: $status',
        };
      });
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final environment = _environment;
    if (environment == null || environment.route == 'unavailable') {
      return const _StandaloneCloneState(
        title: 'Standalone cloning unavailable',
        body: 'This Phase-1 prototype is Android-only.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Standalone clones',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a compatible monolithic APK. The prototype rewrites only safe package/resource '
            'identity, preserves app code, signs with a clone-lab Android Keystore key, and keeps '
            'clone artifacts separate from private vault data. Split bundles, native libraries, '
            'signature-bound apps, verified links, Google identity binding, and ambiguous global '
            'identifiers are rejected instead of patched.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('standalone-clone-pick-apk'),
            onPressed: _busy ? null : _buildClone,
            icon: const Icon(Icons.add_to_photos_outlined),
            label: const Text('Choose APK and build clone'),
          ),
          if (!environment.canRequestPackageInstalls) ...[
            const SizedBox(height: 8),
            const Text(
              'Android will ask you to allow installs from this app before the first install.',
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, key: const ValueKey('standalone-clone-message')),
          ],
          const SizedBox(height: 20),
          if (_clones.isEmpty)
            const Text('No clone-lab artifacts yet.')
          else
            for (final clone in _clones)
              _CloneCard(
                clone: clone,
                disabled: _busy,
                onInstall: () => _runCloneAction(
                  clone,
                  () => widget.client.installClone(clone.cloneId),
                ),
                onLaunch: () => _runCloneAction(
                  clone,
                  () => widget.client.launchClone(clone.cloneId),
                ),
                onRemove: () => _runCloneAction(
                  clone,
                  () => widget.client.removeClone(clone.cloneId),
                ),
              ),
        ],
      ),
    );
  }
}

class _CloneCard extends StatelessWidget {
  const _CloneCard({
    required this.clone,
    required this.disabled,
    required this.onInstall,
    required this.onLaunch,
    required this.onRemove,
  });

  final StandaloneCloneRecord clone;
  final bool disabled;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.copy_all_outlined),
      title: Text(clone.sourcePackage),
      subtitle: Text(
        '${clone.clonePackage}\n${clone.installStatus}'
        '${clone.versionName == null ? '' : ' · ${clone.versionName}'}'
        '${clone.compatibilityWarnings.isEmpty ? '' : '\nWarnings: ${clone.compatibilityWarnings.join(', ')}'}',
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        enabled: !disabled,
        onSelected: (value) {
          switch (value) {
            case 'install':
              onInstall();
              break;
            case 'launch':
              onLaunch();
              break;
            case 'remove':
              onRemove();
              break;
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'install', child: Text('Install / update')),
          PopupMenuItem(value: 'launch', child: Text('Open clone')),
          PopupMenuItem(value: 'remove', child: Text('Remove clone')),
        ],
      ),
    ),
  );
}

class _StandaloneCloneState extends StatelessWidget {
  const _StandaloneCloneState({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.copy_all_outlined, size: 48),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
