extends Control
## 通用确认弹窗：暗底 + 切角面板 + 标题 / 说明 / 两个按钮。
## 用法：`new()` → `UiKit.full_rect()` → 挂到界面 → `open(标题, 说明, 确认文字, 取消文字)`。
## 确认发 confirmed，取消 / Esc 发 cancelled，两个信号之后都会自己关掉。

signal confirmed
signal cancelled

const Neon = preload("res://src/ui/neon_ui.gd")

var title_label: Label
var body_label: Label
var confirm_button: Button
var cancel_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.012, 0.006, 0.027, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(shade)
	add_child(shade)

	var center := CenterContainer.new()
	center.name = "Center"
	UiKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := Neon.panel(Vector4(34, 24, 34, 22))
	panel.name = "DialogPanel"
	panel.fill = Color(0.025, 0.017, 0.064, 0.97)
	panel.edge = Color("c49bff")
	panel.glow = true
	panel.cut = 18
	center.add_child(panel)

	var column := UiKit.vbox(14)
	column.custom_minimum_size.x = 460
	panel.add_child(column)
	title_label = Neon.label("", 21, Color("f0e5ff"), true)
	title_label.name = "DialogTitle"
	column.add_child(title_label)
	body_label = Neon.label("", 14, Neon.MUTED)
	body_label.name = "DialogBody"
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body_label)
	column.add_child(UiKit.rule(Color("624480")))
	var actions := UiKit.hbox(16)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)
	confirm_button = Neon.button("确认", true, 16)
	confirm_button.name = "ConfirmButton"
	confirm_button.custom_minimum_size = Vector2(150, 44)
	confirm_button.pressed.connect(_on_confirm)
	actions.add_child(confirm_button)
	cancel_button = Neon.button("取消", false, 16)
	cancel_button.name = "CancelButton"
	cancel_button.custom_minimum_size = Vector2(150, 44)
	cancel_button.pressed.connect(_on_cancel)
	actions.add_child(cancel_button)


## text 为空时沿用上一次的文案
func open(title: String, body: String, confirm_text := "确认", cancel_text := "取消") -> void:
	if title != "":
		title_label.text = title
	if body != "":
		body_label.text = body
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	show()
	# 默认焦点放在取消上，误按 Enter 不会直接删档
	cancel_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()


func _on_confirm() -> void:
	close()
	confirmed.emit()


func _on_cancel() -> void:
	close()
	cancelled.emit()


## Esc 关掉；弹窗开着时把按键吃掉，别让下面的界面跟着响应
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_cancel()
