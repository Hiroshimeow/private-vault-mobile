import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hosted emulator workflow runs the RC integration test', () async {
    final workflow = await File('.github/workflows/android-integration.yml')
        .readAsString();
    expect(workflow, contains('reactivecircus/android-emulator-runner@v2'));
    expect(workflow, contains('integration_test/private_vault_rc_test.dart'));
    expect(workflow, contains('flutter-version: 3.47.4'));
    expect(workflow, contains('flutter pub get --enforce-lockfile'));
    expect(
      RegExp(r'run:\s*flutter pub get\s*$', multiLine: true).hasMatch(workflow),
      isFalse,
    );
  });

  test(
    'RC release workflow is prerelease-only and checks source version',
    () async {
      final workflow = await File('.github/workflows/release-rc.yml')
          .readAsString();
      expect(workflow, contains('v*.*.*-rc.*'));
      expect(workflow, contains('dart run tool/check_release_version.dart'));
      expect(workflow, contains('prerelease: true'));
      expect(workflow, contains('DEBUG-TEST-ONLY'));
      expect(workflow, contains('sha256sum'));
      expect(
        workflow,
        contains(
          'google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@v2.6.0',
        ),
      );
      expect(workflow, contains('tool/generate_third_party_licenses.dart'));
      expect(workflow, contains('THIRD_PARTY_LICENSES.txt'));
      expect(workflow, contains('flutter-test.jsonl'));
      expect(workflow, contains('test-summary.txt'));
      expect(workflow, contains('dart run tool/summarize_flutter_test.dart'));
      expect(
        RegExp(r'flutter pub get --enforce-lockfile')
            .allMatches(workflow)
            .length,
        4,
      );
      expect(
        RegExp(
          r'run:\s*flutter pub get\s*$',
          multiLine: true,
        ).hasMatch(workflow),
        isFalse,
      );
      expect(workflow, contains('permissions:\n  contents: read'));
      expect(
        workflow,
        contains(
          'publish:\n    needs: [quality, vulnerability, sast, integration, android, ios]\n    permissions:\n      contents: write',
        ),
      );
    },
  );
}
