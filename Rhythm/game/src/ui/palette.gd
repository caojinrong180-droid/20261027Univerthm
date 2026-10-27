class_name Palette
extends RefCounted
## 全部颜色都在这。想换皮先改这里（数值取自网页版制谱器 web/css/editor.css）。

const BG := Color("#0b0d12")
const BG_DEEP := Color("#080a0e")
const PANEL := Color("#14171f")
const PANEL_2 := Color("#10131a")
const PANEL_3 := Color("#1b2029")
const LINE := Color("#232936")
const LINE_SOFT := Color("#191d26")
const TEXT := Color("#dfe4ee")
const DIM := Color("#8a93a6")
const DIM_2 := Color("#5d6678")

const ACCENT := Color("#4cc9f0")
const ACCENT_DIM := Color("#2a7d99")
const HOT := Color("#f72585")
const OK := Color("#7cf5c1")
const WARN := Color("#ffd166")
const PURPLE := Color("#b06bff")

const JUDGE_COLORS := {
	"perfect_plus": Color("#e6ccff"),   # Perfect+ 浅紫（比 Perfect 更亮）
	"perfect": Color("#b06bff"),        # 紫
	"good": Color("#4c9aff"),           # 蓝
	"bad": Color("#ffd166"),            # 黄
	"miss": Color("#f72585"),           # 粉
}

const DIFFICULTY_COLORS := {
	"EASY": Color("#7cf5c1"),
	"NORMAL": Color("#4cc9f0"),
	"HARD": Color("#ffd166"),
	"EXPERT": Color("#b06bff"),
	"MASTER": Color("#f72585"),
}


static func difficulty_color(difficulty: String) -> Color:
	return DIFFICULTY_COLORS.get(difficulty.to_upper(), DIM)


static func judge_color(result: String) -> Color:
	return JUDGE_COLORS.get(result, TEXT)


## 在背景上压一层半透明黑，用来做卡片底
static func alpha(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, a)


static func mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))
