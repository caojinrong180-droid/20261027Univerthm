@tool
extends Control
## 竖版时间轴编辑视图：**横轴 = 轨道**（从左到右，和游戏键位一致），**纵轴 = 时间**。
##
## 布局分两半：
##   * 左边「音符区」：每条轨道一列，放 / 拖 / 删音符
##   * 右边「事件区」：当前选中轨道的某类事件条，底部标签页切类型
## 两半共用同一套时间坐标，所以滚动、缩放、吸附、对齐节拍线完全同步。
##
## 方向约定（downscroll 默认）：
##   * 判定线固定在画布下方 `PLAYHEAD_RATIO_DOWN` 处，**线上方全是"未来"**。
##   * 时间越大 → 屏幕越靠上；播放推进时谱面整体**向下**滚过判定线。

signal edit_begin
signal edit_changed
signal seek_requested(time_sec: float)
signal selection_changed(note)

## 左侧时间刻度栏宽度。
const GUTTER := 56.0
## 判定线高度比例：下滚靠下（上面是未来），上滚靠上（下面是未来）。
const PLAYHEAD_RATIO_DOWN := 0.76
const PLAYHEAD_RATIO_UP := 0.24
const MIN_PPS := 16.0
const MAX_PPS := 1600.0
const NOTE_PAD := 5.0
const EDGE_GRAB := 9.0
const DRAG_THRESHOLD := 3.0
const TAB_H := 24.0
## 长条可能从视口上方伸进来，往前多扫这么多条。
const CROSSING_LOOKBACK := 128

const C_BG := Color("#11141b")
const C_LANE_A := Color("#181c25")
const C_LANE_B := Color("#141821")
const C_GUTTER := Color("#0b0e14")
const C_BEAT := Color("#2b3242")
const C_BAR := Color("#4a5570")
const C_SNAP := Color("#1e2431")
const C_PLAYHEAD := Color("#ff5d8f")
const C_TEXT := Color("#8f9bb3")
const C_SEL := Color("#ffffff")

var doc: RhythmChartDocument = null
var playhead: float = 0.0
## 竖直方向每秒多少像素。
var px_per_sec: float = 220.0
## false = 下滚（判定线靠下、音符从上往下落，默认）；true = 上滚。
var upscroll: bool = false
var selected_note: RhythmChartNote = null

## 事件区当前编辑的属性与轨道（由外层同步）。
var event_type: String = "x"
var event_lane: int = 0
var selected_event: int = -1

var _drag: Dictionary = {}
var _hover_note: RhythmChartNote = null
## 自测用：headless 下确认 _draw 真的执行过。
var debug_draws: int = 0
## 自测用：本帧实际遍历了多少个音符（应当只跟视口高度有关）。
var debug_notes_visited: int = 0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_doc(new_doc: RhythmChartDocument) -> void:
	doc = new_doc
	selected_note = null
	selected_event = -1
	_drag.clear()
	queue_redraw()


func set_playhead(t: float) -> void:
	playhead = maxf(t, 0.0)
	queue_redraw()


func select_note(note: RhythmChartNote) -> void:
	selected_note = note
	selection_changed.emit(note)
	queue_redraw()


## 兼容旧调用：切事件区的属性/轨道。
func set_event_layer(_enabled: bool, type: String, lane: int) -> void:
	event_type = type
	event_lane = lane
	queue_redraw()


# ------------------------------------------------------------ 坐标换算

func judge_y() -> float:
	return size.y * (PLAYHEAD_RATIO_UP if upscroll else PLAYHEAD_RATIO_DOWN)


func time_to_y(t: float) -> float:
	var d := (t - playhead) * px_per_sec
	return judge_y() + (d if upscroll else -d)


func y_to_time(y: float) -> float:
	var d := (y - judge_y()) / px_per_sec
	return playhead + (d if upscroll else -d)


## 视口覆盖的时间区间。必须是 min/max：下滚时屏幕上边是更晚的时间。
func view_from_time() -> float:
	return minf(y_to_time(0.0), y_to_time(size.y))


func view_to_time() -> float:
	return maxf(y_to_time(0.0), y_to_time(size.y))


func lane_total() -> int:
	return maxi(doc.lane_count(), 1) if doc != null else 1


## 音符区右边界（事件区从这里开始）。
func note_area_right() -> float:
	var avail := maxf(size.x - GUTTER, 1.0)
	var ev_w := clampf(avail * 0.26, 190.0, 400.0)
	return GUTTER + maxf(avail - ev_w, 140.0)


func event_area_left() -> float:
	return note_area_right()


func lane_width_px() -> float:
	return maxf((note_area_right() - GUTTER) / float(lane_total()), 8.0)


func lane_left(index: int) -> float:
	return GUTTER + float(index) * lane_width_px()


func x_to_lane(x: float) -> int:
	return clampi(int(floorf((x - GUTTER) / lane_width_px())), 0, lane_total() - 1)


func note_height() -> float:
	return clampf(px_per_sec * 0.09, 12.0, 40.0)


func note_rect(note: RhythmChartNote) -> Rect2:
	var w := lane_width_px() - NOTE_PAD * 2.0
	var h := note_height()
	var x := lane_left(note.lane) + NOTE_PAD
	var y := time_to_y(note.time) - h * 0.5
	if note.is_long():
		var tail := time_to_y(note.end_time())
		return Rect2(Vector2(x, y), Vector2(w, maxf(tail - y, h)))
	return Rect2(Vector2(x, y), Vector2(w, h))


func lane_color(lane_index: int) -> Color:
	if doc != null and lane_index >= 0 and lane_index < doc.lanes.size():
		return doc.lanes[lane_index].display_color()
	return Color("#ffffff")


# ------------------------------------------------------------ 绘制

func _draw() -> void:
	debug_draws += 1
	debug_notes_visited = 0
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	if doc == null:
		_draw_center_text("还没有打开谱面")
		return
	_draw_lanes()
	_draw_grid()
	_draw_notes()
	_draw_event_area()
	_draw_lane_headers()
	_draw_playhead()
	_draw_ruler()


func _draw_center_text(msg: String) -> void:
	var font := get_theme_default_font()
	var fs := 15
	var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5), msg,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)


func _draw_lanes() -> void:
	for i in lane_total():
		var x := lane_left(i)
		var w := lane_width_px()
		draw_rect(Rect2(Vector2(x, 0), Vector2(w, size.y)), C_LANE_A if i % 2 == 0 else C_LANE_B)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.55), 1.0)


func _draw_grid() -> void:
	var from_t := view_from_time()
	var to_t := view_to_time()
	var beat_from := doc.timing.sec_to_beat(from_t)
	var beat_to := doc.timing.sec_to_beat(to_t)
	var divisor := maxi(doc.snap_divisor, 1)
	var px_per_beat := 60.0 / maxf(doc.timing.bpm, 1.0) * px_per_sec

	if px_per_beat / float(divisor) >= 6.0:
		for b in doc.timing.grid_beats(beat_from, beat_to, divisor):
			if absf(fmod(b, 1.0)) > 1e-6:
				var y := time_to_y(doc.timing.beat_to_sec(b))
				draw_line(Vector2(GUTTER, y), Vector2(size.x, y), C_SNAP, 1.0)

	for b in doc.timing.grid_beats(beat_from, beat_to, 1):
		var y := time_to_y(doc.timing.beat_to_sec(b))
		var bar := _is_bar_beat(b)
		draw_line(Vector2(GUTTER, y), Vector2(size.x, y), C_BAR if bar else C_BEAT, 1.5 if bar else 1.0)


## 4 拍一小节。
func _is_bar_beat(b: float) -> bool:
	var r := fposmod(b, 4.0)
	return r < 1e-4 or r > 4.0 - 1e-4


## 底部键位条（画在最上层）：下滚贴底，上滚贴顶。
func _header_top() -> float:
	return 0.0 if upscroll else size.y - 18.0


func _draw_lane_headers() -> void:
	var font := get_theme_default_font()
	var top := _header_top()
	for i in lane_total():
		var lane: RhythmChartLane = doc.lanes[i]
		var x := lane_left(i)
		var w := lane_width_px()
		var lane_col := lane.display_color()
		var strip := lane_col
		strip.a = 0.85 * maxf(lane.alpha_f(), 0.3)
		draw_rect(Rect2(Vector2(x, top), Vector2(w, 18.0)), Color(0.04, 0.05, 0.07, 0.92))
		draw_rect(Rect2(Vector2(x, top), Vector2(4.0, 18.0)), strip)
		var label := "%d %s" % [i + 1, lane.name]
		if w < 72.0:
			label = "%d" % (i + 1)
		elif lane.judge_zone != RhythmChartLane.JudgeZone.NONE and w >= 110.0:
			label += " · " + RhythmChartLane.zone_short(lane.judge_zone)
		draw_string(font, Vector2(x + 9.0, top + 13.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, w - 12.0, 10,
			Color(lane_col.r, lane_col.g, lane_col.b, 0.95 * maxf(lane.alpha_f(), 0.45)))
	var edge_y := top + 17.5 if upscroll else top
	draw_line(Vector2(GUTTER, edge_y), Vector2(note_area_right(), edge_y), Color(0, 0, 0, 0.6), 1.0)


# ------------------------------------------------------------ 音符

## 只画视口里的音符：二分找到下边界，扫到上边界就 break。
func _draw_notes() -> void:
	var from_t := view_from_time()
	var to_t := view_to_time()
	var first := doc.index_at_time(from_t)
	var back := mini(first, CROSSING_LOOKBACK)
	for j in range(first - back, first):
		var crossing: RhythmChartNote = doc.notes[j]
		if crossing.end_time() >= from_t:
			debug_notes_visited += 1
			_draw_note(crossing)
	for i in range(first, doc.notes.size()):
		var n: RhythmChartNote = doc.notes[i]
		if n.time > to_t:
			break
		if n.end_time() < from_t:
			continue
		debug_notes_visited += 1
		_draw_note(n)


func _draw_note(n: RhythmChartNote) -> void:
	var rect := note_rect(n)
	var col := lane_color(n.lane)
	if n.type == RhythmChartNote.Type.MINE:
		col = col.darkened(0.55)

	if n.is_long():
		var head_y := time_to_y(n.time)
		var tail_y := time_to_y(n.end_time())
		var cap := minf(note_height(), absf(tail_y - head_y) + note_height())
		var body := col
		body.a = 0.38
		draw_rect(Rect2(Vector2(rect.position.x + rect.size.x * 0.30, minf(head_y, tail_y)),
			Vector2(rect.size.x * 0.40, absf(tail_y - head_y))), body)
		draw_rect(Rect2(Vector2(rect.position.x, head_y - cap * 0.5),
			Vector2(rect.size.x, cap)), col)
		draw_rect(Rect2(Vector2(rect.position.x, tail_y - cap * 0.5),
			Vector2(rect.size.x, cap)), col.lightened(0.15))
		var grip_y := tail_y + (1.0 if upscroll else -1.0)
		draw_line(Vector2(rect.position.x + 3.0, grip_y),
			Vector2(rect.end.x - 3.0, grip_y), Color(1, 1, 1, 0.65), 2.0)
	else:
		draw_rect(rect, col)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2.0)), col.lightened(0.35))

	if n.type == RhythmChartNote.Type.FLICK:
		var cx := rect.position.x + rect.size.x * 0.5
		var cy := rect.position.y + rect.size.y * 0.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, cy - 5.0), Vector2(cx + 4.0, cy + 2.0), Vector2(cx - 4.0, cy + 2.0),
		]), Color(0.1, 0.1, 0.1, 0.85))
	elif n.type == RhythmChartNote.Type.MINE:
		draw_circle(rect.get_center(), minf(rect.size.y * 0.32, 8.0), Color(0.08, 0.02, 0.04))

	if n == _hover_note:
		draw_rect(rect.grow(1.0), Color(1, 1, 1, 0.35), false, 1.0)
	if n == selected_note:
		draw_rect(rect.grow(2.0), C_SEL, false, 2.0)


# ------------------------------------------------------------ 事件区

func event_col_count() -> int:
	return RhythmChartLane.EVENT_TYPES.size()


## 事件区里第 i 个属性列的矩形（不含底部标签条）。
func event_col_rect(index: int) -> Rect2:
	var left := event_area_left()
	var w := maxf(size.x - left, 1.0) / float(event_col_count())
	return Rect2(Vector2(left + w * float(index), 0.0), Vector2(w, maxf(size.y - TAB_H, 1.0)))


func _event_tab_rect(index: int) -> Rect2:
	var left := event_area_left()
	var w := maxf(size.x - left, 1.0) / float(event_col_count())
	return Rect2(Vector2(left + w * float(index), size.y - TAB_H), Vector2(w, TAB_H))


## 屏幕位置落在哪一列事件上；不在事件区返回 ""。
func event_type_at(pos: Vector2) -> String:
	if doc == null or pos.x < event_area_left():
		return ""
	var left := event_area_left()
	var w := maxf(size.x - left, 1.0) / float(event_col_count())
	var idx := clampi(int(floorf((pos.x - left) / w)), 0, event_col_count() - 1)
	return String(RhythmChartLane.EVENT_TYPES[idx])


func _event_lane_ref() -> RhythmChartLane:
	if doc == null or event_lane < 0 or event_lane >= doc.lane_count():
		return null
	return doc.lanes[event_lane]


## 事件区：X轴 / Y轴 / 角度 / 透明度 / 长度 五列并排，
## 每列只显示这一类事件，和底部标签一一对应（不再来回切）。
func _draw_event_area() -> void:
	if doc == null or event_lane < 0 or event_lane >= doc.lane_count():
		return
	var font := get_theme_default_font()
	var left := event_area_left()
	var lane: RhythmChartLane = doc.lanes[event_lane]
	var col_base := lane.display_color()

	draw_rect(Rect2(Vector2(left, 0), Vector2(size.x - left, size.y)), Color(0.055, 0.068, 0.09))
	draw_line(Vector2(left, 0), Vector2(left, size.y), Color(0, 0, 0, 0.7), 2.0)

	for i in event_col_count():
		var type := String(RhythmChartLane.EVENT_TYPES[i])
		var col_rect := event_col_rect(i)
		var active := type == event_type
		if active:
			draw_rect(col_rect, Color(col_base.r, col_base.g, col_base.b, 0.10))

		var list := lane.get_events(type)
		var x0 := col_rect.position.x + 3.0
		var x1 := col_rect.end.x - 3.0
		for k in list.size():
			var ev: Dictionary = list[k]
			var y0 := time_to_y(float(ev.get("start", 0.0)))
			var y1 := time_to_y(float(ev.get("end", 0.0)))
			var top := minf(y0, y1)
			var bottom := maxf(y0, y1)
			if bottom < 0.0 or top > size.y - TAB_H:
				continue
			var r := Rect2(Vector2(x0, top), Vector2(maxf(x1 - x0, 1.0), maxf(bottom - top, 4.0)))
			var c := col_base
			c.a = 0.30
			draw_rect(r, c)
			draw_rect(r, Color(col_base.r, col_base.g, col_base.b, 0.95), false, 1.2)
			draw_rect(Rect2(Vector2(x0, y0 - 2.5), Vector2(x1 - x0, 5.0)), Color(1, 1, 1, 0.8))
			draw_rect(Rect2(Vector2(x0, y1 - 2.5), Vector2(x1 - x0, 5.0)), Color(1, 1, 1, 0.4))
			if active and k == selected_event:
				draw_rect(r.grow(1.5), Color(1, 1, 1, 1), false, 1.5)

		draw_line(Vector2(col_rect.end.x, 0), Vector2(col_rect.end.x, size.y - TAB_H),
			Color(0, 0, 0, 0.5), 1.0)

	# 底部标签条：列名 + 当前列高亮
	draw_rect(Rect2(Vector2(left, size.y - TAB_H), Vector2(size.x - left, TAB_H)),
		Color(0.03, 0.04, 0.055))
	for i in event_col_count():
		var tab := _event_tab_rect(i)
		var type := String(RhythmChartLane.EVENT_TYPES[i])
		var active := type == event_type
		if active:
			var hi := col_base
			hi.a = 0.30
			draw_rect(tab, hi)
		draw_string(font, Vector2(tab.position.x + 3.0, tab.position.y + 16.0),
			String(RhythmChartLane.EVENT_TAB_LABELS[i]),
			HORIZONTAL_ALIGNMENT_LEFT, tab.size.x - 5.0, 9,
			Color(1, 1, 1, 0.95) if active else Color(0.58, 0.64, 0.74))


## 命中某一列里的哪条事件：{ index, part }。
func _event_at(pos: Vector2, type: String) -> Dictionary:
	var lane := _event_lane_ref()
	if lane == null or type == "":
		return {}
	var list := lane.get_events(type)
	for i in list.size():
		var ev: Dictionary = list[i]
		var y_start := time_to_y(float(ev.get("start", 0.0)))
		var y_end := time_to_y(float(ev.get("end", 0.0)))
		var top := minf(y_start, y_end)
		var bottom := maxf(y_start, y_end)
		if pos.y < top - 4.0 or pos.y > bottom + 4.0:
			continue
		if absf(pos.y - y_start) <= EDGE_GRAB:
			return {"index": i, "part": "start"}
		if absf(pos.y - y_end) <= EDGE_GRAB:
			return {"index": i, "part": "end"}
		return {"index": i, "part": "body"}
	return {}
# ------------------------------------------------------------ 播放头 / 刻度

func _draw_playhead() -> void:
	var y := judge_y()
	draw_line(Vector2(GUTTER, y), Vector2(size.x, y), C_PLAYHEAD, 2.0)
	for i in lane_total():
		var lane: RhythmChartLane = doc.lanes[i]
		var col := lane.display_color()
		col.a = 0.9 * maxf(lane.alpha_f(), 0.3)
		draw_line(Vector2(lane_left(i) + 3.0, y),
			Vector2(lane_left(i) + lane_width_px() - 3.0, y), col, 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(GUTTER - 8.0, y), Vector2(GUTTER - 1.0, y - 5.0), Vector2(GUTTER - 1.0, y + 5.0),
	]), C_PLAYHEAD)


func _draw_ruler() -> void:
	draw_rect(Rect2(Vector2(0, 0), Vector2(GUTTER, size.y)), C_GUTTER)
	draw_line(Vector2(GUTTER - 1.0, 0), Vector2(GUTTER - 1.0, size.y), Color(0, 0, 0, 0.7), 1.0)
	var font := get_theme_default_font()

	var label_step := 1.0
	for candidate in [0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0]:
		if float(candidate) * px_per_sec >= 70.0:
			label_step = float(candidate)
			break
	var from_t := maxf(view_from_time(), 0.0)
	var to_t := view_to_time()
	var t := floorf(from_t / label_step) * label_step
	var guard := 0
	while t <= to_t and guard < 2000:
		if t >= from_t:
			var y := time_to_y(t)
			if absf(y - judge_y()) >= 30.0:
				draw_line(Vector2(GUTTER - 6.0, y), Vector2(GUTTER - 1.0, y),
					Color(1, 1, 1, 0.28), 1.0)
				draw_string(font, Vector2(2.0, y + 4.0), _fmt_sec(t),
					HORIZONTAL_ALIGNMENT_RIGHT, GUTTER - 9.0, 10, C_TEXT)
		t += label_step
		guard += 1

	var beat_now := doc.timing.sec_to_beat(playhead)
	draw_rect(Rect2(1.0, judge_y() - 23.0, GUTTER - 4.0, 16.0), Color(0.04, 0.05, 0.07, 0.96))
	draw_string(font, Vector2(2.0, judge_y() - 11.0), "♪ %.2f" % beat_now,
		HORIZONTAL_ALIGNMENT_RIGHT, GUTTER - 9.0, 10, Color(1.0, 0.75, 0.85))


func _fmt_sec(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - float(m) * 60.0
	return "%d:%04.1f" % [m, s]


# ------------------------------------------------------------ 交互

func _snap(t: float, bypass: bool) -> float:
	if bypass:
		return maxf(t, 0.0)
	return doc.timing.snap_sec(t, doc.snap_divisor)


## 滚轮翻页：每次一拍，落点对齐最近的节拍线。
func _scroll_time(notches: float) -> void:
	if doc == null:
		return
	var sign := 1.0 if upscroll else -1.0
	var beat := roundf(doc.timing.sec_to_beat(playhead))
	seek_requested.emit(maxf(doc.timing.beat_to_sec(beat + sign * notches), 0.0))


func _gui_input(event: InputEvent) -> void:
	if doc == null:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	var pos := mb.position
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.ctrl_pressed:
				zoom_by(1.18, pos.y)
			else:
				_scroll_time(-1.0)
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.ctrl_pressed:
				zoom_by(1.0 / 1.18, pos.y)
			else:
				_scroll_time(1.0)
			accept_event()
		MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_drag = {"mode": "pan", "start_y": pos.y, "start_time": playhead}
			else:
				_drag.clear()
			accept_event()
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_on_left_press(pos, mb.alt_pressed, mb.double_click)
			else:
				_finish_drag()
			accept_event()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_on_right_press(pos, mb.alt_pressed)
			else:
				_finish_drag()
			accept_event()


func zoom_by(factor: float, anchor_y: float = -1.0) -> void:
	if anchor_y < 0.0:
		anchor_y = judge_y()
	var anchor_t := y_to_time(anchor_y)
	px_per_sec = clampf(px_per_sec * factor, MIN_PPS, MAX_PPS)
	seek_requested.emit(maxf(anchor_t - (anchor_y - judge_y()) / px_per_sec, 0.0))
	queue_redraw()


func _on_left_press(pos: Vector2, alt: bool, double_click: bool) -> void:
	# 左侧刻度栏 = 拖动播放头
	if pos.x < GUTTER:
		seek_requested.emit(_snap(y_to_time(pos.y), alt))
		_drag = {"mode": "scrub"}
		return

	# 事件区
	if pos.x >= event_area_left():
		_on_event_press(pos, alt)
		return

	# 音符区
	var lane := x_to_lane(pos.x)
	var hit := _note_at(pos)
	if hit != null:
		select_note(hit)
		if double_click:
			edit_begin.emit()
			_cycle_note_type(hit)
			if hit.type == RhythmChartNote.Type.HOLD and hit.duration <= 0.0:
				hit.duration = maxf(doc.timing.beat_duration_at(doc.timing.sec_to_beat(hit.time)), 0.05)
			hit.normalize()
			edit_changed.emit()
			return
		var mode := "move"
		if hit.is_long() and absf(pos.y - time_to_y(hit.end_time())) <= EDGE_GRAB:
			mode = "resize"
		_drag = {
			"mode": mode,
			"note": hit,
			"grab_t": hit.time - y_to_time(pos.y),
			"start_pos": pos,
			"moved": false,
		}
		return

	# 空白处左键：放一个 Tap
	edit_begin.emit()
	var note := doc.add_note(_snap(y_to_time(pos.y), alt), lane)
	select_note(note)
	_drag = {
		"mode": "move",
		"note": note,
		"grab_t": 0.0,
		"start_pos": pos,
		"moved": false,
	}
	edit_changed.emit()


func _cycle_note_type(n: RhythmChartNote) -> void:
	match n.type:
		RhythmChartNote.Type.TAP:
			n.type = RhythmChartNote.Type.HOLD
		RhythmChartNote.Type.HOLD:
			n.type = RhythmChartNote.Type.FLICK
		RhythmChartNote.Type.FLICK:
			n.type = RhythmChartNote.Type.MINE
		_:
			n.type = RhythmChartNote.Type.TAP


## 右键：点中音符 = 删；空白处按住往时间方向拖 = 放长条。
func _on_right_press(pos: Vector2, alt: bool) -> void:
	if pos.x < GUTTER:
		return
	if pos.x >= event_area_left():
		_delete_event_at(pos)
		return
	if _note_at(pos) != null:
		_delete_at(pos)
		return
	edit_begin.emit()
	var t0 := _snap(y_to_time(pos.y), alt)
	var note := doc.add_note(t0, x_to_lane(pos.x), RhythmChartNote.Type.HOLD)
	note.duration = maxf(doc.timing.beat_duration_at(doc.timing.sec_to_beat(t0)), 0.05)
	select_note(note)
	_drag = {
		"mode": "hold_create",
		"note": note,
		"anchor": t0,
		"start_pos": pos,
		"moved": false,
	}
	edit_changed.emit()
	queue_redraw()


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	var pos := mm.position
	if _drag.is_empty():
		var h := _note_at(pos)
		if h != _hover_note:
			_hover_note = h
			queue_redraw()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != null else Control.CURSOR_ARROW
		return

	match String(_drag.get("mode", "")):
		"pan":
			var delta_sec := (pos.y - float(_drag["start_y"])) / px_per_sec
			seek_requested.emit(maxf(float(_drag["start_time"]) - delta_sec, 0.0))
		"scrub":
			seek_requested.emit(_snap(y_to_time(pos.y), mm.alt_pressed))
		"ev_new", "ev_body", "ev_start", "ev_end":
			_on_event_drag(pos, mm.alt_pressed)
		"hold_create":
			var note: RhythmChartNote = _drag["note"]
			if note == null:
				return
			if not bool(_drag.get("moved", false)) and pos.distance_to(Vector2(_drag["start_pos"])) < DRAG_THRESHOLD:
				return
			_drag["moved"] = true
			var t := _snap(y_to_time(pos.y), mm.alt_pressed)
			var anchor := float(_drag["anchor"])
			note.type = RhythmChartNote.Type.HOLD
			note.time = minf(anchor, t)
			note.duration = maxf(absf(t - anchor), 0.01)
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
			queue_redraw()
		"move":
			var note: RhythmChartNote = _drag["note"]
			if note == null:
				return
			if not bool(_drag.get("moved", false)) and pos.distance_to(Vector2(_drag["start_pos"])) < DRAG_THRESHOLD:
				return
			_drag["moved"] = true
			note.time = _snap(y_to_time(pos.y) + float(_drag["grab_t"]), mm.alt_pressed)
			if pos.x >= GUTTER and pos.x < event_area_left():
				note.lane = x_to_lane(pos.x)
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			queue_redraw()
		"resize":
			var note: RhythmChartNote = _drag["note"]
			if note == null:
				return
			_drag["moved"] = true
			note.type = RhythmChartNote.Type.HOLD
			note.duration = maxf(_snap(y_to_time(pos.y), mm.alt_pressed) - note.time, 0.01)
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
			queue_redraw()


func _finish_drag() -> void:
	if _drag.is_empty():
		return
	var mode := String(_drag.get("mode", ""))
	var note: RhythmChartNote = _drag.get("note", null)
	_drag.clear()
	if mode == "hold_create":
		if note != null:
			if not note.normalize():
				pass
		doc.resort_notes()
		if selected_note != null:
			selection_changed.emit(selected_note)
		edit_changed.emit()
	elif mode == "move" or mode == "resize":
		if note != null:
			note.normalize()
		doc.resort_notes()
		if selected_note != null:
			selection_changed.emit(selected_note)
		edit_changed.emit()
	elif mode.begins_with("ev_"):
		edit_changed.emit()
	queue_redraw()


func _delete_at(pos: Vector2) -> void:
	var hit := _note_at(pos)
	if hit == null:
		return
	edit_begin.emit()
	doc.remove_note(hit)
	if hit == selected_note:
		select_note(null)
	edit_changed.emit()


func _note_at(pos: Vector2) -> RhythmChartNote:
	if pos.x < GUTTER or pos.x >= event_area_left():
		return null
	var from_t := view_from_time()
	var to_t := view_to_time()
	var first := doc.index_at_time(from_t)
	var back := mini(first, CROSSING_LOOKBACK)
	var best: RhythmChartNote = null
	var best_d := INF
	for j in range(first - back, first):
		var crossing: RhythmChartNote = doc.notes[j]
		if crossing.end_time() < from_t:
			continue
		var rc := note_rect(crossing)
		if rc.grow(2.0).has_point(pos):
			var dc := absf(rc.position.y + rc.size.y * 0.5 - pos.y)
			if dc < best_d:
				best_d = dc
				best = crossing
	for i in range(first, doc.notes.size()):
		var n: RhythmChartNote = doc.notes[i]
		if n.time > to_t:
			break
		if n.end_time() < from_t:
			continue
		var r := note_rect(n)
		if r.grow(2.0).has_point(pos):
			var d := absf(r.position.y + r.size.y * 0.5 - pos.y)
			if d < best_d:
				best_d = d
				best = n
	return best


# ------------------------------------------------------------ 事件交互

func _on_event_press(pos: Vector2, alt: bool) -> void:
	var lane := _event_lane_ref()
	if lane == null:
		return
	var type := event_type_at(pos)
	if type == "":
		return
	# 点哪一列就把编辑焦点切到哪一列（右侧参数窗跟着变）
	event_type = type
	selected_event = -1
	queue_redraw()

	var hit := _event_at(pos, type)
	if hit.is_empty():
		edit_begin.emit()
		var start := _snap(y_to_time(pos.y), alt)
		var end := start + maxf(doc.timing.beat_duration_at(doc.timing.sec_to_beat(start)), 0.05)
		var value := lane.resolved_value(type, start)
		lane.set_events(type, RhythmChartLane.append_event(
			lane.get_events(type), start, end, value, value))
		selected_event = lane.get_events(type).size() - 1
		_drag = {
			"mode": "ev_new",
			"index": selected_event,
			"type": type,
			"anchor": start,
			"start_pos": pos,
			"moved": false,
		}
		edit_changed.emit()
		queue_redraw()
		return
	selected_event = int(hit["index"])
	var ev: Dictionary = lane.get_events(type)[selected_event]
	_drag = {
		"mode": "ev_" + String(hit["part"]),
		"index": selected_event,
		"type": type,
		"start_pos": pos,
		"orig_start": float(ev.get("start", 0.0)),
		"orig_end": float(ev.get("end", 0.0)),
		"moved": false,
	}
	queue_redraw()


func _on_event_drag(pos: Vector2, alt: bool) -> void:
	var lane := _event_lane_ref()
	if lane == null:
		return
	var type := String(_drag.get("type", event_type))
	var list := lane.get_events(type)
	var idx := int(_drag.get("index", -1))
	if idx < 0 or idx >= list.size():
		return
	if not bool(_drag.get("moved", false)) and pos.distance_to(Vector2(_drag["start_pos"])) < DRAG_THRESHOLD:
		return
	_drag["moved"] = true
	var ev: Dictionary = list[idx]
	var t := _snap(y_to_time(pos.y), alt)
	match String(_drag["mode"]):
		"ev_new":
			var anchor := float(_drag["anchor"])
			ev["start"] = minf(anchor, t)
			ev["end"] = maxf(anchor, t)
		"ev_body":
			var span := float(_drag["orig_end"]) - float(_drag["orig_start"])
			var delta := t - _snap(y_to_time(_drag["start_pos"]), alt)
			var start := maxf(float(_drag["orig_start"]) + delta, 0.0)
			ev["start"] = start
			ev["end"] = start + span
		"ev_start":
			ev["start"] = maxf(minf(t, float(ev["end"]) - 0.01), 0.0)
		"ev_end":
			ev["end"] = maxf(t, float(ev["start"]) + 0.01)
	lane.set_events(type, list)
	queue_redraw()


func _delete_event_at(pos: Vector2) -> void:
	var lane := _event_lane_ref()
	if lane == null:
		return
	var type := event_type_at(pos)
	if type == "":
		return
	var hit := _event_at(pos, type)
	if hit.is_empty():
		return
	var list: Array = lane.get_events(type).duplicate(true)
	list.remove_at(int(hit["index"]))
	edit_begin.emit()
	lane.set_events(type, list)
	event_type = type
	selected_event = maxi(selected_event - 1, 0)
	edit_changed.emit()
	queue_redraw()
# ------------------------------------------------------------ 键盘

func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		if selected_note != null:
			edit_begin.emit()
			doc.remove_note(selected_note)
			select_note(null)
			edit_changed.emit()
			accept_event()
		return
	if event.keycode == KEY_ESCAPE:
		select_note(null)
		accept_event()
		return
	if selected_note != null and (event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT):
		edit_begin.emit()
		var delta := 1 if event.keycode == KEY_RIGHT else -1
		selected_note.lane = clampi(selected_note.lane + delta, 0, doc.lane_count() - 1)
		edit_changed.emit()
		accept_event()
		return
	if event.keycode == KEY_UP or event.keycode == KEY_DOWN:
		var vertical := 1.0 if event.keycode == KEY_DOWN else -1.0
		var dir := vertical * (1.0 if upscroll else -1.0)
		var step := doc.timing.beat_duration_at(doc.timing.sec_to_beat(playhead)) / float(maxi(doc.snap_divisor, 1))
		seek_requested.emit(maxf(playhead + dir * step, 0.0))
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hover_note != null:
			_hover_note = null
			queue_redraw()
