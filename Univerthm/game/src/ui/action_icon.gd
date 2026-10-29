class_name ActionIcon
extends Button
## 与项目切角视觉一致的无文字动作图标，矢量绘制以保持任意分辨率清晰。

enum Kind { RESUME, RETRY, BACK }
@export var kind := Kind.RESUME
var spring_scale := 1.0
var _scale_velocity := 0.0


func _ready() -> void:
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button_down.connect(func(): _scale_velocity = -4.8)
	button_up.connect(func(): _scale_velocity = 2.8)
	resized.connect(queue_redraw)
	accessibility_name = ["继续游玩", "重新开始", "返回选曲"][kind]


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var target := 0.91 if button_pressed else (1.065 if is_hovered() or has_focus() else 1.0)
	var remaining := minf(delta, 0.1)
	while remaining > 0.0:
		var dt := minf(remaining, 0.008)
		_scale_velocity += ((target - spring_scale) * 350.0 - _scale_velocity * 18.0) * dt
		spring_scale += _scale_velocity * dt
		remaining -= dt
	pivot_offset = size * 0.5
	scale = Vector2.ONE * spring_scale
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var active := is_hovered() or has_focus() or button_pressed
	var purple := Color("ae75ff")
	var green := Color("bcf49a")
	var accent := green if kind == Kind.RESUME else purple
	var border := accent if active else Color("86759f")
	var p := PackedVector2Array([Vector2(20, 2), Vector2(w - 2, 2), Vector2(w - 2, h - 22), Vector2(w - 22, h - 2), Vector2(2, h - 2), Vector2(2, 20), Vector2(20, 2)])
	draw_colored_polygon(p, Color(0.05, 0.03, 0.1, 0.96) if not active else Color(0.15, 0.07, 0.26, 0.98))
	if active:
		draw_polyline(p, Color(accent, 0.09), 12, true)
		draw_polyline(p, Color(accent, 0.18), 5, true)
	draw_polyline(p, border, 1.3, true)
	draw_line(Vector2(20, 2), Vector2(58, 2), accent, 3, true)
	draw_line(Vector2(w - 22, h - 2), Vector2(w - 56, h - 2), accent, 3, true)
	var c := size * 0.5
	var ink := Color("fbf8ff")
	match kind:
		Kind.RESUME:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-15, -24), c + Vector2(25, 0), c + Vector2(-15, 24)]), ink)
		Kind.RETRY:
			draw_arc(c, 24, -0.65, 4.6, 52, ink, 5, true)
			var tip := c + Vector2(24, 0).rotated(-0.65)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(1, -13), tip + Vector2(4, 8), tip + Vector2(-16, 2)]), ink)
		Kind.BACK:
			draw_polyline(PackedVector2Array([c + Vector2(-2, -21), c + Vector2(-24, 0), c + Vector2(-2, 21)]), ink, 5, true)
			draw_line(c + Vector2(-23, 0), c + Vector2(27, 0), ink, 5, true)
