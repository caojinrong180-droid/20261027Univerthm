extends Node
## 真切换界面并采样音频混响：godot --headless --path game res://tests/menu_music.tscn

const Music = preload("res://src/audio/menu_music.gd")

var passed := 0
var failed := 0


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", message)


func _ready() -> void:
	await get_tree().process_frame
	# 音频测试采样菜单总线，主输出静音，避免测试时向扬声器播放。
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(20.0).timeout.connect(func():
		push_error("Menu music tests timed out")
		get_tree().quit(1))
	# 测试驱动留在 root，后续真正替换 current_scene，验证播放器跨场景存活。
	get_tree().current_scene = null
	await _run()
	print("\nMenu music: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


func _run() -> void:
	var music: Music = App.menu_music
	var original_volume := App.settings.music_volume
	check(music.phase == Music.Phase.STOPPED, "进入主界面之前不播放音乐")
	App.goto_menu()
	await get_tree().scene_changed
	var player_id := music.player.get_instance_id()
	check(music.player.playing, "首次进入主界面启动 Difusion")
	check(music.phase == Music.Phase.FADING_IN, "主界面从静音淡入")
	check(music.player.volume_linear < 0.05, "淡入起点接近静音")
	check(music.player.stream is AudioStreamMP3 and music.player.stream.loop, "MP3 开启循环")
	check(is_zero_approx(music.player.stream.loop_offset), "整首从头循环")
	var initial_fade := music._transition
	App.goto_settings()
	await get_tree().scene_changed
	check(music._transition == initial_fade and music.phase == Music.Phase.FADING_IN, "淡入期间打开设置仍连续完成同一段淡入")
	App.back_from_settings()
	await get_tree().scene_changed
	check(music._transition == initial_fade, "淡入期间返回主界面不重新计时")
	music._transition.custom_step(Music.FADE_IN_SECONDS + 0.01)
	check(music.phase == Music.Phase.PLAYING, "淡入正常完成")
	check(is_equal_approx(music.player.volume_linear, 1.0), "淡入到完整声源音量")
	check(is_zero_approx(music.reverb.wet), "正常菜单播放保留原曲声音")

	# 真跨过文件尾部，确认循环不会停在结尾。
	music.player.seek(music.player.stream.get_length() - 0.04)
	var looped := false
	for attempt in 40:
		await get_tree().create_timer(0.05).timeout
		if music.player.get_stream_playback().get_loop_count() > 0:
			looped = true
			break
	check(music.player.playing, "播放到文件末尾后仍继续播放")
	check(looped and music.player.get_playback_position() < 1.0, "到结尾后自动回到歌曲开头")
	music.player.seek(12.0)
	await get_tree().create_timer(0.1).timeout
	var transition := music._transition
	App.goto_settings()
	await get_tree().scene_changed
	check(music.player.get_instance_id() == player_id, "设置页面使用同一个播放器")
	check(music.player.get_playback_position() >= 11.9, "进入设置不从头播放")
	check(music._transition == transition and music.phase == Music.Phase.PLAYING, "进入设置不重新淡入或淡出")

	var settings_screen := get_tree().current_scene
	settings_screen._step_music(-1)
	var bus_index := AudioServer.get_bus_index(music.bus_name)
	var expected_db := Music.BASE_VOLUME_DB + linear_to_db(App.settings.music_volume)
	check(absf(AudioServer.get_bus_volume_db(bus_index) - expected_db) < 0.01, "设置音乐音量立即作用于主界面音乐")
	App.back_from_settings()
	await get_tree().scene_changed
	check(music.player.get_instance_id() == player_id and music.player.get_playback_position() >= 11.9, "从设置返回主界面连续播放")
	check(music.phase == Music.Phase.PLAYING, "从设置返回不重复淡入")

	# 使用主界面的真实按钮，确认淡出发生在进入选曲时。
	get_tree().current_scene.get_node("StartButton").pressed.emit()
	await get_tree().scene_changed
	check(get_tree().current_scene.scene_file_path == App.SELECT_SCENE, "开始游戏按钮进入选曲")
	check(music.phase == Music.Phase.FADING_OUT and music.player.playing, "点开始游戏后淡出声源")
	music._transition.custom_step(0.3)
	check(music.player.volume_linear > 0.0 and music.player.volume_linear < 1.0, "淡出过程中平滑降低音量")
	var exiting := music._transition
	music.fade_out()
	check(music._transition == exiting, "重复离场请求不重置淡出")

	# 正在淡出时快速回主界面，旧的停止回调不能截断新一轮播放。
	App.goto_menu()
	await get_tree().scene_changed
	check(music.player.get_instance_id() == player_id and music.player.get_playback_position() >= 11.9, "快速返回保留同一声源和播放位置")
	music._transition.custom_step(Music.FADE_IN_SECONDS + Music.TAIL_SECONDS + 1.0)
	check(music.phase == Music.Phase.PLAYING and music.player.playing, "取消的离场回调不会停止音乐")

	# 实际采样：停止声源之后仍然有混响输出，尾音结束后回到静音。
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.5
	var capture_slot := AudioServer.get_bus_effect_count(bus_index)
	AudioServer.add_bus_effect(bus_index, capture)
	music.player.seek(25.0)
	await get_tree().create_timer(0.25).timeout
	get_tree().current_scene.get_node("StartButton").pressed.emit()
	await get_tree().scene_changed
	await get_tree().create_timer(Music.FADE_OUT_SECONDS + 0.15).timeout
	check(not music.player.playing and music.phase == Music.Phase.TAIL, "声源淡出后停止，进入独立尾音阶段")
	check(not AudioServer.is_bus_mute(bus_index) and AudioServer.is_bus_effect_enabled(bus_index, 0), "保留混响总线和效果处理")
	capture.clear_buffer()
	await get_tree().create_timer(0.2).timeout
	var tail := capture.get_buffer(capture.get_frames_available())
	var tail_rms := _rms(tail)
	print("  Tail capture: %d frames, RMS %.8f" % [tail.size(), tail_rms])
	check(tail.size() > 0 and tail_rms > 0.00001, "声源停止后采样到真实的混响尾音")
	await get_tree().create_timer(Music.TAIL_SECONDS + 0.2).timeout
	check(music.phase == Music.Phase.STOPPED and not music.player.playing, "尾音之后保持停止")
	capture.clear_buffer()
	await get_tree().create_timer(0.15).timeout
	var silence := capture.get_buffer(capture.get_frames_available())
	check(_rms(silence) < 0.00001, "尾音结束后无残余音乐")
	AudioServer.remove_bus_effect(bus_index, capture_slot)

	App.settings.music_volume = 0.0
	App.refresh_music_volume()
	check(AudioServer.is_bus_mute(bus_index), "音乐音量为零时混响尾音也静音")
	App.settings.music_volume = original_volume
	App.refresh_music_volume()
	App.settings.save()


func _rms(frames: PackedVector2Array) -> float:
	if frames.is_empty():
		return 0.0
	var energy := 0.0
	for frame in frames:
		energy += frame.length_squared()
	return sqrt(energy / float(frames.size() * 2))
