extends Control
## 个人资料：玩家名（可改，存进 settings.cfg）+ 游玩统计（user://profile.cfg）。
## 与收藏品共用紫黑宇宙视觉；场景保留可编辑节点。

const Neon = preload("res://src/ui/neon_ui.gd")

var _name_label: Label
var _avatar: AvatarCircle
var _edit: LineEdit
var _stat_grid: GridContainer


func _ready() -> void:
	theme = UiTheme.theme()
	App.refresh_library()
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
	_edit.text_changed.connect(func(_text): _find("SaveHint").text = "最多 16 字 · Enter 保存")
	_find("AccentBackButton").pressed.connect(func(): App.goto_menu())
	_find("ProfileScroll").resized.connect(_resize_profile)
	Neon.style_scroll(_find("ProfileScroll"))
	_resize_profile.call_deferred()


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
		label.get_parent().get_parent().tooltip_text = text


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
	_find("SaveHint").text = "✓ 名字已保存"


# --------------------------------------------------------------------------- #
# 代码搭界面（只在场景是空的时候用；正常游戏走 .tscn）
# --------------------------------------------------------------------------- #

func _build() -> void:
	Neon.background(self)
	Neon.topbar(self, "个人资料")
	Neon.footer(self, "Esc 返回  ·  Enter 保存名字", "PROFILE / PLAYER RECORD")
	var panel := Neon.content(self)
	var box := UiKit.vbox(12)
	panel.add_child(box)
	box.add_child(Neon.heading("个人资料", "PROFILE / PLAYER RECORD", "你的名字，你的节奏，你的每一次突破。"))
	box.add_child(Neon.section("玩家档案", "UNIVERTHM / PERSONAL DATA"))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var body := BoxContainer.new()
	body.name = "ProfileBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	scroll.add_child(body)

	var identity := Neon.panel(Vector4(20, 18, 20, 16))
	identity.name = "IdentityPanel"
	identity.custom_minimum_size.x = 270
	identity.fill = Color(0.055, 0.025, 0.11, 0.8)
	identity.edge = Color("64478b")
	body.add_child(identity)
	var identity_box := UiKit.vbox(10)
	identity.add_child(identity_box)
	var head := UiKit.hbox(14)
	identity_box.add_child(head)
	var avatar := AvatarCircle.new()
	avatar.name = "Avatar"
	avatar.ring_color = Neon.PURPLE
	avatar.text_color = Neon.LIGHT
	avatar.custom_minimum_size = Vector2(64, 64)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(avatar)
	var names := UiKit.vbox(2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(names)
	names.add_child(Neon.label("UNIVERTHM PLAYER", 9, Neon.PURPLE, true))
	var name_label := Neon.label("User", 24, Neon.LIGHT, true)
	name_label.name = "NameLabel"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(name_label)
	names.add_child(Neon.label("PLAYER / 节奏旅人", 10, Neon.MUTED))
	identity_box.add_child(UiKit.rule(Color("543574")))
	identity_box.add_child(Neon.label("玩家名称", 13, Neon.MUTED))
	var edit := LineEdit.new()
	edit.name = "NameEdit"
	edit.max_length = 16
	edit.placeholder_text = "输入名字"
	edit.custom_minimum_size.y = 38
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 17)
	edit.add_theme_color_override("font_color", Neon.LIGHT)
	edit.add_theme_color_override("caret_color", Neon.PURPLE)
	edit.add_theme_color_override("selection_color", Color("6634a5"))
	edit.add_theme_stylebox_override("normal", UiTheme.style_box(Color("110c20"), 0, 1, Color("725394"), Vector4(12, 5, 12, 5)))
	edit.add_theme_stylebox_override("focus", UiTheme.style_box(Color("211037"), 0, 1, Neon.PURPLE, Vector4(12, 5, 12, 5)))
	identity_box.add_child(edit)
	var save := Neon.button("保存名字  ↵", true, 16)
	save.name = "SaveButton"
	identity_box.add_child(save)
	var hint := Neon.label("最多 16 字 · Enter 保存", 11, Neon.MUTED)
	hint.name = "SaveHint"
	identity_box.add_child(hint)
	identity_box.add_child(UiKit.stretch_v())

	var grid := GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	var specs := [
		["游玩次数", "ValuePlays", "PLAY COUNT", 30, Neon.LIGHT],
		["谱面库", "ValueLibrary", "CHART LIBRARY", 30, Neon.PURPLE],
		["最高分", "ValueBestScore", "BEST SCORE", 30, Neon.LIGHT],
		["最高分曲目", "ValueBestTitle", "BEST TRACK", 20, Neon.LIGHT],
		["最高分准确率", "ValueBestAcc", "BEST ACCURACY", 30, Neon.PURPLE],
		["最近一局", "ValueLast", "LAST SESSION", 17, Neon.MUTED],
	]
	for spec in specs:
		var cell := Neon.panel(Vector4(18, 9, 18, 9))
		cell.name = str(spec[1]).trim_prefix("Value") + "Panel"
		cell.fill = Color(0.025, 0.018, 0.05, 0.82)
		cell.edge = Color("59406d")
		cell.cut = 12
		cell.custom_minimum_size = Vector2(180, 82)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var contents := UiKit.vbox(0)
		cell.add_child(contents)
		var top := UiKit.hbox(6)
		contents.add_child(top)
		top.add_child(Neon.label(spec[0], 12, Neon.MUTED))
		top.add_child(UiKit.stretch())
		top.add_child(Neon.label(spec[2], 8, Color("88769d")))
		var val := Neon.label("—", spec[3], spec[4], true)
		val.name = spec[1]
		val.size_flags_vertical = Control.SIZE_EXPAND_FILL
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		contents.add_child(val)
		grid.add_child(cell)

	box.add_child(UiKit.rule(Color("624480")))
	var actions := UiKit.hbox(14)
	box.add_child(actions)
	var back := Neon.button("← 返回（Esc）", true)
	back.name = "AccentBackButton"
	back.custom_minimum_size.x = 200
	actions.add_child(back)
	actions.add_child(UiKit.stretch())
	var note := Neon.label("每一次游玩，都会留下记录。", 12, Neon.MUTED)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(note)


func _resize_profile() -> void:
	var scroll := _find("ProfileScroll") as ScrollContainer
	var body := _find("ProfileBody") as BoxContainer
	var identity := _find("IdentityPanel") as Control
	var narrow := scroll.size.x < 760
	body.vertical = narrow
	identity.custom_minimum_size.x = 0 if narrow else 270
	_stat_grid.columns = 1 if scroll.size.x < 480 else 2
	# 动态排布改变高度后刷新滚动范围。
	scroll.update_minimum_size()
	scroll.get_combined_minimum_size()
	scroll.queue_sort()


func _export_prepare() -> void:
	# 场景保存中性的占位内容；真实玩家信息在 _resolve / _refresh 中填入。
	_name_label.text = "User"
	_avatar.player_name = "User"
	_edit.text = ""
	for value_name in ["ValuePlays", "ValueLibrary", "ValueBestScore", "ValueBestTitle", "ValueBestAcc", "ValueLast"]:
		_set_stat(value_name, "—")
	for key in ["NameLabel", "Avatar", "NameEdit", "StatsGrid", "BackButton", "SaveButton", "AccentBackButton", "SaveHint", "ProfileScroll", "ProfileBody", "IdentityPanel", "ValuePlays", "ValueLibrary", "ValueBestScore", "ValueBestTitle", "ValueBestAcc", "ValueLast"]:
		_find(key).unique_name_in_owner = true
