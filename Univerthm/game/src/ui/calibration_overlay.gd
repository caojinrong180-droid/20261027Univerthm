class_name CalibrationOverlay
extends Control
## 音画偏移的「辅助测量」浮窗（设置页那一行旁边的小按钮打开）。
##
## 一块铺满屏幕的暗底 + 居中、不可拖动的面板；点面板中间的「开始」之后跑节拍器：
## 每小节四下、三轻一重，玩家在**重音落下的瞬间**按 F。
## 量的是「重音真正播出去的时刻 → 按键」的间隔，包含声卡 / 蓝牙的延迟和人的反应，
## 打满 5 次取平均，点「应用」直接写进 settings.audio_offset_ms。
##
## 方向：按晚了 = 声音比画面到得晚 = 谱面要整体推后 = 正数，
## 和设置页「正数会将谱面整体推后」一个字都不差，所以平均值原样写进去。

signal applied(value_ms: float)
signal closed

enum State { IDLE, RUNNING, DONE }

## 一拍 0.6 秒（100 BPM），一小节 4 拍 = 2.4 秒
const BEAT_USEC := 600000
## 三轻一重：每 4 拍一个重音，落在小节的第 4 拍上
const ACCENT_EVERY := 4
## 开始后先空一小节，让玩家跟上拍子
const LEAD_IN_BEATS := 4
const SAMPLES_NEEDED := 5
## 离重音 ±300 ms 之外的按键不算（早按 / 晚按都收，就是别乱按）
const WINDOW_USEC := 300000
const WINDOW_MS := 300.0
## 重音已经到点、这一帧还没播出去时，按键仍然算给它
const FRAME_SLACK_USEC := 60000
## 一直不打点就自己停，别把节拍器开着不管
const GIVE_UP_SECONDS := 45.0

const LIGHT_DB := -3.0
const ACCENT_DB := 0.0

const DOT_IDLE := Color("2a1145")
const DOT_LIGHT := Color("4c2180")
const DOT_ACCENT := Color("b06bff")

const KEYS := [KEY_F]

const HINT := "在重音时按下F"

var _state := State.IDLE
var _beat_index := 0
var _next_beat_usec := 0
var _deadline_usec := 0
## 已经播出、还没被用掉的重音时刻（0 = 没有）
var _last_accent_usec := 0
## 早按留下的按键时刻，等重音真的播出来再结算
var _pending_press_usec := 0
var _samples: Array[float] = []

var _panel: NeonPanel
var _dot: PanelContainer
var _dot_style: StyleBoxFlat
var _dot_label: Label
var _status: Label
var _toast: Label
var _average_value: Label
var _chips: Array[Label] = []
var _start_button: Button
var _apply_button: Button
var _toast_timer: Timer
var _apply_timer: Timer
var _dot_tween: Tween

var _light_player: AudioStreamPlayer
var _accent_player: AudioStreamPlayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(self)
	_build()
	_build_players()
	hide()
	set_process(false)


# --------------------------------------------------------------------------- #
# 开关
# --------------------------------------------------------------------------- #

func open() -> void:
	_reset_round()
	show()
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_start_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	_stop_round()
	hide()
	closed.emit()


func _reset_round() -> void:
	_stop_round()
	_samples.clear()
	_update_samples()
	_dot_label.text = "—"
	_reset_dot()
	_say("点下面的「开始」，跟着节拍打点")
	_toast.text = ""
	_start_button.text = "开始"
	_enable(_start_button, true)
	_apply_button.text = "应用到偏移"
	_enable(_apply_button, false)


## 状态行：空字符串就把整行收掉，免得留一块空白
func _say(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_status.visible = text != ""


## 停用的按钮也压暗，不然主按钮排的紫色看起来还能点
func _enable(button: Button, enabled: bool) -> void:
	if button == null:
		return
	button.disabled = not enabled
	button.modulate = Color(1, 1, 1, 1.0 if enabled else 0.34)


func _stop_round() -> void:
	_state = State.IDLE
	set_process(false)
	_pending_press_usec = 0
	_last_accent_usec = 0


# --------------------------------------------------------------------------- #
# 节拍器
# --------------------------------------------------------------------------- #

func _process(_delta: float) -> void:
	if _state != State.RUNNING:
		return
	var now := Time.get_ticks_usec()
	if now > _deadline_usec:
		_stop_round()
		_start_button.text = "重新测量"
		_enable(_start_button, true)
		_say("一直没等到打点，点「重新测量」再来一次")
		return
	while _state == State.RUNNING and now >= _next_beat_usec:
		_play_beat(_beat_index)
		_beat_index += 1
		_next_beat_usec += BEAT_USEC


func _is_accent(index: int) -> bool:
	if index < LEAD_IN_BEATS:
		return false
	return (index - LEAD_IN_BEATS) % ACCENT_EVERY == ACCENT_EVERY - 1


func _bar_position(index: int) -> int:
	return (index - LEAD_IN_BEATS) % ACCENT_EVERY + 1


## 下一个重音预计播出的时刻（按节拍表的排程算，只用来判断"早按"）
func _next_accent_usec() -> int:
	if _state != State.RUNNING:
		return 0
	for step in ACCENT_EVERY * 2:
		if _is_accent(_beat_index + step):
			return _next_beat_usec + step * BEAT_USEC
	return 0


func _play_beat(index: int) -> void:
	var accent := _is_accent(index)
	var emit_usec := Time.get_ticks_usec()
	if accent:
		if _accent_player != null:
			_accent_player.play()
	else:
		if _light_player != null:
			_light_player.play()
	_flash(index, accent)
	if not accent:
		return
	if _pending_press_usec > 0:
		var press := _pending_press_usec
		_pending_press_usec = 0
		_last_accent_usec = 0
		_record(float(press - emit_usec) / 1000.0)
	else:
		_last_accent_usec = emit_usec


# --------------------------------------------------------------------------- #
# 输入：只认 F，浮窗开着时其它键也不往下传
# --------------------------------------------------------------------------- #

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if key.keycode == KEY_F11:
		return                                   # 全屏交给 App 自己处理
	get_viewport().set_input_as_handled()
	if key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		close()
		return
	if _state != State.RUNNING or not KEYS.has(key.keycode):
		return
	_on_press(Time.get_ticks_usec())


func _on_press(press_usec: int) -> void:
	if _pending_press_usec > 0:
		return                                   # 已经拍了一下在等重音
	if _last_accent_usec > 0:                    # 晚按：算给刚播出的那个重音
		var late := press_usec - _last_accent_usec
		if late >= 0 and late <= WINDOW_USEC:
			_last_accent_usec = 0
			_record(float(late) / 1000.0)
			return
	var next := _next_accent_usec()               # 早按：留给下一个重音
	if next > 0 and press_usec <= next + FRAME_SLACK_USEC:
		if next - press_usec <= WINDOW_USEC:
			_pending_press_usec = press_usec
			return
	_toast_hint("这一下不是重音，等重音落下再按")


func _record(delta_ms: float) -> void:
	if absf(delta_ms) > WINDOW_MS:
		return
	_samples.append(delta_ms)
	_update_samples()
	if _samples.size() >= SAMPLES_NEEDED:
		_finish()
		return
	_say("第 %d / %d 次  %s" % [_samples.size() + 1, SAMPLES_NEEDED, _fmt(delta_ms)])


func _finish() -> void:
	_state = State.DONE
	set_process(false)
	_last_accent_usec = 0
	_pending_press_usec = 0
	var average := _average_ms()
	_dot_label.text = "OK"
	_reset_dot()
	_say("")
	_start_button.text = "重新测量"
	_enable(_start_button, true)
	_apply_button.text = "应用到偏移 %s" % _fmt(average)
	_enable(_apply_button, true)


func _average_ms() -> float:
	if _samples.is_empty():
		return 0.0
	var total := 0.0
	for value in _samples:
		total += value
	return total / float(_samples.size())


func _fmt(value: float) -> String:
	return "%+d ms" % int(round(value))


# --------------------------------------------------------------------------- #
# 按钮回调
# --------------------------------------------------------------------------- #

func _on_start_pressed() -> void:
	if _state == State.RUNNING:
		return
	_samples.clear()
	_update_samples()
	_beat_index = 0
	_pending_press_usec = 0
	_last_accent_usec = 0
	_state = State.RUNNING
	_deadline_usec = Time.get_ticks_usec() + int(GIVE_UP_SECONDS * 1000000.0)
	_next_beat_usec = Time.get_ticks_usec() + BEAT_USEC
	_dot_label.text = "—"
	_reset_dot()
	_toast.text = ""
	_say("跟着拍子，重音落下时打一下")
	_start_button.text = "测量中…"
	_enable(_start_button, false)
	_apply_button.text = "应用到偏移"
	_enable(_apply_button, false)
	set_process(true)


func _on_apply() -> void:
	if _samples.size() < SAMPLES_NEEDED:
		return
	var average := _average_ms()
	applied.emit(average)
	_state = State.DONE
	_enable(_apply_button, false)
	_enable(_start_button, false)
	_say("已写入音画偏移：%s" % _fmt(average))
	if _apply_timer != null:
		_apply_timer.start(0.7)


func _toast_hint(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	if _toast_timer != null:
		_toast_timer.start(1.4)


func _on_toast_timeout() -> void:
	if _toast != null:
		_toast.text = ""


# --------------------------------------------------------------------------- #
# 节拍音（自己合成，不读现成的 wav）
# --------------------------------------------------------------------------- #

func _build_players() -> void:
	# 轻拍：偏高、偏短、偏轻；重音：低八度附近、更长、更实
	_light_player = _make_player("LightPlayer", _make_click(1720.0, 1290.0, 0.075, 58.0, 0.20), LIGHT_DB)
	_accent_player = _make_player("AccentPlayer", _make_click(980.0, 640.0, 0.14, 26.0, 0.38), ACCENT_DB)


func _make_player(player_name: String, stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.volume_db = volume_db
	player.stream = stream
	add_child(player)
	return player


## 一小段 16 位单声道 PCM：正弦 + 二次 / 三次谐波，头 2 ms 起音防爆音，
## 频率从 start_hz 滑到 end_hz 做「木鱼」那种一敲就收的手感，尾巴再线性收到 0。
func _make_click(start_hz: float, end_hz: float, seconds: float, decay: float, peak: float) -> AudioStreamWAV:
	const RATE := 44100
	const ATTACK := 0.0018
	const TAIL := 0.12
	var frames := maxi(8, int(RATE * seconds))
	var data := PackedByteArray()
	data.resize(frames * 2)
	var dt := 1.0 / float(RATE)
	var phase := 0.0
	for index in frames:
		var t := float(index) * dt
		var progress := t / seconds
		var glide := minf(1.0, progress / 0.45)
		phase += TAU * lerpf(start_hz, end_hz, glide) * dt
		var envelope := exp(-decay * t) * minf(1.0, t / ATTACK)
		envelope *= minf(1.0, (1.0 - progress) / TAIL)
		var tone := sin(phase) + 0.28 * sin(phase * 2.0) + 0.09 * sin(phase * 3.0)
		data.encode_s16(index * 2, int(clampf(tone * envelope * peak, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream


# --------------------------------------------------------------------------- #
# 界面
# --------------------------------------------------------------------------- #

func _build() -> void:
	var shade := ColorRect.new()
	shade.name = "DimShade"
	shade.color = Color(0.008, 0.004, 0.018, 0.86)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(shade)
	add_child(shade)

	var centerer := CenterContainer.new()
	centerer.name = "Center"
	centerer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(centerer)
	add_child(centerer)

	_panel = NeonPanel.new()
	_panel.name = "CalibrationPanel"
	_panel.fill = Color(0.028, 0.016, 0.058, 0.97)
	_panel.edge = Color("c49bff")
	_panel.cut = 26
	_panel.glow = true
	_panel.custom_minimum_size = Vector2(720, 0)
	centerer.add_child(_panel)

	var column := UiKit.vbox(9)
	_panel.add_child(UiKit.margin(column, 34, 24, 34, 22))

	var head := UiKit.hbox(12)
	column.add_child(head)
	head.add_child(NeonUi.label("节拍校准", 30, NeonUi.LIGHT, true))
	head.add_child(NeonUi.label("///", 18, NeonUi.PURPLE, true))
	head.add_child(UiKit.stretch())
	head.add_child(NeonUi.label("CALIBRATION", 11, NeonUi.MUTED))
	var close_button := NeonUi.button("×", false, 17)
	close_button.name = "CloseButton"
	close_button.custom_minimum_size = Vector2(42, 32)
	close_button.pressed.connect(close)
	head.add_child(close_button)

	column.add_child(UiKit.rule(Color("8342cf")))
	var hint := NeonUi.label(HINT, 12, NeonUi.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 18)
	column.add_child(hint)

	var stage := UiKit.vbox(8)
	stage.custom_minimum_size = Vector2(0, 250)
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(stage)

	var dot_row := UiKit.hbox(0)
	dot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dot_row.add_child(_build_dot())
	stage.add_child(dot_row)

	_status = NeonUi.label("点下面的「开始」，跟着节拍打点", 15, NeonUi.LIGHT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(_status)

	var samples := UiKit.hbox(8)
	samples.alignment = BoxContainer.ALIGNMENT_CENTER
	for index in SAMPLES_NEEDED:
		samples.add_child(_build_chip(index))
	stage.add_child(samples)

	var average_row := UiKit.hbox(10)
	average_row.alignment = BoxContainer.ALIGNMENT_CENTER
	average_row.add_child(NeonUi.label("平均", 12, NeonUi.MUTED))
	_average_value = UiKit.mono_label("—", 20, NeonUi.LIGHT)
	average_row.add_child(_average_value)
	stage.add_child(average_row)

	var start_row := UiKit.hbox(0)
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_start_button = NeonUi.button("开始", true, 18)
	_start_button.name = "StartButton"
	_start_button.custom_minimum_size = Vector2(164, 46)
	_start_button.pressed.connect(_on_start_pressed)
	start_row.add_child(_start_button)
	stage.add_child(start_row)

	_toast = NeonUi.label("", 12, NeonUi.PURPLE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.custom_minimum_size = Vector2(0, 16)
	column.add_child(_toast)

	column.add_child(UiKit.rule(Color("4b2a70")))
	var actions := UiKit.hbox(12)
	column.add_child(actions)
	var footer_close := NeonUi.button("关闭（Esc）", false, 14)
	footer_close.name = "FooterCloseButton"
	footer_close.custom_minimum_size = Vector2(136, 42)
	footer_close.pressed.connect(close)
	actions.add_child(footer_close)
	actions.add_child(UiKit.stretch())
	_apply_button = NeonUi.button("应用到偏移", true, 15)
	_apply_button.name = "ApplyButton"
	_apply_button.custom_minimum_size = Vector2(212, 44)
	_apply_button.disabled = true
	_apply_button.pressed.connect(_on_apply)
	actions.add_child(_apply_button)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	add_child(_toast_timer)
	_toast_timer.timeout.connect(_on_toast_timeout)

	_apply_timer = Timer.new()
	_apply_timer.one_shot = true
	add_child(_apply_timer)
	_apply_timer.timeout.connect(close)


func _build_dot() -> Control:
	_dot = PanelContainer.new()
	_dot.name = "BeatDot"
	_dot.custom_minimum_size = Vector2(112, 112)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot_style = UiTheme.style_box(DOT_IDLE, 56, 2, Color("8f5ad0"), Vector4(0, 0, 0, 0))
	_dot.add_theme_stylebox_override("panel", _dot_style)
	_dot.resized.connect(_sync_dot_pivot)
	_dot_label = UiKit.mono_label("—", 30, NeonUi.LIGHT)
	_dot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dot.add_child(_dot_label)
	return _dot


func _build_chip(index: int) -> Control:
	var chip := PanelContainer.new()
	chip.name = "Sample%d" % (index + 1)
	chip.custom_minimum_size = Vector2(96, 30)
	chip.add_theme_stylebox_override("panel",
		UiTheme.style_box(Color(0.055, 0.03, 0.1, 0.92), 5, 1, Color("5c3f86"), Vector4(10, 3, 10, 3)))
	var value := UiKit.mono_label("—", 14, NeonUi.MUTED)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(value)
	_chips.append(value)
	return chip


func _sync_dot_pivot() -> void:
	if _dot != null:
		_dot.pivot_offset = _dot.size * 0.5


## 让圆点回到静止状态（停掉正在跑的闪烁）
func _reset_dot() -> void:
	if _dot_tween != null and _dot_tween.is_valid():
		_dot_tween.kill()
	if _dot != null:
		_dot.scale = Vector2.ONE
	if _dot_style != null:
		_dot_style.bg_color = DOT_IDLE


## 每拍闪一下：重音更亮更大，轻拍只是一点小呼吸
func _flash(index: int, accent: bool) -> void:
	_dot_label.text = str(_bar_position(index)) if index >= LEAD_IN_BEATS else "—"
	_dot_style.bg_color = DOT_ACCENT if accent else DOT_LIGHT
	if _dot_tween != null and _dot_tween.is_valid():
		_dot_tween.kill()
	_dot.pivot_offset = _dot.size * 0.5
	_dot.scale = Vector2.ONE * (1.14 if accent else 1.05)
	_dot_tween = create_tween()
	_dot_tween.set_parallel(true)
	_dot_tween.tween_property(_dot, "scale", Vector2.ONE, 0.2)
	_dot_tween.tween_property(_dot_style, "bg_color", DOT_IDLE, 0.25)


func _update_samples() -> void:
	for index in _chips.size():
		if index < _samples.size():
			_chips[index].text = _fmt(_samples[index])
			_chips[index].add_theme_color_override("font_color", NeonUi.LIGHT)
		else:
			_chips[index].text = "—"
			_chips[index].add_theme_color_override("font_color", NeonUi.MUTED)
	_average_value.text = "—" if _samples.is_empty() else _fmt(_average_ms())
