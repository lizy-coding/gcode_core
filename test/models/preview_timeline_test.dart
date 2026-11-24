import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

VectorPreviewOperation _path(String source, {double? weight}) =>
    VectorPreviewOperation(
      ToolpathBuilder.build(GcodeParser().parse(source).commands),
      weight: weight,
    );

BitmapPreviewOperation _bitmap(int width, int height) =>
    BitmapPreviewOperation(ExposureBitmap(
      width: width,
      height: height,
      samples: Uint8List(width * height),
    ));

void main() {
  test('distance timing is invariant under segment splits and mixed order', () {
    final split = _path([
      for (var i = 1; i <= 20; i++) 'G1 X${i * 1.2}',
    ].join('\n'));
    final two = _path('G1 X12\nG1 X24', weight: 99);
    for (final path in [split, two]) {
      expect(PreviewTimeline(MachiningPreview([path])).totalSeconds,
          closeTo(2, 1e-12));
      final mixed = PreviewTimeline(MachiningPreview([path, _bitmap(2, 120)]));
      expect(mixed.totalSeconds, closeTo(3, 1e-12));
      expect(
        mixed.positionAt(1)!.localPosition,
        closeTo(path.segments.length / 2, 1e-12),
      );
    }
  });

  test('G0 and G1 resolve exact boundaries and partial positions', () {
    final timeline = PreviewTimeline(MachiningPreview([
      _path('G0 X24\nG1 X48'),
      _bitmap(4, 120),
      _path('G1 X12'),
    ]));
    expect(timeline.totalSeconds, 4.5);
    expect(timeline.positionAt(.25), (operationIndex: 0, localPosition: .5));
    expect(timeline.positionAt(.5), (operationIndex: 0, localPosition: 1.0));
    expect(timeline.positionAt(1.5), (operationIndex: 0, localPosition: 1.5));
    expect(timeline.positionAt(2.5), (operationIndex: 1, localPosition: 0.0));
    expect(timeline.positionAt(3.0), (operationIndex: 1, localPosition: .5));
    expect(timeline.positionAt(3.5), (operationIndex: 2, localPosition: 0.0));
    expect(timeline.positionAt(4.5), (operationIndex: 2, localPosition: 1.0));
    expect(timeline.positionAt(3.0), (operationIndex: 1, localPosition: .5));
    expect(timeline.positionAt(-1), timeline.positionAt(0));
  });

  test('custom bitmap timing depends on row count including blank rows', () {
    final timeline = PreviewTimeline(
      MachiningPreview([_bitmap(2, 10), _bitmap(64, 10)]),
      speeds: PreviewSpeeds(bitmapRowsPerSecond: 10),
    );
    expect(timeline.totalSeconds, 2);
    expect(timeline.positionAt(.5), (operationIndex: 0, localPosition: .5));
    expect(timeline.positionAt(1.5), (operationIndex: 1, localPosition: .5));
    expect(timeline.positionAt(5), (operationIndex: 1, localPosition: 1.0));
  });

  test('zero length segments consume zero time, including at the endpoint', () {
    const zero = ToolpathSegment(
      start: MachinePosition(),
      end: MachinePosition(),
      command: GcodeCommand(lineNumber: 1, rawLine: '', code: 'G1', params: {}),
      type: GcodeSegmentType.linear,
    );
    final timeline = PreviewTimeline(MachiningPreview([
      VectorPreviewOperation([zero, ..._path('G1 X12').segments, zero]),
      VectorPreviewOperation([zero]),
    ]));
    expect(timeline.totalSeconds, 1);
    expect(timeline.positionAt(0), (operationIndex: 0, localPosition: 1.0));
    expect(timeline.positionAt(.5), (operationIndex: 0, localPosition: 1.5));
    expect(timeline.positionAt(1), (operationIndex: 1, localPosition: 1.0));
    final empty = PreviewTimeline(MachiningPreview([]));
    expect(empty.totalSeconds, 0);
    expect(empty.positionAt(0), isNull);
  });

  test('rejects rates that are zero, negative or non-finite', () {
    expect(() => PreviewSpeeds(linearUnitsPerSecond: 0), throwsArgumentError);
    expect(() => PreviewSpeeds(rapidUnitsPerSecond: -1), throwsArgumentError);
    expect(() => PreviewSpeeds(bitmapRowsPerSecond: double.infinity),
        throwsArgumentError);
    expect(() => PreviewSpeeds(bitmapRowsPerSecond: double.nan),
        throwsArgumentError);
  });
}
