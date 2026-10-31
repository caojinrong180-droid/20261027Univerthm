extends Control
## 设置界面：界面在 scenes/settings.tscn 里，脚本只负责数值和连线。

const Calibration = preload("res://src/ui/calibration_overlay.gd")
const Tutorial = preload("res://src/ui/tutorial_overlay.gd")

var _settings: AppSettings
var _preview_player: AudioStreamPlayer
## 「辅助测量」浮窗，第一次点按钮时才建
var _calibration: Calibration
## 新手教程弹窗，第一次点「重新查看」时才建
var _tutorial: Tutorial

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
	_ensure_fullscreen_row()
	_ensure_unlock_row()
	_rows = {
		"offset": _find("OffsetRow"),
		"music": _find("MusicRow"),
		"hitvol": _find("HitVolumeRow"),
		"hitsound": _find("HitSoundRow"),
		"hitfx": _find("HitFxRow"),
		"fullscreen": _find("FullscreenRow"),
		"unlockall": _find("UnlockAllRow"),
	}
	var handlers := {
		"offset": _step_offset,
		"music": _step_music,
		"hitvol": _step_hit_volume,
		"hitsound": _toggle_hit_sound,
		"hitfx": _step_hit_fx,
		"fullscreen": _toggle_fullscreen,
		"unlockall": _toggle_unlock_all,
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
	var accent_back := _find("AccentBackButton") as Button
	if accent_back != null and not accent_back.pressed.is_connected(_on_back):
		accent_back.pressed.connect(_on_back)
	var reset := _find("ResetButton") as Button
	if reset != null and not reset.pressed.is_connected(_reset_defaults):
		reset.pressed.connect(_reset_defaults)
	_ensure_calib_button()
	_ensure_tutorial_button()


## 「全屏」开关：场景里没有就补一行（跟在打击音 / 特效那排后面）
func _ensure_fullscreen_row() -> void:
	var anchor_row := _find("HitFxRow") as Control
	if anchor_row == null:
		return
	var row := find_child("FullscreenRow", true, false) as StepperRow
	if row == null:
		row = _make_row("FullscreenRow", "全屏", _toggle_fullscreen, 118)
		var line := anchor_row.get_parent()
		var box := line.get_parent()
		# 先进场景树（StepperRow 的 _ready 才会把 Title / ValueBox 建出来），再套样式
		box.add_child(row)
		box.move_child(row, line.get_index() + 1)
		_style_stepper(row)


## 「全部解锁」的调试开关：场景里没有就补一行（排在「全屏」后面）
func _ensure_unlock_row() -> void:
	var anchor := find_child("FullscreenRow", true, false) as Control
	if anchor == null:
		anchor = _find("HitFxRow") as Control
	if anchor == null:
		return
	var row := find_child("UnlockAllRow", true, false) as StepperRow
	if row == null:
		row = _make_row("UnlockAllRow", "全部解锁（Debug）", _toggle_unlock_all, 118)
		var box := anchor.get_parent()
		box.add_child(row)
		box.move_child(row, anchor.get_index() + 1)
		_style_stepper(row)
		var hint := NeonUi.label("调试用：跳过逐首解锁，所有曲目直接可玩。", 11, NeonUi.MUTED)
		hint.name = "UnlockAllHint"
		box.add_child(hint)
		box.move_child(hint, row.get_index() + 1)


## 「辅助测量」的小按钮：场景里没有就在「音画偏移」标题后面补一个
func _ensure_calib_button() -> void:
	var row := _rows.get("offset") as Control
	if row == null:
		return
	var button := row.get_node_or_null("CalibButton") as Button
	if button == null:
		button = NeonUi.button("辅助测量", false, 14)
		button.name = "CalibButton"
		button.tooltip_text = "跟着节拍打 5 次，测出来的延迟直接写进音画偏移"
		button.custom_minimum_size = Vector2(104, 36)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_color_override("font_color", NeonUi.MUTED)
		row.add_child(button)
		var title := row.get_node_or_null("Title")
		if title != null:
			row.move_child(button, title.get_index() + 1)
	if not button.pressed.is_connected(_open_calibration):
		button.pressed.connect(_open_calibration)


func _open_calibration() -> void:
	if _calibration == null:
		_calibration = Calibration.new()
		_calibration.name = "CalibrationOverlay"
		UiKit.full_rect(_calibration)
		_calibration.applied.connect(_on_calibration_applied)
		add_child(_calibration)
	_calibration.open()


func _on_calibration_applied(value_ms: float) -> void:
	_settings.audio_offset_ms = clampf(round(value_ms), -250.0, 250.0)
	_save()


## 「新手教程」按钮：加在底部那排（返回 / 恢复默认 / 新手教程），点开同一个教程弹窗
func _ensure_tutorial_button() -> void:
	var actions := _actions_row()
	if actions == null:
		return
	var button := find_child("TutorialButton", true, false) as Button
	if button == null:
		button = NeonUi.button("新手教程", false, 15)
		button.name = "TutorialButton"
		button.tooltip_text = "每次启动后首次进入主界面会自动弹出；这里可以随时再看"
		button.custom_minimum_size = Vector2(150, 46)
		actions.add_child(button)
		var reset := _find("ResetButton") as Button
		var index := actions.get_child_count() - 1
		if reset != null:
			index = reset.get_index() + 1
		actions.move_child(button, index)
	if not button.pressed.is_connected(_open_tutorial):
		button.pressed.connect(_open_tutorial)


## 底部那排：返回 / 恢复默认 / 新手教程
func _actions_row() -> Control:
	var back := _find("AccentBackButton") as Control
	if back == null:
		return null
	return back.get_parent() as Control


func _open_tutorial() -> void:
	if _tutorial == null:
		_tutorial = Tutorial.new()
		_tutorial.name = "TutorialOverlay"
		UiKit.full_rect(_tutorial)
		_tutorial.closed.connect(_on_tutorial_closed)
		add_child(_tutorial)
	_tutorial.open()


func _on_tutorial_closed() -> void:
	if _settings == null or _settings.tutorial_seen:
		return
	_settings.tutorial_seen = true
	_settings.save()


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
	_set_row("unlockall", "开" if _settings.unlock_all else "关")
	_set_row("fullscreen", "开" if _settings.fullscreen else "关")


func _set_row(key: String, text: String) -> void:
	var row = _rows.get(key)
	if row != null:
		row.set_value(text)


func _save() -> void:
	_settings.save()
	App.refresh_music_volume()
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


func _toggle_unlock_all(_dir: int) -> void:
	_settings.unlock_all = not _settings.unlock_all
	_save()


## 全屏开关：写进设置并立刻切换窗口（F11 也是改这个值）
func _toggle_fullscreen(_dir: int) -> void:
	App.set_fullscreen(not _settings.fullscreen)
	_refresh()


func _reset_defaults() -> void:
	_settings.reset()
	_save()


# --------------------------------------------------------------------------- #
# 代码搭界面（场景为空时用）
# --------------------------------------------------------------------------- #

func _make_row(row_name: String, row_title: String, handler: Callable, width := 170) -> StepperRow:
	var row := StepperRow.new()
	row.name = row_name
	row.title = row_title
	row.value_width = width
	row.stepped.connect(handler)
	return row


func _build() -> void:
	NeonUi.background(self)
	var background := _find("SpaceBackground") as TextureRect
	background.texture = load("res://assets/settings_black_hole_glitch.png")
	NeonUi.topbar(self, "设置")
	NeonUi.footer(self, "Esc 返回  ·  R 恢复默认  ·  ◀ ▶ 调整数值", "")

	var panel := NeonUi.content(self)
	panel.fill = Color(0.025, 0.015, 0.055, 0.84)
	var box := UiKit.vbox(5)
	panel.add_child(box)
	box.add_child(NeonUi.heading("设置", "SYSTEM / CONFIG"))
	box.add_child(UiKit.gap(7))
	box.add_child(NeonUi.section("对音", "CALIBRATION"))
	var offset := _make_row("OffsetRow", "音画偏移", _step_offset)
	box.add_child(offset)
	_style_stepper(offset)
	box.add_child(NeonUi.label("正数会将谱面整体推后；使用耳机或蓝牙设备时，可根据打击点逐步调整。", 12, NeonUi.MUTED))
	box.add_child(UiKit.gap(5))
	box.add_child(NeonUi.section("声音", "AUDIO"))
	var music := _make_row("MusicRow", "音乐音量", _step_music)
	box.add_child(music)
	_style_stepper(music)

	var hit_line := UiKit.hbox(12)
	box.add_child(hit_line)
	var hit_volume := _make_row("HitVolumeRow", "打击音音量", _step_hit_volume)
	hit_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hit_line.add_child(hit_volume)
	_style_stepper(hit_volume)
	var preview := NeonUi.button("试听", false, 15)
	preview.name = "PreviewButton"
	preview.custom_minimum_size = Vector2(84, 38)
	hit_line.add_child(preview)

	var pair := UiKit.hbox(22)
	box.add_child(pair)
	var hit_sound := _make_row("HitSoundRow", "打击音", _toggle_hit_sound, 118)
	hit_sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pair.add_child(hit_sound)
	_style_stepper(hit_sound)
	var hit_fx := _make_row("HitFxRow", "打击特效", _step_hit_fx, 118)
	hit_fx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pair.add_child(hit_fx)
	_style_stepper(hit_fx)

	box.add_child(UiKit.stretch())
	box.add_child(UiKit.rule(Color("8342cf")))
	var actions := UiKit.hbox(12)
	box.add_child(actions)
	var back := NeonUi.button("← 返回（Esc）", true, 17)
	back.name = "AccentBackButton"
	back.custom_minimum_size = Vector2(190, 46)
	actions.add_child(back)
	var reset := NeonUi.button("恢复默认（R）", false, 15)
	reset.name = "ResetButton"
	reset.custom_minimum_size = Vector2(170, 46)
	actions.add_child(reset)
	actions.add_child(UiKit.stretch())
	actions.add_child(NeonUi.label("UNIVERTHM  /  CONFIGURATION", 11, NeonUi.MUTED, true))


func _style_stepper(row: StepperRow) -> void:
	row.custom_minimum_size.y = 38
	row.add_theme_constant_override("separation", 10)
	var title_label := row.get_node("Title") as Label
	title_label.add_theme_color_override("font_color", NeonUi.LIGHT)
	title_label.add_theme_font_size_override("font_size", 16)
	var value_box := row.get_node("ValueBox") as PanelContainer
	value_box.custom_minimum_size.y = 36
	value_box.add_theme_stylebox_override("panel", UiTheme.style_box(Color(0.035, 0.025, 0.075, 0.95), 5, 1, Color("815cbb"), Vector4(8, 3, 8, 3)))
	var value_label := row.get_node("ValueBox/Value") as Label
	value_label.add_theme_color_override("font_color", NeonUi.LIGHT)
	value_label.add_theme_font_size_override("font_size", 16)
	for side in ["Prev", "Next"]:
		var old := row.get_node(side) as Button
		var index := old.get_index()
		row.remove_child(old)
		old.free()
		var arrow := NeonUi.button("◀" if side == "Prev" else "▶", false, 14)
		arrow.name = side
		arrow.custom_minimum_size = Vector2(45, 36)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var compact := StyleBoxEmpty.new()
			compact.content_margin_left = 5
			compact.content_margin_right = 5
			arrow.add_theme_stylebox_override(state, compact)
		row.add_child(arrow)
		row.move_child(arrow, index)
		arrow.pressed.connect(row._on_prev if side == "Prev" else row._on_next)


## 导出成 .tscn 之前：给要脚本操作的节点起唯一名
func _export_prepare() -> void:
	if _preview_player != null and _preview_player.get_parent() != null:
		_preview_player.get_parent().remove_child(_preview_player)
		_preview_player.free()
		_preview_player = null
	for n in ["OffsetRow", "MusicRow", "HitVolumeRow", "HitSoundRow", "HitFxRow",
			"FullscreenRow", "UnlockAllRow", "UnlockAllHint", "TutorialButton",
			"PreviewButton", "ResetButton", "BackButton", "AccentBackButton", "CalibButton"]:
		var node := find_child(n, true, false)
		if node != null:
			node.unique_name_in_owner = true
