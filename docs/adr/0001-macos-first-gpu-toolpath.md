# 先验证 macOS 的统一二维 GPU 轨迹实现

后端默认值及 Canvas 保留策略已被 [ADR 0002](0002-gpu-only-drawing.md) 替代。

优先稳定二维轨迹绘制，暂不重构累计快照管线。采用官方 Flutter GPU 绘制 G0/G1 轨迹，复用 Flutter Canvas/Widget 合成网格、原点、刀头和图例；先完成 macOS 运行证据，再逐步验证 Windows、Android。包的默认后端保留 Canvas，示例显式启用 GPU，以保留已有调用兼容性和视觉对照；平台启动配置由宿主负责。
