# gcode_core

![example](https://github.com/lizy-coding/gcode_core/blob/master/gcode_print.gif)

G-code parsing and visualization package extracted for Flutter Forge.

## Scope

- Read G-code from strings or files line by line.
- Parse G0/G1 commands with X/Y/F parameters.
- Collect parse errors with line metadata.
- Build incremental or batch toolpath segments.
- Render paths, grid, origin and moving markers with Flutter GPU.
- Render command timelines and playback controls for Flutter frontends.

This package does not open system file pickers or own app-level playback state.

## macOS GPU drawing

Flutter 3.47.2 or newer is required. `GcodeCanvas` is GPU-only: G0 dashes,
G1 lines, background paths, playback, grid, origin, tool head and glow are all
rendered by GPU shaders. There is no Canvas backend or automatic fallback.
Flutter only composites the resulting image and displays ordinary UI widgets.
Only macOS has been exercised in this implementation phase.

```dart
GcodeCanvas(
  segments: snapshot.segments,
  bounds: snapshot.bounds,
  progress: progress,
)
```

Treat the segment list as immutable; replace it when path data changes. Viewport
and line-width changes rebuild geometry; playback only updates GPU uniforms.
The host must enable Impeller and Flutter GPU. The macOS example contains the
required Info.plist settings. Shader sources and their compiled SDK bundle live
under `shaders/`; `python3 example/tool/build_gpu_shaders.py` regenerates them.
The macOS compatibility runner automatically runs shader compilation:

```sh
python3 example/tool/macos_run.py --mode release
python3 example/tool/macos_run.py --mode profile --target lib/gpu_validation.dart
```

The validation entry point writes GPU scene images at different progress values, runs 20
recreation/resize cycles, and measures 10,000 parsed G0/G1 segments. Its log
reports the output directory. This does not benchmark file loading or snapshots.

### API migration

Remove the former `backend` argument and `GcodeCanvasBackend` references.
`GcodeStyle` uses immutable `GcodeStroke(color, width)` values (`rapidMove`,
`rapidBackground`, `linearMove`, `linearBackground`, `grid`, `origin`) and color
fields (`toolHeadColor`, `toolHeadGlowColor`, `originDotColor`), replacing Paint
objects. Unsupported GPU initialization is reported as an error, never a
fallback renderer.

## Test

```bash
flutter test
```

## Example

Run the Flutter example app:

```bash
cd example
flutter run
```

The example demonstrates local file selection, streaming parse snapshots,
`GcodeCanvas` drawing, `CommandTimeline`, and `PlaybackControls`.

Run the console example:

```bash
dart run example/gcode_core_example.dart
```

Minimal usage:

```dart
import 'package:gcode_core/gcode_core.dart';

Future<void> main() async {
  const source = '''
G0 X0 Y0
G1 X10 Y0 F1200
G1 X10 Y10
''';

  final pipeline = GcodeReadlinePipeline();

  await for (final snapshot
      in pipeline.load(const StringGcodeLineReader(source))) {
    if (snapshot.stage == GcodeLoadStage.ready) {
      print(snapshot.commands.length);
      print(snapshot.segments.length);
      print(snapshot.errors.length);
    }
  }
}
```
