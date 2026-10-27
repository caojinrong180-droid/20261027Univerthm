extends Control
## 个人资料：玩家名（可改，存进 settings.cfg）+ 游玩统计（user://profile.cfg）。

var _name_label: Label
var _avatar: _Avatar
var _edit: LineEdit
var _stat_values := {}


func _ready() -> void:
	theme = UiTheme.theme()
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		App.goto_menu()
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		if not _edit.has_focus():
			get_viewport().set_input_as_handled()
			App.goto_menu()


# --------------------------------------------------------------------------- #
# 界面
# --------------------------------------------------------------------------- #

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	UiKit.full_rect(bg)
	add_child(bg)

	var column := UiKit.vbox(0)
	UiKit.full_rect(column)
	add_child(column)
	column.add_child(_build_topbar())

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)

	var card := UiKit.panel(Palette.PANEL, 14, 1, Palette.LINE, Vector4(34, 28, 34, 28))
	card.custom_minimum_size = Vector2(680, 0)
	center.add_child(card)

	var box := UiKit.vbox(16)
	card.add_child(box)

	# 头像 + 名字
	var head := UiKit.hbox(18)
	box.add_child(head)

	_avatar = _Avatar.new()
	_avatar.custom_minimum_size = Vector2(76, 76)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.player_name = _player_name()
	head.add_child(_avatar)

	var name_box := UiKit.vbox(2)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(name_box)

	_name_label = UiKit.label(_player_name(), 28, Palette.TEXT)
	name_box.add_child(_name_label)
	var caption := UiKit.mono_label("PLAYER   ·   RHYTHM", 11, Palette.DIM_2)
	name_box.add_child(caption)

	box.add_child(UiKit.rule())

	# 改名
	var edit_row := UiKit.hbox(10)
	box.add_child(edit_row)
	var edit_label := UiKit.label("名字", 14, Palette.DIM)
	edit_label.custom_minimum_size = Vector2(80, 0)
	edit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	edit_row.add_child(edit_label)

	_edit = LineEdit.new()
	_edit.text = _player_name()
	_edit.max_length = 16
	_edit.placeholder_text = "输入名字（最多 16 字）"
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, 38)
	_edit.add_theme_stylebox_override("normal",
		UiTheme.style_box(Palette.PANEL_2, 7, 1, Palette.LINE, Vector4(14, 6, 14, 6)))
	_edit.add_theme_stylebox_override("focus",
		UiTheme.style_box(Palette.PANEL_3, 7, 1, Palette.ACCENT, Vector4(14, 6, 14, 6)))
	_edit.add_theme_color_override("font_color", Palette.TEXT)
	_edit.add_theme_color_override("caret_color", Palette.ACCENT)
	_edit.text_submitted.connect(func(_t): _save_name())
	edit_row.add_child(_edit)

	var save := UiKit.button("保存", 14, "AccentButton")
	save.custom_minimum_size = Vector2(86, 38)
	save.pressed.connect(_save_name)
	edit_row.add_child(save)

	box.add_child(UiKit.rule())

	# 统计
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 14)
	stats_grid.add_theme_constant_override("v_separation", 14)
	box.add_child(stats_grid)

	var best_title := str(App.stats.get("best_title", ""))
	if best_title == "":
		best_title = "—"
	_add_stat(stats_grid, "游玩次数", str(int(App.stats.get("plays", 0))), Palette.TEXT)
	_add_stat(stats_grid, "谱面库", "%d 张" % App.library.size(), Palette.ACCENT)
	_add_stat(stats_grid, "最高分", "%d" % int(App.stats.get("best_score", 0)), Palette.OK)
	_add_stat(stats_grid, "最高分曲目", best_title, Palette.DIM)
	_add_stat(stats_grid, "最高分准确率", "%.2f%%" % (float(App.stats.get("best_acc", 0.0)) * 100.0), Palette.TEXT)
	_add_stat(stats_grid, "最近一局", _last_play_text(), Palette.DIM)

	box.add_child(UiKit.rule())
	var hint := UiKit.mono_label("名字存在 settings.cfg，统计存在 profile.cfg     ESC 返回", 11, Palette.DIM_2)
	box.add_child(hint)

	_edit.call_deferred("grab_focus")


func _build_topbar() -> Control:
	var bar := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(26, 12, 26, 12))
	var h := UiKit.hbox(12)
	bar.add_child(h)
	var back := UiKit.button("← 返回", 14, "GhostButton")
	back.pressed.connect(func(): App.goto_menu())
	h.add_child(back)
	var title := UiKit.label("个人资料", 20, Palette.TEXT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(title)
	h.add_child(UiKit.stretch())
	var hint := UiKit.mono_label("ESC 返回主界面", 12, Palette.DIM_2)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(hint)
	return bar


func _add_stat(grid: GridContainer, caption: String, value: String, color: Color) -> void:
	var cell := UiKit.flat_panel(Palette.PANEL_2, 8, Vector4(16, 10, 16, 10))
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(290, 0)
	var box := UiKit.vbox(2)
	cell.add_child(box)
	var cap := UiKit.label(caption, 12, Palette.DIM_2)
	box.add_child(cap)
	var val := UiKit.mono_label(value, 20, color)
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(val)
	grid.add_child(cell)


func _last_play_text() -> String:
	if App.last_result.is_empty():
		return "还没有游玩记录"
	return "%s   %d" % [str(App.last_result.get("title", "")), int(App.last_result.get("score", 0))]


func _player_name() -> String:
	if App.settings != null and str(App.settings.player_name).strip_edges() != "":
		return str(App.settings.player_name)
	return "User"


func _save_name() -> void:
	if App.settings == null:
		return
	var nm := _edit.text.strip_edges()
	if nm == "":
		nm = "User"
	_edit.text = nm
	App.settings.player_name = nm
	App.settings.save()
	_name_label.text = nm
	_avatar.player_name = nm
	_avatar.queue_redraw()


## 头像：圆 + 名字首字
class _Avatar:
	extends Control

	var player_name := "User"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Palette.alpha(Palette.ACCENT, 0.18))
		draw_arc(c, r - 1.0, 0.0, TAU, 40, Palette.alpha(Palette.ACCENT, 0.8), 2.0, true)
		var initial := player_name.substr(0, 1).to_upper()
		var font := UiTheme.mono()
		var fs := int(maxf(16.0, r * 1.0))
		var w := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + float(fs) * 0.36), initial,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT)
