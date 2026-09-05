# GPU 独占绘图区收敛验收

日期：2026-09-05。按用户要求删除 Canvas 后端和降级能力，替代上一阶段的 GPU 路径与 Canvas 辅助图形组合。

## 当前实现

- G0 虚线、G1 实线、背景路径、段内进度、网格、原点、刀头和光晕全部由 Flutter GPU 绘制。
- 场景输出到一个 RGBA8 GpuImageSurface；四次提交顺序为网格、背景路径、已播放路径、标记。每次切换 shader 管线前清空绑定，避免不同 uniform 名称的绑定残留覆盖当前管线数据。
- 生产源码中仅保留 `Canvas.drawImageRect`，用于 Flutter 合成最终 GPU 图像；它不绘制任何 G-code 几何，也不读回像素到 CPU。图例、状态提示和控件使用普通 Widget。
- 删除 `GcodeCanvasBackend`、Canvas painter 和旧独立矩形探针；没有自动降级。GPU 初始化或绘制失败直接显示错误。
- `GcodeStyle` 不再持有可变 Paint，改为 `GcodeStroke(color, width)` 和颜色字段。共用 ToolpathViewport 负责轨迹、网格与刀头坐标，并按路径或尺寸变化更新。

## API 迁移

保留 `GcodeCanvas` 类名与 segments/progress/bounds 等输入；删除调用处的 backend 参数及枚举引用。样式字段迁移：

| 旧字段 | 新字段 |
| --- | --- |
| rapidMovePaint / rapidMoveBgPaint | rapidMove / rapidBackground |
| linearMovePaint / linearMoveBgPaint | linearMove / linearBackground |
| gridPaint / originPaint | grid / origin |
| toolHeadPaint / toolHeadGlowPaint | toolHeadColor / toolHeadGlowColor |
| originDotPaint | originDotColor |

Stroke 使用 width 而非 strokeWidth。该 API 调整是显式收敛，不提供旧 Paint 配置适配层。

## 验证结果

Flutter 3.47.2、macOS 26.5 arm64、Metal Impeller。

| 检查 | 结果 |
| --- | --- |
| 生产源码扫描 | 无 CanvasBackend、drawLine/drawCircle/drawPath 和旧 Paint 样式字段 |
| 包和示例静态分析 | PASS |
| 单元测试 | PASS，36 tests |
| shader bundle 编译 | PASS，Metal/Vulkan/GLES 变体；运行仅验证 macOS |
| 0%、45%、100% GPU 整图 | PASS，已检查轨迹、网格、原点、刀头和透明背景路径 |
| 20 次销毁重建及尺寸切换 | PASS，最后图像与重建前 100% 图像一致 |
| 一万段整图绘制 | PASS，实际解析生成 G0/G1 场景，没有 GPU 错误 |
| Release 构建、独立启动及示例加载 | PASS，真实窗口中 5 段轨迹、网格、刀头、图例和预期 G2 错误提示正常 |
| 持续 60 fps | PENDING，当前采样帧数不足，不能沿用上一阶段的 59.9fps 结论 |

性能采样均为 60 秒：第一轮有效图像采样记录 896 帧，UI/raster p95 为 1.483/0.879ms，超预算 2 帧；第二轮记录 1610 帧，UI/raster p95 为 1.414/0.970ms，超预算 3 帧。窗口自动化期间无法稳定保持窗口前台，且部分截图/帧等待延迟较长；仍需在持续可见的受控窗口下复测，不能仅凭 p95 较低断言帧率通过，也不能将帧数不足完全归因于某一因素。

此前出现轨迹颜色被覆盖的试验已废弃；本报告图像来自加入 clearBindings 后的运行。测试不覆盖长时间显存趋势、磁盘/快照负载或 Windows/Android 设备；没有修改快照管线。

## 证据和运行

- [最新报告](evidence/macos-gpu-only/report.json)、[前一轮报告](evidence/macos-gpu-only/previous-report.json)、[日志](evidence/macos-gpu-only/run.txt)
- [45% 场景](evidence/macos-gpu-only/gpu-0.45.png)、[100% 场景](evidence/macos-gpu-only/gpu-1.00.png)、[20 次重建后](evidence/macos-gpu-only/gpu-after-20-reloads.png)
- [1 万段整图](evidence/macos-gpu-only/gpu-10000.png)、[源码指纹](evidence/macos-gpu-only/source-sha256.json)

```sh
python3 example/tool/macos_run.py --mode release
python3 example/tool/macos_run.py --mode profile --target lib/gpu_validation.dart
```

普通示例使用 GPU 唯一后端，兼容入口自动生成 shader。验证入口保存图片与报告；运行时应同时检查图像、错误日志、帧数和耗时分位数。
