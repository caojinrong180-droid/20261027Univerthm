@tool
class_name ChapterSpine
extends Button
## 章节选择里的一本「书脊」：斜着的平行四边形——上下沿水平，左右两侧往右斜 `skew` 像素。
## 文字也是一路往右下斜着排的（底下一个字贴着右下角，往上每个字跟着斜边挪），跟形状一个倾角。
## 点击判定按平行四边形算，四个角的空白点不到。

const BOLD_FONT := preload("res://src/ui/fonts/bold_font.tres")

@export var skew := 52.0:
	set(value):
		skew = value
		queue_redraw()
@export var fill := Color(0.031, 0.02, 0.062, 0.55):
	set(value):
		fill = value
		queue_redraw()
@export var edge := Color(0.85, 0.75, 1, 0.3):
	set(value):
		edge = value
		queue_redraw()
@export var edge_width := 1.0:
	set(value):
		edge_width = value
		queue_redraw()
@export var focus_edge := Color(0.5, 0.36, 0.78, 0.6):
	set(value):
		focus_edge = value
		queue_redraw()
## 竖排文字（一个字一行），贴着书脊右下角往上排
@export var spine_text := "":
	set(value):
		spine_text = value
		queue_redraw()
@export var text_color := Color(0.87451, 0.894118, 0.933333):
	set(value):
		text_color = value
		queue_redraw()
@export var text_size := 19:
	set(value):
		text_size = value
		queue_redraw()
@export var text_pad := 20.0:
	set(value):
		text_pad = value
		queue_redraw()
## 章节封面（可选）：一张图等比放大铺满整条书脊，超出的部分两边裁掉。
## 用 draw_polygon 自带的 UV 直接把图裁成平行四边形，所以四个角不会漏出图来。
## 没挂封面的书脊还是原来那块纯色。
@export var cover: Texture2D:
	set(value):
		cover = value
		queue_redraw()
## 封面底部压多黑（竖排字压在暗部上才看得清；0 = 不压）
@export_range(0.0, 1.0) var cover_veil := 0.62:
	set(value):
		cover_veil = value
		_shade = null
		queue_redraw()

var _shade: GradientTexture2D


func _ready() -> void:
	# 底和图全交给自己画，Button 自带的样式框会让它变回矩形
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## 平行四边形四个角（顺时针：左下 → 右下 → 右上 → 左上）
func shape_points() -> PackedVector2Array:
	var body := maxf(8.0, size.x - skew)
	return PackedVector2Array([
		Vector2(0.0, size.y),
		Vector2(body, size.y),
		Vector2(body + skew, 0.0),
		Vector2(skew, 0.0),
	])


func _draw() -> void:
	var points := shape_points()
	if cover != null:
		_draw_cover(points)
	# 有封面的书脊把状态色压薄一点，别把图糊死；没封面照旧
	var body_fill := fill
	if cover != null:
		body_fill.a = minf(0.6, fill.a * 0.45)
	draw_colored_polygon(points, body_fill)
	var loop := points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, edge, edge_width, true)
	if has_focus():
		var outline := PackedVector2Array()
		var center := size * 0.5
		for point in points:
			outline.append(point + (center - point).normalized() * 2.5)
		outline.append(outline[0])
		draw_polyline(outline, focus_edge, edge_width, true)
	_draw_slanted_text()


## 封面：等比放大到铺满整条书脊（多出来的两边裁掉），再盖一层上亮下暗的渐变，
## 让底下的竖排字有地方落脚。
func _draw_cover(points: PackedVector2Array) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var tex_size := cover.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var span := Vector2.ONE
	var offset := Vector2.ZERO
	var target := size.x / size.y
	var source := tex_size.x / tex_size.y
	if source > target:
		span.x = target / source
		offset.x = (1.0 - span.x) * 0.5
	else:
		span.y = source / target
		offset.y = (1.0 - span.y) * 0.5
	var uv_scale := Vector2(span.x / size.x, span.y / size.y)
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var shade_uvs := PackedVector2Array()
	for point in points:
		colors.append(Color(1, 1, 1, 1))
		uvs.append(offset + point * uv_scale)
		shade_uvs.append(Vector2(0.5, point.y / size.y))
	draw_polygon(points, colors, uvs, cover)
	if cover_veil > 0.0:
		draw_polygon(points, colors, shade_uvs, _shade_texture())


func _shade_texture() -> GradientTexture2D:
	if _shade != null:
		return _shade
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.16),
		Color(0, 0, 0, cover_veil),
	])
	_shade = GradientTexture2D.new()
	_shade.gradient = gradient
	_shade.width = 4
	_shade.height = 256
	_shade.fill_from = Vector2(0.0, 0.0)
	_shade.fill_to = Vector2(0.0, 1.0)
	return _shade



## 竖排文字：最后一个字贴着右下角，整块字跟着斜边同一个倾角一起斜过去
func _draw_slanted_text() -> void:
	if spine_text == "" or size.y <= 0.0:
		return
	var body := maxf(8.0, size.x - skew)
	var font := BOLD_FONT
	var line := font.get_height(text_size) * 1.02
	var count := spine_text.length()
	var bottom := size.y - text_pad
	var anchor := Vector2(body - text_pad, bottom)
	# 绕右下角那个字旋转，角度 = 斜边的倾角（上沿往右歪 → 整块字也往右歪，贴着右边那条斜边）
	var angle := atan(skew / size.y)
	var spin := Transform2D(angle, Vector2.ZERO)
	spin.origin = anchor - spin.basis_xform(anchor)
	draw_set_transform_matrix(spin)
	for i in count:
		var glyph := spine_text.substr(i, 1)
		var glyph_width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		var baseline := Vector2(anchor.x - glyph_width, bottom - float(count - 1 - i) * line)
		# 封面是图的，字下面垫一层暗影，不然浅色的字会跟亮处糊在一起
		if cover != null:
			draw_string(font, baseline + Vector2(1.6, 1.6), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color(0, 0, 0, 0.6))
		draw_string(font, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, text_color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _has_point(point: Vector2) -> bool:
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	return Geometry2D.is_point_in_polygon(point, shape_points())
