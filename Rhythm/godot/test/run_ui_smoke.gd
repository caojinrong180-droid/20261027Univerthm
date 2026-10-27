extends SceneTree
## 制谱器 UI 冒烟测试（headless，不弹窗）：
##   godot --headless --path . --script res://test/run_ui_smoke.gd
##
## 目的不是截图比对，而是把「建界面 → 加音符 → 拖拽几何 → 撤销 → 存盘 → 读回」
## 整条链路真跑一遍，确保插件在编辑器里 _ready() 不会炸。

var _fail := 0
var _screen: Control = null


func _init() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("FAIL: ", msg)
	else:
		print("ok   ", msg)


func _run() -> void:
	var screen_script := load("res://addons/rhythm_chart_editor/ui/chart_editor_screen.gd")
	_screen = screen_script.new()
	get_root().add_child(_screen)
	await process_frame
	await process_frame

	check(_screen.doc != null, "文档已创建")
	check(_screen.doc.lane_count() == 4, "默认 4 轨")
	check(_screen._timeline != null, "时间轴视图存在")
	check(_screen._preview != null, "舞台预览存在")
	check(_screen._player != null, "音频播放器存在")

	# --- 放音符 & 几何 ---
	var note = _screen.doc.add_note(1.0, 1)
	_screen._on_edited()
	check(_screen.doc.notes.size() == 1, "加了一个音符")
	var rect: Rect2 = _screen._timeline.note_rect(note)
	check(rect.size.x > 0.0 and rect.size.y > 0.0, "音符矩形有尺寸")
	check(rect.position.x > 0.0, "音符矩形落在可见区")

	_screen._set_playhead(3.5)
	check(absf(_screen._timeline.playhead - 3.5) < 1e-4, "播放头同步到时间轴")
	check(absf(_screen._preview.playhead - 3.5) < 1e-4, "播放头同步到舞台预览")

	# --- 滚轮方向：往下滚 = 画面内容往上走 ---
	_screen._timeline.upscroll = false
	_screen._set_playhead(10.0)
	_screen._timeline._scroll_time(1.0)
	check(_screen._playhead < 10.0, "下滚模式：滚轮往下 = 时间往回退（%0.2f）" % _screen._playhead)
	_screen._timeline._scroll_time(-1.0)
	check(absf(_screen._playhead - 10.0) < 1e-4, "反向滚一次回到原位")
	_screen._timeline.upscroll = true
	_screen._set_playhead(10.0)
	_screen._timeline._scroll_time(1.0)
	check(_screen._playhead > 10.0, "上滚模式：滚轮往下 = 时间往后走（%0.2f）" % _screen._playhead)
	_screen._timeline.upscroll = false
	_screen._set_playhead(0.0)

	# --- 舞台几何 & 命中测试 ---
	var quad: PackedVector2Array = _screen._preview.lane_quad(_screen.doc.lanes[0])
	check(quad.size() == 4, "轨道四边形有 4 个点")
	_screen._preview.size = Vector2(360.0, 260.0)
	_screen._preview.queue_redraw()
	await process_frame
	var base: Vector2 = _screen._preview.lane_base(_screen.doc.lanes[0])
	var hit: int = _screen._preview.lane_at_point(base + Vector2(0, -60))
	check(hit == 0, "轨道命中测试能点中 0 号轨（hit=%d）" % hit)
	var off_hit: int = _screen._preview.lane_at_point(base + Vector2(-600, -60))
	check(off_hit == -1, "空白处不命中任何轨道（hit=%d）" % off_hit)

	# --- 轨道属性写入 ---
	_screen._lane_list.select(0)
	_screen._on_lane_list_selected(0)
	_screen._set_lane_prop("rotation", 18.0)
	_screen._set_lane_prop("alpha", 115)
	_screen._set_lane_prop("length", 1.6)
	check(absf(_screen.doc.lanes[0].rotation_deg - 18.0) < 1e-4, "旋转写入文档")
	check(_screen.doc.lanes[0].alpha == 115, "透明度（0~255）写入文档")
	check(absf(_screen.doc.lanes[0].length_scale - 1.6) < 1e-4, "长度写入文档")

	# --- 事件动画（PhiEdit 模型）：在时间轴右侧事件区里建 / 删 ---
	_screen._set_playhead(2.0)
	var tl = _screen._timeline
	tl.event_lane = 0
	tl.event_type = "x"
	var ex: float = tl.event_area_left() + 20.0
	tl._on_event_press(Vector2(ex, tl.time_to_y(2.0)), false)
	tl._on_event_drag(Vector2(ex, tl.time_to_y(4.0)), false)
	tl._finish_drag()
	var lane0: RhythmChartLane = _screen.doc.lanes[0]
	check(lane0.get_events("x").size() == 1, "在事件区拖出一条事件")
	var first_ev: Dictionary = lane0.get_events("x")[0]
	check(absf(float(first_ev["start"]) - 2.0) < 1e-4, "事件起点 = 按下处")
	check(absf(float(first_ev["end"]) - 4.0) < 1e-4, "事件终点 = 松开处")

	# 面板同步：选中态应当自动指向这条事件
	_screen._rebuild_event_rows()
	check(_screen._event_panel.sel_type == "x", "面板属性跟着事件区走")
	check(_screen._event_panel.sel_index == 0, "面板选中第 1 条")

	# 改成 -300 → 300 验证区间内插值
	lane0.set_events("x", [{"start": 2.0, "end": 6.0, "from": -300.0, "to": 300.0, "ease": "linear"}])
	check(absf(lane0.resolved_x(4.0)) < 1.0, "事件区间中点 = 0（实际 %.1f）" % lane0.resolved_x(4.0))
	check(absf(lane0.resolved_x(2.0) + 300.0) < 0.01, "事件起点 = from")
	check(absf(lane0.resolved_x(99.0) - 300.0) < 0.01, "事件结束后保持 to")

	# 右键删事件 → 回到静态值
	tl.selected_event = 0
	tl._delete_event_at(Vector2(ex, tl.time_to_y(4.0)))
	check(lane0.get_events("x").is_empty(), "事件区右键删除后回到静态值")
	_screen._set_playhead(0.0)
	# --- 判定区（白/紫/黄）---
	_screen._on_zone_selected(1)
	check(int(_screen.doc.lanes[0].judge_zone) == 1, "判定区写入文档（左/紫）")
	check(_screen.doc.lanes[0].display_color().is_equal_approx(Color("#b06bff")), "轨道显示色变紫")
	check(_screen._timeline.lane_color(0).is_equal_approx(Color("#b06bff")), "时间轴用了判定区颜色")
	_screen._on_zone_selected(0)
	check(int(_screen.doc.lanes[0].judge_zone) == 0, "判定区改回白")
	check(_screen.doc.lanes[0].display_color().is_equal_approx(Color("#ffffff")), "改回白后显示色恢复白色")

	# --- 撤销 ---
	var before: int = _screen.doc.notes.size()
	_screen._push_undo()
	_screen.doc.add_note(2.0, 2)
	check(_screen.doc.notes.size() == before + 1, "撤销前多了一个音符")
	_screen._undo_action()
	check(_screen.doc.notes.size() == before, "撤销把音符数还原")
	_screen._redo_action()
	check(_screen.doc.notes.size() == before + 1, "重做又加回来")

	# --- 变速点 ---
	_screen._add_tempo_event()
	check(_screen.doc.timing.bpm_events.size() >= 1, "能加变速点")

	# --- 存 / 读 ---
	var path := "user://smoke_chart.json"
	_screen._save_chart_to(path)
	check(FileAccess.file_exists(path), "存盘成功")
	_screen._load_chart_file(path)
	check(_screen.doc != null, "读回后文档还在")
	check(absf(_screen.doc.lanes[0].rotation_deg - 18.0) < 0.01, "读回后轨道旋转保持")
	check(_screen.doc.notes.size() == before + 1, "读回后音符数一致")

	# --- 标签/状态没崩 ---
	_screen._update_status()
	check(_screen._w["note_label"].text != "", "状态栏有内容")
	_screen._validate_and_report()

	# --- 让两个视图真的走一次绘制路径 ---
	_screen._timeline.queue_redraw()
	_screen._preview.queue_redraw()
	await process_frame
	await process_frame
	check(_screen._timeline.debug_draws > 0, "时间轴 _draw 执行过（%d 次）" % _screen._timeline.debug_draws)
	check(_screen._preview.debug_draws > 0, "舞台预览 _draw 执行过（%d 次）" % _screen._preview.debug_draws)

	# --- 主屏幕布局回归：父节点是 Container 时面板也必须撑满 ---
	# 编辑器把插件面板塞进一个 Container；只设锚点不设 EXPAND 会塌成"一条"。
	var host := VBoxContainer.new()
	host.size = Vector2(900.0, 640.0)
	get_root().add_child(host)
	var probe_script := load("res://addons/rhythm_chart_editor/ui/chart_editor_screen.gd")
	var probe: Control = probe_script.new()
	host.add_child(probe)
	await process_frame
	await process_frame
	check(probe.size.y > 500.0, "面板在 Container 里纵向撑满（h=%.0f）" % probe.size.y)
	check(probe.size.x > 820.0, "面板在 Container 里横向撑满（w=%.0f）" % probe.size.x)
	probe.queue_free()
	host.queue_free()
	await process_frame

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("---")
	print("UI smoke: fail=%d" % _fail)
	quit(1 if _fail > 0 else 0)
