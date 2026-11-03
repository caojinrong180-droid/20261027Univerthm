class_name StoryLayers
extends Control
## 谱面场里的故事板**图层**（目前画文字层）。
##
## 谱面包里的 `storyboard.json` 属于「谱面场」的那些 layer 由这里实时画出来：
## 时间就是谱面时间（chart_time），位置 / 缩放 / 旋转 / 透明度 / 入场出场都用
## `StoryboardSource.active_layers()` 算好的 state。
##
## 坐标：故事板舞台是 1280×720（16:9），`x / y` 是 0~1 的舞台比例，这里直接乘到窗口上；
## 字号按窗口高度等比放大（1920×1080 时 ×1.5），所以和制谱器预览里看到的一样大。
##
## 还没画的图层类型：图片 / 视频 / 形状（包里目前没有；解析层已经留着字段）。
## 后处理 shader 会盖在这一层上面——和制谱器里「先画图层，再叠 shader」的顺序一致。

## 故事板舞台的基准高度：字号 / 描边都按它等比放大
const STAGE_HEIGHT := 720.0

var scene: Dictionary = {}

var _labels: Dictionary = {}
var _live := 0


func setup(chart_scene: Dictionary) -> void:
	scene = chart_scene
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(self)
	set_process(false)


## 每帧调用：把这一时刻还在生效的图层更新一遍
func set_time(local_time: float) -> void:
	if scene.is_empty():
		return
	var seen := {}
	for entry in StoryboardSource.active_layers(scene, local_time):
		var layer: Dictionary = entry.get("layer", {})
		if str(layer.get("type", "text")) != "text":
			continue
		var id := int(layer.get("id", 0))
		seen[id] = true
		_apply(_label_for(id), layer, entry.get("state", {}))
	for id in _labels.keys():
		if seen.has(id):
			continue
		var node = _labels[id]
		_labels.erase(id)
		if is_instance_valid(node):
			node.queue_free()
	_live = seen.size()


## 当前露出来的文字（调试 / 测试用）
func visible_texts() -> Array:
	var out: Array = []
	for id in _labels:
		var label = _labels[id]
		if is_instance_valid(label) and label.visible and label.modulate.a > 0.01:
			out.append(str(label.text))
	return out


func _label_for(id: int) -> Label:
	var label = _labels.get(id)
	if label != null and is_instance_valid(label):
		return label
	label = Label.new()
	label.name = "TextLayer%d" % id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", 0)
	add_child(label)
	_labels[id] = label
	return label


func _apply(label: Label, layer: Dictionary, state: Dictionary) -> void:
	var style: Dictionary = layer.get("style", {}) if typeof(layer.get("style", {})) == TYPE_DICTIONARY else {}
	var text := str(layer.get("text", ""))
	if label.text != text:
		label.text = text
	var font_size := maxi(8, int(round(float(style.get("size", 32.0)) * _ui_scale())))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_override("font",
		NeonUi.bold() if float(style.get("weight", 400.0)) >= 600.0 else UiTheme.sans())
	label.add_theme_color_override("font_color", _color(style.get("color"), Color.WHITE))

	# 发光 / 描边都用 outline 近似（Godot 的 Label 没有真正的辉光）
	var glow := clampf(float(style.get("glow", 0.0)), 0.0, 1.0)
	var stroke_w := maxf(0.0, float(style.get("strokeW", 0.0)))
	var outline := int(round((stroke_w + glow * font_size * 0.14) * _ui_scale() * 0.5))
	label.add_theme_constant_override("outline_size", maxi(0, outline))
	var outline_color := _color(style.get("stroke"), Color(0, 0, 0, 0))
	if glow > 0.01:
		outline_color = Color(_color(style.get("c1"), Color("4cc9f0")), glow * 0.55)
	label.add_theme_color_override("font_outline_color", outline_color)

	var line_h := maxf(0.6, float(style.get("lineH", 1.0)))
	label.add_theme_constant_override("line_spacing", int(round((line_h - 1.0) * font_size)))
	match str(style.get("align", "center")):
		"left":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		"right":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var alpha := clampf(float(state.get("alpha", 1.0)), 0.0, 1.0)
	label.modulate = Color(1, 1, 1, alpha)
	label.visible = alpha > 0.001
	_layout(label, layer, state)


## 位置：x / y 是舞台比例，字块以这个点为中心
func _layout(label: Label, layer: Dictionary, state: Dictionary) -> void:
	var box := label.get_combined_minimum_size()
	label.size = box
	var center := Vector2(float(layer.get("x", 0.5)) * size.x, float(layer.get("y", 0.5)) * size.y)
	center += Vector2(float(state.get("dx", 0.0)), float(state.get("dy", 0.0))) * _ui_scale()
	var pos := center - box * 0.5
	# 别把字整个推出画面（居中定位遇到很长的行时才会触发）
	pos.x = clampf(pos.x, 6.0, maxf(6.0, size.x - box.x - 6.0))
	pos.y = clampf(pos.y, 6.0, maxf(6.0, size.y - box.y - 6.0))
	label.position = pos
	label.pivot_offset = box * 0.5
	var scale_factor := float(state.get("scale", 1.0))
	label.scale = Vector2(scale_factor, scale_factor)
	label.rotation = deg_to_rad(float(state.get("rot", 0.0)))


func _ui_scale() -> float:
	return maxf(0.25, size.y / STAGE_HEIGHT)


static func _color(raw, fallback: Color) -> Color:
	if raw == null:
		return fallback
	if raw is Color:
		return raw
	var text := str(raw).strip_edges()
	if text == "":
		return fallback
	if text.begins_with("#"):
		text = text.substr(1)
	if text.length() == 6 or text.length() == 8:
		return Color.html(text)
	return fallback
