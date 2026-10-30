extends Node
## 截图脚本：把几个界面渲染成 png，放在 res://tests/_shots/（已在 .gitignore 里）。

const OUT_DIR := "res://tests/_shots"
const SyntheticChart = preload("res://tests/fixtures/synthetic_chart.gd")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await get_tree().process_frame
	await _shot_warning()
	await _shot_splash()
	await _shot_menu()
	await _shot_collection()
	await _shot_profile()
	await _shot_song_select()
	await _shot_settings()
	await _shot_gameplay()
	await _shot_results()
	print("screenshots saved to ", OUT_DIR)
	get_tree().quit(0)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + file_name + ".png")
	print("  ", file_name, ".png  ", img.get_size())


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot_warning() -> void:
	var w = load("res://scenes/warning.tscn").instantiate()
	get_tree().root.add_child(w)
	await _wait_frames(3)
	w._elapsed = 2.6          # 进度条停在中间，截图好看
	await _wait_frames(2)
	w._done = true            # 截图期间别自动跳去开始界面
	await _capture("00_warning")
	w.queue_free()
	await _wait_frames(2)


func _shot_splash() -> void:
	var splash = load("res://scenes/splash.tscn").instantiate()
	get_tree().root.add_child(splash)
	# 等入场动画跑完：淡入 0.5 秒 + 提示文字延迟 0.75 秒 + 淡入 0.35 秒
	await get_tree().create_timer(1.8).timeout
	splash._done = true       # 截图期间别跳去主界面
	await _wait_frames(2)
	await _capture("00a_splash")
	splash.queue_free()
	await _wait_frames(2)


func _shot_menu() -> void:
	# 截图时别让新手教程挡住主界面（只改内存里的标记，不写盘）
	var keep_tutorial: bool = App.settings.tutorial_seen
	App.settings.tutorial_seen = true
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await menu.glow_revealed
	await _wait_frames(2)
	await _capture("00b_main_menu")
	menu.queue_free()
	await _wait_frames(2)
	App.settings.tutorial_seen = keep_tutorial


func _shot_collection() -> void:
	var screen = load("res://scenes/collection.tscn").instantiate()
	get_tree().root.add_child(screen)
	await _wait_frames(5)
	await _capture("00c_collection")
	screen.queue_free()
	await _wait_frames(2)


func _shot_profile() -> void:
	var screen = load("res://scenes/profile.tscn").instantiate()
	get_tree().root.add_child(screen)
	await _wait_frames(5)
	await _capture("00d_profile")
	screen.queue_free()
	await _wait_frames(2)


func _shot_song_select() -> void:
	App.refresh_library()
	var select = load("res://scenes/song_select.tscn").instantiate()
	get_tree().root.add_child(select)
	# 等曲目行的入场弹簧停稳（0.6 秒延迟 + 回弹），否则截到的是滑入半截的画面
	await get_tree().create_timer(2.2).timeout
	await _capture("01_song_select")
	select.queue_free()
	await _wait_frames(2)


func _shot_settings() -> void:
	var screen = load("res://scenes/settings.tscn").instantiate()
	get_tree().root.add_child(screen)
	await _wait_frames(4)
	await _capture("04_settings")
	screen.queue_free()
	await _wait_frames(2)


func _make_session() -> void:
	App.session = {
		"entry": {"key": "test:synthetic", "title": "Synthetic Test"},
		"chart": SyntheticChart.build(),
		"stream": SyntheticChart.stream(),
		"cover": null,
		"warnings": [],
		"errors": [],
	}


func _shot_gameplay() -> void:
	_make_session()
	App.autoplay_once = true

	var game = load("res://scenes/gameplay.tscn").instantiate()
	game.debug_mode = true
	get_tree().root.add_child(game)
	await _wait_frames(2)
	game.set_process(false)
	game.debug_set_audio_clock(false)
	await _wait_frames(1)
	game.debug_start_now()

	var dt := 1.0 / 60.0
	var targets := [2.52, 4.0, 9.2, 11.3, 13.0]
	var names := [
		"02_gameplay_fx", "02b_gameplay", "02c_gameplay_rotate",
		"02d_gameplay_alpha", "02e_gameplay_speed",
	]
	var elapsed := 0.0
	for i in targets.size():
		while elapsed < targets[i]:
			game.debug_advance(dt)
			elapsed += dt
		await _capture(names[i])

	# 没有任何 UI，这里已经是纯渲染画面
	await _capture("02g_stage_only")

	game._pause()
	await _wait_frames(2)
	await _capture("02f_pause")
	game._resume()

	var guard := 0
	while game.state != 3 and guard < 4000:
		game.debug_advance(dt)
		guard += 1
	await _wait_frames(2)
	game.queue_free()
	await _wait_frames(2)
	App.autoplay_once = false


func _shot_results() -> void:
	if App.last_result.is_empty():
		return
	var results = load("res://scenes/results.tscn").instantiate()
	get_tree().root.add_child(results)
	await _wait_frames(4)
	await _capture("03_results")
	results.queue_free()
	await _wait_frames(2)
