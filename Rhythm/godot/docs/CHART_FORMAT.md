# rchart · 谱面 JSON 格式

版本：`format = "rchart"`，`version = 3`

> **版本演进**
> - **v2**：轨道 `alpha` 从 `0.0~1.0` 浮点改成 `0~255` 整数（读 v1 时自动 ×255）。
> - **v3**：动画从 `motion` 关键帧改成 `events` 事件（读 v2 的 `motion` 会自动合成事件，不会丢谱）。

Godot 4.x 用的音游谱面格式。设计目标：**人能直接手写、程序能容错读、编辑器能无损存**。

- **时间一律用秒**（浮点）。BPM 只用于画网格和吸附，不改写已有音符的时间 ——
  这样改 BPM 不会把已经摆好的音符弄乱，音频对不齐时直接调 `audio.offset` 就行。
- **缺字段 = 用默认值**，不是报错。所以最小谱面可以只有 `notes`。
- **未知字段忽略**，未知 `type` 回退成 `tap`，`lane` 越界自动夹到合法轨道并告警。
- 文件是 UTF-8、Tab 缩进的普通 JSON。

---

## 1. 完整示例

```json
{
  "format": "rchart",
  "version": 1,
  "meta": {
    "title": "Neon Pulse (Demo)",
    "artist": "Synth Engine",
    "charter": "Rhythm Chart Editor",
    "difficulty": "HARD",
    "level": 8,
    "description": "示例谱面"
  },
  "audio": {
    "file": "res://audio/neon_pulse.ogg",
    "offset": 0.0,
    "volume_db": 0.0
  },
  "timing": {
    "bpm": 150.0,
    "beat_offset": 0.0,
    "bpm_events": [ { "beat": 0.0, "bpm": 150.0 } ]
  },
  "stage": {
    "lane_count": 4,
    "lane_width": 96.0,
    "highway_length": 6.0,
    "scroll_speed": 1.0,
    "judge_line_y": 0.0
  },
  "lanes": [
    {
      "name": "Outer L",
      "color": "#4cc9f0",
      "position": { "x": -150.0, "y": 0.0 },
      "rotation_deg": -9.0,
      "alpha": 1.0,
      "length_scale": 1.0,
      "visible": true,
      "volume": 1.0
    }
  ],
  "notes": [
    { "id": 1, "time": 0.0,    "lane": 0, "type": "tap" },
    { "id": 2, "time": 0.4,    "lane": 1, "type": "tap" },
    { "id": 3, "time": 0.8,    "lane": 2, "type": "hold", "duration": 0.8 },
    { "id": 4, "time": 1.6,    "lane": 3, "type": "flick" },
    { "id": 5, "time": 2.0,    "lane": 0, "type": "mine" }
  ]
}
```

---

## 2. 顶层

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `format` | string | 否 | 固定 `"rchart"`，只做标识，读了不校验 |
| `version` | int | 否 | 当前 `1`，为以后兼容留的口子 |
| `meta` | object | 否 | 展示信息，见下 |
| `audio` | object | 否 | 音频引用与偏移 |
| `timing` | object | 否 | BPM 映射 |
| `stage` | object | 否 | 舞台全局参数 |
| `lanes` | array | 否 | 轨道数组，**顺序即轨道编号 0..N-1** |
| `notes` | array | 否 | 音符数组，按 `time` 升序存（读取时会重排） |

## 3. `meta`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `title` | string | `""` | 曲名 |
| `artist` | string | `""` | 艺术家 |
| `charter` | string | `""` | 谱师 |
| `difficulty` | string | `"NORMAL"` | 制谱器提供 EASY/NORMAL/HARD/EXPERT/MASTER，但**不做枚举限制** |
| `level` | int | `1` | 数字难度 |
| `description` | string | `""` | 备注 |

## 4. `audio`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `file` | string | `""` | `res://` / `user://` / 绝对路径都可以 |
| `offset` | float | `0.0` | **音频时间 = 谱面时间 + offset**（正数=音频比谱面晚） |
| `volume_db` | float | `0.0` | 预览音量 |

> 制谱器可以直接听桌面上的音频文件（走 `AudioStreamOggVorbis/MP3/WAV.load_from_file`），
> 不一定非要先拷进项目；但最终发布时建议改成 `res://` 路径。

## 5. `timing`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `bpm` | float | `120.0` | 基础 BPM（= `bpm_events[0].bpm`） |
| `beat_offset` | float | `0.0` | 第 0 拍落在第几秒（前奏对齐用） |
| `bpm_events` | array | `[]` | 变速点，元素 `{ beat: float, bpm: float }`，按 `beat` 升序 |

**换算规则**（`RhythmChartTiming`）：

```
beat_to_sec(beat) ：beat_offset + Σ 分段时长
sec_to_beat(sec)  ：其逆运算
snap_sec(sec, d)  ：把时间吸到 1/d 拍网格上（d=4 → 十六分音符）
```

- `bpm_events` 为空时 = 全曲恒定 `bpm`。
- 非空时第一个事件被强制视为 `beat 0`，其 `bpm` 覆盖顶层 `bpm`。
- `beat 0` 永远对应 `beat_offset` 秒，负拍用第一个 BPM 外推。

## 6. `stage`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `lane_count` | int | `4` | 轨道数（写了 `lanes` 时以 `lanes` 长度为准） |
| `lane_width` | float | `96.0` | 轨道宽度（像素） |
| `highway_length` | float | `6.0` | 可视长度，单位**秒**（= 判定线到视野尽头的时长） |
| `scroll_speed` | float | `1.0` | 全局滚动倍率 |
| `judge_line_y` | float | `0.0` | 判定线相对默认位置的额外偏移（像素） |

## 7. `lanes[i]` —— 轨道就是"带变换的长条"

| 字段 | 类型 | 默认 | 范围 | 说明 |
| --- | --- | --- | --- | --- |
| `name` | string | `"Lane N"` | | 显示名 |
| `color` | string | `"#ffffff"` | `#rrggbb` | 轨道底色（判定区为 none 时就是实际显示色） |
| `judge_zone` | string | `"none"` | `none` / `left` / `right` | **判定区**：决定这条轨道上的音符能被哪些键打到 |
| `position` | object | `{0,0}` | | 相对判定线中点的像素位移 `{x, y}` |
| `rotation_deg` | float | `0.0` | 任意（存储时 wrap 到 ±360） | 顺时针为正，0 = 笔直向上 |
| `alpha` | int | `255` | `0 ~ 255` | 整轨透明度（0 = 全透明，255 = 不透明） |
| `length_scale` | float | `1.0` | `0.1 ~ 8.0` | 轨迹长度倍率 |
| `visible` | bool | `true` | | 隐藏（数据保留） |
| `volume` | float | `1.0` | `0.0 ~ 1.0` | 该轨打击音音量的提示值 |
| `events` | object | `{}` | | **事件动画**（PhiEdit / Phigros 模型），见下 |

### 事件动画 `events`（轨道会动）

动画由一条条**独立事件**组成：每条纹一条事件，声明自己的起止时间、起止值和缓动。
可动画的属性：`x` / `y` / `rotation` / `alpha` / `length`。

```json
"events": {
  "x": [
    { "start": 0.0, "end": 8.0,  "from": -150.0, "to": 150.0, "ease": "inOutQuad" },
    { "start": 8.0, "end": 16.0, "from": 150.0,  "to": -150.0, "ease": "outBack" }
  ],
  "alpha": [
    { "start": 0.0, "end": 3.0, "from": 255.0, "to": 40.0, "ease": "inOutSine" }
  ]
}
```

| 事件字段 | 类型 | 说明 |
| --- | --- | --- |
| `start` | float | 开始时间（秒） |
| `end` | float | 结束时间（秒），不能小于 `start` |
| `from` | float | 起始值：`x`/`y` 像素、`rotation` 角度、`alpha` **0~255**、`length` 倍率 |
| `to` | float | 结束值 |
| `ease` | string | 这段的缓动，默认 `linear` |

**求值规则**

1. 取「起点 ≤ 当前时间、且起点最晚」的那条事件。
2. 时间落在 `[start, end]` 内 → 从 `from` 按 `ease` 缓动到 `to`。
3. 已经过了 `end` → 保持 `to`，直到下一条事件开始（**不外推、不自动回弹**）。
4. 还没到任何事件 → 用静态字段（`position` / `rotation_deg` / `alpha` / `length_scale`）。
5. 事件可以重叠，起点更晚的那条覆盖前面的。

渲染和判定都按"当前谱面时间"求值，编辑器预览和游戏里表现一致：
`lane.resolved_position(t)`、`lane.resolved_rotation(t)`、`lane.resolved_alpha(t)`、`lane.resolved_length_scale(t)`。

**内置缓动**：`linear`、`step`、`inSine / outSine / inOutSine`、`inQuad / outQuad / inOutQuad`、
`inCubic / outCubic / inOutCubic`、`inExpo / outExpo`、`inBack / outBack`。

**自定义函数曲线**：`"ease": "bezier(0.25, 0.1, 0.25, 1)"`（和 CSS `cubic-bezier` 同一套算法，
逗号后面有没有空格都行）。实测曲线：

```
ease 名字        0.5 处的进度
linear           0.50
outQuad          0.75
inOutCubic       0.50
bezier(.25,.1,.25,1)  ≈ 0.80
```

### 判定区 `judge_zone`（玩法，不只是颜色）

| 值 | 颜色 | 允许的键 |
| --- | --- | --- |
| `none` | 白 `#ffffff` | `A S D F J K L ;` —— 8 个键任意一个都能判定 |
| `left` | 紫 `#b06bff` | 只有 `A S D F`（左半） |
| `right` | 黄 `#ffd166` | 只有 `J K L ;`（右半） |

- **渲染用「判定区颜色」覆盖轨道自身颜色**：`lane.display_color()`。
  `color` 只在判定区为 `none` 时生效（默认白）。
- 音符粒子的颜色同样跟判定区走；`mine` 用压暗表示，`flick` 用三角标记，**不另配色**。
- 游戏侧判定直接拿 `lane.allowed_keys()`（返回 `["A","S","D","F"]` 之类），
  或者按 `judge_zone` 自己分支。

**渲染语义**（游戏侧照这个算，就能和制谱器预览一致）：

```
judge_origin  = Vector2(屏幕宽/2, 屏幕高*0.85 + stage.judge_line_y)
lane_base     = judge_origin + lane.position
lane_dir      = Vector2.UP.rotated(deg_to_rad(lane.rotation_deg))
lane_side     = Vector2.RIGHT.rotated(deg_to_rad(lane.rotation_deg))
轨迹长度(px)  = stage.highway_length * lane.length_scale * 每秒像素 * stage.scroll_speed
音符位置      = lane_base + lane_dir * ((note.time - 当前谱面时间) * 每秒像素 * scroll_speed)
```

参考实现见 `examples/chart_stage_2d.gd`。

## 8. `notes[i]`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `id` | int | `0` | 编辑器用的唯一标识，运行时不依赖它 |
| `time` | float | `0.0` | 音符到达判定线的谱面时间（秒） |
| `lane` | int | `0` | 轨道序号，`0 .. lanes.size()-1` |
| `type` | string | `"tap"` | `tap` / `hold` / `flick` / `mine` |
| `duration` | float | `0.0` | 仅 `hold` 有意义：按住时长（秒） |
| `velocity` | float | `1.0` | 打击力度提示，`0.0 ~ 1.0`；等于 1.0 时通常不写 |

`type` 语义：

| type | 玩法建议 |
| --- | --- |
| `tap` | 单击 |
| `hold` | 按住到 `time + duration` |
| `flick` | 划键 / 上滑 |
| `mine` | 地雷，碰到扣血（不要按） |

`duration <= 0` 的 `hold` 会被当成 `tap` 处理，`RhythmChartNote.is_long()` 返回 `false`。

---

## 9. 容错规则（读取时）

| 情况 | 行为 |
| --- | --- |
| 文件不存在 / 不是合法 JSON | 返回 `null`，报告里给出原因和行号 |
| 根节点不是对象 | 返回 `null` + 原因 |
| 缺 `meta` / `audio` / `stage` / `timing` | 用默认值补齐 |
| 缺 `lanes` | 按 `stage.lane_count` 生成默认轨道（水平均分） |
| `lane` 越界 | 夹到 `0..N-1`，报告里留一条告警 |
| `type` 拼错 | 回退 `tap` |
| `alpha` / `length_scale` / `volume` 越界 | 夹到合法范围（alpha 夹到 0~255） |
| `motion` 里 `time` 为负 / 顺序乱 | 负数夹到 0，按时间重排 |
| `events` 里 `end` 小于 `start` | `end` 夹到 `start`（零时长事件＝瞬间跳变） |
| `events` 某属性的值不是数组 | 该属性忽略，退回静态值 |
| `ease` 名字不认识 | 当 `linear` 处理 |
| `judge_zone` 拼错 / 缺失 | 退回 `none`（白色，任意键） |
| `time` 为负 | 夹到 `0` |
| 音符顺序乱 | 读取后按 `(time, lane)` 重排 |
| `id` 重复 | 不影响读取；再次保存时编辑器会保证新 id 唯一 |

## 10. 手写最小谱面

```json
{
  "timing": { "bpm": 120 },
  "stage": { "lane_count": 4 },
  "notes": [
    { "time": 0.0, "lane": 0 },
    { "time": 0.5, "lane": 1 },
    { "time": 1.0, "lane": 2 },
    { "time": 1.5, "lane": 3 }
  ]
}
```

这就够跑起来了 —— 默认 4 轨、默认颜色、默认舞台。

## 11. 在游戏里读

```gdscript
const ChartIO := preload("res://addons/rhythm_chart_editor/core/rhythm_chart_io.gd")

var report: Array = []
var doc := ChartIO.load_file("res://charts/neon.json", report)
if doc == null:
	push_error("谱面坏了：%s" % [report])
	return

for note in doc.notes:          # 已按时间排序
	print(note.time, " lane=", note.lane, " type=", note.type)
```

`core/` 目录下的类不依赖编辑器，运行时可以直接用（`@tool` 不影响运行）。

## 12. 版本演进约定

- 加字段：直接加，旧谱面缺它就用默认值，`version` 不用动。
- **已经发生的改语义**：
  - `alpha` 在 v1 是 `0.0~1.0`，v2 起是 `0~255`
  - 动画在 v2 是 `motion` 关键帧，v3 起是 `events` 事件
  读取时按文件里的 `version` 自动迁移，旧谱面照常能开。
- 改字段含义 / 删字段：`version` +1，并在 `RhythmChartDocument.from_dict` 里保留旧版本的转换分支。
- `format` 字段用于文件识别，不要改。
