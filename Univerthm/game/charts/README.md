# 谱面放这里

游戏只负责**读谱 + 玩**，不含任何示例谱面（谱面由你自己做）。

放法二选一：

- **zip**：网页版制谱器 `Ctrl+S` 导出的 `曲名.zip`（里面是 `chart.json` + 音频 + 曲绘）直接丢进这个目录
- **文件夹**：`charts/我的曲子/` 里放 `chart.json`，音频 / 曲绘放同一层，文件名对上
  `audio.file` 和 `meta.cover`

`chart.json` / `xxx.rchart` 也可以单独放着，音频去同目录或 `audio/` 里找。

游戏启动时扫 `res://charts/`（这个目录）和 `user://charts/`（选曲界面「谱面目录」打开的那个），
也支持把 zip 直接拖进窗口自动导入。

谱面格式与字段见 [`../../docs/CHART_FORMAT.md`](../../docs/CHART_FORMAT.md)。
