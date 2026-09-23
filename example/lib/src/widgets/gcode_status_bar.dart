import 'package:flutter/material.dart';

class GcodeStatusBar extends StatelessWidget {
  const GcodeStatusBar({
    super.key,
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
