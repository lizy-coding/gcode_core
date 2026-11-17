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
}
