extends SceneTree
## 数据层 + 判定引擎的 headless 单测。
## 跑法：
##   godot --headless --path game --script res://tests/run_core_tests.gd
## 退出码 0 = 全过。

var passed := 0
var failed := 0


func _initialize() -> void:
	print("== RhythmChart.parse ==")
	_test_parse_defaults()
	_test_zoom_shake_preset()
	_test_unlock_frames()
	_test_parse_clamp()
	_test_parse_events()
	_test_duration_helpers()

	print("== 缓动 ==")
	_test_ease()

	print("== 参数换算 ==")
	_test_convert()
	_test_zone_events()

	print("== 判定引擎 ==")
	_test_judge_windows()
	_test_judge_zones()
	_test_judge_lane_hint()
	_test_judge_miss()
	_test_judge_hold()
	_test_judge_early_late()
	_test_parent_lanes()
	_test_judge_stats()

	print("== 谱面加载 ==")
	_test_chart_source()

	print("== 剧情文本 ==")
	_test_story_source()

	print("== 设置 ==")
	_test_settings()

	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


# --------------------------------------------------------------------------- #
# 断言
# --------------------------------------------------------------------------- #

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: " + msg)


func near(a: float, b: float, msg: String, eps := 0.001) -> void:
	if absf(a - b) <= eps:
		passed += 1
	else:
		failed += 1
		print("  FAIL: %s (got %f, want %f)" % [msg, a, b])


func eq(a, b, msg: String) -> void:
	if a == b:
		passed += 1
	else:
		failed += 1
		print("  FAIL: %s (got %s, want %s)" % [msg, str(a), str(b)])


# --------------------------------------------------------------------------- #
# parse
# --------------------------------------------------------------------------- #

func _test_parse_defaults() -> void:
	var res := RhythmChart.parse({"notes": [{"time": 0, "lane": 0}]})
	var chart: Dictionary = res["chart"]
	check(chart != null, "最小谱面能读")
	eq(chart["lanes"].size(), 4, "缺 lanes → 默认 4 轨")
	near(float(chart["lanes"][0]["speed"]), 10.0, "speed 默认 10")
	near(float(chart["lanes"][0]["length"]), 10.0, "length 默认 10")
	near(float(chart["lanes"][0]["alpha"]), 0.0, "alpha 默认 0")
	eq(str(chart["lanes"][0]["judge_zone"]), "none", "judge_zone 默认 none")
	eq(str(chart["notes"][0]["type"]), "tap", "音符 type 默认 tap")
	eq(int(chart["notes"][0]["lane"]), 0, "lane 0")
	check(RhythmChart.parse("not a dict")["chart"] == null, "非对象 → chart = null")
	check(RhythmChart.parse({"format": "rstory", "scenes": []})["chart"] == null,
		"故事板不能被当作空谱面导入")
	eq(RhythmChart.parse({"notes": [{"time": 1.0, "lane": 0, "type": "hold", "duration": 0}]})["chart"]["notes"][0]["type"], "tap", "duration<=0 的 hold → tap")
	eq(RhythmChart.parse({"notes": [{"time": 0, "lane": 0, "type": "bogus"}]})["chart"]["notes"].size(), 0, "未知 type（flick / mine 等）→ 直接丢掉")


func _test_parse_clamp() -> void:
	var raw := {
		"lanes": [
			{"judge_zone": "bogus", "alpha": 150, "speed": -5, "length": 500,
				"rotation": 9999, "x": 5000, "y": -5000, "color": "nope"},
			{},
			{},
			{},
		],
		"notes": [
			{"time": 3.0, "lane": 0, "type": "tap"},
			{"time": 1.0, "lane": 1, "type": "tap"},
			{"time": -2.0, "lane": 9, "type": "tap"},
		],
	}
	var chart: Dictionary = RhythmChart.parse(raw)["chart"]
	var lane: Dictionary = chart["lanes"][0]
	eq(str(lane["judge_zone"]), "none", "judge_zone 写错 → none")
	near(float(lane["alpha"]), 100.0, "alpha 夹到 100")
	near(float(lane["speed"]), 0.0, "speed 夹到 0")
	near(float(lane["length"]), 100.0, "length 夹到 100")
	near(float(lane["rotation"]), 3600.0, "rotation 夹到 3600")
	near(float(lane["x"]), 2000.0, "x 夹到 2000")
	near(float(lane["y"]), -2000.0, "y 夹到 -2000")
	eq(str(lane["color"]), "#ffffff", "非法颜色 → 白")

	var notes: Array = chart["notes"]
	eq(notes.size(), 3, "音符数量")
	# 排序后：time 0（负时间被夹到 0、lane 9 被夹到 3）→ 1.0 → 3.0
	eq(int(notes[0]["lane"]), 3, "lane 越界夹到 3")
	near(float(notes[0]["time"]), 0.0, "负时间 → 0")
	eq(int(notes[1]["lane"]), 1, "先按 time 排序")
	near(float(notes[1]["time"]), 1.0, "排序后的第二个音符")
	eq(int(notes[2]["lane"]), 0, "time 3.0 排最后")

	# 16 轨上限
	var many: Array = []
	for i in 40:
		many.append({})
	eq(RhythmChart.parse({"lanes": many})["chart"]["lanes"].size(), 16, "轨数上限 16")


func _test_parse_events() -> void:
	var raw := {
		"lanes": [{
			"x": 10.0,
			"events": {
				"x": [
					{"start": 7.0, "end": 9.0, "ease": "outCubic", "from": 0, "to": 10},
					{"start": 1.0, "end": 3.0, "ease": "linear", "from": 0, "to": 100},
					{"start": 5.0, "end": 5.0, "ease": "linear", "from": 0, "to": -50},
				],
				"alpha": "not an array",
			},
		}],
		"notes": [],
	}
	var chart: Dictionary = RhythmChart.parse(raw)["chart"]
	var lane: Dictionary = chart["lanes"][0]
	eq(lane["events"]["x"].size(), 3, "事件读入")
	near(float(lane["events"]["x"][0]["start"]), 1.0, "事件按 start 排序")
	eq(lane["events"].get("alpha", []).size(), 0, "不是数组的通道忽略")

	near(float(RhythmChart.lane_params_at(lane, 0.5)["x"]), 10.0, "事件开始前用静态值")
	near(float(RhythmChart.lane_params_at(lane, 2.0)["x"]), 50.0, "事件中间线性插值")
	near(float(RhythmChart.lane_params_at(lane, 4.0)["x"]), 100.0, "事件结束保持尾值")
	near(float(RhythmChart.lane_params_at(lane, 6.0)["x"]), -50.0, "零时长事件 = 瞬间跳变")
	near(float(RhythmChart.lane_params_at(lane, 8.0)["x"]), 8.75, "outCubic(0.5) = 0.875")
	near(float(RhythmChart.lane_params_at(lane, 2.0)["y"]), 0.0, "没事件的通道保持静态值")

	# 事件 end < start → end 夹到 start
	var chart2: Dictionary = RhythmChart.parse({"lanes": [{"x": 0, "events": {
		"x": [{"start": 2.0, "end": 1.0, "ease": "linear", "from": 0, "to": 40}]}}]})["chart"]
	near(float(RhythmChart.lane_params_at(chart2["lanes"][0], 5.0)["x"]), 40.0, "end<start → 零时长")


func _test_duration_helpers() -> void:
	var chart: Dictionary = RhythmChart.parse({
		"notes": [
			{"time": 1.0, "lane": 0},
			{"time": 2.0, "lane": 1, "type": "hold", "duration": 1.5},
			{"time": 3.0, "lane": 2, "type": "flick"},      # 不支持的类型，解析时会被丢掉
		],
		"lanes": [{}, {}, {}, {}],
	})["chart"]
	near(RhythmChart.chart_duration(chart), 3.5, "chart_duration 算到 hold 尾部")
	eq(RhythmChart.judgeable_count(chart), 2, "不支持的 flick 会被丢掉，只剩 2 颗")
	near(RhythmChart.note_end(chart["notes"][1]), 3.5, "note_end")


# --------------------------------------------------------------------------- #
# 缓动
# --------------------------------------------------------------------------- #

func _test_ease() -> void:
	near(RhythmChart.ease_at("linear", 0.5), 0.5, "linear", 0.0001)
	near(RhythmChart.ease_at("step", 0.5), 0.0, "step(0.5)", 0.0001)
	near(RhythmChart.ease_at("step", 1.0), 1.0, "step(1)", 0.0001)
	near(RhythmChart.ease_at("inQuad", 0.5), 0.25, "inQuad", 0.0001)
	near(RhythmChart.ease_at("outQuad", 0.5), 0.75, "outQuad", 0.0001)
	near(RhythmChart.ease_at("inOutCubic", 0.5), 0.5, "inOutCubic", 0.0001)
	near(RhythmChart.ease_at("outBack", 0.5), 1.0877, "outBack 冲过头", 0.002)
	near(RhythmChart.ease_at("bezier(0.25, 0.1, 0.25, 1)", 0.5), 0.8024, "bezier ≈ 0.802", 0.002)
	near(RhythmChart.ease_at("unknownEase", 0.3), 0.3, "未知缓动 → linear", 0.0001)
	check(RhythmChart.is_known_ease("bezier(0.1,0.2,0.3,0.4)"), "bezier 算已知缓动")


# --------------------------------------------------------------------------- #
# 参数换算
# --------------------------------------------------------------------------- #

func _test_convert() -> void:
	near(RhythmChart.alpha_value({"alpha": 50}), 0.5, "alpha 50 → 0.5")
	near(RhythmChart.speed_mult({"speed": 10}), 1.0, "speed 10 → 1.0×")
	near(RhythmChart.speed_mult({"speed": 20}), 4.0, "speed 20 → 4.0×")
	near(RhythmChart.speed_mult({"speed": 100}), 100.0, "speed 100 → 100×")
	near(RhythmChart.speed_mult({}), 1.0, "speed 默认 → 1.0×")
	near(RhythmChart.length_scale({"length": 10}), 1.0, "length 10 → 1.0")
	near(RhythmChart.length_scale({"length": 0}), 0.0, "length 0 → 0")
	near(RhythmChart.length_scale({}), 1.0, "length 默认 → 1.0")

	eq(RhythmChart.display_color({"judge_zone": "left"}).to_html(false), "b06bff", "left 紫")
	eq(RhythmChart.display_color({"judge_zone": "right"}).to_html(false), "ffd166", "right 黄")
	eq(RhythmChart.display_color({"judge_zone": "none", "color": "#ff0000"}).to_html(false), "ff0000", "none 用轨道色")
	eq(RhythmChart.display_color({"judge_zone": "none", "color": "bad"}).to_html(false), "ffffff", "非法色 → 白")
	eq(RhythmChart.lane_keys({"judge_zone": "left"}), ["A", "S", "D", "F"], "left 键位")
	eq(RhythmChart.lane_keys({"judge_zone": "none"}).size(), 8, "none 任意 8 键")

	# hold 的流速回退（和 core.js 的 holdSpeed 一致）
	var speed_lane: Dictionary = RhythmChart.parse({
		"lanes": [{
			"speed": 0,
			"events": {"speed": [
				{"start": 0.0, "end": 2.0, "ease": "linear", "from": 10, "to": 0},
			]},
		}],
	})["chart"]["lanes"][0]
	near(RhythmChart.hold_speed_mult(speed_lane, 1.0), 0.25, "hold 流速跟着事件走（5²/100）")
	near(RhythmChart.hold_speed_mult(speed_lane, 2.5), 1.0, "流速 0 时回退到最近的非零流速")
	var zero_lane: Dictionary = RhythmChart.parse({"lanes": [{"speed": 0}]})["chart"]["lanes"][0]
	near(RhythmChart.hold_speed_mult(zero_lane, 1.0), 1.0, "全篇 0 流速时回退到 1.0×")

	# 开场倒计时跑的是负时间（LEAD_IN），那时还没有任何事件开始：
	# 必须按第一条关键帧的 from 往前外推，否则 16 条轨道会全叠在舞台正中、流速退回 1×。
	var countdown_lane: Dictionary = RhythmChart.parse({"lanes": [{
		"x": 0, "speed": 10, "alpha": 0,
		"events": {
			"x": [{"start": 0.0, "end": 0.5, "ease": "linear", "from": -45, "to": -45}],
			"speed": [{"start": 0.0, "end": 0.5, "ease": "linear", "from": 20, "to": 20}],
			"alpha": [{"start": 0.0, "end": 0.5, "ease": "linear", "from": 100, "to": 100}],
		},
	}]})["chart"]["lanes"][0]
	var p_neg := RhythmChart.lane_params_at(countdown_lane, -1.5)
	near(float(p_neg["x"]), -45.0, "倒计时（t<0）按第一条关键帧外推 x，而不是静态 0")
	near(float(p_neg["speed"]), 20.0, "倒计时（t<0）按第一条关键帧外推流速，而不是静态 10")
	near(float(p_neg["alpha"]), 100.0, "倒计时（t<0）按第一条关键帧外推 alpha")
	var p_pos := RhythmChart.lane_params_at(countdown_lane, 1.0)
	near(float(p_pos["x"]), -45.0, "事件结束后沿用 to（t≥0 的行为不变）")


# --------------------------------------------------------------------------- #
# 判定区事件（zone 通道）
# --------------------------------------------------------------------------- #

func _test_zone_events() -> void:
	var raw := {"lanes": [{
		"judge_zone": "none", "color": "#ffffff",
		"events": {"zone": [
			{"start": 0.0, "end": 1.0, "ease": "linear", "from": 1, "to": 1},
			{"start": 2.0, "end": 3.0, "ease": "linear", "from": 1, "to": 2},
			{"start": 4.0, "end": 5.0, "ease": "linear", "from": 2, "to": 0},
		]},
	}], "notes": []}
	var lane: Dictionary = RhythmChart.parse(raw)["chart"]["lanes"][0]
	eq(lane["events"]["zone"].size(), 3, "zone 事件读入")
	eq(RhythmChart.lane_zone_at(lane, 0.5), "left", "zone=1 → left")
	eq(RhythmChart.lane_zone_at(lane, 1.5), "left", "zone 事件结束保持尾值")
	eq(RhythmChart.lane_zone_at(lane, 2.5), "right", "zone 插值 1.5 → 四舍五入到 right")
	eq(RhythmChart.lane_zone_at(lane, 4.5), "left", "zone 插值 2→0 中间 → left")
	eq(RhythmChart.lane_zone_at(lane, 6.0), "none", "zone 回到 0 → none")
	eq(RhythmChart.display_color_at(lane, 2.5).to_html(false), "ffd166", "zone 变了颜色跟着变")
	eq(RhythmChart.display_color_at(lane, 6.0).to_html(false), "ffffff", "none 时用轨道自己的颜色")

	var static_lane: Dictionary = RhythmChart.parse({"lanes": [{"judge_zone": "left"}]})["chart"]["lanes"][0]
	eq(RhythmChart.lane_zone_at(static_lane, 3.0), "left", "没有 zone 事件时用静态判定区")
	eq(RhythmChart.display_color_at(static_lane, 3.0).to_html(false), "b06bff", "静态 left 的紫色")

	# 判定也跟着 zone 事件走
	var chart: Dictionary = RhythmChart.parse({
		"lanes": [
			{"judge_zone": "none", "events": {"zone": [
				{"start": 0.0, "end": 0.1, "ease": "linear", "from": 1, "to": 1},
				{"start": 1.5, "end": 1.6, "ease": "linear", "from": 2, "to": 2},
			]}},
			{}, {}, {},
		],
		"notes": [{"time": 1.0, "lane": 0}, {"time": 2.0, "lane": 0}],
	})["chart"]
	var j := RhythmJudge.new()
	j.setup(chart, 1.0)
	check(not bool(j.press("right", 1.0)["hit"]), "zone=left 时不接受右键")
	check(bool(j.press("left", 1.0)["hit"]), "zone=left 时接受左键")
	check(bool(j.press("right", 2.0)["hit"]), "zone 切到 right 后接受右键")


# --------------------------------------------------------------------------- #
# 判定
# --------------------------------------------------------------------------- #

func _make_chart(notes: Array, lanes: Array = []) -> Dictionary:
	var raw := {"notes": notes}
	if lanes.is_empty():
		raw["lanes"] = [
			{"judge_zone": "none"}, {"judge_zone": "none"},
			{"judge_zone": "none"}, {"judge_zone": "none"},
		]
	else:
		raw["lanes"] = lanes
	return RhythmChart.parse(raw)["chart"]


func _new_judge(chart: Dictionary, scale := 1.0) -> RhythmJudge:
	var judge := RhythmJudge.new()
	judge.setup(chart, scale)
	return judge


func _test_judge_windows() -> void:
	var chart := _make_chart([{"time": 1.0, "lane": 0}])
	var j := _new_judge(chart)
	var r := j.press("left", 1.04)
	check(bool(r["hit"]), "按得到音符")
	eq(str(r["result"]), "perfect_plus", "40ms → Perfect+")
	eq(int(j.counts["perfect_plus"]), 1, "Perfect+ 计数")
	eq(j.combo, 1, "连击 1")
	near(j.score, 1010000.0, "单个 Perfect+ = 满分 1,010,000", 0.5)

	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart)
	r = j.press("left", 1.07)
	eq(str(r["result"]), "perfect", "70ms → Perfect")
	near(j.score, 1000000.0, "单个 Perfect = 1,000,000", 0.5)
	near(j.accuracy_live(), 1.0, "Perfect 权重 100%")

	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart)
	r = j.press("left", 1.12)
	eq(str(r["result"]), "good", "120ms → Good")
	near(j.score, 750000.0, "单个 Good = 750,000", 0.5)
	near(j.accuracy_live(), 0.75, "Good 权重 75%")

	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart)
	r = j.press("left", 1.2)
	eq(str(r["result"]), "bad", "200ms → Bad（140~220ms）")

	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart)
	r = j.press("left", 1.15)
	eq(str(r["result"]), "bad", "150ms → Bad（Good 只到 140ms）")
	near(j.score, 0.0, "Bad 不给分", 0.5)
	near(j.accuracy_live(), 0.0, "Bad 权重 0%")
	check(not j.is_full_combo(), "有 Bad 不算 FC")

	# Bad 断连：先打一个 Perfect，再打一个 Bad
	chart = _make_chart([{"time": 1.0, "lane": 0}, {"time": 2.0, "lane": 0}])
	j = _new_judge(chart)
	j.press("left", 1.0)
	eq(j.combo, 1, "Perfect 连击 1")
	j.press("left", 2.2)
	eq(int(j.counts["bad"]), 1, "200ms 记 Bad")
	eq(j.combo, 0, "Bad 断连")

	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart)
	r = j.press("left", 1.25)
	check(not bool(r["hit"]), "超过 220ms → 空打")
	eq(str(r["kind"]), "empty", "空打 kind")

	# 窗口倍率
	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart, 2.0)
	r = j.press("left", 1.4)
	eq(str(r["result"]), "bad", "窗口 2× 时 400ms 还能打到（bad）")


func _test_judge_zones() -> void:
	var lanes := [
		{"judge_zone": "left"}, {"judge_zone": "right"},
		{"judge_zone": "none"}, {},
	]
	var chart := _make_chart([{"time": 1.0, "lane": 0}, {"time": 2.0, "lane": 1}, {"time": 3.0, "lane": 2}], lanes)
	var j := _new_judge(chart)
	check(not bool(j.press("right", 1.0)["hit"]), "left 轨道不吃右边键")
	check(bool(j.press("left", 1.0)["hit"]), "left 轨道吃左边键")
	check(bool(j.press("right", 2.0)["hit"]), "right 轨道吃右边键")
	check(bool(j.press("left", 3.0)["hit"]), "none 轨道任意键都吃")

	# 同一时刻多轨：取 |dt| 最小的
	var chart2 := _make_chart([
		{"time": 1.0, "lane": 0}, {"time": 1.04, "lane": 1},
	], [{"judge_zone": "none"}, {"judge_zone": "none"}, {}, {}])
	var j2 := _new_judge(chart2)
	var r := j2.press("left", 1.03)
	eq(int(r["note"]["lane"]), 1, "两条 none 轨道取最近的")


func _test_judge_lane_hint() -> void:
	# 同区相邻音符：带 lane_hint 时两下分别命中各自轨道（自动演示用，防止互相抢判）
	var lanes := [{"judge_zone": "none"}, {"judge_zone": "none"}, {}, {}]
	var chart := _make_chart([
		{"time": 1.0, "lane": 0}, {"time": 1.001, "lane": 1},
	], lanes)
	var j := _new_judge(chart)
	var r1 := j.press("left", 1.001, 0)
	eq(int(r1["note"]["lane"]), 0, "带 lane_hint 优先命中指定轨道")
	var r2 := j.press("left", 1.001, 1)
	eq(int(r2["note"]["lane"]), 1, "第二下命中另一条轨道")
	eq(int(j.counts["miss"]), 0, "两颗都命中、没有 miss")


func _test_judge_miss() -> void:
	var chart := _make_chart([{"time": 1.0, "lane": 0}, {"time": 2.0, "lane": 1}])
	var j := _new_judge(chart)
	j.update(1.25)
	eq(int(j.counts["miss"]), 1, "超时自动 miss")
	eq(int(j.counts["perfect"]), 0, "miss 不计 perfect")
	eq(j.combo, 0, "miss 断连击")
	j.update(2.3)
	eq(int(j.counts["miss"]), 2, "第二个也 miss")
	near(j.accuracy_final(), 0.0, "全 miss 准确率 0")


func _test_judge_hold() -> void:
	var chart := _make_chart([{"time": 1.0, "lane": 0, "type": "hold", "duration": 1.0}])
	var j := _new_judge(chart)
	var completed := [0]
	j.hold_completed.connect(func(_n): completed[0] += 1)

	j.set_pressed_zones(["left"])
	var r := j.press("left", 1.0)
	eq(str(r["kind"]), "hold", "hold 头判")
	eq(int(j.counts["perfect_plus"]), 1, "头判先记 Perfect+")
	j.update(1.6)
	eq(completed[0], 0, "还没到尾部不完成")
	j.update(2.05)
	eq(completed[0], 1, "按住到尾部 → 完成")
	eq(int(j.counts["miss"]), 0, "完成时不是 miss")

	# 中途松开 = 断
	var chart2 := _make_chart([{"time": 1.0, "lane": 0, "type": "hold", "duration": 1.0}])
	var j2 := _new_judge(chart2)
	var broken := [0]
	j2.hold_broken.connect(func(_n): broken[0] += 1)
	j2.set_pressed_zones(["left"])
	j2.press("left", 1.0)
	j2.set_pressed_zones([])
	j2.update(1.3)
	eq(broken[0], 1, "松开 → break")
	eq(int(j2.counts["miss"]), 1, "断 hold 记 miss")
	eq(int(j2.counts["perfect_plus"]), 0, "断 hold 撤掉 Perfect+")
	near(j2.score, 0.0, "断 hold 退分")
	eq(j2.judged_count, 1, "断 hold 仍算一个已判定音符")
	near(j2.accuracy_live(), 0.0, "只有断 hold 时实时准确率为 0")
	j2.update(3.0)
	eq(j2.judged_count, 1, "断 hold 不重复计数")

	var mixed := _make_chart([
		{"time": 1.0, "lane": 0, "type": "hold", "duration": 1.0},
		{"time": 1.0, "lane": 1},
	])
	var jm := _new_judge(mixed)
	jm.press("left", 1.0, 0)
	jm.press("left", 1.0, 1)
	jm.set_pressed_zones([])
	jm.finish(1.5)
	eq(jm.judged_count, 2, "收尾断 hold 后已判定总数不变")
	near(jm.accuracy_live(), 0.5, "命中一颗、断一颗的实时准确率为 50%")
	near(jm.accuracy_live(), jm.accuracy_final(), "收尾后实时准确率和结算一致")

	# 换手 / 换边：头判按左键，之后只按右键，hold 照样继续
	var lanes4 := [{"judge_zone": "left"}, {}, {}, {}]
	var chart4 := _make_chart([{"time": 1.0, "lane": 0, "type": "hold", "duration": 1.0}], lanes4)
	var j4 := _new_judge(chart4)
	var done4 := [0]
	j4.hold_completed.connect(func(_n): done4[0] += 1)
	j4.set_pressed_zones(["left"])
	var r4 := j4.press("left", 1.0)
	eq(str(r4["kind"]), "hold", "换手：头判命中")
	j4.set_pressed_zones(["right"])          # 左键松开、只按右键
	j4.update(1.5)
	eq(int(j4.counts["miss"]), 0, "只按另一边不算断")
	j4.update(2.05)
	eq(done4[0], 1, "换手后按到尾部 → 照样完成")

	# hold 头判超时没按 → miss（不是留着）
	var chart3 := _make_chart([{"time": 1.0, "lane": 0, "type": "hold", "duration": 1.0}])
	var j3 := _new_judge(chart3)
	j3.update(1.3)
	eq(int(j3.counts["miss"]), 1, "hold 头判漏按 → miss")


func _test_judge_early_late() -> void:
	var chart := _make_chart([
		{"time": 1.0, "lane": 0}, {"time": 2.0, "lane": 0},
		{"time": 3.0, "lane": 0}, {"time": 4.0, "lane": 0},
	])
	var j := _new_judge(chart)
	j.press("left", 0.93)      # 早 70ms → Perfect Early（≤55ms 是 Perfect+，不记 Early/Late）
	j.press("left", 2.07)      # 晚 70ms → Perfect Late
	j.press("left", 2.90)      # 早 100ms → Good Early
	j.press("left", 4.12)      # 晚 120ms → Good Late
	eq(int(j.early_late["perfect_early"]), 1, "Perfect Early 计数")
	eq(int(j.early_late["perfect_late"]), 1, "Perfect Late 计数")
	eq(int(j.early_late["good_early"]), 1, "Good Early 计数")
	eq(int(j.early_late["good_late"]), 1, "Good Late 计数")

	# hold 断开时要把头判那一次撤掉（否则 Early/Late 会比实际判定多）
	var hold_chart := _make_chart([{"time": 1.0, "lane": 0, "type": "hold", "duration": 1.0}])
	var j2 := _new_judge(hold_chart)
	j2.set_pressed_zones(["left"])
	j2.press("left", 1.07)
	eq(int(j2.early_late["perfect_late"]), 1, "hold 头判 late 计入")
	j2.set_pressed_zones([])
	j2.update(1.2)
	eq(int(j2.early_late["perfect_late"]), 0, "hold 断开后撤销 late 计数")


func _test_parent_lanes() -> void:
	# 解析：静态 parent（0 起）+ parent 事件通道（0 = 不跟、i+1 = 轨道 i）
	var chart: Dictionary = RhythmChart.parse({
		"lanes": [
			{"name": "Main"},
			{"name": "Sub", "x": -60, "events": {"parent": [
				{"start": 0, "end": 0, "ease": "linear", "from": 1, "to": 1},
			]}},
			{"name": "Free"},
		],
		"notes": [], "stage": {"lane_count": 3},
	})["chart"]
	var lanes: Array = chart["lanes"]
	eq(RhythmChart.lane_parent_at(lanes[1], 0.0, 3), 0, "parent 事件 1 → 挂在轨道 0")
	eq(RhythmChart.lane_parent_at(lanes[2], 0.0, 3), -1, "没有父线 = -1")

	var cancel_lane := {
		"parent": 0,
		"events": {"parent": [
			{"start": 0, "end": 0, "ease": "linear", "from": 2, "to": 2},
			{"start": 1, "end": 1, "ease": "linear", "from": 0, "to": 0},
		]},
	}
	eq(RhythmChart.lane_parent_at(cancel_lane, 0.5, 3), 1, "事件值 2 → 轨道 1")
	eq(RhythmChart.lane_parent_at(cancel_lane, 1.5, 3), -1, "放一条 0 就取消父线")
	eq(RhythmChart.lane_parent_at({"parent": 9}, 0.0, 3), -1, "父线越界当没有")

	# 坐标系：父线转 90° 时，子线 x 沿父线横向 → 变成竖直方向
	var rot_chart: Dictionary = RhythmChart.parse({
		"lanes": [
			{"name": "Main", "rotation": 90},
			{"name": "Sub", "x": -60, "rotation": 15, "parent": 0},
		],
		"notes": [], "stage": {"lane_count": 2},
	})["chart"]
	var f := RhythmChart.lane_frame_at(rot_chart["lanes"], 1, 0.0)
	near(f["x"], 0.0, "父线转 90°：子线横向偏移转到竖轴", 0.001)
	near(f["y"], 60.0, "子线 x=-60 变成向上 60", 0.001)
	near(f["rot"], 105.0, "子线角度 = 父线 + 自己（90+15）", 0.001)

	# 环：A→B→A 不能卡死，成环那条当没有父线
	var cycle: Dictionary = RhythmChart.parse({
		"lanes": [{"name": "A", "parent": 1}, {"name": "B", "parent": 0}],
		"notes": [], "stage": {"lane_count": 2},
	})["chart"]
	var cf := RhythmChart.lane_frame_at(cycle["lanes"], 0, 0.0)
	check(cf.has("x") and cf.has("rot"), "父线成环也能算出坐标系")

func _test_judge_stats() -> void:
	var chart := _make_chart([
		{"time": 1.0, "lane": 0}, {"time": 1.2, "lane": 1},
		{"time": 1.4, "lane": 2}, {"time": 1.6, "lane": 3},
	])
	var j := _new_judge(chart)
	eq(j.total_judgeable, 4, "可判定数")
	j.press("left", 1.0)
	j.press("left", 1.2)
	near(j.accuracy_live(), 1.0, "实时准确率只看已判定")
	eq(j.max_combo, 2, "最大连击")
	j.update(1.9)
	near(j.accuracy_final(), 0.5, "2/4 → 50%")
	check(not j.is_full_combo(), "有 miss 不算 FC")
	check(not j.is_all_perfect(), "不是 AP")

	# 全 perfect
	var chart2 := _make_chart([{"time": 1.0, "lane": 0}, {"time": 1.2, "lane": 1}])
	var j2 := _new_judge(chart2)
	j2.press("left", 1.0)
	j2.press("left", 1.2)
	check(j2.is_full_combo(), "全 perfect → FC")
	check(j2.is_all_perfect(), "全 perfect → AP")
	eq(j2.grade(), "S", "AP 评级 S")

	# finish 把剩下的音符结掉
	var chart3 := _make_chart([{"time": 1.0, "lane": 0}, {"time": 9.0, "lane": 1}])
	var j3 := _new_judge(chart3)
	j3.press("left", 1.0)
	j3.finish(3.0)
	eq(int(j3.counts["miss"]), 1, "finish 补漏打")
	near(j3.accuracy_final(), 0.5, "finish 后准确率")


# --------------------------------------------------------------------------- #
# 加载
# --------------------------------------------------------------------------- #

func _test_chart_source() -> void:
	eq(ChartSource._zip_find(["assets/song.wav", "song.wav"], "song.wav"), "song.wav",
		"ZIP 同名媒体优先匹配完整路径")
	eq(ChartSource._zip_find(["other/song.wav", "music/song.wav"], "music/song.wav"), "music/song.wav",
		"ZIP 子目录媒体使用谱面指定路径")
	eq(ChartSource._zip_find(["wrapped/song.wav"], "song.wav"), "wrapped/song.wav",
		"ZIP 媒体仍可按文件名兜底")
	# 造一个临时的「文件夹谱面」再扫出来（跑完删掉，不往项目里塞谱面）
	var dir := "user://charts/_unit_test_folder"
	DirAccess.make_dir_recursive_absolute(dir)
	var raw := {
		"format": "rchart",
		"meta": {"title": "Unit Folder", "artist": "unit", "illustrator": "Unit Painter", "difficulty": "EASY", "level": 2},
		"audio": {"file": "song.wav", "offset": 0.0},
		"lanes": [{"judge_zone": "left", "alpha": 100}, {}, {}, {}],
		"notes": [{"time": 1.0, "lane": 0}, {"time": 1.5, "lane": 1, "type": "hold", "duration": 0.4}],
	}
	var chart_file := FileAccess.open(dir + "/chart.json", FileAccess.WRITE)
	check(chart_file != null, "写临时谱面")
	if chart_file == null:
		return
	chart_file.store_string(JSON.stringify(raw))
	chart_file.close()
	var wav_file := FileAccess.open(dir + "/song.wav", FileAccess.WRITE)
	wav_file.store_buffer(FileAccess.get_file_as_bytes("res://audio/hit.wav"))
	wav_file.close()

	var entries := ChartSource.scan(["user://charts"])
	var folder_entry := _find_entry(entries, "Unit Folder")
	check(not folder_entry.is_empty(), "扫描到文件夹谱面")
	if not folder_entry.is_empty():
		eq(str(folder_entry["kind"]), "folder", "文件夹类型")
		check(bool(folder_entry["has_audio"]), "文件夹谱面有音频")
		eq(int(folder_entry["note_count"]), 2, "文件夹谱面音符数")
		eq(str(folder_entry["illustrator"]), "Unit Painter", "扫描带上曲绘作者")
		eq(str(folder_entry["chart"]["meta"]["illustrator"]), "Unit Painter", "解析后的 meta 带曲绘作者")
		var loaded := ChartSource.load_entry(folder_entry)
		check(loaded["chart"] != null, "加载文件夹谱面")
		check(loaded["stream"] is AudioStream, "加载音频流")
		check(loaded["cover"] == null, "没有曲绘时返回 null")
		eq(loaded["errors"].size(), 0, "加载无错误")

	# zip 路径（用 ZIPPacker 真打一个包）
	var zip_path := "user://_unit_test_pack.zip"
	DirAccess.make_dir_recursive_absolute("user://")
	var packer := ZIPPacker.new()
	if packer.open(zip_path) != OK:
		check(false, "创建测试 zip")
		return
	var mini := {
		"format": "rchart", "version": 3,
		"meta": {"title": "Zip Test", "artist": "unit", "difficulty": "EASY", "level": 3},
		"audio": {"file": "hit.wav", "offset": 0.0},
		"lanes": [{"judge_zone": "left", "alpha": 100}, {}, {}, {}],
		"notes": [{"time": 0.5, "lane": 0}, {"time": 1.0, "lane": 1, "type": "hold", "duration": 0.5}],
	}
	packer.start_file("chart.json")
	packer.write_file(JSON.stringify(mini).to_utf8_buffer())
	packer.close_file()
	packer.start_file("hit.wav")
	packer.write_file(FileAccess.get_file_as_bytes("res://audio/hit.wav"))
	packer.close_file()
	packer.close()

	var zip_entries := ChartSource.scan(["user://"])
	var zip_entry := {}
	for e in zip_entries:
		if str(e["title"]) == "Zip Test":
			zip_entry = e
	check(not zip_entry.is_empty(), "扫描到 zip 谱面")
	if not zip_entry.is_empty():
		eq(str(zip_entry["kind"]), "zip", "zip 类型")
		var zip_loaded := ChartSource.load_entry(zip_entry)
		check(zip_loaded["chart"] != null, "zip 里读谱面")
		check(zip_loaded["stream"] is AudioStream, "zip 里读音频")
		eq(zip_loaded["chart"]["notes"].size(), 2, "zip 音符数量")

	# 清理临时文件
	_remove_path(dir + "/chart.json")
	_remove_path(dir + "/song.wav")
	_remove_path(dir)
	_remove_path(zip_path)


func _remove_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	elif DirAccess.dir_exists_absolute(path):
		DirAccess.remove_absolute(path)


# --------------------------------------------------------------------------- #
# 剧情文本
# --------------------------------------------------------------------------- #

func _test_story_source() -> void:
	# 排版约定：标题行 / 小标题 / 分隔线 / 空行分段
	var info := StorySource.parse(
		"标题：雪线之下\n# 第一章 相遇\n第一行\n第二行\n\n第二段。\n---\n【尾声】\n结束。",
		"01_随便.txt")
	eq(str(info["title"]), "雪线之下", "首行「标题：」当标题")
	eq(int(info["chapters"]), 2, "小标题数量（# 与【】）")
	eq(int(info["paragraphs"]), 3, "段落数")
	var blocks: Array = info["blocks"]
	eq(blocks.size(), 6, "排版块数量（2 小标题 + 3 段 + 1 分隔线）")
	if blocks.size() >= 2:
		eq(str(blocks[0]["kind"]), "chapter", "第一块是小标题")
		eq(str(blocks[1]["text"]), "第一行第二行", "中文按行折行的文本直接接上")
	eq(str(info["excerpt"]), "第一行第二行", "列表摘要取第一段")
	eq(int(info["minutes"]), 1, "短篇阅读时长至少 1 分钟")

	# 没写标题就落到文件名，开头编号自动去掉
	eq(str(StorySource.parse("正文。", "02_第二章 回声.txt")["title"]), "第二章 回声", "标题回落到文件名")
	eq(StorySource._title_from_file("123 - 无名.txt"), "无名", "文件名开头的编号被去掉")
	eq(str(StorySource.parse("hello\nworld", "a.txt")["blocks"][0]["text"]), "hello world", "英文断行补一个空格")

	# 一行一段：句号 / 问号结尾的行自己成段，没写完的行才接下一行
	var one_line := StorySource.parse(
		"便利店自动门开合，却少了那声“叮咚”。\n\n天台。星星还在。\n不对，一直都这么安静吗？\n这是硬折\n的一行没有句号", "x.txt")
	eq(int(one_line["paragraphs"]), 4, "句号 / 问号结尾的行各自成段")
	eq((one_line["blocks"] as Array).size(), 4, "四段四个块")
	eq(str(one_line["blocks"][2]["text"]), "不对，一直都这么安静吗？", "短句单独成段")
	eq(str(one_line["blocks"][3]["text"]), "这是硬折的一行没有句号", "没写完的行接到同一段")

	# 编码：UTF-8 BOM / UTF-16LE（记事本的「Unicode」）/ GBK（读不了要有标记）
	var bom := PackedByteArray([0xEF, 0xBB, 0xBF]) + "标题：甲\n正文。".to_utf8_buffer()
	var bom_info := StorySource.parse_bytes(bom, "bom.txt")
	eq(str(bom_info["title"]), "甲", "UTF-8 BOM 能读")
	check(bool(bom_info["utf8_ok"]), "UTF-8 BOM 不标记编码异常")

	var wide := PackedByteArray([0xFF, 0xFE])
	var wide_text := "标题：乙\n正文。"
	for i in wide_text.length():
		var code := wide_text.unicode_at(i)
		wide.append(code & 0xFF)
		wide.append((code >> 8) & 0xFF)
	var wide_info := StorySource.parse_bytes(wide, "wide.txt")
	eq(str(wide_info["title"]), "乙", "UTF-16LE 能读")
	check(bool(wide_info["utf8_ok"]), "UTF-16 不算编码异常")

	check(not bool(StorySource.decode(PackedByteArray([0xC4, 0xE3, 0xBA, 0xC3, 0xA1, 0xA3]))["utf8_ok"]),
		"GBK / ANSI 文本被标记成编码异常")

	# 扫描：只收 .txt（子目录也认），并且读得回正文
	var root := "user://剧情"
	var sub := root.path_join("_core_test")
	DirAccess.make_dir_recursive_absolute(sub)
	var story_file := sub.path_join("01_临时剧情.txt")
	var note_file := sub.path_join("说明.md")
	var fh := FileAccess.open(story_file, FileAccess.WRITE)
	fh.store_string("标题：临时剧情\n这里只有一行正文。")
	fh.close()
	fh = FileAccess.open(note_file, FileAccess.WRITE)
	fh.store_string("# 不是剧情")
	fh.close()

	var entries := StorySource.scan([root])
	var found := {}
	for entry in entries:
		if str(entry.get("file", "")) == "01_临时剧情.txt":
			found = entry
		elif str(entry.get("file", "")) == "说明.md":
			check(false, "非 .txt 不该被当成剧情")
	check(not found.is_empty(), "user:// 里的 txt 被扫到")
	eq(str(found.get("title", "")), "临时剧情", "扫描时就读出标题")
	eq(str(found.get("folder", "")), "_core_test", "子文件夹名记进 folder（序章 / 第一章 那种分组）")
	check(int(found.get("chars", 0)) > 0, "扫描时就算出字数")
	var loaded := StorySource.read_story(found)
	check(bool(loaded.get("ok", false)), "read_story 读得到")
	check((loaded.get("blocks", []) as Array).size() > 0, "read_story 返回正文块")

	# 拖拽导入：拷进 user://剧情，读完清理
	var imported := StorySource.import_file(ProjectSettings.globalize_path(story_file))
	check(bool(imported.get("ok", false)), "import_file 接收 .txt")
	check(FileAccess.file_exists(root.path_join("01_临时剧情.txt")), "导入落到 user://剧情")
	check(not bool(StorySource.import_file(ProjectSettings.globalize_path(note_file)).get("ok", false)), "import_file 拒绝 .md")

	_remove_path(root.path_join("01_临时剧情.txt"))
	for path in [story_file, note_file]:
		_remove_path(path)
	_remove_path(sub)
	check(not FileAccess.file_exists(story_file), "临时剧情已清理")


# --------------------------------------------------------------------------- #
# 设置
# --------------------------------------------------------------------------- #

func _test_settings() -> void:
	var original := AppSettings.load_settings()
	var s := AppSettings.new()
	eq(int(s.hit_fx), 2, "打击特效默认「强」")
	check(s.hit_sound, "打击音默认开")
	near(s.hit_volume, 0.6, "打击音音量默认 60%")

	s.hit_fx = 0
	s.hit_sound = false
	s.hit_volume = 0.35
	s.save()
	var loaded := AppSettings.load_settings()
	eq(int(loaded.hit_fx), 0, "打击特效档位存得住")
	check(not loaded.hit_sound, "打击音开关存得住")
	near(loaded.hit_volume, 0.35, "打击音音量存得住")
	eq(int(loaded.hit_fx), clampi(int(loaded.hit_fx), 0, 2), "打击特效档位被夹到 0~2")

	# 恢复原本设置，别把玩家的设置冲掉
	original.save()




func _test_unlock_frames() -> void:
	# 没有包数据：不能崩，返回 ok=false
	var empty := ChartSource.load_unlock({})
	check(not bool(empty.get("ok", false)), "没有解锁数据时 load_unlock 返回 ok=false")

	# 造一个临时包里烘焙好的帧序列：unlock.json + 2 帧 + 音频
	var dir := "user://unlock_test"
	DirAccess.make_dir_recursive_absolute(dir.path_join("unlock_frames"))
	var img := Image.create(32, 18, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.4, 0.8))
	var jpg := img.save_jpg_to_buffer(0.8)
	for i in 2:
		var fh := FileAccess.open(dir.path_join("unlock_frames").path_join("%05d.jpg" % (i + 1)), FileAccess.WRITE)
		fh.store_buffer(jpg)
		fh.close()
	var meta := {
		"fps": 10, "frames": 2, "width": 32, "duration": 0.2,
		"audio": "", "source": "test.mp4"
	}
	var mf := FileAccess.open(dir.path_join("unlock.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta))
	mf.close()

	var loaded := ChartSource.load_unlock({"kind": "dir", "search_dir": ProjectSettings.globalize_path(dir)})
	check(bool(loaded.get("ok", false)), "能读到烘焙好的帧序列")
	eq(int(loaded.get("frames", []).size()), 2, "帧数对得上")
	near(float(loaded.get("fps", 0.0)), 10.0, "fps 读出来了")
	near(float(loaded.get("duration", 0.0)), 0.2, "时长读出来了")

	# 节点本身：能 setup、能播、能跳过
	var node := UnlockFrames.new()
	check(node.setup(loaded), "UnlockFrames 能吃下这份数据")
	node.start()
	node.skip()
	check(true, "播放 + 跳过不报错")
	node.free()

	# 清理
	for i in 2:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("unlock_frames").path_join("%05d.jpg" % (i + 1))))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("unlock.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("unlock_frames")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))




func _test_zoom_shake_preset() -> void:
	var preset = StoryboardSource.SHADER_PRESETS.get("zoomShake", null)
	check(preset != null, "Godot 侧也有「放大抖动」预设")
	if preset != null:
		near(float(preset.get("zoom", 0.0)), 1.0, "zoom 权重 = 1")
		near(float(preset.get("shake", 0.0)), 1.0, "shake 权重 = 1")
	check(StoryboardSource.WEIGHT_KEYS.has("zoom"), "WEIGHT_KEYS 里有 zoom")
	check(StoryboardSource.WEIGHT_KEYS.has("shake"), "WEIGHT_KEYS 里有 shake")

	# 一条 zoomShake 在区间内应该给出 zoom + shake 两个权重
	var scene := {
		"shaders": [{"id": 1, "preset": "zoomShake", "start": 0.0, "end": 2.0,
			"amount": 100.0, "ramp": 0.0, "ease": "linear"}],
	}
	var stack := StoryboardSource.active_shaders(scene, 1.0)
	eq(stack.size(), 1, "生效层数 = 1")
	if stack.size() > 0:
		var w: Dictionary = stack[0]["weights"]
		near(float(w.get("zoom", 0.0)), 1.0, "生效时 zoom = 1")
		near(float(w.get("shake", 0.0)), 1.0, "生效时 shake = 1")
		near(float(stack[0].get("punchT0", -1.0)), 0.0, "punchT0 = 该层起点（场景内时间）")

	# 区间外不该生效
	eq(StoryboardSource.active_shaders(scene, 3.0).size(), 0, "区间外不生效")


func _find_entry(entries: Array, title: String) -> Dictionary:
	for e in entries:
		if str(e.get("title", "")) == title:
			return e
	return {}
