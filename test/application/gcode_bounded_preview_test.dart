import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

void main() {
  test('bounded previews stay immutable and terminal data is complete',
      () async {
    final source = List.generate(100, (i) => 'G1 X${i + 1} F600').join('\n');
    final snapshots = await GcodeReadlinePipeline(
      options:
          const GcodeReadlineOptions(snapshotBatchSize: 10, previewLimit: 10),
    ).load(StringGcodeLineReader(source)).toList();
    final previews =
        snapshots.where((s) => s.stage == GcodeLoadStage.parsing).toList();
    expect(previews.every((s) => s.segments.length == 10), isTrue);
    expect(identical(previews.first.segments, previews.last.segments), isTrue);
    expect(() => previews.first.segments.clear(), throwsUnsupportedError);
    expect(snapshots.last.segments.length, 100);
    expect(snapshots.last.commands.length, 100);
    expect(snapshots.last.estimatedSeconds, isNotNull);
  });

  test('background acknowledgements preserve every batch and cancellation',
      () async {
    final source = List.generate(100, (i) => 'G1 X${i + 1}').join('\n');
    final pipeline = GcodeReadlinePipeline(
      options:
          const GcodeReadlineOptions(snapshotBatchSize: 10, previewLimit: 10),
    );
    var count = 0;
    await for (final snapshot in pipeline.loadStringInBackground(source)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      count++;
      if (snapshot.stage == GcodeLoadStage.ready)
        expect(snapshot.segments.length, 100);
    }
    expect(count, 12);
    await pipeline.loadStringInBackground(source).take(2).drain<void>();
  });
  for (final background in [false, true]) {
    test('preview uses one source prefix (background=$background)', () async {
      final source = [
        ...List.filled(10, 'G90'),
        ...List.generate(30, (i) => 'G1 X${i + 1} F600'),
      ].join('\n');
      final pipeline = GcodeReadlinePipeline(
          options: const GcodeReadlineOptions(
        snapshotBatchSize: 20,
        previewLimit: 12,
      ));
      final snapshots = await (background
              ? pipeline.loadStringInBackground(source)
              : pipeline.load(StringGcodeLineReader(source)))
          .toList();
      final previews =
          snapshots.where((s) => s.stage == GcodeLoadStage.parsing).toList();
      for (final preview in previews) {
        expect(preview.previewLineLimit, 12);
        expect(preview.commands.length, 12);
        expect(preview.segments.length, 2);
        expect(
            preview.segments.every((s) => preview.commands
                .any((c) => c.lineNumber == s.command.lineNumber)),
            isTrue);
        expect(preview.bounds!.maxX, 2);
        expect(preview.commandCount, preview.linesRead);
        expect(preview.segmentCount, preview.linesRead - 10);
      }
      expect(snapshots.last.previewLineLimit, isNull);
      expect(snapshots.last.segments.length, 30);
      expect(snapshots.last.bounds!.maxX, 30);
    });

    test(
        'timing issues stay bounded and terminal diagnostics are complete (background=$background)',
        () async {
      final source = List.filled(1000, 'G2 X1').join('\n');
      final pipeline = GcodeReadlinePipeline(
          options: const GcodeReadlineOptions(
        snapshotBatchSize: 100,
        previewLimit: 10,
      ));
      final snapshots = await (background
              ? pipeline.loadStringInBackground(source)
              : pipeline.load(StringGcodeLineReader(source)))
          .toList();
      for (final snapshot
          in snapshots.where((s) => s.stage == GcodeLoadStage.parsing)) {
        expect(snapshot.errors.length, 10);
        expect(snapshot.errorCount, snapshot.linesRead);
        expect(snapshot.timeEstimate!.issues.length, 10);
        expect(snapshot.timeEstimate!.issueCount, snapshot.linesRead);
        expect(snapshot.timeEstimate!.issuesTruncated, isTrue);
        expect(snapshot.timeEstimate!.estimatedSeconds, isNull);
      }
      expect(snapshots.last.errors.length, 1000);
      expect(snapshots.last.timeEstimate!.issues.length, 1000);
      expect(snapshots.last.timeEstimate!.issuesTruncated, isFalse);
      expect(snapshots.last.estimatedSeconds, isNull);
    });
  }

  test('zero diagnostic preview cannot make an incomplete estimate complete',
      () {
    final estimator = GcodeTimeEstimator()..append('G2 X1');
    final preview = estimator.snapshotWithIssueLimit(0);
    expect(preview.issues, isEmpty);
    expect(preview.issueCount, 1);
    expect(preview.isComplete, isFalse);
    expect(preview.estimatedSeconds, isNull);
    expect(() => estimator.snapshotWithIssueLimit(-1), throwsArgumentError);
  });
}
