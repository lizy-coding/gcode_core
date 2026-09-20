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
    _playbackTimer?.cancel();
    loading = true;
    isPlaying = false;
    this.sourceName = sourceName;
    snapshot = null;
    status = '正在读取 $sourceName';
    _setPlaybackProgress(1);
    notifyListeners();

    await for (final next in snapshots) {
      if (_disposed) return;
      snapshot = next;
      status = next.message;
      _setPlaybackProgress(1);
      notifyListeners();
      if (next.stage == GcodeLoadStage.parsing) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }

    if (_disposed) return;
    loading = false;
    notifyListeners();
  }

  void play() {
    if ((snapshot?.segments.isEmpty ?? true) || loading) return;
    _playbackTimer?.cancel();
    if (playbackProgress.value >= 1) _setPlaybackProgress(0);
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
    if (total == 0) return;
    pause();
    _setPlaybackProgress((index + 1) / total);
  }

  void _setPlaybackProgress(double value) {
    final progress = value.clamp(0.0, 1.0).toDouble();
    playbackProgress.value = progress;
    final count = snapshot?.commands.length ?? 0;
    final index = count == 0
        ? -1
        : (progress * count).ceil().clamp(1, count) - 1;
    if (currentCommandIndex.value != index) {
      currentCommandIndex.value = index;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackTimer?.cancel();
    playbackProgress.dispose();
    currentCommandIndex.dispose();
    super.dispose();
  }
}
