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
