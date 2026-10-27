extends Node2D
## 游戏侧参考渲染器 —— 把一份 rchart 谱面按「轨道位移 / 旋转 / 透明度 / 长度」画出来。
##
## 这不是完整音游：判定、打击特效、输入映射由你自己的工程接。
## 它的作用是**把格式语义钉死**：你照着这段算，游戏里的舞台就和制谱器预览一致。
##
## 语义：
##   judge_origin = 屏幕底部中点 + stage.judge_line_y
##   lane_base    = judge_origin + lane.position
##   lane_dir     = Vector2.UP.rotated(deg_to_rad(lane.rotation_deg))   # 远离判定线
##   音符位置     = lane_base + lane_dir * ((note.time - chart_time) * 速度)
##   轨迹可视长度 = stage.highway_length * lane.length_scale * 速度
##   lane.alpha / lane.volume 只是渲染与混音提示，不影响判定。

const ChartIO := preload("res://addons/rhythm_chart_editor/core/rhythm_chart_io.gd")

@export_file("*.json") var chart_path: String = "res://charts/demo_neon_pulse.json"
@export var autoplay: bool = true
## 谱面时间每秒在屏幕上走多少像素（约等于"下落速度"）。
@export var px_per_second: float = 300.0
## 左上角那行提示。接进自己工程时可以关掉。
@export var show_hint: bool = true

var doc: RhythmChartDocument = null
var song_time: float = 0.0
var debug_draws: int = 0
## 本帧求值用的谱面时间（供 lane_base / lane_dir 等几何函数使用）。
var _now: float = 0.0


func _ready() -> void:
	var report: Array = []
	doc = ChartIO.load_file(chart_path, report)
	if doc == null:
		push_error("谱面加载失败：%s" % ", ".join(PackedStringArray(report)))
		return
	for problem in report:
		print_rich("[color=orange][chart][/color] ", problem)
	queue_redraw()


func _process(delta: float) -> void:
	if doc == null or not autoplay:
		return
	song_time += delta
	queue_redraw()


## 谱面时间：音频时间减去音频偏移。
func chart_time() -> float:
	if doc == null:
		return 0.0
	return song_time - float(doc.audio.get("offset", 0.0))


func judge_origin() -> Vector2:
	var view := get_viewport_rect().size
	var extra := float(doc.stage.get("judge_line_y", 0.0)) if doc != null else 0.0
	return Vector2(view.x * 0.5, view.y * 0.85 + extra)


## 轨道几何一律按"当前谱面时间"求值：有 motion 关键帧的轨道会动起来。
func lane_base(lane: RhythmChartLane) -> Vector2:
	return judge_origin() + lane.resolved_position(_now)


func lane_dir(lane: RhythmChartLane) -> Vector2:
	return Vector2.UP.rotated(deg_to_rad(lane.resolved_rotation(_now)))


func lane_side(lane: RhythmChartLane) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(lane.resolved_rotation(_now)))


func scroll_px_per_sec() -> float:
	var scroll := float(doc.stage.get("scroll_speed", 1.0)) if doc != null else 1.0
	return px_per_second * scroll


func lane_length_px(lane: RhythmChartLane) -> float:
	return float(doc.stage.get("highway_length", 6.0)) \
		* lane.resolved_length_scale(_now) * scroll_px_per_sec()


func _draw() -> void:
	debug_draws += 1
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("#0e1118"))
	if doc == null:
		return
	_now = chart_time()
	_draw_lanes()
	_draw_notes(_now)
	_draw_judge_line()
	_draw_hint()


## 这玩意儿是"只读参考渲染"，没有编辑功能 —— 明说出来，省得以为 F5 就是制谱器。
func _draw_hint() -> void:
	if not show_hint:
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text := "参考渲染（只读）· 白=任意键 / 紫=ASDF / 黄=JKL; · 编辑请回 Godot 编辑器顶部的「制谱器」标签"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_rect(Rect2(12.0, 10.0, text_size.x + 16.0, 24.0), Color(0.0, 0.0, 0.0, 0.45))
	draw_string(font, Vector2(20.0, 27.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.85, 0.9, 1.0, 0.92))


func _draw_lanes() -> void:
	var half_w := float(doc.stage.get("lane_width", 96.0)) * 0.5
	for lane in doc.lanes:
		var la := lane.resolved_alpha(_now)
		if not lane.visible or la <= 0.001:
			continue
		var b := lane_base(lane)
		var s := lane_side(lane) * half_w
		var d := lane_dir(lane) * lane_length_px(lane)
		var quad := PackedVector2Array([b - s, b + s, b + s + d, b - s + d])
		var lc := lane.display_color()
		var fill := lc
		fill.a = 0.10 * la
		draw_colored_polygon(quad, fill)
		var edge := lc
		edge.a = 0.55 * la
		draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]), edge, 1.5)


func _draw_notes(now: float) -> void:
	var half_w := float(doc.stage.get("lane_width", 96.0)) * 0.5
	var speed := scroll_px_per_sec()
	for i in doc.lane_count():
		var lane: RhythmChartLane = doc.lanes[i]
		var la := lane.resolved_alpha(_now)
		if not lane.visible or la <= 0.001:
			continue
		var b := lane_base(lane)
		var d := lane_dir(lane)
		var s := lane_side(lane)
		for n in doc.notes:
			if n.lane != i:
				continue
			var travel := (n.time - now) * speed
			if travel < -80.0 or travel > lane_length_px(lane) + 200.0:
				continue
			var col := lane.display_color()
			col.a = la
			if n.type == RhythmChartNote.Type.MINE:
				col = col.darkened(0.55)
				col.a = la
			var head := b + d * travel
			var half := minf(half_w * 0.82, 20.0)
			if n.is_long():
				var tail := b + d * ((n.end_time() - now) * speed)
				var body := col
				body.a = 0.4 * la
				var w := minf(half * 0.5, 12.0)
				draw_colored_polygon(PackedVector2Array([
					head - s * w, head + s * w, tail + s * w, tail - s * w,
				]), body)
				draw_colored_polygon(PackedVector2Array([
					head - s * half, head + s * half,
					head + s * half + d * 7.0, head - s * half + d * 7.0,
				]), col)
			else:
				draw_colored_polygon(PackedVector2Array([
					head - s * half - d * 7.0, head + s * half - d * 7.0,
					head + s * half + d * 7.0, head - s * half + d * 7.0,
				]), col)


func _draw_judge_line() -> void:
	var o := judge_origin()
	var half_span := 0.0
	for lane in doc.lanes:
		half_span = maxf(half_span, absf(lane.resolved_x(_now)))
	half_span += float(doc.stage.get("lane_width", 96.0)) * 0.5
	var band := float(doc.stage.get("judge_band", 26.0)) if doc != null else 26.0
	draw_rect(Rect2(Vector2(o.x - half_span, o.y - band * 0.5),
		Vector2(half_span * 2.0, band)), Color(0.91, 0.94, 1.0, 0.11))
	var edge := Color(0.91, 0.94, 1.0, 0.34)
	draw_line(Vector2(o.x - half_span, o.y - band * 0.5),
		Vector2(o.x + half_span, o.y - band * 0.5), edge, 1.0)
	draw_line(Vector2(o.x - half_span, o.y + band * 0.5),
		Vector2(o.x + half_span, o.y + band * 0.5), edge, 1.0)