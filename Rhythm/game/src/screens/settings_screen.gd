extends Control
## 设置界面：音画偏移 / 流速 / 判定窗口 / 音量 / 键位 / 辅助选项。
## 改一项就存一次（user://settings.cfg），不用点保存。

var _labels := {}
var _settings: AppSettings
var _preview_player: AudioStreamPlayer


func _ready() -> void:
	theme = UiTheme.theme()
	_settings = App.settings
	_preview_player = AudioStreamPlayer.new()
	var snd = load("res://audio/hit.wav")
	if snd is AudioStream:
		_preview_player.stream = snd
	add_child(_preview_player)
	_build()
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

	_add_section(box, "对音")
	_add_stepper(box, "offset", "音画偏移", _step_offset)
	box.add_child(UiKit.label("正数 = 谱面整体推后。耳机 / 蓝牙有延迟就慢慢加，靠听打击点调。", 11.5, Palette.DIM_2))
	_add_section(box, "手感")
	_add_stepper(box, "speed", "下落速度", _step_speed)
	_add_stepper(box, "window", "判定窗口", _step_window)
	_add_toggle(box, "autoplay", "自动演示", _toggle_autoplay)
	_add_section(box, "声音")
	_add_stepper(box, "music", "音乐音量", _step_music)
	var hit_vol := UiKit.stepper("打击音音量", _step_hit_volume)
	box.add_child(hit_vol["row"])
	_labels["hitvol"] = hit_vol["value"]
	var preview_button := UiKit.button("试听", 13)
	preview_button.pressed.connect(_preview_hit_sound)
	(hit_vol["row"] as HBoxContainer).add_child(preview_button)
	_add_pair(box,
		"hitsound", "打击音", _toggle_hit_sound,
		"hitfx", "打击特效", _step_hit_fx)
	_add_section(box, "界面")
	_add_toggle(box, "layout", "键位布局", _toggle_layout)
	_add_stepper(box, "stagey", "画面垂直偏移", _step_stage_offset)
	box.add_child(UiKit.label("默认 -24px（在居中的基础上往上抬一点）；想严格居中就调到 0。", 11.5, Palette.DIM_2))

	box.add_child(UiKit.gap(4))
	box.add_child(UiKit.rule())
	box.add_child(UiKit.gap(2))

	var actions := UiKit.hbox(10)
	box.add_child(actions)
	var back := UiKit.button("← 返回（Esc）", 16, "AccentButton")
	back.pressed.connect(func(): App.back_from_settings())
	actions.add_child(back)

	var reset := UiKit.button("恢复默认（R）", 15, "GhostButton")
	reset.pressed.connect(_reset_defaults)
	actions.add_child(reset)

	actions.add_child(UiKit.stretch())
	var path_label := UiKit.mono_label(ProjectSettings.globalize_path(AppSettings.PATH), 11, Palette.DIM_2)
	path_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	actions.add_child(path_label)

	column.add_child(_build_statusbar())
	back.grab_focus()


func _build_topbar() -> Control:
	var bar := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(22, 12, 22, 12))
	var h := UiKit.hbox(10)
	bar.add_child(h)
	h.add_child(UiKit.label("RHYTHM", 21, Palette.ACCENT))
	h.add_child(UiKit.chip("设置", Palette.DIM_2))
	h.add_child(UiKit.stretch())
	var back := UiKit.button("← 选曲", 14, "GhostButton")
	back.pressed.connect(func(): App.back_from_settings())
	h.add_child(back)
	return bar


func _build_statusbar() -> Control:
	var bar := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(22, 7, 22, 12))
	var h := UiKit.hbox(14)
	bar.add_child(h)
	h.add_child(UiKit.label("Esc 返回  ·  R 恢复默认  ·  ◀▶ 调整数值", 12, Palette.DIM_2))
	h.add_child(UiKit.stretch())
	h.add_child(UiKit.label("存于 user://settings.cfg", 12, Palette.DIM_2))
	return bar


func _add_section(parent: VBoxContainer, text: String) -> void:
	parent.add_child(UiKit.gap(4))
	parent.add_child(UiKit.label(text, 12, Palette.ACCENT_DIM))
	parent.add_child(UiKit.rule())


func _add_stepper(parent: VBoxContainer, key: String, row_label: String, handler: Callable) -> void:
	var made := UiKit.stepper(row_label, handler)
	parent.add_child(made["row"])
	_labels[key] = made["value"]


func _add_toggle(parent: VBoxContainer, key: String, row_label: String, handler: Callable) -> void:
	# 布尔项也复用 stepper（左右拨一下就翻转）
	var made := UiKit.stepper(row_label, handler, 190)
	parent.add_child(made["row"])
	_labels[key] = made["value"]


## 两个紧凑的步进项放一行，省纵向空间
func _add_pair(parent: VBoxContainer,
		key_a: String, label_a: String, handler_a: Callable,
		key_b: String, label_b: String, handler_b: Callable) -> void:
	var row := UiKit.hbox(18)
	parent.add_child(row)
	var specs := [[key_a, label_a, handler_a], [key_b, label_b, handler_b]]
	for spec in specs:
		var made := UiKit.stepper(str(spec[1]), spec[2], 112)
		var stepper_row: HBoxContainer = made["row"]
		stepper_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(stepper_row)
		_labels[str(spec[0])] = made["value"]


# --------------------------------------------------------------------------- #
# 数值刷新
# --------------------------------------------------------------------------- #

func _refresh() -> void:
	if _settings == null:
		return
	_labels["offset"].text = "%+d ms" % int(round(_settings.audio_offset_ms))
	_labels["speed"].text = "%.2f×  (判定线→顶 %.2f 秒)" % [_settings.speed_mult, _settings.visible_seconds()]
	_labels["window"].text = "%.2f×  (%s ms)" % [
		_settings.judge_window_scale,
		" / ".join([
			"%.0f" % (RhythmJudge.PERFECT_PLUS_SEC * 1000.0 * _settings.judge_window_scale),
			"%.0f" % (RhythmJudge.PERFECT_SEC * 1000.0 * _settings.judge_window_scale),
			"%.0f" % (RhythmJudge.GOOD_SEC * 1000.0 * _settings.judge_window_scale),
		]),
	]
	_labels["music"].text = "%d %%" % int(round(_settings.music_volume * 100.0))
	_labels["hitvol"].text = "%d %%" % int(round(_settings.hit_volume * 100.0))
	_labels["hitsound"].text = "开" if _settings.hit_sound else "关"
	_labels["hitfx"].text = ["关", "标准", "强"][clampi(_settings.hit_fx, 0, 2)]
	_labels["autoplay"].text = "开启" if _settings.autoplay else "关闭"
	_labels["layout"].text = str(AppSettings.KEY_LAYOUT_LABELS.get(_settings.key_layout, _settings.key_layout))
	_labels["stagey"].text = "%+d px" % int(round(_settings.stage_offset_px))


func _save() -> void:
	_settings.save()
	_refresh()


func _step_offset(dir: int) -> void:
	_settings.audio_offset_ms = clampf(_settings.audio_offset_ms + dir * 5.0, -250.0, 250.0)
	_save()


func _step_speed(dir: int) -> void:
	_settings.speed_mult = clampf(snappedf(_settings.speed_mult + dir * 0.25, 0.25), 0.25, 4.0)
	_save()


func _step_window(dir: int) -> void:
	_settings.judge_window_scale = clampf(snappedf(_settings.judge_window_scale + dir * 0.1, 0.1), 0.4, 2.5)
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


func _toggle_autoplay(_dir: int) -> void:
	_settings.autoplay = not _settings.autoplay
	_save()


func _toggle_layout(_dir: int) -> void:
	_settings.key_layout = "dfjk" if _settings.key_layout == "asdf_jkl" else "asdf_jkl"
	_save()


func _step_stage_offset(dir: int) -> void:
	_settings.stage_offset_px = clampf(_settings.stage_offset_px + dir * 4.0, -400.0, 400.0)
	_save()


func _reset_defaults() -> void:
	_settings.reset()
	_save()
