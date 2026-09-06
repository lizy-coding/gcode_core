// Native validation entry point for the actual GcodeCanvas GPU backend.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:gcode_core/gcode_core.dart';

void main() => runApp(const MaterialApp(home: Validation()));

class Validation extends StatefulWidget {
  const Validation({super.key});
  @override
  State<Validation> createState() => _ValidationState();
}

class _ValidationState extends State<Validation>
    with SingleTickerProviderStateMixin {
  final boundary = GlobalKey();
  late final AnimationController controller;
  final timings = <ui.FrameTiming>[];
  List<ToolpathSegment> segments = [];
  double progress = 1;
  bool recording = false;
  bool visible = true;
  double width = 640;
  String status = '准备验证';
  late Directory output;

  @override
  void initState() {
    super.initState();
    controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..addListener(() {
            setState(() => progress = controller.value);
          });
    SchedulerBinding.instance.addTimingsCallback(collect);
    WidgetsBinding.instance.addPostFrameCallback((_) => runValidation());
  }

  void collect(List<ui.FrameTiming> frames) {
    if (recording) timings.addAll(frames);
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> capture(String name) async {
    await settle();
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${output.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }

  Future<void> runValidation() async {
    try {
      output = await Directory.systemTemp.createTemp('gcode-2d-validation-');
      final parsed = GcodeParser().parse(
        'G0 X-20 Y-10\nG1 X20 Y-10\nG1 X20 Y20\nG0 X-20 Y20\nG1 X-20 Y-10',
      );
      if (parsed.errors.isNotEmpty) throw StateError('Fixture parse failed');
      final fixture = ToolpathBuilder.build(parsed.commands);
      for (final p in [0.0, 0.45, 1.0]) {
        setState(() {
          segments = fixture;
          progress = p;
        });
        await capture('gpu-${p.toStringAsFixed(2)}');
      }
      // Force surface destruction/recreation and resize with real GPU frames.
      for (var i = 0; i < 20; i++) {
        setState(() {
          visible = false;
        });
        await settle();
        setState(() {
          visible = true;
          width = i.isEven ? 480 : 640;
          segments = List.of(fixture);
        });
        await settle();
      }
      await capture('gpu-after-20-reloads');
      final source = StringBuffer();
      for (var i = 0; i < 10000; i++) {
        source.writeln(
          '${i % 7 == 0 ? 'G0' : 'G1'} X${(i % 100) + 1} Y${i ~/ 100}',
        );
      }
      final commands = GcodeParser().parse(source.toString());
      final large = ToolpathBuilder.build(commands.commands);
      if (large.length != 10000) {
        throw StateError('Expected 10000 segments, got ${large.length}');
      }
      setState(() {
        segments = large;
        width = 640;
        status = '实际二维 GPU：10,000 段 · 60 秒播放采样';
      });
      controller.repeat();
      await Future<void>.delayed(const Duration(seconds: 5));
      recording = true;
      await Future<void>.delayed(const Duration(seconds: 60));
      recording = false;
      controller.stop();
      double p95(List<int> a) {
        a.sort();
        return a.isEmpty ? -1 : a[(a.length * .95).ceil() - 1] / 1000;
      }

      final report = {
        'segments': large.length,
        'frames': timings.length,
        'seconds': 60,
        'uiP95Ms': p95(
          timings.map((f) => f.buildDuration.inMicroseconds).toList(),
        ),
        'rasterP95Ms': p95(
          timings.map((f) => f.rasterDuration.inMicroseconds).toList(),
        ),
        'overBudgetFrames': timings
            .where(
              (f) =>
                  f.buildDuration.inMicroseconds > 16667 ||
                  f.rasterDuration.inMicroseconds > 16667,
            )
            .length,
        'reloadCycles': 20,
        'output': output.path,
      };
      await capture('gpu-10000');
      await File(
        '${output.path}/report.json',
      ).writeAsString(jsonEncode(report));
      debugPrint('GPU_2D_RESULT ${jsonEncode(report)}');
      setState(() => status = '验证完成 · ${timings.length} 帧 / 60 秒');
    } catch (e, stack) {
      debugPrint('GPU_2D_FAILED $e\n$stack');
      setState(() => status = '验证失败 $e');
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(status)),
    body: Center(
      child: RepaintBoundary(
        key: boundary,
        child: SizedBox(
          width: width,
          height: 480,
          child: visible
              ? GcodeCanvas(
                  segments: segments,
                  progress: progress,
                  showLegend: false,
                )
              : const SizedBox(),
        ),
      ),
    ),
  );
}
