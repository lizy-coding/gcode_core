import 'dart:collection';

import 'package:example/main.dart';
import 'package:example/src/widgets/gcode_canvas_panel.dart';
import 'package:flutter/material.dart';
import 'package:gcode_core/gcode_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GcodeReadlinePipeline smoke test', (WidgetTester tester) async {
    final pipeline = GcodeReadlinePipeline(
      options: const GcodeReadlineOptions(snapshotBatchSize: 2),
    );

    final snapshots = await pipeline
        .load(const StringGcodeLineReader('G0 X0 Y0\nG1 X10 Y0\n'))
        .toList();

    expect(snapshots.isNotEmpty, true);
    final last = snapshots.last;
    expect(last.stage, GcodeLoadStage.ready);
    expect(last.commands.length, 2);
  });

  testWidgets('example fits a narrow Android-sized viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const GcodeCoreExampleApp());
    await tester.pump();

    expect(find.text('G-code'), findsOneWidget);
    expect(find.byTooltip('示例数据'), findsOneWidget);
    expect(find.byTooltip('选择 G-code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'playback keeps the loaded path statistics without rescanning it',
    (tester) async {
      final parsed = GcodeParser().parse('G0 X10\nG1 X20');
      final segments = _ReadTrackingSegments(
        ToolpathBuilder.build(parsed.commands),
      );
      final snapshot = GcodeLoadSnapshot(
        stage: GcodeLoadStage.ready,
        commands: parsed.commands,
        errors: parsed.errors,
        segments: segments,
        linesRead: 2,
      );
      Widget panel(double progress, {GcodeLoadSnapshot? replacement}) =>
          MaterialApp(
            home: Scaffold(
              body: GcodeCanvasPanel(
                snapshot: replacement ?? snapshot,
                parsing: false,
                progress: progress,
                isPlaying: false,
                speedMultiplier: 1,
                onPlay: () {},
                onPause: () {},
                onReset: () {},
                onSeek: (_) {},
                onSpeedChange: (_) {},
              ),
            ),
          );
      await tester.pumpWidget(panel(0.25));
      await tester.pump();
      expect(find.text('主线段 G1: 1'), findsOneWidget);
      final reads = segments.reads;

      await tester.pumpWidget(panel(0.75));

      expect(segments.reads, reads);
      expect(find.text('主线段 G1: 1'), findsOneWidget);

      final rapid = GcodeParser().parse('G0 X10\nG0 X20');
      await tester.pumpWidget(
        panel(
          0.75,
          replacement: GcodeLoadSnapshot(
            stage: GcodeLoadStage.ready,
            commands: rapid.commands,
            errors: rapid.errors,
            segments: ToolpathBuilder.build(rapid.commands),
            linesRead: 2,
          ),
        ),
      );
      expect(find.text('主线段 G1: 0'), findsOneWidget);
      expect(find.text('移动段 G0/G1: 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ReadTrackingSegments extends ListBase<ToolpathSegment> {
  _ReadTrackingSegments(this._segments);
  final List<ToolpathSegment> _segments;
  int reads = 0;
  @override
  int get length => _segments.length;
  @override
  set length(int value) => throw UnsupportedError('immutable path');
  @override
  ToolpathSegment operator [](int index) {
    reads++;
    return _segments[index];
  }

  @override
  void operator []=(int index, ToolpathSegment value) =>
      throw UnsupportedError('immutable path');
}
