import 'dart:async';

import 'package:flutter/material.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';

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
                label: const Text('Set up work profile'),
              )
            : null,
        footer: _message,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Isolated apps',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Clones run as Android work-profile apps outside Private Vault. '
            'Locking Private Vault does not stop an already-running clone.',
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _removeProfile,
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Remove work profile'),
            ),
          ),
          const SizedBox(height: 16),
          if (_apps.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No visible apps are available in this profile yet. '
                  'Some devices require installing through Play or the OEM store.',
                ),
              ),
            )
          else
            for (final app in _apps)
              _AppTile(app: app, client: widget.client, onRun: _run),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.client,
    required this.onRun,
  });

  final ManagedAppState app;
  final WorkProfileClient client;
  final Future<void> Function(
    ManagedAppState,
    Future<WorkProfileOperationResult> Function(),
  )
  onRun;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.apps),
        title: Text(app.label),
        subtitle: Text(
          app.presentWork
              ? app.suspended
                    ? 'Installed in work profile · suspended'
                    : 'Installed in work profile'
              : app.installerActionRequired
              ? 'Personal app · Android confirmation required'
              : 'Personal app · available for isolation',
        ),
        trailing: app.presentWork
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'launch') {
                    unawaited(onRun(app, () => client.launch(app.packageName)));
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
                  const PopupMenuItem(value: 'launch', child: Text('Open')),
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
            ? IconButton(
                tooltip: 'Clone to work profile',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () =>
                    unawaited(onRun(app, () => client.clone(app.packageName))),
              )
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
