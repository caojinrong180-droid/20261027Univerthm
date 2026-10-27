extends Control
## 选曲界面：谱面库列表 + 右侧详情 + 设置入口。
## 排版照网页版制谱器的深色风格（顶栏 / 左侧列表 / 右侧面板 / 底部状态栏）。

var _rows: Array = []
var _selected := -1
var _list_box: VBoxContainer
var _list_count: Label
var _detail_title: Label
var _detail_artist: Label
var _detail_illust: Label
var _detail_chips: HBoxContainer
var _detail_source: Label
var _detail_audio: Label
var _detail_length: Label
var _detail_keys: Label
var _detail_warn: Label
var _cover: TextureRect
var _cover_empty: Label
var _toast: Label
var _toast_tween: Tween
var _play_button: Button
var _auto_button: Button
var _cover_cache := {}


func _ready() -> void:
	theme = UiTheme.theme()
	_build()
	App.refresh_library()
	_refresh_list()
	if App.toast != "":
		_show_toast(App.toast)
		App.toast = ""
	if not get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.connect(_on_files_dropped)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F5:
			_refresh_library()
		KEY_A:
			_play_selected(true)
		KEY_S:
			App.goto_settings()
		KEY_ESCAPE:
			App.goto_start()


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

	var main := UiKit.hbox(0)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(main)
	main.add_child(_build_list_panel())
	main.add_child(_build_detail_panel())

	column.add_child(_build_statusbar())


func _build_topbar() -> Control:
	var bar := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(22, 12, 22, 12))
	var h := UiKit.hbox(10)
	bar.add_child(h)

	var brand := UiKit.label("RHYTHM", 21, Palette.ACCENT)
	h.add_child(brand)
	h.add_child(UiKit.chip("rchart v3", Palette.DIM_2))
	h.add_child(UiKit.gap(8))

	var settings_btn := UiKit.button("设置", 14, "GhostButton")
	settings_btn.pressed.connect(func(): App.goto_settings())
	h.add_child(settings_btn)

	var refresh_btn := UiKit.button("刷新 (F5)", 14, "GhostButton")
	refresh_btn.pressed.connect(_refresh_library)
	h.add_child(refresh_btn)

	var folder_btn := UiKit.button("谱面目录", 14, "GhostButton")
	folder_btn.pressed.connect(_open_chart_folder)
	h.add_child(folder_btn)

	var quit_btn := UiKit.button("退出", 14, "GhostButton")
	quit_btn.pressed.connect(func(): App.quit_game())
	h.add_child(quit_btn)

	h.add_child(UiKit.stretch())
	_list_count = UiKit.label("", 13, Palette.DIM)
	h.add_child(_list_count)
	return bar


func _build_list_panel() -> Control:
	var panel := UiKit.panel(Palette.PANEL_2, 0, 0, Color(0, 0, 0, 0), Vector4(20, 16, 20, 16))
	panel.custom_minimum_size = Vector2(480, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := UiKit.vbox(10)
	panel.add_child(box)

	var header := UiKit.hbox(8)
	header.add_child(UiKit.label("谱面库", 15, Palette.DIM))
	header.add_child(UiKit.stretch())
	header.add_child(UiKit.label("↑↓ 选择  ·  Enter 开始", 12, Palette.DIM_2))
	box.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)

	_list_box = UiKit.vbox(6)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	box.add_child(UiKit.gap(2))
	return panel


func _build_detail_panel() -> Control:
	var panel := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(24, 20, 24, 20))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := UiKit.vbox(12)
	panel.add_child(box)

	var top := UiKit.hbox(18)
	box.add_child(top)

	var cover_frame := PanelContainer.new()
	cover_frame.custom_minimum_size = Vector2(176, 176)
	cover_frame.add_theme_stylebox_override("panel",
		UiTheme.style_box(Palette.BG_DEEP, 10, 1, Palette.LINE, Vector4(0, 0, 0, 0)))
	var cover_inner := Control.new()
	cover_inner.custom_minimum_size = Vector2(176, 176)
	cover_frame.add_child(cover_inner)
	_cover = TextureRect.new()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	UiKit.full_rect(_cover)
	cover_inner.add_child(_cover)
	_cover_empty = UiKit.label("无曲绘", 14, Palette.DIM_2)
	_cover_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.full_rect(_cover_empty)
	cover_inner.add_child(_cover_empty)
	top.add_child(cover_frame)

	var meta_box := UiKit.vbox(8)
	meta_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_child(meta_box)

	_detail_title = UiKit.label("", 25, Palette.TEXT)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_box.add_child(_detail_title)

	_detail_artist = UiKit.label("", 15, Palette.DIM)
	_detail_artist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_box.add_child(_detail_artist)

	# 曲绘作者（谱面 meta.illustrator，制谱器「曲绘画师」那栏；没填就不占位）
	_detail_illust = UiKit.label("", 13, Palette.DIM_2)
	_detail_illust.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_box.add_child(_detail_illust)

	_detail_chips = UiKit.hbox(6)
	meta_box.add_child(_detail_chips)

	box.add_child(UiKit.rule())

	var info := UiKit.vbox(7)
	box.add_child(info)
	_detail_source = _add_info_row(info, "谱面文件")
	_detail_audio = _add_info_row(info, "音频")
	_detail_length = _add_info_row(info, "时长")
	_detail_keys = _add_info_row(info, "判定键")
	_detail_keys.text = "A S D F / J K L ;"

	_detail_warn = UiKit.label("", 12, Palette.WARN)
	_detail_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_warn)

	box.add_child(UiKit.stretch_v())

	var actions := UiKit.hbox(10)
	box.add_child(actions)
	_play_button = UiKit.button("▶  开始", 18, "AccentButton")
	_play_button.pressed.connect(func(): _play_selected(false))
	_play_button.custom_minimum_size = Vector2(180, 46)
	actions.add_child(_play_button)

	_auto_button = UiKit.button("自动演示 (A)", 16)
	_auto_button.pressed.connect(func(): _play_selected(true))
	_auto_button.custom_minimum_size = Vector2(160, 46)
	actions.add_child(_auto_button)
	return panel


func _add_info_row(parent: VBoxContainer, name: String) -> Label:
	var row := UiKit.hbox(12)
	parent.add_child(row)
	var name_label := UiKit.label(name, 13, Palette.DIM_2)
	name_label.custom_minimum_size = Vector2(88, 0)
	row.add_child(name_label)
	var value := UiKit.mono_label("—", 12, Palette.DIM)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(value)
	return value


func _build_statusbar() -> Control:
	var bar := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(22, 7, 22, 7))
	var h := UiKit.hbox(14)
	bar.add_child(h)
	var hint := UiKit.label("↑↓ 选择 · Enter 开始 · A 自动演示 · F5 刷新 · 拖 zip 进窗口导入", 12, Palette.DIM_2)
	h.add_child(hint)
	h.add_child(UiKit.stretch())
	_toast = UiKit.label("", 12, Palette.OK)
	h.add_child(_toast)
	return bar


# --------------------------------------------------------------------------- #
# 列表
# --------------------------------------------------------------------------- #

func _refresh_library() -> void:
	App.refresh_library()
	_refresh_list()
	_show_toast("已刷新：%d 个谱面" % App.library.size())


func _refresh_list() -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_rows.clear()

	if App.library.is_empty():
		_list_count.text = "0 个谱面"
		_selected = -1
		var hint := UiKit.label(
			"charts 里还没有谱面。\n\n把制谱器导出的 zip 直接拖进这个窗口，\n或者放到下面的目录里再按 F5。",
			14, Palette.DIM_2)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_box.add_child(hint)
		var open_btn := UiKit.button("打开谱面目录", 14)
		open_btn.pressed.connect(_open_chart_folder)
		_list_box.add_child(open_btn)
		_play_button.disabled = true
		_auto_button.disabled = true
		_clear_detail()
		return

	_play_button.disabled = false
	_auto_button.disabled = false

	for i in App.library.size():
		var button := _make_row(App.library[i], i)
		_list_box.add_child(button)
		_rows.append(button)
	_list_count.text = "%d 个谱面" % App.library.size()
	_focus_row(0)


func _make_row(entry: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 68)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal",
		UiTheme.style_box(Palette.PANEL_2, 8, 1, Palette.LINE, Vector4(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover",
		UiTheme.style_box(Color("#181d27"), 8, 1, Color("#2c3545"), Vector4(0, 0, 0, 0)))
	button.add_theme_stylebox_override("pressed",
		UiTheme.style_box(Color("#1d232e"), 8, 1, Palette.ACCENT_DIM, Vector4(0, 0, 0, 0)))
	button.add_theme_stylebox_override("focus",
		UiTheme.style_box(Color("#111722"), 8, 1, Palette.ACCENT, Vector4(0, 0, 0, 0)))
	button.pressed.connect(func(): _play_entry(entry, false))
	button.focus_entered.connect(func(): _on_row_focused(entry, index))

	var content := UiKit.hbox(12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.anchor_left = 0.0
	content.anchor_top = 0.0
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 16.0
	content.offset_right = -16.0
	content.offset_top = 9.0
	content.offset_bottom = -9.0
	button.add_child(content)

	var number := UiKit.mono_label("%02d" % (index + 1), 13, Palette.DIM_2)
	number.custom_minimum_size = Vector2(26, 0)
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(number)

	var text_box := UiKit.vbox(2)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(text_box)

	var title := UiKit.label(str(entry.get("title", "未命名谱面")), 17, Palette.TEXT)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(title)

	var artist := UiKit.label(str(entry.get("artist", "")) + "   " + str(entry.get("charter", "")), 12, Palette.DIM_2)
	artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	artist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(artist)

	var difficulty := str(entry.get("difficulty", "NORMAL"))
	var chip := UiKit.chip(difficulty, Palette.difficulty_color(difficulty), 12)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(chip)

	var level := UiKit.mono_label("Lv.%d" % int(entry.get("level", 1)), 12, Palette.DIM)
	level.custom_minimum_size = Vector2(46, 0)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(level)

	var notes := UiKit.mono_label("%d notes" % int(entry.get("note_count", 0)), 12, Palette.DIM_2)
	notes.custom_minimum_size = Vector2(70, 0)
	notes.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notes.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(notes)
	return button


func _focus_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_selected = index
	(_rows[index] as Button).grab_focus()


func _on_row_focused(entry: Dictionary, index: int) -> void:
	_selected = index
	_update_detail(entry)


# --------------------------------------------------------------------------- #
# 详情
# --------------------------------------------------------------------------- #

func _update_detail(entry: Dictionary) -> void:
	var chart: Dictionary = entry.get("chart", {})

	_detail_title.text = str(entry.get("title", "未命名谱面"))
	_detail_artist.text = "%s   ·   谱师 %s" % [
		str(entry.get("artist", "")),
		str(entry.get("charter", "")) if str(entry.get("charter", "")) != "" else "—",
	]

	var illustrator := str(entry.get("illustrator", ""))
	_detail_illust.text = "曲绘  %s" % illustrator if illustrator != "" else ""
	_detail_illust.visible = illustrator != ""

	for child in _detail_chips.get_children():
		_detail_chips.remove_child(child)
		child.queue_free()
	var difficulty := str(entry.get("difficulty", "NORMAL"))
	_detail_chips.add_child(UiKit.chip(difficulty, Palette.difficulty_color(difficulty), 12))
	_detail_chips.add_child(UiKit.chip("Lv.%d" % int(entry.get("level", 1)), Palette.TEXT, 12))
	_detail_chips.add_child(UiKit.chip("%d 音符" % int(entry.get("note_count", 0)), Palette.DIM, 12))

	_detail_source.text = str(entry.get("source", "—"))
	_detail_audio.text = str(entry.get("audio_file", "")) if bool(entry.get("has_audio", false)) \
		else "没有音频（用内部时钟计时）"
	_detail_length.text = "%s  ·  总长 %.1f 秒" % [
		_format_time(float(entry.get("duration", 0.0))), float(entry.get("duration", 0.0))]

	_detail_warn.text = ""
	var lanes = chart.get("lanes", [])
	var lane_count: int = lanes.size() if lanes is Array else 0
	_detail_keys.text = "%d 轨  ·  判定区 ASDF / JKL;  ·  轨道透明也能打" % lane_count

	_update_cover(entry)


func _update_cover(entry: Dictionary) -> void:
	_cover_empty.visible = true
	_cover.texture = null
	if not bool(entry.get("has_cover", false)):
		return
	var key := str(entry.get("key", ""))
	if _cover_cache.has(key):
		_cover.texture = _cover_cache[key]
	else:
		var tex := ChartSource.load_cover(entry)
		_cover_cache[key] = tex
		_cover.texture = tex
	if _cover.texture != null:
		_cover_empty.visible = false


func _clear_detail() -> void:
	_detail_title.text = "还没有谱面"
	_detail_artist.text = "做好谱面后：制谱器 Ctrl+S 导出 zip，拖进这个窗口就行"
	_detail_source.text = "—"
	_detail_audio.text = "—"
	_detail_length.text = "—"
	_detail_keys.text = "—"
	_detail_warn.text = ""
	_cover.texture = null
	_cover_empty.visible = true
	for child in _detail_chips.get_children():
		_detail_chips.remove_child(child)
		child.queue_free()


func _format_time(seconds: float) -> String:
	var total := int(round(maxf(0.0, seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


# --------------------------------------------------------------------------- #
# 动作
# --------------------------------------------------------------------------- #

func _play_selected(autoplay: bool) -> void:
	if _selected < 0 or _selected >= App.library.size():
		_show_toast("先选一个谱面")
		return
	_play_entry(App.library[_selected], autoplay)


func _play_entry(entry: Dictionary, autoplay: bool) -> void:
	var ok := App.play_entry(entry, autoplay)
	if not ok:
		_show_toast(App.toast)
		App.toast = ""


func _open_chart_folder() -> void:
	DirAccess.make_dir_recursive_absolute("user://charts")
	OS.shell_open(ProjectSettings.globalize_path("user://charts"))


func _on_files_dropped(files: PackedStringArray) -> void:
	var messages: Array = []
	for file in files:
		var res := ChartSource.import_file(str(file))
		messages.append(str(res.get("message", "")))
	App.refresh_library()
	_refresh_list()
	_show_toast("  ·  ".join(messages))


func _show_toast(text: String) -> void:
	if _toast == null or text == "":
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)
