import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/core/storage/secret_store.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/auth/secure_unlock_service.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/panic/panic_sensor_service.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';
import 'package:private_vault_mobile/platform/disguise_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsStore = AppSettingsStore(SharedPreferencesSettingsStorage());
  final settings = await settingsStore.load();
  final secrets = FlutterSecureSecretStore();
  final lockController = LockController();
  final repository = LocalVaultRepository(
    rootDirectory: () async {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'private-vault'));
    },
    keyStore: SecureVaultKeyStore(secrets),
    crypto: VaultCrypto(),
  );
  final media = MediaVaultService(
    repository: repository,
    pickImport: MediaVaultService.pickDeviceFile,
    capturePhoto: MediaVaultService.captureDevicePhoto,
    saveExport: MediaVaultService.saveDeviceExport,
  );
  final panic = PanicSensorService(
    lockController: lockController,
    settings: settings,
    samples: PanicSensorService.deviceSamples(),
  )..start();

  runApp(
    PrivateVaultApp(
      lockController: lockController,
      unlockService: SecureUnlockService(store: secrets),
      biometricUnlock: DeviceBiometricUnlock(),
      vaultRepository: repository,
      mediaService: media,
      settingsStore: settingsStore,
      panicService: panic,
      disguiseBridge: PlatformDisguiseBridge(),
      initialSettings: settings,
    ),
  );
}
