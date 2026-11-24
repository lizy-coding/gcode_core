import 'package:gcode_core/gcode_core.dart';

MachiningPreview buildMixedPreviewSample(ExposureBitmap image) {
  const outline = '''
G0 X1 Y2
G1 X9 Y2
G1 X9 Y8
G1 X1 Y8
G1 X1 Y2
G0 X2 Y7
G1 X8 Y3
''';
  final path = ToolpathBuilder.build(GcodeParser().parse(outline).commands);
  return MachiningPreview([
    VectorPreviewOperation(path.sublist(0, 5)),
    BitmapPreviewOperation(image),
    VectorPreviewOperation(path.sublist(5)),
  ]);
}
