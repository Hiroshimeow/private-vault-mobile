import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CI includes a real Semgrep SAST gate with repository rules', () async {
    final workflow = File('.github/workflows/sast.yml');
    final rules = File('.semgrep.yml');

    expect(await workflow.exists(), isTrue);
    expect(await rules.exists(), isTrue);

    final workflowText = await workflow.readAsString();
    final rulesText = await rules.readAsString();

    expect(workflowText, contains('semgrep==1.177.0'));
    expect(workflowText, contains('semgrep scan'));
    expect(workflowText, contains('--config=p/security-audit'));
    expect(workflowText, contains('--config=.semgrep.yml'));
    expect(workflowText, contains('--severity ERROR'));
    expect(workflowText, contains('--error'));

    expect(rulesText, contains('languages: [dart]'));
    expect(rulesText, contains('languages: [kotlin]'));
    expect(rulesText, contains('languages: [swift]'));
  });
}
