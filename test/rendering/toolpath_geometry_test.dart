import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';
import 'package:gcode_core/src/rendering/toolpath_geometry.dart';

ToolpathSegment segment(double x0, double y0, double x1, double y1,
        {GcodeSegmentType type = GcodeSegmentType.linear}) =>
    ToolpathSegment(
        start: MachinePosition(x: x0, y: y0),
        end: MachinePosition(x: x1, y: y1),
        command: const GcodeCommand(
            lineNumber: 1, rawLine: 'G1', code: 'G1', params: {}),
        type: type);

void main() {
  test('translated negative coordinates produce the same screen geometry', () {
    final a = ToolpathGeometry.build(
        [segment(0, 0, 10, 10)],
        const GcodeBounds(minX: 0, maxX: 10, minY: 0, maxY: 10),
        const Size(200, 200),
        3);
    final b = ToolpathGeometry.build(
        [segment(-50, -30, -40, -20)],
        const GcodeBounds(minX: -50, maxX: -40, minY: -30, maxY: -20),
        const Size(200, 200),
        3);
    expect(a.vertexCount, 6);
    expect(b.vertices, a.vertices);
    // A rising machine Y becomes an upward screen direction.
    expect(a.vertices[8], lessThan(a.vertices[1]));
  });
  test('zero length does not corrupt progress indices or produce NaN', () {
    final geometry = ToolpathGeometry.build([
      segment(0, 0, 0, 0),
      segment(0, 0, 10, 0, type: GcodeSegmentType.rapid)
    ], const GcodeBounds(minX: 0, maxX: 10, minY: 0, maxY: 0),
        const Size(200, 200), 3);
    expect(geometry.vertexCount, 6);
    expect(geometry.vertices.every((v) => v.isFinite), isTrue);
    expect(geometry.vertices[5], 1); // Original segment position is retained.
    expect(geometry.vertices[6], 1); // G0 style survives geometry conversion.
  });
  test('a viewport smaller than padding has no geometry', () {
    expect(
        ToolpathGeometry.build(
                [segment(0, 0, 10, 10)],
                const GcodeBounds(minX: 0, maxX: 10, minY: 0, maxY: 10),
                const Size(50, 40),
                3)
            .vertexCount,
        0);
  });
}
