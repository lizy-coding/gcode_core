import '../core/gcode_bounds.dart';
import '../rendering/toolpath_viewport.dart';
import 'exposure_bitmap.dart';
import 'toolpath_segment.dart';

/// One contiguous operation in processing order.
sealed class PreviewOperation {
  PreviewOperation(double weight) : weight = weight {
    if (!weight.isFinite || weight <= 0) {
      throw ArgumentError.value(
          weight, 'weight', 'Expected a positive finite weight');
    }
  }

  /// Relative share of playback, in a consistent unit across the scene.
  final double weight;
  GcodeBounds get bounds;
}

final class VectorPreviewOperation extends PreviewOperation {
  VectorPreviewOperation(List<ToolpathSegment> path, {double? weight})
      : segments = List.unmodifiable(path),
        super(weight ?? path.length.toDouble()) {
    if (segments.isEmpty) throw ArgumentError('Empty vector operation');
  }

  final List<ToolpathSegment> segments;
  @override
  late final GcodeBounds bounds = ToolpathViewport.measure(segments);
}

final class BitmapPreviewOperation extends PreviewOperation {
  BitmapPreviewOperation(this.image, {double? weight})
      : super(weight ?? image.height.toDouble());

  final ExposureBitmap image;
  @override
  GcodeBounds get bounds => image.bounds;
}

/// Immutable scene. Reuse the instance while playing or seeking.
class MachiningPreview {
  MachiningPreview(List<PreviewOperation> operations)
      : operations = List.unmodifiable(operations) {
    final path = <ToolpathSegment>[];
    var weight = 0.0;
    GcodeBounds? extent;
    for (final operation in this.operations) {
      final next = weight + operation.weight;
      if (!next.isFinite || next <= weight) {
        throw ArgumentError('Unrepresentable playback weight range');
      }
      weight = next;
      if (operation is VectorPreviewOperation) path.addAll(operation.segments);
      final b = operation.bounds;
      extent = extent?.expand(b.minX, b.minY).expand(b.maxX, b.maxY) ?? b;
    }
    segments = List.unmodifiable(path);
    bounds = extent ?? GcodeBounds.zero;
    totalWeight = weight;
  }

  final List<PreviewOperation> operations;
  late final List<ToolpathSegment> segments;
  late final GcodeBounds bounds;
  late final double totalWeight;
}
