export '../features/auth/secure_unlock_service.dart' show UnlockService;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:private_vault_mobile/app/private_vault_theme.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_home.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/auth/secure_unlock_service.dart';
import 'package:private_vault_mobile/features/browser/browser_home.dart';
import 'package:private_vault_mobile/features/cover/calculator_cover.dart';
import 'package:private_vault_mobile/features/cover/notes_cover.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/panic/panic_sensor_service.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/vault_home.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';
import 'package:private_vault_mobile/platform/disguise_bridge.dart';

enum CoverKind { calculator, notes }

class PrivateVaultApp extends StatefulWidget {
  const PrivateVaultApp({
    super.key,
    required this.lockController,
    required this.unlockService,
    this.vaultRepository,
    this.mediaService,
    this.biometricUnlock,
    this.settingsStore,
    this.panicService,
    this.disguiseBridge,
    this.workProfileClient,
    this.initialSettings = const AppSettings.defaults(),
    this.initialCover,
  });

  final LockController lockController;
  final UnlockService unlockService;
  final VaultRepository? vaultRepository;
  final MediaVaultService? mediaService;
  final BiometricUnlock? biometricUnlock;
  final AppSettingsStore? settingsStore;
  final PanicSensorService? panicService;
  final PlatformDisguiseBridge? disguiseBridge;
  final WorkProfileClient? workProfileClient;
  final AppSettings initialSettings;
  final CoverKind? initialCover;

  @override
  State<PrivateVaultApp> createState() => _PrivateVaultAppState();
}

class _PrivateVaultAppState extends State<PrivateVaultApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _secretNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _secretMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  late final VoidCallback _confidentialityBoundary;
  late AppSettings _settings;
  late CoverKind _cover;

  @override
  void initState() {
    super.initState();
    _confidentialityBoundary = _purgeSecretRoutes;
    widget.lockController.attachConfidentialityBoundary(
      _confidentialityBoundary,
    );
    _settings = widget.initialSettings;
    _cover =
        widget.initialCover ??
        (_settings.cover == CoverPreference.notes
            ? CoverKind.notes
            : CoverKind.calculator);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant PrivateVaultApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lockController, widget.lockController)) {
      oldWidget.lockController.detachConfidentialityBoundary(
        _confidentialityBoundary,
      );
      widget.lockController.attachConfidentialityBoundary(
        _confidentialityBoundary,
      );
    }
  }

  void _purgeSecretRoutes() {
    _secretMessengerKey.currentState?.clearSnackBars();
    _secretNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.lockController.onForeground();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.lockController.onBackground(
        delay: Duration(seconds: _settings.autoLockSeconds),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.lockController.detachConfidentialityBoundary(
      _confidentialityBoundary,
    );
    final panic = widget.panicService;
    if (panic != null) unawaited(panic.dispose());
    super.dispose();
  }

  Future<void> _requestUnlock(BuildContext materialContext) async {
    final configured = await widget.unlockService.isConfigured();
    if (!mounted || !materialContext.mounted) return;

    var biometricAvailable = false;
    final biometric = widget.biometricUnlock;
    if (configured && _settings.biometricsEnabled && biometric != null) {
      biometricAvailable = await biometric.isAvailable();
      if (!mounted || !materialContext.mounted) return;
    }

    var pin = '';
    String? error;
    await showModalBottomSheet<void>(
      context: materialContext,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              final candidate = pin;
              if (configured) {
                final accepted = await widget.unlockService.verify(candidate);
                if (!sheetContext.mounted) return;
                if (!accepted) {
                  setSheetState(() => error = 'PIN not accepted');
                  return;
                }
              } else {
                try {
                  await widget.unlockService.configure(candidate);
                } on Object {
                  if (!sheetContext.mounted) return;
                  setSheetState(
                    () => error = 'Use 6–12 digits for the access PIN',
                  );
                  return;
                }
              }

              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              widget.lockController.unlock();
            }

            Future<void> submitBiometric() async {
              if (!biometricAvailable || biometric == null) return;
              final accepted = await biometric.authenticate();
              if (!sheetContext.mounted) return;
              if (!accepted) {
                setSheetState(() => error = 'Biometric unlock not accepted');
                return;
              }
              Navigator.of(sheetContext).pop();
              widget.lockController.unlock();
            }

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                8,
                24,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .secondaryContainer,
                      child: Icon(
                        Icons.lock_outline,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    child: Text(
                      configured ? 'Enter PIN' : 'Set access PIN',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    configured
                        ? 'Unlock protected content with your access PIN.'
                        : 'Create a 6–12 digit PIN for protected content.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('unlock-pin'),
                    autofocus: true,
                    obscureText: true,
                    onChanged: (value) => pin = value,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 12,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: submit,
                    child: Text(configured ? 'Unlock' : 'Create PIN'),
                  ),
                  if (biometricAvailable) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: submitBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use biometrics'),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applySettings(AppSettings next) async {
    if (next == _settings) return;
    setState(() {
      _settings = next;
      _cover = next.cover == CoverPreference.notes
          ? CoverKind.notes
          : CoverKind.calculator;
    });
    widget.panicService?.updateSettings(next);
    await widget.settingsStore?.save(next);
  }

  Widget _secretWorkspace() {
    return ScaffoldMessenger(
      key: _secretMessengerKey,
      child: Navigator(
        key: _secretNavigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/secret'),
          builder: (_) => SecretWorkspace(
            onLock: widget.lockController.lock,
            vaultRepository: widget.vaultRepository,
            mediaService: widget.mediaService,
            settings: _settings,
            disguiseBridge: widget.disguiseBridge,
            workProfileClient: widget.workProfileClient,
            onSettingsChanged: (next) {
              unawaited(_applySettings(next));
            },
          ),
        ),
      ),
    );
  }

  Widget _coverWorkspace(BuildContext materialContext) {
    return switch (_cover) {
      CoverKind.calculator => CalculatorCover(
        onUnlockRequested: () => _requestUnlock(materialContext),
      ),
      CoverKind.notes => NotesCover(
        onUnlockRequested: () => _requestUnlock(materialContext),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _cover == CoverKind.calculator ? 'Calculator' : 'Notes',
      debugShowCheckedModeBanner: false,
      themeMode: _settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: PrivateVaultTheme.light(),
      darkTheme: PrivateVaultTheme.dark(),
      home: Builder(
        builder: (materialContext) => AnimatedBuilder(
          animation: widget.lockController,
          builder: (context, _) {
            if (widget.lockController.isLocked) {
              return _coverWorkspace(materialContext);
            }
            return _secretWorkspace();
          },
        ),
      ),
    );
  }
}

class SecretWorkspace extends StatefulWidget {
  const SecretWorkspace({
    super.key,
    required this.onLock,
    required this.settings,
    required this.onSettingsChanged,
    this.disguiseBridge,
    this.workProfileClient,
    this.vaultRepository,
    this.mediaService,
  });

  final VoidCallback onLock;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final PlatformDisguiseBridge? disguiseBridge;
  final WorkProfileClient? workProfileClient;
  final VaultRepository? vaultRepository;
  final MediaVaultService? mediaService;

  @override
  State<SecretWorkspace> createState() => _SecretWorkspaceState();
}

class _SecretWorkspaceState extends State<SecretWorkspace> {
  int _index = 0;
  final Set<int> _visited = {0};

  void _select(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  Widget _page(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    final hasApps = widget.workProfileClient != null;
    if (index == 0) {
      return widget.vaultRepository != null && widget.mediaService != null
          ? VaultHome(
              key: const ValueKey('vault-home'),
              repository: widget.vaultRepository!,
              media: widget.mediaService!,
              confirmExport: widget.settings.confirmExport,
            )
          : const _VaultUnavailable();
    }
    if (hasApps && index == 1) {
      return WorkProfileHome(
        key: const ValueKey('work-profile-home'),
        client: widget.workProfileClient!,
      );
    }
    final browserIndex = hasApps ? 2 : 1;
    if (index == browserIndex) {
      return BrowserHome(
        key: const ValueKey('browser-home'),
        repository: widget.vaultRepository,
        clearOnClose: widget.settings.browserClearOnClose,
      );
    }
    return _SettingsHome(
      key: const ValueKey('settings-home'),
      settings: widget.settings,
      disguiseBridge: widget.disguiseBridge,
      onChanged: widget.onSettingsChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasApps = widget.workProfileClient != null;
    final labels = hasApps
        ? const ['Vault', 'Apps', 'Browser', 'Settings']
        : const ['Vault', 'Browser', 'Settings'];
    final pageCount = hasApps ? 4 : 3;

    return Scaffold(
      appBar: AppBar(
        title: Text(labels[_index]),
        actions: [
          IconButton(
            onPressed: widget.onLock,
            tooltip: 'Lock now',
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(pageCount, _page),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Vault',
          ),
          if (hasApps)
            const NavigationDestination(
              icon: Icon(Icons.apps_outlined),
              selectedIcon: Icon(Icons.apps),
              label: 'Apps',
            ),
          const NavigationDestination(
            icon: Icon(Icons.language_outlined),
            selectedIcon: Icon(Icons.language),
            label: 'Browser',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _VaultUnavailable extends StatelessWidget {
  const _VaultUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Protected storage is unavailable in this runtime.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SettingsHome extends StatefulWidget {
  const _SettingsHome({
    super.key,
    required this.settings,
    required this.onChanged,
    this.disguiseBridge,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;
  final PlatformDisguiseBridge? disguiseBridge;

  @override
  State<_SettingsHome> createState() => _SettingsHomeState();
}

class _SettingsHomeState extends State<_SettingsHome> {
  late AppSettings _draft;
  Future<DisguiseCapabilities>? _capabilities;

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
    _refreshCapabilities();
  }

  @override
  void didUpdateWidget(covariant _SettingsHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings && _draft != widget.settings) {
      _draft = widget.settings;
    }
    if (!identical(oldWidget.disguiseBridge, widget.disguiseBridge)) {
      _refreshCapabilities();
    }
  }

  void _refreshCapabilities() {
    final bridge = widget.disguiseBridge;
    _capabilities = bridge?.capabilities();
  }

  void _commit(AppSettings next) {
    if (next == _draft) return;
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  void _updateDraft(AppSettings next) {
    if (next == _draft) return;
    setState(() => _draft = next);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _draft;
    final cover = settings.cover == CoverPreference.notes
        ? CoverKind.notes
        : CoverKind.calculator;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SettingsSection(
          title: 'Cover',
          icon: Icons.layers_outlined,
          child: SegmentedButton<CoverKind>(
            segments: const [
              ButtonSegment(
                value: CoverKind.calculator,
                label: Text('Calculator'),
                icon: Icon(Icons.calculate_outlined),
              ),
              ButtonSegment(
                value: CoverKind.notes,
                label: Text('Notes'),
                icon: Icon(Icons.checklist_outlined),
              ),
            ],
            selected: {cover},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              _commit(
                settings.copyWith(
                  cover: selection.first == CoverKind.notes
                      ? CoverPreference.notes
                      : CoverPreference.calculator,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          title: 'Concealment',
          icon: Icons.visibility_off_outlined,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Shake to conceal'),
                subtitle: const Text(
                  'Locks and returns to the cover workspace.',
                ),
                value: settings.panicShakeEnabled,
                onChanged: (value) =>
                    _commit(settings.copyWith(panicShakeEnabled: value)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Shake sensitivity'),
                subtitle: Slider(
                  key: const Key('settings-shake-slider'),
                  value: settings.shakeThresholdG,
                  min: 1.5,
                  max: 4.5,
                  divisions: 30,
                  label: settings.shakeThresholdG.toStringAsFixed(1),
                  onChanged: settings.panicShakeEnabled
                      ? (value) => _updateDraft(
                          settings.copyWith(shakeThresholdG: value),
                        )
                      : null,
                  onChangeEnd: settings.panicShakeEnabled
                      ? (_) => widget.onChanged(_draft)
                      : null,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Face-down conceal'),
                subtitle: const Text(
                  'Locks after the phone stays face-down for the configured delay.',
                ),
                value: settings.panicFaceDownEnabled,
                onChanged: (value) =>
                    _commit(settings.copyWith(panicFaceDownEnabled: value)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Face-down delay'),
                subtitle: Slider(
                  key: const Key('settings-face-down-slider'),
                  value: settings.faceDownDelayMs.toDouble(),
                  min: 500,
                  max: 3000,
                  divisions: 10,
                  label:
                      '${(settings.faceDownDelayMs / 1000).toStringAsFixed(1)} s',
                  onChanged: settings.panicFaceDownEnabled
                      ? (value) => _updateDraft(
                          settings.copyWith(faceDownDelayMs: value.round()),
                        )
                      : null,
                  onChangeEnd: settings.panicFaceDownEnabled
                      ? (_) => widget.onChanged(_draft)
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<int>(
                initialValue: settings.autoLockSeconds,
                decoration: const InputDecoration(
                  labelText: 'Lock after background',
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Immediately')),
                  DropdownMenuItem(value: 15, child: Text('15 seconds')),
                  DropdownMenuItem(value: 30, child: Text('30 seconds')),
                  DropdownMenuItem(value: 60, child: Text('1 minute')),
                  DropdownMenuItem(value: 300, child: Text('5 minutes')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _commit(settings.copyWith(autoLockSeconds: value));
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          title: 'Access',
          icon: Icons.fingerprint,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Biometric unlock'),
            subtitle: const Text('PIN remains the fallback and key owner.'),
            value: settings.biometricsEnabled,
            onChanged: (value) =>
                _commit(settings.copyWith(biometricsEnabled: value)),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          title: 'Data handling',
          icon: Icons.shield_outlined,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Clear browser data on close'),
                value: settings.browserClearOnClose,
                onChanged: (value) =>
                    _commit(settings.copyWith(browserClearOnClose: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Confirm before export'),
                value: settings.confirmExport,
                onChanged: (value) =>
                    _commit(settings.copyWith(confirmExport: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          title: 'Appearance',
          icon: Icons.contrast_outlined,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark mode'),
            value: settings.darkMode,
            onChanged: (value) => _commit(settings.copyWith(darkMode: value)),
          ),
        ),
        if (widget.disguiseBridge != null) ...[
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'Launcher',
            icon: Icons.apps_outlined,
            child: FutureBuilder<DisguiseCapabilities>(
              future: _capabilities,
              builder: (context, snapshot) {
                final capabilities =
                    snapshot.data ?? const DisguiseCapabilities();
                if (!capabilities.isSupported) {
                  return const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Launcher disguise unavailable'),
                    subtitle: Text(
                      'Support depends on the installed platform and build.',
                    ),
                  );
                }
                final description = capabilities.androidLauncherAliases
                    ? 'Android switches between predeclared launcher aliases and labels.'
                    : 'iOS changes only the predeclared icon. The app display name cannot change at runtime.';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              unawaited(
                                widget.disguiseBridge!.apply(
                                  DisguiseChoice.calculator,
                                ),
                              );
                            },
                            child: const Text('Calculator'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              unawaited(
                                widget.disguiseBridge!.apply(
                                  DisguiseChoice.notes,
                                ),
                              );
                            },
                            child: Text(
                              capabilities.androidLauncherAliases
                                  ? 'Notes'
                                  : 'Notes icon',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title settings',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
