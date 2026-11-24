import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

void main() {
  test('concurrent default loads keep their own geometry bounds and timing',
      () async {
    final pipeline = GcodeReadlinePipeline(
      options: const GcodeReadlineOptions(snapshotBatchSize: 1),
    );
    final firstSource = StreamController<GcodeLineRecord>();
    final secondSource = StreamController<GcodeLineRecord>();
    final first = StreamIterator(
      pipeline.load(_StreamGcodeLineReader(firstSource.stream)),
    );
    final second = StreamIterator(
      pipeline.load(_StreamGcodeLineReader(secondSource.stream)),
    );
    addTearDown(() async {
      await first.cancel();
      await second.cancel();
      await firstSource.close();
      await secondSource.close();
    });

    await first.moveNext();
    firstSource.add(_record(1, 'G0 F600 X10'));
    await first.moveNext();
    await second.moveNext();
    secondSource.add(_record(1, 'G0 F600 X100'));
    await second.moveNext();
    firstSource.add(_record(2, 'G0 X20'));
    await first.moveNext();

    expect(first.current.segments.last.start.x, 10);
    expect(first.current.segments.last.end.x, 20);
    expect(first.current.bounds!.maxX, 20);
    expect(first.current.timeEstimate!.knownSeconds, 2);
    expect(second.current.segments.single.start.x, 0);
    expect(second.current.segments.single.end.x, 100);
    expect(second.current.bounds!.maxX, 100);
  });

  test('injected builders reject overlap and are reusable after cancellation',
      () async {
    final builder = IncrementalToolpathBuilder();
    final pipeline = GcodeReadlinePipeline(
      toolpathBuilder: builder,
      options: const GcodeReadlineOptions(snapshotBatchSize: 1),
    );
    var cancelled = false;
    final source = StreamController<GcodeLineRecord>(
      onCancel: () => cancelled = true,
    );
    final active = StreamIterator(
      pipeline.load(_StreamGcodeLineReader(source.stream)),
    );
    addTearDown(() async {
      await active.cancel();
      await source.close();
    });
    await active.moveNext();
    source.add(_record(1, 'G0 F600 X10'));
    await active.moveNext();

    await expectLater(
      pipeline.load(const StringGcodeLineReader('G0 F600 X100')).toList(),
      throwsStateError,
    );
    expect(builder.current.x, 10);
    await active.cancel();
    expect(cancelled, isTrue);
    final reused =
        await pipeline.load(const StringGcodeLineReader('G0 F600 X2')).last;
    expect(reused.stage, GcodeLoadStage.ready);
    expect(reused.segments.single.start.x, 0);
    expect(reused.segments.single.end.x, 2);
    expect(builder.current.x, 2);
  });

  test('injected builders are reusable after a read failure and completed load',
      () async {
    final builder = IncrementalToolpathBuilder();
    final pipeline = GcodeReadlinePipeline(toolpathBuilder: builder);
    final failed = await pipeline
        .load(_StreamGcodeLineReader(
          Stream<GcodeLineRecord>.error(StateError('read failed')),
        ))
        .last;
    expect(failed.stage, GcodeLoadStage.failed);
    expect(failed.estimatedSeconds, isNull);
    for (final x in [2, 3]) {
      final loaded =
          await pipeline.load(StringGcodeLineReader('G0 F600 X$x')).last;
      expect(loaded.stage, GcodeLoadStage.ready);
      expect(loaded.segments.single.start.x, 0);
      expect(loaded.segments.single.end.x, x);
      expect(builder.current.x, x);
    }
  });

  test('an injected builder cannot be occupied by two pipeline instances',
      () async {
    final builder = IncrementalToolpathBuilder();
    final firstPipeline = GcodeReadlinePipeline(
      toolpathBuilder: builder,
      options: const GcodeReadlineOptions(snapshotBatchSize: 1),
    );
    final secondPipeline = GcodeReadlinePipeline(toolpathBuilder: builder);
    final source = StreamController<GcodeLineRecord>();
    final active = StreamIterator(
      firstPipeline.load(_StreamGcodeLineReader(source.stream)),
    );
    addTearDown(() async {
      await active.cancel();
      await source.close();
    });
    await active.moveNext();
    source.add(_record(1, 'G0 F600 X10'));
    await active.moveNext();
    await expectLater(
      secondPipeline.load(const StringGcodeLineReader('G0 F600 X2')).toList(),
      throwsStateError,
    );
    await active.cancel();
    final reused = await secondPipeline
        .load(const StringGcodeLineReader('G0 F600 X2'))
        .last;
    expect(reused.segments.single.start.x, 0);
    expect(builder.current.x, 2);
  });

  test('initial-snapshot cancellation releases an injected builder', () async {
    final builder = IncrementalToolpathBuilder();
    final pipeline = GcodeReadlinePipeline(toolpathBuilder: builder);
    final initial =
        await pipeline.load(const StringGcodeLineReader('G0 F600 X10')).first;
    expect(initial.stage, GcodeLoadStage.reading);
    final reused =
        await pipeline.load(const StringGcodeLineReader('G0 F600 X2')).last;
    expect(reused.stage, GcodeLoadStage.ready);
    expect(builder.current.x, 2);
  });

  test('invalid timing options release an injected builder before propagating',
      () async {
    final builder = IncrementalToolpathBuilder();
    final invalid = GcodeReadlinePipeline(
      toolpathBuilder: builder,
      options: const GcodeReadlineOptions(
        timeOptions: GcodeTimeOptions(pulsePerMm: 0),
      ),
    );
    await expectLater(
      invalid.load(const StringGcodeLineReader('G0 F600 X10')).toList(),
      throwsArgumentError,
    );
    final loaded = await GcodeReadlinePipeline(toolpathBuilder: builder)
        .load(const StringGcodeLineReader('G0 F600 X2'))
        .last;
    expect(loaded.stage, GcodeLoadStage.ready);
    expect(builder.current.x, 2);
  });

  test(
      'cancelled background loads finish promptly and the pipeline is reusable',
      () async {
    final pipeline = GcodeReadlinePipeline(
      options: const GcodeReadlineOptions(snapshotBatchSize: 1),
    );
    final source = List.filled(2000, 'G0 F600 X10').join('\n');
    final active = StreamIterator(pipeline.loadStringInBackground(source));
    final reused =
        StreamIterator(pipeline.loadStringInBackground('G0 F600 X2'));
    const timeout = Duration(seconds: 3);
    try {
      expect(await active.moveNext().timeout(timeout), isTrue);
      expect(active.current.stage, GcodeLoadStage.reading);
      expect(await active.moveNext().timeout(timeout), isTrue);
      expect(active.current.stage, GcodeLoadStage.parsing);
      await active.cancel().timeout(timeout);

      GcodeLoadSnapshot? complete;
      while (await reused.moveNext().timeout(timeout)) {
        complete = reused.current;
      }
      expect(complete!.stage, GcodeLoadStage.ready);
      expect(complete.estimatedSeconds, 0.2);
      expect(complete.segments.single.start.x, 0);
      expect(complete.segments.single.end.x, 2);
    } finally {
      await active.cancel().timeout(timeout);
      await reused.cancel().timeout(timeout);
    }
  });
}

GcodeLineRecord _record(int line, String source) => GcodeLineRecord(
      lineNumber: line,
      rawLine: source,
      byteOffset: 0,
    );

class _StreamGcodeLineReader implements GcodeLineReader {
  const _StreamGcodeLineReader(this.stream);

  final Stream<GcodeLineRecord> stream;

  @override
  Stream<GcodeLineRecord> readLines() => stream;
}
