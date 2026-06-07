import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:gcode_core/gcode_core.dart';

void main() {
  runApp(const GcodeCoreExampleApp());
}

class GcodeCoreExampleApp extends StatelessWidget {
  const GcodeCoreExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G-code Core Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
        useMaterial3: true,
      ),
      home: const GcodeExamplePage(),
    );
  }
}

class GcodeExamplePage extends StatefulWidget {
  const GcodeExamplePage({super.key});

  @override
  State<GcodeExamplePage> createState() => _GcodeExamplePageState();
}

class _GcodeExamplePageState extends State<GcodeExamplePage> {
  static const _sampleSource = '''
G0 X0 Y0
G1 X30 Y0 F1200
G1 X30 Y18
G1 X12 Y18
G0 X6 Y8
G1 X22 Y8
G2 X40 Y40
''';

  final _pipeline = GcodeReadlinePipeline(
    options: const GcodeReadlineOptions(snapshotBatchSize: 100),
  );

  GcodeLoadSnapshot? _snapshot;
  String _sourceName = '未选择文件';
  String _status = '请选择本地 G-code 文件，或加载内置示例。';
  bool _loading = false;

  Future<void> _pickAndParseFile() async {
    const typeGroup = XTypeGroup(
      label: 'G-code',
      extensions: ['gcode', 'nc', 'tap', 'txt'],
    );

    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    await _parseReader(FileGcodeLineReader(file.path), sourceName: file.name);
  }

  Future<void> _loadSample() {
    return _parseReader(
      const StringGcodeLineReader(_sampleSource),
      sourceName: '内置示例',
    );
  }

  Future<void> _parseReader(
    GcodeLineReader reader, {
    required String sourceName,
  }) async {
    setState(() {
      _loading = true;
      _sourceName = sourceName;
      _snapshot = null;
      _status = '正在读取 $sourceName';
    });

    await for (final snapshot in _pipeline.load(reader)) {
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _status = snapshot.message;
      });
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('G-code Core 调用示例'),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : _loadSample,
            icon: const Icon(Icons.data_object),
            label: const Text('示例数据'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _pickAndParseFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('选择 G-code'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBar(
              sourceName: _sourceName,
              status: _status,
              loading: _loading,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: _ToolpathCanvas(segments: snapshot?.segments ?? []),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: _ResultPanel(snapshot: snapshot)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.sourceName,
    required this.status,
    required this.loading,
  });

  final String sourceName;
  final String status;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.route),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$sourceName - $status',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.snapshot});

  final GcodeLoadSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final current = snapshot;

    if (current == null) {
      return const Center(child: Text('解析结果会显示在这里'));
    }

    return ListView(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Metric(label: '行数', value: current.linesRead.toString()),
            _Metric(label: '指令', value: current.commands.length.toString()),
            _Metric(label: '轨迹', value: current.segments.length.toString()),
            _Metric(label: '错误', value: current.errors.length.toString()),
          ],
        ),
        const SizedBox(height: 16),
        Text('轨迹段', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final segment in current.segments.take(12))
          ListTile(
            dense: true,
            leading: Icon(
              segment.type == GcodeSegmentType.rapid
                  ? Icons.near_me
                  : Icons.timeline,
            ),
            title: Text(segment.command.rawLine),
            subtitle: Text(
              '(${segment.start.x}, ${segment.start.y}) -> '
              '(${segment.end.x}, ${segment.end.y})',
            ),
          ),
        if (current.segments.length > 12)
          Text('还有 ${current.segments.length - 12} 条轨迹段未显示'),
        const SizedBox(height: 16),
        Text('解析错误', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (current.errors.isEmpty)
          const Text('无')
        else
          for (final error in current.errors)
            ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber),
              title: Text('第 ${error.lineNumber} 行'),
              subtitle: Text('${error.message}\n${error.rawLine}'),
            ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 78,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolpathCanvas extends StatelessWidget {
  const _ToolpathCanvas({required this.segments});

  final List<ToolpathSegment> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _ToolpathPainter(segments),
          child: Center(child: segments.isEmpty ? const Text('暂无轨迹') : null),
        ),
      ),
    );
  }
}

class _ToolpathPainter extends CustomPainter {
  const _ToolpathPainter(this.segments);

  final List<ToolpathSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xffe5e7eb)
      ..strokeWidth = 1;

    for (var x = 0.0; x <= size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (segments.isEmpty) return;

    final bounds = _boundsFor(segments);
    final scale = _scaleFor(bounds, size);
    final origin = Offset(
      (size.width - bounds.width * scale) / 2,
      (size.height - bounds.height * scale) / 2,
    );

    Offset mapPoint(MachinePosition point) {
      final x = origin.dx + (point.x - bounds.left) * scale;
      final y = origin.dy + (bounds.bottom - point.y) * scale;
      return Offset(x, y);
    }

    final rapidPaint = Paint()
      ..color = const Color(0xfff97316)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final linearPaint = Paint()
      ..color = const Color(0xff2563eb)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final segment in segments) {
      final paint = segment.type == GcodeSegmentType.rapid
          ? rapidPaint
          : linearPaint;
      canvas.drawLine(mapPoint(segment.start), mapPoint(segment.end), paint);
    }
  }

  Rect _boundsFor(List<ToolpathSegment> segments) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;

    for (final segment in segments) {
      minX = math.min(minX, math.min(segment.start.x, segment.end.x));
      maxX = math.max(maxX, math.max(segment.start.x, segment.end.x));
      minY = math.min(minY, math.min(segment.start.y, segment.end.y));
      maxY = math.max(maxY, math.max(segment.start.y, segment.end.y));
    }

    if (minX == maxX) {
      minX -= 1;
      maxX += 1;
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(4);
  }

  double _scaleFor(Rect bounds, Size size) {
    const padding = 24.0;
    final availableWidth = math.max(1, size.width - padding * 2);
    final availableHeight = math.max(1, size.height - padding * 2);
    return math.min(
      availableWidth / bounds.width,
      availableHeight / bounds.height,
    );
  }

  @override
  bool shouldRepaint(covariant _ToolpathPainter oldDelegate) {
    return oldDelegate.segments != segments;
  }
}
