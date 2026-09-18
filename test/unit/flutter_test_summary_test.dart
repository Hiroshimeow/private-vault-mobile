import 'package:flutter_test/flutter_test.dart';

import '../../tool/summarize_flutter_test.dart';

void main() {
  test('summarizes testDone events and ignores protocol array events', () {
    final summary = summarizeFlutterMachineLines([
      '{"type":"start"}',
      '[{"event":"test.startedProcess","params":{"vmServiceUri":"http://x"}}]',
      '{"type":"testDone","hidden":true,"result":"success","skipped":false}',
      '{"type":"testDone","hidden":false,"result":"success","skipped":false}',
      '{"type":"testDone","hidden":false,"result":"success","skipped":true}',
      '{"type":"testDone","hidden":false,"result":"failure","skipped":false}',
    ]);

    expect(summary.passed, 1);
    expect(summary.failed, 1);
    expect(summary.skipped, 1);
  });
}
