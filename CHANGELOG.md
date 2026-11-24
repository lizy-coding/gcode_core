# Changelog

## 0.3.0 — 2026-11-21

- Add GPU exposure-bitmap and mixed toolpath previews with a shared playback timeline.
- Bound loading preview work and apply backpressure during background parsing.
- Track GPU render submissions and budget per-frame uniforms.

- Export a timing-only public entrypoint and direct UTF-8 file/line-stream APIs.

- Add streaming demo-based machining estimates, including G0 travel, G25
  exposure/jump delay, axis moves and explicit waits.
- Expose timing and diagnostics in load snapshots and the example result panel.
- Share the loading pipeline across direct and background entrypoints.
- Align timing parameter and comment handling with parsing, and restore G0
  mode after excluded homing commands.
- Normalize CR/LF/CRLF input and propagate background configuration failures.
- Isolate concurrent loads and cancel example loads on replacement or disposal.
- Map command selection to motion segments and cache playback legend counts.
- Add optional GPU first-frame and failure callbacks for consuming hosts.

## 0.2.1 — 2026-09-30

- Enable Flutter GPU explicitly in the Android example host.
- Reduce playback draw work by submitting foreground vertices only through the active segment.
- Add regression coverage for playback vertex counts.
- Document Android GPU host configuration.
- macOS and Android manual acceptance confirmed by the maintainer for this release.

## 0.2.0 — 2026-09-23

First stable package release. It promotes the Flutter GPU renderer from the
macOS prerelease and adds the Android API 29+ ARM64 host contract, adaptive
example UI, session-controller extraction, and CI coverage for package tests,
Android builds, macOS builds, and declared platform support.

### Platform support

- macOS: Flutter GPU runtime baseline validated.
- Android: API 29+ ARM64 host, build, and physical-device runtime validated.
- Web, Windows, Linux, and iOS: not supported by the GPU renderer in this
  release.

## 0.2.0-dev.1 — 2026-09-06

First macOS prerelease, distributed by Git tag / GitHub Release.

### Added

- GPU-only G0/G1 paths, dashed rapid movement, background paths, playback, grid,
  origin, tool head and glow, rendered into one Flutter GPU image surface.
- Packaged Metal/Vulkan/GLES shader variants and native macOS validation tools.
- Immutable GcodeStroke values and a shared viewport transform.

### Breaking changes from 0.1.0 / 7a52281

- Flutter 3.47.2+ is required; this release is validated on 3.47.2.
- Hosts must enable Impeller and Flutter GPU; there is no Canvas fallback.
- GcodeStyle Paint fields are replaced with stroke/color values. Arbitrary Paint
  properties and in-place Paint mutation are no longer supported.
- Replace segment lists when changing path data; GPU geometry is identity-cached.
- Coordinate correction, clipping, antialiasing and empty-state/legend changes
  may require updating screenshot expectations.

GcodeCanvas's main constructor inputs are unchanged from 7a52281. The removed
backend argument / GcodeCanvasBackend only existed in an intermediate development
iteration. Parsing, toolpath-building and snapshot public APIs are unchanged.

### Fixed

- Nonzero/negative Y coordinate mapping.
- Explicit RGBA8 surface format, premultiplied-alpha blending and pipeline
  binding reset between path and guide shaders.
- Scoped example Xcode compiler-probe workaround for ordinary Flutter/IDE runs;
  clear unrelated deployment-target variables in Flutter's macOS build phase.

### Known limitations

- Only macOS has runtime evidence. Windows/Android shader compilation is not
  equivalent to device support; no cross-platform stable-support claim is made.
- Sustained 10,000-segment 60 fps remains unverified for the GPU-only version.
- Long-running GPU memory behavior, device/driver coverage and file/snapshot
  performance are not release guarantees.
- No pub.dev publication; publish_to remains none.
