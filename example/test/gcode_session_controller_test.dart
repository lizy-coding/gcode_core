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
    final commandCount = controller.snapshot!.commands.length;

    controller.selectCommand(2);

    expect(controller.currentCommandIndex.value, 2);
    expect(controller.playbackProgress.value, closeTo(3 / commandCount, 1e-9));
  });
}
