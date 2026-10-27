extends Control
class_name StagePost
## 故事板后处理层（游戏侧）。
##
## 网页版是「一条 shader = 一层，逐层 ping-pong pass」；Godot 这里用同样的思路，
## 但走 2D 后缓冲：每层一个 ColorRect（素材 = story_grade.gdshader），
## 前面插一个 BackBufferCopy，于是第 N 层采到的 screen_tex 就是第 N-1 层的输出。
##
## 用法（gameplay 里）：
##   _post = StagePost.new()  （或者场景里先放一个）
##   _post.apply(StoryboardSource.active_shaders(chart_scene, chart_time), chart_time)
## 每帧调一次，层数按需增减。

const SBS = preload("res://src/core/storyboard_source.gd")
const SHADER_PATH := "res://shaders/story_grade.gdshader"
const MAX_LAYERS := 12

var _mats: Array = []        # ShaderMaterial
var _rects: Array = []       # ColorRect
var _copies: Array = []      # BackBufferCopy
var _shader: Shader = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shader = load(SHADER_PATH)
	if _shader == null:
		push_warning("后处理 shader 没加载到：" + SHADER_PATH)


## stack = [{ preset, value, weights }]；一层一个 pass
func apply(stack: Array, time: float) -> void:
	if _shader == null:
		return
	var n: int = min(stack.size(), MAX_LAYERS)
	_ensure(n)
	for i in _mats.size():
		var mat: ShaderMaterial = _mats[i]
		var rect: ColorRect = _rects[i]
		var copy: BackBufferCopy = _copies[i]
		if i >= n:
			rect.visible = false
			copy.visible = false
			continue
		rect.visible = true
		copy.visible = true
		var entry: Dictionary = stack[i]
		var weights: Dictionary = entry.get("weights", {})
		mat.set_shader_parameter("u_time", time)
		mat.set_shader_parameter("u_res", _res_vec())
		for key in SBS.WEIGHT_KEYS:
			mat.set_shader_parameter("u_" + key, float(weights.get(key, 0.0)))


## 层数变成 n（多退少补）。每层：BackBufferCopy → ColorRect
func _ensure(n: int) -> void:
	while _mats.size() < n:
		# BackBufferCopy 是 Node2D，没有 anchors / mouse_filter；COPY_MODE_VIEWPORT 会拷整屏
		var copy := BackBufferCopy.new()
		copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(copy)

		var rect := ColorRect.new()
		rect.color = Color(1, 1, 1, 1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		rect.material = mat
		add_child(rect)

		_copies.append(copy)
		_rects.append(rect)
		_mats.append(mat)


func _res_vec() -> Vector2:
	var vp := get_viewport()
	if vp != null:
		var sz := vp.get_visible_rect().size
		if sz.x > 1.0 and sz.y > 1.0:
			return sz
	return Vector2(1280, 720)


func clear() -> void:
	apply([], 0.0)
