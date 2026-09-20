import 'package:example/main.dart';
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
}
