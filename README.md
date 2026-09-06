# gcode_core

![example](https://github.com/lizy-coding/gcode_core/blob/master/gcode_print.gif)

G-code parsing and visualization package extracted for Flutter Forge.

## First macOS prerelease: 0.2.0-dev.1

This release is distributed through GitHub/Git, not pub.dev. Pin the release tag
instead of following `dev`:

```yaml
dependencies:
  gcode_core:
    git:
      url: https://github.com/lizy-coding/gcode_core.git
      ref: v0.2.0-dev.1
```

See [release notes](docs/releases/0.2.0-dev.1.md) and
[CHANGELOG](CHANGELOG.md) for breaking changes and validation limits.

For a macOS host, use Flutter 3.47.2 and add these keys to the top-level dict in
`macos/Runner/Info.plist`:

```xml
<key>FLTEnableImpeller</key>
<true/>
<key>FLTEnableFlutterGPU</key>
<true/>
```

The host needs a macOS deployment target of at least 12.0; runtime evidence is
currently limited to macOS 26.5 on Apple Silicon. The package bundles its shader
asset automatically. Example Xcode/CocoaPods workarounds do not propagate into
consumer apps and should only be adopted if the same build issue occurs.
This is a Flutter package; its public entry point is not a pure Dart CLI API.

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
flutter run -d macos
```

IDE runs use `example/lib/main.dart` with the macOS device. The example's
Xcode and CocoaPods configurations enable the scoped compiler-probe workaround
automatically, including Debug builds. The Flutter build phase also removes
non-macOS deployment-target environment variables that conflict with clang's
Debug framework build. No global Xcode or Flutter SDK changes are required.

The example demonstrates local file selection, streaming parse snapshots,
`GcodeCanvas` drawing, `CommandTimeline`, and `PlaybackControls`.

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
