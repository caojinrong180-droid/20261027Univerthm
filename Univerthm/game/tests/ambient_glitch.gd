extends SceneTree
## godot --headless --path game --script res://tests/ambient_glitch.gd

const Synthetic = preload("res://tests/fixtures/synthetic_chart.gd")
var passed := 0
var failed := 0
var app: Node
var overlay: CanvasLayer
var _capture_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", message)


func _run() -> void:
	await process_frame
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1280, 720)
	create_timer(30.0).timeout.connect(func():
		push_error("Ambient glitch tests timed out")
		quit(1))
	var args := OS.get_cmdline_user_args()
	var capture_arg := args.find("--capture-dir")
	if capture_arg >= 0 and capture_arg + 1 < args.size():
		_capture_dir = args[capture_arg + 1]
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	app = root.get_node("App")
	overlay = app.screen_glitch
	check(overlay != null, "全局故障层已创建")
	if overlay == null:
		quit(1)
		return
	for path in [app.WARNING_SCENE, app.SELECT_SCENE, app.SETTINGS_SCENE, app.COLLECTION_SCENE, app.PROFILE_SCENE]:
		var screen := await _visit(path)
		check(overlay.effect.is_processing(), "非播放界面启用周期故障：" + path)
		_check_idle(path)
		await _capture(screen.name + "_idle")
		_begin_burst(path)
		await _capture(screen.name + "_burst")
		_finish_burst(path)
		if path == app.COLLECTION_SCENE and not screen._cards.is_empty():
			screen._open_preview(screen._cards[0])
			_begin_burst("收藏品全屏预览")
			await _capture("CollectionPreview_burst")
			_key(KEY_ESCAPE)
			check(current_scene == screen and not screen._overlay.visible, "故障期间 Esc 仍能关闭收藏品预览")
			_finish_burst("收藏品全屏预览")

	var select := await _visit(app.SELECT_SCENE)
	_begin_burst("选曲返回按钮")
	_click(select.find_child("BackButton", true, false))
	await scene_changed
	check(current_scene.scene_file_path == app.MENU_SCENE, "故障层不拦截返回按钮点击")
	_check_disabled("主界面不叠加第二层故障")
	var menu := current_scene
	await menu.entrance_finished
	var local: MenuGlitch = menu.get_node("AmbientGlitch")
	check(is_equal_approx(local.min_interval, 1.2) and is_equal_approx(local.max_interval, 2.6), "主界面故障间隔减半")
	check(local.is_processing(), "主界面入场后启动自己的故障")
	local._wait_remaining = 0.0
	local._process(0.001)
	local.set_process(false)
	local._process(0.04)
	check(local.visible and local.material.get_shader_parameter("protected_rect").z > 0.0, "主界面保留立绘面部保护")
	await _capture("MainMenu_burst")

	for autoplay in [false, true]:
		app.session = {"chart": Synthetic.build(), "stream": null, "cover": null, "entry": {"key": "test:synthetic"}}
		app.autoplay_once = autoplay
		var game := await _visit(app.GAMEPLAY_SCENE)
		game.debug_mode = true
		game.set_process(false)
		check(overlay.effect.is_processing(), "倒计时允许故障")
		_begin_burst("倒计时")
		game._tick_countdown(game.LEAD_IN)
		check(game.is_chart_playing(), "倒计时进入实际谱面播放")
		_check_disabled("实际播放立即关闭故障，自动演示：%s" % autoplay)
		await process_frame
		_check_disabled("播放中持续关闭故障")
		await _capture("Playing_%s" % autoplay)
		_key(KEY_ESCAPE)
		check(game.state == game.State.PAUSED and game._pause_layer.visible, "Esc 打开暂停界面")
		check(overlay.effect.is_processing(), "暂停时恢复周期故障")
		await create_timer(0.35).timeout
		_begin_burst("暂停界面")
		await _capture("Paused_%s_burst" % autoplay)
		_click(game._pause_layer.buttons[0])
		await create_timer(0.2).timeout
		check(game.is_chart_playing(), "故障期间点击继续仍能恢复游玩")
		_check_disabled("恢复游玩立即清除暂停故障")
		game.state = game.State.UNLOCK
		check(overlay.effect.is_processing(), "解锁演出属于非播放界面")
		game.debug_start_now()
		_check_disabled("直接开始游玩也关闭故障")
		game._finish()
		check(overlay.effect.is_processing(), "谱面结束后恢复故障")
		await _visit(app.RESULTS_SCENE)
		_begin_burst("结算界面")
		await _capture("Results_%s_burst" % autoplay)
		_finish_burst("结算界面")

	var final_scene := current_scene
	current_scene = null
	final_scene.queue_free()
	await process_frame
	_check_disabled("场景离开时立即清理故障和屏幕复制")
	print("Ambient glitch: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _visit(path: String) -> Node:
	check(change_scene_to_file(path) == OK, "切换场景：" + path)
	await scene_changed
	await process_frame
	await process_frame
	return current_scene


func _check_idle(label: String) -> void:
	check(not overlay.effect.visible, "等待期间隐藏故障：" + label)
	check(overlay._capture.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "等待期间不复制屏幕：" + label)


func _check_disabled(label: String) -> void:
	_check_idle(label)
	check(not overlay.effect.is_processing(), "停止故障调度：" + label)


func _begin_burst(label: String) -> void:
	overlay.effect.set_process(false)
	overlay.effect._wait_remaining = 0.0
	overlay.effect._process(0.001)
	overlay.effect._process(0.04)
	check(overlay.effect.visible, "故障可见：" + label)
	check(overlay._capture.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT, "故障采样当前完整界面：" + label)
	check(overlay.effect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "故障不接管鼠标输入：" + label)
	check(overlay.effect.size.is_equal_approx(root.get_visible_rect().size), "故障适配窗口尺寸：" + label)


func _finish_burst(label: String) -> void:
	overlay.effect._process(1.0)
	_check_idle(label)
	overlay.effect.set_process(true)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _click(button: Control) -> void:
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _capture(file_name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(_capture_dir.path_join(file_name + ".png")) == OK, "保存原生截图：" + file_name)
