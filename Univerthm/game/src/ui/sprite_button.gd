class_name SpriteButton
extends TextureRect
## 主界面那种「切图当按钮」的控件：悬停时轻轻上浮、不透明度变高，鼠标指针保持默认箭头。
## 在编辑器里把一张切图拖到 Texture 上，挂这个脚本就能用。

signal pressed

## 悬停上浮距离（像素）
@export var hover_lift := 6.0
## 常态 / 悬停时的不透明度
@export var alpha_idle := 0.82
@export var alpha_hover := 1.0
## 上浮 / 淡入时长（秒）
@export var tween_time := 0.12

var _hover := false
var _base_y := 0.0
var _base_ready := false


func _ready() -> void:
	if focus_mode == Control.FOCUS_NONE:
		focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = alpha_idle
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	focus_entered.connect(func(): _set_hover(true))
	focus_exited.connect(func(): _set_hover(false))


func _set_hover(v: bool) -> void:
	if _hover == v:
		return
	_hover = v
	if not _base_ready:
		_base_y = position.y
		_base_ready = true
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", _base_y - (hover_lift if v else 0.0), tween_time)
	tw.parallel().tween_property(self, "modulate:a", alpha_hover if v else alpha_idle, tween_time + 0.02)


func _gui_input(event: InputEvent) -> void:
	var fire := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		fire = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			fire = true
	if fire:
		accept_event()
		pressed.emit()
