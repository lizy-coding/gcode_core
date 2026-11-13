import 'dart:async';

/// Requires a presented GPU frame and retains every failure during a run.
class GpuValidationMonitor {
  Completer<void> _firstFrame = Completer<void>();
  Object? _failure;
  bool _presented = false;

  bool get isReady => _presented && _failure == null;
  Object? get failure => _failure;

  /// Starts a new mounted scene without forgetting an earlier GPU failure.
  void beginScene() {
    _firstFrame = Completer<void>();
    _presented = false;
  }

  void presented() {
    if (_failure != null) return;
    _presented = true;
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  void failed(Object error) {
    _failure ??= error;
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  void check() {
    if (_failure != null) throw StateError('GPU validation failed: $_failure');
  }

  Future<void> waitForReady({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    check();
    try {
      await _firstFrame.future.timeout(timeout);
    } on TimeoutException catch (error) {
      failed(error);
      rethrow;
    }
    check();
  }
}
