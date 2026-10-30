extends Control
class_name FirstEntryWarning
## 神秘曲（列表第 3 首）第一次踏入时的红色警告。
## 选曲页在 App.needs_first_entry() 时说一句：选「否」留在列表，选「是」才真的进谱面；
## 进了之后这一趟不许按 Esc 暂停 / 退出（见 gameplay.gd 的 _first_entry）。
##
## 只负责「问」和「答」，落盘的事交给 App.commit_entry()——通关结算时才算真的踏进去。

signal chosen(confirmed: bool)

const HEADLINE := "踏出这一步就不能反悔了，你确定吗？"
const BODY := "踏进去之后就没有退路了：这一趟不能暂停，按 Esc 也出不来，\n" \
	+ "解锁动画也不能跳过。中途把游戏关掉，一切都会回到现在这一步之前。"
const RED := Color("ff3b5c")
const RED_FILL := Color(0.09, 0.012, 0.022, 0.97)
const RED_SOFT := Color("c98a97")

var buttons: Array[Button] = []
var _card: NeonPanel
var _no_button: Button
var _yes_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(self)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.03, 0.005, 0.012, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(dim)
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(center)
	add_child(center)

	_card = NeonUi.panel(Vector4(38, 30, 38, 28))
	_card.name = "WarningCard"
	_card.slanted = true
	_card.cut = 26
	_card.fill = RED_FILL
	_card.edge = RED
	_card.glow = true
	center.add_child(_card)

	var box := UiKit.vbox(15)
	_card.add_child(box)

	var head := UiKit.hbox(10)
	box.add_child(head)
	head.add_child(NeonUi.label("///", 15, RED, true))
	head.add_child(NeonUi.label("警告", 15, RED, true))
	head.add_child(UiKit.stretch())
	head.add_child(NeonUi.label("POINT OF NO RETURN", 11, RED_SOFT))

	var headline := NeonUi.label(HEADLINE, 27, NeonUi.LIGHT, true)
	headline.name = "Headline"
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.custom_minimum_size = Vector2(560, 0)
	box.add_child(headline)

	var body := NeonUi.label(BODY, 13, NeonUi.MUTED)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	box.add_child(body)

	box.add_child(UiKit.rule(Color(RED, 0.38)))

	var actions := UiKit.hbox(14)
	box.add_child(actions)
	var hint := NeonUi.label("Esc = 否", 11, Color("9c7f88"))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(hint)
	actions.add_child(UiKit.stretch())

	_no_button = _make_button("否", false)
	_no_button.name = "NoButton"
	_no_button.pressed.connect(_choose.bind(false))
	actions.add_child(_no_button)
	buttons.append(_no_button)

	_yes_button = _make_button("是", true)
	_yes_button.name = "YesButton"
	_yes_button.pressed.connect(_choose.bind(true))
	actions.add_child(_yes_button)
	buttons.append(_yes_button)

	hide()


## 自己的按钮：共用霓虹按钮会自动刷回紫色，这块框要的是血红，所以在这儿现画。
func _make_button(text: String, danger: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(124, 44)
	button.add_theme_font_override("font", NeonUi.bold())
	button.add_theme_font_size_override("font_size", 17)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 24
		box.content_margin_right = 24
		box.content_margin_top = 7
		box.content_margin_bottom = 7
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, NeonUi.LIGHT)

	var frame := NeonPanel.new()
	frame.name = "ButtonFrame"
	frame.slanted = true
	frame.cut = 12
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.show_behind_parent = true
	UiKit.full_rect(frame)
	button.add_child(frame)
	button.set_meta("frame", frame)
	button.set_meta("danger", danger)
	for sig in [button.mouse_entered, button.mouse_exited, button.focus_entered, button.focus_exited]:
		sig.connect(_refresh_button.bind(button))
	_refresh_button(button)
	return button


func _refresh_button(button: Button) -> void:
	var frame = button.get_meta("frame", null) as NeonPanel
	if frame == null:
		return
	var danger := bool(button.get_meta("danger", false))
	var active := button.is_hovered() or button.has_focus() or button.button_pressed
	if danger:
		frame.fill = Color("a5132d") if active else Color("7d0d1e")
		frame.edge = Color("ff8a9d") if active else RED
		frame.glow = true
	else:
		frame.fill = Color(0.13, 0.05, 0.075, 0.98) if active else Color(0.06, 0.025, 0.035, 0.95)
		frame.edge = RED_SOFT if active else Color("7a4b57")
		frame.glow = false


## 弹出来：默认焦点在「否」，手滑也不会直接踏进去
func open() -> void:
	show()
	if _no_button != null:
		_no_button.grab_focus()


func close() -> void:
	hide()
	for button in buttons:
		button.release_focus()


func is_open() -> bool:
	return visible


func _choose(confirmed: bool) -> void:
	if not visible:
		return
	close()
	chosen.emit(confirmed)


## Esc 一律当「否」：这个框弹出的意义就是给人留一条不回头的路
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_choose(false)
