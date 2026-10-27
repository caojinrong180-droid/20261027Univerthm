extends Control
## 设置界面：界面在 scenes/settings.tscn 里，脚本只负责数值和连线。
## 改一项就存一次（user://settings.cfg），不用点保存。

var _settings: AppSettings
var _preview_player: AudioStreamPlayer

var _rows := {}


func _ready() -> void:
	theme = UiTheme.theme()
	var empty := get_child_count() == 0
	_settings = App.settings
	_preview_player = AudioStreamPlayer.new()
	var snd = load("res://audio/hit.wav")
	if snd is AudioStream:
		_preview_player.stream = snd
	add_child(_preview_player)
	if empty:
		_build()
	_resolve()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE, KEY_Q:
			App.back_from_settings()
		KEY_R:
			_reset_defaults()


# --------------------------------------------------------------------------- #
# 连节点
# --------------------------------------------------------------------------- #

func _find(node_name: String) -> Node:
	var n := get_node_or_null("%" + node_name)
	if n != null:
		return n
	return find_child(node_name, true, false)


func _resolve() -> void:
	_rows = {
		"offset": _find("OffsetRow"),
		"music": _find("MusicRow"),
		"hitvol": _find("HitVolumeRow"),
		"hitsound": _find("HitSoundRow"),
		"hitfx": _find("HitFxRow"),
	}
	var handlers := {
		"offset": _step_offset,
		"music": _step_music,
		"hitvol": _step_hit_volume,
		"hitsound": _toggle_hit_sound,
		"hitfx": _step_hit_fx,
	}
	for key in _rows:
		var row = _rows[key]
		if row == null:
			continue
		var cb: Callable = handlers[key]
		if not row.stepped.is_connected(cb):
			row.stepped.connect(cb)
	var preview := _find("PreviewButton") as Button
	if preview != null and not preview.pressed.is_connected(_preview_hit_sound):
		preview.pressed.connect(_preview_hit_sound)
	var back := _find("BackButton") as Button
	if back != null and not back.pressed.is_connected(_on_back):
		back.pressed.connect(_on_back)
	var reset := _find("ResetButton") as Button
	if reset != null and not reset.pressed.is_connected(_reset_defaults):
		reset.pressed.connect(_reset_defaults)


func _on_back() -> void:
	App.back_from_settings()


# --------------------------------------------------------------------------- #
# 数值刷新
# --------------------------------------------------------------------------- #

func _refresh() -> void:
	if _settings == null:
		return
	_set_row("offset", "%+d ms" % int(round(_settings.audio_offset_ms)))
	_set_row("music", "%d %%" % int(round(_settings.music_volume * 100.0)))
	_set_row("hitvol", "%d %%" % int(round(_settings.hit_volume * 100.0)))
	_set_row("hitsound", "开" if _settings.hit_sound else "关")
	_set_row("hitfx", ["关", "标准", "强"][clampi(_settings.hit_fx, 0, 2)])


func _set_row(key: String, text: String) -> void:
	var row = _rows.get(key)
	if row != null:
		row.set_value(text)


func _save() -> void:
	_settings.save()
	_refresh()


func _step_offset(dir: int) -> void:
	_settings.audio_offset_ms = clampf(_settings.audio_offset_ms + dir * 5.0, -250.0, 250.0)
	_save()


func _step_music(dir: int) -> void:
	_settings.music_volume = clampf(snappedf(_settings.music_volume + dir * 0.05, 0.05), 0.0, 1.0)
	_save()


func _step_hit_volume(dir: int) -> void:
	_settings.hit_volume = clampf(snappedf(_settings.hit_volume + dir * 0.05, 0.05), 0.0, 1.0)
	_save()


func _step_hit_fx(dir: int) -> void:
	_settings.hit_fx = wrapi(int(_settings.hit_fx) + dir, 0, 3)
	_save()


func _preview_hit_sound() -> void:
	if _preview_player == null or _preview_player.stream == null:
		return
	_preview_player.volume_db = linear_to_db(clampf(_settings.hit_volume, 0.0001, 1.0))
	_preview_player.play()


func _toggle_hit_sound(_dir: int) -> void:
	_settings.hit_sound = not _settings.hit_sound
	_save()


func _reset_defaults() -> void:
	_settings.reset()
	_save()


# --------------------------------------------------------------------------- #
# 代码搭界面（场景为空时用）
# --------------------------------------------------------------------------- #

func _make_row(row_name: String, row_title: String, handler: Callable, width := 210) -> StepperRow:
	var row := StepperRow.new()
	row.name = row_name
	row.title = row_title
	row.value_width = width
	row.stepped.connect(handler)
	return row


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	UiKit.full_rect(bg)
	add_child(bg)

	var column := UiKit.vbox(0)
	UiKit.full_rect(column)
	add_child(column)

	var bar := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(22, 12, 22, 12))
	column.add_child(bar)
	var h := UiKit.hbox(10)
	bar.add_child(h)
	h.add_child(UiKit.label("RHYTHM", 21, Palette.ACCENT))
	h.add_child(UiKit.chip("设置", Palette.DIM_2))
	h.add_child(UiKit.stretch())
	var back_top := UiKit.button("← 返回", 14, "GhostButton")
	back_top.name = "BackButton"
	h.add_child(back_top)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(center)

	var panel := UiKit.panel(Palette.PANEL, 12, 1, Palette.LINE, Vector4(30, 14, 30, 14))
	panel.custom_minimum_size = Vector2(840, 0)
	center.add_child(panel)

	var box := UiKit.vbox(2)
	panel.add_child(box)

	var title := UiKit.label("设置", 20, Palette.TEXT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(UiKit.label("改完立刻生效，自动保存。进了游戏后按 Esc 可以暂停。", 12, Palette.DIM_2))
	box.add_child(UiKit.gap(4))

	box.add_child(_section("对音"))
	box.add_child(_make_row("OffsetRow", "音画偏移", _step_offset))
	box.add_child(UiKit.label("正数 = 谱面整体推后。耳机 / 蓝牙有延迟就慢慢加，靠听打击点调。", 11.5, Palette.DIM_2))

	box.add_child(_section("声音"))
	box.add_child(_make_row("MusicRow", "音乐音量", _step_music))

	var hit_vol := _make_row("HitVolumeRow", "打击音音量", _step_hit_volume)
	box.add_child(hit_vol)
	var preview := UiKit.button("试听", 13)
	preview.name = "PreviewButton"
	hit_vol.add_child(preview)

	var pair := UiKit.hbox(18)
	box.add_child(pair)
	var sound_row := _make_row("HitSoundRow", "打击音", _toggle_hit_sound, 112)
	sound_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pair.add_child(sound_row)
	var fx_row := _make_row("HitFxRow", "打击特效", _step_hit_fx, 112)
	fx_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pair.add_child(fx_row)

	box.add_child(UiKit.gap(4))
	box.add_child(UiKit.rule())
	box.add_child(UiKit.gap(2))

	var actions := UiKit.hbox(10)
	box.add_child(actions)
	var back := UiKit.button("← 返回（Esc）", 16, "AccentButton")
	back.name = "AccentBackButton"
	actions.add_child(back)
	var reset := UiKit.button("恢复默认（R）", 15, "GhostButton")
	reset.name = "ResetButton"
	actions.add_child(reset)
	actions.add_child(UiKit.stretch())
	var path_label := UiKit.mono_label(ProjectSettings.globalize_path(AppSettings.PATH), 11, Palette.DIM_2)
	path_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	actions.add_child(path_label)

	var status := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(22, 7, 22, 12))
	column.add_child(status)
	var sh := UiKit.hbox(14)
	status.add_child(sh)
	sh.add_child(UiKit.label("Esc 返回  ·  R 恢复默认  ·  ◀▶ 调整数值", 12, Palette.DIM_2))
	sh.add_child(UiKit.stretch())
	sh.add_child(UiKit.label("存于 user://settings.cfg", 12, Palette.DIM_2))

	var back2 := _find("AccentBackButton") as Button
	if back2 != null and not back2.pressed.is_connected(_on_back):
		back2.pressed.connect(_on_back)


func _section(text: String) -> Control:
	var box := UiKit.vbox(2)
	box.add_child(UiKit.gap(4))
	box.add_child(UiKit.label(text, 12, Palette.ACCENT_DIM))
	box.add_child(UiKit.rule())
	return box


## 导出成 .tscn 之前：给要脚本操作的节点起唯一名
func _export_prepare() -> void:
	if _preview_player != null and _preview_player.get_parent() != null:
		_preview_player.get_parent().remove_child(_preview_player)
		_preview_player.free()
		_preview_player = null
	for n in ["OffsetRow", "MusicRow", "HitVolumeRow", "HitSoundRow", "HitFxRow",
			"PreviewButton", "ResetButton", "BackButton", "AccentBackButton"]:
		var node := find_child(n, true, false)
		if node != null:
			node.unique_name_in_owner = true
