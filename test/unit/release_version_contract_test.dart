import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_release_version.dart' as release;

void main() {
  test('RC tag must match pubspec prerelease semantic version', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('version: 1.0.0-rc.1+1'));

    expect(release.validateReleaseVersion('v1.0.0-rc.1', pubspec), isNull);
    expect(
      release.validateReleaseVersion('v1.0.0-rc.2', 'version: 1.0.0-rc.1+1'),
      contains('Tag/pubspec mismatch'),
    );
    expect(
      release.validateReleaseVersion('v1.0.0', pubspec),
      contains('Unsupported RC tag'),
    );
  });
}
