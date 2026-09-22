export '../features/auth/secure_unlock_service.dart'
    show PinLengthAwareUnlockService, UnlockService;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:private_vault_mobile/app/private_vault_theme.dart';
import 'package:private_vault_mobile/features/apps/vault_shuttle_service.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/apps/work_profile_home.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/auth/secure_unlock_service.dart';
import 'package:private_vault_mobile/features/auth/system_handoff_lifecycle.dart';
import 'package:private_vault_mobile/features/auth/unlock_gate/calculator_unlock_gate.dart';
import 'package:private_vault_mobile/features/auth/unlock_attempt_controller.dart';
import 'package:private_vault_mobile/features/browser/browser_home.dart';
import 'package:private_vault_mobile/features/cover/calculator_cover.dart';
import 'package:private_vault_mobile/features/cover/notes_cover.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/panic/panic_sensor_service.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/legacy_v1_migration.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_storage.dart';
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
    this.vaultShuttle,
    this.portableRootAccess,
    this.legacyVaultMigration,
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
  final VaultShuttle? vaultShuttle;
  final PortableVaultRootAccess? portableRootAccess;
  final LegacyVaultMigrationService? legacyVaultMigration;
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
  Future<int?>? _pinLengthFuture;
  int _calculatorPinLength = 4;
  final CalculatorUnlockAttemptController _unlockAttemptController =
      CalculatorUnlockAttemptController();
  late final SystemHandoffLifecycleCoordinator _handoffLifecycle;

  @override
  void initState() {
    super.initState();
    _confidentialityBoundary = _purgeSecretRoutes;
    widget.lockController.attachConfidentialityBoundary(
      _confidentialityBoundary,
    );
    _settings = widget.initialSettings;
    _handoffLifecycle = SystemHandoffLifecycleCoordinator(
      onBackground: () => widget.lockController.onBackground(
        delay: Duration(seconds: _settings.autoLockSeconds),
      ),
      onForeground: widget.lockController.onForeground,
    );
    _cover =
        widget.initialCover ??
        (_settings.cover == CoverPreference.notes
            ? CoverKind.notes
            : CoverKind.calculator);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshCalculatorPinLength());
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
    if (!identical(oldWidget.unlockService, widget.unlockService)) {
      _pinLengthFuture = null;
      unawaited(_refreshCalculatorPinLength());
    }
  }

  void _purgeSecretRoutes() {
    _secretMessengerKey.currentState?.clearSnackBars();
    _secretNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    final media = widget.mediaService;
    if (media != null) {
      unawaited(media.purgePreviewPlaintext());
    }
    final repository = widget.vaultRepository;
    if (repository is PinSessionVaultRepository) {
      repository.clearSession();
    }
    final shuttle = widget.vaultShuttle;
    if (shuttle != null) {
      unawaited(shuttle.purgeStagedPlaintext());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handoffLifecycle.handle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _handoffLifecycle.dispose();
    final biometricWasStarted = _unlockAttemptController.cancelCurrent();
    final biometric = widget.biometricUnlock;
    if (biometricWasStarted && biometric != null) {
      unawaited(biometric.cancel());
    }
    _unlockAttemptController.dispose();
    final media = widget.mediaService;
    if (media != null) {
      unawaited(media.purgePreviewPlaintext());
    }
    final repository = widget.vaultRepository;
    if (repository is PinSessionVaultRepository) {
      repository.clearSession();
    }
    widget.lockController.detachConfidentialityBoundary(
      _confidentialityBoundary,
    );
    final panic = widget.panicService;
    if (panic != null) unawaited(panic.dispose());
    super.dispose();
  }

  Future<void> _refreshCalculatorPinLength() async {
    final length = await _configuredPinLength();
    if (!mounted || length == null || length == _calculatorPinLength) return;
    setState(() => _calculatorPinLength = length);
  }

  Future<int?> _configuredPinLength() {
    final service = widget.unlockService;
    if (service is! PinLengthAwareUnlockService) {
      return Future<int?>.value(null);
    }
    final lengthAware = service as PinLengthAwareUnlockService;
    return _pinLengthFuture ??= lengthAware.configuredPinLength();
  }

  Future<bool> _openVaultSession(String pin) async {
    final repository = widget.vaultRepository;
    if (repository is! PinSessionVaultRepository) return true;
    try {
      await repository.openSession(pin);
      return true;
    } on Object {
      repository.clearSession();
      return false;
    }
  }

  Future<void> _attemptCalculatorUnlock(CalculatorUnlockAttempt attempt) async {
    if (!widget.lockController.isLocked) return;

    final state = _unlockAttemptController.begin();
    try {
      final configuredLength = await _configuredPinLength();
      if (!mounted ||
          !widget.lockController.isLocked ||
          !_unlockAttemptController.isCurrent(state)) {
        return;
      }
      if (configuredLength == null ||
          attempt.candidate.length != configuredLength) {
        return;
      }

      final pinAccepted = await widget.unlockService.verify(attempt.candidate);
      if (!mounted ||
          !widget.lockController.isLocked ||
          !_unlockAttemptController.isCurrent(state) ||
          !pinAccepted) {
        return;
      }

      if (attempt.requiresBiometric) {
        final biometric = widget.biometricUnlock;
        if (!_settings.biometricsEnabled || biometric == null) return;
        if (!_unlockAttemptController.beginBiometricCheck(state)) return;

        final available = await biometric.isAvailable();
        if (!mounted ||
            !widget.lockController.isLocked ||
            !_unlockAttemptController.isCurrent(state) ||
            !available) {
          return;
        }

        if (!_unlockAttemptController.markBiometricStarted(state)) return;
        final biometricAccepted = await biometric.authenticate();
        if (!mounted ||
            !widget.lockController.isLocked ||
            !_unlockAttemptController.isCurrent(state) ||
            !biometricAccepted) {
          return;
        }
      }

      if (_unlockAttemptController.isCurrent(state) &&
          widget.lockController.isLocked) {
        if (!await _openVaultSession(attempt.candidate)) return;
        if (!_unlockAttemptController.isCurrent(state) ||
            !widget.lockController.isLocked) {
          final repository = widget.vaultRepository;
          if (repository is PinSessionVaultRepository) {
            repository.clearSession();
          }
          return;
        }
        widget.lockController.unlock();
      }
    } finally {
      _unlockAttemptController.complete(state);
    }
  }

  void _onCalculatorUnlockReleased(CalculatorUnlockTrigger trigger) {
    if (trigger != CalculatorUnlockTrigger.equals) return;
    final biometricWasStarted = _unlockAttemptController.cancelCurrent();
    final biometric = widget.biometricUnlock;
    if (biometricWasStarted && biometric != null) {
      unawaited(biometric.cancel());
    }
  }

  Future<void> _requestUnlock(BuildContext materialContext) async {
    final configured = await widget.unlockService.isConfigured();
    if (!mounted || !materialContext.mounted) return;

    var biometricAvailable = false;
    final biometric = widget.biometricUnlock;
    if (_settings.biometricsEnabled && biometric != null) {
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
                  _pinLengthFuture = null;
                } on Object {
                  if (!sheetContext.mounted) return;
                  setSheetState(
                    () => error = 'Use 4–12 digits for the access PIN',
                  );
                  return;
                }
              }

              if (_settings.biometricsEnabled) {
                if (!biometricAvailable || biometric == null) {
                  if (!sheetContext.mounted) return;
                  setSheetState(() => error = 'Biometrics unavailable');
                  return;
                }
                final biometricAccepted = await biometric.authenticate();
                if (!sheetContext.mounted) return;
                if (!biometricAccepted) {
                  setSheetState(() => error = 'Biometric unlock not accepted');
                  return;
                }
              }

              if (!sheetContext.mounted) return;
              if (!await _openVaultSession(candidate)) {
                if (!sheetContext.mounted) return;
                setSheetState(() => error = 'Protected storage unavailable');
                return;
              }
              if (!sheetContext.mounted) {
                final repository = widget.vaultRepository;
                if (repository is PinSessionVaultRepository) {
                  repository.clearSession();
                }
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
                        : 'Create a 4–12 digit PIN for protected content.',
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
            unlockService: widget.unlockService,
            onPinChanged: (pin) async {
              if (!await _openVaultSession(pin)) return false;
              _pinLengthFuture = null;
              await _refreshCalculatorPinLength();
              return true;
            },
            vaultRepository: widget.vaultRepository,
            mediaService: widget.mediaService,
            onSystemHandoffChanged: (active) {
              if (active) {
                _handoffLifecycle.arm();
              } else {
                _handoffLifecycle.disarm();
              }
            },
            settings: _settings,
            disguiseBridge: widget.disguiseBridge,
            workProfileClient: widget.workProfileClient,
            vaultShuttle: widget.vaultShuttle,
            portableRootAccess: widget.portableRootAccess,
            legacyVaultMigration: widget.legacyVaultMigration,
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
        pinLength: _calculatorPinLength,
        biometricMode: _settings.biometricsEnabled,
        holdDuration: Duration(milliseconds: _settings.unlockHoldMs),
        onUnlockTriggered: (attempt) =>
            unawaited(_attemptCalculatorUnlock(attempt)),
        onUnlockReleased: _onCalculatorUnlockReleased,
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
    required this.unlockService,
    required this.onPinChanged,
    required this.onSystemHandoffChanged,
    required this.settings,
    required this.onSettingsChanged,
    this.disguiseBridge,
    this.portableRootAccess,
    this.legacyVaultMigration,
    this.workProfileClient,
    this.vaultShuttle,
    this.vaultRepository,
    this.mediaService,
  });

  final VoidCallback onLock;
  final UnlockService unlockService;
  final Future<bool> Function(String pin) onPinChanged;
  final ValueChanged<bool> onSystemHandoffChanged;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final PlatformDisguiseBridge? disguiseBridge;
  final PortableVaultRootAccess? portableRootAccess;
  final LegacyVaultMigrationService? legacyVaultMigration;
  final WorkProfileClient? workProfileClient;
  final VaultShuttle? vaultShuttle;
  final VaultRepository? vaultRepository;
  final MediaVaultService? mediaService;

  @override
  State<SecretWorkspace> createState() => _SecretWorkspaceState();
}

class _SecretWorkspaceState extends State<SecretWorkspace> {
  int _index = 0;
  int _vaultIdentityEpoch = 0;
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
              key: ValueKey('vault-home-$_vaultIdentityEpoch'),
              repository: widget.vaultRepository!,
              media: widget.mediaService!,
              confirmExport: widget.settings.confirmExport,
              onSystemHandoffChanged: widget.onSystemHandoffChanged,
            )
          : const _VaultUnavailable();
    }
    if (hasApps && index == 1) {
      return WorkProfileHome(
        key: const ValueKey('work-profile-home'),
        client: widget.workProfileClient!,
        vaultShuttle: widget.vaultShuttle,
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
      unlockService: widget.unlockService,
      onPinChanged: (pin) async {
        final switched = await widget.onPinChanged(pin);
        if (switched && mounted) {
          setState(() {
            _vaultIdentityEpoch += 1;
            _visited.add(0);
          });
        }
        return switched;
      },
      disguiseBridge: widget.disguiseBridge,
      portableRootAccess: widget.portableRootAccess,
      legacyVaultMigration: widget.legacyVaultMigration,
      onSystemHandoffChanged: widget.onSystemHandoffChanged,
      onPortableRootChanged: () {
        if (!mounted) return;
        setState(() => _vaultIdentityEpoch += 1);
      },
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
    required this.unlockService,
    required this.onPinChanged,
    required this.onChanged,
    this.disguiseBridge,
    this.portableRootAccess,
    this.legacyVaultMigration,
    required this.onSystemHandoffChanged,
    required this.onPortableRootChanged,
  });

  final AppSettings settings;
  final UnlockService unlockService;
  final Future<bool> Function(String pin) onPinChanged;
  final ValueChanged<AppSettings> onChanged;
  final PlatformDisguiseBridge? disguiseBridge;
  final PortableVaultRootAccess? portableRootAccess;
  final LegacyVaultMigrationService? legacyVaultMigration;
  final ValueChanged<bool> onSystemHandoffChanged;
  final VoidCallback onPortableRootChanged;

  @override
  State<_SettingsHome> createState() => _SettingsHomeState();
}

class _SettingsHomeState extends State<_SettingsHome> {
  late AppSettings _draft;
  Future<DisguiseCapabilities>? _capabilities;
  Future<bool>? _portableRootStatus;
  Future<LegacyVaultMigrationPreview>? _legacyMigrationPreview;
  bool _legacyMigrationBusy = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
    _refreshCapabilities();
    _refreshPortableRootStatus();
    _refreshLegacyMigrationPreview();
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
    if (!identical(oldWidget.portableRootAccess, widget.portableRootAccess)) {
      _refreshPortableRootStatus();
    }
    if (!identical(
      oldWidget.legacyVaultMigration,
      widget.legacyVaultMigration,
    )) {
      _refreshLegacyMigrationPreview();
    }
  }

  void _refreshCapabilities() {
    final bridge = widget.disguiseBridge;
    _capabilities = bridge?.capabilities();
  }

  void _refreshPortableRootStatus() {
    final access = widget.portableRootAccess;
    _portableRootStatus = access?.hasRoot();
  }

  void _refreshLegacyMigrationPreview() {
    _legacyMigrationPreview = widget.legacyVaultMigration?.inspect();
  }

  Future<void> _migrateLegacyVault() async {
    final migration = widget.legacyVaultMigration;
    if (migration == null || _legacyMigrationBusy) return;

    final rootAccess = widget.portableRootAccess;
    if (rootAccess != null && !await rootAccess.hasRoot()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a Portable Vault folder before copying legacy data.',
          ),
        ),
      );
      return;
    }

    final preview = await migration.inspect();
    if (!mounted) return;
    if (preview.keyUnavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Legacy encrypted data exists, but its V1 key is unavailable. '
            'The original files were not changed.',
          ),
        ),
      );
      return;
    }
    if (preview.itemCount == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Copy legacy Vault data?'),
        content: Text(
          'Copy ${preview.itemCount} V1 item(s) into the current Portable Vault. '
          'The original V1 files remain untouched. Running migration again may '
          'create duplicate copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('settings-migrate-legacy-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Copy legacy data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _legacyMigrationBusy = true);
    LegacyVaultMigrationResult? result;
    Object? failure;
    try {
      result = await migration.copyAll();
    } on Object catch (error) {
      failure = error;
    } finally {
      if (mounted) {
        setState(() {
          _legacyMigrationBusy = false;
          _refreshLegacyMigrationPreview();
        });
      }
    }
    if (!mounted) return;

    if (failure != null || result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Legacy data could not be copied. The original V1 files were not changed.',
          ),
        ),
      );
      return;
    }

    widget.onPortableRootChanged();
    final message = result.failedCount == 0
        ? 'Copied ${result.importedCount} legacy item(s). Original V1 data was kept.'
        : 'Copied ${result.importedCount} legacy item(s); '
              '${result.failedCount} failed. Original V1 data was kept.';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choosePortableRoot() async {
    final access = widget.portableRootAccess;
    if (access == null) return;
    widget.onSystemHandoffChanged(true);
    try {
      await access.pickRoot();
    } finally {
      widget.onSystemHandoffChanged(false);
    }
    if (!mounted) return;
    setState(_refreshPortableRootStatus);
    widget.onPortableRootChanged();
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

  Future<void> _changePin() async {
    var pin = '';
    var confirm = '';
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Switch Vault PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The PIN selects the Vault identity. Existing data under other PINs is not deleted.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('settings-new-pin'),
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 12,
                decoration: const InputDecoration(labelText: 'New PIN'),
                onChanged: (value) => pin = value,
              ),
              TextField(
                key: const Key('settings-confirm-pin'),
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: 'Confirm PIN',
                  errorText: error,
                ),
                onChanged: (value) => confirm = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('settings-save-pin'),
              onPressed: () async {
                if (pin != confirm) {
                  setDialogState(() => error = 'PINs do not match');
                  return;
                }
                try {
                  await widget.unlockService.configure(pin);
                } on InvalidPinException {
                  setDialogState(() => error = 'Use 4-12 digits');
                  return;
                }
                final switched = await widget.onPinChanged(pin);
                if (!dialogContext.mounted) return;
                if (!switched) {
                  setDialogState(() => error = 'Protected storage unavailable');
                  return;
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Switch PIN'),
            ),
          ],
        ),
      ),
    );
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
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Biometric mode'),
                subtitle: Text(
                  settings.biometricsEnabled
                      ? 'Enter the full PIN, then hold =. Release = to cancel biometric scanning.'
                      : 'Enter the full PIN, then hold the second PIN digit.',
                ),
                value: settings.biometricsEnabled,
                onChanged: (value) =>
                    _commit(settings.copyWith(biometricsEnabled: value)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.password_outlined),
                title: const Text('Switch Vault PIN'),
                subtitle: const Text(
                  'PIN changes are available only inside Settings.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changePin,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Unlock hold duration'),
                subtitle: Slider(
                  key: const Key('settings-unlock-hold-slider'),
                  value: settings.unlockHoldMs.toDouble(),
                  min: 700,
                  max: 3000,
                  divisions: 23,
                  label:
                      '${(settings.unlockHoldMs / 1000).toStringAsFixed(1)} s',
                  onChanged: (value) => _updateDraft(
                    settings.copyWith(unlockHoldMs: value.round()),
                  ),
                  onChangeEnd: (_) => widget.onChanged(_draft),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          title: 'Data handling',
          icon: Icons.shield_outlined,
          child: Column(
            children: [
              if (widget.portableRootAccess != null)
                FutureBuilder<bool>(
                  future: _portableRootStatus,
                  builder: (context, snapshot) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Portable Vault folder'),
                    subtitle: Text(
                      snapshot.data == true
                          ? 'Shared folder authorized for portable encrypted storage.'
                          : 'Choose a shared folder to keep encrypted data across reinstalls.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _choosePortableRoot,
                  ),
                ),
              if (widget.legacyVaultMigration != null)
                FutureBuilder<LegacyVaultMigrationPreview>(
                  future: _legacyMigrationPreview,
                  builder: (context, snapshot) {
                    final preview = snapshot.data;
                    if (preview == null ||
                        (preview.itemCount == 0 && !preview.keyUnavailable)) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      key: const Key('settings-legacy-v1-migration'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_outlined),
                      title: const Text('Legacy Vault V1 data'),
                      subtitle: Text(
                        preview.keyUnavailable
                            ? 'Legacy encrypted data exists, but its V1 key is unavailable. '
                                  'Original files remain untouched.'
                            : '${preview.itemCount} legacy item(s) can be copied into '
                                  'the current Portable Vault. Originals stay untouched.',
                      ),
                      trailing: preview.keyUnavailable
                          ? const Icon(Icons.warning_amber_outlined)
                          : _legacyMigrationBusy
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              key: const Key('settings-migrate-legacy'),
                              onPressed: _migrateLegacyVault,
                              child: const Text('Copy'),
                            ),
                    );
                  },
                ),
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
