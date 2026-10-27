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
	_test_judge_mine()
	_test_judge_early_late()
	_test_judge_stats()

	print("== 谱面加载 ==")
	_test_chart_source()

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
	eq(RhythmChart.parse({"notes": [{"time": 1.0, "lane": 0, "type": "hold", "duration": 0}]})["chart"]["notes"][0]["type"], "tap", "duration<=0 的 hold → tap")
	eq(RhythmChart.parse({"notes": [{"time": 0, "lane": 0, "type": "bogus"}]})["chart"]["notes"][0]["type"], "tap", "未知 type → tap")


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
			{"time": -2.0, "lane": 9, "type": "tap"},
			{"time": 1.0, "lane": 1, "type": "flick"},
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
			{"time": 3.0, "lane": 2, "type": "mine"},
		],
		"lanes": [{}, {}, {}, {}],
	})["chart"]
	near(RhythmChart.chart_duration(chart), 3.5, "chart_duration 算到 hold 尾部")
	eq(RhythmChart.judgeable_count(chart), 2, "地雷不计入可判定数")
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

	# 没有 Bad 判定：超出 Good 窗口的按键打不中，音符过线后算 Miss
	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart)
	r = j.press("left", 1.2)
	check(not bool(r["hit"]), "200ms（超过 Good 窗口）打不中")
	j.update(1.2)
	eq(int(j.counts["miss"]), 1, "漏掉的音符记 Miss")
	near(j.score, 0.0, "Miss 不给分", 0.5)
	near(j.accuracy_live(), 0.0, "Miss 权重 0%")

	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart)
	r = j.press("left", 1.25)
	check(not bool(r["hit"]), "超过 220ms → 空打")
	eq(str(r["kind"]), "empty", "空打 kind")

	# 窗口倍率
	chart = _make_chart([{"time": 1.0, "lane": 0}])
	j = _new_judge(chart, 2.0)
	r = j.press("left", 1.3)
	eq(str(r["result"]), "good", "窗口 2× 时 300ms 还能打到（good）")


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


func _test_judge_mine() -> void:
	var chart := _make_chart([{"time": 1.0, "lane": 0, "type": "mine"}, {"time": 3.0, "lane": 1, "type": "mine"}])
	var j := _new_judge(chart)
	eq(RhythmChart.judgeable_count(chart), 0, "地雷不算可判定")
	var r := j.press("left", 1.02)
	eq(str(r["kind"]), "mine", "按到地雷")
	eq(int(j.counts["mine"]), 1, "地雷计数")
	j.update(3.3)
	eq(int(j.counts["miss"]), 0, "地雷过线不记 miss")
	eq(j.mines_passed, 1, "地雷过线计数")
	eq(str(chart["notes"][1]["state"]), "passed", "地雷状态 passed")


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


func _find_entry(entries: Array, title: String) -> Dictionary:
	for e in entries:
		if str(e.get("title", "")) == title:
			return e
	return {}
