# Flutter 3.47.2 三端差异与 macOS 原型记录

日期：2026-09-05。用户确认优先调查端能力差异，再在 macOS 实现验证。首期 10,000 段、60 fps；其他设备范围暂不设门槛。

## 最新结果：构建阻塞已有项目级解决路径

本轮已实际完成 Profile GPU 窗口、普通 G-code Release 窗口及 GPU Release 窗口验证。下文最初 BLOCKED 记录保留为排查历史；不再代表当前可运行状态。

Xcode 的 compiler probe 存在管道输出阻塞：clang 卡在 write，SwiftBuild service 等待；直接执行 clang 正常。将探测输出先完整收集，再去除成功探测 stderr 中的内部 `-cc1` 命令回显后，构建成功。此处理仅用于 `-v -E -dM ... /dev/null`，stdout 宏定义、版本诊断和退出码保留；正常编译直接 exec 原始 clang。对宏输出相等、真实 C 文件编译、错误诊断/退出码已验证。底层 SwiftBuild 管道调度问题的具体根因仍未确定，因此这是本机 Xcode 的有界兼容处理，不声称修复了 Xcode 本身。

持久化工具：`example/tool/macos_run.py` 配合 `tool/macos/compiler_probe.py`，仅在本次 xcodebuild 命令设置 CC；不修改 SDK、系统权限或全局编译器。真实编译器由外层 xcrun 解析后通过任务专用环境变量传入。包装文件保留 `.py` 名称；早期命名为 `clang` 的尝试仍发生阻塞，未作为交付路径。Xcode 会提示包装编译器未识别/显式模块支持受限，这是采用兼容工具的构建代价。

普通 Flutter 命令尚不自动使用此兼容处理；本机遇到卡点时使用以下命令（仓库根目录）：

```sh
# 普通 G-code 应用
python3 example/tool/macos_run.py --mode release
# GPU 吞吐探针
python3 example/tool/macos_run.py --mode profile --target lib/gpu_probe.dart
# GPU Release 构建；去掉 --build-only 可直接运行
python3 example/tool/macos_run.py --mode release --target lib/gpu_probe.dart --build-only
```

工具面向本次 Apple Silicon macOS，原生窗口由应用自身创建。普通 Release 的真实窗口已加载内置示例：7 行、6 指令、5 段轨迹、1 个预期 G2 错误，实线/虚线/刀头及错误提示均可见；GPU Release 独立执行时日志确认 MetalSDF、GPU_PROBE_READY，截图确认 10,000 段可见。

### 性能结果与限制

以下均为 1600×1088 物理绘制面积、5 秒预热后 60 秒采样的合成实线探针。不是实际文件解析或完整 GPU G-code 功能的验收。

| Profile 轮次 | 帧数 | UI p95 ms | Raster p95 ms | 超 16.67ms 比例 | 判定 |
| --- | ---: | ---: | ---: | ---: | --- |
| 1 | 25 | 0.783 | 0.754 | 0 | 帧数不足，无效性能样本 |
| 2 | 3602 | 0.881 | 0.823 | 0 | 本轮约 60fps，满足首期探针目标 |
| 3 | 1951 | 0.460 | 0.738 | 0.0513% | 帧数不足，不用于稳定 60fps 结论 |

窗口激活/可见性和运行期间其他工作会影响采样。第 1、3 轮保留原始证据，不能仅凭 p95 较低判 PASS；没有足够证据将第 3 轮低帧数完全归因于窗口状态。已取得一次有效 60fps 样本，尚未取得三次连续受控通过。后续正式性能验收应在专用、不切换应用的会话重复，并加入实际 G-code、Canvas 对照、加载中渲染和内存测量。

证据：[run1](evidence/macos-gpu-profile-run1.txt)、[run2](evidence/macos-gpu-profile-run2.txt)、[run3](evidence/macos-gpu-profile-run3.txt)、[普通 Release 构建](evidence/gcode-release-durable.txt)。

## 实际环境

`/Users/forest/development/flutter`：stable 3.47.2，Framework `d3b14c8769`，Engine `a804b26164`，Dart 3.13.2；macOS 26.5 arm64，Xcode 26.6。

## 三端差异：来自本机锁定版本源码

以下路径均相对 Flutter SDK 的 `engine/src/flutter/`，是静态证据，不代表三端运行验收。

| 项目 | macOS | Windows | Android | 维护策略 |
| --- | --- | --- | --- | --- |
| 启动 | `FLTEnableFlutterGPU`；Impeller 默认开启 | `DartProject.set_enable_flutter_gpu(true)`，引擎转启动参数 | `io.flutter.embedding.android.EnableFlutterGPU` 元数据 | 差异集中在宿主配置 |
| 后端路径 | Metal | Windows engine 使用 OpenGL/ANGLE，不应假定 Vulkan | Impeller/Vulkan；设备和渲染器回退须实测 | Dart 绘制统一；不直接调用平台图形 API |
| shader | Metal 变体 | GLES 变体 | Vulkan 变体，其他后端需能力验证 | 同一 GLSL 源编译多变体 shader bundle |
| MSAA | 按设备能力选择 | GLES 的 offscreen/implicit resolve 支持须查询 | 驱动与设备能力须查询 | 首个探针单采样，后续统一 shader 抗锯齿或能力分支 |
| 高级 buffer/纹理能力 | 不作为三端共同前提 | GLES `SupportsSSBO()` 返回 false，blit/MSAA 有能力开关 | 不按高端 Vulkan 功能建立最低契约 | 首期仅顶点/索引、uniform、基础颜色目标 |
| 生命周期 | resize、DPR、窗口退出 | resize、DPI、窗口/驱动变化 | 后台恢复、surface 重建 | 共用资源所有权模型，宿主触发恢复 |

证据位置：`shell/platform/darwin/macos/framework/Source/FlutterDartProject.mm`、`shell/platform/windows/client_wrapper/include/flutter/dart_project.h`、`shell/platform/windows/flutter_windows_engine.cc`、`shell/platform/android/io/flutter/embedding/engine/FlutterEngineFlags.java`、`lib/gpu/shader_library.cc`、`impeller/renderer/backend/gles/capabilities_gles.cc`。

结论：首期没有发现必须维护三套绘制业务实现的依据。统一应建立在基础图形能力上，而不是要求各平台驱动特性相同；Windows 的 GLES 路径是设计共同能力下限时的重要约束。

## 已落地探针

- `example/lib/gpu_probe.dart`：独立入口，缓存 10,000 条窄矩形线段（60,000 顶点、480,000 字节位置数据）；每帧完整提交并通过官方 GpuImageSurface 合成，另绘制移动标记驱动刷新。
- `example/shaders/probe.vert` / `.frag` 和 `.shaderbundle`：同一份源生成 Metal/Vulkan/GLES 变体，官方 impellerc 编译成功。
- `example/tool/build_gpu_shaders.py`：macOS 上使用 PATH 所选 Flutter SDK 的编译器复现生成过程；这是 macOS 调研工具，尚未封装 Windows 的构建工具发现逻辑。
- macOS Info.plist 开启 GPU/Impeller；SDK 自动将最低 macOS 版本提升至 12.0，更新依赖锁文件和分析排除目录。
- 预热 5 秒后收集 60 秒 FrameTiming，输出 `GPU_PROBE_RESULT`，含实际物理尺寸、UI/raster p95 和超预算比例。

这是基础吞吐与呈现探针。尚未接入真实 G-code、虚线、完整播放语义、加载期间更新、视觉对照和 Canvas 基线；即使探针通过，也不能视为完整产品达标。采集帧数必须与显示刷新率/窗口是否被遮挡一起解释，不能只看 p95。完整验收还需三次采样和 release 独立启动。

## 验证结果与阻断

| 检查 | 结果 |
| --- | --- |
| SDK 版本与三端源码核查 | PASS |
| 三后端 shader bundle 编译 | PASS |
| 原型静态分析 | PASS |
| 原有包测试 | PASS，30 tests |
| macOS Profile 构建 | BLOCKED：Xcode compiler probe 不返回 |
| 实际图像、1 万段/60fps、release | PENDING，尚无运行数据 |

两次构建（普通和 verbose）均停在 Xcode `ExecuteExternalTool clang -v -E -dM ... /dev/null`，未进入应用编译。对本任务 clang 采样显示主线程阻塞在 `llvm::raw_fd_ostream::write_impl` → `write`。同一 clang 探测用独立 subprocess 执行返回 0；`xcodebuild -version` 也正常。因此 doctor 成功不等于完整构建链已通过，目前只定位到 Xcode 调用编译器时的输出阻塞，尚未证明其更深层根因。

已停止本任务两个 xcodebuild 进程，未停止其他项目的构建。诊断材料：[构建输出](evidence/macos-gpu-build.txt)、[clang 采样](evidence/macos-clang-sample.txt)。

## 恢复验证步骤

在 `example` 目录：

```sh
python3 tool/build_gpu_shaders.py
flutter analyze lib/gpu_probe.dart
flutter run -d macos --profile -t lib/gpu_probe.dart
```

解决本机 Xcode 构建阻塞后，保持窗口可见至少 65 秒，保存 READY/RESULT 和异常输出；重复三次。随后执行 `flutter build macos --release -t lib/gpu_probe.dart` 并从生成的 app 独立启动。记录设备、窗口物理尺寸和采样条件，再进入真实 G-code 等价绘制与 Canvas 对照。

下一阶段按 macOS 优先执行，不等待 Windows/Android 完成运行验收；但不将 macOS 的结果外推为三端通过。
