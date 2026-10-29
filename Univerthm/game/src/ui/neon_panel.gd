@tool
class_name NeonPanel
extends PanelContainer
## 可在场景编辑器调整的切角面板，边框为实时矢量绘制。

@export var fill := Color(0.025, 0.02, 0.055, 0.91):
	set(value):
		fill = value
		queue_redraw()
@export var edge := Color("9470ce"):
	set(value):
		edge = value
		queue_redraw()
@export var cut := 18.0:
	set(value):
		cut = value
		queue_redraw()
@export var slanted := false:
	set(value):
		slanted = value
		queue_redraw()
@export var accents := true:
	set(value):
		accents = value
		queue_redraw()
@export var glow := false:
	set(value):
		glow = value
		queue_redraw()


func _ready() -> void:
	if not has_theme_stylebox_override("panel"):
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := minf(cut, minf(w, h) * 0.4)
	var points: PackedVector2Array
	if slanted:
		points = PackedVector2Array([Vector2(c, 1), Vector2(w - 1, 1), Vector2(w - c, h - 1), Vector2(1, h - 1), Vector2(c, 1)])
	else:
		points = PackedVector2Array([Vector2(c, 1), Vector2(w - c, 1), Vector2(w - 1, c), Vector2(w - 1, h - c), Vector2(w - c, h - 1), Vector2(c, h - 1), Vector2(1, h - c), Vector2(1, c), Vector2(c, 1)])
	draw_colored_polygon(points, fill)
	if glow:
		draw_polyline(points, Color(edge, 0.06), 9.0, true)
		draw_polyline(points, Color(edge, 0.14), 4.0, true)
	draw_polyline(points, edge, 1.0, true)
	if not accents:
		return
	var purple := Color("963bff")
	if slanted:
		draw_line(Vector2(c, 2), Vector2(c - 7, 19), purple, 4, true)
		draw_line(Vector2(w - c, h - 2), Vector2(w - c + 7, h - 19), Color("cc9cff"), 3, true)
	else:
		draw_polyline(PackedVector2Array([Vector2(1, minf(h - c, 65)), Vector2(1, c), Vector2(c, 1), Vector2(minf(w - c, 80), 1)]), purple, 3, true)
		draw_polyline(PackedVector2Array([Vector2(w - 1, h - minf(h - c, 62)), Vector2(w - 1, h - c), Vector2(w - c, h - 1), Vector2(w - minf(w - c, 80), h - 1)]), Color("c798ff"), 2, true)
