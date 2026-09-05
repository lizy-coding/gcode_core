# gcode_core example

Flutter example for the `gcode_core` package.

It demonstrates the full local workflow:

- Pick a local `.gcode`, `.nc`, `.tap`, or `.txt` file.
- Read the file line by line with `FileGcodeLineReader`.
- Parse supported `G0/G1` commands with `GcodeReadlinePipeline`.
- Dynamically refresh parsed snapshots while reading.
- Draw toolpath segments with the package-provided `GcodeCanvas`.
- Show `G0` jump moves as red dashed lines and `G1` cutting moves as solid paths.
- Show commands and parse errors with `CommandTimeline`.
- Preview the generated path with `PlaybackControls`.

The main integration points are:

```dart
final pipeline = GcodeReadlinePipeline(
  options: const GcodeReadlineOptions(snapshotBatchSize: 1),
);

await for (final snapshot in pipeline.load(FileGcodeLineReader(file.path))) {
  setState(() => _snapshot = snapshot);
}

GcodeCanvas(
  segments: snapshot.segments,
  progress: playbackProgress,
  errorCount: snapshot.errors.length,
);
```

Run it from this directory:

```bash
flutter run
```
# macOS 本机构建兼容入口

若 Xcode 26.6 卡在 `clang -v -E -dM`，从本目录运行：

```sh
python3 tool/macos_run.py --mode release
```

GPU 探针使用：

```sh
python3 tool/build_gpu_shaders.py
python3 tool/macos_run.py --mode profile --target lib/gpu_probe.dart
```

此入口对本次 xcodebuild 使用局部编译器探测包装，不修改系统或 Flutter SDK；常规编译与错误退出码仍来自真实 clang。GPU 探针为合成 10,000 段实验，并非完整 G-code renderer。详细限制见 [验证报告](../docs/macos-gpu-probe.md)。
