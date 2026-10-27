extends Control
## 个人资料：玩家名（可改，存进 settings.cfg）+ 游玩统计（user://profile.cfg）。
## 界面节点在 scenes/profile.tscn 里，脚本只负责填数据 / 连线。

var _name_label: Label
var _avatar: AvatarCircle
var _edit: LineEdit
var _stat_grid: GridContainer


func _ready() -> void:
	theme = UiTheme.theme()
	if get_child_count() == 0:
		_build()
	_resolve()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		App.goto_menu()
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		if _edit != null and not _edit.has_focus():
			get_viewport().set_input_as_handled()
			App.goto_menu()


# --------------------------------------------------------------------------- #
# 连节点 / 填数据
# --------------------------------------------------------------------------- #

func _resolve() -> void:
	_avatar = _find("Avatar")
	_name_label = _find("NameLabel")
	_edit = _find("NameEdit")
	_stat_grid = _find("StatsGrid")
	_name_label.text = _player_name()
	_avatar.player_name = _player_name()
	_edit.text = _player_name()
	if not _edit.text_submitted.is_connected(_on_name_submitted):
		_edit.text_submitted.connect(_on_name_submitted)
	var back: Button = _find("BackButton")
	if back != null:
		back.pressed.connect(func(): App.goto_menu())
	var save: Button = _find("SaveButton")
	if save != null:
		save.pressed.connect(_save_name)
	_edit.call_deferred("grab_focus")


func _refresh() -> void:
	var best_title := str(App.stats.get("best_title", ""))
	if best_title == "":
		best_title = "—"
	_set_stat("ValuePlays", str(int(App.stats.get("plays", 0))))
	_set_stat("ValueLibrary", "%d 张" % App.library.size())
	_set_stat("ValueBestScore", "%d" % int(App.stats.get("best_score", 0)))
	_set_stat("ValueBestTitle", best_title)
	_set_stat("ValueBestAcc", "%.2f%%" % (float(App.stats.get("best_acc", 0.0)) * 100.0))
	_set_stat("ValueLast", _last_play_text())


## 先找唯一名（%Name），再退回 find_child，这样代码搭的和 .tscn 都能用
func _find(node_name: String) -> Node:
	var n := get_node_or_null("%" + node_name)
	if n != null:
		return n
	return find_child(node_name, true, false)


func _set_stat(node_name: String, text: String) -> void:
	var label := _find(node_name) as Label
	if label != null:
		label.text = text


func _on_name_submitted(_text: String) -> void:
	_save_name()


func _last_play_text() -> String:
	if App.last_result.is_empty():
		return "还没有游玩记录"
	return "%s   %d" % [str(App.last_result.get("title", "")), int(App.last_result.get("score", 0))]


func _player_name() -> String:
	if App.settings != null and str(App.settings.player_name).strip_edges() != "":
		return str(App.settings.player_name)
	return "User"


func _save_name() -> void:
	if App.settings == null or _edit == null:
		return
	var nm := _edit.text.strip_edges()
	if nm == "":
		nm = "User"
	_edit.text = nm
	App.settings.player_name = nm
	App.settings.save()
	_name_label.text = nm
	_avatar.player_name = nm


# --------------------------------------------------------------------------- #
# 代码搭界面（只在场景是空的时候用；正常游戏走 .tscn）
# --------------------------------------------------------------------------- #

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	UiKit.full_rect(bg)
	add_child(bg)

	var column := UiKit.vbox(0)
	UiKit.full_rect(column)
	add_child(column)

	# 顶栏
	var bar := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(26, 12, 26, 12))
	bar.name = "TopBar"
	column.add_child(bar)
	var h := UiKit.hbox(12)
	bar.add_child(h)
	var back := UiKit.button("← 返回", 14, "GhostButton")
	back.name = "BackButton"
	h.add_child(back)
	var title := UiKit.label("个人资料", 20, Palette.TEXT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(title)
	h.add_child(UiKit.stretch())
	var hint := UiKit.mono_label("ESC 返回主界面", 12, Palette.DIM_2)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(hint)

	# 卡片
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)

	var card := UiKit.panel(Palette.PANEL, 14, 1, Palette.LINE, Vector4(34, 28, 34, 28))
	card.name = "Card"
	card.custom_minimum_size = Vector2(680, 0)
	center.add_child(card)

	var box := UiKit.vbox(16)
	card.add_child(box)

	var head := UiKit.hbox(18)
	box.add_child(head)

	var avatar := AvatarCircle.new()
	avatar.name = "Avatar"
	avatar.custom_minimum_size = Vector2(76, 76)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(avatar)

	var name_box := UiKit.vbox(2)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(name_box)

	var name_label := UiKit.label(_player_name(), 28, Palette.TEXT)
	name_label.name = "NameLabel"
	name_box.add_child(name_label)
	name_box.add_child(UiKit.mono_label("PLAYER   ·   RHYTHM", 11, Palette.DIM_2))

	box.add_child(UiKit.rule())

	var edit_row := UiKit.hbox(10)
	box.add_child(edit_row)
	var edit_label := UiKit.label("名字", 14, Palette.DIM)
	edit_label.custom_minimum_size = Vector2(80, 0)
	edit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	edit_row.add_child(edit_label)

	var edit := LineEdit.new()
	edit.name = "NameEdit"
	edit.max_length = 16
	edit.placeholder_text = "输入名字（最多 16 字）"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 38)
	edit.add_theme_stylebox_override("normal",
		UiTheme.style_box(Palette.PANEL_2, 7, 1, Palette.LINE, Vector4(14, 6, 14, 6)))
	edit.add_theme_stylebox_override("focus",
		UiTheme.style_box(Palette.PANEL_3, 7, 1, Palette.ACCENT, Vector4(14, 6, 14, 6)))
	edit.add_theme_color_override("font_color", Palette.TEXT)
	edit.add_theme_color_override("caret_color", Palette.ACCENT)
	edit_row.add_child(edit)

	var save := UiKit.button("保存", 14, "AccentButton")
	save.name = "SaveButton"
	save.custom_minimum_size = Vector2(86, 38)
	edit_row.add_child(save)

	box.add_child(UiKit.rule())

	var stats_grid := GridContainer.new()
	stats_grid.name = "StatsGrid"
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 14)
	stats_grid.add_theme_constant_override("v_separation", 14)
	box.add_child(stats_grid)

	var specs := [
		["游玩次数", "ValuePlays", Palette.TEXT],
		["谱面库", "ValueLibrary", Palette.ACCENT],
		["最高分", "ValueBestScore", Palette.OK],
		["最高分曲目", "ValueBestTitle", Palette.DIM],
		["最高分准确率", "ValueBestAcc", Palette.TEXT],
		["最近一局", "ValueLast", Palette.DIM],
	]
	for spec in specs:
		var cell := UiKit.flat_panel(Palette.PANEL_2, 8, Vector4(16, 10, 16, 10))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size = Vector2(290, 0)
		var cell_box := UiKit.vbox(2)
		cell.add_child(cell_box)
		cell_box.add_child(UiKit.label(str(spec[0]), 12, Palette.DIM_2))
		var val := UiKit.mono_label("", 20, spec[2])
		val.name = str(spec[1])
		val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cell_box.add_child(val)
		stats_grid.add_child(cell)

	box.add_child(UiKit.rule())
	box.add_child(UiKit.mono_label("名字存在 settings.cfg，统计存在 profile.cfg     ESC 返回", 11, Palette.DIM_2))


## 导出成 .tscn 之前调用：把要脚本操作的节点标成唯一名
func _export_prepare() -> void:
	var names := {
		"NameLabel": "NameLabel", "Avatar": "Avatar", "NameEdit": "NameEdit",
		"StatsGrid": "StatsGrid", "BackButton": "BackButton", "SaveButton": "SaveButton",
		"TopBar": "TopBar", "Card": "Card",
	}
	for key in names:
		var node := find_child(key, true, false)
		if node != null:
			node.name = str(names[key])
			node.unique_name_in_owner = true
	var grid := find_child("StatsGrid", true, false)
	if grid != null:
		for cell in grid.get_children():
			var cell_box := cell.get_child(0)
			for child in cell_box.get_children():
				if child is Label and child.name.begins_with("Value"):
					child.unique_name_in_owner = true
