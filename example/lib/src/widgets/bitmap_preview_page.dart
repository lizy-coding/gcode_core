import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gcode_core/gcode_core.dart';

import '../mixed_preview_sample.dart';

class BitmapPreviewPage extends StatefulWidget {
  const BitmapPreviewPage({super.key});

  @override
  State<BitmapPreviewPage> createState() => _BitmapPreviewPageState();
}

class _BitmapPreviewPageState extends State<BitmapPreviewPage>
    with SingleTickerProviderStateMixin {
  static const rows = [
    '1111100000001',
    '1000000000000',
    '1000000000000',
    '1111000000000',
    '1000000000000',
    '1000000000000',
    '0000000000000',
    '1000000000011',
  ];
  final image = ExposureBitmap(
    width: rows.first.length,
    height: rows.length,
    samples: Uint8List.fromList([
      for (final row in rows)
        for (final pixel in row.codeUnits) pixel == 49 ? 255 : 0,
    ]),
    origin: const Offset(2, 7),
    columnStep: const Offset(0.5, 0),
    rowStep: const Offset(0, -0.5),
  );
  late final scene = buildMixedPreviewSample(image);
  late final mixedTimeline = PreviewTimeline(scene);
  late final bitmapTimeline = PreviewTimeline(
    MachiningPreview([BitmapPreviewOperation(image)]),
  );
  bool mixed = false;
  double speedMultiplier = 1;
  PreviewTimeline get timeline => mixed ? mixedTimeline : bitmapTimeline;
  late final playback = AnimationController(
    vsync: this,
    duration: _playbackDuration,
    value: 1,
  );

  Duration get _playbackDuration => Duration(
    microseconds:
        (timeline.totalSeconds *
                Duration.microsecondsPerSecond /
                speedMultiplier)
            .ceil(),
  );

  void _changeSpeed(double multiplier) {
    final resume = playback.isAnimating;
    playback.stop();
    setState(() {
      speedMultiplier = multiplier;
      playback.duration = _playbackDuration;
    });
    if (resume) playback.forward();
  }

  @override
  void dispose() {
    playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('位图扫描示意')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: playback,
        builder: (context, _) => Column(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('单张位图')),
                ButtonSegment(value: true, label: Text('混合加工')),
              ],
              selected: {mixed},
              onSelectionChanged: (selection) => setState(() {
                mixed = selection.single;
                playback.duration = _playbackDuration;
                playback.value = 0;
              }),
            ),
            Expanded(
              child: GcodeCanvas.timed(
                timeline: timeline,
                progress: playback.value,
              ),
            ),
            Text(
              '预览时间 ${(playback.value * timeline.totalSeconds).toStringAsFixed(2)}'
              ' / ${timeline.totalSeconds.toStringAsFixed(2)} 秒',
              textAlign: TextAlign.center,
            ),
            PlaybackControls(
              isPlaying: playback.isAnimating,
              progress: playback.value,
              speedMultiplier: speedMultiplier,
              onPlay: () => setState(() {
                playback.forward(from: playback.isCompleted ? 0 : null);
              }),
              onPause: () => setState(() => playback.stop()),
              onReset: () => playback.value = 0,
              onSeek: (value) => playback.value = value,
              onSpeedChange: _changeSpeed,
            ),
          ],
        ),
      ),
    ),
  );
}
