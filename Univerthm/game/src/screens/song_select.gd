extends Control
## 极简曲绘选曲：点击选择试听，独立确认后开始游玩。

const Neon = preload("res://src/ui/neon_ui.gd")
const Preview = preload("res://src/audio/song_preview.gd")
const GREEN := Color("bdf49c")
const WHITE := Color("f8f6ff")
const MUTED := Color("c3bcd1")
const ROW_REVEAL_DELAY := 0.6
const ROW_SPRING := 260.0
const ROW_DAMPING := 20.0

var _rows: Array = []
var _row_slots: Array[Control] = []
var _row_velocity: Array[float] = []
var _row_entrance_time := 0.0
var _row_generation := 0
var _selected := -1
var _list_box: VBoxContainer
var _list_count: Label
var _detail_title: Label
var _detail_artist: Label
var _detail_illust: Label
var _detail_meta: Label
var _cover: TextureRect
var _cover_empty: Label
var _cover_frame: PanelContainer
var _toast: Label
var _toast_tween: Tween
var _play_button: Button
var _auto_button: Button
var _cover_cache := {}
var _background_cache := {}
var _preview: Node
var _preview_status: Label
var _backgrounds: Array[TextureRect] = []
var _background_tween: Tween
var _body: BoxContainer
var _list_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _leaving := false


func _ready() -> void:
	theme = UiTheme.theme()
	_build()
	_preview = Preview.new()
	_preview.name = "SongPreview"
	add_child(_preview)
	_preview.status_changed.connect(_on_preview_status)
	if App.menu_music != null:
		App.menu_music.stop_immediately()
	App.refresh_library()
	_refresh_list()
	if App.toast != "":
		_show_toast(App.toast)
		App.toast = ""
	if not get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.connect(_on_files_dropped)
	resized.connect(_layout)
	_layout.call_deferred()
	set_process(false)


func _process(delta: float) -> void:
	if _rows.is_empty():
		set_process(false)
		return
	_row_entrance_time += minf(delta, 0.05)
	var ready := _row_entrance_time >= ROW_REVEAL_DELAY
	var settled := ready
	for i in _rows.size():
		if _row_entrance_time < minf(i, 6) * 0.045:
			settled = false
			continue
		var width := _row_slots[i].size.x
		if width <= 0.0:
			settled = false
			continue
		var target := _row_target(i, width) if ready else -width * 0.5
		var row: Button = _rows[i]
		var x := row.position.x
		var velocity := _row_velocity[i]
		var remaining := minf(delta, 0.05)
		while remaining > 0.0:
			var step := minf(remaining, 0.008)
			velocity += ((target - x) * ROW_SPRING - velocity * ROW_DAMPING) * step
			x += velocity * step
			remaining -= step
		if absf(x - target) < 0.35 and absf(velocity) < 0.5:
			x = target
			velocity = 0.0
		else:
			settled = false
		row.position.x = x
		# 半露出的卡片仍露出曲名；完整滑出后内容回到原有排版。
		row.get_node("RowContent").offset_left = 18.0 - minf(x, 0.0) * 0.7
		_row_velocity[i] = velocity
	if settled:
		set_process(false)


func _row_target(index: int, width: float) -> float:
	var distance := absi(index - _selected)
	if distance == 0:
		return 0.0
	if distance == 1:
		return -width * 0.22
	if distance == 2:
		return -width * 0.36
	return -width * 0.5


func _begin_row_entrance(generation: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or generation != _row_generation:
		return
	for i in _rows.size():
		_rows[i].position.x = -_row_slots[i].size.x - 24.0
		_row_velocity[i] = 0.0
	_row_entrance_time = 0.0
	set_process(not _rows.is_empty())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode not in [KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER, KEY_A, KEY_F5, KEY_S, KEY_ESCAPE]:
		return
	# 场景切换会立即移除当前节点，必须在导航前消费按键。
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_UP:
			if not _rows.is_empty():
				_focus_row(wrapi(_selected - 1, 0, _rows.size()))
		KEY_DOWN:
			if not _rows.is_empty():
				_focus_row(wrapi(_selected + 1, 0, _rows.size()))
		KEY_ENTER, KEY_KP_ENTER:
			_play_selected(false)
		KEY_A:
			_play_selected(true)
		KEY_F5:
			_refresh_library()
		KEY_S:
			_open_settings()
		KEY_ESCAPE:
			_back()


func _build() -> void:
	var black := ColorRect.new()
	black.color = Color("0c0715")
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(black)
	add_child(black)
	for i in 2:
		var background := TextureRect.new()
		background.name = "BlurredCover%d" % i
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/cover_blur.gdshader")
		background.material = material
		background.texture = preload("res://assets/menu_deep_space.png")
		UiKit.full_rect(background)
		add_child(background)
		_backgrounds.append(background)
	_backgrounds[1].modulate.a = 0.0

	var top := MarginContainer.new()
	top.name = "TopBar"
	top.anchor_right = 1
	top.offset_left = 48
	top.offset_right = -48
	top.offset_top = 24
	top.offset_bottom = 64
	add_child(top)
	var toolbar := UiKit.hbox(16)
	top.add_child(toolbar)
	toolbar.add_child(Neon.label("Univerthm", 24, WHITE, true))
	toolbar.add_child(Neon.label("/", 24, Neon.PURPLE, true))
	toolbar.add_child(Neon.label("选曲", 17, WHITE, true))
	toolbar.add_child(UiKit.stretch())
	var settings_button := _quiet_button("设置", "音量、打击特效与偏移 · S")
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(_open_settings)
	toolbar.add_child(settings_button)
	var refresh := _quiet_button("↻", "刷新曲库 · F5")
	refresh.name = "RefreshButton"
	refresh.pressed.connect(_refresh_library)
	toolbar.add_child(refresh)
	var folder := _quiet_button("＋", "打开谱面目录，也可直接拖入谱面")
	folder.name = "FolderButton"
	folder.pressed.connect(_open_chart_folder)
	toolbar.add_child(folder)
	var back := _quiet_button("←", "返回主界面 · Esc")
	back.name = "BackButton"
	back.pressed.connect(_back)
	toolbar.add_child(back)

	var main := MarginContainer.new()
	main.name = "Main"
	UiKit.full_rect(main)
	main.offset_left = 56
	main.offset_right = -56
	main.offset_top = 106
	main.offset_bottom = -76
	add_child(main)
	_body = BoxContainer.new()
	_body.name = "MusicBody"
	_body.add_theme_constant_override("separation", 66)
	main.add_child(_body)
	_build_library()
	_build_detail()

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.anchor_right = 1
	footer.anchor_top = 1
	footer.anchor_bottom = 1
	footer.offset_left = 56
	footer.offset_right = -56
	footer.offset_top = -43
	footer.offset_bottom = -20
	add_child(footer)
	footer.add_child(Neon.label("↑↓ 选择   ·   Enter 开始   ·   A 自动演示", 11, MUTED))
	footer.add_child(UiKit.stretch())
	_toast = Neon.label("", 11, GREEN)
	footer.add_child(_toast)
	_preview_status = Neon.label("", 11, GREEN)
	_preview_status.name = "PreviewStatus"
	footer.add_child(_preview_status)


func _quiet_button(title: String, hint: String) -> Button:
	var button := UiKit.button(title, 16)
	button.tooltip_text = hint
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_hover_color", WHITE)
	for state in ["normal", "focus"]:
		button.add_theme_stylebox_override(state, UiTheme.style_box(Color.TRANSPARENT, 0, 0, Color.TRANSPARENT, Vector4(12, 5, 12, 5)))
	for state in ["hover", "pressed"]:
		button.add_theme_stylebox_override(state, UiTheme.style_box(Color(0.6, 0.35, 0.9, 0.14), 0, 0, Color.TRANSPARENT, Vector4(12, 5, 12, 5)))
	return button


func _build_library() -> void:
	var library := UiKit.vbox(20)
	library.name = "Library"
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.size_flags_stretch_ratio = 0.95
	_body.add_child(library)
	var head := UiKit.hbox(10)
	library.add_child(head)
	head.add_child(Neon.label("曲库", 18, WHITE, true))
	head.add_child(UiKit.stretch())
	_list_count = Neon.label("", 12, MUTED)
	head.add_child(_list_count)
	library.add_child(UiKit.rule(Color(0.8, 0.7, 1, 0.18)))
	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "SongListScroll"
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Neon.style_scroll(_list_scroll)
	library.add_child(_list_scroll)
	_list_box = UiKit.vbox(12)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list_box)
	_list_box.resized.connect(func():
		if _row_entrance_time >= ROW_REVEAL_DELAY and not _rows.is_empty():
			set_process(true))


func _build_detail() -> void:
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "DetailScroll"
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_stretch_ratio = 1.05
	Neon.style_scroll(_detail_scroll)
	_body.add_child(_detail_scroll)
	var box := UiKit.vbox(9)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_detail_scroll.add_child(box)
	var center := CenterContainer.new()
	box.add_child(center)
	_cover_frame = Neon.panel(Vector4(5, 5, 5, 5))
	_cover_frame.name = "CoverFrame"
	_cover_frame.cut = 12
	_cover_frame.accents = false
	_cover_frame.edge = Color(0.8, 0.7, 1.0, 0.42)
	_cover_frame.fill = Color(0.05, 0.025, 0.1, 0.4)
	_cover_frame.custom_minimum_size = Vector2(250, 250)
	center.add_child(_cover_frame)
	var art := Control.new()
	_cover_frame.add_child(art)
	_cover = TextureRect.new()
	_cover.name = "SelectedCover"
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(_cover)
	art.add_child(_cover)
	_cover_empty = Neon.label("♪", 70, Neon.PURPLE)
	_cover_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.full_rect(_cover_empty)
	art.add_child(_cover_empty)
	box.add_child(UiKit.gap(1))
	_detail_title = Neon.label("", 32, WHITE, true)
	_detail_title.name = "SongTitle"
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_title.max_lines_visible = 2
	_detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_detail_title)
	_detail_artist = Neon.label("", 13, MUTED)
	_detail_artist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_detail_artist)
	_detail_illust = Neon.label("", 11, MUTED)
	_detail_illust.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_illust.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_detail_illust)
	_detail_meta = Neon.label("", 14, GREEN, true)
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail_meta)
	box.add_child(UiKit.gap(8))
	var actions := UiKit.hbox(18)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	_play_button = UiKit.button("▶  开始", 17)
	_play_button.name = "StartButton"
	_play_button.custom_minimum_size = Vector2(176, 46)
	_play_button.add_theme_font_override("font", Neon.bold())
	_play_button.add_theme_color_override("font_color", Color("160b24"))
	_play_button.add_theme_color_override("font_hover_color", Color("160b24"))
	_play_button.add_theme_color_override("font_pressed_color", Color("160b24"))
	for state in ["normal", "focus"]:
		_play_button.add_theme_stylebox_override(state, UiTheme.style_box(WHITE, 0, 0, WHITE, Vector4(22, 10, 22, 10)))
	for state in ["hover", "pressed"]:
		_play_button.add_theme_stylebox_override(state, UiTheme.style_box(GREEN, 0, 0, GREEN, Vector4(22, 10, 22, 10)))
	_play_button.pressed.connect(_play_selected.bind(false))
	actions.add_child(_play_button)
	_auto_button = _quiet_button("自动演示", "自动演示 · A")
	_auto_button.name = "AutoplayButton"
	_auto_button.pressed.connect(_play_selected.bind(true))
	actions.add_child(_auto_button)


func _layout() -> void:
	var narrow := size.x < 900
	_body.vertical = narrow
	_body.add_theme_constant_override("separation", 22 if narrow else 66)
	_list_scroll.custom_minimum_size.y = 140 if narrow else 0
	var cover_size := clampf(size.y - 468, 170, 280)
	_cover_frame.custom_minimum_size = Vector2(cover_size, cover_size)
	for scroll in [_list_scroll, _detail_scroll]:
		scroll.update_minimum_size()
		scroll.get_combined_minimum_size()
		scroll.queue_sort()


func _refresh_library() -> void:
	_cover_cache.clear()
	_background_cache.clear()
	_preview.stop()
	App.refresh_library()
	_refresh_list()
	_show_toast("已刷新曲库")


func _refresh_list() -> void:
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_row_slots.clear()
	_row_velocity.clear()
	_row_generation += 1
	set_process(false)
	_selected = -1
	_list_count.text = "%d 个谱面" % App.library.size()
	var empty := App.library.is_empty()
	_play_button.disabled = empty
	_auto_button.disabled = empty
	if empty:
		var hint := Neon.label("等待第一首曲子\n\n将谱面拖入窗口，开始新的旅程。", 16, MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_box.add_child(hint)
		var open := _quiet_button("＋ 导入谱面", "打开谱面目录")
		open.pressed.connect(_open_chart_folder)
		_list_box.add_child(open)
		_clear_detail()
		return
	var selected_index := 0
	for i in App.library.size():
		if str(App.library[i].get("key", "")) == App.selected_chart_key:
			selected_index = i
		var button := _make_row(App.library[i], i)
		var slot := Control.new()
		slot.name = "SongSlot_%02d" % i
		slot.custom_minimum_size.y = 100
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list_box.add_child(slot)
		UiKit.full_rect(button)
		button.position.x = -2000.0
		slot.add_child(button)
		_row_slots.append(slot)
		_rows.append(button)
		_row_velocity.append(0.0)
	_focus_row(selected_index)
	_layout.call_deferred()
	_begin_row_entrance(_row_generation)


func _make_row(entry: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.name = "Song_%02d" % index
	button.custom_minimum_size.y = 100
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", UiTheme.style_box(Color(0.02, 0.01, 0.04, 0.22), 0, 0, Color.TRANSPARENT, Vector4.ZERO))
	button.add_theme_stylebox_override("hover", UiTheme.style_box(Color(0.5, 0.26, 0.8, 0.16), 0, 0, Color.TRANSPARENT, Vector4.ZERO))
	button.add_theme_stylebox_override("pressed", UiTheme.style_box(Color(0.5, 0.26, 0.8, 0.25), 0, 0, Color.TRANSPARENT, Vector4.ZERO))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_focus_row.bind(index))
	button.focus_entered.connect(_on_row_focused.bind(entry, index))
	# 键盘方向键只移动曲目焦点，Enter 由选曲页确认开始。
	button.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_play_selected(false)
				button.accept_event()
			elif event.keycode in [KEY_UP, KEY_DOWN]:
				_focus_row(wrapi(index + (-1 if event.keycode == KEY_UP else 1), 0, _rows.size()))
				button.accept_event())
	var mark := ColorRect.new()
	mark.name = "SelectedMark"
	mark.color = GREEN
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.anchor_bottom = 1
	mark.offset_top = 20
	mark.offset_bottom = -20
	mark.offset_right = 3
	mark.hide()
	button.add_child(mark)
	var content := UiKit.hbox(15)
	content.name = "RowContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(content)
	content.offset_left = 18
	content.offset_right = -18
	content.offset_top = 12
	content.offset_bottom = -12
	button.add_child(content)
	var thumb := TextureRect.new()
	thumb.texture = _cover_for(entry)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.custom_minimum_size = Vector2(64, 64)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(thumb)
	var texts := UiKit.vbox(3)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(texts)
	var title := Neon.label(str(entry.get("title", "未命名谱面")), 17, WHITE, true)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(title)
	var artist := Neon.label(str(entry.get("artist", "")), 11, MUTED)
	artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(artist)
	texts.add_child(Neon.label("%s   /   Lv.%d" % [str(entry.get("difficulty", "NORMAL")), int(entry.get("level", 1))], 11, Neon.PURPLE))
	return button


func _focus_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var changed := _selected != index
	_rows[index].grab_focus()
	if changed and _selected != index:
		_on_row_focused(App.library[index], index)


func _on_row_focused(entry: Dictionary, index: int) -> void:
	if _selected == index:
		return
	_selected = index
	set_process(true)
	App.selected_chart_key = str(entry.get("key", ""))
	for i in _rows.size():
		var row: Button = _rows[i]
		row.get_node("SelectedMark").visible = i == index
		row.add_theme_stylebox_override("normal", UiTheme.style_box(Color(0.22, 0.09, 0.36, 0.62) if i == index else Color(0.02, 0.01, 0.04, 0.22), 0, 1 if i == index else 0, Color(0.66, 0.43, 1, 0.5), Vector4.ZERO))
	_list_scroll.ensure_control_visible(_row_slots[index])
	_update_detail(entry)
	_preview.select(entry)


func _cover_for(entry: Dictionary) -> Texture2D:
	var key := str(entry.get("key", ""))
	if not _cover_cache.has(key):
		_cover_cache[key] = ChartSource.load_cover(entry)
	return _cover_cache[key]


func _update_detail(entry: Dictionary) -> void:
	_detail_title.text = str(entry.get("title", "未命名谱面"))
	_detail_artist.text = str(entry.get("artist", ""))
	var credits := "谱师  " + str(entry.get("charter", "—"))
	var illust := str(entry.get("illustrator", ""))
	if illust != "":
		credits += "    /    曲绘  " + illust
	_detail_illust.text = credits
	_detail_meta.text = "%s    /    Lv.%d    /    %s" % [str(entry.get("difficulty", "NORMAL")), int(entry.get("level", 1)), _format_time(float(entry.get("duration", 0.0)))]
	_cover.texture = _cover_for(entry)
	_cover_empty.visible = _cover.texture == null
	_set_background(_cover.texture)


func _set_background(texture: Texture2D) -> void:
	if texture == null:
		texture = preload("res://assets/menu_deep_space.png")
	texture = _soft_background(texture)
	if _background_tween != null and _background_tween.is_valid():
		_background_tween.kill()
	if _backgrounds[1].modulate.a > 0.5:
		_backgrounds[0].texture = _backgrounds[1].texture
	_backgrounds[1].texture = texture
	_backgrounds[1].modulate.a = 0.0
	_background_tween = create_tween()
	_background_tween.tween_property(_backgrounds[1], "modulate:a", 1.0, 0.32)


func _soft_background(texture: Texture2D) -> Texture2D:
	var key := texture.get_instance_id()
	if _background_cache.has(key):
		return _background_cache[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	if image.is_compressed():
		image.decompress()
	var factor := 96.0 / maxf(image.get_width(), image.get_height())
	image.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	var soft := ImageTexture.create_from_image(image)
	if _background_cache.size() >= 4:
		_background_cache.erase(_background_cache.keys()[0])
	_background_cache[key] = soft
	return soft


func _on_preview_status(playing: bool) -> void:
	if is_instance_valid(_preview_status):
		_preview_status.text = "●  试听 / 50%" if playing else ""


func _clear_detail() -> void:
	_preview.stop()
	_detail_title.text = "下一段旋律，等待开启"
	_detail_artist.text = "导入谱面后，曲绘与音乐会在这里相遇。"
	_detail_illust.text = ""
	_detail_meta.text = ""
	_cover.texture = null
	_cover_empty.show()
	_set_background(null)


func _format_time(seconds: float) -> String:
	var total := int(round(maxf(0, seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


func _play_selected(autoplay: bool) -> void:
	if _leaving or _selected < 0 or _selected >= App.library.size():
		return
	_play_entry(App.library[_selected], autoplay)


func _play_entry(entry: Dictionary, autoplay: bool) -> void:
	_preview.stop()
	_leaving = true
	if not App.play_entry(entry, autoplay):
		_leaving = false
		_show_toast(App.toast)
		App.toast = ""
		_preview.select(entry)


func _open_settings() -> void:
	_preview.stop()
	App.goto_settings()


func _back() -> void:
	_preview.stop()
	App.goto_menu()


func _open_chart_folder() -> void:
	DirAccess.make_dir_recursive_absolute("user://charts")
	OS.shell_open(ProjectSettings.globalize_path("user://charts"))


func _on_files_dropped(files: PackedStringArray) -> void:
	var messages: Array = []
	for file in files:
		var result := ChartSource.import_file(str(file))
		messages.append(str(result.get("message", "")))
	_preview.stop()
	_cover_cache.clear()
	_background_cache.clear()
	App.refresh_library()
	_refresh_list()
	_show_toast("  ·  ".join(messages))


func _show_toast(message: String) -> void:
	if message == "":
		return
	_toast.text = message
	_toast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _exit_tree() -> void:
	if is_instance_valid(_preview):
		_preview.stop()
