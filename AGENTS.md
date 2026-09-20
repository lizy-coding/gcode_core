# Agent guide

## Repository purpose

`gcode_core` parses a deliberately small G-code subset, builds two-dimensional
toolpaths, and renders them through Flutter GPU. The package is GPU-only; do not
silently introduce a second renderer or claim a platform is supported from a
successful cross-compile alone.

## Layout and ownership

- `lib/src/parser`, `models`, `services`: platform-neutral parsing and geometry.
- `lib/src/data/readers`: native file-system readers; currently uses `dart:io`.
- `lib/src/rendering`: Flutter GPU resources, geometry, surfaces, and shaders.
- `lib/src/widgets`: reusable package UI.
- `shaders`: source shaders plus the checked-in generated shader bundle.
- `example/lib/src/gcode_session_controller.dart`: example state and playback.
- `example/lib/src/gcode_example_page.dart`: page composition only.
- `example/lib/src/widgets`: independently testable example UI.
- `example/lib/gpu_validation.dart`: native GPU lifecycle/performance harness.
- `docs/evidence`: durable runtime evidence; do not rewrite historical evidence.

## Current platform contract

- macOS: primary validated GPU platform.
- Android: host and APK build are present; runtime GPU/device evidence is pending.
- iOS, Linux, Windows: not supported until hosts, builds, and native evidence land.
- Web: unsupported while `dart:io` and the GPU-only renderer remain unconditional.

Update the platform-contract CI job and this section together when adding a
host. A build is only build evidence. Runtime support requires a platform report
with device/OS, Flutter revision, artifact revision, file-picker behavior, GPU
initialization, screenshots, and frame/memory measurements.

## Change boundaries

- Keep parsing behavior out of widgets.
- Keep file-picker calls in the example controller or a platform service.
- Treat segment lists as immutable; replace the list when geometry changes.
- Reuse GPU buffers and surfaces across frames. Dispose `ui.Image` handles.
- Do not rebuild geometry for playback-only progress changes.
- Preserve unrelated evidence and generated platform files.

## Test growth order

1. Pure unit tests for parser, bounds, builders, and viewport math.
2. Controller tests for loading, playback, replay, seeking, and disposal.
3. Widget tests at 320, 600, 720, and desktop widths.
4. Android emulator integration tests for picker cancellation and sample load.
5. Native GPU profile runs using `gpu_validation.dart`.
6. Add iOS/Windows/Linux build jobs only with their corresponding host changes.

Minimum local gate from the repository root:

```sh
flutter analyze
flutter test
(cd example && flutter test)
```

Run Android builds from `example`, not the package root:

```sh
cd example
flutter build apk --debug
```

macOS uses its checked compatibility entrypoint:

```sh
cd example
python3 tool/macos_run.py --mode release --build-only
```
