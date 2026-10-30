@tool
class_name LockIcon
extends Control
## 极简纯白小挂锁：一段圆弧当锁梁 + 一块圆角矩形当锁体，纯色、无渐变无阴影。
## 尺寸跟着节点走（把 Control 拉多大就画多大），在编辑器里也能直接看到。

@export var color := Color(1, 1, 1, 0.96):
	set(value):
		color = value
		queue_redraw()
## 锁梁线宽占高度的比例
@export_range(0.02, 0.2, 0.005) var stroke_ratio := 0.075:
	set(value):
		stroke_ratio = value
		queue_redraw()
## 锁体高度占高度的比例
@export_range(0.3, 0.7, 0.01) var body_ratio := 0.46:
	set(value):
		body_ratio = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var line_width := maxf(1.5, h * stroke_ratio)
	var body_w := w * 0.78
	var body_h := h * body_ratio
	var body_x := (w - body_w) * 0.5
	var body_y := h - body_h
	# 锁梁：圆心压在锁体顶边上，只画上半圈，两个端点正好落在锁体顶面
	var shackle_center := Vector2(w * 0.5, body_y + line_width * 0.5)
	draw_arc(shackle_center, w * 0.26, PI, TAU, 40, color, line_width, true)
	# 锁体：圆角矩形
	var body := StyleBoxFlat.new()
	body.bg_color = color
	body.set_corner_radius_all(int(round(maxf(2.0, h * 0.1))))
	draw_style_box(body, Rect2(body_x, body_y, body_w, body_h))
