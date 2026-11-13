import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

void main() {
  testWidgets('GPU initialization failure reports failure without readiness',
      (tester) async {
    final errors = <Object>[];
    var readyCount = 0;
    final segments = ToolpathBuilder.build(
      GcodeParser().parse('G1 X10').commands,
    );
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 300,
        child: GcodeCanvas(
          segments: segments,
          progress: 1,
          onReady: () => readyCount++,
          onError: errors.add,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(errors, hasLength(1));
    expect(readyCount, 0);
    expect(find.textContaining('GPU 绘制不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
