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
        _message = 'Real clone-profile capability could not be queried.';
      });
    }
  }

  Future<void> _requestPrivilege() async {
    final granted = await widget.client.requestPrivilege();
    if (!mounted) return;
    setState(() {
      _message = granted ? 'Privileged clone access granted.' : 'Shizuku authorization is required for real Android clone profiles.';
    });
    if (granted) await _refresh();
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
            ? '${app.label} updated in the Android clone profile.'
            : result.capability.message ?? 'Clone operation failed.';
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
        title: 'Clone profile unavailable',
        body: 'Android clone-profile state could not be determined.',
      );
    }

    if (!capability.ready) {
      final (title, body, action) = switch (capability.state) {
        CloneProfileCapabilityState.privilegeRequired => (
          'Privileged clone access required',
          'Private Vault creates a real Android profile.CLONE through Shizuku. '
              'It will not substitute a managed Work Profile.',
          FilledButton.icon(
            onPressed: _requestPrivilege,
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Authorize Shizuku'),
          ),
        ),
        CloneProfileCapabilityState.cloneProfileUnsupportedByOem => (
          'Clone profiles unsupported',
          capability.message ?? 'This Android build does not expose the real profile.CLONE user type.',
          null,
        ),
        CloneProfileCapabilityState.conflictingExternalCloneProfile => (
          'Existing clone profile detected',
          capability.message ??
              'Another app or the OEM owns the available clone profile. '
                  'Private Vault will not take it over.',
          null,
        ),
        CloneProfileCapabilityState.operationFailed => (
          'Clone backend unavailable',
          capability.message ?? 'The privileged clone operation failed.',
          null,
        ),
        CloneProfileCapabilityState.ready => ('Clone apps', '', null),
      };
      return _CloneState(
        title: title,
        body: body,
        action: action,
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
            'Clone creates a second package instance in Android profile.CLONE. '
            'It does not provision or reuse a managed Work Profile, and cloned '
            'apps start with separate private app data.',
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          for (final app in _apps)
            Card(
              child: ListTile(
                leading: app.iconBytes == null
                    ? const Icon(Icons.apps_outlined)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          app.iconBytes!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                title: Text(app.label),
                subtitle: Text(
                  app.cloned
                      ? 'Installed in real clone profile'
                      : 'Personal app · clone data starts fresh',
                ),
                onTap: app.cloned
                    ? () => unawaited(
                        _run(app, () => widget.client.launch(app.packageName)),
                      )
                    : null,
                trailing: app.cloned
                    ? PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'launch') {
                            unawaited(
                              _run(
                                app,
                                () => widget.client.launch(app.packageName),
                              ),
                            );
                          } else if (value == 'uninstall') {
                            unawaited(
                              _run(
                                app,
                                () => widget.client.uninstall(app.packageName),
                              ),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'launch',
                            child: Text('Open clone'),
                          ),
                          PopupMenuItem(
                            value: 'uninstall',
                            child: Text('Remove clone instance'),
                          ),
                        ],
                      )
                    : FilledButton(
                        onPressed: _operationInFlight
                            ? null
                            : () => unawaited(
                                _run(
                                  app,
                                  () => widget.client.clone(app.packageName),
                                ),
                              ),
                        child: const Text('Clone'),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CloneState extends StatelessWidget {
  const _CloneState({
    required this.title,
    required this.body,
    this.action,
    this.footer,
  });

  final String title;
  final String body;
  final Widget? action;
  final String? footer;

  @override
  Widget build(BuildContext context) => Center(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(32),
      children: [
        const Icon(Icons.copy_all_outlined, size: 48),
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
          Text(footer!, textAlign: TextAlign.center),
        ],
      ],
    ),
  );
}
