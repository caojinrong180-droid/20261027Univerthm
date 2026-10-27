extends SceneTree
## 性能回归测试（headless，不需要显卡）：
##   godot --headless --path . --script res://test/run_perf_test.gd
##
## 钉住两条容易退化的性质（谱面一旦上千音符，退化就会表现成"编辑器卡住"）：
##   1. 舞台预览的布局重算次数与音符数量无关 —— 只与帧数有关；
##   2. 两个视图每帧遍历的音符数与"视野里的音符数"同阶，而不是整个谱面的总量。

var _fail := 0
var _notes := 4000
## 0.05s 一个音符 = 20 音符/秒，比真实谱面密得多。
const DENSE_SPACING := 0.05


func _init() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("FAIL: ", msg)
	else:
		print("ok   ", msg)


func _build_dense_doc(count: int) -> RhythmChartDocument:
	var doc := RhythmChartDocument.create_default()
	doc.set_lane_count(8)
	doc.timing.set_bpm(180.0)
	doc.notes.clear()
	for i in count:
		var n := RhythmChartNote.new()
		n.id = i + 1
		n.time = float(i) * DENSE_SPACING
		n.lane = i % 8
		if i % 17 == 0:
			n.type = RhythmChartNote.Type.HOLD
			n.duration = 0.3
		doc.notes.append(n)
	doc.resort_notes()
	return doc


func _run() -> void:
	var doc := _build_dense_doc(_notes)
	print("test chart: %d notes, %.1f s, %d lanes" % [doc.notes.size(), doc.total_duration(), doc.lane_count()])

	# --- 二分定位本身必须正确（视图跳过视口外音符全靠它）---
	check(doc.index_at_time(10.0) == 200, "index_at_time(10s) == 200（实际 %d）" % doc.index_at_time(10.0))
	check(doc.index_at_time(-1.0) == 0, "早于全部音符时返回 0")
	check(doc.index_at_time(1e9) == doc.notes.size(), "晚于全部音符时返回 size")

	var screen_script := load("res://addons/rhythm_chart_editor/ui/chart_editor_screen.gd")
	var screen: Control = screen_script.new()
	get_root().add_child(screen)
	await process_frame

	screen._assign_doc(doc)
	screen._timeline.px_per_sec = 240.0
	screen._set_playhead(120.0)
	await process_frame
	await process_frame

	# --- 单帧：两个视图各自遍历了多少音符、预览重算了几次布局 ---
	screen._timeline.debug_notes_visited = 0
	screen._preview.debug_notes_visited = 0
	screen._preview.debug_layout_calls = 0
	screen._timeline.queue_redraw()
	screen._preview.queue_redraw()
	await process_frame

	var tl: int = screen._timeline.debug_notes_visited
	var pv: int = screen._preview.debug_notes_visited
	var lays: int = screen._preview.debug_layout_calls
	print("1 frame: timeline visited=%d, preview visited=%d, layout_calls=%d" % [tl, pv, lays])

	check(tl > 0 and tl < 700, "时间轴只扫视口内的音符（%d，总量 %d）" % [tl, _notes])
	check(pv > 0 and pv < 1200, "舞台预览只扫回看窗口（%d，总量 %d）" % [pv, _notes])
	check(lays <= 2, "舞台预览每帧最多重算 1 次布局（实际 %d）" % lays)

	# --- 连续 20 帧的墙钟时间（粗粒度兜底，防的是数量级退化）---
	var t0 := Time.get_ticks_msec()
	for i in 20:
		screen._timeline.queue_redraw()
		screen._preview.queue_redraw()
		await process_frame
	var ms := Time.get_ticks_msec() - t0
	print("20 frames @ %d notes: %d ms (%.1f ms/帧)" % [_notes, ms, float(ms) / 20.0])
	check(ms < 4000, "20 帧耗时可接受（%d ms）" % ms)

	print("---")
	print("perf: fail=%d" % _fail)
	quit(1 if _fail > 0 else 0)
