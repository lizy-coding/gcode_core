import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

void main() {
  test(
      'invalid timing options fail consistently in direct and background loads',
      () async {
    final pipeline = GcodeReadlinePipeline(
      options: const GcodeReadlineOptions(
        timeOptions: GcodeTimeOptions(pulsePerMm: 0),
      ),
    );
    await expectLater(
      pipeline.load(const StringGcodeLineReader('G0 F600 X10')).toList(),
      throwsArgumentError,
    );
    await expectLater(
      pipeline.loadStringInBackground('G0 F600 X10').toList(),
      throwsArgumentError,
    );
    await expectLater(
      pipeline.loadFileInBackground('/not/a/gcode/file.nc').toList(),
      throwsArgumentError,
    );
  });

  test('CR LF and CRLF sources keep text file and background timing identical',
      () async {
    final directory = await Directory.systemTemp.createTemp('gcode_newlines');
    addTearDown(() => directory.delete(recursive: true));
    final pipeline = GcodeReadlinePipeline();
    for (final separator in ['\r', '\n', '\r\n']) {
      final source = ['G0 F600 X10', 'G0 X20', ''].join(separator);
      final file =
          await File('${directory.path}/source.nc').writeAsString(source);
      final direct = await pipeline.load(StringGcodeLineReader(source)).last;
      final background = await pipeline.loadStringInBackground(source).last;
      final fromFile = await pipeline.loadFileInBackground(file.path).last;
      expect(estimateGcodeTime(source).estimatedSeconds, 2);
      for (final snapshot in [direct, background, fromFile]) {
        expect(snapshot.linesRead, 2);
        expect(snapshot.estimatedSeconds, 2);
        expect(snapshot.errors, isEmpty);
        expect(snapshot.segments, hasLength(2));
        expect(snapshot.segments.last.start.x, 10);
        expect(snapshot.segments.last.end.x, 20);
      }
    }
  });

  test(
      'empty sources have zero lines and complete zero duration in every loader',
      () async {
    final directory = await Directory.systemTemp.createTemp('gcode_empty');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/empty.nc').writeAsString('');
    final pipeline = GcodeReadlinePipeline();
    for (final snapshot in [
      await pipeline.load(const StringGcodeLineReader('')).last,
      await pipeline.loadStringInBackground('').last,
      await pipeline.loadFileInBackground(file.path).last,
    ]) {
      expect(snapshot.stage, GcodeLoadStage.ready);
      expect(snapshot.linesRead, 0);
      expect(snapshot.estimatedSeconds, 0);
      expect(snapshot.segments, isEmpty);
    }
  });

  test(
    'all loading entrypoints expose the same complete source timing',
    () async {
      const source = 'G0 F600 X10 Y0\nG25 X20 Y0 T1000\nG4 T1000';
      final directory = await Directory.systemTemp.createTemp('gcode_timing');
      addTearDown(() => directory.delete(recursive: true));
      final file =
          await File('${directory.path}/test.nc').writeAsString(source);
      final pipeline = GcodeReadlinePipeline(
        options: const GcodeReadlineOptions(snapshotBatchSize: 1),
      );
      final direct =
          await pipeline.load(const StringGcodeLineReader(source)).toList();
      final background = await pipeline.loadStringInBackground(source).toList();
      final fromFile =
          await pipeline.loadFileInBackground('"${file.path}"').toList();
      for (final snapshots in [direct, background, fromFile]) {
        expect(snapshots.last.stage, GcodeLoadStage.ready);
        expect(snapshots.last.estimatedSeconds, closeTo(3.00145, 1e-10));
        expect(snapshots[1].estimatedSeconds, isNull);
        expect(snapshots[1].timeEstimate!.knownSeconds, 1);
        expect(
          snapshots.last.errors,
          hasLength(2),
          reason: 'timing does not broaden geometry support',
        );
      }
      expect(
        direct[1].timeEstimate!.knownSeconds,
        1,
        reason: 'later lines do not mutate earlier snapshots',
      );
    },
  );

  test(
    'successive loads reset timing and propagate configured feeds',
    () async {
      final pipeline = GcodeReadlinePipeline(
        options: const GcodeReadlineOptions(
          timeOptions: GcodeTimeOptions(rapidFeedRate: 600),
        ),
      );
      for (var i = 0; i < 2; i++) {
        final result =
            await pipeline.load(const StringGcodeLineReader('G0 X10')).last;
        expect(result.estimatedSeconds, 1);
      }
      final background = await pipeline.loadStringInBackground('G0 X10').last;
      expect(background.estimatedSeconds, 1);
    },
  );

  test(
    'unsupported and failed loads do not publish a complete duration',
    () async {
      final pipeline = GcodeReadlinePipeline();
      final invalid = await pipeline.loadStringInBackground('G2 X10 F600').last;
      expect(invalid.estimatedSeconds, isNull);
      expect(invalid.timeEstimate!.issues.single.lineNumber, 1);
      final missing =
          await pipeline.loadFileInBackground('/not/a/gcode/file.nc').last;
      expect(missing.stage, GcodeLoadStage.failed);
      expect(missing.estimatedSeconds, isNull);
    },
  );
}
