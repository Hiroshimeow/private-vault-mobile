import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Dart source contains no direct secret logging', () async {
    final sources = await Directory('lib')
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.dart'))
        .cast<File>()
        .toList();

    final forbiddenLogging = <RegExp>[
      RegExp(r'\bprint\s*\('),
      RegExp(r'\bdebugPrint\s*\('),
      RegExp(r'\blog\s*\('),
    ];
    const syntheticSecrets = <String>[
      'fixture-secret-value',
      'synthetic secret',
      'picked-secret',
      'downloaded-fixture',
      'Synthetic protected note',
    ];

    for (final source in sources) {
      final text = await source.readAsString();
      for (final pattern in forbiddenLogging) {
        expect(
          pattern.hasMatch(text),
          isFalse,
          reason:
              'Direct logging is forbidden in production source: ${source.path}',
        );
      }
      for (final secret in syntheticSecrets) {
        expect(
          text.contains(secret),
          isFalse,
          reason:
              'Synthetic secret fixture leaked into production source: ${source.path}',
        );
      }
    }
  });
}
