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
      expect(adapter, isNot(contains('requestQuietModeEnabled')));
      expect(bridge, contains('setApplicationHidden'));
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
