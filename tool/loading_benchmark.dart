import 'dart:convert';
import 'dart:io';

import 'package:gcode_core/gcode_time.dart';
import 'package:gcode_core/src/application/gcode_readline_pipeline.dart';
import 'package:gcode_core/src/data/readers/gcode_line_reader.dart';
import 'package:gcode_core/src/domain/gcode_line_record.dart';
import 'package:gcode_core/src/domain/gcode_load_stage.dart';

String _sourceLine(int index) => 'G1 X${index + 1} F600';

class _GeneratedLineReader implements GcodeLineReader {
  const _GeneratedLineReader(this.lines);
  final int lines;

  @override
  Stream<GcodeLineRecord> readLines() async* {
    var offset = 0;
    for (var index = 0; index < lines; index++) {
      final source = _sourceLine(index);
      yield GcodeLineRecord(
        lineNumber: index + 1,
        rawLine: source,
        byteOffset: offset,
      );
      offset += source.length + 1; // The generated fixture is ASCII plus LF.
    }
  }
}

Future<File> _writeFixture(Directory directory, int lines) async {
  final file = File('${directory.path}/source.nc');
  final sink = file.openWrite();
  try {
    for (var index = 0; index < lines; index++) {
      sink.writeln(_sourceLine(index));
      if ((index + 1) % 1000 == 0) await sink.flush();
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  return file;
}

Map<String, String> _parseArguments(List<String> arguments) {
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) throw ArgumentError('Unexpected $argument');
    final equals = argument.indexOf('=');
    if (equals != -1) {
      values[argument.substring(2, equals)] = argument.substring(equals + 1);
    } else {
      if (++index >= arguments.length) {
        throw ArgumentError('Missing value for $argument');
      }
      values[argument.substring(2)] = arguments[index];
    }
  }
  if (values.keys
      .any((key) => !{'lines', 'mode', 'batch-size'}.contains(key))) {
    throw ArgumentError('Use --lines, --mode and optional --batch-size');
  }
  return values;
}

/// Measures loading on the Dart VM without creating Flutter/GPU resources.
///
/// Snapshot element counts estimate cumulative shallow list entries copied by
/// the current full-snapshot implementation. They are neither allocated bytes
/// nor GPU memory. Background transfer copies object graphs as well; only list
/// element counts, not object graph sizes, are estimated here.
Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final lines = int.tryParse(options['lines'] ?? '') ?? 0;
  final mode = options['mode'];
  final batchSize = int.tryParse(options['batch-size'] ?? '200') ?? 0;
  if (lines <= 0 ||
      batchSize <= 0 ||
      !{'timing-only', 'direct-snapshot', 'background-snapshot'}
          .contains(mode)) {
    throw ArgumentError('Use --lines POSITIVE --mode '
        'timing-only|direct-snapshot|background-snapshot '
        '[--batch-size POSITIVE]');
  }
  final setup = Stopwatch()..start();
  Directory? directory;
  File? fixture;
  if (mode == 'background-snapshot') {
    directory = await Directory.systemTemp.createTemp('gcode_benchmark_');
    fixture = await _writeFixture(directory, lines);
  }
  setup.stop();
  final startRss = ProcessInfo.currentRss;
  final stopwatch = Stopwatch()..start();
  var linesRead = 0;
  var commands = 0;
  var segments = 0;
  var snapshots = 0;
  var estimatedElementCopies = 0;
  var lastProgressMs = 0;
  double? seconds;

  Map<String, Object?> metrics(String status) => {
        'status': status,
        'mode': mode,
        'requestedLines': lines,
        'lines': linesRead,
        'commands': commands,
        'segments': segments,
        'snapshots': snapshots,
        'snapshotBatchSize': batchSize,
        'setupElapsedMs': setup.elapsedMicroseconds / 1000,
        'elapsedMs': stopwatch.elapsedMicroseconds / 1000,
        'currentRssBytes': ProcessInfo.currentRss,
        'peakProcessRssBytes': ProcessInfo.maxRss,
        'rssBytesAtMeasuredStart': startRss,
        'estimatedFullSnapshotElementsCopied': estimatedElementCopies,
        'estimatedSnapshotElementsSentBetweenIsolates':
            mode == 'background-snapshot' ? estimatedElementCopies : 0,
        'estimatedSeconds': seconds,
        'fixture': mode == 'background-snapshot'
            ? 'generated UTF-8 file; setup excluded from elapsedMs'
            : 'generated source stream; no retained source string',
        'metricScope': 'Dart process RSS and cumulative list elements; no GPU',
        'runtime': Platform.version,
      };

  void progress() {
    if (stopwatch.elapsedMilliseconds - lastProgressMs >= 1000) {
      lastProgressMs = stopwatch.elapsedMilliseconds;
      stdout.writeln(jsonEncode(metrics('progress')));
    }
  }

  try {
    if (mode == 'timing-only') {
      Stream<String> source() async* {
        for (var index = 0; index < lines; index++) {
          linesRead = index + 1;
          yield _sourceLine(index);
          progress();
        }
      }

      final estimate = await estimateGcodeStreamTime(source());
      seconds = estimate.estimatedSeconds;
      snapshots = 1;
      estimatedElementCopies = estimate.issues.length;
    } else {
      final pipeline = GcodeReadlinePipeline(
        options: GcodeReadlineOptions(snapshotBatchSize: batchSize),
      );
      final stream = mode == 'background-snapshot'
          ? pipeline.loadFileInBackground(fixture!.path)
          : pipeline.load(_GeneratedLineReader(lines));
      var ready = false;
      await for (final snapshot in stream) {
        linesRead = snapshot.linesRead;
        commands = snapshot.commands.length;
        segments = snapshot.segments.length;
        snapshots++;
        estimatedElementCopies += commands +
            segments +
            snapshot.errors.length +
            (snapshot.timeEstimate?.issues.length ?? 0);
        seconds = snapshot.estimatedSeconds;
        if (snapshot.stage == GcodeLoadStage.failed) {
          throw StateError(snapshot.message);
        }
        ready = snapshot.stage == GcodeLoadStage.ready;
        progress();
      }
      if (!ready || commands != lines || segments != lines) {
        throw StateError('Incomplete pipeline or unexpected geometry counts');
      }
    }
    if (linesRead != lines ||
        seconds == null ||
        (seconds - lines / 10).abs() > 1e-4) {
      throw StateError('Unexpected timing or line count: $linesRead, $seconds');
    }
    stopwatch.stop();
    stdout.writeln(jsonEncode(metrics('pass')));
  } catch (error) {
    stopwatch.stop();
    stdout.writeln(jsonEncode({...metrics('error'), 'error': '$error'}));
    exitCode = 1;
  } finally {
    await directory?.delete(recursive: true);
  }
}
