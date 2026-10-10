import 'dart:convert';
import 'dart:io';

class FlutterTestSummary {
  const FlutterTestSummary({
    required this.passed,
    required this.failed,
    required this.skipped,
  });

  final int passed;
  final int failed;
  final int skipped;

  String format(String label) =>
      '$label: passed=$passed failed=$failed skipped=$skipped';
}

FlutterTestSummary summarizeFlutterMachineLines(Iterable<String> lines) {
  var passed = 0;
  var failed = 0;
  var skipped = 0;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('{') && !line.startsWith('[')) continue;
    final event = jsonDecode(line);
    if (event is! Map<String, dynamic>) continue;
    if (event['type'] != 'testDone' || event['hidden'] == true) continue;

    if (event['skipped'] == true) {
      skipped++;
    } else if (event['result'] == 'success') {
      passed++;
    } else {
      failed++;
    }
  }

  return FlutterTestSummary(passed: passed, failed: failed, skipped: skipped);
}

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln(
      'Usage: dart run tool/summarize_flutter_test.dart '
      '<machine-jsonl> <summary-output> <label>',
    );
    exitCode = 2;
    return;
  }

  final input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('Machine test output not found: ${args[0]}');
    exitCode = 2;
    return;
  }

  final summary = summarizeFlutterMachineLines(input.readAsLinesSync());
  final line = summary.format(args.sublist(2).join(' '));
  File(args[1]).writeAsStringSync('$line\n', flush: true);
  stdout.writeln(line);

  if (summary.failed > 0) {
    exitCode = 1;
  }
}
