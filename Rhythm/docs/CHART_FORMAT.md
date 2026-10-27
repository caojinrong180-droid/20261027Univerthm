# rchart · 谱面格式规范

> 版本：`format = "rchart"`，`version = 3`
> 这是 **网页版制谱器**（`web/`）实际读写的那一套。游戏侧照这份文档读就能和编辑器对齐。
> 旧 Godot 版的字段（`position` / `rotation_deg` / `length_scale` / `motion`）**不适用**，
> 那是另一套，见 `godot/docs/CHART_FORMAT.md`。

## 0. 三条硬约定

1. **时间一律是「秒」**（浮点，存盘保留 3 位小数）。BPM 只影响网格和吸附，不改写时间。
2. **缺字段用默认值，不报错**。最小谱面可以只有 `notes`。
3. **未知字段忽略**；未知音符类型退回 `tap`；`lane` 越界夹到合法范围。

## 1. 完整示例

```json
{
  "format": "rchart",
  "version": 3,
  "meta": {
    "title": "Neon Pulse",
    "artist": "Synth Engine",
    "charter": "我",
    "illustrator": "Curtain",
    "difficulty": "HARD",
    "level": 8,
    "cover": "cover.png"
  },
  "audio": { "file": "song.mp3", "offset": 0.0, "volume_db": 0.0 },
  "timing": { "bpm": 150.0, "beat_offset": 0.0 },
  "stage": { "lane_count": 4, "highway_length": 2.0 },
  "lanes": [
    {
      "name": "Lane 1", "color": "#ffffff", "judge_zone": "left",
      "x": -96, "y": 0, "alpha": 100, "speed": 10, "length": 10, "rotation": 0,
      "events": {
        "x":     [ { "start": 2.0, "end": 6.0, "ease": "inOutQuad", "from": -96, "to": -40 } ],
        "alpha": [ { "start": 2.0, "end": 3.0, "ease": "outCubic",  "from": 0,   "to": 100 } ]
      }
    },
    { "name": "Lane 2", "judge_zone": "left" },
    { "name": "Lane 3", "judge_zone": "right" },
    { "name": "Lane 4", "judge_zone": "right" }
  ],
  "notes": [
    { "id": 1, "time": 1.000, "lane": 0, "type": "tap" },
    { "id": 2, "time": 1.400, "lane": 1, "type": "hold", "duration": 0.800 },
    { "id": 3, "time": 2.400, "lane": 2, "type": "flick" },
    { "id": 4, "time": 3.200, "lane": 3, "type": "mine" }
  ]
}
```

## 2. 顶层

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `format` | string | 否 | 固定 `"rchart"`，只做标识 |
| `version` | int | 否 | 当前 `3` |
| `meta` | object | 否 | 展示信息 |
| `audio` | object | 否 | 音频引用与偏移 |
| `timing` | object | 否 | BPM |
| `stage` | object | 否 | 全局参数 |
| `lanes` | array | 否 | 轨道，**顺序即轨道编号 0..N-1** |
| `notes` | array | 否 | 音符，按 `(time, lane)` 升序存 |

## 3. `meta`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `title` | string | `"未命名谱面"` | 曲名 |
| `artist` | string | `""` | 艺术家 |
| `charter` | string | `""` | 谱师 |
| `illustrator` | string | `""` | 曲绘作者（画师 / Illustration by）；编辑器侧栏「曲绘画师」一栏 |
| `difficulty` | string | `"NORMAL"` | EASY / NORMAL / HARD / EXPERT / MASTER，不枚举限制 |
| `level` | int | `1` | 数字难度，夹到 1~99 |
| `cover` | string | `""` | 曲绘文件名，和 zip 里的图片同名 |

## 4. `audio`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `file` | string | `""` | 音频文件名 |
| `offset` | float | `0.0` | **谱面时间 = 音频时间 − offset** |
| `volume_db` | float | `0.0` | 音乐音量（dB，0 = 原始音量，-6 ≈ 一半） |
| `hit_volume_db` | float | `-3.0` | 打击音音量（dB，只影响编辑器预览） |

`offset` 为正表示「音频比谱面晚」，即谱面的第 0 秒对应音频的第 offset 秒。

## 5. `timing`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `bpm` | float | `150` | 夹到 20~1000 |
| `beat_offset` | float | `0.0` | 第 0 拍落在第几秒 |

```
beatToSec(beat) = beat_offset + beat * 60 / bpm
secToBeat(sec)  = (sec - beat_offset) * bpm / 60
```

**游戏侧一般不需要这两个值** —— 音符时间是绝对秒数，BPM 只是编辑器画网格用。
只有做「按小节显示」之类的 UI 才需要。

## 6. `stage`

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `lane_count` | int | `4` | 写了 `lanes` 时以 `lanes.length` 为准 |
| `highway_length` | float | `2.0` | **只用于打开谱面时初始化编辑器的「可视秒数」**，游戏忽略 |

## 7. `lanes[i]` —— 一条轨道

### 7.1 基本字段

| 字段 | 类型 | 默认 | 范围 | 说明 |
| --- | --- | --- | --- | --- |
| `name` | string | `"Lane N"` | | 显示名 |
| `color` | string | `"#ffffff"` | `#rrggbb` | **只在 `judge_zone = none` 时生效** |
| `judge_zone` | string | `"none"` | `none` / `left` / `right` | 判定区，决定能被哪些键打到，也决定显示颜色 |
| `x` | float | `0` | ±2000 | 相对**舞台正中**的像素偏移，**向右为正** |
| `y` | float | `0` | ±2000 | 同上，**向上为正** |
| `alpha` | float | `0` | 0~100 | **0 = 完全隐藏，100 = 完全不透明**；只影响轨道本体和判定线，**不影响音符** |
| `speed` | float | `10` | 0~100 | 音符流速，**10 = 1.00×，平方曲线**（见 7.3） |
| `length` | float | `10` | 0~100 | 轨道长度，**10 = 标准全长（判定线到画面顶），0 = 只剩判定线** |
| `rotation` | float | `0` | ±3600 | 度，**顺时针为正**，0 = 竖直向上 |
| `events` | object | `{}` | | 动画通道，见 7.4 |

### 7.2 判定区

| `judge_zone` | 颜色 | 能判定的键 |
| --- | --- | --- |
| `none` | `#ffffff`（或 `color`） | `A S D F J K L ;` 任意一个 |
| `left` | `#b06bff` 紫 | `A S D F` |
| `right` | `#ffd166` 黄 | `J K L ;` |

键必须属于**该音符所在轨道的判定区**才算命中。

### 7.3 三个数值的换算（照抄这段就不会错）

```js
opacity   = alpha / 100                 // 0 ~ 1
speedMult = (speed * speed) / 100       // 10 → 1.00×，20 → 4.00×，100 → 100.00×
lenScale  = length / 10                 // 10 → 1.00×，0 → 0
```

`speed` 是**平方曲线**：中间值变化温和，往上越来越猛。

> **长条（hold）在预览里的长度 = `duration × 基础速度 × speedMult`** —— 流速越快长条越长。
> 流速为 0 时音符全压在判定线上、长条会缩成一条线，所以编辑器会回退到**时间上最近的非零流速**
> （先往回找，没有再往前找）；整条轨道从头到尾都是 0 时退回 `1.00×`。
> 时间轴（编辑区的方格）**不受流速影响**，永远按时间画。

### 7.4 `events` —— 轨道动画（7 条独立通道）

> **编辑器约定**：新建一条轨道时，6 个数值参数会各自在 `t = 0` 处自动生成一条
> `start: 0, end: 0.5, from: to: <默认值>` 的事件 —— 轨道的「基础参数」就存在这条事件里，
> 编辑器里**没有单独的参数输入框**。`lanes[i].x / y / alpha / ...` 这几个静态字段退化成
> 「这条通道没有任何事件时的兜底值」。游戏侧照下面的求值规则算就行。
>
> `zone` 通道**不会自动铺**：没有 `zone` 事件时一直用静态的 `judge_zone`。

```json
"events": {
  "x":        [ { "start": 2, "end": 6, "ease": "inOutQuad", "from": -60, "to": 60 } ],
  "alpha":    [ { "start": 2, "end": 4, "ease": "outCubic",  "from": 0,   "to": 100 } ],
  "rotation": [ { "start": 4, "end": 8, "ease": "outBack",   "from": 0,   "to": 90 } ],
  "zone":     [ { "start": 6, "end": 6, "ease": "linear",    "from": 1,   "to": 1 } ]
}
```

- 通道名：`x` / `y` / `alpha` / `rotation` / `speed` / `length` / `zone`
- 每个通道一个数组，数组里是事件；**通道之间完全独立**
- 事件字段：`start` `end`（秒）、`ease`（缓动名）、`from` `to`（该参数的数值，不是对象）
- `zone` 是**判定区通道**，值用数字表示：`0` = none（白）、`1` = left（紫）、`2` = right（黄）；
  求值后四舍五入取整再对应回名字，所以中间值只会落在三种状态之一。
  想「瞬间切换」就把 `start` 和 `end` 写成同一个值
- 同一通道里按 `start` 升序

**求值规则**（`laneParamsAt`）：

```js
function paramsAt(lane, t) {
  const p = { x: lane.x, y: lane.y, alpha: lane.alpha,
              rotation: lane.rotation, speed: lane.speed, length: lane.length };
  for (const key of ['x','y','alpha','rotation','speed','length']) {
    const list = (lane.events && lane.events[key]) || [];
    let cur = null;
    for (const ev of list) {          // 已按 start 升序
      if (ev.start <= t) cur = ev;    // 取「起点 ≤ t 且起点最晚」的那条
      else break;
    }
    if (!cur) continue;               // 这条通道没有事件 → 用静态值
    const span = cur.end - cur.start;
    const k = span > 0 ? clamp((t - cur.start) / span, 0, 1) : 1;
    p[key] = cur.from + (cur.to - cur.from) * easeAt(cur.ease, k);
  }
  return p;
}
```

**关键行为**：

- 事件还没开始时 → 用轨道静态值
- 事件进行中 → 从 `from` 缓动到 `to`
- **事件结束后保持 `to`，不回弹**，直到同通道的下一条事件开始
- 事件可以重叠，起点更晚的覆盖前面的

**判定区单独一个函数**（`zoneAt`），因为它的值是枚举不是连续量：

```js
const ZONE_NAMES = ['none', 'left', 'right'];   // 0 = 白, 1 = 紫, 2 = 黄

function zoneAt(lane, t) {
  const cur = eventAt(lane, 'zone', t);          // 和上面一样：起点 ≤ t 且最晚的那条
  if (!cur) return lane.judge_zone;              // 没有 zone 事件 → 静态值
  const span = cur.end - cur.start;
  const k = span > 1e-9 ? clamp((t - cur.start) / span, 0, 1) : 1;
  const v = cur.from + (cur.to - cur.from) * easeAt(cur.ease, k);
  return ZONE_NAMES[clamp(Math.round(v), 0, 2)];
}

function displayColorAt(lane, t) {               // 轨道该画成什么颜色
  const z = zoneAt(lane, t);
  return z === 'none' ? lane.color : { left: '#b06bff', right: '#ffd166' }[z];
}
```

## 8. `notes[i]` —— 一个音符

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `id` | int | | **仅编辑器用**，游戏不要依赖 |
| `time` | float | `0` | 到达判定线的谱面时间（秒），≥0 |
| `lane` | int | `0` | 轨道序号 `0 .. lanes.length-1` |
| `type` | string | `"tap"` | `tap` / `hold` / `flick` / `mine` |
| `duration` | float | `0` | **仅 `hold` 有意义**：按住时长（秒） |

`type` 语义：

| type | 玩法 |
| --- | --- |
| `tap` | 单击一次 |
| `hold` | 按住，直到 `time + duration` |
| `flick` | 划键 / 上滑 |
| `mine` | 地雷，**碰到扣血，不要按** |

`duration <= 0` 的 `hold` 在读取时会被当成 `tap`。

## 9. 缓动（`ease`）

内置名字（大小写敏感）：

```
linear  step
inSine  outSine  inOutSine
inQuad  outQuad  inOutQuad
inCubic outCubic inOutCubic
inQuart outQuart inOutQuart
inExpo  outExpo  inOutExpo
inBack  outBack  inOutBack
```

也可以写自定义曲线：`"bezier(0.25, 0.1, 0.25, 1)"`（和 CSS `cubic-bezier` 同一套算法）。

```js
// 参考实现（和编辑器一致）
function easeAt(name, k) {
  k = clamp(k, 0, 1);
  if (name.startsWith('bezier(')) return cubicBezier(...name)(k);
  const c1 = 1.70158, c3 = c1 + 1;
  switch (name) {
    case 'step':       return k < 1 ? 0 : 1;
    case 'inSine':     return 1 - Math.cos(k * Math.PI / 2);
    case 'outSine':    return Math.sin(k * Math.PI / 2);
    case 'inOutSine':  return -(Math.cos(Math.PI * k) - 1) / 2;
    case 'inQuad':     return k * k;
    case 'outQuad':    return 1 - (1 - k) * (1 - k);
    case 'inOutQuad':  return k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
    case 'inCubic':    return k * k * k;
    case 'outCubic':   return 1 - Math.pow(1 - k, 3);
    case 'inOutCubic': return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
    case 'inQuart':    return k * k * k * k;
    case 'outQuart':   return 1 - Math.pow(1 - k, 4);
    case 'inOutQuart': return k < 0.5 ? 8 * Math.pow(k, 4) : 1 - Math.pow(-2 * k + 2, 4) / 2;
    case 'inExpo':     return k === 0 ? 0 : Math.pow(2, 10 * k - 10);
    case 'outExpo':    return k === 1 ? 1 : 1 - Math.pow(2, -10 * k);
    case 'inOutExpo':  return k === 0 ? 0 : k === 1 ? 1
      : (k < 0.5 ? Math.pow(2, 20 * k - 10) / 2 : (2 - Math.pow(2, -20 * k + 20)) / 2);
    case 'inBack':     return c3 * k * k * k - c1 * k * k;
    case 'outBack':    return 1 + c3 * Math.pow(k - 1, 3) + c1 * Math.pow(k - 1, 2);
    case 'inOutBack':  return k < 0.5
      ? (Math.pow(2 * k, 2) * ((c1 + 1) * 2 * k - c1)) / 2
      : (Math.pow(2 * k - 2, 2) * ((c1 + 1) * (k * 2 - 2) + c1) + 2) / 2;
    default:           return k;
  }
}
```

实测值（`k = 0.5`）：`linear` 0.500，`inQuad` 0.250，`outQuad` 0.750，`inOutCubic` 0.500，
`outBack` 1.088（会冲过头），`bezier(.25,.1,.25,1)` ≈ 0.802。

## 10. 读取容错（照这个做，脏谱面也不会崩）

| 情况 | 处理 |
| --- | --- |
| 不是合法 JSON / 根不是对象 | 拒绝，返回原因 |
| 缺 `meta` / `audio` / `timing` / `stage` | 用默认值 |
| 缺 `lanes` | 按 `stage.lane_count` 生成默认轨道 |
| `lanes` 长度为 N | 轨道数就是 N（覆盖 `stage.lane_count`），上限 16 |
| `lane` 越界 | 夹到 `0..N-1` |
| `type` 不认识 | 当 `tap` |
| `hold` 的 `duration <= 0` | 当 `tap` |
| `time < 0` | 夹到 0 |
| `x` / `y` 超范围 | 夹到 ±2000 |
| `alpha` / `speed` / `length` 超范围 | 夹到 0~100 |
| `rotation` 超范围 | 夹到 ±3600 |
| `judge_zone` 写错 | 退回 `none` |
| `ease` 不认识 | 当 `linear` |
| 事件 `end < start` | `end` 夹到 `start`（零时长事件＝瞬间跳变） |
| 某通道的值不是数组 | 该通道忽略，退回静态值 |
| `id` 重复 | 不影响，编辑器重新编号 |
| 音符顺序乱 | 读取后按 `(time, lane)` 重排 |

## 11. 导出 zip 的结构

编辑器 `Ctrl+S` 导出一个 zip（store 模式，不压缩）：

```
Neon Pulse.zip
├── chart.json      谱面（就是上面这份）
├── song.mp3        音频（`audio.file` 同名）
└── cover.png       曲绘（`meta.cover` 同名）
```

文件名取自 `meta.title`（非法字符替换成 `_`）。没选音频 / 曲绘时对应条目就不存在。

游戏侧：解压 → 读 `chart.json` → 按 `audio.file` 和 `meta.cover` 找同目录的媒体文件。

> 编辑器本身也能**直接打开这个 zip**（`Ctrl+O`）：会把 `chart.json` 读成谱面，
> 同时把音频和曲绘从包里捞出来 —— 所以「导出 → 再打开」是完整往返的。
> 系统右键「压缩到 zip」生成的 deflate 包同样能开（走浏览器的 `DecompressionStream`）。

## 12. 手写最小谱面

```json
{
  "notes": [
    { "time": 0.0, "lane": 0 },
    { "time": 0.5, "lane": 1 },
    { "time": 1.0, "lane": 2 },
    { "time": 1.5, "lane": 3 }
  ]
}
```

默认 4 轨、默认参数、全是 tap。这就够跑起来了。

## 13. 在 JS 里读

```js
const RChart = require('./web/js/core.js');

const res = RChart.normalize(JSON.parse(text));
if (!res.chart) { console.error(res.warnings); return; }
if (res.warnings.length) console.warn('读入时的容错：', res.warnings);

const chart = res.chart;
console.log(chart.meta.title, chart.notes.length, '个音符');

// 某个时刻轨道长什么样
const lane = chart.lanes[0];
const p = RChart.laneParamsAt(lane, 3.0);   // { x, y, alpha, rotation, speed, length }

// 这条轨道能吃的键
const keys = RChart.laneKeys(lane);          // ['A','S','D','F']
const color = RChart.displayColor(lane);     // '#b06bff'
```

`web/js/core.js` 不依赖任何 DOM / 浏览器 API（只有 `zipStore` 用到 `TextEncoder`），
可以直接给游戏用，也可以照文档自己重写一遍。
