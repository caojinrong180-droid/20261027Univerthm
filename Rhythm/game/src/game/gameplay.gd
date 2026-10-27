extends Control
## 游玩场景：倒计时 → 播放 → 判定 → 暂停 / 结算。
##
## 时间来源（docs/GAME_INTEGRATION.md 第 4 节）：
##   谱面时间 = 音频时间 - audio.offset - 玩家偏移
## 音频时间用 get_playback_position() + 混音延迟 - 输出延迟算，再用帧时间做平滑。
## 没有音频（例如拖进来一个只有 json 的谱面）时退化成用 delta 累加。

enum State { COUNTDOWN, PLAYING, PAUSED, DONE, UNLOCK }

const LEAD_IN := 2.0
const HIT_SOUND_PATH := "res://audio/hit.wav"

@onready var stage: StageView = $Stage
@onready var post: StagePost = $Post

## 故事板（可选）：包里带 storyboard.json 才有；有的话谱面场会叠上它的后处理
var storyboard: Dictionary = {}
## 解锁动画（帧序列，来自谱面包的 unlock_frames/）
var _unlock: UnlockFrames = null
var _unlock_data: Dictionary = {}
var _chart_scene: Dictionary = {}
var _post_stack: Array = []

var chart: Dictionary = {}
var settings: AppSettings
var judge: RhythmJudge
var player: AudioStreamPlayer
var hit_player: AudioStreamPlayer

var state := State.COUNTDOWN
var chart_time := 0.0
var has_audio := false
var autoplay := false

## 测试用：不换场景、手动推进时间
var debug_mode := false
var debug_run_result: Dictionary = {}


var _countdown_elapsed := 0.0
var _countdown_from := 0.0
var _end_time := 0.0
var _audio_length := 0.0
var _audio_done := false
var _held := {}
var _zones: Array = []
var _auto_cursor := 0
var _use_audio_clock := true
var _pause_layer: Control
var _resume_button: Button
var _pause_stats: Label
var _pause_hit_sound_value: Label
var _pause_hit_volume_value: Label
var _pause_fx_value: Label


# --------------------------------------------------------------------------- #
# 生命周期
# --------------------------------------------------------------------------- #

func _ready() -> void:
	theme = UiTheme.theme()
	settings = App.settings if App.settings != null else AppSettings.new()
	chart = App.session.get("chart", {})
	storyboard = App.session.get("storyboard", {})
	if typeof(storyboard) == TYPE_DICTIONARY and not storyboard.is_empty():
		var spans := StoryboardSource.scene_spans(storyboard, RhythmChart.chart_duration(chart))
		for sp in spans:
			if str(sp["kind"]) == "chart":
				_chart_scene = sp["scene"]
				break
	if not (chart is Dictionary) or chart.is_empty():
		push_warning("没有谱面，回选曲界面")
		App.goto_select()
		return

	autoplay = App.autoplay_enabled()

	judge = RhythmJudge.new()
	judge.setup(chart, settings.judge_window_scale)

	stage.setup(chart, judge, settings, App.session.get("cover"))

	player = AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	add_child(player)
	hit_player = AudioStreamPlayer.new()
	hit_player.name = "HitPlayer"
	add_child(hit_player)
	_apply_audio_settings()

	var stream = App.session.get("stream")
	if stream is AudioStream and stream.get_length() > 0.01:
		player.stream = stream
		has_audio = true
		_audio_length = stream.get_length()
		player.finished.connect(_on_audio_finished)

	var snd = load(HIT_SOUND_PATH)
	if snd is AudioStream:
		hit_player.stream = snd

	_end_time = RhythmChart.chart_duration(chart) + 1.5
	if has_audio:
		_end_time = maxf(_end_time, _audio_length + 0.4)

	# 顶部进度条按「音频长度 / 谱面长度里更长的那个」算（没音频的谱面也不会一下子走满）
	var song_total := RhythmChart.chart_duration(chart)
	if has_audio:
		song_total = maxf(song_total, _audio_length)
	stage.song_length = maxf(0.1, song_total)

	_build_pause_layer()

	_build_unlock()
	_countdown_from = -_chart_offset() - LEAD_IN
	chart_time = _countdown_from
	stage.chart_time = chart_time
	state = State.UNLOCK if _unlock != null else State.COUNTDOWN


func _process(delta: float) -> void:
	_update_story_post()
	match state:
		State.UNLOCK:
			pass          # 帧播放自己走时间，播完发 finished
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.PLAYING:
			_tick_play(delta)


# --------------------------------------------------------------------------- #
# 时间
# --------------------------------------------------------------------------- #

func _chart_offset() -> float:
	var off := float(chart.get("audio", {}).get("offset", 0.0))
	if has_audio:
		off += settings.offset_seconds()
	return off


func _sample_audio_time() -> float:
	var pos := player.get_playback_position()
	pos += AudioServer.get_time_since_last_mix()
	pos -= AudioServer.get_output_latency()
	return pos - _chart_offset()


func _input_time() -> float:
	if state == State.PLAYING and _use_audio_clock and has_audio and not _audio_done and player.playing:
		return _sample_audio_time()
	return chart_time


func _tick_countdown(delta: float) -> void:
	_countdown_elapsed += delta
	chart_time = _countdown_from + _countdown_elapsed
	stage.chart_time = chart_time
	stage.queue_redraw()

	if _countdown_elapsed >= LEAD_IN:
		if has_audio:
			player.play()
		chart_time = -_chart_offset()
		state = State.PLAYING


func _tick_play(delta: float) -> void:
	if _use_audio_clock and has_audio and not _audio_done and player.playing:
		var target := _sample_audio_time()
		var drift := target - chart_time
		if absf(drift) > 0.08:
			chart_time = target          # 大跳（暂停恢复 / 卡顿）直接对齐
		else:
			chart_time += delta + drift * 0.3
	else:
		chart_time += delta

	if autoplay:
		_autoplay_step(chart_time)
	else:
		judge.set_pressed_zones(_zones)

	judge.update(chart_time)

	stage.chart_time = chart_time
	stage.pressed_zones = _zones.duplicate()
	stage.autoplay = autoplay
	stage.queue_redraw()

	if chart_time > _end_time:
		_finish()


func _on_audio_finished() -> void:
	_audio_done = true


# --------------------------------------------------------------------------- #
# 输入
# --------------------------------------------------------------------------- #

func _unhandled_input(event: InputEvent) -> void:
	# 解锁动画期间：任意键（含 Escape）都跳过，不进暂停菜单
	if state == State.UNLOCK:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			skip_unlock()
			get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return
	var code := key_event.physical_keycode
	if code == 0:
		code = key_event.keycode

	if not key_event.pressed:
		_on_key_up(code)
		return

	match state:
		State.PAUSED:
			match code:
				KEY_ESCAPE:
					_resume()
				KEY_R:
					App.retry()
				KEY_Q:
					App.goto_select()
		State.PLAYING:
			match code:
				KEY_ESCAPE:
					_pause()
				KEY_R:
					App.retry()
				_:
					var zone := _zone_for_key(code)
					if zone != "":
						_on_key_down(code, zone)
		State.COUNTDOWN:
			if code == KEY_ESCAPE:
				App.goto_select()
			elif code == KEY_R:
				App.retry()


func _zone_for_key(code: int) -> String:
	var layout := settings.key_layout
	if layout == "dfjk":
		if code == KEY_D or code == KEY_F:
			return "left"
		if code == KEY_J or code == KEY_K:
			return "right"
		return ""
	if code == KEY_A or code == KEY_S or code == KEY_D or code == KEY_F:
		return "left"
	if code == KEY_J or code == KEY_K or code == KEY_L or code == KEY_SEMICOLON:
		return "right"
	return ""


func _on_key_down(code: int, zone: String) -> void:
	if _held.has(code):
		return
	_held[code] = zone
	_rebuild_zones()
	var result := judge.press(zone, _input_time())
	if bool(result.get("hit", false)):
		_play_hit()


func _on_key_up(code: int) -> void:
	if _held.has(code):
		_held.erase(code)
		_rebuild_zones()


func _rebuild_zones() -> void:
	_zones.clear()
	for key in _held.keys():
		var z := str(_held[key])
		if not _zones.has(z):
			_zones.append(z)


# --------------------------------------------------------------------------- #
# 自动演示
# --------------------------------------------------------------------------- #

func _autoplay_step(t: float) -> void:
	while _auto_cursor < judge.notes.size():
		var note: Dictionary = judge.notes[_auto_cursor]
		if float(note["time"]) > t + 0.002:
			break
		if str(note["state"]) == "pending":
			if float(note["time"]) >= t - 0.25:
				var lane: Dictionary = judge.lanes[int(note["lane"])]
				var press_t := maxf(t, float(note["time"]))
				# 判定区可能被 zone 事件动画过，要用「按下那一刻」的生效判定区
				var zone := RhythmChart.lane_zone_at(lane, press_t)
				if zone == "none":
					zone = "left"
				var result := judge.press(zone, press_t, int(note["lane"]))
				if bool(result.get("hit", false)):
					_play_hit()

		_auto_cursor += 1

	# hold 需要一直按住（判定区同样按当前生效值）
	var held_zones: Array = []
	for note in judge.active_holds():
		var lane: Dictionary = judge.lanes[int(note["lane"])]
		var zone := RhythmChart.lane_zone_at(lane, t)
		if zone == "none":
			zone = "left"
		if not held_zones.has(zone):
			held_zones.append(zone)
	_zones = held_zones
	judge.set_pressed_zones(_zones)


# --------------------------------------------------------------------------- #
# 暂停 / 重开 / 结束
# --------------------------------------------------------------------------- #

func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	if has_audio:
		player.stream_paused = true
	_pause_stats.text = "分数 %d   ·   准确率 %.2f%%   ·   连击 %d" % [
		int(round(judge.score)), judge.accuracy_live() * 100.0, judge.max_combo,
	]
	_refresh_pause_audio()
	_pause_layer.visible = true
	if _resume_button != null:
		_resume_button.grab_focus()


func _resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	if has_audio:
		player.stream_paused = false
	_pause_layer.visible = false
	if _resume_button != null:
		_resume_button.release_focus()


func _finish() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	if has_audio:
		player.stop()
	judge.finish(chart_time)

	var meta: Dictionary = chart.get("meta", {})
	var result := {
		"title": str(meta.get("title", "未命名谱面")),
		"artist": str(meta.get("artist", "")),
		"charter": str(meta.get("charter", "")),
		"illustrator": str(meta.get("illustrator", "")),
		"difficulty": str(meta.get("difficulty", "NORMAL")),
		"level": int(meta.get("level", 1)),
		"cover": App.session.get("cover"),
		"entry": App.session.get("entry", {}),
		"score": int(round(judge.score)),
		"accuracy": judge.accuracy_final(),
		"grade": judge.grade(),
		"max_combo": judge.max_combo,
		"counts": judge.counts.duplicate(),
		"total": judge.total_judgeable,
		"note_count": judge.notes.size(),
		"fc": judge.is_full_combo(),
		"early_late": judge.early_late.duplicate(),
		"ap": judge.is_all_perfect(),
		"ap_plus": judge.is_all_perfect_plus(),
		"autoplay": autoplay,
		"length": _end_time,
	}
	App.last_result = result
	debug_run_result = result
	if not autoplay:
		App.record_result(result)          # 个人资料里的游玩次数 / 最高分
	if debug_mode:
		return
	get_tree().change_scene_to_file("res://scenes/results.tscn")


func _play_hit() -> void:
	if settings == null or not settings.hit_sound:
		return
	if hit_player == null or hit_player.stream == null:
		return
	hit_player.volume_db = _db(settings.hit_volume)
	hit_player.play()


func _apply_audio_settings() -> void:
	if settings == null:
		return
	if player != null:
		player.volume_db = _db(settings.music_volume)
	if hit_player != null:
		hit_player.volume_db = _db(settings.hit_volume)


## 暂停面板里的打击音 / 特效：改完立刻生效并存盘
func _pause_step_hit_sound(_dir: int) -> void:
	settings.hit_sound = not settings.hit_sound
	settings.save()
	_refresh_pause_audio()
	if settings.hit_sound:
		_play_hit()


func _pause_step_hit_volume(dir: int) -> void:
	settings.hit_volume = clampf(snappedf(settings.hit_volume + dir * 0.05, 0.05), 0.0, 1.0)
	settings.save()
	_apply_audio_settings()
	_refresh_pause_audio()
	_play_hit()


func _pause_step_hit_fx(dir: int) -> void:
	settings.hit_fx = wrapi(int(settings.hit_fx) + dir, 0, 3)
	settings.save()
	_refresh_pause_audio()


func _refresh_pause_audio() -> void:
	if _pause_hit_sound_value != null:
		_pause_hit_sound_value.text = "开" if settings.hit_sound else "关"
	if _pause_hit_volume_value != null:
		_pause_hit_volume_value.text = "%d%%" % int(round(settings.hit_volume * 100.0))
	if _pause_fx_value != null:
		_pause_fx_value.text = ["关", "标准", "强"][clampi(settings.hit_fx, 0, 2)]


func _db(linear: float) -> float:
	return linear_to_db(clampf(linear, 0.0001, 1.0))


# --------------------------------------------------------------------------- #
# 暂停面板（游玩时不显示任何 UI，只有按 Esc 才出来）
# --------------------------------------------------------------------------- #

func _build_pause_layer() -> void:
	_pause_layer = Control.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.visible = false
	_pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(_pause_layer)
	add_child(_pause_layer)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.74)
	UiKit.full_rect(shade)
	_pause_layer.add_child(shade)

	var panel := UiKit.panel(Palette.PANEL, 14, 1, Palette.LINE, Vector4(28, 24, 28, 24))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240.0
	panel.offset_right = 240.0
	panel.offset_top = -255.0
	panel.offset_bottom = 255.0
	_pause_layer.add_child(panel)

	var box := UiKit.vbox(12)
	panel.add_child(box)

	var title := UiKit.label("已暂停", 26, Palette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_pause_stats = UiKit.mono_label("", 13, Palette.DIM)
	_pause_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_pause_stats)

	box.add_child(UiKit.gap(2))
	box.add_child(UiKit.rule())

	var sound_row := UiKit.stepper("打击音", _pause_step_hit_sound)
	_pause_hit_sound_value = sound_row["value"]
	box.add_child(sound_row["row"])

	var volume_row := UiKit.stepper("打击音音量", _pause_step_hit_volume)
	_pause_hit_volume_value = volume_row["value"]
	box.add_child(volume_row["row"])

	var fx_row := UiKit.stepper("打击特效", _pause_step_hit_fx)
	_pause_fx_value = fx_row["value"]
	box.add_child(fx_row["row"])

	box.add_child(UiKit.gap(4))

	_resume_button = UiKit.button("继续（Esc）", 17, "AccentButton")
	_resume_button.pressed.connect(_resume)
	box.add_child(_resume_button)

	var retry_button := UiKit.button("重试（R）", 17)
	retry_button.pressed.connect(func(): App.retry())
	box.add_child(retry_button)

	var select_button := UiKit.button("选曲（Q）", 17, "GhostButton")
	select_button.pressed.connect(func(): App.goto_select())
	box.add_child(select_button)

	var hint := UiKit.label("音画偏移 / 流速 / 判定窗口在选曲界面的「设置」里", 12, Palette.DIM_2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)


# --------------------------------------------------------------------------- #
# 给测试 / 其它界面用的小接口
# --------------------------------------------------------------------------- #

func is_autoplay() -> bool:
	return autoplay


func get_judge() -> RhythmJudge:
	return judge


func debug_start_now() -> void:
	_countdown_elapsed = LEAD_IN
	chart_time = -_chart_offset()
	state = State.PLAYING


func debug_set_audio_clock(enabled: bool) -> void:
	_use_audio_clock = enabled


func debug_advance(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.PLAYING:
			_tick_play(delta)


## 故事板后处理：一条 shader = 一层，逐层叠（和网页版一致）
func _update_story_post() -> void:
	if post == null:
		return
	if _chart_scene.is_empty():
		if not _post_stack.is_empty():
			_post_stack.clear()
			post.apply([], chart_time)
		return
	_post_stack = StoryboardSource.active_shaders(_chart_scene, chart_time)
	post.apply(_post_stack, chart_time)


# --------------------------------------------------------------------------- #
# 解锁动画（谱面包里导入的视频 -> 烘焙成帧序列）
# --------------------------------------------------------------------------- #

func _build_unlock() -> void:
	# 测试 / 截图 / 无头模式不播，避免每帧推进都要多等 20 秒
	if debug_mode or DisplayServer.get_name() == "headless":
		return
	var entry = App.session.get("entry", {})
	if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
		return
	var data := ChartSource.load_unlock(entry)
	if not bool(data.get("ok", false)):
		return
	_unlock = UnlockFrames.new()
	_unlock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _unlock.setup(data):
		_unlock.queue_free()
		_unlock = null
		return
	add_child(_unlock)
	move_child(_unlock, stage.get_index() + 1)      # 盖在舞台上方、后处理下方
	_unlock.finished.connect(_finish_unlock)
	_unlock.start()


func _finish_unlock() -> void:
	if _unlock != null:
		_unlock.queue_free()
		_unlock = null
	state = State.COUNTDOWN
	_countdown_elapsed = 0.0
	chart_time = _countdown_from
	stage.chart_time = chart_time


## 任意键 / 点击跳过解锁动画
func skip_unlock() -> void:
	if state != State.UNLOCK:
		return
	if _unlock != null:
		_unlock.skip()
	else:
		_finish_unlock()
