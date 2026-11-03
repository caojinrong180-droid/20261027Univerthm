extends Node
## 新手教程自检：教程图弹窗本身（图载入 / 比例 / Esc 关闭）+ 设置页按钮直接进教程谱面
##   godot --headless --path game res://tests/tutorial_check.tscn
## 跑完会把玩家原来的状态写回去。

const TutorialOverlay = preload("res://src/ui/tutorial_overlay.gd")

var _failures := 0


func _ok(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _ready() -> void:
	# 看门狗：万一卡在换场景上，20 秒后自己退出，别把命令行挂死
	get_tree().create_timer(20.0).timeout.connect(func():
		if is_inside_tree():
			print("WATCHDOG timeout -> quit(2)")
			get_tree().quit(2))
	var keep_seen: bool = App.settings.tutorial_seen
	App.settings.tutorial_seen = false

	# ① 教程图弹窗本身（现在没挂入口，但组件还能用：设置里换成进谱面了）
	await get_tree().process_frame        # 等这一帧建完，再往树里挂子节点
	var overlay = TutorialOverlay.new()
	overlay.name = "TutorialOverlay"
	get_tree().root.add_child(overlay)
	await get_tree().process_frame
	_ok(not overlay.visible, "弹窗默认是关着的")
	overlay.open()
	await get_tree().process_frame
	_ok(overlay.visible, "open() 能把弹窗打开")
	_ok(overlay._image.texture != null, "教图载入成功")
	_ok(overlay._image.custom_minimum_size.y > 0.0,
		"图尺寸算出来了 %.0f x %.0f" % [overlay._image.custom_minimum_size.x, overlay._image.custom_minimum_size.y])
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	get_viewport().push_input(esc)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(not overlay.visible, "Esc 关掉教程图")
	overlay.queue_free()
	await get_tree().process_frame

	# ② 设置页那颗「新手教程」：现在直接进教程谱面
	var screen: Control = load("res://scenes/settings.tscn").instantiate()
	get_tree().root.add_child(screen)
	get_tree().current_scene = screen
	await get_tree().process_frame
	await get_tree().process_frame
	var button := screen.find_child("TutorialButton", true, false) as Button
	_ok(button != null, "设置里有「新手教程」按钮")
	if button != null:
		var actions: Control = screen._actions_row()
		var back := screen.find_child("AccentBackButton", true, false)
		_ok(actions != null and button.get_parent() == actions, "按钮在底部那排（返回 / 恢复默认 / 新手教程）")
		_ok(back != null and button.get_index() > back.get_index(), "按钮排在「返回」右边")
		_ok(button.tooltip_text.contains("教程谱面"), "按钮提示指向教程谱面")
		var entry: Dictionary = App.tutorial_entry()
		_ok(not entry.is_empty(), "教程谱面包读得到：" + App.TUTORIAL_ZIP)
		button.pressed.emit()
		await get_tree().create_timer(0.4).timeout
		_ok(bool(App.session.get("tutorial", false)), "点按钮后这一趟带 tutorial 标记")
		_ok(get_tree().current_scene != null
			and get_tree().current_scene.scene_file_path.ends_with("gameplay.tscn"),
			"点按钮直接进谱面（不是弹教程图）")

	App.settings.tutorial_seen = keep_seen
	App.settings.save()
	print("failures = ", _failures)
	get_tree().quit(1 if _failures > 0 else 0)
