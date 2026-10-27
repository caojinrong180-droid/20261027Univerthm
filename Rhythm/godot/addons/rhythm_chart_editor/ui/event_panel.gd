@tool
extends VBoxContainer
## 事件参数面板。
##
## 只显示「当前在时间轴事件区里选中的那一条事件」的参数：
##
##   事件（动画）                     [▼]
##   起始时间 [0.00 s]  结束时间 [8.00 s]
##   起点值   [-50]     终点值   [-220]
##   缓动     [inOutQuad ▾]
##   ┌ 缓动曲线 ┐
##   └──────────┘
##
## 新建 / 删除都在时间轴右侧的事件区里做（左键拖 = 建，右键 = 删），
## 这里不再提供按钮，也不再有属性下拉和事件列表 —— 那两样在时间轴上就是可见的。

signal edit_begin
signal changed

const ChartLane := preload("res://addons/rhythm_chart_editor/core/rhythm_chart_lane.gd")
const EaseCurve := preload("res://addons/rhythm_chart_editor/ui/ease_curve.gd")

var doc: RhythmChartDocument = null
var lane_index: int = 0
var playhead: float = 0.0
## 当前选中的事件：它属于哪一类属性、第几条。
var sel_type: String = "x"
var sel_index: int = -1

var _syncing := false
var _collapsed := false

var _title: Label = null
var _toggle_btn: Button = null
var _body: VBoxContainer = null
var _start_spin: SpinBox = null
var _end_spin: SpinBox = null
var _from_spin: SpinBox = null
var _to_spin: SpinBox = null
var _ease_opt: OptionButton = null
var _ease_curve: EaseCurve = null
var _hint: Label = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_build()


func _build() -> void:
	var head := HBoxContainer.new()
	_title = Label.new()
	_title.text = "事件（动画）"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.add_theme_font_size_override("font_size", 11)
	_title.add_theme_color_override("font_color", Color(0.55, 0.62, 0.75))
	head.add_child(_title)
	_toggle_btn = Button.new()
	_toggle_btn.text = "▼"
	_toggle_btn.flat = true
	_toggle_btn.tooltip_text = "收起 / 展开事件参数"
	_toggle_btn.custom_minimum_size = Vector2(26, 20)
	_toggle_btn.pressed.connect(_on_toggle)
	head.add_child(_toggle_btn)
	add_child(head)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	add_child(_body)

	_start_spin = _make_time_spin()
	_body.add_child(_labelled("起始时间", _start_spin))
	_end_spin = _make_time_spin()
	_body.add_child(_labelled("结束时间", _end_spin))
	_from_spin = _make_value_spin()
	_body.add_child(_labelled("起点值", _from_spin))
	_to_spin = _make_value_spin()
	_body.add_child(_labelled("终点值", _to_spin))

	var ease_row := HBoxContainer.new()
	var ease_label := Label.new()
	ease_label.text = "缓动"
	ease_label.custom_minimum_size.x = 52
	ease_label.add_theme_font_size_override("font_size", 11)
	ease_row.add_child(ease_label)
	_ease_opt = OptionButton.new()
	for e in ChartLane.EASINGS:
		_ease_opt.add_item(String(e))
	_ease_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ease_opt.item_selected.connect(_on_ease_selected)
	ease_row.add_child(_ease_opt)
	_body.add_child(ease_row)

	_ease_curve = EaseCurve.new()
	_ease_curve.custom_minimum_size = Vector2(0, 44)
	_body.add_child(_ease_curve)

	_hint = Label.new()
	_hint.text = ""
	_hint.clip_text = true
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	_body.add_child(_hint)

	_start_spin.value_changed.connect(func(v: float) -> void: _write("start", v))
	_end_spin.value_changed.connect(func(v: float) -> void: _write("end", v))
	_from_spin.value_changed.connect(func(v: float) -> void: _write("from", v))
	_to_spin.value_changed.connect(func(v: float) -> void: _write("to", v))


func _make_time_spin() -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0.0
	s.max_value = 3600.0
	s.step = 0.01
	s.suffix = " s"
	return s


func _make_value_spin() -> SpinBox:
	var s := SpinBox.new()
	s.min_value = -4000.0
	s.max_value = 4000.0
	s.step = 1.0
	return s


func _labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 52
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _on_toggle() -> void:
	_collapsed = not _collapsed
	_body.visible = not _collapsed
	_toggle_btn.text = "▶" if _collapsed else "▼"


# ------------------------------------------------------------ 数据

func _lane() -> RhythmChartLane:
	if doc == null or lane_index < 0 or lane_index >= doc.lane_count():
		return null
	return doc.lanes[lane_index]


func _current_event() -> Dictionary:
	var lane := _lane()
	if lane == null or sel_index < 0:
		return {}
	var list := lane.get_events(sel_type)
	if sel_index >= list.size():
		return {}
	return list[sel_index]


func _write(key: String, value: float) -> void:
	if _syncing:
		return
	var lane := _lane()
	var ev := _current_event()
	if lane == null or ev.is_empty():
		return
	edit_begin.emit()
	match key:
		"start":
			ev["start"] = maxf(value, 0.0)
			if float(ev["end"]) < float(ev["start"]):
				ev["end"] = ev["start"]
		"end":
			ev["end"] = maxf(value, float(ev["start"]))
		"from":
			ev["from"] = value
		"to":
			ev["to"] = value
	lane.set_events(sel_type, lane.get_events(sel_type))
	changed.emit()
	_refresh()


func _on_ease_selected(index: int) -> void:
	if _syncing:
		return
	var lane := _lane()
	var ev := _current_event()
	if lane == null or ev.is_empty():
		return
	edit_begin.emit()
	ev["ease"] = String(ChartLane.EASINGS[index])
	lane.set_events(sel_type, lane.get_events(sel_type))
	_ease_curve.set_ease(String(ev["ease"]))
	changed.emit()


# ------------------------------------------------------------ 外部接口

func configure(p_doc: RhythmChartDocument, p_lane: int, p_playhead: float) -> void:
	doc = p_doc
	lane_index = p_lane
	playhead = maxf(p_playhead, 0.0)
	_refresh()


## 时间轴上选中了哪条事件（切列 / 点事件条时调用）。
func select_event(type: String, index: int) -> void:
	sel_type = type
	sel_index = index
	_refresh()


func set_playhead(t: float) -> void:
	playhead = maxf(t, 0.0)


# ------------------------------------------------------------ 刷新

func _refresh() -> void:
	if _start_spin == null:
		return
	var lane := _lane()
	var list: Array = lane.get_events(sel_type) if lane != null else []
	if sel_index >= list.size():
		sel_index = -1
	var ev := _current_event()
	var has := not ev.is_empty()

	_syncing = true
	var label := String(ChartLane.EVENT_LABELS[ChartLane.EVENT_TYPES.find(sel_type)]) \
		if ChartLane.EVENT_TYPES.has(sel_type) else sel_type
	_title.text = "事件 · %s" % label

	var range_v := [-4000.0, 4000.0, 1.0]
	match sel_type:
		"rotation":
			range_v = [-180.0, 180.0, 0.5]
		"alpha":
			range_v = [0.0, 255.0, 1.0]
		"length":
			range_v = [0.1, 8.0, 0.01]
	_from_spin.min_value = range_v[0]
	_from_spin.max_value = range_v[1]
	_from_spin.step = range_v[2]
	_to_spin.min_value = range_v[0]
	_to_spin.max_value = range_v[1]
	_to_spin.step = range_v[2]

	_start_spin.editable = has
	_end_spin.editable = has
	_from_spin.editable = has
	_to_spin.editable = has
	_ease_opt.disabled = not has

	if has:
		_start_spin.value = float(ev.get("start", 0.0))
		_end_spin.value = float(ev.get("end", 0.0))
		_from_spin.value = float(ev.get("from", 0.0))
		_to_spin.value = float(ev.get("to", 0.0))
		var ease := String(ev.get("ease", "linear"))
		var idx := ChartLane.EASINGS.find(ease)
		_ease_opt.selected = 0 if idx < 0 else idx
		_ease_curve.set_ease(ease)
		_hint.text = "第 %d / %d 条" % [sel_index + 1, list.size()]
	else:
		_ease_curve.set_ease("linear")
		_hint.text = "在时间轴右侧事件区点一条事件条" if list.is_empty() else "点一条事件条来编辑"
	_syncing = false
