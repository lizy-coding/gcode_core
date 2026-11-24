import 'dart:async';

import 'package:example/src/gcode_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcode_core/gcode_core.dart';

void main() {
  test('loads the sample and exposes its parse error', () async {
    final controller = GcodeSessionController();
    addTearDown(controller.dispose);

    await controller.loadSample();

    expect(controller.loading, isFalse);
    expect(controller.snapshot?.stage, GcodeLoadStage.ready);
    expect(controller.snapshot?.errors, hasLength(1));
    expect(controller.sourceName, '内置示例');
  });

  test('play restarts a completed toolpath from the beginning', () async {
    final controller = GcodeSessionController();
    addTearDown(controller.dispose);
    await controller.loadSample();

    expect(controller.playbackProgress.value, 1);
    controller.play();

    expect(controller.isPlaying, isTrue);
    expect(controller.playbackProgress.value, 0);
    controller.pause();
  });

  test('selecting a command seeks playback and updates its index', () async {
    final controller = GcodeSessionController();
    addTearDown(controller.dispose);
    await controller.loadSample();
    controller.selectCommand(2);

    expect(controller.currentCommandIndex.value, 2);
    expect(controller.playbackProgress.value, 0.4);
  });

  test('disposal cancels a load waiting for its next snapshot', () async {
    var cancelled = false;
    final source = StreamController<GcodeLoadSnapshot>(
      onCancel: () => cancelled = true,
    );
    final controller = GcodeSessionController();
    final load = controller.parseSnapshots(
      source.stream,
      sourceName: 'slow.nc',
    );
    await Future<void>.delayed(Duration.zero);

    controller.dispose();

    expect(cancelled, isTrue);
    await load;
    await source.close();
  });

  test(
    'a replacement requested while notifying skips the superseded source',
    () async {
      var sourceStarted = false;
      final source = StreamController<GcodeLoadSnapshot>(
        onListen: () => sourceStarted = true,
      );
      final controller = GcodeSessionController();
      addTearDown(controller.dispose);
      Future<void>? replacement;
      controller.addListener(() {
        if (controller.sourceName == 'old.nc' && replacement == null) {
          replacement = controller.parseSnapshots(
            const Stream<GcodeLoadSnapshot>.empty(),
            sourceName: 'new.nc',
          );
        }
      });
      final load = controller.parseSnapshots(
        source.stream,
        sourceName: 'old.nc',
      );
      await Future<void>.delayed(Duration.zero);

      try {
        expect(source.hasListener, isFalse);
        await replacement;
        expect(controller.sourceName, 'new.nc');
        expect(controller.loading, isFalse);
      } finally {
        final cleanup = sourceStarted ? null : source.stream.listen(null);
        await source.close();
        await cleanup?.cancel();
        await load;
      }
    },
  );

  test(
    'a stream failure restores loading and marks its prefix incomplete',
    () async {
      final prefix = await GcodeReadlinePipeline()
          .load(const StringGcodeLineReader('G1 X10 F600'))
          .last;
      final controller = GcodeSessionController();
      addTearDown(controller.dispose);
      Stream<GcodeLoadSnapshot> failingLoad() async* {
        yield prefix;
        throw StateError('read interrupted');
      }

      await controller.parseSnapshots(failingLoad(), sourceName: 'broken.nc');

      expect(controller.loading, isFalse);
      expect(controller.snapshot?.stage, GcodeLoadStage.failed);
      expect(controller.snapshot?.segments, hasLength(1));
      expect(controller.snapshot?.estimatedSeconds, isNull);
      expect(controller.status, contains('read interrupted'));
    },
  );

  test('a replacement load waits until the old source has stopped', () async {
    final cancellation = Completer<void>();
    final oldSource = StreamController<GcodeLoadSnapshot>(
      onCancel: () => cancellation.future,
    );
    var replacementStarted = false;
    final replacement = StreamController<GcodeLoadSnapshot>(
      onListen: () => replacementStarted = true,
    );
    final controller = GcodeSessionController();
    addTearDown(controller.dispose);
    final oldLoad = controller.parseSnapshots(
      oldSource.stream,
      sourceName: 'old.nc',
    );
    await Future<void>.delayed(Duration.zero);

    final newLoad = controller.parseSnapshots(
      replacement.stream,
      sourceName: 'new.nc',
    );
    oldSource.add(GcodeLoadSnapshot.empty());
    await Future<void>.delayed(Duration.zero);
    expect(replacementStarted, isFalse);

    cancellation.complete();
    await oldLoad;
    await Future<void>.delayed(Duration.zero);
    expect(replacementStarted, isTrue);
    replacement.add(
      await GcodeReadlinePipeline()
          .load(const StringGcodeLineReader('G1 X42'))
          .last,
    );
    await replacement.close();
    await newLoad;

    expect(controller.sourceName, 'new.nc');
    expect(controller.snapshot?.segments.single.end.x, 42);
    expect(controller.loading, isFalse);
    await oldSource.close();
  });

  test(
    'selecting a motion command stops at its actual trajectory endpoint',
    () async {
      final controller = GcodeSessionController();
      addTearDown(controller.dispose);
      await controller.parseSnapshots(
        GcodeReadlinePipeline().load(
          const StringGcodeLineReader('G90\nG1 X10\nG1 X20'),
        ),
        sourceName: 'mixed.nc',
      );

      controller.selectCommand(1);

      expect(controller.playbackProgress.value, 0.5);
      expect(controller.currentCommandIndex.value, 1);
    },
  );

  test(
    'non-motion commands keep their selection at the preceding endpoint',
    () async {
      final controller = GcodeSessionController();
      addTearDown(controller.dispose);
      await controller.parseSnapshots(
        GcodeReadlinePipeline().load(
          const StringGcodeLineReader(
            'G90\nG1 X10\nG1 F600\nG1 X10\nG91\nG1 X10',
          ),
        ),
        sourceName: 'non-motion.nc',
      );

      controller.selectCommand(0);
      expect(controller.playbackProgress.value, 0);
      expect(controller.currentCommandIndex.value, 0);
      for (final index in [2, 3, 4]) {
        controller.selectCommand(index);
        expect(controller.playbackProgress.value, 0.5);
        expect(controller.currentCommandIndex.value, index);
      }

      for (final (progress, index) in <(double, int)>[
        (0, 1),
        (0.25, 1),
        (0.5, 1),
        (0.5001, 5),
        (1, 5),
      ]) {
        controller.seekPlayback(progress);
        expect(controller.currentCommandIndex.value, index);
      }
    },
  );

  test(
    'starting playback highlights motion instead of a selected feed command',
    () async {
      final controller = GcodeSessionController();
      addTearDown(controller.dispose);
      await controller.parseSnapshots(
        GcodeReadlinePipeline().load(
          const StringGcodeLineReader('G1 X10\nG1 F600\nG1 X20'),
        ),
        sourceName: 'feed.nc',
      );
      controller.selectCommand(1);

      controller.play();

      expect(controller.currentCommandIndex.value, 0);
      controller.pause();
    },
  );
}
