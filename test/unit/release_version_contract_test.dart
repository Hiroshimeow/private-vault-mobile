import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_release_version.dart' as release;

void main() {
  test('RC tag must match pubspec prerelease semantic version', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final versionMatch = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+-rc\.(\d+))(?:\+\d+)?\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(versionMatch, isNotNull);
    final version = versionMatch!.group(1)!;
    final rcNumber = int.parse(versionMatch.group(2)!);
    final mismatchedVersion = version.replaceFirst(
      '-rc.$rcNumber',
      '-rc.${rcNumber + 1}',
    );
    final stableVersion = version.substring(0, version.indexOf('-rc.'));

    expect(release.validateReleaseVersion('v$version', pubspec), isNull);
    expect(
      release.validateReleaseVersion('v$mismatchedVersion', pubspec),
      contains('Tag/pubspec mismatch'),
    );
    expect(
      release.validateReleaseVersion('v$stableVersion', pubspec),
      contains('Unsupported RC tag'),
    );
  });
}
