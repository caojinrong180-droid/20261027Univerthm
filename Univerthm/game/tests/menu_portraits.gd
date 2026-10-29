extends Node
## godot --headless --path game res://tests/menu_portraits.tscn
## 原生渲染可追加 -- --capture-dir <已忽略的草稿目录> 保存切换画面。

var passed := 0
var failed := 0
var _capture_dir := ""


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", message)


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	get_window().size = Vector2i(1280, 720)
	var args := OS.get_cmdline_user_args()
	var capture_arg := args.find("--capture-dir")
	if capture_arg >= 0 and capture_arg + 1 < args.size():
		_capture_dir = args[capture_arg + 1]
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	get_tree().create_timer(20.0).timeout.connect(func():
		push_error("Menu portrait tests timed out")
		get_tree().quit(1))
	await get_tree().process_frame
	get_tree().current_scene = null
	await _run()
	print("Menu portraits: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


func _run() -> void:
	var old_saved_index: int = App.settings.banner_index
	App.settings.banner_index = 3
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	var girl: TextureRect = menu.get_node("Banner")
	var outgoing: TextureRect = menu.get_node("BannerOutgoing")
	check(menu._banners.size() == 8, "Stra 和 Kisai 的八张立绘均已载入")
	check(girl.texture.resource_path == "res://assets/banners/stra1.png", "默认 Stra 原始立绘，不受旧排序设置影响")
	var early_click := InputEventMouseButton.new()
	early_click.button_index = MOUSE_BUTTON_LEFT
	early_click.pressed = true
	early_click.position = Vector2(940, 330)
	get_viewport().push_input(early_click, true)
	check(menu._banner_index() == 0 and not menu._banner_busy, "入场完成前不接受角色点击")
	early_click.pressed = false
	get_viewport().push_input(early_click, true)
	await menu.entrance_finished
	menu.get_node("AmbientGlitch").stop()
	menu.get_node("MouseCollapse").stop()
	menu.pointer_parallax = false
	await _capture("00_default")
	var opaque := _image_point(menu, girl, true)
	var transparent := _image_point(menu, girl, false)
	check(opaque != Vector2(-1, -1) and transparent != Vector2(-1, -1), "能找到可见角色及图内透明区域")
	_click(transparent)
	check(menu._banner_index() == 0, "透明空白不切换")
	_click(opaque, MOUSE_BUTTON_RIGHT)
	check(menu._banner_index() == 0, "右键不切换")
	_click(opaque)
	check(menu._banner_index() == 1 and menu._banner_busy, "真实左键点击角色进入第二张")
	check(outgoing.visible and outgoing.texture.resource_path.ends_with("/stra1.png"), "旧立绘保留用于交叉淡化")
	check(is_equal_approx(menu._character_reveal, 1.0), "切换不会让整个角色重新淡出到空白")
	menu._banner_tween.custom_step(0.12)
	menu._process(0.12)
	check(girl.self_modulate.a > 0.1 and outgoing.self_modulate.a > 0.1, "过渡中两张立绘同时可见")
	check(absf(girl.self_modulate.a + outgoing.self_modulate.a - 1.0) < 0.001, "交叉淡化权重连续")
	await _capture("01_crossfade")
	_check_spring(menu)
	await _finish_transition(menu)
	check(not outgoing.visible and outgoing.texture == null, "过渡结束清理旧立绘")
	await _capture("02_wave")

	for expected in [2, 3, 0]:
		_click(_image_point(menu, girl, true))
		await _finish_transition(menu)
		check(menu._banner_index() == expected and menu._active_character == 0, "默认只在 Stra 四张间循环：%d" % expected)
		check(girl.texture == menu._banners[expected], "显示对应姿势的纹理：%d" % expected)
		await _capture("%02d_stra" % expected)
	check(menu._banner_masks.size() == 4, "Stra 四张图均缓存透明命中蒙版")

	var version: Control = menu.get_node("Version")
	_click(version.get_global_rect().get_center())
	check(menu._active_character == 1 and menu._banner_index() == 4, "点击左下版本号切到 Kisai 第一张")
	await _finish_transition(menu)
	await _capture("04_Kisai")
	for expected in [5, 6, 7, 4]:
		_click(_image_point(menu, girl, true))
		await _finish_transition(menu)
		check(menu._banner_index() == expected and menu._active_character == 1, "Kisai 四张独立循环：%d" % expected)
		await _capture("%02d_Kisai" % expected)
	check(menu._banner_masks.size() == 8, "八张图均缓存透明命中蒙版")
	_check_kisai_margins(menu)
	_click(version.get_global_rect().get_center())
	check(menu._active_character == 0 and menu._banner_index() == 0, "再次点击版本号回 Stra 第一张")
	await _finish_transition(menu)

	# 在上一张仍可见时连点，验证每次点击都被保留且只触发一次。
	_click(_image_point(menu, girl, true))
	for press in 3:
		_click(_image_point(menu, outgoing, true))
	check(menu._banner_pending_steps == 3, "切换途中连续三次点击按顺序排队")
	for transition in 4:
		menu._banner_tween.custom_step(1.0)
		menu._process(1.0 / 60.0)
	check(menu._banner_index() == 0 and not menu._banner_busy and menu._banner_pending_steps == 0, "连续四次点击只在 Stra 内循环一周")
	check(girl.scale.x > 0.8 and girl.scale.y > 0.8, "连续点击不会累积缩放畸变")
	menu._process(1.0)

	_click(version.get_global_rect().get_center())
	check(menu._active_character == 1 and menu._banner_index() == 4, "版本号切到 Kisai 时能启动动画")
	_click(version.get_global_rect().get_center())
	check(menu._active_character == 0 and menu._banner_index() == 0, "过渡中再次点版本号可立即切回 Stra")
	await _finish_transition(menu)
	check(App.settings.banner_index == 3, "临时切换姿势不改写玩家设置")

	# 实际点击开始游戏，确保角色交互没有截获左侧菜单按钮。
	var start_button: Control = menu.get_node("StartButton")
	_click(start_button.get_global_rect().get_center())
	await get_tree().scene_changed
	check(get_tree().current_scene.scene_file_path == App.SELECT_SCENE, "开始游戏按钮正常进入选曲")
	App.goto_menu()
	await get_tree().scene_changed
	check(get_tree().current_scene.get_node("Banner").texture.resource_path.ends_with("/stra1.png"), "重新进入主界面仍默认第一张")
	App.settings.banner_index = old_saved_index
	get_tree().current_scene.queue_free()
	await get_tree().process_frame


func _check_spring(menu) -> void:
	var initial_position := Vector3(44.0, -0.065, deg_to_rad(-1.1))
	var initial_velocity := Vector3(-50.0, 0.2, deg_to_rad(2.0))
	menu._banner_spring = initial_position
	menu._banner_velocity = initial_velocity
	menu._advance_banner_spring(0.25)
	var single_step: Vector3 = menu._banner_spring
	check(single_step.x < 0.0, "惯性超过目标位置再回弹")
	menu._banner_spring = initial_position
	menu._banner_velocity = initial_velocity
	for frame in 15:
		menu._advance_banner_spring(1.0 / 60.0)
	check(menu._banner_spring.distance_to(single_step) < 0.0001, "长帧与 60 FPS 的弹簧轨迹一致")
	menu._advance_banner_spring(1.0)
	check(menu._banner_spring.length() < 0.002 and menu._banner_velocity.length() < 0.02, "弹簧平滑收敛，不残留抖动")
	menu._update_character_motion()


func _check_kisai_margins(menu) -> void:
	for index in range(4, 8):
		var image: Image = menu._banners[index].get_image()
		if image.is_compressed():
			image.decompress()
		var opaque_border := 0
		for y in range(0, image.get_height(), 24):
			if image.get_pixel(0, y).a > 0.1:
				opaque_border += 1
			if image.get_pixel(image.get_width() - 1, y).a > 0.1:
				opaque_border += 1
		for x in range(0, image.get_width(), 24):
			if image.get_pixel(x, 0).a > 0.1:
				opaque_border += 1
			if image.get_pixel(x, image.get_height() - 1).a > 0.1:
				opaque_border += 1
		check(opaque_border <= 2, "Kisai%d 披风收在透明画布内" % (index - 3))


func _image_point(menu: Control, portrait: TextureRect, opaque: bool) -> Vector2:
	var image := portrait.texture.get_image()
	if image.is_compressed():
		image.decompress()
	for y in range(24, image.get_height(), 24):
		for x in range(24, image.get_width(), 24):
			var alpha := image.get_pixel(x, y).a
			if (opaque and alpha < 0.95) or (not opaque and alpha > 0.01):
				continue
			var point := portrait.get_transform() * (Vector2(x, y) / Vector2(image.get_size()) * portrait.size)
			if point.x > 720.0 and point.x < 1200.0 and point.y > 160.0 and point.y < 490.0:
				return menu.get_global_transform() * point
	return Vector2(-1, -1)


func _click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.global_position = point
	event.pressed = true
	get_viewport().push_input(event, true)
	event.pressed = false
	get_viewport().push_input(event, true)


func _finish_transition(menu) -> void:
	menu._banner_tween.custom_step(1.0)
	menu._process(1.0)
	await get_tree().process_frame


func _capture(file_name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(file_name + ".png"))
	check(error == OK, "保存原生渲染截图：" + file_name)
