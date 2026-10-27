# Rhythm · 文档

给「用 Godot 做音游、用网页版制谱器写谱」这条路线准备的四份文档。

| 文档 | 讲什么 | 什么时候看 |
| --- | --- | --- |
| [CHART_FORMAT.md](CHART_FORMAT.md) | 谱面 JSON 的每个字段、默认值、范围、容错规则、zip 结构 | 写解析器 / 手改谱面 |
| [GAME_INTEGRATION.md](GAME_INTEGRATION.md) | 坐标系、渲染公式、判定逻辑、分数建议、哪些是硬约束 | 想先搞懂「编辑器里的画面对应游戏里什么」 |
| [GODOT_GUIDE.md](GODOT_GUIDE.md) | **GDScript 版**：读 zip、数据层、缓动、`_draw`、判定、对音，附可直接抄的代码 | 实际动手写游戏 |
| [../web/README.md](../web/README.md) | 制谱器本身怎么用 | 制谱 |

## 阅读顺序建议

1. 先看 **GAME_INTEGRATION.md 第 2 节**（坐标与渲染公式）—— 这是「为什么预览窗口里的画面能直接搬进游戏」的核心
2. 再看 **GODOT_GUIDE.md 第 7 节**的最小可跑脚本，把 zip 拖进工程跑起来
3. 需要细节时查 **CHART_FORMAT.md** 的字段表

## 一句话版本

- 谱面时间单位是**秒**，音符落地时刻就是 `note.time`
- 舞台坐标：`cx = 屏宽/2 + lane.x`，`cy = 判定线高度 − lane.y`（**Y 向上为正**）
- 音符离判定线的距离 = `(note.time − 当前时间) × 基础速度 × (lane.speed² / 100)`
- 轨道动画是**每条轨道 6 条独立通道**（x / y / alpha / rotation / speed / length），事件跑完**保持尾值不回弹**
- 判定按 **轨道序号**，不按屏幕位置；按键要属于该轨道的判定区（`none` = 任意键）
- 导出的 zip 里是 `chart.json + 音频 + 曲绘`
