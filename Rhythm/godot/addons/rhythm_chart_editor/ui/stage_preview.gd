@tool
extends Control
## 舞台预览：用游戏里那样的视角把谱面画出来，专门用来调「轨道形状」。
##
## 每条轨道独立拥有 position / rotation_deg / alpha / length_scale，
## 这里直接让它们可拖：
##   * 左键拖轨道 = 平移
##   * 右键拖轨道 = 绕轴心旋转（轨道会朝向鼠标）
## 拖完的数字立刻写回谱面文档，保存时就进了 JSON。
##
## 坐标系说明：舞台本身有一套"单位空间"（判定线在原点，1 秒 = STAGE_PX_PER_SEC 单位），
## 每一帧根据所有轨道四边形的包围盒算出一个 fit 缩放，把整个舞台塞进当前控件里 ——
## 这样无论面板多宽多窄、轨道转成什么样，都不会被裁掉。

signal edit_begin
signal edit_changed
signal lane_selected(index: int)

## 舞台单位空间里，1 秒对应多少单位（只影响预览观感，不影响谱面数据）。
const STAGE_PX_PER_SEC := 260.0
## 从播放头往前回看多少秒的音符（为了不漏掉刚越过判定线、身体还在视野里的长条）。
const NOTE_LOOKBACK_SEC := 30.0

const C_BG_TOP := Color("#10131a")
const C_BG_BOTTOM := Color("#1b2130")
const C_JUDGE := Color("#e8eefc")
const C_TEXT := Color("#7f8aa3")

var doc: RhythmChartDocument = null
var playhead: float = 0.0
var highlight_lane: int = -1

var _drag: Dictionary = {}
## 自测用：headless 下也能确认 _draw 真的被执行过。
var debug_draws: int = 0
## 自测用：本帧实际遍历了多少个音符（应当只跟视野里的数量有关）。
var debug_notes_visited: int = 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		invalidate_layout()


func set_doc(new_doc: RhythmChartDocument) -> void:
	doc = new_doc
	_drag.clear()
	invalidate_layout()
	queue_redraw()


func set_playhead(t: float) -> void:
	playhead = maxf(t, 0.0)
	queue_redraw()


func set_highlight_lane(index: int) -> void:
	highlight_lane = index
	queue_redraw()


func notify_lane_changed() -> void:
	invalidate_layout()
	queue_redraw()


# ------------------------------------------------------------ 布局适配
#
# 注意：算 layout 要遍历所有轨道求包围盒。如果每次取 lane_base() 都重算一遍，
# 那就是"每个音符 × 每条轨道"各算一次全量布局 —— 几千音符的谱面会直接把编辑器卡死。
# 所以这里缓存起来，只在 doc / 控件尺寸 / 轨道变换变化后重算。

var _lay_origin := Vector2.ZERO
var _lay_scale := 1.0
var _lay_dirty := true
## 自测用：布局重算次数（应当与音符数量无关）。
var debug_layout_calls: int = 0


func invalidate_layout() -> void:
	_lay_dirty = true


## 舞台单位空间 → 屏幕。原点 = 判定线在屏幕上的位置；
## 包围盒居中，长宽按较短的一边收缩。
func _ensure_layout() -> void:
	if not _lay_dirty:
		return
	_lay_dirty = false
	debug_layout_calls += 1
	# 固定机位：判定线钉在画布下方 86% 处，缩放只跟「静态可视长度」有关。
	# 轨道有事件动画时会照常动、跑出画面也算正常 —— 镜头不跟着跑、不自己缩放。
	var highway := 6.0
	var judge_offset := 0.0
	if doc != null:
		highway = maxf(float(doc.stage.get("highway_length", 6.0)), 0.2)
		judge_offset = float(doc.stage.get("judge_line_y", 0.0))
	var origin := Vector2(size.x * 0.5, size.y * 0.86 + judge_offset)
	var scl := clampf(maxf(size.y * 0.86, 40.0) / (highway * STAGE_PX_PER_SEC), 0.02, 4.0)
	_lay_origin = origin
	_lay_scale = scl


func layout() -> Array:
	_ensure_layout()
	return [_lay_origin, _lay_scale]


func stage_origin() -> Vector2:
	_ensure_layout()
	return _lay_origin


func stage_scale() -> float:
	_ensure_layout()
	return _lay_scale


func lane_width_units() -> float:
	return float(doc.stage.get("lane_width", 96.0)) if doc != null else 96.0


func lane_length_units(lane: RhythmChartLane) -> float:
	return float(doc.stage.get("highway_length", 6.0)) \
		* lane.resolved_length_scale(playhead) * STAGE_PX_PER_SEC


## 单位空间里的一段时间 → 屏幕像素（音符位移用这个）。
func travel_px(dt_sec: float) -> float:
	return dt_sec * STAGE_PX_PER_SEC * stage_scale()


## 动画采样点：所有关键帧时间 + 0。用来算"整段动画的包围盒"，
## 这样轨道在动的时候，自动适配的缩放是稳定的，不会跟着抖。
func _sample_times(lane: RhythmChartLane) -> PackedFloat64Array:
	var times := PackedFloat64Array([0.0])
	for type in RhythmChartLane.EVENT_TYPES:
		for e in lane.get_events(String(type)):
			times.append(float(e.get("start", 0.0)))
			times.append(float(e.get("end", 0.0)))
	times.sort()
	var out := PackedFloat64Array()
	for t in times:
		if out.is_empty() or absf(out[out.size() - 1] - t) > 0.0001:
			out.append(t)
	if out.size() > 32:
		var thinned := PackedFloat64Array()
		var step := float(out.size() - 1) / 31.0
		for i in 32:
			thinned.append(out[int(round(float(i) * step))])
		return thinned
	return out


func _lane_length_units_at(lane: RhythmChartLane, t: float) -> float:
	return float(doc.stage.get("highway_length", 6.0)) \
		* lane.resolved_length_scale(t) * STAGE_PX_PER_SEC


# ------------------------------------------------------------ 几何（屏幕坐标）
#
# 注意：这里一律用 resolved_*（在当前播放头那一刻求值），
# 所以轨道有关键帧动画时，预览里会跟着时间动 —— 和游戏里一致。

func lane_rotation(lane: RhythmChartLane) -> float:
	return lane.resolved_rotation(playhead)


func lane_dir(lane: RhythmChartLane) -> Vector2:
	return Vector2.UP.rotated(deg_to_rad(lane_rotation(lane)))


func lane_side(lane: RhythmChartLane) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(lane_rotation(lane)))


func lane_base(lane: RhythmChartLane) -> Vector2:
	return stage_origin() + lane.resolved_position(playhead) * stage_scale()


func lane_alpha(lane: RhythmChartLane) -> float:
	return lane.resolved_alpha(playhead)


func lane_half_width() -> float:
	return lane_width_units() * 0.5 * stage_scale()


func lane_length_px(lane: RhythmChartLane) -> float:
	return lane_length_units(lane) * stage_scale()


func lane_quad(lane: RhythmChartLane) -> PackedVector2Array:
	var b := lane_base(lane)
	var s := lane_side(lane) * lane_half_width()
	var d := lane_dir(lane) * lane_length_px(lane)
	return PackedVector2Array([b - s, b + s, b + s + d, b - s + d])


# ------------------------------------------------------------ 绘制

func _draw() -> void:
	debug_draws += 1
	debug_notes_visited = 0
	# 每帧最多重算一次布局；拖轨道时轨道变换变了，靠这里拿到新值。
	invalidate_layout()
	_draw_background()
	if doc != null and doc.lane_count() > 0:
		_draw_lanes()
		_draw_notes()
		_draw_judge_line()
	_draw_hud()


func _draw_background() -> void:
	var bands := 12
	for i in bands:
		var t := float(i) / float(bands - 1)
		var col := C_BG_TOP.lerp(C_BG_BOTTOM, t)
		draw_rect(Rect2(0.0, size.y * t, size.x, size.y / float(bands) + 1.0), col)


func _draw_lanes() -> void:
	for i in doc.lane_count():
		var lane: RhythmChartLane = doc.lanes[i]
		var a := lane_alpha(lane)
		if not lane.visible or a <= 0.001:
			continue
		var quad := lane_quad(lane)
		var lc := lane.display_color()
		var fill := lc
		fill.a = 0.10 * a
		draw_colored_polygon(quad, fill)
		var edge := lc
		edge.a = 0.55 * a
		draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]), edge, 1.5)
		if i == highlight_lane:
			draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]),
				Color(1, 1, 1, 0.85), 2.0)
		# 轴心小方块：说明"旋转是绕这里转的"
		var b := lane_base(lane)
		draw_rect(Rect2(b - Vector2(3, 3), Vector2(6, 6)), lc)


## 单趟遍历所有音符：每条轨道的几何先取一次缓存下来，
## 再按时间升序扫一遍（doc.notes 已排序，越过视野尽头就 break）。
## 老写法是"每轨 × 每个音符"，几千音符时会卡。
func _draw_notes() -> void:
	var count := doc.lane_count()
	var bases: Array[Vector2] = []
	var dirs: Array[Vector2] = []
	var sides: Array[Vector2] = []
	var alphas: Array[float] = []
	var colors: Array[Color] = []
	var max_len := 0.0
	for i in count:
		var lane: RhythmChartLane = doc.lanes[i]
		bases.append(lane_base(lane))
		dirs.append(lane_dir(lane))
		sides.append(lane_side(lane))
		colors.append(lane.display_color())
		var la := lane_alpha(lane)
		alphas.append(la if (lane.visible and la > 0.001) else 0.0)
		max_len = maxf(max_len, lane_length_px(lane))

	var speed := STAGE_PX_PER_SEC * stage_scale()
	var half := lane_half_width() * 0.82
	var limit := max_len + 200.0
	# 从播放头前 30 秒开始扫（二分定位）：既不会漏掉刚过头、身体还在视野里的长条，
	# 也不会把前面几千个已经播完的音符过一遍。
	var start := doc.index_at_time(playhead - NOTE_LOOKBACK_SEC)
	for i in range(start, doc.notes.size()):
		var n: RhythmChartNote = doc.notes[i]
		debug_notes_visited += 1
		var travel := (n.time - playhead) * speed
		if travel > limit:
			break
		if n.lane < 0 or n.lane >= count:
			continue
		# 越过判定区的 Tap 立刻收掉；长条只要尾巴还在判定区里就继续画
		if travel < 0.0 and not (n.is_long() and n.end_time() >= playhead):
			continue
			continue
		var a: float = alphas[n.lane]
		if a <= 0.001:
			continue
		var base: Vector2 = bases[n.lane]
		var d: Vector2 = dirs[n.lane]
		var s: Vector2 = sides[n.lane]
		var head := base + d * travel
		var col: Color = colors[n.lane]
		col.a = a
		# 颜色只表示判定区；地雷压暗区分
		if n.type == RhythmChartNote.Type.MINE:
			col = col.darkened(0.55)
			col.a = a
		if n.is_long():
			var tail := base + d * ((n.end_time() - playhead) * speed)
			var body := col
			body.a = 0.45 * a
			var w := minf(half * 0.5, 14.0)
			draw_colored_polygon(PackedVector2Array([
				head - s * w, head + s * w, tail + s * w, tail - s * w,
			]), body)
			draw_colored_polygon(PackedVector2Array([
				head - s * w - d * 4.0, head + s * w - d * 4.0,
				head + s * w + d * 4.0, head - s * w + d * 4.0,
			]), col)
		else:
			var nw := minf(half * 0.7, 18.0)
			var nh := 6.0
			draw_colored_polygon(PackedVector2Array([
				head - s * nw - d * nh, head + s * nw - d * nh,
				head + s * nw + d * nh, head - s * nw + d * nh,
			]), col)


func _draw_judge_line() -> void:
	var o := stage_origin()
	var half_span := lane_width_units() * 0.5 * stage_scale()
	for lane in doc.lanes:
		half_span = maxf(half_span, absf(lane.resolved_x(playhead) * stage_scale()) + lane_half_width())
	var band := clampf(size.y * 0.06, 12.0, 34.0)
	draw_rect(Rect2(Vector2(o.x - half_span, o.y - band * 0.5),
		Vector2(half_span * 2.0, band)), Color(0.91, 0.94, 1.0, 0.11))
	var edge := Color(0.91, 0.94, 1.0, 0.34)
	draw_line(Vector2(o.x - half_span, o.y - band * 0.5),
		Vector2(o.x + half_span, o.y - band * 0.5), edge, 1.0)
	draw_line(Vector2(o.x - half_span, o.y + band * 0.5),
		Vector2(o.x + half_span, o.y + band * 0.5), edge, 1.0)
	for i in doc.lane_count():
		var lane: RhythmChartLane = doc.lanes[i]
		var b := lane_base(lane)
		var s := lane_side(lane) * lane_half_width()
		var col := lane.display_color()
		col.a = 0.9 * lane_alpha(lane)
		draw_line(b - s, b + s, col, 3.0)


func _draw_hud() -> void:
	var font := get_theme_default_font()
	var text := "舞台预览 · 左键拖移动 / 右键拖旋转 · 自动适配"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	draw_rect(Rect2(4.0, 3.0, text_size.x + 10.0, 17.0), Color(0.0, 0.0, 0.0, 0.45))
	draw_string(font, Vector2(9.0, 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	if not _drag.is_empty() and doc != null:
		var lane: RhythmChartLane = doc.lanes[int(_drag.get("lane", 0))]
		var pos := lane.resolved_position(playhead)
		var info := "%s  pos=(%.0f, %.0f)  rot=%.1f°  α=%d/255  len=%.2f" % [
			lane.name, pos.x, pos.y, lane.resolved_rotation(playhead),
			int(round(lane.resolved_alpha_255(playhead))), lane.resolved_length_scale(playhead)]
		var info_size := font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		draw_rect(Rect2(4.0, size.y - 22.0, info_size.x + 10.0, 18.0), Color(0.0, 0.0, 0.0, 0.5))
		draw_string(font, Vector2(9.0, size.y - 8.0), info,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))


# ------------------------------------------------------------ 交互

func lane_at_point(p: Vector2) -> int:
	if doc == null:
		return -1
	var scl := stage_scale()
	if scl <= 0.0:
		return -1
	var stage_p := (p - stage_origin()) / scl
	var half_w := lane_width_units() * 0.5
	var slack := 12.0 / scl
	# 逆序：后画的轨道在上层，先命中它。
	for i in range(doc.lane_count() - 1, -1, -1):
		var lane: RhythmChartLane = doc.lanes[i]
		if not lane.visible or lane_alpha(lane) <= 0.001:
			continue
		var rel := stage_p - lane.resolved_position(playhead)
		var along := rel.dot(lane_dir(lane))
		var across := rel.dot(lane_side(lane))
		if along >= -slack and along <= lane_length_units(lane) and absf(across) <= half_w:
			return i
	return -1


## 拖动写回静态值。注意：该属性若有事件动画，事件会盖过静态值 —— 面板里改事件才对。
func _apply_lane_position(lane: RhythmChartLane, new_pos: Vector2, _ease_hint: String = "linear") -> void:
	lane.position = Vector2(
		clampf(new_pos.x, -4000.0, 4000.0),
		clampf(new_pos.y, -4000.0, 4000.0))


func _apply_lane_rotation(lane: RhythmChartLane, deg: float, _ease_hint: String = "linear") -> void:
	lane.rotation_deg = deg
	lane.clamp_values()


func _gui_input(event: InputEvent) -> void:
	if doc == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			var idx := lane_at_point(mb.position)
			if idx < 0:
				return
			lane_selected.emit(idx)
			edit_begin.emit()
			_drag = {
				"lane": idx,
				"mode": "move" if mb.button_index == MOUSE_BUTTON_LEFT else "rotate",
				"last": mb.position,
			}
			accept_event()
		elif not mb.pressed and not _drag.is_empty():
			_drag.clear()
			edit_changed.emit()
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		var mm := event as InputEventMouseMotion
		var lane: RhythmChartLane = doc.lanes[int(_drag["lane"])]
		if String(_drag["mode"]) == "move":
			# 以"当前显示的位置"为基准做增量，动画轨道上拖也不会跳
			var delta := (mm.position - Vector2(_drag["last"])) / maxf(stage_scale(), 0.001)
			_apply_lane_position(lane, lane.resolved_position(playhead) + delta)
		else:
			var rel := mm.position - stage_origin()
			_apply_lane_rotation(lane, rad_to_deg(atan2(rel.x, -rel.y)))
		_drag["last"] = mm.position
		invalidate_layout()
		edit_changed.emit()
		queue_redraw()
		accept_event()