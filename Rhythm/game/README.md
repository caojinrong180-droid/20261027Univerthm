# Rhythm Game（Godot 4.7）

用 Godot 做的音游，读**网页版制谱器**导出的 `rchart v3` 谱面。
游玩画面按**制谱器「预渲染窗口」的绘制规则**重画：同样的线宽 / 颜色 / 剔除规则，
谱面里填的 `x / y` 像素值和制谱器里一致；舞台是 **16:9**，直接铺满 16:9 窗口。

> **工程里不带任何谱面**：`charts/` 是空的，谱面你自己做。
> 放法见 [`charts/README.md`](charts/README.md)。

---

## 跑起来

```powershell
# 打开编辑器
& 'C:\Users\Dy\Desktop\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\Dy\Desktop\Rhythm\game' --editor

# 或者直接运行
& 'C:\Users\Dy\Desktop\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\Dy\Desktop\Rhythm\game'
```

编辑器里也可以「导入」→ 选 `game/project.godot`，然后 **F5**。
主场景是**光敏性癫痫警告**（`scenes/warning.tscn`）：停 5 秒自动进入**开始界面**（`scenes/start.tscn`），
在开始界面点「开始」（或按 Enter / 空格）才进入**选曲界面**（`scenes/song_select.tscn`）。
空谱面库时选曲界面会提示你把 zip 拖进来。

窗口固定 **16:9**，默认开 **1920×1080**，可以随便拉伸缩放，拉伸时保持 16:9 不变形。
**画面永远按窗口的真实像素分辨率渲染**（1280×720 / 1920×1080 / 2560×1440 都是 1:1 出图），
放大窗口不会把低分辨率画面拉糊；想再清晰就按 **`F11` 全屏**（按屏幕原生分辨率画）。
UI 的虚拟分辨率是 1280×720，`canvas_items` 会按窗口等比放大所有控件。
游玩画面的舞台也是 **16:9**，直接铺满窗口（没有黑边）；判定线仍在画面高度的 85%。
和制谱器的预渲染窗口是同构的。

## 操作

| 场景 | 键 | 作用 |
| --- | --- | --- |
| 游戏 | `A S D F` / `J K L ;` | 打左 / 右判定区的轨道（`judge_zone = none` 的轨道任意键都吃） |
| | `Esc` | 暂停 / 继续 |
| | `R` | 重试 |
| | `F11` | 全屏 / 窗口（全屏按屏幕原生分辨率渲染，最清晰） |
| 警告 | 任意键 / 点击 | 跳过，直接进开始界面（不按也会 5 秒后自动进） |
| 开始 | `Enter` / `空格` | 进选曲界面 |
| | `Esc` | 退出 |
| 选曲 | `↑ ↓` | 选谱面 |
| | `Enter` | 开始 |
| | `A` | 自动演示（不会写进设置） |
| | `F5` / `S` / `Esc` | 刷新谱面库 / 设置 / 返回开始界面 |
| 暂停 | `Esc` `R` `Q` | 继续 / 重试 / 选曲 |
| 结算 | `R` / `Esc` | 重试 / 选曲 |
| 设置 | `◀ ▶` / `Esc` / `R` | 调值 / 返回 / 恢复默认 |

拖拽：把 `.zip`（制谱器导出的包）或 `.json` 拖进窗口会自动复制到 `user://charts` 并刷新。

## 1:1 复刻预渲染窗口

舞台不是"重新画一遍"，而是把 `web/js/editor.js` 里那套绘制逐函数搬过来：

| 制谱器（editor.js） | 游戏（stage_view.gd） |
| --- | --- |
| `computePreviewLayout()` | `_draw()` 里的逻辑尺寸常量 |
| `laneGeom()` | `_lane_geom()` |
| `drawLaneBody()` | `_draw_lane_body()` |
| `drawPreviewNotes()`（含剔除 / hold 回退流速） | `_draw_notes()` |
| `drawLaneJudge()` | `_draw_lane_judge()` |
| `noteQuad()` / `bandQuad()` | `_note_quad()` / `_band_quad()` |

**逻辑舞台 350 × 196.875（16:9）**，和窗口同比例，所以正好铺满：

| 量 | 值 |
| --- | --- |
| `judgeY` | `round(196.875 × 0.85) = 167` |
| 4 轨 `laneWidth` | `min(350×0.05, 350×0.43/4) × 1.75 = 30.6`（`PV_SCALE = 1.75`） |
| `halfW` / 音符半宽 / 音符半厚 | `14.81` / `13.81` / `2.0` |
| 判定线 | 底部一条实心圆角横条（两端圆角），粗细 = `halfW × 0.36`（4 轨 ≈ 5.3）；不画半透明光带 |
| 圆角 | 音符 / 长条 `NOTE_RADIUS = 2.4`；判定条两端圆角 |
| 轨道背景 | **完全透明**：只画两侧 1px 描边（`alpha × 0.16`），没有底色填充 |
| 音符高光 | 无（那条半透明高光线去掉了） |
| 长条（hold） | 身体靠头一端**实心**、直角（和头无缝接上）；靠尾一端圆角 + **渐变透明**（纯画法，判定/计分不受影响） |
| 长条超出轨道 | 尾巴被轨道长度截断时**硬切断**（不渐变、不圆角），不会看起来像半路消失 |
| 长条的头 | 头贴到判定线后会被裁掉一半，此时**身体自己带圆角帽**（_head），不会剩下一个方缺口 |
| 超长长条 | 绘制回看窗口 = max(最长 hold 时长 × 最大流速, 4s)（上限 60s），再长的长条也不会在半路被剔除 |
| 没接住的长条 | 不消失：整体压到 50% 透明度继续走，直到尾巴过判定线（渐变长度同时缩短，免得淡到看不见） |
| 自动演示 | 按键时带 lane_hint，同区相邻音符不会互相抢判（以前会漏按 → 断连击） |
| `pps` | `judgeY / 可视秒数`，可视秒数默认取谱面的 `stage.highway_length` |
| 舞台在窗口里的位置 | `scale = min(W/350, H/196.875)`，16:9 时正好 1280×720，没有黑边 |

绘制时 `draw_set_transform(origin, 0, scale)` 整体等比放大，所以像素位置、线宽比例、
音符厚度都跟预览一致，只是放大了。背景就是预览的 `#080a0e` 纯色，
**不画曲绘、不画渐变**（预览里也没有）；音符过判定线立刻消失、hold 身体跟着尾巴缩，
这些剔除规则也照预览来。

**游玩界面是极简 HUD**（照 UI 稿做的，全部画在屏幕坐标上，不参与舞台缩放）：

| 位置 | 内容 |
| --- | --- |
| 顶部 | 白色**歌曲进度条**（按音频 / 谱面里更长的一个算，左右铺满） |
| 左上 | `Combo 100`（等宽字体） |
| 右上 | 8 位补零的分数 + 下面一行准确率 `100%`（右对齐） |
| 左下 | 曲名（`meta.title`） |
| 右下 | 等级（`Lv.5`） |

HUD 的数字和文字每次重绘都会跟着判定器走（`hud_progress()` / `hud_score_text()` 等几个小函数负责取字），
没有血条 / 血量、没有判定弹字、没有倒计时。想往上/下微调整块画面，用 `设置 → 界面 → 画面垂直偏移`
（默认 **-24px**）。

剩下的只有打击特效（设置里可以关成纯预览）和判定区动画：

- 打击特效：一圈判定环（FX_RING_START/GROW/WIDTH 控制起半径、扩散量、线宽）；设置里可以关成纯预览；锚点用 _lane_fx_anchor() 在命中那一刻定死，轨道瞬移时不会被拽着走
- 多押提示：同一时刻（±CHORD_EPS = 20ms）有 ≥2 个可判定音符时，这几颗 note 外圈会有一层**柔和的蓝光**（由外到内叠 6 层低透明度圆角块，没有硬描边；_draw_chord_glow()），地雷不算；CHORD_GLOW 是发光色，跟「打击特效」开关无关、永远显示
- 判定区：**`zone` 事件通道也支持**（`events.zone`，数值 0/1/2 → none/left/right，带缓动插值），
  轨道颜色和可用按键都会跟着时间变（对齐 `core.js` 的 `zoneAt` / `displayColorAt`）
- 舞台外的内容会被盖掉（`_draw_letterbox`）：谱面里 `x / y / length` 再离谱也画不出 16:9 舞台

## 谱面

支持三种形态，和 [`../docs/CHART_FORMAT.md`](../docs/CHART_FORMAT.md) 一致：

| 形态 | 说明 |
| --- | --- |
| `xxx.zip` | 制谱器 Ctrl+S 导出：`chart.json` + 音频 + 曲绘 |
| 文件夹 | `charts/曲名/` 里有 `chart.json`，音频/曲绘放同层 |
| `xxx.json` / `xxx.rchart` | 单文件，音频去同目录 / `res://audio` / `user://audio` 找 |

扫描目录：`res://charts/`（随游戏发布）和 `user://charts/`（选曲界面「谱面目录」能打开）。
`chart.json` 缺字段、`lane` 越界、类型不认识等容错规则全部照文档实现（`RhythmChart.parse`）。

## 目录结构

```
game/
  project.godot              工程设置（1280×720 虚拟分辨率 / 1920×1080 窗口，canvas_items 拉伸）
  scenes/                    6 个场景：警告 / 开始 / 选曲 / 游玩 / 结算 / 设置（界面都是代码搭的）
  src/
    app.gd                   autoload「App」：设置 + 谱面库 + 本次游玩会话 + 结算数据
    core/
      rhythm_chart.gd        数据层：读谱容错、lane 参数、事件求值、缓动、音符换算
      judge.gd               判定引擎：tap / hold / flick / mine、连击、分数（纯逻辑）
      chart_source.gd        谱面发现与加载（zip / 文件夹 / json、音频与曲绘字节 → 资源）
      settings.gd            玩家设置（user://settings.cfg 读写）
    game/
      stage_view.gd          舞台渲染：1:1 复刻制谱器预渲染窗口（_draw）+ 打击特效
      gameplay.gd            游玩流程：倒计时 → 音频时钟 → 判定 → 暂停 → 结算
    ui/
      palette.gd             全部颜色（换皮先改这里）
      theme_builder.gd       Theme：字体 / 按钮 / 面板 / 滚动条 / 进度条
      ui_kit.gd              建控件的小函数（label / button / panel / chip / stepper…）
    screens/
      warning.gd             启动：光敏性癫痫警告（5 秒自动继续，任意键 / 点击可跳过）
      start.gd               开始界面：标题 +「开始」按钮（Enter / 空格）
      song_select.gd         选曲：列表 + 详情 + 拖拽导入 + 空状态提示
      settings_screen.gd     设置项
      results.gd             结算
  audio/hit.wav              打击音（可换）
  charts/                    ← 你的谱面放这里（现在只有 README）
  tests/
    run_core_tests.gd        纯逻辑单测（headless）
    smoke.tscn / smoke.gd    界面 + 玩法冒烟（自动演示把测试谱面打通）
    realtime.tscn / realtime.gd  真实音频时钟自检（需要窗口 / 声卡）
    shot.tscn / shot.gd      截图脚本（开发自查用）
    fixtures/synthetic_chart.gd  测试用合成谱面（只在测试里，不写盘、不进 charts）
```

## 判定 / 评分

判定窗口（`settings.judge_window_scale` 会整体缩放，默认 1.00×）：

| 判定 | 时间窗 | 权重 |
| --- | --- | --- |
| PERFECT+ | ≤ 55 ms | 100% |
| PERFECT | ≤ 80 ms | 100% |
| GOOD | 80 ~ 160 ms | 75% |
| MISS | 超过 160 ms 没打 / hold 断了（**没有 BAD 判定**） | 0% |

- 按键找音符：轨道判定区接受这个键 + 未判定 + `|dt| ≤ 160ms`（Good 窗口），取 `|dt|` 最近的那个；超过就完全打不中
- **分数**：`1,000,000 × (Σ权重 / 可判定音符数) + 10,000 × (Perfect+ 数 / 可判定音符数)`
  - 全 Perfect+ = **1,010,000**（非 Perfect+ 部分满分 1,000,000，Perfect+ 单独再算 10,000）
  - 没有连击加成，分数只由准确率决定
- **ACC（准确率）**：`Σ权重 / 判定数`（实时）/ `Σ权重 / 可判定音符数`（结算）
  - Perfect+ / Perfect 记 100%，Good 记 75%，Miss 记 0%
  - **Early / Late**：Perfect 和 Good 各分「早按 / 晚按」计数（`judge.early_late`），结算界面单独显示一行；Perfect+ 不区分
- 没有血量条也没有失败：漏了就是漏了，谱面一定播完（结算照常出评级）
- 评级：≥96% `S`，≥92% `A`，≥85% `B`，≥75% `C`，其余 `D`
- 徽章：`ALL PERFECT+`（全 Perfect+）、`ALL PERFECT`（全 PERFECT 及以上）、`FULL COMBO`（0 MISS）

四种音符：

| type | 行为 |
| --- | --- |
| `tap` | 按到就判 |
| `hold` | 头判命中后**只要键盘上还有任意键按着**就算保持（换手、换边、zone 事件切到另一侧都不算断）；所有键都松开才断（撤掉判定记 MISS）；按到尾部 → 完成 |
| `flick` | 当前用按键触发（和 tap 一样），没做滑动识别 |
| `mine` | **不要按**。按到（±120ms、同判定区）断连击、记 MINE；自然过线无事、不计入准确率与分数 |

> 一个音符只产生一次判定：hold 的头判就是它的判定，断了会降级成 MISS。

## 打击音效 / 打击特效

**打击音**：`audio/hit.wav`，命中的音符响一次（hold 只响头；空打不响）。

- 设置里能调 **音量**（带「试听」按钮）和 **开关**
- **暂停面板里也能改**（打击音 / 打击音音量 / 打击特效），改完立刻生效并存盘
- 音量直接在 `AudioStreamPlayer.volume_db` 上改（`linear_to_db`），每次命中前会再同步一次

**打击特效**（`settings.hit_fx`，三档）：

| 档位 | 内容 |
| --- | --- |
| 关 | 什么特效都不画（纯预渲染画面） |
| 标准 | 一圈判定环（略细） |
| 强（默认） | 一圈判定环（更粗）；地雷爆炸红环 + 强屏震 |

判定档位不一样的反馈（颜色在 [src/ui/palette.gd](src/ui/palette.gd) 的 `JUDGE_COLORS`）：

| 判定 | 颜色 | 特效 |
| --- | --- | --- |
| PERFECT+ / PERFECT | 紫 `#b06bff` | **同一个效果**：一圈粗判定环（**不屏震**） |
| GOOD | 蓝 `#4c9aff` | 同上，一圈判定环（**不屏震**） |
| MISS | — | **没有任何特效**（不画红叉，音符直接过线消失） |
| 踩雷 | 红 | 红环 + 强屏震 |

- `hold` 按到尾部有一个紫色的完成环；**hold 吃到 MISS 不会立刻消失**，
  而是压到 50% 透明度继续挂着，等尾巴过判定线才消失
- 轨道本体和判定线**不做任何「击打变亮」**：命中时只有屏幕坐标上的那一圈判定环，
  轨道颜色、亮度、判定线宽度都只由谱面本身（`alpha` / `color` / `zone`）决定，和预渲染窗口完全一致
- 全部在 [src/game/stage_view.gd](src/game/stage_view.gd) 的「打击特效」一节：
  `_draw_fx()` 画判定环（`_fx_color()` 决定颜色，Perfect+ 与 Perfect 同色）、
  `_add_shake()` 屏震（现在只有踩雷会震）；寿命常量在文件顶部
  （`FX_RING_START` / `FX_RING_GROW` / `FX_RING_WIDTH` / `FX_RING_LIFE`）

## 和 docs 的对应（硬约束都在这）

| 规范 | 实现位置 |
| --- | --- |
| `judge_y = round(H × 0.85)`、`cx = W/2 + x`、`cy = judge_y − y` | `stage_view.gd::_draw` / `_lane_geom` |
| `dir = Vector2.UP.rotated(rad)`（0° 朝上、顺时针为正） | 同上 |
| `lane_w = min(W×0.05, W×0.43/N)`、`half_w = max(2, lane_w/2 − 0.5)` | 同上 |
| `d = (note.time − t) × base_pps × speedMult`，`speedMult = speed²/100` | `_draw_notes` |
| `laneLen = judge_y × length/10`，透明度只藏轨道不藏音符 | `_draw_lane_body` / `_draw_notes` |
| 渲染顺序：轨道 → 音符 → 判定线（判定线最后画） | `_draw` 分三趟画 |
| 事件 6 通道、结束后保持尾值不回弹 | `rhythm_chart.gd::lane_params_at` |
| hold 在流速 0 时回退到最近的非零流速 | `rhythm_chart.gd::hold_speed_mult`（对齐 core.js `holdSpeed`） |
| 缓动（含 `bezier(...)`，数值和网页版一致） | `rhythm_chart.gd::ease_at` |
| 谱面时间 = 音频时间 − `audio.offset` − 玩家偏移 | `gameplay.gd::_chart_offset/_sample_audio_time` |
| 16:9 像素值自洽 | 逻辑 350×196.875 → 16:9 窗口里正好铺满 |

`base_pps = judge_y / 可视秒数`，可视秒数 = 谱面 `stage.highway_length` / `settings.speed_mult`
（默认 2 秒，和制谱器预览一致）。

## 设置

| 项 | 默认 | 说明 |
| --- | --- | --- |
| 音画偏移 | 0 ms | 正数 = 谱面整体推后；蓝牙耳机有延迟就调它 |
| 下落速度 | 1.00× | 判定线→画面顶的秒数 = 2.0 / 倍率 |
| 判定窗口 | 1.00× | 55 / 80 / 160 ms 整体缩放 |
| 自动演示 | 关 | 选曲界面按 `A` 也可以一次性开 |
| 音乐/打击音音量 | 85% / 60% | 打击音音量旁边有「试听」 |
| 打击音 | 开 | 暂停面板里也能切 |
| 打击特效 | 强 | 关 / 标准 / 强（判定环粗细；只有踩雷会屏震） |
| 键位布局 | `ASDF / JKL;` | 另一套是 `DF / JK` |
| 画面垂直偏移 | -24 px | 在居中的基础上往上抬一点；调 0 = 严格居中 |

存档：`user://settings.cfg`（Windows ≈ `%APPDATA%\Godot\app_userdata\Rhythm Game\settings.cfg`）。

## 美化（留给你）

改这几处就够了：

- **颜色**：`src/ui/palette.gd`（现在是制谱器那套深色 + 青/紫/黄）
- **字体 / 控件外观**：`src/ui/theme_builder.gd`（`SystemFont` 取系统字体）
  - `sans()`：**Bahnschrift 500**（DIN 风、中等粗细）→ 中文自动回落到 Noto Sans SC / 雅黑
  - `mono()`：**Noto Sans SC 500**（数字等宽、`0` 是干净椭圆；别用 Cascadia Mono / Consolas，
    它们的 0 带点或斜杠）
  - HUD 的分数用 `_draw_fixed_digits()` 按固定字宽画，位数变化时右边不动
  - 想换成像素/赛博字体：把 `.ttf` 放进 `src/ui/`，在 `sans()` / `mono()` 里 `preload` 一个 `FontFile` 就行
- **游玩画面**：`src/game/stage_view.gd` 现在是 1:1 复刻预渲染窗口 —— 想加东西就加在这一层：
  背景是 `_draw()` 开头那块 `#080a0e`（想换成曲绘 / 渐变就改这里）；音符外形在 `_draw_notes()`；
  轨道和判定线在 `_draw_lane_body()` / `_draw_lane_judge()`；打击特效在 `_draw_fx()`（屏幕坐标，
  寿命和数量都在文件顶部常量里）。**公式和常量别动**，动了就跟制谱器预览对不上了
- **菜单 / 结算 / 设置**：`src/screens/*.gd`，用 `UiKit` 拼的，间距、顺序、字号都是明码
- **曲绘**：预渲染窗口里没有曲绘，所以游玩画面不画；选曲和结算界面会用 `meta.cover`
- **故事板**（可选）：包里带 `storyboard.json` 就自动读（`src/core/storyboard_source.gd`）
  - **解锁动画**：进谱面前播一次（`src/game/unlock_frames.gd`），播的是谱面包里**导入的那个视频**——
    由 `tools/bake_unlock.ps1` 烘焙成 `unlock_frames/*.jpg` + `unlock_audio.ogg` + `unlock.json`
    （本机 ffmpeg 的 libtheora 编码坏的，产不出可播 ogv，所以走帧序列）；任意键 / 点击跳过；`debug_mode` / 无头模式自动跳过
  - 谱面场的**后处理 Shader** 已生效：一条 shader = 一层，逐层叠加（`shaders/story_grade.gdshader` + `src/game/stage_post.gd`，
    每层一个 ColorRect，层间插 `BackBufferCopy`），14 种预设和网页版同一套公式
  - **解锁动画 / 文字 / 图片 / 形状图层还没画**（Godot 端只做了解析，图层渲染待补）
- **曲绘作者**：谱面 `meta.illustrator`（制谱器侧栏「曲绘画师」那栏）。选曲详情在「谱师」下面多一行
  「曲绘 XXX」，结算界面标题下面也会显示；空串就整行不占位（老谱面不用改）

界面是代码搭的而不是编辑器场景，好处是换皮只动少数几个文件、不用挨个场景点节点；
想改成场景也很容易——每个 `_build()` 里的结构就是节点树。

## 测试

```powershell
# 纯逻辑（数据层 + 判定 + 加载）
& 'Godot...console.exe' --headless --path game --script res://tests/run_core_tests.gd

# 界面 + 玩法冒烟（自动演示把测试谱面打通，检查 1:1 几何常量 / 100% 准确率 / 结算 / 失败路径）
& 'Godot...console.exe' --headless --path game res://tests/smoke.tscn

# 真实音频时钟自检（要窗口 + 声卡，约 5 秒；顺带验打击音播放 / 音量 / 开关和特效产出）
& 'Godot...console.exe' --path game res://tests/realtime.tscn

# 截图（要窗口，会写到 tests/_shots/，已在 .gitignore）
& 'Godot...console.exe' --path game res://tests/shot.tscn
```

`tests/fixtures/synthetic_chart.gd` 是**测试专用的合成谱面**：运行时在内存里拼出来，
不写盘、不放进 `charts/`，只为了在没有真实谱面的情况下验证渲染和判定。

## 已知限制

- 不支持变速：`timing.bpm_events` 只取第一个 BPM（会告警）
- `flick` 没有滑动/触屏判定，按键即算
- 只有键盘判定，没有触摸音符、没有准星
- 键位只有两套预设，没有自定义映射
- 不保存成绩 / 排行 / 最佳记录
- 导出 exe 时记得把 `*.json`、`*.wav` 之类加进导出资源过滤（或者让玩家把歌放进 `user://charts`）
