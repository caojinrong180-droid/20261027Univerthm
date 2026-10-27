# 游戏侧对接规范 · 玩法 / 渲染 / 判定

> 配合 [CHART_FORMAT.md](CHART_FORMAT.md) 看。这份文档讲**怎么把谱面变成画面和判定**。
>
> 凡标「**硬约束**」的，是编辑器已经定死、游戏照做才能和预览窗口长得一样的；
> 凡标「**建议**」的，是还没实现、你可以自己定，我给的默认值只是参考。

---

## 1. 数据流

```
zip → 解压 → chart.json (+ 音频 + 曲绘)
                  │
                  ├─ 编辑器 / 游戏共用的数据层：web/js/core.js
                  │    normalize()      容错读取
                  │    laneParamsAt()   某个时刻某条轨道的 6 个参数（含事件动画）
                  │    laneKeys()       这条轨道能吃哪些键
                  │    displayColor()   这条轨道画什么颜色
                  │
                  └─ 渲染：每帧 for 每条轨道 → 取参数 → 画轨道 + 画音符
                     判定：按键 → 找匹配的未判定音符 → 出判定
```

`web/js/core.js` 不碰 DOM，可以直接 `require` 进游戏；也可以照文档重写一遍。

---

## 2. 坐标系与渲染公式（**硬约束**）

编辑器预渲染窗口里的数学，原样搬到游戏里就能对上。下面 `W × H` 是舞台画面尺寸。

### 2.1 基准量

```js
const judgeY = Math.round(H * 0.85);                       // 判定线高度
const laneWidth = Math.min(W * 0.05, (W * 0.43) / laneCount); // 单条轨道宽度
const halfW = Math.max(2, laneWidth / 2 - 0.5);            // 轨道半宽
const noteHalfW = Math.max(2, halfW - 1);                  // 音符半宽
const NOTE_TH = 1.25;                                      // 音符半厚
```

### 2.2 每条轨道（每帧算一次，带上事件动画）

```js
const p = laneParamsAt(lane, t);        // 6 个参数，见格式文档 7.4
const rad = p.rotation * Math.PI / 180;

const cx = W / 2 + p.x;                 // 基点 x（舞台正中 + x）
const cy = judgeY - p.y;                // 基点 y（注意是减：Y 向上为正）

const dx =  Math.sin(rad), dy = -Math.cos(rad);  // 沿轨道方向的单位向量（0° 时朝上）
const sx =  Math.cos(rad), sy =  Math.sin(rad);  // 横向单位向量（0° 时朝右）

const opacity = p.alpha / 100;                    // 0~1
const speedMult = (p.speed * p.speed) / 100;      // 10 → 1.00×
const laneLen = judgeY * (p.length / 10);         // 轨道像素长度，0 = 只剩判定线
```

### 2.2.1 父子线（`parent`）

父线是一个**事件通道**（`events.parent`），值 `0` = 没有父线、`i + 1` = 挂在第 `i` 条上，
所以它会随时间变、也能取消。用 `parentAt(lane, t, laneCount)` 取当前父线（没有事件时退回静态 `parent`）：

`js
const parentIdx = parentAt(lane, t, lanes.length);   // -1 = 不挂
` 

拿到 `parentIdx >= 0` 时，这条轨道的 `x / y / rotation` 都是**相对父线**的：

```js
function laneFrame(lane, t, lanes) {
  const p = laneParamsAt(lane, t);
  const pi = parentAt(lane, t, lanes.length);        // 父线也是事件，会随时间变
  const parent = (pi >= 0 && pi < lanes.length) ? lanes[pi] : null;
  if (!parent) {
    return { cx: W / 2 + p.x, cy: judgeY - p.y, rot: p.rotation };
  }
  const pf = laneFrame(parent, t, lanes);            // 递归，天然支持「爷爷线」
  const prad = pf.rot * Math.PI / 180;
  return {
    cx: pf.cx + Math.cos(prad) * p.x + Math.sin(prad) * p.y,
    cy: pf.cy + Math.sin(prad) * p.x - Math.cos(prad) * p.y,
    rot: pf.rot + p.rotation                            // 角度叠加
  };
}
```

拿到 `{cx, cy, rot}` 之后，`dx / dy / sx / sy` 就按 2.2 节用 `rot` 算 —— 子线的音符、
判定线、长条全都跟着父线走。

> 递归层数做个数上限（比如 8），防止手改 JSON 时写出环卡死。

### 2.3 轨道本体

一条从基点沿 `(dx, dy)` 延伸 `laneLen` 的平行四边形，宽 `2 * halfW`：

```js
function laneQuad(cx, cy, dx, dy, sx, sy, halfW, len) {
  return [
    { x: cx - sx * halfW,          y: cy - sy * halfW },
    { x: cx + sx * halfW,          y: cy + sy * halfW },
    { x: cx + sx * halfW + dx * len, y: cy + sy * halfW + dy * len },
    { x: cx - sx * halfW + dx * len, y: cy - sy * halfW + dy * len }
  ];
}
```

- 填充：`rgba(255,255,255,0.03)`，整块乘 `opacity`
- 两条长边描 `displayColor(lane)` 的 16% 透明度

### 2.4 判定线

每条轨道自己在 `d = 0` 处画一段横线（宽 `2 * halfW`），颜色 `displayColor(lane)`，`lineWidth ≈ 1.2`，
外加一块 ±2.5px 的淡光晕。**不是一条贯穿全屏的线** —— 轨道挪开/旋转后判定线跟着走。

`opacity = 0` 时轨道本体和判定线都不画。

### 2.5 音符位置

```js
// t = 当前谱面时间（秒），note.time = 音符到达判定线的时间
const d = (note.time - t) * basePps * speedMult;   // 距判定线的距离（沿轨道方向，正数=在上方）
const px = cx + dx * d;
const py = cy + dy * d;
```

`basePps` = **基础下落速度（像素/秒）**，由你自己定。
编辑器预览里 `basePps = judgeY / 可视秒数`（默认可视 2 秒，即 `judgeY / 2`）。

> 建议：把 `basePps` 做成难度相关的设置项。`speedMult` 是**单条轨道**的倍率，会叠乘上去。

### 2.6 音符外形

音符是以 `(px, py)` 为中心、宽 `2 * noteHalfW`、厚 `2 * NOTE_TH` 的四边形：

```js
function noteQuad(px, py, dx, dy, sx, sy, halfW, th) {
  return [
    { x: px - sx * halfW - dx * th, y: py - sy * halfW - dy * th },  // 靠判定线那侧
    { x: px + sx * halfW - dx * th, y: py + sy * halfW - dy * th },
    { x: px + sx * halfW + dx * th, y: py + sy * halfW + dy * th },
    { x: px - sx * halfW + dx * th, y: py - sy * halfW + dy * th }
  ];
}
```

各种类型：

| type | 画法 |
| --- | --- |
| `tap` | 实心 `displayColor` 92% + 靠判定线一侧一条白色 55% 高光线 |
| `hold` | 从 `d(头部)` 到 `d(尾部)` 画一条半透明长条（`displayColor` 30%），头部再画上面那种 tap 块 |

`hold` 的长条：`dHead = (note.time - t) * ...`，`dTail = (note.time + note.duration - t) * ...`，
两者之间的部分用同一个 `laneQuad` 画，宽度收窄 2~3px。

**流速对角色的影响要注意 0 这个坑**：

```js
const speedMult = (lane.speed * lane.speed) / 100;
// 长条长度 = duration * basePps * speedMult → 流速越快长条越长
```

流速为 0 时所有音符都钉在判定线上，长条会缩成一条线。编辑器里的处理是
**回退到时间上最近的非零流速**（`RC.holdSpeed(lane, note.time)`）：
先往回找、没有再往前找、全程都是 0 就用 `1.00×`。游戏侧可以用同一个函数保持观感一致
（判定逻辑不受影响，0 流速只是视觉上的）。

> 时间轴（编辑器的方格区）不按流速画，永远按时间；只有舞台预览是「高速 = 长条拉长」。

### 2.6.1 音符到判定线之后怎么办

音符的 `head` 会随时间变成负数（过线了）。**不要让它继续往下掉**，编辑器/预览的做法是：

```js
// 普通音符（tap）：落到判定线就消失，不做淡出
if (head < 0) continue;

// hold：头贴在判定线上，身体随尾巴缩进去；按 tail 剔除
const headDraw = Math.max(0, head);
if (tail < -10) continue;
```

长条尤其要注意：**剔除要看 `tail` 不看 `head`**，否则头一过线整条就没了，
明明身上还有一大截。

### 2.7 分辨率怎么处理（**重要**）

编辑器里 `x / y` 的像素值是相对 **4:3 预览窗**算的。游戏分辨率不同（16:9、手机竖屏）时，
两种做法二选一，别混：

1. **推荐**：先按固定虚拟分辨率渲染（比如 `1280 × 720`），再整图缩放到实际窗口。
   这样谱面里的像素值和任何屏幕都自洽。
2. 或者按 `实际宽 / 预览宽` 等比缩放 `x`、`y`、`laneWidth`，保证构图比例一致。

---

## 3. 判定（**建议**，编辑器里没有实现）

### 3.1 按键 → 轨道

```js
const KEY_ZONE = {
  A: 'left', S: 'left', D: 'left', F: 'left',
  J: 'right', K: 'right', L: 'right', ';': 'right'
};
```

一条轨道能不能吃某个键：

```js
// zone 会随时间变，所以按音符自己的时刻取
const zone = zoneAt(chart.lanes[i], note.time);   // 'none' | 'left' | 'right'
const ok = (zone === 'none') || (zone === KEY_ZONE[key]);
```

即：`none` 的轨道**任何键都能吃**，`left` 只吃 `ASDF`，`right` 只吃 `JKL;`。

> 判定区也能做成事件（`zone` 通道，值 0/1/2）随时间切换，见格式文档 7.4。
> 这种情况要用 **`zoneAt(lane, note.time)`** —— 按**音符自己的时刻**取判定区，
> 不能用当前时刻（否则滑过切换点的音符会突然打不中）。

### 3.2 找音符

按了键之后：

1. 遍历所有**未判定**的音符
2. 跳过轨道判定区不接受这个键的
3. 跳过时间差超过窗口的
4. 剩下的里取 **|dt| 最小** 的那个（多条 `none` 轨道同时能接这个键时，靠时间最近决定）

```js
function judgePress(key, now) {
  const zone = KEY_ZONE[key];
  let best = null;
  for (const note of chart.notes) {
    if (note.judged) continue;
    const lz = chart.lanes[note.lane].judge_zone;
    if (lz !== 'none' && lz !== zone) continue;
    const dt = now - note.time;
    if (Math.abs(dt) > BAD_WINDOW) continue;
    if (!best || Math.abs(dt) < Math.abs(best.dt)) best = { note, dt };
  }
  return best;   // 没有就是空打
}
```

### 3.3 判定窗口建议

| 判定 | 时间窗（`|now - note.time|`） | 权重 |
| --- | --- | --- |
| PERFECT | ≤ 45 ms | 100% |
| GOOD | ≤ 90 ms | 65% |
| BAD | ≤ 135 ms | 30% |
| MISS | 超过 135 ms 未打 | 0 |

超过窗口还没打的音符，在 `t > note.time + BAD_WINDOW` 时判 MISS。

### 3.4 四种音符的行为建议

| type | 判定 |
| --- | --- |
| `tap` | 按下时按 3.2 找音符，命中即判 |
| `hold` | 头判同上；之后要求一直按住到 `time + duration`。中途松开 → hold 断开（判 MISS 或 BREAK），到尾部还在按 → 按时间差判 |

### 3.5 分数与连击建议

```
单音符得分 = 权重 × 1000
连击加成   = 1 + min(combo, 100) / 200        // 最多 1.5 倍
总分       = Σ (单音符得分 × 连击加成)
准确率     = Σ 权重 / 音符总数
```

评级随便定（S/A/B/C 或 EX/FC）。这些和谱面数据无关，纯粹是设计选择。

---

## 4. 音频同步（**硬约束**）

```
谱面时间 = 音频当前时间 − audio.offset
```

- 编辑器存盘时 `audio.offset` 就是按这个方向记的
- 开局 `audio.currentTime = 0`，则谱面时间从 `-offset` 开始（offset 为正时谱面「晚」开始）
- 音画不同步就调 `offset`，**不要**去批量改音符时间

打击音（可选）：编辑器用 `web/audio/hit.wav` 做音符过线提示，
游戏里可以用自己的音效，**每个音符响一次**（hold 只响头）。

---

## 5. 哪些是硬约束，哪些随便改

| 项目 | 是否硬约束 |
| --- | --- |
| `judgeY = H × 0.85` | 硬约束（预览就是这么画的） |
| `cx = W/2 + x`、`cy = judgeY - y` | 硬约束 |
| `rotation` 顺时针为正、0 = 朝上 | 硬约束 |
| `d = Δt × basePps × speedMult` | 公式硬约束，`basePps` 自由 |
| `speedMult = speed² / 100` | 硬约束（平方曲线） |
| `opacity = alpha / 100`，不影响音符 | 硬约束 |
| `laneLen = judgeY × length / 10` | 硬约束 |
| 事件求值规则（含「结束后不回弹」） | 硬约束 |
| 轨道宽度比例 `min(W×0.05, W×0.43/N)` | 建议照抄，想改也不影响数据 |
| 判定窗口、分数、连击、评级 | 完全自由 |
| 音符颜色 / 高光 / 圆角 | 自由（判定区颜色建议照抄） |

**一条最容易踩的**：判定按 **lane 索引**，不看屏幕位置。轨道 `x/y/rotation` 动了只是画面动，
玩家该按的键不变。除非你想做「跟着轨道走的触摸判定」，那是另一套设计。

---

## 6. 最小实现骨架

```js
const RChart = require('./web/js/core.js');

// ---- 加载 ----
const chart = RChart.normalize(JSON.parse(jsonText)).chart;

// ---- 每帧渲染 ----
function render(t) {                 // t = 谱面时间（秒）
  const W = canvas.width, H = canvas.height;
  const judgeY = Math.round(H * 0.85);
  const laneW = Math.min(W * 0.05, (W * 0.43) / chart.lanes.length);
  const halfW = Math.max(2, laneW / 2 - 0.5);

  for (let i = 0; i < chart.lanes.length; i++) {
    const lane = chart.lanes[i];
    const p = RChart.laneParamsAt(lane, t);

    const rad = p.rotation * Math.PI / 180;
    const cx = W / 2 + p.x;
    const cy = judgeY - p.y;
    const dx = Math.sin(rad), dy = -Math.cos(rad);
    const sx = Math.cos(rad), sy = Math.sin(rad);
    const opacity = p.alpha / 100;
    const speedMult = p.speed * p.speed / 100;
    const laneLen = judgeY * (p.length / 10);

    drawLane(cx, cy, dx, dy, sx, sy, halfW, laneLen, RChart.displayColor(lane), opacity);
    drawJudgeLine(cx, cy, sx, sy, halfW, RChart.displayColor(lane), opacity);

    if (opacity <= 0) { /* 轨道本体不画，但下面的音符照画 */ }

    // 这条轨道上的音符
    for (const note of notesByLane[i]) {
      const d = (note.time - t) * BASE_PPS * speedMult;
      if (d < 0 || d > laneLen + 40) continue;          // 过线了 / 还没进视野
      drawNote(cx + dx * d, cy + dy * d, dx, dy, sx, sy, note, RChart.displayColor(lane));
    }
  }
}

// ---- 按键 ----
onkeydown = (e) => {
  const key = e.key.toUpperCase();
  if (!(key in KEY_ZONE)) return;
  const hit = judgePress(key, chartTimeNow());
  if (hit) playHitSound(), markJudged(hit);
};
```

---

## 7. 常见坑

1. **Y 轴方向**：谱面的 `y` 向上为正，画布 `y` 向下为正，所以是 `cy = judgeY - y`。
2. **透明度默认 0**：新谱面的轨道默认全隐藏，游戏里如果没给轨道本体画出来只剩音符，是**数据问题不是 bug** —— 让谱师把它调大。
3. **`speed` 是平方**：想「2 倍速」要填 `14.14` 左右（≈`√200`），填 `20` 是 **4 倍**。
4. **`length` 是绝对长度不是倍率**：`10` 才是标准全长，`0` 只剩判定线（连音符也画不出来了）。
5. **事件结束不回弹**：一条 `x` 从 -60 到 60 的事件跑完后，轨道一直待在 60，直到下一条 `x` 事件。
6. **判定按 lane 索引**，不是按位置。
7. **音符时间是绝对秒**，别用 BPM 去反推。
8. **zip 里文件名要和 json 字段一致**：`audio.file` / `meta.cover`。

## 故事板（rstory v2）

故事板导出包和谱面放在一起时，游戏会一起读：

- `game/src/core/storyboard_source.gd` —— 解析 + 时间轴（`scene_spans` / `scene_at` / `active_shaders`）
- `game/shaders/story_grade.gdshader` —— 后处理主着色器（14 种效果，权重 uniform）
- `game/src/game/stage_post.gd` —— 逐层叠加层（每条 shader 一层 ColorRect + BackBufferCopy）
- `gameplay.gd` 每帧用 `StoryboardSource.active_shaders(谱面场, chart_time)` 刷新 uniform

- `game/src/game/unlock_anim.gd` —— 解锁动画（7 种预设），gameplay 在倒计时之前播一次（`State.UNLOCK`），
  时长/预设取故事板解锁场，缺省 tape + 2.6s；任意键跳过；`debug_mode` / headless 自动跳过

注意：读 `storyboard.json` 必须用**原生 JSON 解析**（`ChartSource._parse_raw_json_bytes`），
不能再走 `RhythmChart.parse` —— 那样会被归一化成谱面结构，`scenes` 全丢，游戏里就“看不到 Shader”。

- `game/src/game/unlock_frames.gd` —— 解锁动画：播 `unlock_frames/*.jpg`（`unlock.json` 给 fps/时长）+ `unlock_audio.ogg`，
  gameplay 在倒计时前播一次（`State.UNLOCK`），任意键跳过

目前生效的是**后处理 + 解锁动画**；文字 / 图片 / 形状图层还没在 Godot 里画。
解锁动画如果用的是**导入的视频图层**（而不是内置 7 种预设），游戏里目前播不出那段视频（C 方案不读图层），会退回内置动画。
