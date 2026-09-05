# macOS 二维 GPU 绘制验收

此报告是保留辅助 Canvas 时的历史验收。当前 GPU 独占实现见 [GPU 独占验收](macos-gpu-only-acceptance.md)，不能将本报告的性能数据直接视为新实现数据。

日期：2026-09-05。基线 commit：`2e5fee4`；本报告对应其后的工作区实现，尚未额外提交。

## 本轮范围

优先稳定 macOS 二维绘制，不修改快照或解析管线。新增 `GcodeCanvasBackend.gpu`，示例使用该后端；包默认仍为 Canvas。G0 虚线、G1 实线、未播放背景路径、段内进度由 GPU 实现；网格、原点、刀头与图例仍由 Flutter 合成。

几何按路径内容、边界、尺寸和线宽缓存；播放更新 uniform，以背景层和前景层两次批量提交呈现。颜色统一采用 RGBA8 和显式预乘 Alpha 混合，避免默认格式初始化失败和背景路径透明度偏低。修正共用 Canvas 参考绘制中对非零 minY 的重复减法，使负坐标数据与 GPU 位置一致。窄于内边距的视口不生成无效几何。

## 环境和结果

Flutter 3.47.2 / Engine a804b26164，macOS 26.5 arm64，Xcode 26.6。使用项目局部编译器探测兼容入口构建；不修改全局 Xcode/Flutter 环境。

| 项目 | 结果 |
| --- | --- |
| 包静态分析、示例/验证入口静态分析 | PASS |
| 单元测试 | PASS，33 tests；新增负坐标、退化段、窄视口测试 |
| Shader 多后端编译 | PASS；仅 macOS 运行验收 |
| 实际组件 0%、45%、100% 对照 | PASS，已检查保存的 Canvas/GPU 图像 |
| 20 次销毁重建及 480/640 宽度切换 | PASS，无 GPU 错误；最后图像与重建前 GPU 100% 图像相同 |
| 10,000 段 G0/G1 播放 | PASS，本轮 60 秒 3,595 帧，约 59.9fps |
| UI p95 / raster p95 | 1.396ms / 0.851ms；超过 16.67ms 的记录为 0 |
| 普通示例 Release 构建和独立启动 | PASS，真实窗口加载内置示例，5 段轨迹及预期解析错误正常显示 |

性能由实际 `GcodeCanvas` GPU 后端产生，不再是固定矩形探针。测试文本经现有 `GcodeParser` 与 `ToolpathBuilder` 生成 10,000 段（每七条含一次 G0）；预热 5 秒后采样 60 秒，绘制区域固定为 640×480 logical pixels。未包含磁盘读取、快照传输和时间线列表负载；这是本机本场景通过，不外推到所有设备或百万段。

抗锯齿与虚线端点存在小幅像素差异；0%、45%、100% 图像各通道平均绝对误差均小于 0.6/255。此统计以大量背景像素为分母，仅为辅助证据，主要判断来自图像检查。不得将它解释为所有局部像素差异都小于 0.6。

## 证据

- [性能和重建结果](evidence/macos-2d/report.json)
- [原生运行日志](evidence/macos-2d/run.txt)
- [GPU 45%](evidence/macos-2d/gpu-0.45.png) / [Canvas 45%](evidence/macos-2d/canvas-0.45.png)
- [GPU 100%](evidence/macos-2d/gpu-1.00.png) / [20 次重建后](evidence/macos-2d/gpu-after-20-reloads.png)
- [1 万段图像](evidence/macos-2d/gpu-10000.png)
- [源码指纹](evidence/macos-2d/source-sha256.json)

## 复现

仓库根目录运行：

```sh
python3 example/tool/macos_run.py --mode release
python3 example/tool/macos_run.py --mode profile --target lib/gpu_validation.dart
```

兼容入口自动编译 shader。验证入口输出截图与 report.json 所在路径；验收时同时检查日志没有 `GCODE_GPU_INIT_FAILED`、`GCODE_GPU_RENDER_FAILED` 或 `GPU_2D_FAILED`，并检查帧数，而非仅看 p95。

## 后续边界

Windows/Android 尚未做运行验收，本轮不默认宣告支持；下一阶段复用相同 shader/数据契约验证实际设备。长时间显存/内存趋势、多显示器 DPR 切换和更多驱动组合尚未覆盖。示例的播放/进度回调保持原有代码，自动验证已覆盖连续进度变化和离散跳转；本轮桌面自动化的手动拖动操作未取得可靠回执，不额外宣告其端到端验收通过。
