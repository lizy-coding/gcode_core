# Flutter GPU 三端统一绘制评估

日期：2026-09-05。代码基线：`7a52281`。状态：调研与建议计划，未实施迁移，未获得三端性能实测。

## 已确认目标

- 优先采用官方 Flutter 能力，统一 macOS、Windows、Android 的解析与绘制，减少平台维护差异。
- 为后续大文件处理建立结构；首阶段按 **10,000 条轨迹段、60 fps** 调试，暂不定义最低设备。
- 用户自行升级环境。研究以当前官方文档的 Flutter **3.47.2** 为候选基线；执行时记录实际 SDK、Engine 和 Dart 版本并锁定，不在开发中追随浮动 latest。
- 本轮按已有二维 G0/G1 轨迹功能等价迁移估算。三维、圆弧解释和材料去除均需单独定义范围。

## 结论

官方统一三端的技术路径存在，建议先做三端最小验证，再决定是否采用 Flutter GPU 作为默认绘制。不能继续沿用“Windows 没有 Impeller”的旧结论，也不能把 Impeller 可用等同于 Flutter GPU 的产物已验收。

当前 Canvas 路径本身可由 Flutter 引擎使用 GPU 加速。迁移的收益是控制几何缓存、批量提交和进度更新，减少 Dart 每帧工作；不是把整个 G-code 解析搬到 GPU。现有解析、轨迹构建已经主要共用 Dart，迁移不会自动进一步统一这些业务语义。

## 官方依据及版本边界

1. [Impeller 平台文档](https://docs.flutter.dev/perf/impeller)：3.47 起 macOS、Windows 默认启用；Android API 29+ 默认启用，不支持 Vulkan 等设备可能回退旧渲染器。
2. [Flutter GPU 文档](https://raw.githubusercontent.com/flutter/flutter/main/docs/engine/impeller/Flutter-GPU.md)：仍标记 early preview、不保证 API 稳定，并要求 Impeller。此文部分工具链说明可能落后于新版本，构建方式应以锁定版本实际验证为准。
3. [3.47.2 Windows DartProject](https://raw.githubusercontent.com/flutter/flutter/3.47.2/engine/src/flutter/shell/platform/windows/client_wrapper/include/flutter/dart_project.h)：提供 `set_enable_flutter_gpu(bool)` 和 Impeller 开关。
4. [3.47.2 GPU context](https://raw.githubusercontent.com/flutter/flutter/3.47.2/engine/src/flutter/lib/gpu/context.cc)：初始化同时检查 Impeller 与 Flutter GPU 开关，并要求能取到 Impeller context。
5. [GPU API](https://api.flutter.dev/flutter/flutter_gpu/)：SDK 包提供 buffers、shaders、render pipelines、render targets 和 image surface 等低层接口。

官网能力声明、源码接口存在和设备实际运行是三种不同证据。以上仅支持前两者；本次没有新 SDK 三端运行证据。

| 平台 | 计划配置与验证 | 当前可用性评价 |
| --- | --- | --- |
| macOS | Metal/Impeller；开启 `FLTEnableFlutterGPU`；验证独立启动、窗口缩放与跨屏 DPR | 可进入原型验证；未实测 |
| Windows | 3.47.2 官方 Runner，`set_enable_flutter_gpu(true)`；验证实际 Impeller context、shader 和 release 启动 | 有官方接口依据；必须优先验证，未实测 |
| Android | `io.flutter.embedding.android.EnableFlutterGPU`；先选择能运行 Impeller 的真机，测试后台恢复 | 有条件可行；不代表所有 Android 设备可用 |

调试 CLI 开关不替代产物启动设置；从终端成功运行后，还必须从 Finder、Windows Explorer、Android Launcher 独立启动 release。

## 当前代码与迁移范围

| 范围 | 当前证据 | 处理建议 |
| --- | --- | --- |
| 绘制 | `lib/src/widgets/gcode_canvas.dart:278`；全路径与已播放前缀每帧遍历，虚线逐段展开 | 保留外部 Widget 与状态展示，替换内部轨迹 renderer；网格、文字与图例可继续官方 Canvas/Widget |
| 数据管线 | `lib/src/application/gcode_readline_pipeline.dart:136`；默认每 200 行复制累计列表，后台路径也发送累计结果 | 改为带任务 ID、批次序号的追加批次；UI 聚合，取消过期任务；有界队列和背压 |
| 后台解析 | 同文件 `loadFileInBackground` / `loadStringInBackground` | 保留 CPU isolate；统一重复处理逻辑；管理 spawn 失败、异常、取消和端口关闭 |
| 领域数据 | commands、segments、bounds、parser、builder | 二维迁移大部分复用；为绘制建立紧凑数组，避免改变解析语义 |
| 样式 | `GcodeStyle` 使用 Flutter Paint | 转换为 renderer 可消费的颜色、线宽与虚线参数，保留兼容适配 |
| 宿主 | `OWNERS.md` 将文件选择和启动策略归宿主 | 包内维护绘制能力；三端启动与文件访问放在 example/宿主，避免平台判断散落业务代码 |

若有 N 个有效段且每 B 行发送累计结果，累计复制/传输量可能接近 O(N²/B)，即使后台解析也会给接收方和 GC 带来压力。修复此处与更换 renderer 是两项独立工作。

## 建议架构与实现工作

`文件流 → CPU isolate 解析/构建 → 有界追加批次 → UI 轨迹存储 → 绘制数据缓存 → Flutter GPU → Flutter 合成`

1. 统一数据契约：批次带 source/job ID、序号、追加段、边界、错误与结束状态；晚到的旧任务消息不污染新文件。时间线按需显示，避免保留每份历史快照。
2. 按块生成紧凑顶点/索引数据并上传 GPU；播放只更新进度 uniform、绘制范围和当前段，不每帧重建全部几何。背景路径与进度层分开组织。
3. 实线和虚线以三角形带与 shader 实现；保持线宽、端点、抗锯齿、虚线相位、透明度以及刀头位置一致。不要假设底层原生线图元能跨端保持宽线效果。
4. 使用统一矩阵处理坐标、Y 轴、视口和 DPR。大坐标采用局部原点偏移，避免 float32 精度损失。修正旧表现中的问题须与等价迁移明确区分。
5. shader 编译和资源打包纳入锁定 SDK 的构建流程；debug 与 release 均验证。图像呈现尽量使用官方 surface/image 路径，避免逐帧 GPU→CPU readback。
6. 定义 resize、页面退出、重新加载、后台恢复时的资源所有权与重建；按锁定 SDK 的资源 API 实施，确保异步提交完成前资源不被复用。
7. 只设一个能力探测和后端选择入口。先验证统一 Flutter GPU；失败时才启用下文差异策略，不提前维护三套实现。

内存规划例：若每段 4 顶点、每顶点 24 字节、6 个 uint32 索引，约 120 字节/段；1 万段约 1.2 MB，100 万段约 120 MB。仅为几何布局估算，不含 Dart 对象、原文、批次缓冲、纹理和抗锯齿附件；双份几何或上传缓冲会继续增加。1 万段达标不能证明百万段可用。

## 分阶段成本和产物

以下为工程估算，不是实测工期。前提：已有 Flutter 经验并能编写 shader 的工程师，三端构建设备可用，限定现有二维功能，不维护自定义 Engine。单位为人日，不含排队等待、设备购买、签名账号配置和上游缺陷修复。

| 阶段 | 人日 | 必须交付 |
| --- | ---: | --- |
| P0 三端可行性与基线 | 3–5 | 锁定 SDK；三端 release 最小 GPU 场景；10k 数据集；现有 Canvas 基线；运行日志 |
| P1 增量数据与 renderer 边界 | 4–7 | 公用批次协议、取消/背压、兼容接口、功能测试 |
| P2 GPU 等价绘制 | 6–10 | 同一 Dart/GLSL 实现；实/虚线、进度、刀头、缓存和 resize 生命周期 |
| P3 三端整合与性能验收 | 5–8 | 三端 example、真机 trace、图像对照、独立 release 启动、失败诊断 |
| P4 交付维护 | 2–3 | CI 构建矩阵、版本锁定、升级回归说明、验收报告 |
| 合计 | **20–33** | 可评估是否发布的三端二维绘制产物 |

预留约 25%–35% 风险后，预算 **25–45 人日**；一人约 5–9 工作周。纯展示原型可在 P0 后继续用约 3–5 人日完成，但不代表生产可用。若缺乏图形编程经验，另预留 5–10 人日学习与排错。维护预算可暂留每次 SDK 升级 1–3 人日三端回归，遇到 API/驱动变动重新估算。

如果 P0 证明优化后的 Canvas 已达到 10k/60fps，GPU 的短期收益就需要以 CPU 时间、扩展斜率和维护成本进一步证明；建议把 Canvas 作为对照，而非仅凭“使用 GPU”判断成功。仅优化现有 Canvas/数据链路的候选投入约 5–10 人日，不与完整 GPU 方案成本相加。

## 可用性验收计划

建议值，尚待用户确认：每端选定一台设备，记录 OS/GPU/驱动、SDK/Engine、物理分辨率与 DPR。首轮优先统一约 1080p 物理绘制面积，实际布局不同则分别记录，不直接比较平均 fps。

- 固定 10,000 有效轨迹段：全实线、虚线密集、交叉密集、负坐标/退化段；覆盖进度 0、50%、100%、来回拖动，以及加载中播放。
- 预热后采集 60 秒，重复 3 次；Profile 测 UI/raster 帧耗时与超预算帧，release 验证实际行为。建议 UI 和 raster 各自 p95 ≤16.67ms、超预算帧率 ≤1%，同时记录 p99、峰值内存、首次可见时间、总加载时间和批次队列峰值。这是建议的 60fps 工程门槛，不代表零掉帧承诺。
- GPU 原生测量按平台配合工具，不能只用平均 fps 或 Dart 计时推断 GPU 耗时。加载和稳定播放分开报告。
- 视觉对照覆盖线宽、虚线、透明度、坐标方向、边界、刀头；回放沿用段数进度语义。比较语义正确性和合理像素容差，不要求不同 GPU 位级相同。
- 连续重新加载/进入退出至少 20 次，观察内存是否持续上升；测试窗口 resize、Android 后台恢复、读取失败和取消。
- 增补 100k/1m 压力曲线，首期只记录性能与内存拐点，不承诺其 60fps。
- 所有平台必须有真实运行证据；Android 模拟器和 macOS 成功不能替代 Windows/Android 真机验收。

当前状态：源码调研完成；GPU 构建、视觉正确性、10k/60fps、生命周期与 release 可用性均 **PENDING**。

## 若统一路径失败

先分清配置/打包问题、某个驱动问题、官方 API 缺口，给出最小复现和所选 SDK 的证据。P0 建议以 5 人日封顶，届时报告阻断点，不无期限尝试。

第一备选仍是官方 Canvas：共享解析、数据模型、样式、进度与验收数据，仅让 renderer 适配器分叉；统一能力探测负责降级，不在 parser 或页面中添加平台分支。代价是维护两个 renderer 的一致性测试，初步追加 3–6 人日，再根据差异重估。

若 Canvas 降级达不到确认后的大文件目标，再单独评估原生 GPU 插件或定制 Engine。它们会引入 C++/平台纹理/ABI/驱动和额外发布维护，不符合本轮优先降低平台差异的方向，不包含在 25–45 人日预算内。

## 待下一轮确认

1. 第一阶段是否只保持现有二维 G0/G1 和按段数回放；缩放平移、点选、G2/G3、Z 轴另列增量？
2. 是否接受 Flutter GPU 当前 API 稳定性风险，采用固定稳定 SDK，遇到必须 master/自定义 Engine 才解决的问题就回到路线评估？
3. 是否认可 P0 的 3–5 人日验证关口及上述 60fps 测量口径？通过后再确认完整实现，避免把源码可行性当成性能承诺。

尚未选定最终绘制架构，因此暂不记录 accepted ADR；确认技术取舍后再新增 ADR。
