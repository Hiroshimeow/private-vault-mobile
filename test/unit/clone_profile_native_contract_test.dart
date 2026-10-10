import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apps clone path is helper-UID plugin transform, not privileged cloning', () async {
    final app = await File('lib/app/private_vault_app.dart').readAsString();
    final main = await File('lib/main.dart').readAsString();
    final bridge = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/CloneProfileBridge.kt',
    ).readAsString();
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    final settings = await File('android/settings.gradle.kts').readAsString();
    final appManifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final helperManifest = await File(
      'android/pluginhost/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(app, contains('CloneProfileHome('));
    expect(app, contains('widget.cloneProfileClient'));
    expect(main, contains('PlatformCloneProfileClient()'));
    expect(settings, contains('include(":pluginhost")'));
    expect(settings, contains('include(":pluginfixture")'));
    expect(gradle, isNot(contains('dev.rikka.shizuku')));

    final forbidden = <String>[
      'Shizuku',
      'profile.CLONE',
      'android.os.usertype.profile.CLONE',
      'install-existing',
      'create-clone',
      'ACTION_PROVISION_MANAGED_PROFILE',
      'ACTION_PROVISION_MANAGED_DEVICE',
      'getLaunchIntentForPackage',
    ];
    for (final token in forbidden) {
      expect(bridge, isNot(contains(token)), reason: 'forbidden active clone token: $token');
    }

    expect(bridge, contains('PLUGIN_HOST_SLOT0'));
    expect(bridge, contains('PLUGIN_HOST_SLOT1'));
    expect(bridge, contains('contentResolver.call'));
    expect(appManifest, contains('android:protectionLevel="signature"'));
    expect(helperManifest, contains('PluginHostProvider'));
    expect(helperManifest, contains('PluginContainerActivity'));
    expect(helperManifest, contains('android:exported="false"'));
  });

  test('Vault and helper share one fail-closed release signing owner', () async {
    final appGradle = await File('android/app/build.gradle.kts').readAsString();
    final hostGradle = await File('android/pluginhost/build.gradle.kts').readAsString();
    final signing = await File('android/release-signing.gradle.kts').readAsString();

    const applyLine = 'apply(from = rootProject.file("release-signing.gradle.kts"))';
    expect(appGradle, contains(applyLine));
    expect(hostGradle, contains(applyLine));
    expect(signing, contains('ANDROID_KEYSTORE_PATH'));
    expect(signing, contains('validateReleaseSigning()'));
    expect(signing, contains('getByName("release").signingConfig'));
    expect(appGradle, isNot(contains('ANDROID_KEYSTORE_PATH')));
    expect(hostGradle, isNot(contains('ANDROID_KEYSTORE_PATH')));
  });

  test('plugin host source keeps a bounded fail-closed transform contract', () async {
    final root = Directory('android/pluginhost/src/main/kotlin');
    final files = await root
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.kt'))
        .cast<File>()
        .toList();
    final source = (await Future.wait(files.map((file) => file.readAsString())))
        .join('\n');

    for (final state in <String>[
      'ready',
      'helper_missing',
      'no_free_slot',
      'transform_unsupported',
      'transform_failed',
      'package_unreadable',
      'missing_split',
      'unsupported_split_code',
      'unsupported_provider',
      'unsupported_service',
      'unsupported_receiver',
      'unsupported_multiprocess',
      'unsupported_abi',
      'unsupported_native_path_behavior',
      'source_signer_changed',
      'launch_failed',
      'operation_failed',
    ]) {
      expect(source, contains(state), reason: 'missing typed state $state');
    }

    expect(source, contains('setReadOnly()'));
    expect(source, contains('sourceSignerDigests'));
    expect(source, contains('sourceApkSha256'));
    expect(source, contains('TRANSFORM_SCHEMA_VERSION'));
    expect(source, isNot(contains('PathClassLoader')));
    expect(source, isNot(contains('ActivityThread')));
    expect(source, isNot(contains('Runtime.getRuntime().exec')));
  });
}
