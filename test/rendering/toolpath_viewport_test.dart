import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';
import 'package:gcode_core/src/rendering/toolpath_viewport.dart';

void main() {
  final segments = ToolpathBuilder.build(
      GcodeParser().parse('G1 X10 Y0\nG1 X10 Y10').commands);
  test('markers use the same segment interpolation and coordinate transform',
      () {
    final view = ToolpathViewport(
        ToolpathViewport.measure(segments), const Size(200, 200));
    expect(view.toolHead(segments, 0), view.project(0, 0));
    expect(view.toolHead(segments, .25), view.project(5, 0));
    expect(view.toolHead(segments, .5), view.project(10, 0));
    expect(view.toolHead(segments, 1), view.project(10, 10));
  });
  test(
      'grid phase remains aligned to machine coordinates across negative bounds',
      () {
    final view = ToolpathViewport(
        const GcodeBounds(minX: -13, maxX: 17, minY: -8, maxY: 22),
        const Size(360, 360));
    final origin = view.project(0, 0), grid = view.gridOrigin;
    expect((origin.dx - grid.dx) % 20, closeTo(0, 1e-6));
    expect((origin.dy - grid.dy) % 20, closeTo(0, 1e-6));
    expect(view.plot.contains(view.project(0, 0)), isTrue);
  });
  test('default style provides value parameters without mutable Paint', () {
    const style = GcodeStyle();
    expect(style.linearMove.width, 2.5);
    expect(style.rapidMove.width, 1.5);
    expect(style.toolHeadGlowColor.a, closeTo(.3, .01));
  });
}
