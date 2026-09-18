import 'dart:io';

String? validateReleaseVersion(String tag, String pubspec) {
  final match = RegExp(r'^v(\d+\.\d+\.\d+-rc\.\d+)$').firstMatch(tag);
  if (match == null) {
    return 'Unsupported RC tag: $tag';
  }

  final versionMatch = RegExp(
    r'^version:\s*([^\s+]+)(?:\+\S+)?\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (versionMatch == null) {
    return 'pubspec.yaml version was not found.';
  }

  final expected = match.group(1)!;
  final actual = versionMatch.group(1)!;
  if (actual != expected) {
    return 'Tag/pubspec mismatch: tag=$expected pubspec=$actual';
  }

  return null;
}

void main(List<String> args) {
  final tag = args.isNotEmpty
      ? args.first
      : Platform.environment['GITHUB_REF_NAME'];
  if (tag == null || tag.isEmpty) {
    stderr.writeln('Release tag is required via argv[0] or GITHUB_REF_NAME.');
    exitCode = 2;
    return;
  }

  final pubspec = File('pubspec.yaml').readAsStringSync();
  final error = validateReleaseVersion(tag, pubspec);
  if (error != null) {
    stderr.writeln(error);
    exitCode = error.startsWith('Tag/pubspec mismatch:') ? 1 : 2;
    return;
  }

  final version = RegExp(
    r'^version:\s*([^\s+]+)',
    multiLine: true,
  ).firstMatch(pubspec)!.group(1)!;
  stdout.writeln('Release version contract OK: $tag <-> $version');
}
