// Native validation of bitmap and mixed preview through the public canvas.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:gcode_core/gcode_core.dart';

import 'src/gpu_validation_monitor.dart';
import 'src/mixed_preview_sample.dart';

void main() => runApp(const MaterialApp(home: _Validation()));

class _Validation extends StatefulWidget {
  const _Validation();

  @override
  State<_Validation> createState() => _ValidationState();
}

class _ValidationState extends State<_Validation> {
  final boundary = GlobalKey();
  final monitor = GpuValidationMonitor();
  final output = Directory(
    Platform.environment['GCODE_GPU_OUTPUT'] ?? Directory.systemTemp.path,
  );
  GcodeRenderStats stats = GcodeRenderStats();
  MachiningPreview? scene;
  ExposureBitmap? bitmap;
  double progress = 0;
  double width = 640;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  ExposureBitmap _bitmap(int width, int height, {bool reverse = false}) {
    const rows = [
      '1111100000001',
      '1000000000000',
      '1000000000000',
      '1111000000000',
      '1000000000000',
      '1000000000000',
      '0000000000000',
      '1000000000011',
    ];
    final samples = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        samples[y * width + x] = rows[y % 8].codeUnitAt(x % 13) == 49 ? 255 : 0;
      }
    }
    return ExposureBitmap(
      width: width,
      height: height,
      samples: samples,
      origin: const Offset(2, 7),
      columnStep: Offset(6.5 / width, 0),
      rowStep: Offset(0, -4 / height),
      firstRowRightToLeft: reverse,
    );
  }

  Map<String, int> _stats() => {
    'frames': stats.compositedFrames,
    'textures': stats.textureUploads,
    'textureBytes': stats.textureUploadBytes,
    'geometryBuilds': stats.geometryBuilds,
    'vertexBytes': stats.vertexUploadBytes,
    'surfaceResizes': stats.surfaceResizes,
    'uniformBufferCreations': stats.uniformBufferCreations,
    'uniformBufferReservedBytes': stats.uniformBufferReservedBytes,
  };

  Future<void> _seek(double value) async {
    setState(() => progress = value);
    await WidgetsBinding.instance.endOfFrame;
    monitor.check();
  }

  Future<void> _scene({MachiningPreview? mixed, ExposureBitmap? image}) async {
    monitor.beginScene();
    setState(() {
      stats = GcodeRenderStats();
      scene = mixed;
      bitmap = image;
      progress = 0;
    });
    await monitor.waitForReady();
    monitor.check();
  }

  Future<void> _capture(String name) async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('${output.path}/$name.png').writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
    monitor.check();
  }

  Future<Map<String, Object?>> _sample(MachiningPreview mixed) async {
    await _scene(mixed: mixed);
    await _seek(1);
    final timings = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(collect);
    final memory = <Map<String, int>>[];
    final clock = Stopwatch()..start();
    var frames = 0;
    try {
      while (clock.elapsedMilliseconds < 15000) {
        if (memory.length <= clock.elapsedMilliseconds ~/ 1000) {
          memory.add({
            'ms': clock.elapsedMilliseconds,
            'rss': ProcessInfo.currentRss,
            'frames': frames,
          });
        }
        await _seek(frames.isEven ? 1 : .98);
        frames++;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(collect);
    }
    double? p95(Iterable<int> micros) {
      final sorted = micros.toList()..sort();
      return sorted.isEmpty
          ? null
          : sorted[(sorted.length * .95).ceil() - 1] / 1000;
    }

    return {
      'operations': mixed.operations.length,
      'updates': frames,
      'elapsedMs': clock.elapsedMilliseconds,
      'timingSamples': timings.length,
      'uiP95Ms': p95(timings.map((f) => f.buildDuration.inMicroseconds)),
      'rasterP95Ms': p95(timings.map((f) => f.rasterDuration.inMicroseconds)),
      'rssSamples': memory,
      'stats': _stats(),
    };
  }

  Future<void> _run() async {
    try {
      await output.create(recursive: true);
      final image = _bitmap(13, 8);
      final mixed = buildMixedPreviewSample(image);
      await _scene(image: image);
      final bitmapReady = _stats();
      await _capture('bitmap-zero');
      await _seek(.95);
      await _capture('bitmap-reverse-last');
      await _seek(1);
      await _capture('bitmap-full');

      await _scene(mixed: mixed);
      final mixedReady = _stats();
      await _seek(.25);
      await _capture('mixed-outline');
      await _seek(.55);
      await _capture('mixed-bitmap');
      final mixedFirstBitmap = _stats();
      for (var i = 0; i < 30; i++) {
        await _seek(i.isEven ? 0 : .55);
        await _seek(1);
        await _capture('mixed-full-$i');
      }
      await _seek(.25);
      await _capture('mixed-rewind');
      final mixedAfterSeek = _stats();

      await _scene(image: _bitmap(4096, 4096, reverse: true));
      final largeReady = _stats();
      final first = Stopwatch()..start();
      await _seek(1);
      first.stop();
      await _capture('large-full');
      final largeFirst = _stats();
      setState(() => width = 520);
      await _seek(.5);
      await _seek(1);
      final largeAfterResize = _stats();
      setState(() => width = 640);

      final control = await _sample(mixed);
      final stress = await _sample(
        MachiningPreview([
          mixed.operations.first,
          for (var i = 0; i < 62; i++) BitmapPreviewOperation(image),
          mixed.operations.last,
        ]),
      );
      if (!mounted) throw StateError('Validation view was disposed');
      final data = {
        'os': Platform.operatingSystemVersion,
        'dart': Platform.version,
        'dpr': MediaQuery.devicePixelRatioOf(context),
        'canvas': '640x480 logical',
        'bitmapReady': bitmapReady,
        'mixedReady': mixedReady,
        'mixedFirstBitmap': mixedFirstBitmap,
        'mixedAfterSeek': mixedAfterSeek,
        'largeReady': largeReady,
        'largeFirst': largeFirst,
        'largeFirstFrameMs': first.elapsedMicroseconds / 1000,
        'largeAfterResize': largeAfterResize,
        'control': control,
        'stress': stress,
      };
      await File(
        '${output.path}/metrics.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      stdout.writeln('MIXED_GPU_VALIDATION_COMPLETE ${output.path}');
      exit(0);
    } catch (error, stack) {
      stderr.writeln('MIXED_GPU_VALIDATION_FAILED $error\n$stack');
      exit(1);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: boundary,
        child: SizedBox(
          width: width,
          height: 480,
          child: scene != null
              ? GcodeCanvas.mixed(
                  preview: scene!,
                  progress: progress,
                  stats: stats,
                  onReady: monitor.presented,
                  onError: monitor.failed,
                )
              : bitmap != null
              ? GcodeCanvas.bitmap(
                  image: bitmap!,
                  progress: progress,
                  stats: stats,
                  onReady: monitor.presented,
                  onError: monitor.failed,
                )
              : null,
        ),
      ),
    ),
  );
}
