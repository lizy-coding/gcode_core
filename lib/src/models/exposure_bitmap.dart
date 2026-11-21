import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../core/gcode_bounds.dart';

/// Final row-major exposure samples (0 = blank, 255 = full exposure).
/// [origin] is the outer corner before pixel (0, 0). Each step advances one
/// pixel in machine units. Pixel centers lie half a step from each edge.
class ExposureBitmap {
  ExposureBitmap({
    required this.width,
    required this.height,
    required Uint8List samples,
    this.origin = Offset.zero,
    this.columnStep = const Offset(1, 0),
    this.rowStep = const Offset(0, -1),
    this.firstRowRightToLeft = false,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        samples.length % width != 0 ||
        samples.length ~/ width != height) {
      throw ArgumentError('Expected one exposure byte per pixel');
    }
    final determinant = columnStep.dx * rowStep.dy - columnStep.dy * rowStep.dx;
    if (!determinant.isFinite || determinant == 0) {
      throw ArgumentError('Pixel steps must span a finite area');
    }
    final corners = [
      origin,
      origin + columnSpan,
      origin + rowSpan,
      origin + columnSpan + rowSpan
    ];
    if (corners.any((p) => !p.isFinite)) {
      throw ArgumentError('Bitmap corners must be finite');
    }
    bounds = GcodeBounds(
      minX: corners.map((p) => p.dx).reduce(math.min),
      maxX: corners.map((p) => p.dx).reduce(math.max),
      minY: corners.map((p) => p.dy).reduce(math.min),
      maxY: corners.map((p) => p.dy).reduce(math.max),
    );
    this.samples = Uint8List.fromList(samples).asUnmodifiableView();
  }

  final int width;
  final int height;
  final Offset origin;
  final Offset columnStep;
  final Offset rowStep;
  final bool firstRowRightToLeft;
  late final Uint8List samples;
  late final GcodeBounds bounds;
  Offset get columnSpan => columnStep * width.toDouble();
  Offset get rowSpan => rowStep * height.toDouble();
}
