extends SceneTree
## 核心层自测（不需要编辑器、不需要显卡）：
##   godot --headless --path . --script res://test/run_core_tests.gd
##
## 覆盖：音符/轨道序列化容错、BPM 换算与吸附、文档增删排序、JSON 存读往返、
## 校验告警、快照恢复、示例谱面可加载。

var _pass := 0
var _fail := 0
var _fail_msgs: Array = []


func _init() -> void:
	print("=== rchart core tests ===")
	_test_note_roundtrip()
	_test_note_fallbacks()
	_test_lane_roundtrip()
	_test_judge_zone()
	_test_events()
	_test_timing()
	_test_timing_bpm_events()
	_test_document_basics()
	_test_lane_resize()
	_test_io_roundtrip()
	_test_validation()
	_test_snapshot_restore()
	_test_demo_chart()
	_test_audio_guard()

	print("---")
	print("pass=%d fail=%d" % [_pass, _fail])
	for m in _fail_msgs:
		print("  FAILED: ", m)
	quit(1 if _fail > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fail_msgs.append(msg)
		print("FAIL: ", msg)


func near(a: float, b: float, eps: float = 1e-4) -> bool:
	return absf(a - b) <= eps


# ------------------------------------------------------------------ 音符

func _test_note_roundtrip() -> void:
	var n := RhythmChartNote.new()
	n.id = 7
	n.time = 1.2345678
	n.lane = 2
	n.type = RhythmChartNote.Type.HOLD
	n.duration = 0.5
	n.velocity = 0.8
	var d := n.to_dict()
	check(String(d["type"]) == "hold", "hold 序列化成 hold")
	check(near(float(d["time"]), 1.234568, 1e-6), "时间保留 6 位小数")

	var back := RhythmChartNote.from_dict(d)
	check(back.id == 7, "id 往返")
	check(near(back.time, 1.234568, 1e-6), "时间往返")
	check(back.lane == 2, "lane 往返")
	check(back.type == RhythmChartNote.Type.HOLD, "type 往返")
	check(near(back.duration, 0.5), "duration 往返")
	check(near(back.end_time(), 1.734568, 1e-6), "end_time 正确")
	check(back.is_long(), "is_long 正确")


func _test_note_fallbacks() -> void:
	var a := RhythmChartNote.from_dict({"time": 1.0, "lane": 0})
	check(a.type == RhythmChartNote.Type.TAP, "缺 type 默认 tap")
	check(near(a.velocity, 1.0), "缺 velocity 默认 1.0")

	var b := RhythmChartNote.from_dict({"type": "TAPPP", "time": -5.0, "lane": -3})
	check(b.type == RhythmChartNote.Type.TAP, "错误 type 退回 tap")
	check(near(b.time, 0.0), "负时间夹到 0")
	check(b.lane == 0, "负 lane 夹到 0")

	var c := RhythmChartNote.from_dict({"type": "hold"})
	check(near(c.duration, 0.0), "hold 缺 duration 记 0")
	check(not c.is_long(), "duration=0 的 hold 不算长条")

	var typed := RhythmChartNote.from_dict({"type": "FLICK"})
	check(typed.type == RhythmChartNote.Type.FLICK, "类型大小写不敏感")


# ------------------------------------------------------------------ 轨道

func _test_lane_roundtrip() -> void:
	var lane := RhythmChartLane.default_for(2)
	lane.name = "Outer R"
	lane.color = Color("#ffd166")
	lane.position = Vector2(-150.4, 12.5)
	lane.rotation_deg = -9.5
	lane.alpha = 158
	lane.length_scale = 1.35
	lane.visible = false
	lane.volume = 0.7

	var d := lane.to_dict()
	var back := RhythmChartLane.from_dict(d, 2)
	check(back.name == "Outer R", "轨道名往返")
	check(back.color.is_equal_approx(Color("#ffd166")), "颜色往返")
	check(near(back.position.x, -150.4, 0.01) and near(back.position.y, 12.5, 0.01), "位移往返")
	check(near(back.rotation_deg, -9.5, 0.01), "旋转往返")
	check(back.alpha == 158, "透明度（0~255）往返")
	check(near(back.alpha_f(), 0.6196, 0.002), "alpha_f 换算成 0~1")
	check(near(back.length_scale, 1.35, 0.001), "长度倍率往返")
	check(back.visible == false, "可见性往返")
	check(near(back.volume, 0.7, 0.001), "音量往返")

	# 越界值必须被夹住，不然渲染层会画出诡异的东西
	var wild := RhythmChartLane.from_dict({"alpha": 999, "length_scale": -3.0, "rotation_deg": 400.0})
	check(wild.alpha == 255, "alpha 夹到 255")
	check(wild.length_scale == 0.1, "length_scale 夹到 0.1")
	check(wild.rotation_deg >= -360.0 and wild.rotation_deg <= 360.0, "rotation 被 wrap")

	# v1 谱面里的 alpha 是 0~1 浮点，读的时候要换算成 0~255
	var legacy := RhythmChartLane.from_dict({"alpha": 0.5}, 0, true)
	check(legacy.alpha == 128, "v1 旧谱面 alpha 0.5 → 128（实际 %d）" % legacy.alpha)
	var modern := RhythmChartLane.from_dict({"alpha": 0.5}, 0, false)
	check(modern.alpha == 1, "v2 谱面 alpha 0.5 → 夹到 1（实际 %d）" % modern.alpha)

	var copy := lane.duplicate_lane()
	copy.position.x = 999.0
	check(not near(lane.position.x, 999.0), "duplicate_lane 是深拷贝")


# ------------------------------------------------------------------ 判定区

func _test_judge_zone() -> void:
	# 默认：白色 + 任意键
	var lane := RhythmChartLane.default_for(0)
	check(lane.judge_zone == RhythmChartLane.JudgeZone.NONE, "默认判定区是 none（白）")
	check(lane.display_color().is_equal_approx(Color("#ffffff")), "默认轨道颜色是白色")
	check(lane.allowed_keys().size() == 8, "白色 = ASDFJKL; 8 个键都能判定")

	var left := RhythmChartLane.from_dict({"judge_zone": "left"})
	check(left.judge_zone == RhythmChartLane.JudgeZone.LEFT, "left 判定区解析")
	check(left.allowed_keys() == PackedStringArray(["A", "S", "D", "F"]), "紫色只能用 ASDF")
	check(left.display_color().is_equal_approx(Color("#b06bff")), "紫色显示为紫")
	check(String(left.to_dict()["judge_zone"]) == "left", "判定区往返")

	var right := RhythmChartLane.from_dict({"judge_zone": "RIGHT"})
	check(right.judge_zone == RhythmChartLane.JudgeZone.RIGHT, "判定区大小写不敏感")
	check(right.allowed_keys() == PackedStringArray(["J", "K", "L", ";"]), "黄色只能用 JKL;")

	var bogus := RhythmChartLane.from_dict({"judge_zone": "紫色"})
	check(bogus.judge_zone == RhythmChartLane.JudgeZone.NONE, "未知判定区退回 none")

	# 自定义颜色 + 判定区：显示色跟判定区走
	var custom := RhythmChartLane.default_for(3)
	custom.color = Color("#00ff00")
	custom.judge_zone = RhythmChartLane.JudgeZone.LEFT
	check(custom.display_color().is_equal_approx(Color("#b06bff")), "设了判定区后显示色跟判定区")
	custom.judge_zone = RhythmChartLane.JudgeZone.NONE
	check(custom.display_color().is_equal_approx(Color("#00ff00")), "未设判定区时用轨道自身颜色")

	# 判定区跟着轨道一起深拷贝
	var copy := custom.duplicate_lane()
	copy.judge_zone = RhythmChartLane.JudgeZone.RIGHT
	check(custom.judge_zone == RhythmChartLane.JudgeZone.NONE, "duplicate_lane 深拷贝判定区")


# ------------------------------------------------------------------ 关键帧动画

func _test_events() -> void:
	# --- 缓动曲线 ---
	check(near(RhythmChartLane.apply_ease("linear", 0.5), 0.5), "linear 缓动")
	check(near(RhythmChartLane.apply_ease("outQuad", 0.5), 0.75), "outQuad(0.5) = 0.75")
	check(near(RhythmChartLane.apply_ease("inQuad", 0.5), 0.25), "inQuad(0.5) = 0.25")
	check(near(RhythmChartLane.apply_ease("inOutCubic", 0.5), 0.5), "inOutCubic 中点对称")
	check(near(RhythmChartLane.apply_ease("step", 0.99), 0.0), "step 在 t<1 时是 0")
	check(near(RhythmChartLane.apply_ease("step", 1.0), 1.0), "step 到 1 才跳变")
	check(near(RhythmChartLane.apply_ease("linear", 0.0), 0.0), "缓动端点 t=0")
	check(near(RhythmChartLane.apply_ease("linear", 1.0), 1.0), "缓动端点 t=1")

	# 自定义贝塞尔曲线
	var curve := "bezier(0.25, 0.1, 0.25, 1)"
	var bz0 := RhythmChartLane.apply_ease(curve, 0.0)
	var bz5 := RhythmChartLane.apply_ease(curve, 0.5)
	var bz1 := RhythmChartLane.apply_ease(curve, 1.0)
	check(near(bz0, 0.0, 0.01) and near(bz1, 1.0, 0.01), "bezier 端点 0/1")
	check(bz5 > 0.0 and bz5 < 1.0, "bezier 中点落在 (0,1) 内（%.3f）" % bz5)
	check(near(RhythmChartLane.apply_ease("bezier(0.25,0.1,0.25,1)", 0.5), bz5, 1e-6),
		"bezier 允许无空格写法")

	# --- 事件求值（PhiEdit 模型）---
	var lane := RhythmChartLane.default_for(0)
	lane.position = Vector2(-150.0, 0.0)
	lane.set_events("x", [
		{"start": 0.0, "end": 4.0, "from": -150.0, "to": 50.0, "ease": "linear"},
	])
	check(near(lane.resolved_x(2.0), -50.0), "事件线性插值 t=2 → -50")
	check(near(lane.resolved_x(-1.0), -150.0), "第一条事件之前用静态值")
	check(near(lane.resolved_x(4.0), 50.0), "事件结束点等于 to")
	check(near(lane.resolved_x(99.0), 50.0), "事件结束后保持 to，不外推")
	check(lane.has_events(), "has_events 为真")
	check(near(lane.resolved_y(1.0), 0.0), "没有事件的属性用静态值")

	# 缓动生效：outQuad 中点应该更快
	lane.set_events("x", [
		{"start": 0.0, "end": 2.0, "from": 0.0, "to": 100.0, "ease": "outQuad"},
	])
	check(near(lane.resolved_x(1.0), 75.0), "outQuad 事件中点 = 75（实际 %.1f）" % lane.resolved_x(1.0))

	# 多条事件：起点最晚的那条生效，事件之间保持上一条的 to
	lane.set_events("x", [
		{"start": 0.0, "end": 2.0, "from": 0.0, "to": 100.0, "ease": "linear"},
		{"start": 4.0, "end": 6.0, "from": 500.0, "to": 600.0, "ease": "linear"},
	])
	check(near(lane.resolved_x(1.0), 50.0), "第一段事件内插值")
	check(near(lane.resolved_x(3.0), 100.0), "两段之间保持第一段的 to")
	check(near(lane.resolved_x(5.0), 550.0), "第二段事件内插值")

	# 透明度事件：0~255 渐变
	var fade := RhythmChartLane.default_for(2)
	fade.set_events("alpha", [
		{"start": 0.0, "end": 2.0, "from": 255.0, "to": 0.0, "ease": "linear"},
	])
	check(near(fade.resolved_alpha_255(1.0), 127.5, 0.01), "透明度事件中点 = 127.5")
	check(near(fade.resolved_alpha(2.0), 0.0, 0.01), "透明度事件渐变到 0")

	# 追加事件时按起点排序
	var list: Array = [{"start": 4.0, "end": 5.0, "from": 0.0, "to": 1.0, "ease": "linear"}]
	list = RhythmChartLane.append_event(list, 0.0, 1.0, 0.0, 1.0)
	check(list.size() == 2 and near(float(list[0]["start"]), 0.0), "append_event 按起点排序")
	var zero := RhythmChartLane.append_event([], 3.0, 1.0, 0.0, 1.0)
	check(near(float(zero[0]["end"]), 3.0), "结束时间不能早于开始时间")

	# --- 序列化往返 ---
	var d := lane.to_dict()
	check(int(d["alpha"]) == 255, "alpha 存成 0~255 整数")
	check((d.get("events", {}) as Dictionary).has("x"), "events 写进 JSON")
	var back := RhythmChartLane.from_dict(d, 0, false)
	check(back.get_events("x").size() == 2, "事件往返数量")
	check(near(back.resolved_x(5.0), 550.0), "事件往返后求值一致")
	check(String(back.get_events("x")[0].get("ease", "")) == "linear", "缓动名字往返")

	# 乱序写入也要按起点排好
	var messy := RhythmChartLane.default_for(0)
	messy.set_events("y", [
		{"start": 3.0, "end": 4.0, "from": 30.0, "to": 40.0, "ease": "linear"},
		{"start": 1.0, "end": 2.0, "from": 10.0, "to": 20.0, "ease": "linear"},
	])
	check(near(float(messy.get_events("y")[0]["start"]), 1.0), "事件写入时按起点排序")

	# v2 的 motion 关键帧能自动合成事件（兼容旧文件）
	var legacy_motion := {
		"x": [
			{"time": 0.0, "value": 0.0, "ease": "linear"},
			{"time": 2.0, "value": 100.0, "ease": "linear"},
			{"time": 4.0, "value": 0.0, "ease": "outQuad"},
		],
	}
	var converted := RhythmChartLane.events_from_motion(legacy_motion)
	check((converted.get("x", []) as Array).size() == 2, "motion 三帧 → 两条事件")
	var converted_lane := RhythmChartLane.from_dict({"motion": legacy_motion}, 0, false)
	check(converted_lane.get_events("x").size() == 2, "旧文件载入时自动迁移成事件")
	check(near(converted_lane.resolved_x(1.0), 50.0), "迁移后求值正确")

# ------------------------------------------------------------------ 时间轴

func _test_timing() -> void:
	var t := RhythmChartTiming.new()
	t.set_bpm(120.0)
	t.set_beat_offset(0.0)
	check(near(t.beat_to_sec(1.0), 0.5), "120BPM 一拍 0.5s")
	check(near(t.beat_to_sec(4.0), 2.0), "120BPM 一小节 2s")
	check(near(t.sec_to_beat(2.0), 4.0), "2s = 第 4 拍")
	check(near(t.beat_duration_at(0.0), 0.5), "beat_duration_at")

	# 吸附：1/4 拍网格
	check(near(t.snap_sec(0.13, 4), 0.125), "0.13s 吸到 0.125s（1/4 拍）")
	check(near(t.snap_sec(0.40, 1), 0.5), "0.40s 吸到整拍 0.5s")
	check(near(t.snap_sec(0.13, 0), 0.13), "divisor=0 不吸附")

	var grid := t.grid_beats(0.0, 2.0, 4)
	check(grid.size() == 9, "0..2 拍按 1/4 切出 9 条线（实际 %d）" % grid.size())

	# 首拍偏移
	var t2 := RhythmChartTiming.new()
	t2.set_bpm(100.0)
	t2.set_beat_offset(1.5)
	check(near(t2.beat_to_sec(0.0), 1.5), "首拍偏移让 beat0 落在 1.5s")
	check(near(t2.beat_to_sec(1.0), 2.1, 1e-5), "100BPM 一拍 0.6s")


func _test_timing_bpm_events() -> void:
	var t := RhythmChartTiming.new()
	t.from_dict({
		"bpm": 120.0,
		"beat_offset": 0.0,
		"bpm_events": [{"beat": 0.0, "bpm": 120.0}, {"beat": 4.0, "bpm": 60.0}],
	})
	check(near(t.beat_to_sec(4.0), 2.0), "前 4 拍 120BPM = 2s")
	check(near(t.beat_to_sec(5.0), 3.0), "变速后一拍变 1s")
	check(near(t.sec_to_beat(3.0), 5.0), "变速后秒转拍正确")
	check(near(t.beat_duration_at(4.5), 1.0), "变速点后的单拍时长")
	check(near(t.beat_duration_at(0.0), 0.5), "变速点前的单拍时长")

	var rt := RhythmChartTiming.new()
	rt.from_dict(t.to_dict())
	check(rt.bpm_events.size() == 2, "bpm_events 往返数量")
	check(near(rt.beat_to_sec(5.0), 3.0), "bpm_events 往返换算一致")


# ------------------------------------------------------------------ 文档

func _test_document_basics() -> void:
	var doc := RhythmChartDocument.create_default()
	check(doc.lane_count() == 4, "默认 4 轨")
	check(doc.notes.is_empty(), "默认没有音符")

	doc.add_note(2.0, 1)
	doc.add_note(1.0, 0)
	doc.add_note(3.0, 3)
	check(doc.notes.size() == 3, "加了 3 个音符")
	check(near(doc.notes[0].time, 1.0), "音符按时间排序")
	check(near(doc.notes[2].time, 3.0), "排序末尾正确")
	check(near(doc.total_duration(), 3.0), "total_duration")

	var hit := doc.find_note_near(1.05, 0, 0.1)
	check(hit != null and near(hit.time, 1.0), "find_note_near 命中")
	check(doc.find_note_near(1.05, 2, 0.1) == null, "find_note_near 不会跨轨命中")

	var counts := doc.note_count_by_type()
	check(int(counts["tap"]) == 3, "类型统计")

	doc.remove_note(hit)
	check(doc.notes.size() == 2, "删除音符")

	var ids := {}
	for n in doc.notes:
		ids[n.id] = true
	check(ids.size() == doc.notes.size(), "id 不重复")


func _test_lane_resize() -> void:
	var doc := RhythmChartDocument.create_default()
	doc.lanes[0].name = "自定义 0"
	doc.add_note(1.0, 3)
	doc.set_lane_count(6)
	check(doc.lane_count() == 6, "扩到 6 轨")
	check(doc.lanes[0].name == "自定义 0", "扩展时保留已有轨道设置")
	check(int(doc.stage["lane_count"]) == 6, "stage.lane_count 同步")

	doc.set_lane_count(2)
	check(doc.lane_count() == 2, "缩到 2 轨")
	check(doc.notes.is_empty(), "被删轨道上的音符一并移除")
	for n in doc.notes:
		check(n.lane < 2, "剩余音符轨道合法")

	var d := doc.to_dict()
	check((d["lanes"] as Array).size() == 2, "序列化轨道数与文档一致")


# ------------------------------------------------------------------ 存读

func _test_io_roundtrip() -> void:
	var doc := RhythmChartDocument.create_default()
	doc.meta["title"] = "往返测试"
	doc.meta["artist"] = "Test Artist"
	doc.audio["file"] = "res://audio/x.ogg"
	doc.audio["offset"] = 0.042
	doc.timing.set_bpm(174.0)
	doc.lanes[1].rotation_deg = 12.5
	doc.lanes[1].alpha = 128
	doc.add_note(0.5, 0).type = RhythmChartNote.Type.HOLD
	doc.notes[0].duration = 0.25
	doc.add_note(1.0, 2)

	var path := "user://io_roundtrip.json"
	var err := RhythmChartIO.save_file(doc, path)
	check(err == OK, "保存返回 OK（err=%d）" % err)
	check(FileAccess.file_exists(path), "文件确实写出来了")

	var report: Array = []
	var loaded := RhythmChartIO.load_file(path, report)
	check(loaded != null, "能读回来")
	if loaded != null:
		check(String(loaded.meta["title"]) == "往返测试", "标题往返")
		check(near(float(loaded.audio["offset"]), 0.042), "音频偏移往返")
		check(near(loaded.timing.bpm, 174.0, 0.001), "BPM 往返")
		check(near(loaded.lanes[1].rotation_deg, 12.5, 0.01), "轨道旋转往返")
		check(loaded.lanes[1].alpha == 128, "轨道透明度往返")
		check(loaded.notes.size() == 2, "音符数量往返")
		check(loaded.notes[0].type == RhythmChartNote.Type.HOLD, "长条类型往返")
		check(near(loaded.notes[0].duration, 0.25), "长条长度往返")
		check(loaded.path == path, "路径被记住")

	# 坏 JSON 不能崩，只能报错
	var bad := RhythmChartIO.doc_from_text("{ 这不是 json ", "bad.json", report)
	check(bad == null, "坏 JSON 返回 null")
	check(not report.is_empty(), "坏 JSON 产生报告")

	var missing := RhythmChartIO.load_file("user://根本不存在.json", report)
	check(missing == null, "文件不存在返回 null")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ------------------------------------------------------------------ 校验

func _test_validation() -> void:
	var doc := RhythmChartDocument.create_default()
	var problems := doc.validate()
	check(not problems.is_empty(), "没音频时应当有提示")

	# 手写 JSON 把 lane 写到不存在的轨道：应当被夹住并留下告警
	var report: Array = []
	var parsed := RhythmChartIO.doc_from_text(
		JSON.stringify({
			"meta": {"title": "手写", "level": 3},
			"audio": {"file": "res://a.ogg"},
			"timing": {"bpm": 150},
			"lanes": [],
			"notes": [{"time": 1.0, "lane": 9, "type": "tap"}],
		}), "hand.json", report)
	check(parsed != null, "手写最小 JSON 能解析")
	if parsed != null:
		check(parsed.lane_count() == 4, "没给 lanes 时按 stage.lane_count 补默认轨道")
		check(parsed.notes[0].lane == 3, "越界 lane 被夹到最后一轨")
		check(report.size() > 0, "越界 lane 留下告警")


# ------------------------------------------------------------------ 快照

func _test_snapshot_restore() -> void:
	var doc := RhythmChartDocument.create_default()
	doc.add_note(1.0, 0)
	doc.add_note(2.0, 1)
	var snap := doc.snapshot()

	doc.add_note(3.0, 2)
	doc.lanes[0].alpha = 26
	check(doc.notes.size() == 3, "改完之后 3 个音符")

	doc.restore(snap)
	check(doc.notes.size() == 2, "快照恢复音符数")
	check(doc.lanes[0].alpha == 255, "快照恢复轨道透明度")

	# 快照必须是深拷贝：改快照不能影响文档
	var snap2 := doc.snapshot()
	snap2["notes"][0]["time"] = 42.0
	check(not near(doc.notes[0].time, 42.0), "snapshot 是深拷贝（改快照不影响文档）")

	var snap3 := doc.snapshot()
	snap3["notes"][0]["time"] = 99.0
	doc.restore(snap3)
	var has99 := false
	for n in doc.notes:
		if near(n.time, 99.0):
			has99 = true
	check(has99, "restore 吃的是传入的快照数据")


# ------------------------------------------------------------------ 示例谱面

func _test_demo_chart() -> void:
	var path := "res://charts/demo_neon_pulse.json"
	if not FileAccess.file_exists(path):
		check(false, "示例谱面缺失：" + path)
		return
	var report: Array = []
	var doc := RhythmChartIO.load_file(path, report)
	check(doc != null, "示例谱面能载入")
	if doc == null:
		return
	check(doc.notes.size() > 60, "示例谱面音符数 = %d" % doc.notes.size())
	check(doc.lane_count() == 4, "示例谱面 4 轨")
	check(not near(doc.lanes[0].rotation_deg, 0.0), "示例谱面有旋转轨道")
	check(not near(doc.lanes[0].position.x, doc.lanes[1].position.x), "示例谱面轨道有独立位移")
	# 示例谱面演示判定区：白 / 紫 / 黄 / 白
	check(doc.lanes[0].judge_zone == RhythmChartLane.JudgeZone.NONE, "示例谱面 1 轨白色")
	check(doc.lanes[1].judge_zone == RhythmChartLane.JudgeZone.LEFT, "示例谱面 2 轨紫色")
	check(doc.lanes[2].judge_zone == RhythmChartLane.JudgeZone.RIGHT, "示例谱面 3 轨黄色")
	check(doc.lanes[0].color.is_equal_approx(Color("#ffffff")), "示例谱面轨道底色是白")
	check(doc.lanes[0].alpha == 255, "示例谱面 1 轨 alpha 255")
	check(doc.lanes[1].has_events(), "示例谱面 2 轨有动画")
	check(doc.lanes[1].get_events("x").size() == 2, "示例谱面 2 轨 x 有 2 条事件")
	check(doc.lanes[1].get_events("alpha").size() == 2, "示例谱面 2 轨 alpha 有 2 条事件")
	check(doc.lanes[2].get_events("rotation").size() == 2, "示例谱面 3 轨有旋转动画")
	# 动画在时间上确实在变
	check(not near(doc.lanes[1].resolved_x(0.0), doc.lanes[1].resolved_x(8.0)),
		"示例谱面 2 轨的 x 随时间变化")
	check(not near(doc.lanes[1].resolved_alpha_255(0.0), doc.lanes[1].resolved_alpha_255(6.0), 1.0),
		"示例谱面 2 轨透明度随时间变化")
	var holds := 0
	var flicks := 0
	var mines := 0
	for n in doc.notes:
		if n.type == RhythmChartNote.Type.HOLD:
			holds += 1
		elif n.type == RhythmChartNote.Type.FLICK:
			flicks += 1
		elif n.type == RhythmChartNote.Type.MINE:
			mines += 1
	check(holds > 0 and flicks > 0 and mines > 0,
		"示例谱面包含 hold/flick/mine（%d/%d/%d）" % [holds, flicks, mines])
	# 时间必须严格递增（同时间允许多轨）
	var prev := -1.0
	var ordered := true
	for n in doc.notes:
		if n.time < prev - 1e-6:
			ordered = false
		prev = n.time
	check(ordered, "示例谱面按时间有序")
	check(near(doc.timing.bpm, 150.0, 0.001), "示例谱面 BPM 150")


# ------------------------------------------------------------------ 音频守卫

func _test_audio_guard() -> void:
	check(RhythmChartAudio.load_stream("") == null, "空路径返回 null")
	check(RhythmChartAudio.load_stream("res://不存在.ogg") == null, "不存在的音频返回 null")
	check(RhythmChartAudio.load_stream("res://x.txt") == null, "不支持的扩展名返回 null")
	check(RhythmChartAudio.load_stream("C:/nope/a.ogg") == null, "不存在的绝对路径返回 null")
