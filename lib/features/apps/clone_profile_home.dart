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
        _message = 'Plugin clone capability could not be queried.';
      });
    }
  }

  Future<void> _run(
    String label,
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
        _message = result.ok ? '$label completed.' : result.capability.message ?? 'Plugin clone operation failed.';
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
        title: 'Plugin clone unavailable',
        body: 'Plugin helper state could not be determined.',
      );
    }
    if (!capability.ready) {
      return _CloneState(
        title: capability.state == CloneProfileCapabilityState.helperMissing
            ? 'Plugin helpers required'
            : 'Plugin clone unavailable',
        body: capability.message ?? capability.state.name,
        footer: _message,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Clone apps', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Each clone runs inside one of two fixed helper apps with its own Android UID. '
            'The source APK is transformed into helper-private plugin code; Private Vault '
            'does not execute guest code or pass vault data to it.',
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          for (final app in _apps)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.label, style: Theme.of(context).textTheme.titleMedium),
                    Text(app.packageName, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var slot = 0; slot < 2; slot++)
                          if (app.slots.contains(slot)) ...[
                            OutlinedButton(
                              onPressed: _operationInFlight
                                  ? null
                                  : () => unawaited(_run(
                                        'Open ${app.label} in slot ${slot + 1}',
                                        () => widget.client.launch(app.packageName, slot),
                                      )),
                              child: Text('Open slot ${slot + 1}'),
                            ),
                            TextButton(
                              onPressed: _operationInFlight
                                  ? null
                                  : () => unawaited(_run(
                                        'Remove slot ${slot + 1}',
                                        () => widget.client.uninstall(slot),
                                      )),
                              child: Text('Remove slot ${slot + 1}'),
                            ),
                          ] else
                            FilledButton.tonal(
                              onPressed: _operationInFlight ||
                                      capability.slots.any((item) => item.slot == slot && item.occupied)
                                  ? null
                                  : () => unawaited(_run(
                                        'Clone ${app.label} to slot ${slot + 1}',
                                        () => widget.client.clone(app.packageName, slot),
                                      )),
                              child: Text('Clone to slot ${slot + 1}'),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
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
