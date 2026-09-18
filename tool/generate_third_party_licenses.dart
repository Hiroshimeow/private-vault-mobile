import 'dart:convert';
import 'dart:io';

const _licenseNames = <String>[
  'LICENSE',
  'LICENSE.txt',
  'LICENSE.md',
  'COPYING',
  'COPYING.txt',
];

void main(List<String> args) {
  final outputPath = args.isNotEmpty ? args.first : 'THIRD_PARTY_LICENSES.txt';
  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) {
    stderr.writeln(
      '.dart_tool/package_config.json is missing; run flutter pub get first.',
    );
    exitCode = 2;
    return;
  }

  final decoded = jsonDecode(configFile.readAsStringSync());
  if (decoded is! Map<String, dynamic> || decoded['packages'] is! List) {
    stderr.writeln('Invalid package_config.json.');
    exitCode = 2;
    return;
  }

  final packages =
      (decoded['packages'] as List)
          .whereType<Map<String, dynamic>>()
          .where((package) => package['name'] != 'private_vault_mobile')
          .toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  final missing = <String>[];
  final output = StringBuffer(
    '# Third-party license inventory\n'
    '# Generated from the resolved Dart/Flutter package graph.\n\n',
  );

  for (final package in packages) {
    final name = package['name'];
    final rootUriRaw = package['rootUri'];
    if (name is! String || rootUriRaw is! String) {
      stderr.writeln('Invalid package entry: $package');
      exitCode = 2;
      return;
    }

    final rootUri = Uri.parse(rootUriRaw);
    final resolvedRoot = rootUri.hasScheme
        ? rootUri
        : configFile.parent.uri.resolveUri(rootUri);
    final root = Directory.fromUri(resolvedRoot);
    final version = _readVersion(root) ?? 'unknown';
    final license = _findLicense(root);

    output.writeln('===== $name $version =====');
    if (license == null) {
      missing.add(name);
      output.writeln('[LICENSE FILE NOT FOUND]');
    } else {
      output.writeln(license.readAsStringSync().trim());
    }
    output.writeln();
  }

  File(outputPath).writeAsStringSync(output.toString(), flush: true);

  if (missing.isNotEmpty) {
    stderr.writeln('Missing license text for: ${missing.join(', ')}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Wrote ${packages.length} package licenses to $outputPath.');
}

String? _readVersion(Directory root) {
  final pubspec = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
  if (!pubspec.existsSync()) return null;
  return RegExp(
    r'^version:\s*([^\s]+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync())?.group(1);
}

File? _findLicense(Directory root) {
  var current = root;
  for (var depth = 0; depth < 5; depth++) {
    for (final name in _licenseNames) {
      final candidate = File('${current.path}${Platform.pathSeparator}$name');
      if (candidate.existsSync()) return candidate;
    }

    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return null;
}
