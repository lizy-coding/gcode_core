import 'package:flutter/material.dart';

import 'gcode_session_controller.dart';
import 'widgets/gcode_canvas_panel.dart';
import 'widgets/gcode_result_panel.dart';
import 'widgets/gcode_status_bar.dart';

class GcodeExamplePage extends StatefulWidget {
  const GcodeExamplePage({super.key, this.controller});

  final GcodeSessionController? controller;

  @override
  State<GcodeExamplePage> createState() => _GcodeExamplePageState();
}

class _GcodeExamplePageState extends State<GcodeExamplePage> {
  late final GcodeSessionController _controller =
      widget.controller ?? GcodeSessionController();
  late final bool _ownsController = widget.controller == null;

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).width < 600;
        return Scaffold(
          appBar: AppBar(
            title: Text(compact ? 'G-code' : 'G-code Core 绘制示例'),
            actions: _buildActions(compact),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GcodeStatusBar(
                  sourceName: _controller.sourceName,
                  status: _controller.status,
                  loading: _controller.loading,
                ),
                const SizedBox(height: 16),
                Expanded(child: _buildWorkspace()),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActions(bool compact) {
    final sample = _controller.loading ? null : _controller.loadSample;
    final pick = _controller.loading ? null : _controller.pickAndParseFile;
    if (compact) {
      return [
        IconButton(
          onPressed: sample,
          icon: const Icon(Icons.data_object),
          tooltip: '示例数据',
        ),
        IconButton(
          onPressed: pick,
          icon: const Icon(Icons.folder_open),
          tooltip: '选择 G-code',
        ),
        const SizedBox(width: 8),
      ];
    }
    return [
      TextButton.icon(
        onPressed: sample,
        icon: const Icon(Icons.data_object),
        label: const Text('示例数据'),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(
        onPressed: pick,
        icon: const Icon(Icons.folder_open),
        label: const Text('选择 G-code'),
      ),
      const SizedBox(width: 16),
    ];
  }

  Widget _buildWorkspace() {
    final canvas = ValueListenableBuilder<double>(
      valueListenable: _controller.playbackProgress,
      builder: (context, progress, _) => GcodeCanvasPanel(
        snapshot: _controller.snapshot,
        parsing: _controller.loading,
        progress: progress,
        isPlaying: _controller.isPlaying,
        speedMultiplier: _controller.speedMultiplier,
        onPlay: _controller.play,
        onPause: _controller.pause,
        onReset: _controller.resetPlayback,
        onSeek: _controller.seekPlayback,
        onSpeedChange: _controller.setSpeed,
      ),
    );
    final results = ValueListenableBuilder<int>(
      valueListenable: _controller.currentCommandIndex,
      builder: (context, index, _) => GcodeResultPanel(
        snapshot: _controller.snapshot,
        currentIndex: index,
        onCommandTap: _controller.selectCommand,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: canvas),
              const SizedBox(width: 16),
              SizedBox(width: 360, child: results),
            ],
          );
        }
        final canvasHeight = (constraints.maxHeight * 0.58)
            .clamp(280.0, 420.0)
            .toDouble();
        return ListView(
          children: [
            SizedBox(height: canvasHeight, child: canvas),
            const SizedBox(height: 16),
            SizedBox(height: 420, child: results),
          ],
        );
      },
    );
  }
}
