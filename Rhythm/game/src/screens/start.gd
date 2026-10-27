extends Control
## 开始界面：标题 + 「开始」按钮，点开始才进入选曲主界面。

func _ready() -> void:
	theme = UiTheme.theme()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()
			_start()
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			App.quit_game()


func _start() -> void:
	App.goto_select()


# --------------------------------------------------------------------------- #
# 界面
# --------------------------------------------------------------------------- #

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG_DEEP
	UiKit.full_rect(bg)
	add_child(bg)

	# 背后四条很淡的轨道，暗示这是个按键音游
	var lanes := _LaneBackdrop.new()
	UiKit.full_rect(lanes)
	lanes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lanes)

	var center := CenterContainer.new()
	UiKit.full_rect(center)
	add_child(center)

	var column := UiKit.vbox(0)
	column.custom_minimum_size = Vector2(560, 0)
	center.add_child(column)

	var tag := UiKit.mono_label("rchart v3  ·  KEYBOARD RHYTHM", 12, Palette.DIM_2)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tag)
	column.add_child(UiKit.gap(6))

	var title := UiKit.label("RHYTHM", 72, Palette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(UiKit.gap(8))

	var rule := ColorRect.new()
	rule.color = Palette.alpha(Palette.ACCENT, 0.85)
	rule.custom_minimum_size = Vector2(560, 2)
	column.add_child(rule)

	column.add_child(UiKit.gap(16))

	var subtitle := UiKit.label("键位 D F J K  ·  支持长按与划键", 15, Palette.DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	column.add_child(UiKit.gap(44))

	var start_button := UiKit.button("开始", 22, "AccentButton")
	start_button.custom_minimum_size = Vector2(240, 56)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(_start)
	column.add_child(start_button)

	column.add_child(UiKit.gap(14))

	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)

	var settings_button := UiKit.button("设置", 14, "GhostButton")
	settings_button.pressed.connect(func(): App.goto_settings())
	row.add_child(settings_button)

	var quit_button := UiKit.button("退出", 14, "GhostButton")
	quit_button.pressed.connect(func(): App.quit_game())
	row.add_child(quit_button)

	column.add_child(UiKit.gap(40))

	var hint := UiKit.mono_label("ENTER 开始      ESC 退出", 12, Palette.DIM_2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	start_button.grab_focus()


## 背景：四条淡淡的竖直轨道
class _LaneBackdrop extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var lane := w * 0.052
		var gap := lane * 0.6
		var total := lane * 4.0 + gap * 3.0
		var x0 := w * 0.5 - total * 0.5
		for i in 4:
			var x := x0 + float(i) * (lane + gap)
			draw_rect(Rect2(x, h * 0.16, lane, h * 0.68), Color(1, 1, 1, 0.010))
			draw_line(Vector2(x, h * 0.16), Vector2(x, h * 0.84), Color(1, 1, 1, 0.022), 1.0)
			draw_line(Vector2(x + lane, h * 0.16), Vector2(x + lane, h * 0.84),
				Color(1, 1, 1, 0.022), 1.0)
