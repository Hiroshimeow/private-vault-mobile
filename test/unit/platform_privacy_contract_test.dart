import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android secret surfaces enable FLAG_SECURE', () async {
    final source = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/MainActivity.kt',
    ).readAsString();

    expect(source, contains('FLAG_SECURE'));
    expect(source, contains('FlutterFragmentActivity'));
  });

  test('Android predeclares calculator and notes launcher aliases', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final activity = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/MainActivity.kt',
    ).readAsString();

    expect(manifest, contains('.CalculatorAlias'));
    expect(manifest, contains('.NotesAlias'));
    expect(activity, contains('MethodChannel'));
    expect(activity, contains('setComponentEnabledSetting'));
  });

  test('iOS biometric usage string is declared', () async {
    final plist = await File('ios/Runner/Info.plist').readAsString();

    expect(plist, contains('NSFaceIDUsageDescription'));
    expect(plist, contains('NSCameraUsageDescription'));
  });

  test('iOS predeclares an alternate icon and native switch bridge', () async {
    final project = await File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsString();
    final delegate = await File('ios/Runner/AppDelegate.swift').readAsString();

    expect(
      await Directory('ios/Runner/Assets.xcassets/NotesIcon.appiconset')
          .exists(),
      isTrue,
    );
    expect(project, contains('ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES'));
    expect(delegate, contains('setAlternateIconName'));
    expect(delegate, contains('MethodChannel'));
  });

  test('iOS scene installs an app-switcher privacy cover', () async {
    final source = await File('ios/Runner/SceneDelegate.swift').readAsString();

    expect(source, contains('privacyCover'));
    expect(source, contains('sceneWillResignActive'));
    expect(source, contains('sceneDidBecomeActive'));
  });
}
