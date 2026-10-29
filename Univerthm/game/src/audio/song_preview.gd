extends Node
## 独立试听声源，轻微防抖与交叉淡化；销毁时取消所有待播放请求。

signal status_changed(playing: bool)
const GAIN := 0.5
const FADE_SECONDS := 0.22
var players: Array[AudioStreamPlayer] = []
var active := 0
var current_key := ""
var target_gain := 0.0
var _serial := 0
var _fade: Tween
var _cache := {}
var _playing_key := ""


func _ready() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "PreviewVoice%d" % i
		player.volume_linear = 0.0
		add_child(player)
		player.finished.connect(_on_finished.bind(i))
		players.append(player)


func select(entry: Dictionary) -> void:
	var key := str(entry.get("key", ""))
	if key == current_key:
		return
	current_key = key
	_playing_key = ""
	_serial += 1
	var serial := _serial
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	for voice in players:
		_fade.tween_property(voice, "volume_linear", 0.0, 0.12)
	_fade.chain().tween_callback(_stop_faded_voices)
	status_changed.emit(false)
	await get_tree().create_timer(0.1).timeout
	if serial != _serial or not is_inside_tree():
		return
	var stream: AudioStream = _cache.get(key)
	if stream == null:
		stream = ChartSource.load_audio(entry)
		if stream != null:
			# 仅缓存相邻两首，避免大型曲库累积占用音频内存。
			if _cache.size() >= 2:
				_cache.erase(_cache.keys()[0])
			_cache[key] = stream
	if stream == null or stream.get_length() <= 0.01:
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var previous := active
	active = 1 - active
	players[active].stop()
	players[active].stream = stream
	players[active].volume_linear = 0.0
	var chart: Dictionary = entry.get("chart", {})
	target_gain = clampf(App.settings.music_volume, 0.0, 1.0) * GAIN * db_to_linear(float(chart.get("audio", {}).get("volume_db", 0.0)))
	players[active].play()
	_playing_key = key
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(players[active], "volume_linear", target_gain, FADE_SECONDS)
	_fade.tween_property(players[previous], "volume_linear", 0.0, FADE_SECONDS)
	_fade.chain().tween_callback(players[previous].stop)
	status_changed.emit(true)


func _on_finished(index: int) -> void:
	if index == active and current_key != "" and current_key == _playing_key:
		players[index].play()


func _stop_faded_voices() -> void:
	for voice in players:
		voice.stop()


func stop() -> void:
	_serial += 1
	current_key = ""
	_playing_key = ""
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for voice in players:
		voice.stop()
		voice.stream = null
		voice.volume_linear = 0.0
	status_changed.emit(false)


func _exit_tree() -> void:
	stop()
