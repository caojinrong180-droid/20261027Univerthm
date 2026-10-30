extends Node
## 设置页「辅助测量」浮窗自检：开合 / 节拍器 / 打点 / 取平均 / 写进音画偏移。
## 跑法：godot --headless --path game res://tests/calibration_check.tscn
## 跑完会把玩家原来的音画偏移写回去。

var _failures := 0


func _ok(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _push_key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event)


func _ready() -> void:
	var keep_offset: float = App.settings.audio_offset_ms
	var screen: Control = load("res://scenes/settings.tscn").instantiate()
	get_tree().root.add_child.call_deferred(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	var button = screen.find_child("CalibButton", true, false)
	_ok(button != null, "音画偏移那一行多了一个 CalibButton")
	if button == null:
		get_tree().quit(1)
		return
	_ok(screen._calibration == null, "浮窗是懒加载的，一开始不存在")

	button.pressed.emit()
	await get_tree().process_frame
	var overlay = screen._calibration
	_ok(overlay != null and overlay.visible, "点按钮打开浮窗")
	_ok(overlay.get_node_or_null("DimShade") != null, "背景有暗底")
	_ok(overlay.find_child("CalibrationPanel", true, false) != null, "中间有面板")

	# 面板必须居中且不可拖动（锚点定死、没有拖拽逻辑）
	var panel: Control = overlay.find_child("CalibrationPanel", true, false)
	var screen_rect: Rect2 = overlay.get_global_rect()
	var panel_rect: Rect2 = panel.get_global_rect()
	_ok(absf((panel_rect.position.x - screen_rect.position.x) - (screen_rect.size.x - panel_rect.size.x) * 0.5) < 2.0,
		"面板水平居中")

	# ---- 开始 → 节拍器 ----
	overlay._on_start_pressed()
	_ok(overlay._state == 1, "点开始进入测量状态")
	var started: int = Time.get_ticks_usec()
	while overlay._beat_index < 2 and Time.get_ticks_usec() - started < 5000000:
		await get_tree().process_frame
	_ok(overlay._beat_index >= 2, "节拍器在走（已经过了 %d 拍）" % overlay._beat_index)

	# ---- 只认 F：A 不算 ----
	var before: int = overlay._samples.size()
	_push_key(KEY_A)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(overlay._samples.size() == before and overlay._pending_press_usec == 0, "按 A 不算数（只认 F）")

	# ---- 晚按：等重音播出后 50 ms 打一下 ----
	var expected_late := 50.0
	var guard: int = Time.get_ticks_usec()
	for i in 5:
		while overlay._last_accent_usec == 0 and Time.get_ticks_usec() - guard < 30000000:
			await get_tree().process_frame
		await get_tree().create_timer(expected_late / 1000.0).timeout
		_push_key(KEY_F)
		await get_tree().process_frame
		await get_tree().process_frame
	_ok(overlay._samples.size() == 5, "打满 5 次就收（实际 %d）" % overlay._samples.size())
	_ok(overlay._state == 2, "打满 5 次后进入完成状态")
	var avg: float = overlay._average_ms()
	_ok(absf(avg - expected_late) < 60.0, "平均值贴着真实延迟 %+.0f ms（期望约 +%.0f）" % [avg, expected_late])

	# ---- 应用 ----
	var applied_button = overlay.find_child("ApplyButton", true, false)
	_ok(applied_button != null and not applied_button.disabled, "应用按钮可用")
	applied_button.pressed.emit()
	await get_tree().process_frame
	_ok(absf(App.settings.audio_offset_ms - round(avg)) < 0.01,
		"确认后写进音画偏移：%+.0f ms" % App.settings.audio_offset_ms)
	await get_tree().create_timer(0.9).timeout
	_ok(not overlay.visible, "应用后面板自己关掉")

	# ---- 早按：重音前 120 ms 打点，等重音真正播出后记账 ----
	button.pressed.emit()
	await get_tree().process_frame
	overlay._on_start_pressed()
	guard = Time.get_ticks_usec()
	var early_done := false
	while Time.get_ticks_usec() - guard < 20000000 and not early_done:
		var next: int = overlay._next_accent_usec()
		if next > 0 and next - Time.get_ticks_usec() < 120000:
			_push_key(KEY_F)
			early_done = true
			break
		await get_tree().process_frame
	_ok(early_done, "等到重音前一瞬")
	if early_done:
		var wait_guard: int = Time.get_ticks_usec()
		while overlay._samples.is_empty() and Time.get_ticks_usec() - wait_guard < 4000000:
			await get_tree().process_frame
		_ok(overlay._samples.size() == 1, "早按也算一次（%d）" % overlay._samples.size())
		if overlay._samples.size() == 1:
			_ok(overlay._samples[0] < 0.0, "早按记成负值：%+.0f ms" % overlay._samples[0])

	# ---- Esc 关掉 ----
	_push_key(KEY_ESCAPE)
	await get_tree().process_frame
	_ok(not overlay.visible, "Esc 关掉浮窗")
	_ok(screen.visible, "关掉浮窗后设置页还在")

	# 还原玩家原本的偏移
	App.settings.audio_offset_ms = keep_offset
	App.settings.save()

	print("failures = ", _failures)
	get_tree().quit(1 if _failures > 0 else 0)
