import 'dart:async';

import 'package:example/src/gcode_example_page.dart';
import 'package:example/src/gcode_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

void main() {
  for (final width in [320.0, 600.0, 720.0, 1280.0]) {
    testWidgets('loaded complete source fits width $width', (tester) async {
      final controller = GcodeSessionController();
      addTearDown(controller.dispose);
      await tester.runAsync(
        () => controller.parseSnapshots(
          GcodeReadlinePipeline().load(
            const StringGcodeLineReader('G1 X10 F600'),
          ),
          sourceName: 'complete.nc',
        ),
      );
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: GcodeExamplePage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('主线段 G1: 1'), findsOneWidget);
      expect(find.text('移动段 G0/G1: 1'), findsOneWidget);
      expect(find.text('预计加工耗时：1.000 秒'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loaded incomplete source fits width $width', (tester) async {
      final controller = GcodeSessionController();
      addTearDown(controller.dispose);
      await tester.runAsync(
        () => controller.parseSnapshots(
          GcodeReadlinePipeline().load(const StringGcodeLineReader('G1 X10')),
          sourceName: 'incomplete.nc',
        ),
      );
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: GcodeExamplePage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('主线段 G1: 1'), findsOneWidget);
      expect(find.text('预计加工耗时：不完整'), findsOneWidget);
      expect(find.textContaining('估时第 1 行'), findsOneWidget);
      expect(find.text('预计加工耗时：0.000 秒'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loaded source with parse errors fits width $width', (
      tester,
    ) async {
      final controller = GcodeSessionController();
      addTearDown(controller.dispose);
      await tester.runAsync(
        () => controller.parseSnapshots(
          GcodeReadlinePipeline().load(
            const StringGcodeLineReader('G1 X10 F600\nG2 X20'),
          ),
          sourceName: 'errors.nc',
        ),
      );
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: GcodeExamplePage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('1 个解析错误'), findsOneWidget);
      expect(find.text('1 错误'), findsOneWidget);
      expect(find.text('ERR'), findsOneWidget);
      expect(find.text('预计加工耗时：不完整'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading source fits width $width and disables new loads', (
      tester,
    ) async {
      late GcodeSessionController controller;
      late StreamController<GcodeLoadSnapshot> source;
      late Future<void> load;
      await tester.runAsync(() async {
        controller = GcodeSessionController();
        source = StreamController<GcodeLoadSnapshot>();
        final ready = await GcodeReadlinePipeline()
            .load(const StringGcodeLineReader('G1 X10 F600'))
            .last;
        final prefixReceived = Completer<void>();
        controller.addListener(() {
          if (controller.snapshot?.stage == GcodeLoadStage.parsing &&
              !prefixReceived.isCompleted) {
            prefixReceived.complete();
          }
        });
        load = controller.parseSnapshots(
          source.stream,
          sourceName: 'loading.nc',
        );
        source.add(
          GcodeLoadSnapshot(
            stage: GcodeLoadStage.parsing,
            commands: ready.commands,
            errors: ready.errors,
            segments: ready.segments,
            bounds: ready.bounds,
            linesRead: ready.linesRead,
            message: '已读取 1 行',
            timeEstimate: ready.timeEstimate,
          ),
        );
        await prefixReceived.future;
      });
      addTearDown(() async {
        controller.dispose();
        await load;
        await source.close();
      });
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: GcodeExamplePage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('动态解析绘制中'), findsOneWidget);
      expect(find.text('预计加工耗时：等待加载完成'), findsOneWidget);
      expect(find.text('预计加工耗时：1.000 秒'), findsNothing);
      final actions = find.descendant(
        of: find.byType(AppBar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is IconButton ||
              widget is TextButton ||
              widget is FilledButton,
        ),
      );
      expect(actions, findsNWidgets(2));
      for (final widget in tester.widgetList(actions)) {
        if (widget is IconButton) expect(widget.onPressed, isNull);
        if (widget is ButtonStyleButton) expect(widget.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
