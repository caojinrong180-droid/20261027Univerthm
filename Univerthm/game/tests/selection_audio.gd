extends SceneTree
## 试听音量、快速切歌、无音频与离开清理；用隔离的 APPDATA 运行。

const Synthetic = preload("res://tests/fixtures/synthetic_chart.gd")
var passed := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(message)


func _run() -> void:
	await process_frame
	var app := root.get_node("App")
	var original_volume: float = app.settings.music_volume
	app.settings.music_volume = 0.72
	var directory := "user://tests/selection-audio-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var tone: AudioStreamWAV = Synthetic.stream()
	var data := tone.data
	var original_data := data.duplicate()
	while data.size() < tone.mix_rate * 3 * (4 if tone.stereo else 2):
		data.append_array(original_data)
	tone.data = data
	check(tone.save_to_wav(directory.path_join("tone.wav")) == OK, "write disposable tone")
	var chart := Synthetic.build()
	chart["audio"] = {"file": "tone.wav", "volume_db": -4.0}
	var file := FileAccess.open(directory.path_join("chart.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(chart))
	file.close()
	var entries := ChartSource.scan([directory])
	check(entries.size() == 1, "discover disposable audio fixture")
	if entries.is_empty():
		quit(1)
		return
	var entry: Dictionary = entries[0]
	check(ChartSource.load_audio(entry) != null, "lightweight loose audio loader")
	var preview = load("res://src/audio/song_preview.gd").new()
	root.add_child(preview)
	preview.select(entry)
	await create_timer(0.5).timeout
	var expected := 0.72 * 0.5 * db_to_linear(-4.0)
	check(preview.players[preview.active].playing, "selected track starts playback")
	check(absf(preview.players[preview.active].volume_linear - expected) < 0.001, "exact half of normal gain including chart dB")
	var position: float = preview.players[preview.active].get_playback_position()
	preview.select(entry)
	await create_timer(0.1).timeout
	check(preview.players[preview.active].get_playback_position() >= position, "same selection does not restart audio")
	var second := entry.duplicate(true)
	second["key"] = "second"
	second["chart"]["audio"]["volume_db"] = -1.0
	var third := entry.duplicate(true)
	third["key"] = "third"
	third["chart"]["audio"]["volume_db"] = -12.0
	preview.select(second)
	await create_timer(0.03).timeout
	preview.select(third)
	await create_timer(0.5).timeout
	check(preview.current_key == "third", "rapid selection keeps newest request")
	check(absf(preview.players[preview.active].volume_linear - 0.36 * db_to_linear(-12.0)) < 0.001, "stale request cannot replace latest gain")
	var other: int = 1 - preview.active
	check(not preview.players[other].playing, "crossfade stops outgoing voice")
	var missing := entry.duplicate(true)
	missing["key"] = "missing"
	missing["audio_file"] = "missing.wav"
	preview.select(missing)
	await create_timer(0.4).timeout
	for voice in preview.players:
		check(not voice.playing, "missing audio stops old song")
	app.settings.music_volume = 0.0
	preview.select(entry)
	await create_timer(0.5).timeout
	check(is_zero_approx(preview.players[preview.active].volume_linear), "zero music volume remains silent")
	preview.select(second)
	preview.stop()
	await create_timer(0.4).timeout
	for voice in preview.players:
		check(not voice.playing and voice.stream == null, "stop cancels pending playback and releases stream")
	preview.queue_free()
	await process_frame
	app.settings.music_volume = original_volume
	DirAccess.remove_absolute(directory.path_join("tone.wav"))
	DirAccess.remove_absolute(directory.path_join("chart.json"))
	DirAccess.remove_absolute(directory)
	print("Selection audio: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
