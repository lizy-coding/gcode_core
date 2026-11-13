import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:gcode_core/gcode_core.dart';

class GcodeSessionController extends ChangeNotifier {
  GcodeSessionController({GcodeReadlinePipeline? pipeline})
    : _pipeline =
          pipeline ??
          GcodeReadlinePipeline(
            options: const GcodeReadlineOptions(snapshotBatchSize: 200),
          );

  static const sampleSource = '''
G0 X0 Y0
G1 X30 Y0 F1200
G1 X30 Y18
G1 X12 Y18
G0 X6 Y8
G1 X22 Y8
G2 X40 Y40
''';

  final GcodeReadlinePipeline _pipeline;
  final playbackProgress = ValueNotifier<double>(1);
  final currentCommandIndex = ValueNotifier<int>(-1);

  GcodeLoadSnapshot? snapshot;
  String sourceName = '未选择文件';
  String status = '请选择本地 G-code 文件，或加载内置示例。';
  bool loading = false;
  bool isPlaying = false;
  double speedMultiplier = 1;

  Timer? _playbackTimer;
  StreamSubscription<GcodeLoadSnapshot>? _loadSubscription;
  Completer<void>? _loadDone;
  Future<void> _loadCancellation = Future<void>.value();
  List<int> _commandSegmentCounts = const [];
  List<int> _segmentCommandIndices = const [];
  int _loadGeneration = 0;
  bool _disposed = false;

  Future<void> pickAndParseFile() async {
    const types = XTypeGroup(
      label: 'G-code',
      extensions: ['gcode', 'nc', 'tap', 'txt'],
    );
    final file = await openFile(acceptedTypeGroups: [types]);
    if (file == null || _disposed) return;
    await parseSnapshots(
      _pipeline.loadFileInBackground(file.path),
      sourceName: file.name,
    );
  }

  Future<void> loadSample() => parseSnapshots(
    _pipeline.load(const StringGcodeLineReader(sampleSource)),
    sourceName: '内置示例',
  );

  Future<void> parseSnapshots(
    Stream<GcodeLoadSnapshot> snapshots, {
    required String sourceName,
  }) async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    _playbackTimer?.cancel();
    try {
      await _cancelLoad();
    } catch (error) {
      if (!_disposed && generation == _loadGeneration) {
        _loadFailed(error);
        loading = false;
        notifyListeners();
      }
      return;
    }
    if (_disposed || generation != _loadGeneration) return;
    loading = true;
    isPlaying = false;
    this.sourceName = sourceName;
    snapshot = null;
    _commandSegmentCounts = const [];
    _segmentCommandIndices = const [];
    status = '正在读取 $sourceName';
    _setPlaybackProgress(1);
    notifyListeners();
    if (_disposed || generation != _loadGeneration) return;

    final done = Completer<void>();
    _loadDone = done;
    StreamSubscription<GcodeLoadSnapshot>? subscription;
    subscription = snapshots.listen(
      (next) {
        if (_disposed || generation != _loadGeneration) return;
        snapshot = next;
        _mapCommands(next);
        status = next.message;
        _setPlaybackProgress(1);
        notifyListeners();
        if (next.stage == GcodeLoadStage.parsing) {
          subscription?.pause(
            Future<void>.delayed(const Duration(milliseconds: 16)),
          );
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    _loadSubscription = subscription;
    try {
      await done.future;
    } catch (error) {
      if (!_disposed && generation == _loadGeneration) _loadFailed(error);
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        try {
          await _cancelLoad();
        } catch (error) {
          if (!_disposed && generation == _loadGeneration) _loadFailed(error);
        }
        if (!_disposed && generation == _loadGeneration) {
          loading = false;
          notifyListeners();
        }
      }
    }
  }

  void _loadFailed(Object error) {
    final prefix = snapshot;
    status = '读取失败: $error';
    snapshot = GcodeLoadSnapshot(
      stage: GcodeLoadStage.failed,
      commands: prefix?.commands ?? const [],
      errors: prefix?.errors ?? const [],
      segments: prefix?.segments ?? const [],
      linesRead: prefix?.linesRead ?? 0,
      message: status,
      bounds: prefix?.bounds,
      timeEstimate: prefix?.timeEstimate,
    );
  }

  void _mapCommands(GcodeLoadSnapshot next) {
    final commandIndices = {
      for (final (index, command) in next.commands.indexed)
        command.lineNumber: index,
    };
    final counts = List<int>.filled(next.commands.length, 0);
    _segmentCommandIndices = [
      for (final segment in next.segments)
        commandIndices[segment.command.lineNumber] ?? -1,
    ];
    for (final index in _segmentCommandIndices) {
      if (index >= 0) counts[index]++;
    }
    var cumulative = 0;
    _commandSegmentCounts = [for (final count in counts) cumulative += count];
  }

  Future<void> _cancelLoad() {
    final subscription = _loadSubscription;
    final done = _loadDone;
    _loadSubscription = null;
    _loadDone = null;
    final cancelled = (subscription?.cancel() ?? Future<void>.value())
        .whenComplete(() {
          if (done != null && !done.isCompleted) done.complete();
        });
    final cancellation = Future.wait<void>([
      _loadCancellation,
      cancelled,
    ]).then<void>((_) {});
    _loadCancellation = cancellation.then<void>(
      (_) {},
      onError: (Object error) {
        debugPrint('GCODE_LOAD_CANCEL_FAILED $error');
      },
    );
    return cancellation;
  }

  void play() {
    if ((snapshot?.segments.isEmpty ?? true) || loading) return;
    _playbackTimer?.cancel();
    _setPlaybackProgress(
      playbackProgress.value >= 1 ? 0 : playbackProgress.value,
    );
    isPlaying = true;
    notifyListeners();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_disposed) return;
      _setPlaybackProgress(playbackProgress.value + 0.004 * speedMultiplier);
      if (playbackProgress.value >= 1) {
        _playbackTimer?.cancel();
        isPlaying = false;
        notifyListeners();
      }
    });
  }

  void pause() {
    _playbackTimer?.cancel();
    isPlaying = false;
    notifyListeners();
  }

  void resetPlayback() {
    _playbackTimer?.cancel();
    _setPlaybackProgress(0);
    isPlaying = false;
    notifyListeners();
  }

  void seekPlayback(double value) => _setPlaybackProgress(value);

  void setSpeed(double value) {
    speedMultiplier = value;
    notifyListeners();
  }

  void selectCommand(int index) {
    final total = snapshot?.commands.length ?? 0;
    if (index < 0 || index >= total) return;
    pause();
    final segments = _segmentCommandIndices.length;
    _setPlaybackProgress(
      segments == 0 ? 0 : _commandSegmentCounts[index] / segments,
      selectedCommandIndex: index,
    );
  }

  void _setPlaybackProgress(double value, {int? selectedCommandIndex}) {
    final progress = value.clamp(0.0, 1.0).toDouble();
    playbackProgress.value = progress;
    final count = _segmentCommandIndices.length;
    // At an exact boundary highlight the just-completed motion command.
    final index =
        selectedCommandIndex ??
        (count == 0
            ? -1
            : _segmentCommandIndices[(progress * count).ceil().clamp(1, count) -
                  1]);
    if (currentCommandIndex.value != index) {
      currentCommandIndex.value = index;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    unawaited(_cancelLoad().catchError((Object _) {}));
    _playbackTimer?.cancel();
    playbackProgress.dispose();
    currentCommandIndex.dispose();
    super.dispose();
  }
}
