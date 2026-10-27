# Rhythm

音游工具链：**网页版制谱器** + **故事板制作器** + **Godot 音游** + 两边共用的规范文档。

- **`web/`** —— 制谱器（纯前端，双击 `web/index.html` 就能用）。
  入口文档：[web/README.md](web/README.md)
- **`web/storyboard.html`** —— **故事板制作器**：导入谱面（**只读**，不改谱面）→
  叠解锁动画 / 文字特效 / Shader 后处理 → 存工程、导出整包、截图、录屏。
  入口文档：[web/STORYBOARD.md](web/STORYBOARD.md)
- **`tutorial/`** —— **新手教程**：用 DataErr0r（180 BPM）从 tap 写到完整谱面，
  四课四份分步谱面（176 / 224 / 364 / 472 音符），每份都配一个能直接拖进游戏的 `.zip` 整包。
  入口文档：[tutorial/README.md](tutorial/README.md)
- **`game/`** —— Godot 4.7 音游（读 `rchart` v3，玩法/渲染/判定照 `docs/` 实现）。
  **工程里不含谱面**，谱面自己做了往 `game/charts/` 放。
  入口文档：[game/README.md](game/README.md)
- **`docs/`** —— 游戏侧要对齐的东西：谱面格式、渲染与判定规范、GDScript 实现。
  入口文档：[docs/README.md](docs/README.md)
  - [谱面格式](docs/CHART_FORMAT.md) · [玩法/渲染规范](docs/GAME_INTEGRATION.md) · [Godot 指南](docs/GODOT_GUIDE.md)
- **`godot/`** —— 上一版 Godot 制谱器（EditorPlugin），保留没删，跟现在这套格式不同。
  入口文档：[godot/README.md](godot/README.md)

> 用 Godot 做游戏的话：照着 [docs/GODOT_GUIDE.md](docs/GODOT_GUIDE.md) 抄，
> 里面的 GDScript 都在 Godot 4.7.2 上跑过语法检查；现成的成品在 `game/`。

## Godot 音游（`game/`）

```powershell
& 'C:\Users\Dy\Desktop\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\Dy\Desktop\Rhythm\game' --editor
```

- 启动流程：**光敏性癫痫警告**（5 秒 / 任意键跳过）→ **主界面**（开始游戏 / 收藏品 / 设置 / 个人资料）→ **选曲界面**；
  谱面放 `game/charts/`（或选曲界面「谱面目录」打开的 `user://charts`），
  也支持把制谱器导出的 zip 直接拖进窗口自动导入
- 键位 `A S D F` / `J K L ;`，`Esc` 暂停、`R` 重试；判定 55/80/140/220 ms，
  分数 / 连击 / 血量 / 评级规则见 [game/README.md](game/README.md)
- **游玩界面是极简 HUD**：顶部白色歌曲进度条、左上 `Combo 100`、右上 8 位分数 + 准确率、
  左下曲名、右下等级；没有血条 / 判定弹字 / 倒计时
- **游玩画面按制谱器「预渲染窗口」的规则画**：同样的线宽 / 颜色 / 剔除规则，
  谱面里的 `x/y` 像素值和制谱器里一致；舞台是 **16:9（逻辑 350×196.875）**，直接铺满 16:9 窗口
- 打击音效（音量 + 开关 + 试听，暂停面板里也能调）和打击特效（判定环 / 屏震，关·标准·强三档）
- 轨道父子线（`parent`）：子线跟着父线一起平移/旋转/动画，父链最多 8 层、成环会被忽略
- 主界面：玩家名 + 开始游戏 / 收藏品 / 设置 / 个人资料，右侧看板娘立绘（`game/assets/banner_girl.png`）；收藏品是立绘 + 曲绘图鉴，个人资料能改名并显示游玩统计
- 工程里**不带示例谱面**（`game/charts/` 里只有放谱面的说明）
- 自测：`godot --headless --path game --script res://tests/run_core_tests.gd`（193 条）、
  `godot --headless --path game res://tests/smoke.tscn`（91 条）

## 网页版制谱器

双击 `web/index.html`（Chrome / Edge），或者：

```powershell
start 'C:\Users\Dy\Desktop\Rhythm\web\index.html'
```

- 左键点空白放 tap，拖 = 移动，右键 = 删除，右键空白上下拖 = 画 hold，双击 = 换类型
- 空格播放（先「载入音频」），滚轮翻页，`Ctrl`+滚轮缩放
- 右侧 **4:3 预渲染窗口**：按游戏的舞台语义实时画谱面，播放时跟着音频走
- 时间轴左半边编音符、**右半边编事件**：一条事件带 6 组头尾参数（X/Y/透明度/旋转/流速/长度）+ 缓动曲线
- **打击音**：`web/audio/hit.wav`，放音符和播放过线都会响，可勾掉
- 每条轨道可切 **无 / 左 / 右** 判定区（白 `ASDFJKL;` / 紫 `ASDF` / 黄 `JKL;`）
- 每条轨道 5 组舞台参数：**X / Y · 透明度 · 音符流速 · 轨道长度 · 旋转角度**
  （X/Y=0 是舞台正中、重合正常；透明度 0 = 完全隐藏但只藏轨道不藏音符；
  流速 10 = 1.00×、100 = 100×（平方曲线）；长度 10 = 标准全长、0 = 只剩判定线；旋转 ±3600°）
- `Ctrl+S` 导出 JSON，`Ctrl+O` 打开 JSON，`Ctrl+Z` 撤销
- 自测：`node web/test/core.test.js`（245 条）、`node web/test/ui.smoke.js`（284 条）

完整说明见 [web/README.md](web/README.md)。

## 新手教程（`tutorial/`）

不会写谱就先看这个：[tutorial/README.md](tutorial/README.md)。

- 练手曲 **DataErr0r**（Cosmograph · 180 BPM · 2:05），目标是一张 **4 轨 / 472 音符 / NORMAL 7**
- 四课各只加一样东西：**tap → hold → None/L/R 判定区 → 融合写完剩下的 28 秒**
- `tutorial/01_tap.json` → `02_hold.json` → `03_zone.json` → `04_full.json` 是同一张谱的四次快照，
  用编辑器 `Ctrl+O` 逐份打开，一眼看出每课加了什么（后一份 = 前一份 + 本章）
- 同名 `.zip` 是**能直接导入的整包**（`chart.json` + 音频 + 曲绘）：拖进 Godot 游戏窗口即出现在选曲界面，
  制谱器 `Ctrl+O` 也能把整包读回来
- 每课都有小节格子图、操作步骤、常见错，以及「你自己练」的那一小段

## 故事板制作器（`web/storyboard.html`）

给做好的谱面做**演出包装**，谱面**只读**（工程里只存文件名 + 指纹，导出整包时原样复制 `chart.json`）。

```powershell
start 'C:\Users\Dy\Desktop\Rhythm\web\storyboard.html'
# 没谱面想先看效果：storyboard.html?demo=1，或点左边「载入示例」
```

- **场景**：故事板 = 一串场景（**解锁场 → 谱面场 → 片尾场**）；解锁动画放在谱面**之前**的解锁场里，
  谱面场才开始画音符、才开始放音乐，每场有自己的图层和后处理
- **图层**：**视频**（导入自己的 mp4/webm 当解锁动画，导入后把图层时长对齐视频）、文字（9 种特效：发光 / 故障 / 打字机 / 逐字弹入 / 波浪 / 描边 / 渐变 / 抖动 / 普通）、
  **解锁动画**（7 种：磁带插入 / 扫描 / 进度 / 碎片汇聚 / 锁链破碎 / 快门 / 环印盖章）、
  图片、形状（方框 / 线 / 圆 / 环 / 网格）
- **Shader 后处理** 15 种（辉光 / RGB 分离（立刻）/ CRT / 水波 / 故障 / 热浪 / 像素化 / 色调分离 / 暗角 / 颗粒 / 四角拉伸 / …），
  时间重叠会叠加，状态栏实时显示权重
- **时间轴**：拖图层条改起止 / 平移，关键帧 5 条通道（X/Y/缩放/旋转/透明度），按 BPM 吸附
- **模板**一键铺「开场标题卡 / 解锁演出 / 结算卡」，占位符自动填曲名和难度
- 左栏「音频」可调**音量 + 静音**（存进工程 `stage.volume`，不动谱面自己的音量）
- 谱面卡片有「**曲绘作者**」一栏（谱面没有这个字段，存在故事板里，文字里可用 `{illust}` 引用）
- **谱面画面 1:1 照抄 Godot 游戏**（`web/js/chart_stage.js` = `game/src/game/stage_view.gd` 的移植）：
  逻辑舞台 350×196.875、judgeY=167、圆角音符、长条尾部渐隐、多押蓝光、过线即消失
- 导出：工程 `.rstory.json` / 整包 `.zip`（谱面 + 故事板 + 音频 + 曲绘）/ 截图 PNG / 录制 WebM
- 自测：`node web/test/sb.test.js`（366 条）、`node web/test/sb.smoke.js`（311 条）

完整说明见 [web/STORYBOARD.md](web/STORYBOARD.md)。

## Godot 版（上一版）

```powershell
# 打开工程
& 'C:\Users\Dy\Desktop\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\Dy\Desktop\Rhythm\godot' --editor
```

2. 编辑器顶部点 **「制谱器」** 标签 → 打开 → 选 `godot/charts/demo_neon_pulse.json`
3. 按 **F5** 看游戏侧参考渲染（`godot/examples/demo_stage.tscn`）
