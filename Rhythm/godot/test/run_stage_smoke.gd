extends SceneTree
## 游戏侧参考渲染器冒烟测试：
##   godot --headless --path . --script res://test/run_stage_smoke.gd

var _fail := 0


func _init() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("FAIL: ", msg)
	else:
		print("ok   ", msg)


func _run() -> void:
	var packed := load("res://examples/demo_stage.tscn")
	check(packed != null, "示例场景能加载")
	if packed == null:
		quit(1)
		return
	var stage: Node2D = packed.instantiate()
	get_root().add_child(stage)
	await process_frame
	await process_frame

	check(stage.doc != null, "参考渲染器读到谱面")
	if stage.doc == null:
		quit(1)
		return
	check(stage.doc.notes.size() > 0, "谱面有音符（%d）" % stage.doc.notes.size())
	check(stage.lane_length_px(stage.doc.lanes[0]) > 0.0, "轨道可视长度为正")
	check(stage.lane_dir(stage.doc.lanes[0]).length() > 0.99, "轨道方向是单位向量")

	# 让时间往前走，逼它真的画一遍
	for i in 4:
		stage.song_time = float(i) * 2.0
		stage.queue_redraw()
		await process_frame
	check(stage.debug_draws > 0, "参考渲染器 _draw 执行过（%d 次）" % stage.debug_draws)
	check(absf(stage.chart_time() - (stage.song_time - float(stage.doc.audio.get("offset", 0.0)))) < 1e-5,
		"chart_time 扣掉了音频偏移")

	print("---")
	print("stage smoke: fail=%d" % _fail)
	quit(1 if _fail > 0 else 0)
