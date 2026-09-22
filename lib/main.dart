import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/core/storage/secret_store.dart';
import 'package:private_vault_mobile/features/apps/vault_shuttle_service.dart';
import 'package:private_vault_mobile/features/apps/work_profile_client.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/auth/secure_unlock_service.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/panic/panic_sensor_service.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/legacy_v1_migration.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_repository.dart';
import 'package:private_vault_mobile/features/vault/portable_storage/portable_vault_session.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';
import 'package:private_vault_mobile/platform/disguise_bridge.dart';
import 'package:private_vault_mobile/platform/portable_vault_tree_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsStore = AppSettingsStore(SharedPreferencesSettingsStorage());
  final settings = await settingsStore.load();
  final secrets = FlutterSecureSecretStore();
  final unlockService = SecureUnlockService(store: secrets);
  if (!await unlockService.isConfigured()) {
    await unlockService.configure('0000');
  }
  final lockController = LockController();

  final PortableVaultTreeBridge? portableTree = Platform.isAndroid
      ? PortableVaultTreeBridge()
      : null;
  Future<Directory> legacyRootDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'private-vault'));
  }

  final VaultRepository repository;
  LegacyVaultMigrationService? legacyVaultMigration;
  if (portableTree != null) {
    final portableRepository = PortableVaultRepository(
      storage: portableTree,
      session: PortableVaultSession(),
    );
    repository = portableRepository;
    legacyVaultMigration = LegacyVaultMigrationService(
      source: LocalVaultRepository(
        rootDirectory: legacyRootDirectory,
        keyStore: SecureVaultKeyStore(secrets),
        crypto: VaultCrypto(),
      ),
      target: portableRepository,
    );
  } else {
    repository = LocalVaultRepository(
      rootDirectory: legacyRootDirectory,
      keyStore: SecureVaultKeyStore(secrets),
      crypto: VaultCrypto(),
    );
  }

  final media = MediaVaultService(
    repository: repository,
    pickImport: MediaVaultService.pickDeviceFile,
    pickImports: MediaVaultService.pickDeviceFiles,
    capturePhoto: MediaVaultService.captureDevicePhoto,
    saveExport: MediaVaultService.saveDeviceExport,
  );
  final panic = PanicSensorService(
    lockController: lockController,
    settings: settings,
    samples: PanicSensorService.deviceSamples(),
  )..start();
  final vaultShuttle = Platform.isAndroid
      ? VaultShuttleService(
          repository: repository,
          bridge: PigeonVaultShuttleBridge(),
          tempDirectory: getTemporaryDirectory,
        )
      : null;
  if (vaultShuttle != null) {
    await vaultShuttle.purgeStagedPlaintext();
  }

  runApp(
    PrivateVaultApp(
      lockController: lockController,
      unlockService: unlockService,
      biometricUnlock: DeviceBiometricUnlock(),
      vaultRepository: repository,
      mediaService: media,
      settingsStore: settingsStore,
      panicService: panic,
      disguiseBridge: PlatformDisguiseBridge(),
      portableRootAccess: portableTree,
      legacyVaultMigration: legacyVaultMigration,
      workProfileClient: Platform.isAndroid
          ? PigeonWorkProfileClient()
          : const UnavailableWorkProfileClient(),
      vaultShuttle: vaultShuttle,
      initialSettings: settings,
    ),
  );
}
