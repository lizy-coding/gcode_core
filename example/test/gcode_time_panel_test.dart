import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

import 'package:example/src/widgets/gcode_result_panel.dart';

void main() {
  testWidgets('shows full timing only when loaded and complete', (
    tester,
  ) async {
    Future<void> show(GcodeLoadStage stage, String source) async {
      final snapshot = GcodeLoadSnapshot(
        stage: stage,
        commands: const [],
        errors: const [],
        segments: const [],
        linesRead: 1,
        timeEstimate: estimateGcodeTime(source),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GcodeResultPanel(
              snapshot: snapshot,
              currentIndex: -1,
              onCommandTap: (_) {},
            ),
          ),
        ),
      );
    }

    await show(GcodeLoadStage.parsing, 'G0 F600 X10');
    expect(find.text('预计加工耗时：等待加载完成'), findsOneWidget);
    await show(GcodeLoadStage.ready, 'G0 F600 X10');
    expect(find.text('预计加工耗时：1.000 秒'), findsOneWidget);
    await show(GcodeLoadStage.ready, 'G0 X10');
    expect(find.text('预计加工耗时：不完整'), findsOneWidget);
    expect(find.textContaining('估时第 1 行'), findsOneWidget);
    expect(find.text('预计加工耗时：0.000 秒'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
