import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart' as core;
import 'package:gcode_core/gcode_time.dart' as time;

void main() {
  test('both public entrypoints expose text, stream and incremental APIs',
      () async {
    const source = 'G0 F600 X10\nG25 X20 T1000\nG4 T1000';
    expect(core.estimateGcodeTime(source).estimatedSeconds,
        closeTo(3.00145, 1e-10));
    expect(time.estimateGcodeTime(source).estimatedSeconds,
        closeTo(3.00145, 1e-10));
    final streamed = await core
        .estimateGcodeStreamTime(Stream.fromIterable(source.split('\n')));
    expect(streamed.estimatedSeconds, closeTo(3.00145, 1e-10));
    final incremental = time.GcodeTimeEstimator();
    for (final line in source.split('\n')) {
      incremental.append(line);
    }
    expect(incremental.snapshot.estimatedSeconds, streamed.estimatedSeconds);
  });

  test('file API handles file URIs and forwarded calibration', () async {
    final directory = await Directory.systemTemp.createTemp('gcode_api');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/timing file.nc')
        .writeAsString('G0 X10\nG102 O0 H0 N1000 F1000\nG0 Y0');
    const options = time.GcodeTimeOptions(rapidFeedRate: 600, pulsePerMm: 500);
    final result =
        await time.estimateGcodeFileTime(file.uri.toString(), options: options);
    expect(result.estimatedSeconds, closeTo(2.4, 1e-10));
    expect(
        (await core.estimateGcodeFileTime('"${file.path}"', options: options))
            .estimatedSeconds,
        result.estimatedSeconds);
  });

  test('invalid source retains diagnostics through public stream API',
      () async {
    final result = await time.estimateGcodeStreamTime(
        Stream.fromIterable(['G0 F600 X10', 'G2 X20']));
    expect(result.estimatedSeconds, isNull);
    expect(result.knownSeconds, 1);
    expect(result.issues.single.lineNumber, 2);
    expect(
        (await time.estimateGcodeStreamTime(const Stream.empty()))
            .estimatedSeconds,
        0);
  });

  test('read errors and stream failures are not successful partial totals',
      () async {
    final directory = await Directory.systemTemp.createTemp('gcode_api_errors');
    addTearDown(() => directory.delete(recursive: true));
    await expectLater(
        time.estimateGcodeFileTime('${directory.path}/missing.nc'),
        throwsA(isA<FileSystemException>()));
    final corrupt = await File('${directory.path}/bad.nc').writeAsBytes([0xff]);
    await expectLater(time.estimateGcodeFileTime(corrupt.path),
        throwsA(isA<FormatException>()));
    Stream<String> failing() async* {
      yield 'G0 F600 X10';
      throw StateError('producer failed');
    }

    await expectLater(
        time.estimateGcodeStreamTime(failing()), throwsStateError);
    await expectLater(
        time.estimateGcodeStreamTime(Stream.value('G0 X10'),
            options: const time.GcodeTimeOptions(pulsePerMm: 0)),
        throwsArgumentError);
  });

  test('stream API subscribes once and cancels after a producer error',
      () async {
    var subscriptions = 0;
    var cancellations = 0;
    late StreamController<String> source;
    source = StreamController<String>(
      onListen: () {
        subscriptions++;
        source.add('G0 F600 X10');
        source.addError(StateError('source failed'));
        source.add('G0 X20');
      },
      onCancel: () => cancellations++,
    );
    addTearDown(source.close);

    await expectLater(
      time.estimateGcodeStreamTime(source.stream),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'source failed',
      )),
    );
    expect(subscriptions, 1);
    expect(cancellations, 1);
  });
}
