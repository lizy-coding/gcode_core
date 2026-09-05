// Synthetic GPU capability probe; not the production G-code renderer.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

void main() => runApp(const MaterialApp(home: Probe()));

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  final timings = <ui.FrameTiming>[];
  ProbePainter? painter;
  String? error;
  Timer? timer;
  bool recording = false;
  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    SchedulerBinding.instance.addTimingsCallback(collect);
    initialize();
  }

  void collect(List<ui.FrameTiming> batch) {
    if (recording) timings.addAll(batch);
  }

  Future<void> initialize() async {
    try {
      final library = await gpu.ShaderLibrary.fromAsset(
        'shaders/probe.shaderbundle',
      );
      if (library == null) throw StateError('Shader bundle unavailable');
      final data = Float32List(120000);
      var offset = 0;
      for (var i = 0; i < 10000; i++) {
        final x = -.95 + (i % 100) * .019;
        final y = -.95 + (i ~/ 100) * .019;
        for (final p in [
          x,
          y,
          x + .015,
          y,
          x,
          y + .003,
          x,
          y + .003,
          x + .015,
          y,
          x + .015,
          y + .003,
        ]) {
          data[offset++] = p;
        }
      }
      final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
        ByteData.sublistView(data),
      );
      final vertices = gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: data.lengthInBytes,
      );
      final pipeline = gpu.gpuContext.createRenderPipeline(
        library['ProbeVertex']!,
        library['ProbeFragment']!,
      );
      if (!mounted) return;
      setState(() => painter = ProbePainter(pipeline, vertices, animation));
      animation.repeat();
      timer = Timer(const Duration(seconds: 5), () {
        recording = true;
        timer = Timer(const Duration(seconds: 60), finish);
      });
      debugPrint(
        'GPU_PROBE_READY segments=10000 geometryBytes=${data.lengthInBytes}',
      );
    } catch (e, stack) {
      debugPrint('GPU_PROBE_FAILED $e\n$stack');
      if (mounted) setState(() => error = '$e');
    }
  }

  void finish() {
    recording = false;
    double p95(List<int> values) {
      if (values.isEmpty) return -1;
      values.sort();
      return values[(values.length * .95).ceil() - 1] / 1000;
    }

    final missed = timings
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 16667 ||
              f.rasterDuration.inMicroseconds > 16667,
        )
        .length;
    debugPrint(
      'GPU_PROBE_RESULT ${jsonEncode({'segments': 10000, 'sampleSeconds': 60, 'frames': timings.length, 'uiP95Ms': p95(timings.map((f) => f.buildDuration.inMicroseconds).toList()), 'rasterP95Ms': p95(timings.map((f) => f.rasterDuration.inMicroseconds).toList()), 'overBudgetRatio': timings.isEmpty ? null : missed / timings.length, 'physicalWidth': painter?.surface?.width, 'physicalHeight': painter?.surface?.height, 'scope': 'synthetic solid quads, not feature parity'})}',
    );
    animation.stop();
  }

  @override
  void dispose() {
    timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(collect);
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Flutter GPU · 10,000 段能力验证')),
    body: error != null
        ? SelectableText(error!)
        : painter == null
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(
            builder: (context, constraints) {
              painter!.dpr = MediaQuery.devicePixelRatioOf(context);
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: painter,
              );
            },
          ),
  );
}

class ProbePainter extends CustomPainter {
  ProbePainter(this.pipeline, this.vertices, this.animation)
    : super(repaint: animation);
  final gpu.RenderPipeline pipeline;
  final gpu.BufferView vertices;
  final Animation<double> animation;
  double dpr = 1;
  gpu.GpuImageSurface? surface;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final width = math.max(1, (size.width * dpr).ceil());
    final height = math.max(1, (size.height * dpr).ceil());
    surface ??= gpu.gpuContext.createImageSurface(width, height);
    if (surface!.width != width || surface!.height != height) {
      surface!.resize(width, height);
    }
    final frame = surface!.acquireNextFrame();
    try {
      final command = gpu.gpuContext.createCommandBuffer();
      final pass = command.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(texture: frame.colorTexture),
        ),
      );
      pass.bindPipeline(pipeline);
      pass.bindVertexBuffer(vertices);
      pass.draw(60000);
      frame.present(command);
      command.submit();
      final image = surface!.currentImage!;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
      image.dispose();
      canvas.drawCircle(
        Offset(size.width * animation.value, size.height / 2),
        6,
        Paint()..color = Colors.orange,
      );
    } catch (_) {
      frame.discard();
      rethrow;
    }
  }

  @override
  bool shouldRepaint(covariant ProbePainter oldDelegate) => true;
}
