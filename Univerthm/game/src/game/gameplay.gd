extends Control
## 游玩场景：倒计时 → 播放 → 判定 → 暂停 / 结算。

enum State { COUNTDOWN, PLAYING, PAUSED, DONE, UNLOCK, RESUME }

signal state_changed

const LEAD_IN := 2.0
## 从暂停里恢复时的倒计时秒数
const RESUME_LEAD_IN := 3.0
const HIT_SOUND_PATH := "res://audio/hit.wav"
const PauseActions = preload("res://src/ui/pause_actions.gd")
## 从选曲页「变黑」接过来时：先压住全黑这么久，再淡出去（露出解锁动画 / 舞台）
## 有解锁动画（??? 那首）：黑屏先停 5 秒，让「进入谱面」的黑场落一下，再让动画从黑里起来
const FROM_BLACK_HOLD_UNLOCK := 5.0
## 没有解锁动画：黑屏很短，直接淡出到倒计时
const FROM_BLACK_HOLD_SILENT := 0.15
const FROM_BLACK_FADE := 0.75
const FROM_BLACK_FADE_SILENT := 0.4

@onready var stage: StageView = $Stage
@onready var post: StagePost = $Post

## 故事板（可选）：包里带 storyboard.json 才有；有的话谱面场会叠上它的后处理
var storyboard: Dictionary = {}
## 解锁动画（帧序列，来自谱面包的 unlock_frames/）
var _unlock: UnlockFrames = null
var _unlock_data: Dictionary = {}
var _chart_scene: Dictionary = {}
var _post_stack: Array = []
## 谱面场的故事板图层（文字）；没有图层的包这里是 null
var _story_layers: StoryLayers = null
## 这一趟是不是「神秘曲的第一次踏入」：是的话 Esc 不暂停、不退出
## （中途强关游戏 = 没踏进去过，下次还要重新过红色警告，见 App.commit_entry）
var _first_entry := false
## 这一趟是不是新手教程（第一次进游戏打的那个包）：打完 / 中途退出都直接回主界面
var _tutorial := false

var chart: Dictionary = {}
var settings: AppSettings
var judge: RhythmJudge
var player: AudioStreamPlayer
var hit_player: AudioStreamPlayer

var state := State.COUNTDOWN:
	set(value):
		if state == value:
			return
		state = value
		state_changed.emit()
var chart_time := 0.0
var has_audio := false
var autoplay := false

## 测试用：不换场景、手动推进时间
var debug_mode := false
var debug_run_result: Dictionary = {}


var _countdown_elapsed := 0.0
var _countdown_from := 0.0
## 暂停恢复时冻结在哪个谱面时间
var _resume_from := 0.0
## 重开（同一首曲）时跳过开场倒计时
var _skip_countdown := false
var _countdown_label: Label
var _end_time := 0.0
var _audio_length := 0.0
var _audio_done := false
var _held := {}
var _zones: Array = []
var _auto_cursor := 0
var _use_audio_clock := true
var _pause_layer: Control



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
	# 自动演示不算「踏入」：不锁 Esc、不发警告、不记 entered
	_first_entry = App.needs_first_entry(_entry_key()) and not autoplay
	_tutorial = bool(App.session.get("tutorial", false))

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
		_end_time = maxf(_end_time, _audio_length - _chart_offset() + 0.4)

	# 顶部进度条按「音频长度 / 谱面长度里更长的那个」算（没音频的谱面也不会一下子走满）
	var song_total := RhythmChart.chart_duration(chart)
	if has_audio:
		song_total = maxf(song_total, _audio_length - _chart_offset())
	stage.song_length = maxf(0.1, song_total)

	_build_pause_layer()
	_build_countdown_label()
	_build_story_layers()

	_build_unlock()
	_countdown_from = -_chart_offset() - LEAD_IN
	chart_time = _countdown_from
	stage.chart_time = chart_time
	# 从暂停菜单「重开」进来的这一趟不要开场倒计时，直接进谱面
	var skip_countdown := bool(App.session.get("skip_countdown", false))
	App.session.erase("skip_countdown")
	if _unlock != null:
		_skip_countdown = skip_countdown
		state = State.UNLOCK
	elif skip_countdown:
		_start_playing_now()
	else:
		state = State.COUNTDOWN
	# 选曲页那边已经黑透了：这一侧也从黑里淡出来，接上解锁动画
	if bool(App.session.get("from_black", false)):
		_reveal_from_black()


func _process(delta: float) -> void:
	_update_story_post()
	_update_story_layers()
	match state:
		State.UNLOCK:
			pass          # 帧播放自己走时间，播完发 finished
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.RESUME:
			_tick_resume(delta)
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


## 暂停恢复：画面冻在暂停点，数 3 秒再继续（音乐也等数完再放开）
func _tick_resume(delta: float) -> void:
	_countdown_elapsed += delta
	var remaining := maxf(0.0, RESUME_LEAD_IN - _countdown_elapsed)
	chart_time = _resume_from
	stage.chart_time = chart_time
	stage.queue_redraw()
	_update_countdown_label(remaining)
	# 累加的 delta 可能差一点点到 3.0（浮点），留个 epsilon 免得总是差一帧
	if _countdown_elapsed + 1e-6 >= RESUME_LEAD_IN:
		_hide_countdown_label()
		if has_audio:
			player.stream_paused = false
		chart_time = _resume_from
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
	# 解锁动画期间：整段必须看完。任意键 / 点击都只被吃掉，既不跳过也不进暂停菜单
	if state == State.UNLOCK:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
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

	# 神秘曲的第一次踏入：Esc 既不暂停也不回选曲，这一趟只能打完
	# （真要把游戏关掉也行，但下次打开会回到踏入之前，等于没走过这一步）
	if _first_entry and code == KEY_ESCAPE:
		return

	match state:
		State.PAUSED:
			match code:
				KEY_ESCAPE:
					_resume()
				KEY_Q:
					_quit_run()
		State.RESUME:
			match code:
				KEY_ESCAPE:
					_pause()
				KEY_Q:
					_quit_run()
		State.PLAYING:
			match code:
				KEY_ESCAPE:
					_pause()
				_:
					var zone := _zone_for_key(code)
					if zone != "":
						_on_key_down(code, zone)
		State.COUNTDOWN:
			if code == KEY_ESCAPE:
				_quit_run()


## 退出这一趟：普通谱面回选曲页；新手教程回主界面，并且记下「教程走过了」
func _quit_run() -> void:
	if _tutorial:
		App.finish_tutorial()
		App.goto_menu()
		return
	App.goto_select()


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
			var lane: Dictionary = judge.lanes[int(note["lane"])]
			# 自动演示按音符本身的时刻判定，避免帧率 / 卡顿改变成绩。
			var press_t := float(note["time"])
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
	if state != State.PLAYING and state != State.RESUME:
		return
	# 神秘曲第一次踏入：这一趟不给暂停（Esc 也已经被 _unhandled_input 吃掉）
	if _first_entry:
		return
	_hide_countdown_label()
	_held.clear()
	_rebuild_zones()
	state = State.PAUSED
	if has_audio:
		player.stream_paused = true
	_pause_layer.open()


func _resume() -> void:
	if state != State.PAUSED:
		return
	_pause_layer.close()
	_resume_from = chart_time
	_countdown_elapsed = 0.0
	if _countdown_label != null:
		_countdown_label.show()
	_update_countdown_label(RESUME_LEAD_IN)
	state = State.RESUME


## 从暂停菜单「重开」：同一首重新来一遍，但不要开场倒计时
func _retry() -> void:
	App.retry(true)


func _start_playing_now() -> void:
	_hide_countdown_label()
	_countdown_elapsed = LEAD_IN
	chart_time = -_chart_offset()
	stage.chart_time = chart_time
	stage.queue_redraw()
	if has_audio:
		player.play()
	state = State.PLAYING


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
	# 通关掉落（自动演示不掉）：第 N 首谱面 → 第 N 篇笔记；这一首的曲绘也一并进收藏
	if not autoplay:
		result["story_drop"] = App.grant_story_drop(result)
		result["cover_drop"] = App.grant_cover_drop(result)
	App.last_result = result
	debug_run_result = result
	# 新手教程这一趟：不记成绩、不掉剧情，直接记「教程走过了」然后回主界面
	if _tutorial:
		if not debug_mode:
			App.finish_tutorial()
			App.goto_menu()
		return
	if not autoplay:
		App.record_result(result)          # 个人资料里的游玩次数 / 最高分
		# 这一趟打完了，神秘曲的「第一次踏入」才算真的踏进去（中途强关游戏走不到这里）
		if not debug_mode:
			App.commit_entry(_entry_key())
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
		player.volume_db = _db(settings.music_volume) + float(chart.get("audio", {}).get("volume_db", 0.0))
	if hit_player != null:
		hit_player.volume_db = _db(settings.hit_volume)


func _db(linear: float) -> float:
	return linear_to_db(clampf(linear, 0.0001, 1.0))


# --------------------------------------------------------------------------- #
# 暂停面板（游玩时不显示任何 UI，只有按 Esc 才出来）
# --------------------------------------------------------------------------- #

func _build_pause_layer() -> void:
	_pause_layer = PauseActions.new()
	_pause_layer.name = "PauseLayer"
	UiKit.full_rect(_pause_layer)
	add_child(_pause_layer)
	_pause_layer.action_requested.connect(_on_pause_action)


func _on_pause_action(action: int) -> void:
	if state != State.PAUSED:
		return
	match action:
		0:
			_resume()
		1:
			_retry()
		2:
			_quit_run()


# --------------------------------------------------------------------------- #
# 暂停恢复的 3 秒倒计时（画面正中一个数字）
# --------------------------------------------------------------------------- #

func _build_countdown_label() -> void:
	_countdown_label = Label.new()
	_countdown_label.name = "ResumeCountdown"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 120)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(_countdown_label)
	_countdown_label.hide()
	add_child(_countdown_label)


func _update_countdown_label(remaining: float) -> void:
	if _countdown_label == null:
		return
	var frac := remaining - floorf(remaining)
	_countdown_label.text = str(maxi(1, ceili(remaining)))
	_countdown_label.modulate = Color(1, 1, 1, clampf(0.45 + 0.55 * frac, 0.0, 1.0))


func _hide_countdown_label() -> void:
	if _countdown_label != null:
		_countdown_label.hide()


# --------------------------------------------------------------------------- #
# 给测试 / 其它界面用的小接口
# --------------------------------------------------------------------------- #

func is_autoplay() -> bool:
	return autoplay


func is_chart_playing() -> bool:
	return state == State.PLAYING or state == State.RESUME


func get_judge() -> RhythmJudge:
	return judge


func debug_start_now() -> void:
	_hide_countdown_label()
	_countdown_elapsed = LEAD_IN
	chart_time = -_chart_offset()
	stage.chart_time = chart_time
	state = State.PLAYING


func debug_set_audio_clock(enabled: bool) -> void:
	_use_audio_clock = enabled


func debug_advance(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.RESUME:
			_tick_resume(delta)
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


## 谱面场的故事板图层（文字）：建在 Stage 之后、Post 之前，
## 这样后处理 shader 会把字一起处理，和制谱器里「先画图层再叠 shader」一致。
func _build_story_layers() -> void:
	if _chart_scene.is_empty():
		return
	var layers = _chart_scene.get("layers", [])
	if not (layers is Array) or (layers as Array).is_empty():
		return
	var node := StoryLayers.new()
	node.name = "StoryLayers"
	node.setup(_chart_scene)
	add_child(node)
	if post != null:
		move_child(node, mini(post.get_index(), get_child_count() - 1))
	_story_layers = node


## 每帧把图层的时间推到谱面时间上（暂停 / 结算时时间不走，字也就定格）
func _update_story_layers() -> void:
	if _story_layers == null or not is_instance_valid(_story_layers):
		return
	_story_layers.set_time(chart_time)


# --------------------------------------------------------------------------- #
# 解锁动画（谱面包里导入的视频 -> 烘焙成帧序列）
# --------------------------------------------------------------------------- #

## 这一趟玩的是哪首（谱面 key）。解锁动画 / 神秘曲第一次踏入都按它认人。
func _entry_key() -> String:
	var entry = App.session.get("entry", {})
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str(entry.get("key", ""))


func _build_unlock() -> void:
	# 测试 / 截图 / 无头模式不播，避免每帧推进都要多等 20 秒
	if debug_mode or DisplayServer.get_name() == "headless":
		return
	var entry = App.session.get("entry", {})
	if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
		return
	# 解锁动画每首谱面只演一次（演过就直接进倒计时，不占第二次的进谱时间）；
	# 神秘曲的第一次踏入以「正式踏入」为准，规则在 App.should_play_unlock() 里
	var key := str(entry.get("key", ""))
	if not App.should_play_unlock(key):
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
	# 一般曲子一开场就记下（跳过 / 中途退出也算看过）；
	# 神秘曲第一次踏入这趟不记，等结算时由 App.commit_entry() 和「踏入」一起落盘
	if App.should_mark_unlock_seen(key):
		App.mark_unlock_seen(key)
	# 从选曲页黑过来的：先别播，等黑幕淡出时再起（见 _reveal_from_black）
	if bool(App.session.get("from_black", false)):
		return
	_unlock.start()


## 选曲页「是」→ 慢慢变黑 → 切到这里：先全黑压一下，再淡出去，
## 让黑幕和解锁动画接成一段（没有解锁动画时就淡出到倒计时 / 舞台）。
func _reveal_from_black() -> void:
	if debug_mode:
		return
	var cover := ColorRect.new()
	cover.name = "FromBlack"
	cover.color = Color(0, 0, 0, 1)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)                                # 最后加 = 盖在所有东西上面
	var tween := create_tween()
	# 有解锁动画：黑屏先停 2 秒（??? 那首要求的时长），再让动画从黑里起来；
	# 没有解锁动画：黑场马上就淡，别把 2 秒倒计时也盖掉
	var has_unlock := _unlock != null
	var hold := FROM_BLACK_HOLD_UNLOCK if has_unlock else FROM_BLACK_HOLD_SILENT
	var fade := FROM_BLACK_FADE if has_unlock else FROM_BLACK_FADE_SILENT
	tween.tween_interval(hold)
	# 黑透了才让解锁动画动起来：开头那几帧不会被糊在淡出里
	tween.tween_callback(_start_unlock_after_black)
	tween.tween_property(cover, "color:a", 0.0, fade) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(cover.queue_free)


## 黑幕开始淡出时起播解锁动画（调试里可能已经被 skip_unlock() 拆掉，所以先判有效性）
func _start_unlock_after_black() -> void:
	if _unlock != null and is_instance_valid(_unlock):
		_unlock.start()


func _finish_unlock() -> void:
	if _unlock != null:
		_unlock.queue_free()
		_unlock = null
	if _skip_countdown:
		_skip_countdown = false
		_start_playing_now()
		return
	state = State.COUNTDOWN
	_countdown_elapsed = 0.0
	chart_time = _countdown_from
	stage.chart_time = chart_time


## 调试 / 测试用：跳过解锁动画。
## 正常游玩**不再**从这里跳过——`_unhandled_input` 只把按键吃掉，片子必须整段看完。
func skip_unlock() -> void:
	if state != State.UNLOCK:
		return
	if _unlock != null:
		_unlock.skip()
	else:
		_finish_unlock()
