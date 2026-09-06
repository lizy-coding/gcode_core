# 绘图区只保留 Flutter GPU

按用户确认，移除 Canvas 后端和降级能力，覆盖 ADR 0001 中保留 Canvas 默认后端的决定。轨迹、网格、原点、刀头及光晕全部由同一 GPU surface 输出；Flutter 仅合成最终图像并显示普通控件。样式改为不可变颜色和线宽值，不保留 Paint 配置兼容层；GPU 不可用时报告错误，平台可用性仍按 macOS、Windows、Android 分阶段取得证据。
