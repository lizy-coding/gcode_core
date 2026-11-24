# Agent guide

## Repository purpose

`gcode_core` parses a deliberately small G-code subset, builds two-dimensional
toolpaths, and renders them through Flutter GPU. The package is GPU-only; do not
silently introduce a second renderer or claim a platform is supported from a
successful cross-compile alone.

## Layout and ownership

- `lib/src/parser`, `lib/src/core`, `lib/src/models`, `lib/src/services`: parsing and toolpath modeling.
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

- macOS: macOS 12+, with Impeller and Flutter GPU enabled in the host.
- Android: API 29+ and ARM64-only, with Impeller enabled and
  `io.flutter.embedding.android.EnableFlutterGPU=true` inside the host
  application. Do not add ARM32 or x86 compatibility without an explicit
  product decision.
- iOS, Linux, Windows: not supported until hosts, builds, and native evidence land.
- Web: unsupported while `dart:io` and the GPU-only renderer remain unconditional.

The maintainer confirmed macOS and Android manual acceptance for 0.2.1;
`docs/evidence/0.2.1-maintainer-acceptance.md` records the source baseline and
the limits of that confirmation. Device/OS, API-level coverage, Flutter
revision, picker results, screenshots, and frame/memory measurements remain
unrecorded. The macOS GPU-only report is historical evidence and does not bind
the current revision to detailed runtime acceptance. Sustained 60 fps and
long-running GPU memory stability are not asserted.

Update the platform-contract CI job and this section together when adding a
host. A build is only build evidence. Runtime support requires a platform report
with device/OS, Flutter revision, artifact revision, file-picker behavior, GPU
initialization, screenshots, and frame/memory measurements.

## Change boundaries

- Keep parsing behavior out of widgets.
- `gcode_time_estimator.dart` owns the independent BSL demo timing model; all
  loading paths must use the same streaming accumulator. Public timing APIs
  are exported through `lib/gcode_time.dart` and the main entrypoint; keep the
  timing-only entrypoint free of Flutter/GPU imports. File/stream APIs own one
  subscription and propagate read failures instead of returning partial success. Keep timing issues
  separate from renderer parse errors and never display incomplete totals as
  full machining time. Timing is not calibrated device or GPU evidence.
- Keep file-picker calls in the example controller or a platform service.
- Treat segment lists as immutable; replace the list when geometry changes.
- Reuse GPU buffers and surfaces across frames. Dispose `ui.Image` handles.
- Playback-only progress changes update uniforms and foreground draw counts;
  do not rebuild geometry. Keep the full background path and preserve prefix
  vertex counts for degenerate segments.
- Clear GPU resources on renderer failure and disposal. Maintain shader
  sources together with the compiled bundle.
- Preserve unrelated evidence and generated platform files.

## Test growth order

1. Pure unit tests for parser, bounds, builders, and viewport math.
2. Controller tests for loading, playback, replay, seeking, and disposal.
3. Widget tests at 320, 600, 720, and desktop widths.
4. Android ARM64 API 29 and API 35 integration tests for picker cancellation
   and sample load. Do not use x86/x86_64 emulator evidence.
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
flutter build apk --debug --target-platform android-arm64
```

macOS uses its checked compatibility entrypoint:

```sh
cd example
python3 tool/macos_run.py --mode release --build-only
```

## Agent Hub exploration

When managed by Agent Hub, start with the `gcode-core` project registration
and adapter context. Confirm its runtime repository path, current HEAD,
worktree status, and recent changed filenames before selecting evidence.
Read `AGENTS.md`, `pubspec.yaml`, and `.github/workflows/ci.yml`, then inspect
only the named evidence files needed for the task. Broaden inspection only
for a concrete unresolved question; do not begin with a full repository
scan or registry refresh.

The package owns parsing, toolpath modeling, native line readers, and GPU
rendering. Native readers use `dart:io`; file-picker behavior and app playback
state remain owned by the example or consuming application. Forge release
platforms do not expand this package platform contract.

Resolve the current version from `pubspec.yaml`. Project manual acceptance
only from the matching version evidence document and its explicit
confirmation; missing or mismatched evidence remains unknown. Keep manual
confirmation, historical runtime evidence, current detailed acceptance, and
CI build evidence separate. Agent Hub planning tasks must retain empty
allowed operations and write paths until an authorized implementation task
defines their scope.
