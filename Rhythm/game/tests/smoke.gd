extends Node
## headless 冒烟测试：真把选曲 / 游玩 / 结算 / 设置建起来跑一遍，
## 并用「自动演示」把一个**运行时合成的测试谱面**（tests/fixtures/synthetic_chart.gd）
## 从头打到尾，检查判定统计。
##
## 跑法：
##   godot --headless --path game res://tests/smoke.tscn
## 退出码 0 = 全过。

const SyntheticChart = preload("res://tests/fixtures/synthetic_chart.gd")

var passes := 0
var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		print("  FAIL: " + msg)


func near(a: float, b: float, msg: String, eps := 0.001) -> void:
	if absf(a - b) <= eps:
		passes += 1
	else:
		failures += 1
		print("  FAIL: %s (got %f, want %f)" % [msg, a, b])


func eq(a, b, msg: String) -> void:
	if a == b:
		passes += 1
	else:
		failures += 1
		print("  FAIL: %s (got %s, want %s)" % [msg, str(a), str(b)])


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("\n%d passed, %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _run() -> void:
	App.refresh_library()
	check(true, "谱面库扫描没崩（当前 %d 个谱面）" % App.library.size())
	_check_stage_geometry()
	await _check_song_select()
	await _check_gameplay_autoplay()
	await _check_key_input()
	await _check_fx_rules()
	await _check_chord_marking()
	await _check_settings()
	print("  smoke done")


## 判定特效规则：只有一圈判定环（Perfect+ / Perfect / Good 同款，颜色按判定）/ Miss 无特效 / Hold 的 Miss 半透明保留
func _check_fx_rules() -> void:
	_make_session()
	App.autoplay_once = false
	var game = _new_gameplay()
	await get_tree().process_frame
	game.debug_start_now()
	var stage: StageView = game.stage
	stage._fx.clear()
	stage._shake_amp = 0.0

	eq(Palette.judge_color("perfect").to_html(false), "b06bff", "Perfect 颜色 = 紫")
	eq(Palette.judge_color("good").to_html(false), "4c9aff", "Good 颜色 = 蓝")

	stage._on_note_judged({"type": "tap", "lane": 0, "state": "judged"}, "perfect", 0.0)
	check(stage._fx.size() == 1, "Perfect 只有一圈判定环")
	eq(stage._fx_color("perfect_plus").to_html(false), stage._fx_color("perfect").to_html(false), "Perfect+ 与 Perfect 特效同色")
	check(is_zero_approx(stage._shake_amp), "Perfect 不屏震")

	stage._fx.clear()
	stage._on_note_judged({"type": "tap", "lane": 0, "state": "judged"}, "good", 0.0)
	check(stage._fx.size() == 1, "Good 也有一圈判定环")
	check(is_zero_approx(stage._shake_amp), "Good 不屏震")

	stage._fx.clear()
	stage._on_note_judged({"type": "tap", "lane": 0, "state": "judged"}, "miss", 0.0)
	check(stage._fx.is_empty(), "Miss 没有任何特效")

	stage._fx.clear()
	var hold_miss := {"type": "hold", "lane": 0, "state": "judged", "result": "miss"}
	stage._on_note_judged(hold_miss, "miss", 0.0)
	check(bool(hold_miss.get("hold_dim", false)), "Hold 的 Miss 会压到 50% 透明")
	check(stage._fx.is_empty(), "Hold 的 Miss 不放特效")

	stage._on_mine_detonated({"type": "mine", "lane": 0}, 0.0)
	check(stage._shake_amp > 0.0, "踩雷还屏震")
	game.queue_free()
	await get_tree().process_frame


## 1:1：逻辑舞台的常量和网页版预渲染窗口（editor.js / computePreviewLayout）一致
func _check_stage_geometry() -> void:
	var stage := StageView.new()
	stage.settings = App.settings
	stage.setup(SyntheticChart.build(), null, App.settings, null)
	stage.size = Vector2(1280, 720)
	near(stage.stage_scale(), 720.0 / (350.0 * 9.0 / 16.0), "16:9 窗口（1280×720）时缩放 = 720/196.875")
	check(is_equal_approx(StageView.STAGE_W, 350.0), "逻辑舞台宽 350")
	check(is_equal_approx(StageView.STAGE_H, 350.0 * 9.0 / 16.0), "逻辑舞台高 196.875（16:9）")

	# 超长 hold：绘制回看窗口必须覆盖它，不然头和身体会在 4 秒后被整条剔除
	var long_chart := SyntheticChart.build()
	long_chart["notes"] = [{"time": 1.0, "lane": 0, "type": "hold", "duration": 12.0}]
	var long_stage := StageView.new()
	long_stage.setup(long_chart, null, App.settings, null)
	check(long_stage._hold_lookback >= 12.0, "长条绘制回看窗口覆盖 12 秒的 hold")
	long_stage.free()
	var rect := stage.stage_rect()
	near(rect.size.y, 720.0, "舞台铺满窗口高度")
	near(rect.size.x, 1280.0, "舞台铺满窗口宽度（16:9 没有黑边）", 1.0)
	# 默认 stage_offset_px = -24：在居中的基础上往上抬 24px（顶部裁掉，底部留边）
	near(rect.position.y, -24.0, "默认画面上抬 24px", 1.0)
	near(rect.position.x, 0.0, "16:9 舞台水平方向无黑边", 1.0)
	# 画面垂直偏移可调
	App.settings.stage_offset_px = 10.0
	near(stage.stage_rect().position.y, 10.0, "画面垂直偏移生效", 1.0)
	App.settings.stage_offset_px = -24.0
	check(is_equal_approx(StageView.NOTE_TH, 2.0), "音符半厚 2.0")
	check(is_equal_approx(StageView.PV_SCALE, 1.75), "轨道 / 音符整体放大 1.75×")
	var judge_y := roundf(StageView.STAGE_H * 0.85)
	check(judge_y == 167.0, "judgeY = round(H*0.85) = 167")
	var lane_w := minf(StageView.STAGE_W * 0.05, (StageView.STAGE_W * 0.43) / 4.0) * StageView.PV_SCALE
	near(lane_w, 30.625, "4 轨时 laneWidth = 17.5 × 1.75 = 30.6")
	var half_w := maxf(2.0, lane_w / 2.0 - 0.5)
	near(half_w, 14.8125, "halfW = 14.81")
	near(maxf(2.0, half_w - 1.0), 13.8125, "音符半宽 13.81")
	var info := stage._lane_geom(0, judge_y, half_w)
	near(float(info["cx"]), 175.0 - 150.0, "cx = W/2 + x")
	near(float(info["cy"]), 167.0, "cy = judgeY - y")
	near(float(info["len"]), 167.0, "length 10 → 轨道长度 = judgeY")
	check(is_equal_approx(float(info["dx"]), 0.0), "rotation 0 → dx = 0")
	check(is_equal_approx(float(info["dy"]), -1.0), "rotation 0 → dy = -1（朝上）")
	stage.free()


func _check_song_select() -> void:
	var select = load("res://scenes/song_select.tscn").instantiate()
	get_tree().root.add_child(select)
	await get_tree().process_frame
	await get_tree().process_frame
	check(select.get_child_count() > 0, "选曲界面建起来了")
	check(select._rows.size() == App.library.size(), "列表行数 = 谱面数")
	if App.library.is_empty():
		check(select._selected == -1, "空谱面库时不选中")
		check(select._list_count.text == "0 个谱面", "空谱面库计数文案")
	else:
		check(select._detail_title.text != "", "详情标题已填（焦点在第一行）")
	select.queue_free()
	await get_tree().process_frame


func _make_session() -> void:
	var chart := SyntheticChart.build()
	App.session = {
		"entry": {"key": "test:synthetic", "title": "Synthetic Test"},
		"chart": chart,
		"stream": SyntheticChart.stream(),
		"cover": null,
		"warnings": [],
		"errors": [],
	}


func _new_gameplay() -> Node:
	var game = load("res://scenes/gameplay.tscn").instantiate()
	game.debug_mode = true
	get_tree().root.add_child(game)
	return game


func _check_gameplay_autoplay() -> void:
	_make_session()
	App.autoplay_once = true
	var game = _new_gameplay()
	await get_tree().process_frame

	var chart: Dictionary = App.session["chart"]
	var judgeable := RhythmChart.judgeable_count(chart)
	check(game.judge != null, "判定引擎建起来了")
	check(game.judge.total_judgeable == judgeable, "可判定音符数 %d" % judgeable)
	check(game.state == 0, "初始是倒计时状态")
	check(game.autoplay, "自动演示已开启")
	check(game._zone_for_key(KEY_A) == "left", "A → 左判定区")
	check(game._zone_for_key(KEY_J) == "right", "J → 右判定区")
	check(game._zone_for_key(KEY_G) == "", "G 不参与判定")

	game.debug_start_now()
	check(game.state == 1, "进入播放状态")

	game._pause()
	check(game.state == 2, "Esc 暂停")
	game._resume()
	check(game.state == 1, "继续")

	var dt := 1.0 / 60.0
	var guard := 0
	while game.state != 3 and guard < 4000:
		game.debug_advance(dt)
		guard += 1
	check(game.state == 3, "自动演示跑到结算（%.1f 秒 / %d 帧）" % [game.chart_time, guard])

	var result: Dictionary = game.debug_run_result
	check(not result.is_empty(), "有结算数据")
	if not result.is_empty():
		print("  自动演示：score=%d acc=%.2f%% combo=%d counts=%s" % [
			int(result["score"]), float(result["accuracy"]) * 100.0,
			int(result["max_combo"]), str(result["counts"])])
		check(int(result["total"]) == judgeable, "结算 total = 可判定数")
		check(int(result["counts"]["miss"]) == 0, "自动演示 0 miss")
		check(int(result["counts"]["perfect"]) + int(result["counts"]["perfect_plus"]) == int(result["total"]), "自动演示全 PERFECT（含 Perfect+）")
		check(int(result["counts"]["perfect_plus"]) == int(result["total"]), "自动演示全 Perfect+")
		check(int(result["score"]) == 1010000, "全 Perfect+ 满分 1,010,000")
		check(bool(result["ap_plus"]), "自动演示 ALL PERFECT+")
		check(float(result["accuracy"]) >= 0.999, "自动演示 100% 准确率")
		check(str(result["grade"]) == "S", "自动演示评级 S")
		check(bool(result["ap"]), "自动演示 AP")
		check(int(result["max_combo"]) >= int(result["total"]), "最大连击 ≥ 可判定数")
		check(int(result["counts"]["mine"]) == 0, "自动演示不会踩地雷")
		check(int(result["note_count"]) - judgeable > 0, "谱面里的地雷不计入判定数")
	check(not game.stage._fx.is_empty(), "自动演示全程有判定环")
	game.queue_free()
	await get_tree().process_frame

	App.last_result = result
	var results_scene = load("res://scenes/results.tscn").instantiate()
	get_tree().root.add_child(results_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	check(results_scene.get_child_count() > 0, "结算界面建起来了")
	results_scene.queue_free()
	await get_tree().process_frame
	App.autoplay_once = false


func _check_key_input() -> void:
	_make_session()
	App.autoplay_once = false
	var game = _new_gameplay()
	await get_tree().process_frame
	game.debug_start_now()
	var dt := 1.0 / 60.0
	# 第一个音符在 1.2 秒、0 轨（左判定区）
	while game.chart_time < 1.2:
		game.debug_advance(dt)
	game._on_key_down(KEY_A, "left")
	check(int(game.judge.counts["perfect_plus"]) >= 1, "手动按键命中第一个音符")
	check(game._zones.has("left"), "按住时左判定区亮着")
	check(not game.stage._fx.is_empty(), "命中产生判定环")
	check(game.stage.hud_combo_text() == "Combo %d" % int(game.judge.combo), "HUD Combo 文本跟判定器一致")
	check(game.stage.hud_score_text().length() == 8, "HUD 分数是 8 位补零")
	check(game.stage.hud_accuracy_text().ends_with("%"), "HUD 准确率带 %")
	check(game.stage.hud_level_text().begins_with("Lv."), "HUD 等级是 Lv.x")
	check(game.stage.hud_title_text() != "", "HUD 有曲名")
	check(game.stage.song_length > 0.0, "HUD 进度有总时长")
	game._on_key_up(KEY_A)
	check(not game._zones.has("left"), "松开后判定区灭掉")

	# 暂停面板里的打击音 / 特效设置
	var original_sound: bool = App.settings.hit_sound
	var original_volume: float = App.settings.hit_volume
	var original_fx: int = App.settings.hit_fx
	game._pause()
	check(game.state == 2, "暂停面板打开")
	game._pause_step_hit_sound(1)
	check(App.settings.hit_sound != original_sound, "暂停面板能切打击音开关")
	game._pause_step_hit_volume(-1)
	check(absf(App.settings.hit_volume - maxf(0.0, original_volume - 0.05)) < 0.001, "暂停面板能调打击音音量")
	check(absf(game.hit_player.volume_db - linear_to_db(clampf(App.settings.hit_volume, 0.0001, 1.0))) < 0.05, "音量立刻作用到播放器")
	game._pause_step_hit_fx(-1)
	check(int(App.settings.hit_fx) == wrapi(original_fx - 1, 0, 3), "暂停面板能切打击特效档位")
	game._resume()
	check(game.state == 1, "关掉暂停继续")
	App.settings.hit_sound = original_sound
	App.settings.hit_volume = original_volume
	App.settings.hit_fx = original_fx
	App.settings.save()
	game.queue_free()
	await get_tree().process_frame

	# 特效设成「关」时不该产生任何打击特效
	App.settings.hit_fx = 0
	_make_session()
	var muted = _new_gameplay()
	await get_tree().process_frame
	muted.debug_start_now()
	while muted.chart_time < 1.2:
		muted.debug_advance(dt)
	muted._on_key_down(KEY_A, "left")
	check(int(muted.judge.counts["perfect_plus"]) >= 1, "特效关掉后判定照常")
	check(muted.stage._fx.is_empty(), "特效关：没有判定环")
	App.settings.hit_fx = 2
	App.settings.save()
	muted.queue_free()
	await get_tree().process_frame


## 多押标记：同一时刻（±20ms）≥2 个可判定音符才算，地雷不算
func _check_chord_marking() -> void:
	var chart := SyntheticChart.build()
	chart["notes"] = [
		{"time": 1.0, "lane": 0, "type": "tap"},
		{"time": 1.0, "lane": 1, "type": "tap"},
		{"time": 1.01, "lane": 2, "type": "tap"},
		{"time": 2.0, "lane": 2, "type": "hold", "duration": 0.5},
		{"time": 2.0, "lane": 3, "type": "mine"},
		{"time": 3.0, "lane": 0, "type": "tap"},
	]
	var stage := StageView.new()
	stage.settings = App.settings
	stage.setup(chart, null, App.settings, null)
	var notes: Array = chart["notes"]
	eq(int(notes[0].get("chord", 0)), 3, "同刻三押 → chord=3")
	eq(int(notes[1].get("chord", 0)), 3, "三押第二颗也标记")
	eq(int(notes[2].get("chord", 0)), 3, "20ms 内也算同刻")
	eq(int(notes[3].get("chord", 0)), 0, "hold + 地雷同刻 → 地雷不算，不成多押")
	eq(int(notes[5].get("chord", 0)), 0, "单独音符没有多押标记")
	stage.free()
	await get_tree().process_frame


func _check_settings() -> void:
	var screen = load("res://scenes/settings.tscn").instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	check(screen.get_child_count() > 0, "设置界面建起来了")
	check(screen._labels.size() >= 8, "设置项数量")
	screen._refresh()
	check(App.settings.key_layout in AppSettings.KEY_LAYOUTS, "键位布局合法")
	screen.queue_free()
	await get_tree().process_frame

	App.settings.audio_offset_ms = -15.0
	App.settings.speed_mult = 1.5
	App.settings.save()
	var reloaded := AppSettings.load_settings()
	check(absf(reloaded.audio_offset_ms + 15.0) < 0.001, "偏移存得住")
	check(absf(reloaded.speed_mult - 1.5) < 0.001, "流速存得住")
	App.settings.reset()
	App.settings.save()
