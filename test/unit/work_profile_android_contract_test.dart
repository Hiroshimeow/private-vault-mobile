import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bridge returns results through an explicit PendingIntent callback',
    () async {
      final manifest = await File('android/app/src/main/AndroidManifest.xml')
          .readAsString();
      final adapter = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
      ).readAsString();
      final bridge = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
      ).readAsString();

      expect(manifest, contains('.WorkProfileResultReceiver'));
      expect(adapter, contains('PendingIntent.getBroadcast'));
      expect(adapter, contains('EXTRA_RESULT_PENDING_INTENT'));
      expect(bridge, contains('EXTRA_RESULT_PENDING_INTENT'));
      expect(bridge, contains('.send('));
      expect(adapter, contains('activity.startActivity('));
    },
  );

  test(
    'typed bridge error is parsed before generic result-code failure',
    () async {
      final adapter = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
      ).readAsString();

      final parseTypedError = adapter.indexOf(
        'data?.getStringExtra(WorkProfileProtocol.EXTRA_ERROR_CODE)',
      );
      final genericFailure = adapter.indexOf(
        'if (resultCode != Activity.RESULT_OK || data == null)',
        adapter.indexOf('private fun operationResult'),
      );

      expect(parseTypedError, greaterThanOrEqualTo(0));
      expect(genericFailure, greaterThanOrEqualTo(0));
      expect(parseTypedError, lessThan(genericFailure));
    },
  );

  test(
    'ordinary clone preserves base and split APKs in work PackageInstaller',
    () async {
      final adapter = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
      ).readAsString();
      final bridge = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
      ).readAsString();

      expect(adapter, contains('splitSourceDirs'));
      expect(adapter, contains('ClipData'));
      expect(adapter, contains('FLAG_GRANT_READ_URI_PERMISSION'));
      expect(bridge, contains('PackageInstaller.SessionParams'));
      expect(bridge, contains('openWrite'));
      expect(bridge, contains('STATUS_PENDING_USER_ACTION'));
    },
  );

  test(
    'transient APK files are cleaned after bridge result or launch failure',
    () async {
      final adapter = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
      ).readAsString();

      expect(adapter, contains('revokeUriPermission'));
      expect(adapter, contains('staged.forEach'));
      expect(adapter, contains('file.delete()'));
    },
  );

  test(
    'work-only policy commands execute only in profile-owner bridge',
    () async {
      final bridge = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
      ).readAsString();

      expect(bridge, contains('isProfileOwnerApp'));
      expect(bridge, contains('enableSystemApp'));
      expect(bridge, contains('setPackagesSuspended'));
      expect(bridge, contains('setApplicationHidden'));
      expect(bridge, contains('packageManager.packageInstaller.uninstall'));
      expect(bridge, contains('ACTION_UNINSTALL_STATUS'));
    },
  );

  test('managed-profile CI bootstrap is debug-only and production manifest stays clean', () async {
    final mainManifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final debugManifest = await File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsString();
    final debugReceiver = File(
      'android/app/src/debug/kotlin/io/hiroshimeow/private_vault_mobile/'
      'WorkProfileDebugBootstrapReceiver.kt',
    );
    final smokeScript = File('tool/work_profile_clone_smoke.sh');
    final smokeTest = File(
      'integration_test/work_profile_clone_smoke_test.dart',
    );

    expect(mainManifest, isNot(contains('WorkProfileDebugBootstrapReceiver')));
    expect(debugManifest, contains('.WorkProfileDebugBootstrapReceiver'));
    expect(await debugReceiver.exists(), isTrue);
    expect(await smokeScript.exists(), isTrue);
    expect(await smokeTest.exists(), isTrue);

    final script = await smokeScript.readAsString();
    expect(script, contains('pm create-user'));
    expect(script, contains('--profileOf 0'));
    expect(script, contains('--managed'));
    expect(script, contains('--for-testing'));
    expect(script, contains('dpm set-profile-owner'));
    expect(script, contains('wait_for_profile_ready'));
    expect(script, contains('dump_diagnostics'));
    expect(script, contains('dumpsys device_policy'));
    expect(script, contains('pm list users'));
    expect(script, isNot(contains('sleep 1')));
    expect(script, contains('work_profile_clone_smoke_test.dart'));
  });

  test(
    'package visibility stays narrow and does not request global visibility',
    () async {
      final manifest = await File('android/app/src/main/AndroidManifest.xml')
          .readAsString();

      expect(manifest, isNot(contains('QUERY_ALL_PACKAGES')));
      expect(manifest, contains('android.intent.category.LAUNCHER'));
    },
  );
}
