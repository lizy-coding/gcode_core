import 'dart:convert';
import 'package:gcode_core/src/application/gcode_readline_pipeline.dart';
import 'package:gcode_core/src/data/readers/string_gcode_line_reader.dart';

Future<void> main() async {
  final source = List.filled(10000, 'G2 X1').join('\n');
  final watch = Stopwatch()..start();
  var parserReferences = 0, timingReferences = 0, snapshots = 0;
  await for (final snapshot in GcodeReadlinePipeline(
    options:
        const GcodeReadlineOptions(snapshotBatchSize: 100, previewLimit: 100),
  ).load(StringGcodeLineReader(source))) {
    parserReferences += snapshot.errors.length;
    timingReferences += snapshot.timeEstimate?.issues.length ?? 0;
    snapshots++;
  }
  print(jsonEncode({
    'lines': 10000,
    'snapshots': snapshots,
    'publishedParserErrors': parserReferences,
    'publishedTimingIssues': timingReferences,
    'milliseconds': watch.elapsedMilliseconds,
  }));
}
