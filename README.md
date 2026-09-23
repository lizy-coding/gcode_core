# gcode_core

![example](https://github.com/lizy-coding/gcode_core/blob/master/gcode_print.gif)

G-code parsing, streaming toolpath construction, playback UI, and Flutter GPU
visualization for Flutter applications.

## Install

Version 0.2.0 is published on pub.dev:

```yaml
dependencies:
  gcode_core: ^0.2.0
```

Flutter 3.47.2 or newer is required. The package bundles its compiled shader
asset; consumers do not need to copy shader files manually.

## Platform support

| Platform | Status | Requirements |
| --- | --- | --- |
| macOS | Supported | macOS 12+, Impeller and Flutter GPU enabled |
| Android | Supported | API 29+, ARM64, Impeller and Flutter GPU enabled |
| iOS | Not supported | No validated host contract in 0.2.0 |
| Windows | Not supported | Flutter GPU renderer is not admitted in 0.2.0 |
| Linux | Not supported | No validated host contract in 0.2.0 |
| Web | Not supported | The renderer and file reader use native-only APIs |

Unsupported platforms do not imply that parsing concepts are platform-specific;
the published package as a whole includes a GPU-only Flutter renderer and is
released only against the hosts listed as supported.

### Host configuration

For a macOS host, use Flutter 3.47.2 and add these keys to the top-level dict in
`macos/Runner/Info.plist`:

```xml
<key>FLTEnableImpeller</key>
<true/>
<key>FLTEnableFlutterGPU</key>
<true/>
```

The macOS deployment target must be at least 12.0. On Android, use a minimum SDK
of 29, build for `arm64-v8a`, and keep Impeller enabled. The example project is
the reference host configuration for both platforms. Example Xcode/CocoaPods
workarounds do not propagate into consumer apps and should only be adopted if
the same build issue occurs.

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
The renderer has no Canvas fallback. Unsupported GPU initialization is surfaced
as an error so applications can provide an explicit unavailable state.

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

## Validation

```bash
flutter test
(cd example && flutter test)
```

CI keeps separate quality, Android build, macOS build, and platform-contract
jobs. Android is deliberately constrained to API 29+ and `arm64-v8a`. Native
acceptance evidence remains platform-specific; adding a new host requires its
own build, runtime, rendering, lifecycle, and performance evidence. See
`AGENTS.md` for the admission contract.

## Example

Run the Flutter example app:

```bash
cd example
flutter run -d macos
# or an API 29+ ARM64 Android device
flutter run -d <android-device-id>
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

## License

MIT. See [LICENSE](LICENSE).
