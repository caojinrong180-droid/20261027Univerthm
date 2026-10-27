@tool
extends Control
## 事件曲线预览：横轴 = 时间，纵轴 = 数值，把一条轨道的某类事件画成折线。
##
## 相当于 PhiEdit 里那张曲线图的小号版：一眼看出事件叠加后值怎么走、缓动是不是想要的形状。
## 只是预览，不可交互。

const C_BG := Color("#0a0e14")
const C_GRID := Color("#1a2330")
const C_BASE := Color("#39465c")
const C_CURVE := Color("#5eead4")
const C_PLAYHEAD := Color("#ff5d8f")
const C_TEXT := Color("#6b7b91")

var doc: RhythmChartDocument = null
var lane_index: int = 0
var event_type: String = "x"
var playhead: float = 0.0

var debug_draws: int = 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(p_doc: RhythmChartDocument, p_lane: int, p_type: String, p_playhead: float) -> void:
	doc = p_doc
	lane_index = p_lane
	event_type = p_type
	playhead = maxf(p_playhead, 0.0)
	queue_redraw()


## 数值范围：把事件的起止值和静态值都算进来，留一点边距。
func value_range(lane: RhythmChartLane) -> Vector2:
	var lo := lane.base_value(event_type)
	var hi := lo
	for e in lane.get_events(event_type):
		lo = minf(lo, minf(float(e.get("from", 0.0)), float(e.get("to", 0.0))))
		hi = maxf(hi, maxf(float(e.get("from", 0.0)), float(e.get("to", 0.0))))
	if hi - lo < 1.0:
		var mid := (hi + lo) * 0.5
		lo = mid - 0.5
		hi = mid + 0.5
	var pad := (hi - lo) * 0.12
	return Vector2(lo - pad, hi + pad)


func _draw() -> void:
	debug_draws += 1
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	if doc == null or doc.lane_count() == 0 or size.x < 8.0 or size.y < 8.0:
		return
	var lane: RhythmChartLane = doc.lanes[clampi(lane_index, 0, doc.lane_count() - 1)]
	var t_end := maxf(doc.total_duration(), 1.0)
	var vr := value_range(lane)
	var pad_x := 4.0
	var pad_y := 6.0
	var w := maxf(size.x - pad_x * 2.0, 1.0)
	var h := maxf(size.y - pad_y * 2.0, 1.0)
	var font := get_theme_default_font()

	# 网格（3 条横线）
	for i in 4:
		var y := pad_y + h * float(i) / 3.0
		draw_line(Vector2(pad_x, y), Vector2(pad_x + w, y), C_GRID, 1.0)

	# 静态值参考线
	var base_y := pad_y + h * (1.0 - (lane.base_value(event_type) - vr.x) / (vr.y - vr.x))
	draw_line(Vector2(pad_x, base_y), Vector2(pad_x + w, base_y), C_BASE, 1.0)

	# 曲线：按时间采样，事件/缓动怎么叠加都能如实画出来
	var samples := int(clampf(w, 32.0, 220.0))
	var pts := PackedVector2Array()
	for i in samples + 1:
		var t := t_end * float(i) / float(samples)
		var v := lane.resolved_value(event_type, t)
		var x := pad_x + w * float(i) / float(samples)
		var y := pad_y + h * (1.0 - clampf((v - vr.x) / (vr.y - vr.x), 0.0, 1.0))
		pts.append(Vector2(x, y))
	if pts.size() >= 2:
		draw_polyline(pts, C_CURVE, 1.5)

	# 事件边界小刻度，方便对齐
	for e in lane.get_events(event_type):
		for key in ["start", "end"]:
			var x := pad_x + w * clampf(float(e.get(key, 0.0)) / t_end, 0.0, 1.0)
			draw_line(Vector2(x, size.y - 3.0), Vector2(x, size.y - 1.0), C_CURVE, 1.0)

	# 播放头
	var px := pad_x + w * clampf(playhead / t_end, 0.0, 1.0)
	draw_line(Vector2(px, pad_y - 2.0), Vector2(px, size.y - pad_y + 2.0), C_PLAYHEAD, 1.0)

	# 数值标注
	var desc := "%s  %.1f ~ %.1f" % [String(RhythmChartLane.EVENT_LABELS[
		maxi(RhythmChartLane.EVENT_TYPES.find(event_type), 0)]), vr.x, vr.y]
	draw_string(font, Vector2(pad_x + 3.0, 11.0), desc,
		HORIZONTAL_ALIGNMENT_LEFT, w, 9, C_TEXT)
