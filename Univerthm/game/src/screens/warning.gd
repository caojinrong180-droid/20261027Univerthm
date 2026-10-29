extends Control
## 启动画面：光敏性癫痫警告。界面节点在 scenes/warning.tscn 里（可以直接在编辑器里改字）。
## 停留 HOLD_SEC 秒后自动进主界面；中途按任意键 / 点一下可以跳过。

## 自动继续时间（秒）
const HOLD_SEC := 5.0
## 刚出现时的保护时间：这之前不响应跳过，避免误触
const SKIP_GUARD := 0.6

@export_range(0.1, 1.5, 0.05) var fade_out_duration := 0.45

var _elapsed := 0.0
var _done := false

@onready var _bar: ColorRect = $Center/Column/BarHolder/Bar
@onready var _bar_holder: Control = $Center/Column/BarHolder
@onready var _background: ColorRect = $Background
@onready var _column: VBoxContainer = $Center/Column


func _ready() -> void:
	theme = UiTheme.theme()
	_background.resized.connect(_update_backdrop)
	_column.item_rect_changed.connect(_update_backdrop)
	_update_backdrop.call_deferred()


## 波动跟随文字块中间偏左的位置，窗口缩放时仍保持对齐。
func _update_backdrop() -> void:
	if not is_instance_valid(_background) or not is_instance_valid(_column):
		return
	if _background.size.x <= 0.0 or _background.size.y <= 0.0:
		return
	var backdrop_material := _background.material as ShaderMaterial
	if backdrop_material == null:
		return
	var anchor := _column.get_global_transform() * (_column.size * Vector2(0.36, 0.52))
	anchor = _background.get_global_transform().affine_inverse() * anchor
	backdrop_material.set_shader_parameter("viewport_size", _background.size)
	backdrop_material.set_shader_parameter("wave_center", anchor / _background.size)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var k := clampf(_elapsed / HOLD_SEC, 0.0, 1.0)
	if _bar != null and _bar_holder != null:
		_bar.size = Vector2(_bar_holder.size.x * k, _bar_holder.size.y)
	if _elapsed >= HOLD_SEC:
		_leave()


## 在 GUI 控件消费点击前接收输入，让文字和空白区域都能跳过。
func _input(event: InputEvent) -> void:
	if _done or _elapsed < SKIP_GUARD:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		skip = true
	elif event is InputEventMouseButton and event.pressed:
		skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_leave()


func _leave() -> void:
	if _done:
		return
	_done = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_interval(0.04)
	fade.tween_callback(App.goto_menu)
