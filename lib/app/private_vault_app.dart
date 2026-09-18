export '../features/auth/secure_unlock_service.dart' show UnlockService;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final AppSettings initialSettings;
  final CoverKind? initialCover;

  @override
  State<PrivateVaultApp> createState() => _PrivateVaultAppState();
}

class _PrivateVaultAppState extends State<PrivateVaultApp>
    with WidgetsBindingObserver {
  late AppSettings _settings;
  late CoverKind _cover;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _cover =
        widget.initialCover ??
        (_settings.cover == CoverPreference.notes
            ? CoverKind.notes
            : CoverKind.calculator);
    WidgetsBinding.instance.addObserver(this);
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
                  Text(
                    configured ? 'Enter PIN' : 'Set access PIN',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
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
    setState(() {
      _settings = next;
      _cover = next.cover == CoverPreference.notes
          ? CoverKind.notes
          : CoverKind.calculator;
    });
    widget.panicService?.updateSettings(next);
    await widget.settingsStore?.save(next);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF536975),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F7),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF91A7B3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (materialContext) => AnimatedBuilder(
          animation: widget.lockController,
          builder: (context, _) {
            if (widget.lockController.isLocked) {
              return _coverWorkspace(materialContext);
            }
            return SecretWorkspace(
              onLock: widget.lockController.lock,
              vaultRepository: widget.vaultRepository,
              mediaService: widget.mediaService,
              settings: _settings,
              disguiseBridge: widget.disguiseBridge,
              onSettingsChanged: (next) {
                unawaited(_applySettings(next));
              },
            );
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
    this.vaultRepository,
    this.mediaService,
  });

  final VoidCallback onLock;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final PlatformDisguiseBridge? disguiseBridge;
  final VaultRepository? vaultRepository;
  final MediaVaultService? mediaService;

  @override
  State<SecretWorkspace> createState() => _SecretWorkspaceState();
}

class _SecretWorkspaceState extends State<SecretWorkspace> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const labels = ['Vault', 'Browser', 'Settings'];

    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7086FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF111722),
        useMaterial3: true,
      ),
      child: Scaffold(
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
        body: switch (_index) {
          0 =>
            widget.vaultRepository != null && widget.mediaService != null
                ? VaultHome(
                    repository: widget.vaultRepository!,
                    media: widget.mediaService!,
                    confirmExport: widget.settings.confirmExport,
                  )
                : const _VaultUnavailable(),
          1 => BrowserHome(
            repository: widget.vaultRepository,
            clearOnClose: widget.settings.browserClearOnClose,
          ),
          _ => _SettingsHome(
            settings: widget.settings,
            disguiseBridge: widget.disguiseBridge,
            onChanged: widget.onSettingsChanged,
          ),
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Vault',
            ),
            NavigationDestination(
              icon: Icon(Icons.language_outlined),
              selectedIcon: Icon(Icons.language),
              label: 'Browser',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Settings',
            ),
          ],
        ),
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

class _SettingsHome extends StatelessWidget {
  const _SettingsHome({
    required this.settings,
    required this.onChanged,
    this.disguiseBridge,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;
  final PlatformDisguiseBridge? disguiseBridge;

  @override
  Widget build(BuildContext context) {
    final cover = settings.cover == CoverPreference.notes
        ? CoverKind.notes
        : CoverKind.calculator;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Cover', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<CoverKind>(
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
            onChanged(
              settings.copyWith(
                cover: selection.first == CoverKind.notes
                    ? CoverPreference.notes
                    : CoverPreference.calculator,
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        Text('Concealment', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Shake to conceal'),
          subtitle: const Text('Locks and returns to the cover workspace.'),
          value: settings.panicShakeEnabled,
          onChanged: (value) =>
              onChanged(settings.copyWith(panicShakeEnabled: value)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Shake sensitivity'),
          subtitle: Slider(
            value: settings.shakeThresholdG,
            min: 1.5,
            max: 4.5,
            divisions: 30,
            label: settings.shakeThresholdG.toStringAsFixed(1),
            onChanged: settings.panicShakeEnabled
                ? (value) =>
                      onChanged(settings.copyWith(shakeThresholdG: value))
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
              onChanged(settings.copyWith(panicFaceDownEnabled: value)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Face-down delay'),
          subtitle: Slider(
            value: settings.faceDownDelayMs.toDouble(),
            min: 500,
            max: 3000,
            divisions: 10,
            label: '${(settings.faceDownDelayMs / 1000).toStringAsFixed(1)} s',
            onChanged: settings.panicFaceDownEnabled
                ? (value) => onChanged(
                    settings.copyWith(faceDownDelayMs: value.round()),
                  )
                : null,
          ),
        ),
        DropdownButtonFormField<int>(
          initialValue: settings.autoLockSeconds,
          decoration: const InputDecoration(labelText: 'Lock after background'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Immediately')),
            DropdownMenuItem(value: 15, child: Text('15 seconds')),
            DropdownMenuItem(value: 30, child: Text('30 seconds')),
            DropdownMenuItem(value: 60, child: Text('1 minute')),
            DropdownMenuItem(value: 300, child: Text('5 minutes')),
          ],
          onChanged: (value) {
            if (value != null) {
              onChanged(settings.copyWith(autoLockSeconds: value));
            }
          },
        ),
        const SizedBox(height: 20),
        Text('Access', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Biometric unlock'),
          subtitle: const Text('PIN remains the fallback and key owner.'),
          value: settings.biometricsEnabled,
          onChanged: (value) =>
              onChanged(settings.copyWith(biometricsEnabled: value)),
        ),
        const SizedBox(height: 12),
        Text('Browser', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Clear browser data on close'),
          value: settings.browserClearOnClose,
          onChanged: (value) =>
              onChanged(settings.copyWith(browserClearOnClose: value)),
        ),
        const SizedBox(height: 12),
        Text('Export', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Confirm before export'),
          value: settings.confirmExport,
          onChanged: (value) =>
              onChanged(settings.copyWith(confirmExport: value)),
        ),
        const SizedBox(height: 12),
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dark mode'),
          value: settings.darkMode,
          onChanged: (value) => onChanged(settings.copyWith(darkMode: value)),
        ),
        if (disguiseBridge != null) ...[
          const SizedBox(height: 12),
          Text('Launcher', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<DisguiseCapabilities>(
            future: disguiseBridge!.capabilities(),
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            unawaited(
                              disguiseBridge!.apply(DisguiseChoice.calculator),
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
                              disguiseBridge!.apply(DisguiseChoice.notes),
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
        ],
      ],
    );
  }
}
