@tool
extends Control
## 缓动曲线预览：把 apply_ease 从 0 到 1 的形状画出来（像 PhiEdit 右下角那张小图）。
## 只是可视化，不参与逻辑。

const C_BG := Color("#0a0e14")
const C_GRID := Color("#1a2330")
const C_LINE := Color("#ffd166")
const C_REF := Color("#39465c")

var ease_name: String = "linear"

var debug_draws: int = 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_ease(name: String) -> void:
	if ease_name == name:
		return
	ease_name = name
	queue_redraw()


func _draw() -> void:
	debug_draws += 1
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, C_BG)
	var pad := 5.0
	var w := maxf(size.x - pad * 2.0, 1.0)
	var h := maxf(size.y - pad * 2.0, 1.0)
	# 网格
	for i in 3:
		var y := pad + h * float(i) / 2.0
		draw_line(Vector2(pad, y), Vector2(pad + w, y), C_GRID, 1.0)
	# 线性参考线
	draw_line(Vector2(pad, pad + h), Vector2(pad + w, pad), C_REF, 1.0)
	# 缓动曲线
	var pts := PackedVector2Array()
	var samples := int(clampf(w, 24.0, 96.0))
	for i in samples + 1:
		var t := float(i) / float(samples)
		var v := RhythmChartLane.apply_ease(ease_name, t)
		pts.append(Vector2(pad + w * t, pad + h * (1.0 - clampf(v, -0.2, 1.2))))
	if pts.size() >= 2:
		draw_polyline(pts, C_LINE, 1.6)
