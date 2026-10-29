extends Node
## 跨界面播放的主菜单音乐。只衰减声源，独立混响总线保留离场尾音。

enum Phase { STOPPED, FADING_IN, PLAYING, FADING_OUT, TAIL }

const MUSIC_PATH := "res://audio/difusion.mp3"
const BASE_VOLUME_DB := -9.0
const FADE_IN_SECONDS := 1.5
const FADE_OUT_SECONDS := 0.9
const TAIL_SECONDS := 3.0
const TAIL_FADE_SECONDS := 1.0
const EXIT_WET := 0.5

var phase := Phase.STOPPED
var player: AudioStreamPlayer
var reverb: AudioEffectReverb
var bus_name := "MenuMusic"
var _transition: Tween
var _owns_bus := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_bus()
	player = AudioStreamPlayer.new()
	player.name = "Difusion"
	player.bus = bus_name
	player.volume_linear = 0.0
	var source := load(MUSIC_PATH) as AudioStreamMP3
	if source != null:
		var music := source.duplicate() as AudioStreamMP3
		music.loop = true
		music.loop_offset = 0.0
		player.stream = music
	else:
		push_warning("主界面音乐无法载入：" + MUSIC_PATH)
	add_child(player)


func _create_bus() -> void:
	var suffix := 1
	while AudioServer.get_bus_index(bus_name) >= 0:
		bus_name = "MenuMusic%d" % suffix
		suffix += 1
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, BASE_VOLUME_DB)
	reverb = AudioEffectReverb.new()
	reverb.room_size = 0.82
	reverb.damping = 0.5
	reverb.spread = 1.0
	reverb.predelay_msec = 45.0
	reverb.predelay_feedback = 0.2
	reverb.dry = 1.0
	reverb.wet = 0.0
	AudioServer.add_bus_effect(index, reverb)
	_owns_bus = true


func set_music_volume(value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var gain := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, gain <= 0.0)
	AudioServer.set_bus_volume_db(index, BASE_VOLUME_DB + linear_to_db(maxf(gain, 0.0001)))


func enter_menu() -> void:
	if player == null or player.stream == null:
		return
	if phase == Phase.PLAYING or phase == Phase.FADING_IN:
		return
	_cancel_transition()
	if not player.playing:
		player.volume_linear = 0.0
		player.play()
	phase = Phase.FADING_IN
	_transition = create_tween().set_parallel(true)
	_transition.tween_property(player, "volume_linear", 1.0, FADE_IN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_property(reverb, "wet", 0.0, 0.25)
	_transition.chain().tween_callback(_finish_fade_in)


func fade_out() -> void:
	if phase == Phase.STOPPED or phase == Phase.FADING_OUT or phase == Phase.TAIL:
		return
	_cancel_transition()
	phase = Phase.FADING_OUT
	_transition = create_tween().set_parallel(true)
	_transition.tween_property(player, "volume_linear", 0.0, FADE_OUT_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_property(reverb, "wet", EXIT_WET, 0.25)
	_transition.chain().tween_callback(_begin_tail)
	_transition.chain().tween_interval(TAIL_SECONDS - TAIL_FADE_SECONDS)
	_transition.chain().tween_property(reverb, "wet", 0.0, TAIL_FADE_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.chain().tween_callback(_finish_tail)


func _finish_fade_in() -> void:
	phase = Phase.PLAYING


func _begin_tail() -> void:
	player.stop()
	phase = Phase.TAIL
	# 此处不能静音、删除总线或禁用混响，否则缓存里的尾音会被截断。


func _finish_tail() -> void:
	reverb.wet = 0.0
	phase = Phase.STOPPED


func _cancel_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


func _exit_tree() -> void:
	_cancel_transition()
	if player != null:
		player.stop()
	if _owns_bus:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.remove_bus(index)
