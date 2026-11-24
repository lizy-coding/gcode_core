import 'dart:async';

import 'package:example/src/gpu_validation_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a GPU failure prevents success even if readiness arrives later',
    () async {
      final monitor = GpuValidationMonitor();
      monitor.failed(StateError('GPU unavailable'));
      monitor.presented();
      await expectLater(monitor.waitForReady(), throwsStateError);
      expect(monitor.isReady, isFalse);
    },
  );

  test('a first-frame timeout cannot turn into a late success', () async {
    final monitor = GpuValidationMonitor();
    await expectLater(
      monitor.waitForReady(timeout: const Duration(milliseconds: 1)),
      throwsA(isA<TimeoutException>()),
    );
    monitor.presented();
    expect(monitor.isReady, isFalse);
    expect(monitor.check, throwsStateError);
  });

  test('each mounted scene needs a presented frame and retains prior failures',
      () async {
    final monitor = GpuValidationMonitor();
    monitor.presented();
    await monitor.waitForReady();
    expect(monitor.isReady, isTrue);
    monitor.beginScene();
    expect(monitor.isReady, isFalse);
    monitor.presented();
    await monitor.waitForReady();
    monitor.failed(StateError('draw failed'));
    monitor.beginScene();
    monitor.presented();
    await expectLater(monitor.waitForReady(), throwsStateError);
  });
}
