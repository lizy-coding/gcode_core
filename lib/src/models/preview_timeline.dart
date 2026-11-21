import 'dart:math' as math;
import 'dart:typed_data';

import 'gcode_command.dart';
import 'machining_preview.dart';

/// Rates for visual playback, in machine units or rows per preview second.
class PreviewSpeeds {
  PreviewSpeeds({
    this.linearUnitsPerSecond = 12,
    this.rapidUnitsPerSecond = 48,
    this.bitmapRowsPerSecond = 120,
  }) {
    for (final (name, value) in [
      ('linearUnitsPerSecond', linearUnitsPerSecond),
      ('rapidUnitsPerSecond', rapidUnitsPerSecond),
      ('bitmapRowsPerSecond', bitmapRowsPerSecond),
    ]) {
      if (!value.isFinite || value <= 0) {
        throw ArgumentError.value(
            value, name, 'Expected a positive finite rate');
      }
    }
  }

  final double linearUnitsPerSecond;
  final double rapidUnitsPerSecond;
  final double bitmapRowsPerSecond;
}

/// Computes visual playback positions for one immutable machining preview.
class PreviewTimeline {
  PreviewTimeline(this.preview, {PreviewSpeeds? speeds})
      : speeds = speeds ?? PreviewSpeeds(),
        _operationEnds = Float64List(preview.operations.length),
        _segmentEnds = List.filled(preview.operations.length, null) {
    var elapsed = 0.0;
    for (var i = 0; i < preview.operations.length; i++) {
      final operation = preview.operations[i];
      switch (operation) {
        case VectorPreviewOperation():
          final ends = Float64List(operation.segments.length);
          var time = 0.0;
          for (var j = 0; j < operation.segments.length; j++) {
            final segment = operation.segments[j];
            final dx = segment.end.x - segment.start.x;
            final dy = segment.end.y - segment.start.y;
            final rate = segment.type == GcodeSegmentType.rapid
                ? this.speeds.rapidUnitsPerSecond
                : this.speeds.linearUnitsPerSecond;
            time = _addTime(time, math.sqrt(dx * dx + dy * dy) / rate);
            ends[j] = time;
          }
          _segmentEnds[i] = ends;
          elapsed = _addTime(elapsed, time);
        case BitmapPreviewOperation():
          elapsed = _addTime(elapsed,
              operation.image.height / this.speeds.bitmapRowsPerSecond);
      }
      _operationEnds[i] = elapsed;
    }
  }

  final MachiningPreview preview;
  final PreviewSpeeds speeds;
  final Float64List _operationEnds;
  final List<Float64List?> _segmentEnds;

  double get totalSeconds => _operationEnds.isEmpty ? 0 : _operationEnds.last;

  /// Resolves elapsed preview seconds to a position in the original scene.
  ///
  /// The vector position is a segment index plus the fraction of that segment.
  /// The bitmap position is a fraction of the entire scan. The endpoint
  /// includes trailing zero-duration operations.
  ({int operationIndex, double localPosition})? positionAt(double seconds) {
    if (_operationEnds.isEmpty) return null;
    final elapsed = seconds.isNaN ? 0.0 : seconds.clamp(0.0, totalSeconds);
    if (elapsed >= totalSeconds) {
      final last = _operationEnds.length - 1;
      return (
        operationIndex: last,
        localPosition: _segmentEnds[last]?.length.toDouble() ?? 1.0,
      );
    }
    final index = _firstEndAfter(_operationEnds, elapsed.toDouble());
    final start = index == 0 ? 0.0 : _operationEnds[index - 1];
    final localTime = elapsed - start;
    final segments = _segmentEnds[index];
    if (segments == null) {
      return (
        operationIndex: index,
        localPosition:
            (localTime / (_operationEnds[index] - start)).clamp(0.0, 1.0),
      );
    }
    // At large timestamps subtracting the operation start can round to its end.
    if (localTime >= segments.last) {
      return (operationIndex: index, localPosition: segments.length.toDouble());
    }
    final segment = _firstEndAfter(segments, localTime.toDouble());
    final segmentStart = segment == 0 ? 0.0 : segments[segment - 1];
    return (
      operationIndex: index,
      localPosition: segment +
          (localTime - segmentStart) / (segments[segment] - segmentStart),
    );
  }

  static double _addTime(double start, double duration) {
    final end = start + duration;
    if (!end.isFinite || (duration > 0 && end == start)) {
      throw ArgumentError('Preview duration cannot be represented');
    }
    return end;
  }

  static int _firstEndAfter(Float64List ends, double time) {
    var low = 0;
    var high = ends.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (ends[middle] <= time) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
