import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/core/crypto/vault_crypto.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/browser/browser_profiles.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class _Unlock implements UnlockService {
  @override
  Future<void> configure(String pin) async {}

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) async => candidate == '482951';
}

class _Biometric implements BiometricUnlock {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

class _Keys implements VaultKeyStore {
  SecretKey? _key;

  @override
  Future<SecretKey> getOrCreate() async =>
      _key ??= await AesGcm.with256bits().newSecretKey();

  @override
  Future<SecretKey?> read() async => _key;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RC locked, unlock, lifecycle relock, and panic conceal', (
    tester,
  ) async {
    final lock = LockController();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: _Unlock(),
        biometricUnlock: _Biometric(),
        initialSettings: const AppSettings.defaults().copyWith(
          biometricsEnabled: true,
          autoLockSeconds: 0,
        ),
      ),
    );

    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);

    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('unlock-pin')), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('PIN not accepted'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);

    await tester.enterText(find.byKey(const Key('unlock-pin')), '482951');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Lock now'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);

    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Use biometrics'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Lock now'), findsOneWidget);

    lock.panic();
    await tester.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('RC production crypto round-trip rejects tampering', (
    tester,
  ) async {
    final temp = await Directory.systemTemp.createTemp('private-vault-rc-');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final repo = LocalVaultRepository(
      rootDirectory: () async => temp,
      keyStore: _Keys(),
      crypto: VaultCrypto(),
    );
    final clear = Uint8List.fromList('rc-device-secret'.codeUnits);

    final item = await repo.addBytes(clear, kind: VaultItemKind.note);
    expect(await repo.readBytes(item.id), clear);

    final file = File('${temp.path}${Platform.pathSeparator}${item.id}.vault');
    final bytes = await file.readAsBytes();
    bytes[bytes.length ~/ 2] ^= 1;
    await file.writeAsBytes(bytes, flush: true);

    expect(
      () => repo.readBytes(item.id),
      throwsA(
        anyOf(isA<VaultIntegrityException>(), isA<VaultFormatException>()),
      ),
    );
  });

  testWidgets('RC browser profile switch and close clear shared state', (
    tester,
  ) async {
    var cookieClears = 0;
    var cacheClears = 0;
    final profiles = EphemeralBrowserProfiles(
      clearCookies: () async => cookieClears++,
      clearCache: () async => cacheClears++,
      clearOnClose: true,
    );
    final second = profiles.addProfile();

    await profiles.switchTo(second.id);
    await profiles.close();

    expect(cookieClears, 2);
    expect(cacheClears, 2);
  });
}
