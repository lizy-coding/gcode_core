import 'dart:convert';
import 'dart:io';
import 'package:gcode_core/src/application/gcode_readline_pipeline.dart';
import 'package:gcode_core/src/data/readers/string_gcode_line_reader.dart';

Future<void> main() async {
  final source = List.generate(100000, (i) => 'G1 X${i + 1} F600').join('\n');
  for (final limit in <int?>[null, 2000]) {
    final watch = Stopwatch()..start();
    var snapshots = 0, references = 0;
    await for (final s in GcodeReadlinePipeline(
            options: GcodeReadlineOptions(
                snapshotBatchSize: 2000, previewLimit: limit))
        .load(StringGcodeLineReader(source))) {
      snapshots++;
      references += s.commands.length + s.segments.length + s.errors.length;
    }
    print(jsonEncode({
      'previewLimit': limit,
      'milliseconds': watch.elapsedMilliseconds,
      'snapshots': snapshots,
      'publishedReferences': references,
      'rss': ProcessInfo.currentRss
    }));
  }
}
