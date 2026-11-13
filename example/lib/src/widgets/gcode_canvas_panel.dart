import 'package:flutter/material.dart';
import 'package:gcode_core/gcode_core.dart';

class GcodeCanvasPanel extends StatelessWidget {
  const GcodeCanvasPanel({
    super.key,
    required this.snapshot,
    required this.parsing,
    required this.progress,
    required this.isPlaying,
    required this.speedMultiplier,
    required this.onPlay,
    required this.onPause,
    required this.onReset,
    required this.onSeek,
    required this.onSpeedChange,
  });

  final GcodeLoadSnapshot? snapshot;
  final bool parsing;
  final double progress;
  final bool isPlaying;
  final double speedMultiplier;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onReset;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeedChange;

  @override
  Widget build(BuildContext context) {
    final segments = snapshot?.segments ?? const <ToolpathSegment>[];
    final errors = snapshot?.errors.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: GcodeCanvas(
                  segments: segments,
                  progress: parsing ? 1 : progress,
                  errorCount: errors,
                  bounds: snapshot?.bounds,
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: _CanvasLegend(parsing: parsing, segments: segments),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PlaybackControls(
          isPlaying: isPlaying,
          progress: parsing ? 1 : progress,
          speedMultiplier: speedMultiplier,
          onPlay: onPlay,
          onPause: onPause,
          onReset: onReset,
          onSeek: onSeek,
          onSpeedChange: onSpeedChange,
        ),
      ],
    );
  }
}

class _CanvasLegend extends StatefulWidget {
  const _CanvasLegend({required this.parsing, required this.segments});

  final bool parsing;
  final List<ToolpathSegment> segments;

  @override
  State<_CanvasLegend> createState() => _CanvasLegendState();
}

class _CanvasLegendState extends State<_CanvasLegend> {
  late int _mainSegments;

  @override
  void initState() {
    super.initState();
    _countSegments();
  }

  @override
  void didUpdateWidget(covariant _CanvasLegend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.segments, oldWidget.segments)) _countSegments();
  }

  void _countSegments() {
    _mainSegments = widget.segments
        .where((segment) => segment.type == GcodeSegmentType.linear)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: DefaultTextStyle(
          style: theme.textTheme.labelMedium!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.parsing ? '动态解析绘制中' : 'GPU 轨迹绘制'),
              const SizedBox(height: 4),
              Text('主线段 G1: $_mainSegments'),
              Text('移动段 G0/G1: ${widget.segments.length}'),
            ],
          ),
        ),
      ),
    );
  }
}
