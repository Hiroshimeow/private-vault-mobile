import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<String> _readIfExists(String path) async {
  final file = File(path);
  return file.existsSync() ? file.readAsString() : '';
}

void main() {
  test('Apps routes clone control through the virtual-container backend', () async {
    final app = await File('lib/app/private_vault_app.dart').readAsString();
    final main = await File('lib/main.dart').readAsString();
    final settings = await File('android/settings.gradle.kts').readAsString();
    final appGradle = await File('android/app/build.gradle.kts').readAsString();
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(app, contains('CloneProfileHome('));
    expect(app, contains('widget.cloneProfileClient'));
    expect(main, contains('PlatformCloneProfileClient()'));
    expect(settings, contains('include(":clonehost")'));
    expect(
      manifest,
      contains('io.hiroshimeow.private_vault.permission.CLONE_CONTROL'),
    );
    expect(
      appGradle,
      isNot(contains('dev.rikka.shizuku')),
    );
  });

  test('clone backend has no privileged, spoofing, or direct-launch fallback', () async {
    const oldBridge =
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/CloneProfileBridge.kt';
    const oldService =
        'android/app/src/main/java/io/hiroshimeow/private_vault_mobile/CloneProfileUserService.java';
    const newBridge =
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/VirtualCloneBridge.kt';

    expect(File(oldBridge).existsSync(), isFalse);
    expect(File(oldService).existsSync(), isFalse);
    expect(File(newBridge).existsSync(), isTrue);
    expect(Directory('android/clonehost').existsSync(), isTrue);

    final sources = <String>[
      await _readIfExists(newBridge),
      await _readIfExists('android/app/build.gradle.kts'),
      await _readIfExists('android/clonehost/build.gradle.kts'),
      await _readIfExists('android/clonehost/src/main/AndroidManifest.xml'),
    ].join('\n');
    final banned = <String>[
      'dev.rikka.shizuku',
      'Shizuku',
      'profile.CLONE',
      'android.os.usertype.profile.CLONE',
      'Pine',
      'AntiDetection',
      'IdentitySpoofing',
      'fake location',
      'SafetyNet',
      'PlayIntegrity',
      'signature spoof',
      'getLaunchIntentForPackage',
      'pm create-user',
      'pm install-existing',
    ];
    for (final token in banned) {
      expect(sources, isNot(contains(token)), reason: 'banned token: $token');
    }
  });

  test('clone hosts are fixed UID-isolated slots behind signature permission', () async {
    final gradle = await _readIfExists('android/clonehost/build.gradle.kts');
    final manifest = await _readIfExists(
      'android/clonehost/src/main/AndroidManifest.xml',
    );

    expect(
      gradle,
      contains('io.hiroshimeow.private_vault.clonehost.slot0'),
    );
    expect(
      gradle,
      contains('io.hiroshimeow.private_vault.clonehost.slot1'),
    );
    expect(
      manifest,
      contains('io.hiroshimeow.private_vault.permission.CLONE_CONTROL'),
    );
    expect(manifest, contains('.control'));
  });

  test('cross-slot instrumentation is owned by the permission-holding Vault app', () async {
    const appHarness =
        'android/app/src/androidTest/kotlin/io/hiroshimeow/private_vault_mobile/CloneRuntimeInstrumentedTest.kt';
    const hostHarness =
        'android/clonehost/src/androidTest/kotlin/io/hiroshimeow/private_vault_clonehost/CloneRuntimeInstrumentedTest.kt';
    final appGradle = await _readIfExists('android/app/build.gradle.kts');
    final appManifest = await _readIfExists(
      'android/app/src/main/AndroidManifest.xml',
    );

    expect(File(appHarness).existsSync(), isTrue);
    expect(File(hostHarness).existsSync(), isFalse);
    expect(appGradle, contains('androidx.test.runner.AndroidJUnitRunner'));
    expect(appManifest, contains(
      '<uses-permission android:name="io.hiroshimeow.private_vault.permission.CLONE_CONTROL" />',
    ));
  });
}
