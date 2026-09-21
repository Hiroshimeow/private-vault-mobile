import 'dart:async';

import 'package:flutter/material.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';

enum _AppScope { personal, isolated }

class WorkProfileHome extends StatefulWidget {
  const WorkProfileHome({super.key, required this.client});

  final WorkProfileClient client;

  @override
  State<WorkProfileHome> createState() => _WorkProfileHomeState();
}

class _WorkProfileHomeState extends State<WorkProfileHome> {
  WorkProfileCapability? _capability;
  List<ManagedAppState> _apps = const [];
  bool _loading = true;
  String? _message;
  _AppScope _scope = _AppScope.personal;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _message = null;
    });
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

  Future<void> _run(
    ManagedAppState app,
    Future<WorkProfileOperationResult> Function() action,
  ) async {
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _message = result.ok
            ? '${app.label} updated.'
            : result.message ?? 'Android rejected this operation.';
      });
      if (result.ok) unawaited(_refresh());
    } on Object {
      if (!mounted) return;
      setState(() => _message = 'Android work-profile operation failed.');
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
            ? OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
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
  });

  final ManagedAppState app;
  final _AppScope scope;
  final WorkProfileClient client;
  final Future<void> Function(
    ManagedAppState,
    Future<WorkProfileOperationResult> Function(),
  )
  onRun;

  @override
  Widget build(BuildContext context) {
    final isolated = scope == _AppScope.isolated;
    return Card(
      child: ListTile(
        onTap: isolated
            ? () => unawaited(onRun(app, () => client.launch(app.packageName)))
            : null,
        leading: Icon(isolated ? Icons.work_outline : Icons.apps_outlined),
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
                  if (value == 'suspend') {
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
