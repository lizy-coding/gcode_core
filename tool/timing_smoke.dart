import 'dart:convert';
import 'dart:io';

import 'package:gcode_core/gcode_time.dart' as gcode;

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _expectFailure<T>(Future<Object?> Function() operation) async {
  try {
    await operation();
  } catch (error) {
    _check(error is T, 'Expected $T, received ${error.runtimeType}');
    return;
  }
  throw StateError('Expected $T instead of a successful partial estimate');
}

/// Runs on the ordinary Dart VM; importing Flutter or dart:ui breaks this smoke.
Future<void> main() async {
  const source = 'G0 F600 X10\nG25 X20 T1000\nG4 T1000';
  const expectedSeconds = 3.00145;
  void checkEstimate(gcode.GcodeTimeEstimate estimate) {
    _check(estimate.isComplete, 'Expected complete timing');
    _check(
      (estimate.estimatedSeconds! - expectedSeconds).abs() < 1e-10,
      'Unexpected duration: ${estimate.estimatedSeconds}',
    );
  }

  checkEstimate(gcode.estimateGcodeTime(source));
  checkEstimate(await gcode.estimateGcodeStreamTime(
    Stream.fromIterable(source.split('\n')),
  ));
  final incremental = gcode.GcodeTimeEstimator();
  for (final line in source.split('\n')) {
    incremental.append(line);
  }
  checkEstimate(incremental.snapshot);

  final directory = await Directory.systemTemp.createTemp('gcode_time_smoke_');
  try {
    final file =
        await File('${directory.path}/timing source.nc').writeAsString(source);
    checkEstimate(await gcode.estimateGcodeFileTime(file.uri.toString()));
    await _expectFailure<FileSystemException>(
      () => gcode.estimateGcodeFileTime('${directory.path}/missing.nc'),
    );
    final invalidUtf8 =
        await File('${directory.path}/invalid.nc').writeAsBytes([0xff]);
    await _expectFailure<FormatException>(
      () => gcode.estimateGcodeFileTime(invalidUtf8.path),
    );
    Stream<String> failingLines() async* {
      yield 'G0 F600 X10';
      throw StateError('source read failed');
    }

    await _expectFailure<StateError>(
      () => gcode.estimateGcodeStreamTime(failingLines()),
    );
    final incomplete = gcode.estimateGcodeTime('G0 F600 X10\nG2 X20');
    _check(!incomplete.isComplete, 'Unsupported motion must be incomplete');
    _check(incomplete.estimatedSeconds == null, 'Partial total must be hidden');
  } finally {
    await directory.delete(recursive: true);
  }
  stdout.writeln(jsonEncode({
    'status': 'pass',
    'runtime': Platform.version,
    'checks': [
      'text',
      'stream',
      'incremental',
      'file URI',
      'missing file',
      'invalid UTF-8',
      'upstream read failure',
      'incomplete timing',
    ],
  }));
}
