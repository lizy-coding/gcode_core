import 'package:flutter/material.dart';
import 'package:gcode_core/gcode_core.dart';

class GcodeResultPanel extends StatelessWidget {
  const GcodeResultPanel({
    super.key,
    required this.snapshot,
    required this.currentIndex,
    required this.onCommandTap,
  });

  final GcodeLoadSnapshot? snapshot;
  final int currentIndex;
  final ValueChanged<int> onCommandTap;

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
        CommandTimeline(
          commands: current.commands,
          errors: current.errors,
          currentIndex: currentIndex,
          onTap: onCommandTap,
          maxHeight: 360,
        ),
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
