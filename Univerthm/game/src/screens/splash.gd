extends Control
## 开屏画面：标题 logo + 一行「点击任意按键进入游戏」。
## 界面节点在 scenes/splash.tscn 里（可以直接在编辑器里换图 / 改字）。
## 流程位置：启动 → 警告 → 这里 → 主界面。
##
## 和警告页不同，这里**不会自动继续**：标题页就是停着等玩家按一下，
## 鼠标点画面任意处、或者按键盘任意键，都进主界面。

## 刚出现时的保护时间：这之前不响应点击。
## 跳过警告页的那一下（双击 / 连按）不该顺手把开屏也带过去。
const SKIP_GUARD := 0.4
## 提示文字多久之后淡入
const HINT_DELAY := 0.75
## 提示文字一次呼吸的时长（秒）与最暗时的透明度
const HINT_BREATH := 1.9
const HINT_MIN_ALPHA := 0.6

## F11 是全局全屏切换，当「进入游戏」的话玩家就没法全屏了
const IGNORED_KEYS := [KEY_F11]
## 滚轮不算点击
const IGNORED_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
	MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]

@export_range(0.1, 1.5, 0.05) var fade_in_duration := 0.5
@export_range(0.1, 1.5, 0.05) var fade_out_duration := 0.45

var _elapsed := 0.0
var _done := false
## 提示文字的淡入进度（0 → 1），呼吸效果再乘上去
var _hint_reveal := 0.0
var _hint_time := 0.0

@onready var _hint: Label = $Center/Column/Hint


func _ready() -> void:
	theme = UiTheme.theme()
	modulate.a = 0.0
	_hint.self_modulate.a = 0.0
	var intro := create_tween()
	intro.tween_property(self, "modulate:a", 1.0, fade_in_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	intro.tween_interval(HINT_DELAY)
	intro.tween_property(self, "_hint_reveal", 1.0, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 提示文字一直轻轻呼吸，提示这里在等人按。
func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	_hint_time += delta
	var breath := HINT_MIN_ALPHA + (1.0 - HINT_MIN_ALPHA) \
		* (0.5 + 0.5 * sin(_hint_time * TAU / HINT_BREATH))
	_hint.self_modulate.a = _hint_reveal * breath


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
