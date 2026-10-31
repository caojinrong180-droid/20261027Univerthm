extends Control
## 开屏画面：透明整屏 UI 叠在暗色背景上，点击或按键进入主界面。

## 刚出现时的保护时间：这之前不响应点击。
const SKIP_GUARD := 0.4
## F11 是全局全屏切换，当「进入游戏」的话玩家就没法全屏了
const IGNORED_KEYS := [KEY_F11]
## 滚轮不算点击
const IGNORED_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]

@export_range(0.1, 1.5, 0.05) var fade_in_duration := 0.5
@export_range(0.1, 1.5, 0.05) var fade_out_duration := 0.45
@export_range(0.0, 2.0, 0.05) var idle_motion_strength := 1.0

var _elapsed := 0.0
var _done := false
var _motion_time := 0.0

@onready var _artwork: TextureRect = $Artwork


func _ready() -> void:
	theme = UiTheme.theme()
	_artwork.resized.connect(_update_artwork_pivot)
	_update_artwork_pivot()
	modulate.a = 0.0
	var intro := create_tween()
	intro.tween_property(self, "modulate:a", 1.0, fade_in_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	_motion_time += delta
	_update_artwork_motion()


func _update_artwork_pivot() -> void:
	_artwork.pivot_offset = _artwork.size * Vector2(0.5, 0.5)


func _update_artwork_motion() -> void:
	# 与主界面 Banner 相同的呼吸、轻摆和浮动节奏。
	var t := _motion_time
	var strength := idle_motion_strength
	var breath := sin(t * 1.15)
	_artwork.scale = Vector2(1.0 + breath * 0.0025 * strength, 1.0 + breath * 0.004 * strength)
	_artwork.rotation = sin(t * 0.58) * deg_to_rad(0.14) * strength
	var idle_offset := Vector2(sin(t * 0.53) * 1.5, -sin(t * 1.05) * 3.5) * strength
	_artwork.position = (size - _artwork.size) * 0.5 + idle_offset


## 在 GUI 控件消费输入前接住事件，画面任何位置、任何键都算。
func _input(event: InputEvent) -> void:
	if _done or _elapsed < SKIP_GUARD:
		return
	var enter := false
	if event is InputEventKey:
		var key := event as InputEventKey
		enter = key.pressed and not key.echo and key.keycode not in IGNORED_KEYS
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		enter = button.pressed and button.button_index not in IGNORED_BUTTONS
	if enter:
		get_viewport().set_input_as_handled()
		_leave()


func _leave() -> void:
	if _done:
		return
	_done = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, fade_out_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_interval(0.04)
	fade.tween_callback(App.goto_menu)
