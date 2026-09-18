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

  test('backup policy excludes all application data', () async {
    final backup = await File('android/app/src/main/res/xml/backup_rules.xml')
        .readAsString();
    final extraction = await File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsString();
    expect(backup, contains('exclude domain="root" path="."'));
    expect(extraction, contains('disableIfNoEncryptionCapabilities="true"'));
  });
}
