import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android work-profile bridge crosses into managed profile', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final native = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
    ).readAsString();
    final bridgeFile = File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
    );

    expect(await bridgeFile.exists(), isTrue);
    final bridge = await bridgeFile.readAsString();

    expect(manifest, contains('.WorkProfileBridgeActivity'));
    expect(native, contains('addCrossProfileIntentFilter'));
    expect(native, contains('FLAG_MANAGED_CAN_ACCESS_PARENT'));
    expect(native, contains('PendingIntent.getBroadcast'));
    expect(native, contains('WorkProfileResultReceiver'));
    expect(native, contains('EXTRA_RESULT_PENDING_INTENT'));
    expect(native, contains('EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE'));
    expect(native, contains('EXTRA_CONTROL_TOKEN'));
    expect(bridge, contains('isProfileOwnerApp'));
    expect(bridge, contains('constantTimeTokenEquals'));
  });

  test(
    'ordinary clone transfers base and split APKs into PackageInstaller',
    () async {
      final native = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
      ).readAsString();
      final bridge = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
      ).readAsString();

      expect(native, contains('sourceDir'));
      expect(native, contains('splitSourceDirs'));
      expect(native, contains('ClipData'));
      expect(native, contains('FLAG_GRANT_READ_URI_PERMISSION'));
      expect(bridge, contains('PackageInstaller.SessionParams'));
      expect(bridge, contains('openWrite'));
      expect(bridge, contains('commit'));
    },
  );

  test('modern DPC provisioning hooks are declared', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();

    expect(manifest, contains('android.app.action.GET_PROVISIONING_MODE'));
    expect(manifest, contains('android.app.action.ADMIN_POLICY_COMPLIANCE'));
    expect(manifest, contains('.WorkProfileProvisioningModeActivity'));
    expect(manifest, contains('.WorkProfilePolicyComplianceActivity'));
  });

  test('profile owner declares wipe-data policy for profile removal', () async {
    final policy = await File(
      'android/app/src/main/res/xml/device_admin_receiver.xml',
    ).readAsString();

    expect(policy, contains('<wipe-data'));
  });

  test(
    'bridge reliability has bounded timeout quiet state and launch polling',
    () async {
      final adapter = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
      ).readAsString();
      final bridge = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
      ).readAsString();
      final policy = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileNativePolicy.kt',
      ).readAsString();

      expect(policy, contains('FAST_BRIDGE_TIMEOUT_MS'));
      expect(policy, contains('USER_CONFIRMATION_TIMEOUT_MS'));
      expect(policy, contains('bridgeTimeoutMs'));
      expect(policy, contains('bridgeTimeoutError'));
      expect(policy, contains('shouldContinuePolling'));
      expect(adapter, contains('isQuietModeEnabled'));
      expect(adapter, contains('profileQuiet ='));
      expect(policy, contains('NativeWorkProfileState.QUIET'));
      expect(adapter, contains('shouldRequestQuietModeDirectly'));
      expect(adapter, contains('requestQuietModeEnabled(false, otherProfile)'));
      expect(adapter, contains('MANAGED_PROFILE_SETTINGS_ACTION'));
      expect(adapter, contains('Settings.ACTION_SETTINGS'));
      expect(adapter, contains('USER_ACTION_REQUIRED'));
      expect(bridge, contains('setApplicationHidden'));
      expect(bridge, contains('MATCH_UNINSTALLED_PACKAGES'));
      expect(bridge, contains('MATCH_DISABLED_COMPONENTS'));
      expect(bridge, contains('setPackagesSuspended'));
      expect(bridge, contains('PACKAGE_STATE_TIMEOUT_MS'));
      expect(bridge, contains('queryIntentActivities'));
    },
  );

  test('vault shuttle is read-only and forwarded into isolated apps', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final adapter = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
    ).readAsString();
    final bridge = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
    ).readAsString();
    final providerFile = File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/VaultShuttleProvider.kt',
    );

    expect(await providerFile.exists(), isTrue);
    final provider = await providerFile.readAsString();
    expect(manifest, contains('.VaultShuttleProvider'));
    expect(manifest, contains(r'${applicationId}.vault_shuttle'));
    expect(provider, contains('TRANSFER_DIR = "vault-shuttle"'));
    expect(provider, contains('MODE_READ_ONLY'));
    expect(provider, isNot(contains('MODE_WRITE')));
    expect(adapter, contains('ACTION_SHARE_VAULT_FILE'));
    expect(adapter, contains('FLAG_GRANT_READ_URI_PERMISSION'));
    expect(bridge, contains('Intent.ACTION_SEND'));
    expect(bridge, contains('Intent.EXTRA_STREAM'));
    expect(bridge, contains('setPackage(targetPackage)'));
  });

  test('work-profile inbound picker preserves provider identity and streams to Vault', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final pigeon = await File('pigeons/work_profile_api.dart').readAsString();
    final adapter = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
    ).readAsString();
    final bridge = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
    ).readAsString();
    final mainActivity = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/MainActivity.kt',
    ).readAsString();
    final home = await File('lib/features/apps/work_profile_home.dart')
        .readAsString();

    expect(manifest, contains('action.PICK_WORK_DOCUMENT'));
    expect(manifest, contains('action.OPEN_STORE'));
    expect(manifest, contains('action.SHARE_VAULT_FILE'));
    expect(pigeon, contains('class NativePickedWorkDocument'));
    expect(pigeon, contains('NativePickedWorkDocument? pickWorkDocument()'));
    expect(bridge, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(bridge, contains('OpenableColumns.DISPLAY_NAME'));
    expect(bridge, contains('contentResolver.getType(uri)'));
    expect(bridge, contains('EXTRA_CAN_DELETE'));
    expect(adapter, contains('launchDocumentResult'));
    expect(mainActivity, contains('openDocumentStream'));
    expect(mainActivity, contains('readDocumentStream'));
    expect(mainActivity, contains('contentResolver.openInputStream(uri)'));
    expect(home, contains('PickedVaultSource('));
    expect(home, contains('mediaService.importSources'));
    expect(home, contains('moveSource: moveSource'));
    expect(home, isNot(contains('writeAsBytes')));
  });

  test(
    'readiness store fallback and icon transport stay bounded and app-scoped',
    () async {
      final adapter = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
      ).readAsString();
      final bridge = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
      ).readAsString();
      final client = await File('lib/features/apps/work_profile_client.dart')
          .readAsString();
      final home = await File('lib/features/apps/work_profile_home.dart')
          .readAsString();

      expect(home, contains('Future<void>? _refreshFuture'));
      expect(home, contains('if (current != null) return current'));
      expect(home, contains('future.whenComplete'));
      expect(bridge, contains('market://details?id='));
      expect(bridge, contains('packageManager.resolveActivity'));
      expect(bridge, contains('WorkProfileProtocol.ACTION_OPEN_STORE'));
      expect(adapter, contains('MAX_APP_ICON_BYTES = 64 * 1024'));
      expect(adapter, contains('MAX_APPS_JSON_BYTES = 256 * 1024'));
      expect(adapter, contains('boundedAppIconPng'));
      expect(bridge, contains('iconInclusionMask'));
      expect(bridge, contains('toJson(includeIcon = false)'));
      expect(client, contains('mapped.iconBytes ?? current.iconBytes'));
      expect(home, contains('Image.memory'));
    },
  );

  test('package visibility remains narrow', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();

    expect(manifest, isNot(contains('QUERY_ALL_PACKAGES')));
    expect(
      manifest,
      isNot(
        contains(
          r'android:permission="${applicationId}.permission.WORK_PROFILE_CONTROL"',
        ),
      ),
    );
  });
}
