import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android disables backup and cleartext traffic', () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  test(
    'secret production surfaces do not write plaintext to clipboard',
    () async {
      final secretFiles = await Directory('lib/features/vault')
          .list(recursive: true)
          .where((entry) => entry is File && entry.path.endsWith('.dart'))
          .cast<File>()
          .toList();

      for (final file in secretFiles) {
        final source = await file.readAsString();
        expect(
          source,
          isNot(contains('Clipboard.setData')),
          reason: '${file.path} must not copy decrypted vault content',
        );
      }
    },
  );

  test('backup policy excludes all application data', () async {
    final backup = await File('android/app/src/main/res/xml/backup_rules.xml')
        .readAsString();
    final extraction = await File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsString();
    expect(backup, contains('exclude domain="root" path="."'));
    expect(extraction, contains('disableIfNoEncryptionCapabilities="true"'));
  });

  test(
    'Android release signing never falls back to debug credentials',
    () async {
      final gradle = await File('android/app/build.gradle.kts').readAsString();
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
      expect(gradle, contains('signingConfigs.getByName("release")'));
      expect(gradle, contains('ANDROID_KEYSTORE_PATH'));
      expect(gradle, contains('ANDROID_KEYSTORE_PASSWORD'));
      expect(gradle, contains('ANDROID_KEY_ALIAS'));
      expect(gradle, contains('ANDROID_KEY_PASSWORD'));
      expect(gradle, contains('Release signing is not configured.'));
      expect(gradle, contains('setOf("assemble", "build", "bundle")'));
      expect(
        gradle,
        contains('setOf("assembleRelease", "bundleRelease", "installRelease")'),
      );
      expect(
        gradle,
        isNot(contains('selector.contains("release", ignoreCase = true)')),
      );
      expect(gradle, contains("taskName.substringAfterLast(':')"));
      expect(gradle, contains("taskName.lastIndexOf(':')"));
      expect(gradle, contains('requestedProjectPath == project.path'));
      expect(
        gradle,
        contains(
          'gradle.startParameter.taskNames.any(::releaseSigningTaskRequested)',
        ),
      );
    },
  );

  test('README documents fail-closed Android release signing', () async {
    final readme = await File('README.md').readAsString();
    expect(
      readme,
      isNot(contains('release configuration currently uses debug signing')),
    );
    expect(
      readme,
      contains('Android release builds never fall back to debug signing'),
    );
    expect(readme, contains('android/key.properties'));
    expect(readme, contains('ANDROID_KEYSTORE_PATH'));
    expect(readme, contains('Missing signing inputs fail closed'));
  });

  test('CI treats unsigned release as an expected signing failure', () async {
    final workflow = await File('.github/workflows/ci.yml').readAsString();
    expect(
      workflow,
      contains('Verify release signing fails closed without secrets'),
    );
    expect(workflow, contains(r'test "$status" -ne 0'));
    expect(workflow, contains('Release signing is not configured.'));
    expect(
      workflow,
      contains('Verify aggregate Android build fails closed without secrets'),
    );
    expect(workflow, contains('./gradlew :app:assemble --dry-run'));
    expect(
      workflow,
      contains(
        'Verify release-variant development tasks do not require signing',
      ),
    );
    expect(workflow, contains('./gradlew :app:testReleaseUnitTest --dry-run'));
    expect(workflow, contains('./gradlew :app:compileReleaseKotlin --dry-run'));
    expect(
      workflow,
      contains('Verify unrelated modules do not require app signing'),
    );
    expect(
      workflow,
      contains('./gradlew :android_file_picker:build --dry-run'),
    );
    expect(
      workflow,
      contains('./gradlew :android_file_picker:assembleRelease --dry-run'),
    );
    expect(workflow, isNot(contains('Build release APK smoke')));
  });
}
