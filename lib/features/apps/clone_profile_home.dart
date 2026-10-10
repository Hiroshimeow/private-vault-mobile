import 'dart:async';

import 'package:flutter/material.dart';
import 'package:private_vault_mobile/features/apps/clone_profile_client.dart';

class CloneProfileHome extends StatefulWidget {
  const CloneProfileHome({super.key, required this.client});

  final CloneProfileClient client;

  @override
  State<CloneProfileHome> createState() => _CloneProfileHomeState();
}

class _CloneProfileHomeState extends State<CloneProfileHome> {
  CloneProfileCapability? _capability;
  List<CloneProfileApp> _apps = const [];
  bool _loading = true;
  bool _operationInFlight = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      final result = await widget.client.listApps();
      if (!mounted) return;
      setState(() {
        _capability = result.capability;
        _apps = result.apps;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Virtual clone capability could not be queried.';
      });
    }
  }

  Future<void> _run(
    CloneProfileApp app,
    Future<CloneProfileOperationResult> Function() operation,
  ) async {
    if (_operationInFlight) return;
    setState(() {
      _operationInFlight = true;
      _message = null;
    });
    try {
      final result = await operation();
      if (!mounted) return;
      setState(() {
        _capability = result.capability;
        _message = result.ok
            ? '${app.label} virtual clone updated.'
            : result.errorCode ?? result.message ?? result.capability.message ?? 'Clone operation failed.';
      });
      if (result.ok) await _refresh();
    } finally {
      if (mounted) setState(() => _operationInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final capability = _capability;
    if (capability == null) {
      return const _CloneState(
        title: 'Virtual clone unavailable',
        body: 'Virtual clone state could not be determined.',
      );
    }

    if (!capability.ready) {
      final (title, body) = switch (capability.state) {
        CloneProfileCapabilityState.runnerMissing => (
          'Clone runners missing',
          capability.message ?? 'The fixed clone-host companion apps are not available.',
        ),
        CloneProfileCapabilityState.engineUnsupported => (
          'Virtual engine unsupported',
          capability.message ?? 'This Android build cannot run the virtual clone prototype.',
        ),
        CloneProfileCapabilityState.unsupportedAbi => (
          'Unsupported app ABI',
          capability.message ?? 'This app requires a native ABI this clone runner cannot load.',
        ),
        CloneProfileCapabilityState.operationFailed => (
          'Clone backend unavailable',
          capability.message ?? 'The virtual clone operation failed.',
        ),
        CloneProfileCapabilityState.ready => ('Virtual clones', ''),
      };
      return _CloneState(title: title, body: body, footer: _message);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Virtual clones', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Each clone runs in one of two companion app slots with a separate Android UID and private data root. '
            '${capability.slotsAvailable} of ${capability.slotsTotal} slots available.',
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          for (final app in _apps) _AppCard(
            app: app,
            busy: _operationInFlight,
            slotsAvailable: capability.slotsAvailable,
            onClone: () => _run(app, () => widget.client.clone(app.packageName)),
            onLaunch: (instance) => _run(app, () => widget.client.launch(instance.instanceId)),
            onStop: (instance) => _run(app, () => widget.client.stop(instance.instanceId)),
            onRemove: (instance) => _run(app, () => widget.client.uninstall(instance.instanceId)),
          ),
        ],
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.busy,
    required this.slotsAvailable,
    required this.onClone,
    required this.onLaunch,
    required this.onStop,
    required this.onRemove,
  });

  final CloneProfileApp app;
  final bool busy;
  final int slotsAvailable;
  final VoidCallback onClone;
  final ValueChanged<CloneInstance> onLaunch;
  final ValueChanged<CloneInstance> onStop;
  final ValueChanged<CloneInstance> onRemove;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: app.iconBytes == null
                ? const Icon(Icons.apps_outlined)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(app.iconBytes!, width: 40, height: 40, fit: BoxFit.cover),
                  ),
            title: Text(app.label),
            subtitle: Text(app.packageName),
            trailing: FilledButton(
              onPressed: busy || !app.canClone || slotsAvailable == 0 ? null : onClone,
              child: const Text('Clone'),
            ),
          ),
          if (app.instances.isEmpty)
            const Text('No virtual instances yet.')
          else
            for (final instance in app.instances)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Instance ${instance.slot + 1}'),
                        Text(instance.state, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>('clone-launch-${instance.instanceId}'),
                    onPressed: busy ? null : () => onLaunch(instance),
                    tooltip: 'Open instance',
                    icon: const Icon(Icons.play_arrow),
                  ),
                  IconButton(
                    key: ValueKey<String>('clone-stop-${instance.instanceId}'),
                    onPressed: busy ? null : () => onStop(instance),
                    tooltip: 'Stop instance',
                    icon: const Icon(Icons.stop_outlined),
                  ),
                  IconButton(
                    key: ValueKey<String>('clone-remove-${instance.instanceId}'),
                    onPressed: busy ? null : () => onRemove(instance),
                    tooltip: 'Remove instance',
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
        ],
      ),
    ),
  );
}

class _CloneState extends StatelessWidget {
  const _CloneState({required this.title, required this.body, this.footer});

  final String title;
  final String body;
  final String? footer;

  @override
  Widget build(BuildContext context) => Center(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(32),
      children: [
        const Icon(Icons.copy_all_outlined, size: 48),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center),
        if (footer != null) ...[
          const SizedBox(height: 12),
          Text(footer!, textAlign: TextAlign.center),
        ],
      ],
    ),
  );
}
