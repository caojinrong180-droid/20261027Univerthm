@tool
extends Control
## 制谱器主屏幕：工具栏 + 谱面信息 + 时间轴 + 轨道检查器 + 舞台预览。
##
## 数据流很简单：所有控件都只改 doc（RhythmChartDocument），
## doc.changed 再回头刷新视图；存盘就是把 doc.to_dict() 序列化。
## 撤销用整份快照（to_dict / from_dict），实现短但可靠。

const ChartDoc := preload("res://addons/rhythm_chart_editor/core/rhythm_chart_doc.gd")
const ChartIO := preload("res://addons/rhythm_chart_editor/core/rhythm_chart_io.gd")
const ChartNote := preload("res://addons/rhythm_chart_editor/core/rhythm_chart_note.gd")
const ChartLane := preload("res://addons/rhythm_chart_editor/core/rhythm_chart_lane.gd")
const ChartAudio := preload("res://addons/rhythm_chart_editor/core/rhythm_chart_audio.gd")
const TimelineView := preload("res://addons/rhythm_chart_editor/ui/timeline_view.gd")
const StagePreview := preload("res://addons/rhythm_chart_editor/ui/stage_preview.gd")
const EventCurve := preload("res://addons/rhythm_chart_editor/ui/event_curve.gd")
const EventPanel := preload("res://addons/rhythm_chart_editor/ui/event_panel.gd")

const UNDO_LIMIT := 100
## 状态栏（含 validate 全量扫描）的最小刷新间隔。
const STATUS_INTERVAL_MS := 120
const SNAP_ITEMS := [
	{"label": "1/1 整拍", "divisor": 1},
	{"label": "1/2 半拍", "divisor": 2},
	{"label": "1/3 三连", "divisor": 3},
	{"label": "1/4 十六分", "divisor": 4},
	{"label": "1/6 六连", "divisor": 6},
	{"label": "1/8 三十二分", "divisor": 8},
]
const DIFFICULTIES := ["EASY", "NORMAL", "HARD", "EXPERT", "MASTER"]

var doc: ChartDoc = null

var _undo: Array = []
var _redo: Array = []
var _dirty := false
var _syncing := false
var _last_undo_push := {}
var _status_pending := false
var _status_flushed_ms := 0

var _timeline: Control = null
var _preview: Control = null
var _player: AudioStreamPlayer = null
var _stream: AudioStream = null
var _playing := false
var _playhead := 0.0

var _lane_list: ItemList = null
var _tempo_rows: VBoxContainer = null
var _event_rows: VBoxContainer = null
var _event_type_opt: OptionButton = null
var _event_curve: EventCurve = null
var _event_panel: EventPanel = null
var _margin: Control = null

var _w: Dictionary = {}
var _dlg_chart: FileDialog = null
var _dlg_save: FileDialog = null
var _dlg_audio: FileDialog = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 编辑器主屏幕的父节点是 Container：光设锚点不够，还要 EXPAND 标志，
	# 否则只会拿到最小尺寸（宽度撑满、高度塌成一条）。
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_player = AudioStreamPlayer.new()
	_player.name = "ChartPreviewPlayer"
	add_child(_player)
	_build_ui()
	_new_chart()


func _exit_tree() -> void:
	if _player != null:
		_player.stop()


# ================================================================ 界面搭建

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = margin
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	root.add_child(_wrap_hscroll(_build_toolbar()))

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 6)
	root.add_child(main)

	main.add_child(_build_left_panel())
	main.add_child(_build_center())
	main.add_child(_build_right_panel())

	root.add_child(_wrap_hscroll(_build_status_bar()))




## 工具箱/状态栏这类"一行很多控件"的横条，用横向滚动包起来：
## 否则它们的 min width 会把整个根容器撑宽，右侧面板被挤出屏幕（高 DPI 下必现）。
func _wrap_hscroll(inner: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(inner)
	return scroll


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)

	bar.add_child(_tool_button("新建", _new_chart))
	bar.add_child(_tool_button("打开", _open_chart_dialog))
	bar.add_child(_tool_button("保存", _save_chart))
	bar.add_child(_tool_button("另存为", _save_chart_as))
	bar.add_child(VSeparator.new())

	var rewind := _tool_button("⏮", _rewind)
	rewind.tooltip_text = "回到开头"
	bar.add_child(rewind)
	var play := _tool_button("▶ 播放", _toggle_play)
	play.tooltip_text = "空格"
	_w["play_button"] = play
	bar.add_child(play)

	bar.add_child(VSeparator.new())
	var snap_label := Label.new()
	snap_label.text = "吸附"
	bar.add_child(snap_label)
	var snap_opt := OptionButton.new()
	for item in SNAP_ITEMS:
		snap_opt.add_item(String(item["label"]))
	snap_opt.selected = 3
	snap_opt.item_selected.connect(_on_snap_selected)
	_w["snap"] = snap_opt
	bar.add_child(snap_opt)

	bar.add_child(VSeparator.new())
	var dir_label := Label.new()
	dir_label.text = "滚动"
	bar.add_child(dir_label)
	var dir_opt := OptionButton.new()
	dir_opt.add_item("上 → 下")
	dir_opt.add_item("下 → 上")
	dir_opt.selected = 0
	dir_opt.tooltip_text = "音符走向：上→下 = 判定线在下方（默认）；下→上 = 判定线在上方"
	dir_opt.item_selected.connect(func(i: int) -> void:
		if _timeline != null:
			_timeline.upscroll = (i == 1)
			_timeline.queue_redraw()
	)
	bar.add_child(dir_opt)
	bar.add_child(VSeparator.new())
	var layer_label := Label.new()
	layer_label.text = "编辑层"
	bar.add_child(layer_label)
	var layer_opt := OptionButton.new()
	layer_opt.add_item("Note")
	for i in ChartLane.EVENT_LABELS.size():
		layer_opt.add_item("事件 " + String(ChartLane.EVENT_LABELS[i]))
	layer_opt.selected = 0
	layer_opt.tooltip_text = "在时间轴上直接摆事件：滚动/缩放/吸附和音符完全同步"
	layer_opt.item_selected.connect(_on_edit_layer_selected)
	_w["edit_layer"] = layer_opt
	bar.add_child(layer_opt)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var check := _tool_button("校验谱面", _validate_and_report)
	bar.add_child(check)

	return bar


func _tool_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


func _build_left_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = 248
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)

	# --- 谱面信息 ---
	var sec1 := _section(box, "谱面信息")
	var title := LineEdit.new()
	title.placeholder_text = "曲名"
	title.text_changed.connect(func(t: String) -> void: _set_meta("title", t))
	sec1.add_child(_row("曲名", title))
	var artist := LineEdit.new()
	artist.text_changed.connect(func(t: String) -> void: _set_meta("artist", t))
	sec1.add_child(_row("艺术家", artist))
	var charter := LineEdit.new()
	charter.text_changed.connect(func(t: String) -> void: _set_meta("charter", t))
	sec1.add_child(_row("谱师", charter))
	var diff := OptionButton.new()
	for d in DIFFICULTIES:
		diff.add_item(d)
	diff.item_selected.connect(func(i: int) -> void: _set_meta("difficulty", String(DIFFICULTIES[i])))
	sec1.add_child(_row("难度", diff))
	var level := _spin(1, 99, 1, 5)
	level.value_changed.connect(func(v: float) -> void: _set_meta("level", int(v)))
	sec1.add_child(_row("等级", level))
	_w["meta_title"] = title
	_w["meta_artist"] = artist
	_w["meta_charter"] = charter
	_w["meta_diff"] = diff
	_w["meta_level"] = level

	# --- 音频 ---
	var sec2 := _section(box, "音频")
	var audio_row := HBoxContainer.new()
	var audio_edit := LineEdit.new()
	audio_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_edit.placeholder_text = "res://audio/song.ogg"
	audio_edit.text_submitted.connect(func(_t: String) -> void: _reload_audio())
	audio_edit.focus_exited.connect(_reload_audio)
	audio_row.add_child(audio_edit)
	var browse := Button.new()
	browse.text = "…"
	browse.pressed.connect(_pick_audio_dialog)
	audio_row.add_child(browse)
	sec2.add_child(_row("文件", audio_row))
	var offset := _spin(-30.0, 30.0, 0.001, 0.0, " s")
	offset.tooltip_text = "音频时间 = 谱面时间 + offset"
	offset.value_changed.connect(func(v: float) -> void: _set_audio("offset", v))
	sec2.add_child(_row("偏移", offset))
	var vol := _spin(-40.0, 12.0, 0.5, 0.0, " dB")
	vol.value_changed.connect(func(v: float) -> void:
		_set_audio("volume_db", v)
		if _player != null:
			_player.volume_db = v
	)
	sec2.add_child(_row("音量", vol))
	_w["audio_edit"] = audio_edit
	_w["audio_offset"] = offset
	_w["audio_vol"] = vol

	# --- 时间轴 ---
	var sec3 := _section(box, "时间轴")
	var bpm := _spin(20.0, 400.0, 0.001, 150.0)
	bpm.value_changed.connect(_on_bpm_changed)
	sec3.add_child(_row("BPM", bpm))
	var beat_offset := _spin(-5.0, 5.0, 0.001, 0.0, " s")
	beat_offset.value_changed.connect(_on_beat_offset_changed)
	sec3.add_child(_row("首拍偏移", beat_offset))
	_w["bpm"] = bpm
	_w["beat_offset"] = beat_offset
	var tempo_label := Label.new()
	tempo_label.text = "变速点（beat → bpm）"
	tempo_label.add_theme_font_size_override("font_size", 11)
	sec3.add_child(tempo_label)
	_tempo_rows = VBoxContainer.new()
	_tempo_rows.add_theme_constant_override("separation", 2)
	sec3.add_child(_tempo_rows)
	var add_tempo := Button.new()
	add_tempo.text = "+ 在播放头处加变速点"
	add_tempo.pressed.connect(_add_tempo_event)
	sec3.add_child(add_tempo)

	# --- 舞台 ---
	var sec4 := _section(box, "舞台")
	var lanes := _spin(1, 16, 1, 4)
	lanes.value_changed.connect(_on_lane_count_changed)
	sec4.add_child(_row("轨道数", lanes))
	var lane_w := _spin(16.0, 320.0, 1.0, 96.0)
	lane_w.value_changed.connect(func(v: float) -> void: _set_stage("lane_width", v))
	sec4.add_child(_row("轨道宽", lane_w))
	var highway := _spin(0.5, 30.0, 0.1, 6.0, " s")
	highway.value_changed.connect(func(v: float) -> void: _set_stage("highway_length", v))
	sec4.add_child(_row("可视长度", highway))
	var scroll_v := _spin(0.1, 6.0, 0.05, 1.0)
	scroll_v.value_changed.connect(func(v: float) -> void: _set_stage("scroll_speed", v))
	sec4.add_child(_row("滚动倍率", scroll_v))
	var judge := _spin(-2000.0, 2000.0, 1.0, 0.0)
	judge.value_changed.connect(func(v: float) -> void: _set_stage("judge_line_y", v))
	sec4.add_child(_row("判定线 Y", judge))
	_w["lane_count"] = lanes
	_w["lane_width"] = lane_w
	_w["highway"] = highway
	_w["scroll"] = scroll_v
	_w["judge"] = judge

	return panel


func _build_center() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)

	_timeline = TimelineView.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.custom_minimum_size = Vector2(220, 180)
	_timeline.edit_begin.connect(_push_undo)
	_timeline.edit_changed.connect(_on_edited)
	_timeline.seek_requested.connect(_set_playhead)
	_timeline.selection_changed.connect(_on_note_selected)
	box.add_child(_timeline)

	var hint := Label.new()
	hint.text = "左键点轨道空白放音符 / 拖音符改位置 / 拖长条尾端改长度 / 右键删 / 双击换类型 / 滚轮翻页 / Ctrl+滚轮缩放"
	hint.clip_text = true
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	box.add_child(hint)
	return box


func _build_right_panel() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 336
	box.add_theme_constant_override("separation", 4)

	_preview = StagePreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_stretch_ratio = 0.85
	_preview.custom_minimum_size = Vector2(200, 120)
	_preview.edit_begin.connect(_push_undo)
	_preview.edit_changed.connect(_on_edited)
	_preview.lane_selected.connect(_on_lane_selected_index)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 4.0 / 3.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.size_flags_stretch_ratio = 0.95
	aspect.custom_minimum_size = Vector2(0, 250)
	aspect.add_child(_preview)
	box.add_child(aspect)

	# 检查器内容多（属性 + 事件），放进滚动容器，不然矮窗口下会被挤没
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 3)
	scroll.add_child(inner)

	var sec := _section(inner, "轨道")
	_lane_list = ItemList.new()
	_lane_list.custom_minimum_size.y = 92
	_lane_list.item_selected.connect(_on_lane_list_selected)
	sec.add_child(_lane_list)

	var row_btns := HBoxContainer.new()
	var add_lane := Button.new()
	add_lane.text = "+ 轨道"
	add_lane.pressed.connect(_add_lane)
	var dup_lane := Button.new()
	dup_lane.text = "复制"
	dup_lane.pressed.connect(_duplicate_lane)
	var del_lane := Button.new()
	del_lane.text = "删除"
	del_lane.pressed.connect(_remove_lane)
	row_btns.add_child(add_lane)
	row_btns.add_child(dup_lane)
	row_btns.add_child(del_lane)
	sec.add_child(row_btns)
	_build_event_section(sec)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	sec.add_child(grid)
	var px := _spin(-4000.0, 4000.0, 1.0, 0.0)
	px.value_changed.connect(func(v: float) -> void: _set_lane_prop("x", v))
	grid.add_child(_row("X", px))
	var py := _spin(-4000.0, 4000.0, 1.0, 0.0)
	py.value_changed.connect(func(v: float) -> void: _set_lane_prop("y", v))
	grid.add_child(_row("Y", py))
	var rot := _spin(-180.0, 180.0, 0.5, 0.0, " °")
	rot.value_changed.connect(func(v: float) -> void: _set_lane_prop("rotation", v))
	grid.add_child(_row("旋转", rot))
	var alpha := _spin(0, 255, 1, 255)
	alpha.tooltip_text = "0 = 全透明，255 = 不透明"
	alpha.value_changed.connect(func(v: float) -> void: _set_lane_prop("alpha", v))
	grid.add_child(_row("透明度", alpha))
	var length_scale := _spin(0.1, 8.0, 0.01, 1.0, " ×")
	length_scale.value_changed.connect(func(v: float) -> void: _set_lane_prop("length", v))
	grid.add_child(_row("长度", length_scale))
	var vol := _spin(0.0, 1.0, 0.01, 1.0)
	vol.value_changed.connect(func(v: float) -> void: _set_lane_prop("volume", v))
	grid.add_child(_row("音量", vol))
	var zone_opt := OptionButton.new()
	for z in ChartLane.ZONE_LABELS.size():
		zone_opt.add_item(ChartLane.zone_label(ChartLane.zone_from_index(z)))
	zone_opt.tooltip_text = "判定区：白 = 任意键 ASDFJKL; ／ 紫 = 只有 ASDF ／ 黄 = 只有 JKL;"
	zone_opt.item_selected.connect(_on_zone_selected)
	grid.add_child(_row("判定区", zone_opt))
	var color_pick := ColorPickerButton.new()
	color_pick.edit_alpha = false
	color_pick.color_changed.connect(func(c: Color) -> void: _set_lane_color(c))
	grid.add_child(_row("颜色", color_pick))
	var visible_check := CheckBox.new()
	visible_check.text = "可见"
	visible_check.toggled.connect(func(on: bool) -> void: _set_lane_prop("visible", on))
	grid.add_child(visible_check)

	_w["lane_x"] = px
	_w["lane_y"] = py
	_w["lane_rot"] = rot
	_w["lane_alpha"] = alpha
	_w["lane_len"] = length_scale
	_w["lane_vol"] = vol
	_w["lane_color"] = color_pick
	_w["lane_zone"] = zone_opt
	_w["lane_vis"] = visible_check


	return box


func _build_status_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	var time_label := Label.new()
	# 长文本一律裁切，避免把整行撑宽（校验结果很长时会挤坏布局）
	time_label.custom_minimum_size.x = 90
	time_label.clip_text = true
	time_label.text = "00:00.000"
	bar.add_child(time_label)
	var note_label := Label.new()
	# 长文本一律裁切，避免把整行撑宽（校验结果很长时会挤坏布局）
	note_label.custom_minimum_size.x = 430
	note_label.clip_text = true
	bar.add_child(note_label)
	var warn_label := Label.new()
	# 长文本一律裁切，避免把整行撑宽（校验结果很长时会挤坏布局）
	warn_label.custom_minimum_size.x = 330
	warn_label.clip_text = true
	warn_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	bar.add_child(warn_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var path_label := Label.new()
	# 长文本一律裁切，避免把整行撑宽（校验结果很长时会挤坏布局）
	path_label.custom_minimum_size.x = 250
	path_label.clip_text = true
	path_label.add_theme_font_size_override("font_size", 11)
	path_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	bar.add_child(path_label)
	_w["time_label"] = time_label
	_w["note_label"] = note_label
	_w["warn_label"] = warn_label
	_w["path_label"] = path_label
	return bar


func _section(parent: Control, title: String) -> VBoxContainer:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.75))
	parent.add_child(label)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	parent.add_child(inner)
	return inner


func _row(label_text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 62
	l.add_theme_font_size_override("font_size", 11)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


func _spin(min_v: float, max_v: float, step: float, value: float, suffix: String = "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.suffix = suffix
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


# ================================================================ 文档生命周期

func _new_chart() -> void:
	_assign_doc(ChartDoc.create_default())
	doc.meta["title"] = "未命名谱面"
	_dirty = false
	_refresh_all()


func _assign_doc(new_doc: ChartDoc) -> void:
	if doc != null and doc.changed.is_connected(_on_doc_changed):
		doc.changed.disconnect(_on_doc_changed)
	doc = new_doc
	doc.changed.connect(_on_doc_changed)
	_undo.clear()
	_redo.clear()
	_playhead = 0.0
	_timeline.set_doc(doc)
	_preview.set_doc(doc)
	_reload_audio()
	_set_playhead(0.0)


func _on_doc_changed() -> void:
	if _timeline != null:
		_timeline.queue_redraw()
	if _preview != null:
		_preview.queue_redraw()
	# 状态栏要跑一遍 validate()（遍历全部音符），拖轨道时每帧调用会明显吃 CPU，
	# 改成打标记 + _process 里节流刷新。
	_status_pending = true


func _on_edited() -> void:
	if _syncing:
		return
	_dirty = true
	# 舞台预览里拖动轨道时，检查器的数值要跟着动。
	_sync_lane_widgets()
	var idx := _selected_lane_index()
	if idx >= 0:
		_update_lane_item(idx)
	if doc != null:
		doc.changed.emit()
	_rebuild_event_rows()


func _mark_dirty() -> void:
	_dirty = true
	_update_status()


# ================================================================ 撤销 / 重做

func _open_chart_dialog() -> void:
	if _dlg_chart == null:
		_dlg_chart = FileDialog.new()
		_dlg_chart.access = FileDialog.ACCESS_FILESYSTEM
		_dlg_chart.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dlg_chart.add_filter("*.json ; 谱面 JSON")
		_dlg_chart.add_filter("*.rchart ; 谱面")
		_dlg_chart.file_selected.connect(_load_chart_file)
		add_child(_dlg_chart)
	_dlg_chart.popup_centered_ratio(0.5)


func _load_chart_file(path: String) -> void:
	var report: Array = []
	var loaded := ChartIO.load_file(path, report)
	if loaded == null:
		_push_status("打开失败：" + ", ".join(PackedStringArray(report)))
		return
	_assign_doc(loaded)
	_dirty = false
	_refresh_all()
	_push_status("已打开 %s（%d 个音符）" % [path.get_file(), loaded.notes.size()])


func _save_chart() -> void:
	if doc == null:
		return
	if doc.path.is_empty():
		_save_chart_as()
		return
	var err := ChartIO.save_file(doc, doc.path)
	if err != OK:
		_push_status("保存失败（错误码 %d）" % err)
		return
	_dirty = false
	_refresh_all()
	_push_status("已保存到 %s" % doc.path)


func _save_chart_as() -> void:
	if doc == null:
		return
	if _dlg_save == null:
		_dlg_save = FileDialog.new()
		_dlg_save.access = FileDialog.ACCESS_FILESYSTEM
		_dlg_save.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_dlg_save.add_filter("*.json ; 谱面 JSON")
		_dlg_save.file_selected.connect(_save_chart_to)
		add_child(_dlg_save)
	_dlg_save.current_file = doc.path.get_file() if not doc.path.is_empty() else "chart.json"
	_dlg_save.popup_centered_ratio(0.5)


func _save_chart_to(path: String) -> void:
	if path.get_extension().is_empty():
		path += ".json"
	var err := ChartIO.save_file(doc, path)
	if err != OK:
		_push_status("保存失败（错误码 %d）" % err)
		return
	_dirty = false
	_refresh_all()
	_push_status("已保存到 %s" % path)


func _pick_audio_dialog() -> void:
	if _dlg_audio == null:
		_dlg_audio = FileDialog.new()
		_dlg_audio.access = FileDialog.ACCESS_FILESYSTEM
		_dlg_audio.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dlg_audio.add_filter("*.ogg, *.mp3, *.wav ; 音频文件")
		_dlg_audio.file_selected.connect(func(path: String) -> void:
			doc.audio["file"] = path
			_w["audio_edit"].text = path
			_mark_dirty()
			_reload_audio()
		)
		add_child(_dlg_audio)
	_dlg_audio.popup_centered_ratio(0.5)


func _reload_audio() -> void:
	if doc == null:
		return
	var path := String(doc.audio.get("file", ""))
	if not _w.has("audio_edit"):
		return
	if _w["audio_edit"].text != path:
		_w["audio_edit"].text = path
	_stream = ChartAudio.load_stream(path)
	if _playing:
		_stop_playback()
	if _stream != null and _player != null:
		_player.stream = _stream
		_player.volume_db = float(doc.audio.get("volume_db", 0.0))
		_push_status("音频已加载：%.1f 秒" % _stream.get_length())
	elif not path.is_empty():
		_push_status("音频加载失败：%s" % path)


# ================================================================ 播放

func _set_playhead(t: float) -> void:
	_playhead = maxf(t, 0.0)
	if _timeline != null:
		_timeline.set_playhead(_playhead)
	if _preview != null:
		_preview.set_playhead(_playhead)
	if _event_panel != null:
		_event_panel.set_playhead(_playhead)
	if _event_curve != null:
		_event_curve.playhead = _playhead
		_event_curve.queue_redraw()
	if _w.has("time_label"):
		_w["time_label"].text = _fmt_time(_playhead)


func _fmt_time(sec: float) -> String:
	var m := int(sec / 60.0)
	var s := fmod(sec, 60.0)
	return "%02d:%06.3f" % [m, s]


func _toggle_play() -> void:
	if _playing:
		_stop_playback()
	else:
		_start_playback()


func _start_playback() -> void:
	_playing = true
	if _stream != null and _player != null:
		var offset := float(doc.audio.get("offset", 0.0))
		_player.stream = _stream
		_player.volume_db = float(doc.audio.get("volume_db", 0.0))
		_player.play(maxf(_playhead + offset, 0.0))
	_update_play_button()


func _stop_playback() -> void:
	_playing = false
	if _player != null:
		_player.stop()
	_update_play_button()


func _rewind() -> void:
	_stop_playback()
	_set_playhead(0.0)


func _update_play_button() -> void:
	if _w.has("play_button"):
		_w["play_button"].text = "⏸ 暂停" if _playing else "▶ 播放"


func _process(delta: float) -> void:
	_tick_playback(delta)
	_flush_status()


func _tick_playback(delta: float) -> void:
	if not _playing:
		return
	if _stream != null and _player != null and _player.playing:
		var t := _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		_set_playhead(t - float(doc.audio.get("offset", 0.0)))
	else:
		# 没有音频也允许"空放"，用挂钟推进播放头，方便无音乐先摆位置。
		_set_playhead(_playhead + delta)
		if _stream != null and _player != null and not _player.playing:
			_stop_playback()


func _flush_status() -> void:
	if not _status_pending:
		return
	var now := Time.get_ticks_msec()
	if now - _status_flushed_ms < STATUS_INTERVAL_MS:
		return
	_status_pending = false
	_status_flushed_ms = now
	_update_status()


# ================================================================ 文档字段写入

func _set_meta(key: String, value: Variant) -> void:
	if _syncing or doc == null:
		return
	doc.meta[key] = value
	_mark_dirty()


func _set_audio(key: String, value: Variant) -> void:
	if _syncing or doc == null:
		return
	doc.audio[key] = value
	_mark_dirty()


func _set_stage(key: String, value: Variant) -> void:
	if _syncing or doc == null:
		return
	doc.stage[key] = value
	_mark_dirty()
	if _timeline != null:
		_timeline.queue_redraw()
	if _preview != null:
		_preview.queue_redraw()


func _on_bpm_changed(v: float) -> void:
	if _syncing or doc == null:
		return
	doc.timing.set_bpm(v)
	if not doc.timing.bpm_events.is_empty():
		doc.timing.bpm_events[0]["bpm"] = v
	doc.timing.mark_dirty()
	_mark_dirty()
	if _timeline != null:
		_timeline.queue_redraw()


func _on_beat_offset_changed(v: float) -> void:
	if _syncing or doc == null:
		return
	doc.timing.set_beat_offset(v)
	_mark_dirty()
	if _timeline != null:
		_timeline.queue_redraw()


func _on_snap_selected(index: int) -> void:
	if doc == null or index < 0 or index >= SNAP_ITEMS.size():
		return
	doc.snap_divisor = int(SNAP_ITEMS[index]["divisor"])
	if _timeline != null:
		_timeline.queue_redraw()


func _on_lane_count_changed(v: float) -> void:
	if _syncing or doc == null:
		return
	_push_undo()
	doc.set_lane_count(int(v))
	_refresh_all()


func _add_lane() -> void:
	_push_undo()
	doc.set_lane_count(doc.lane_count() + 1)
	_refresh_all()


func _remove_lane() -> void:
	if doc.lane_count() <= 1:
		return
	_push_undo()
	doc.set_lane_count(doc.lane_count() - 1)
	_refresh_all()


func _duplicate_lane() -> void:
	var idx := _selected_lane_index()
	if idx < 0:
		return
	_push_undo()
	doc.set_lane_count(doc.lane_count() + 1)
	var src: ChartLane = doc.lanes[idx]
	var copy: ChartLane = src.duplicate_lane()
	copy.name = src.name + " copy"
	doc.lanes[doc.lane_count() - 1] = copy
	doc.stage["lane_count"] = doc.lane_count()
	_refresh_all()


func _selected_lane_index() -> int:
	if _lane_list == null:
		return -1
	return _lane_list.get_selected_items()[0] if _lane_list.get_selected_items().size() > 0 else -1


func _on_lane_list_selected(index: int) -> void:
	_on_lane_selected_index(index)


func _on_lane_selected_index(index: int) -> void:
	if _lane_list != null and index >= 0 and index < _lane_list.item_count:
		_lane_list.select(index)
	if _preview != null:
		_preview.set_highlight_lane(index)
	_sync_lane_widgets()
	_sync_edit_layer_lane(index)
	_rebuild_event_rows()


func _set_lane_prop(key: String, value: Variant) -> void:
	if _syncing or doc == null:
		return
	var idx := _selected_lane_index()
	if idx < 0 or idx >= doc.lane_count():
		return
	var lane: ChartLane = doc.lanes[idx]
	match key:
		"x":
			lane.position.x = value
		"y":
			lane.position.y = value
		"rotation":
			lane.rotation_deg = value
		"alpha":
			lane.alpha = clampi(int(round(float(value))), 0, 255)
		"length":
			lane.length_scale = value
		"volume":
			lane.volume = value
		"visible":
			lane.visible = value
	lane.clamp_values()
	_push_undo_throttled("lane_" + key)
	_mark_dirty()
	if _preview != null:
		_preview.notify_lane_changed()
	if _timeline != null:
		_timeline.queue_redraw()


func _on_zone_selected(index: int) -> void:
	if _syncing or doc == null:
		return
	var lane_index := _selected_lane_index()
	if lane_index < 0 or lane_index >= doc.lane_count():
		return
	doc.lanes[lane_index].judge_zone = ChartLane.zone_from_index(index)
	_push_undo_throttled("lane_zone")
	_mark_dirty()
	_update_lane_item(lane_index)
	if _preview != null:
		_preview.notify_lane_changed()
	if _timeline != null:
		_timeline.queue_redraw()


func _set_lane_color(c: Color) -> void:
	var idx := _selected_lane_index()
	if idx < 0 or idx >= doc.lane_count():
		return
	doc.lanes[idx].color = c
	_push_undo_throttled("lane_color")
	_mark_dirty()
	if _preview != null:
		_preview.notify_lane_changed()


## 连续拖数值时不要把撤销栈刷爆：同一属性 0.8 秒内只留一个快照。
func _push_undo_throttled(key: String) -> void:
	var now := Time.get_ticks_msec()
	if _last_undo_push.has(key) and now - int(_last_undo_push[key]) < 800:
		return
	_last_undo_push[key] = now
	_push_undo()


# ================================================================ 事件动画
#
# PhiEdit / Phigros 那套事件模型：一条事件 = 起止时间 + 起止值 + 缓动。
# 右侧面板直接列事件，主视图外还配一条曲线，肉眼确认叠加结果。

func _build_event_section(parent: Control) -> void:
	_event_panel = EventPanel.new()
	_event_panel.edit_begin.connect(_push_undo)
	_event_panel.changed.connect(_on_edited)
	parent.add_child(_event_panel)


func _build_event_section_legacy(parent: Control) -> void:
	var sec := _section(parent, "事件（动画）")
	_event_type_opt = OptionButton.new()
	for i in ChartLane.EVENT_LABELS.size():
		_event_type_opt.add_item(String(ChartLane.EVENT_LABELS[i]))
	_event_type_opt.selected = 0
	_event_type_opt.tooltip_text = "要编辑哪一类事件"
	_event_type_opt.item_selected.connect(func(_i: int) -> void: _on_event_type_changed())
	sec.add_child(_row("属性", _event_type_opt))

	_event_curve = EventCurve.new()
	_event_curve.custom_minimum_size = Vector2(0, 88)
	sec.add_child(_event_curve)

	var btns := HBoxContainer.new()
	var add_btn := Button.new()
	add_btn.text = "+ 事件"
	add_btn.tooltip_text = "在播放头处新建一条事件（长度 1 拍，起止值 = 当前值）"
	add_btn.pressed.connect(_add_event_here)
	btns.add_child(add_btn)
	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.tooltip_text = "清掉该属性的所有事件（回到静态值）"
	clear_btn.pressed.connect(_clear_events)
	btns.add_child(clear_btn)
	sec.add_child(btns)

	_event_rows = VBoxContainer.new()
	_event_rows.add_theme_constant_override("separation", 4)
	sec.add_child(_event_rows)


func _event_type() -> String:
	if _event_type_opt == null:
		return "x"
	return String(ChartLane.EVENT_TYPES[_event_type_opt.selected])


func _on_event_type_changed() -> void:
	_rebuild_event_rows()


func _event_value_range(type: String) -> Array:
	match type:
		"x", "y":
			return [-4000.0, 4000.0, 1.0]
		"rotation":
			return [-180.0, 180.0, 0.5]
		"alpha":
			return [0.0, 255.0, 1.0]
		"length":
			return [0.1, 8.0, 0.01]
	return [0.0, 1.0, 0.01]


func _sync_event_curve() -> void:
	if _event_curve == null:
		return
	_event_curve.configure(doc, _selected_lane_index(), _event_type(), _playhead)


func _rebuild_event_rows() -> void:
	if _event_panel != null and _timeline != null:
		_event_panel.select_event(_timeline.event_type, _timeline.selected_event)
	if _event_panel != null:
		_event_panel.configure(doc, _selected_lane_index(), _playhead)
	if _event_rows == null:
		return
	for child in _event_rows.get_children():
		_event_rows.remove_child(child)
		child.queue_free()
	_sync_event_curve()
	if doc == null:
		return
	var idx := _selected_lane_index()
	if idx < 0 or idx >= doc.lane_count():
		return
	var lane: ChartLane = doc.lanes[idx]
	var type := _event_type()
	var list := lane.get_events(type)
	if list.is_empty():
		var hint := Label.new()
		hint.text = "无事件 → 用静态值 %.1f" % lane.base_value(type)
		hint.clip_text = true
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		_event_rows.add_child(hint)
		return

	var rng := _event_value_range(type)
	for i in list.size():
		var ev: Dictionary = list[i]
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		# 第一行：起止时间 + 删除
		var row1 := HBoxContainer.new()
		row1.add_theme_constant_override("separation", 3)
		var start_spin := _spin(0.0, 3600.0, 0.01, float(ev.get("start", 0.0)), " s")
		start_spin.custom_minimum_size.x = 82
		start_spin.tooltip_text = "事件开始时间"
		start_spin.value_changed.connect(func(v: float) -> void:
			ev["start"] = maxf(v, 0.0)
			if float(ev["end"]) < float(ev["start"]):
				ev["end"] = ev["start"]
			_commit_events(lane, type)
		)
		row1.add_child(start_spin)
		var end_spin := _spin(0.0, 3600.0, 0.01, float(ev.get("end", 0.0)), " s")
		end_spin.custom_minimum_size.x = 82
		end_spin.tooltip_text = "事件结束时间"
		end_spin.value_changed.connect(func(v: float) -> void:
			ev["end"] = maxf(v, float(ev["start"]))
			_commit_events(lane, type)
		)
		row1.add_child(end_spin)
		var del := Button.new()
		del.text = "×"
		del.custom_minimum_size.x = 24
		del.pressed.connect(func() -> void:
			var copy: Array = lane.get_events(type).duplicate(true)
			if i < copy.size():
				copy.remove_at(i)
			_push_undo()
			lane.set_events(type, copy)
			_mark_event_changed()
			_rebuild_event_rows()
		)
		row1.add_child(del)
		card.add_child(row1)

		# 第二行：起止值 + 缓动
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 3)
		var from_spin := _spin(rng[0], rng[1], rng[2], float(ev.get("from", 0.0)))
		from_spin.custom_minimum_size.x = 62
		from_spin.tooltip_text = "起始值"
		from_spin.value_changed.connect(func(v: float) -> void:
			ev["from"] = v
			_commit_events(lane, type)
		)
		row2.add_child(from_spin)
		var to_spin := _spin(rng[0], rng[1], rng[2], float(ev.get("to", 0.0)))
		to_spin.custom_minimum_size.x = 62
		to_spin.tooltip_text = "结束值"
		to_spin.value_changed.connect(func(v: float) -> void:
			ev["to"] = v
			_commit_events(lane, type)
		)
		row2.add_child(to_spin)

		var items: Array = ChartLane.EASINGS.duplicate()
		var current := String(ev.get("ease", "linear"))
		if not items.has(current):
			items.append(current)
		var ease_opt := OptionButton.new()
		ease_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ease_opt.custom_minimum_size.x = 86
		for e in items:
			ease_opt.add_item(String(e))
		ease_opt.selected = maxi(items.find(current), 0)
		ease_opt.tooltip_text = "这条事件用哪条缓动曲线（也可手写 bezier(x1,y1,x2,y2)）"
		ease_opt.item_selected.connect(func(sel: int) -> void:
			ev["ease"] = String(items[sel])
			_commit_events(lane, type)
		)
		row2.add_child(ease_opt)
		card.add_child(row2)

		_event_rows.add_child(card)


## 事件改动统一从这里落盘：重新排序 → 标脏 → 刷新曲线/预览。
func _commit_events(lane: ChartLane, type: String) -> void:
	lane.set_events(type, lane.get_events(type))
	_mark_event_changed()


func _beat_length() -> float:
	if doc == null:
		return 0.5
	return maxf(doc.timing.beat_duration_at(doc.timing.sec_to_beat(_playhead)), 0.05)


func _add_event_here() -> void:
	if doc == null:
		return
	var idx := _selected_lane_index()
	if idx < 0 or idx >= doc.lane_count():
		return
	var lane: ChartLane = doc.lanes[idx]
	var type := _event_type()
	_push_undo()
	var start := _playhead
	var end := start + _beat_length()
	var value := lane.resolved_value(type, start)
	lane.set_events(type, ChartLane.append_event(lane.get_events(type), start, end, value, value))
	_mark_event_changed()
	_rebuild_event_rows()
	_push_status("%s 新增「%s」事件：%.2fs → %.2fs" % [
		lane.name, String(ChartLane.EVENT_LABELS[_event_type_opt.selected]), start, end])


func _clear_events() -> void:
	if doc == null:
		return
	var idx := _selected_lane_index()
	if idx < 0 or idx >= doc.lane_count():
		return
	var lane: ChartLane = doc.lanes[idx]
	var type := _event_type()
	if lane.get_events(type).is_empty():
		return
	_push_undo()
	lane.set_events(type, [])
	_mark_event_changed()
	_rebuild_event_rows()
	_push_status("%s 的「%s」事件已清空" % [
		lane.name, String(ChartLane.EVENT_LABELS[_event_type_opt.selected])])


func _mark_event_changed() -> void:
	_mark_dirty()
	_sync_event_curve()
	if _preview != null:
		_preview.notify_lane_changed()
	if _timeline != null:
		_timeline.queue_redraw()
	if doc != null:
		doc.changed.emit()


# ================================================================ 撤销 / 重做

func _push_undo() -> void:
	if doc == null or _syncing:
		return
	_undo.append(doc.snapshot())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()


func _undo_action() -> void:
	if doc == null or _undo.is_empty():
		_push_status("没有可撤销的操作")
		return
	_redo.append(doc.snapshot())
	_apply_snapshot(_undo.pop_back())
	_push_status("已撤销（剩 %d 步）" % _undo.size())


func _redo_action() -> void:
	if doc == null or _redo.is_empty():
		return
	_undo.append(doc.snapshot())
	_apply_snapshot(_redo.pop_back())
	_push_status("已重做（剩 %d 步可重做）" % _redo.size())


func _apply_snapshot(snap: Dictionary) -> void:
	_syncing = true
	doc.from_dict(snap)
	_syncing = false
	if _timeline != null:
		_timeline.select_note(null)
	_refresh_all()
	_mark_dirty()


# ================================================================ 变速点

func _add_tempo_event() -> void:
	if doc == null:
		return
	_push_undo()
	var beat := doc.timing.sec_to_beat(_playhead)
	doc.timing.bpm_events.append({"beat": snappedf(beat, 0.001), "bpm": doc.timing.bpm})
	doc.timing.bpm_events.sort_custom(func(a, b): return float(a["beat"]) < float(b["beat"]))
	doc.timing.mark_dirty()
	_mark_dirty()
	_rebuild_tempo_rows()


func _rebuild_tempo_rows() -> void:
	if _tempo_rows == null:
		return
	for child in _tempo_rows.get_children():
		child.queue_free()
	if doc == null:
		return
	for i in doc.timing.bpm_events.size():
		var ev: Dictionary = doc.timing.bpm_events[i]
		var row := HBoxContainer.new()
		var beat_spin := _spin(0.0, 100000.0, 0.001, float(ev.get("beat", 0.0)))
		beat_spin.tooltip_text = "拍位"
		beat_spin.value_changed.connect(func(v: float) -> void:
			ev["beat"] = v
			doc.timing.mark_dirty()
			_mark_dirty()
			if _timeline != null:
				_timeline.queue_redraw()
		)
		var bpm_spin := _spin(20.0, 400.0, 0.001, float(ev.get("bpm", 120.0)))
		bpm_spin.tooltip_text = "BPM"
		bpm_spin.value_changed.connect(func(v: float) -> void:
			ev["bpm"] = v
			doc.timing.mark_dirty()
			_mark_dirty()
		)
		var del := Button.new()
		del.text = "×"
		del.pressed.connect(func() -> void:
			_push_undo()
			doc.timing.bpm_events.remove_at(i)
			doc.timing.mark_dirty()
			_mark_dirty()
			_rebuild_tempo_rows()
		)
		row.add_child(beat_spin)
		row.add_child(bpm_spin)
		row.add_child(del)
		_tempo_rows.add_child(row)


# ================================================================ 刷新

func _refresh_all() -> void:
	if doc == null:
		return
	_sync_widgets()
	_rebuild_lane_list()
	_rebuild_tempo_rows()
	_sync_lane_widgets()
	_rebuild_event_rows()
	if _timeline != null:
		_timeline.queue_redraw()
	if _preview != null:
		_preview.queue_redraw()
	_status_pending = false
	_status_flushed_ms = Time.get_ticks_msec()
	_update_status()


func _sync_widgets() -> void:
	_syncing = true
	if _w.has("meta_title"):
		_w["meta_title"].text = String(doc.meta.get("title", ""))
		_w["meta_artist"].text = String(doc.meta.get("artist", ""))
		_w["meta_charter"].text = String(doc.meta.get("charter", ""))
		_w["meta_level"].value = float(doc.meta.get("level", 5))
		var diff_idx := DIFFICULTIES.find(String(doc.meta.get("difficulty", "NORMAL")))
		_w["meta_diff"].selected = diff_idx if diff_idx >= 0 else 1
		_w["audio_edit"].text = String(doc.audio.get("file", ""))
		_w["audio_offset"].value = float(doc.audio.get("offset", 0.0))
		_w["audio_vol"].value = float(doc.audio.get("volume_db", 0.0))
		_w["bpm"].value = doc.timing.bpm
		_w["beat_offset"].value = doc.timing.beat_offset
		_w["lane_count"].value = doc.lane_count()
		_w["lane_width"].value = float(doc.stage.get("lane_width", 96.0))
		_w["highway"].value = float(doc.stage.get("highway_length", 6.0))
		_w["scroll"].value = float(doc.stage.get("scroll_speed", 1.0))
		_w["judge"].value = float(doc.stage.get("judge_line_y", 0.0))
		var snap_idx := 3
		for i in SNAP_ITEMS.size():
			if int(SNAP_ITEMS[i]["divisor"]) == doc.snap_divisor:
				snap_idx = i
		_w["snap"].selected = snap_idx
	_syncing = false


func _lane_item_text(index: int) -> String:
	var lane: ChartLane = doc.lanes[index]
	var suffix := "" if lane.visible else "（隐藏）"
	return "%d  %s  [%s]  rot %.0f°  α %d  ×%.2f%s" % [
		index + 1, lane.name, ChartLane.zone_short(lane.judge_zone),
		lane.rotation_deg, lane.alpha, lane.length_scale, suffix]


func _update_lane_item(index: int) -> void:
	if _lane_list == null or index < 0 or index >= _lane_list.item_count:
		return
	_lane_list.set_item_text(index, _lane_item_text(index))
	_lane_list.set_item_custom_fg_color(index, doc.lanes[index].display_color())


func _rebuild_lane_list() -> void:
	if _lane_list == null:
		return
	var previous := _selected_lane_index()
	_lane_list.clear()
	for i in doc.lane_count():
		_lane_list.add_item(_lane_item_text(i))
		_lane_list.set_item_custom_fg_color(i, doc.lanes[i].display_color())
	var keep := clampi(previous, 0, doc.lane_count() - 1)
	_lane_list.select(keep)
	if _preview != null:
		_preview.set_highlight_lane(keep)


func _sync_lane_widgets() -> void:
	var idx := _selected_lane_index()
	if doc == null or idx < 0 or idx >= doc.lane_count():
		return
	var lane: ChartLane = doc.lanes[idx]
	_syncing = true
	_w["lane_x"].value = lane.position.x
	_w["lane_y"].value = lane.position.y
	_w["lane_rot"].value = lane.rotation_deg
	_w["lane_alpha"].value = lane.alpha
	_w["lane_len"].value = lane.length_scale
	_w["lane_vol"].value = lane.volume
	_w["lane_color"].color = lane.color
	_w["lane_zone"].selected = int(lane.judge_zone)
	_w["lane_vis"].button_pressed = lane.visible
	_syncing = false


func _on_note_selected(_note: ChartNote) -> void:
	_update_status()


func _update_status() -> void:
	if doc == null:
		return
	if _w.has("note_label"):
		var counts := doc.note_count_by_type()
		_w["note_label"].text = "音符 %d  ·  tap %d / hold %d / flick %d / mine %d  ·  BPM %.2f  ·  时长 %s" % [
			doc.notes.size(), int(counts["tap"]), int(counts["hold"]),
			int(counts["flick"]), int(counts["mine"]), doc.timing.bpm, _fmt_time(doc.total_duration())]
		var problems := doc.validate()
		_w["warn_label"].text = "" if problems.is_empty() else "⚠ %d 项提示" % problems.size()
		_w["warn_label"].tooltip_text = "\n".join(PackedStringArray(problems))
		var p := doc.path if not doc.path.is_empty() else "（未保存）"
		_w["path_label"].text = ("● " if _dirty else "") + p


func _push_status(msg: String) -> void:
	if _w.has("warn_label"):
		_w["warn_label"].text = msg
		_w["warn_label"].tooltip_text = msg


func _validate_and_report() -> void:
	var problems := doc.validate()
	if problems.is_empty():
		_push_status("校验通过，没有发现问题")
		return
	_push_status("校验发现 %d 项：%s" % [problems.size(), "；".join(PackedStringArray(problems).slice(0, 3))])
	for p in problems:
		print_rich("[color=orange][制谱器][/color] ", p)


# ================================================================ 快捷键

func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var k := event as InputEventKey
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if ctrl and k.keycode == KEY_S:
		if k.shift_pressed:
			_save_chart_as()
		else:
			_save_chart()
		accept_event()
	elif ctrl and k.keycode == KEY_O:
		_open_chart_dialog()
		accept_event()
	elif ctrl and k.keycode == KEY_N:
		_new_chart()
		accept_event()
	elif ctrl and k.keycode == KEY_Z:
		if k.shift_pressed:
			_redo_action()
		else:
			_undo_action()
		accept_event()
	elif ctrl and k.keycode == KEY_Y:
		_redo_action()
		accept_event()
	elif k.keycode == KEY_SPACE:
		_toggle_play()
		accept_event()


## 编辑器主屏幕容器给的尺寸可能比窗口还大（高 DPI + dock 叠加时会这样），
## 所以这里按"窗口逻辑尺寸 - 自己的全局位置"自己裁一个可见区域出来，
## 否则右侧面板会被推出屏幕、状态栏会掉到屏幕外。
func _on_edit_layer_selected(index: int) -> void:
	if _timeline == null:
		return
	var lane := maxi(_selected_lane_index(), 0)
	if index <= 0:
		_timeline.set_event_layer(false, "x", lane)
	else:
		_timeline.set_event_layer(true, String(ChartLane.EVENT_TYPES[index - 1]), lane)
	_push_status("编辑层：%s" % ("Note" if index <= 0 else "事件 " + String(ChartLane.EVENT_LABELS[index - 1])))


## 切换轨道时，事件层跟着切到那条轨道。
func _sync_edit_layer_lane(index: int) -> void:
	if _timeline == null:
		return
	_timeline.event_lane = maxi(index, 0)
	_timeline.queue_redraw()
