extends Node
## 新手教程弹窗自检：设置页那个按钮 + 弹窗本身（图载入 / 比例 / Esc 关闭 / 记成看过）
##   godot --headless --path game res://tests/tutorial_check.tscn
## 跑完会把玩家原来的「看过没有」写回去。

var _failures := 0


func _ok(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _ready() -> void:
	var keep_seen: bool = App.settings.tutorial_seen
	App.settings.tutorial_seen = false
	var screen: Control = load("res://scenes/settings.tscn").instantiate()
	get_tree().root.add_child.call_deferred(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	var button := screen.find_child("TutorialButton", true, false) as Button
	_ok(button != null, "设置里有「新手教程」按钮")
	if button != null:
		var actions: Control = screen._actions_row()
		var back := screen.find_child("AccentBackButton", true, false)
		_ok(actions != null and button.get_parent() == actions, "按钮在底部那排（返回 / 恢复默认 / 新手教程）")
		_ok(back != null and button.get_index() > back.get_index(), "按钮排在「返回」右边")
	_ok(screen._tutorial == null, "弹窗是懒加载的")
	if button != null:
		button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var overlay = screen._tutorial
		_ok(overlay != null and overlay.visible, "点「新手教程」打开教程弹窗")
		if overlay != null:
			_ok(overlay._image.texture != null, "教图载入成功")
			_ok(overlay._image.custom_minimum_size.y > 0.0,
				"图尺寸算出来了 %.0f x %.0f" % [overlay._image.custom_minimum_size.x, overlay._image.custom_minimum_size.y])
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.pressed = true
			get_viewport().push_input(esc)
			await get_tree().process_frame
			await get_tree().process_frame
			_ok(not overlay.visible, "Esc 关掉教程")
			_ok(App.settings.tutorial_seen, "从设置里看过也算「看过了」")
	_ok(screen.visible, "关掉教程后设置页还在")
	screen.queue_free()
	await get_tree().process_frame

	App.settings.tutorial_seen = keep_seen
	App.settings.save()
	print("failures = ", _failures)
	get_tree().quit(1 if _failures > 0 else 0)
