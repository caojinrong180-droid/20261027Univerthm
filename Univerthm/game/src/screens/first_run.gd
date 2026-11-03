extends Control
## 第一次进游戏的流程：**全黑** → 辅助校准弹窗 → 关掉 → 打新手教程谱面（White Noise）→ 主界面。
##
## 只在 `App.settings.tutorial_seen == false` 时由开屏画面进到这里；
## 教程谱面打完（或中途退出）时 `App.finish_tutorial()` 会把看过标记写进 settings.cfg，
## 之后再启动就直接进主界面。

const Calibration = preload("res://src/ui/calibration_overlay.gd")
## 打开校准弹窗之前先黑一下，别让玩家觉得画面卡住
const PRE_OPEN_DELAY := 0.45

var _calibration: Calibration
var _started := false


func _ready() -> void:
	# 全黑：这一屏什么都不画，只有校准弹窗浮在上面
	var black := ColorRect.new()
	black.name = "Black"
	black.color = Color(0, 0, 0, 1)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)

	_calibration = Calibration.new()
	_calibration.name = "Calibration"
	# 首次进游戏的强制校准：右上角没有「×」，左下角那颗是「跳过」（跳过直接进谱面）
	_calibration.first_run = true
	UiKit.full_rect(_calibration)
	add_child(_calibration)
	_calibration.closed.connect(_on_calibration_closed)
	_calibration.applied.connect(_on_calibration_applied)
	_open_soon()


func _open_soon() -> void:
	await get_tree().create_timer(PRE_OPEN_DELAY).timeout
	if not is_inside_tree() or _started:
		return
	_calibration.open()


## 校准里的「应用到偏移」：写进设置（和设置页里那颗按钮同一套规则）
func _on_calibration_applied(value_ms: float) -> void:
	if App.settings == null:
		return
	App.settings.audio_offset_ms = clampf(round(value_ms), -250.0, 250.0)
	App.settings.save()


## 校准关掉了 → 直接进新手教程谱面；包读不了就退回主界面，别把人卡在黑屏里
func _on_calibration_closed() -> void:
	if _started:
		return
	_started = true
	if App.play_tutorial():
		return
	push_warning(App.toast)
	App.finish_tutorial()
	App.goto_menu()
