class_name StageView
extends Control
## 1:1 复刻网页版制谱器的「预渲染窗口」（web/js/editor.js → drawPreview 那一套）。
##
## 逻辑舞台 **350 × 196.875（16:9）**，正好铺满 16:9 窗口：
##   judgeY = round(H*0.85) = 167
##   laneWidth = min(W*0.05, W*0.43/N) * PV_SCALE(1.75) = 30.6（4 轨）
##   halfW = 14.81，音符半宽 13.81，音符半厚 NOTE_TH = 2.0，判定线 = 底部实心加粗横条（halfW×0.36）
## 谱面里的 x / y 像素值就是按这套逻辑尺寸定的，所以这里只在逻辑坐标里画，
## 最后整体等比缩放到窗口：
##   scale  = min(size.x / 350, size.y / 196.875)
##   origin = 居中（+ 画面垂直偏移）
##
## 逐函数对照 editor.js：
##   drawPreview()      → _draw()
##   drawLaneBody()     → _draw_lane_body()
##   drawPreviewNotes() → _draw_notes()
##   drawLaneJudge()    → _draw_lane_judge()
##   laneGeom / noteQuad / bandQuad → _lane_geom / _lane_shape / _band_quad（音符和轨道都带圆角）
## 颜色、透明度、线宽、绘制顺序、剔除规则都照抄；预渲染窗口里没有的东西
## （曲绘背景、渐变、键位字、打击特效）不在舞台本体里，特效单独画在屏幕坐标上，
## 当作「游戏反馈」，设置里可以关。

const STAGE_W := 350.0
const STAGE_H := 350.0 * 9.0 / 16.0   # 16:9 舞台：350 × 196.875
## 轨道 / 音符的整体放大倍数（editor.js 的 PV_SCALE）
const PV_SCALE := 1.75
const NOTE_TH := 2.0
## 音符 / 长条的圆角（逻辑像素）
const NOTE_RADIUS := 2.4
## 底部判定线粗细 = halfW × 这个比例（1.6 时 halfW=13.5 → 约 4.9）
const JUDGE_LINE_RATIO := 0.36

## 判定环：从 FX_RING_START 扩散到 +FX_RING_GROW，线宽 FX_RING_WIDTH（随时间略收细）
const FX_RING_START := 9.0
const FX_RING_GROW := 78.0
const FX_RING_WIDTH := 7.0
const FX_RING_LIFE := 0.55
## Bad：音符自己渐变消失；判定线同时闪红
const BAD_FADE_TIME := 0.25
const BAD_FLASH_TIME := 0.42
const BAD_TINT := Color("#ff2d55")
const MAX_FX := 48
## 多押判定容差：两个音符时间差在这个范围内算「同时」
const CHORD_EPS := 0.02
## 多押外圈发光色（Phigros 那种偏冷的蓝）
const CHORD_GLOW := Color("#57c8ff")

var chart: Dictionary = {}
var judge: RhythmJudge = null
var settings: AppSettings = null
## 预渲染窗口不画曲绘；这个字段留着给以后美化用
var cover: Texture2D = null

var chart_time := 0.0
var pressed_zones: Array = []
var autoplay := false
## 顶部进度条用的总时长（gameplay 会把音频/谱面长度写进来）
var song_length := 0.0

var _lane_count := 0
var _notes_by_lane: Array = []
## 每条轨道上次 Bad 的时间（判定线闪红用）
var _bad_flash: Array = []
## Bad 淡出中的音符：画在判定线之后（不被判定条和红光盖住）
var _bad_fade_notes: Array = []
## 绘制时往前回看多少秒（保证超长的 hold 不会被提前剔除）
var _hold_lookback := 4.0

var _fx: Array = []            # 判定环：[{ lane, t, result }]

var _last_draw_time := 0.0


func setup(chart_: Dictionary, judge_: RhythmJudge, settings_: AppSettings, cover_: Texture2D) -> void:
	chart = chart_
	judge = judge_
	settings = settings_
	cover = cover_
	var lanes_arr = chart.get("lanes", [])
	_lane_count = int(lanes_arr.size()) if lanes_arr is Array else 0
	_notes_by_lane = []
	_bad_flash = []
	for i in _lane_count:
		_notes_by_lane.append([])
		_bad_flash.append(-1000.0)
	_hold_lookback = 4.0
	for n in chart.get("notes", []):
		var li := int(n.get("lane", 0))
		if li >= 0 and li < _lane_count:
			_notes_by_lane[li].append(n)

	# 长条再长也要能被看见：绘制回看窗口 = max(最长春条 × 最大流速, 4 秒)
	var max_speed := 1.0
	for lane in chart.get("lanes", []):
		var evs = lane.get("events", {})
		if evs is Dictionary:
			for e in evs.get("speed", []):
				max_speed = maxf(max_speed, absf(float(e.get("from", 1.0))))
				max_speed = maxf(max_speed, absf(float(e.get("to", 1.0))))
	for n in chart.get("notes", []):
		if str(n.get("type", "")) == "hold":
			_hold_lookback = maxf(_hold_lookback, float(n.get("duration", 0.0)) * max_speed)
	_hold_lookback = minf(_hold_lookback, 60.0)     # 再离谱的谱面也不用扫更远

	_mark_chords()

	if judge != null:
		judge.note_judged.connect(_on_note_judged)
		judge.hold_completed.connect(_on_hold_completed)


## 标出「多押」：同一时刻（±CHORD_EPS）有两个以上可判定音符时，给它们挂上 chord 数量，
## 画的时候外圈镀一层蓝光（类似 Phigros 的多指提示）。地雷不算。
func _mark_chords() -> void:
	var notes: Array = chart.get("notes", [])
	var i := 0
	while i < notes.size():
		var t := float(notes[i]["time"])
		var j := i
		var group: Array = []
		while j < notes.size() and absf(float(notes[j]["time"]) - t) <= CHORD_EPS:
			group.append(notes[j])
			j += 1
		if group.size() >= 2:
			for n in group:
				n["chord"] = group.size()
		i = j


## 0 = 关，1 = 标准，2 = 强
func fx_level() -> int:
	return int(settings.hit_fx) if settings != null else 2


func _has_fx() -> bool:
	return fx_level() > 0


func stage_scale() -> float:
	if size.x < 2.0 or size.y < 2.0:
		return 1.0
	return minf(size.x / STAGE_W, size.y / STAGE_H)


## 4:3 舞台在窗口里的矩形（居中，左右或上下留黑边；位置取整避免半像素发虚）
## settings.stage_offset_px 可以整体上下微调（默认 0，和预渲染严格对齐）
func stage_rect() -> Rect2:
	var scale := stage_scale()
	var stage_size := Vector2(STAGE_W, STAGE_H) * scale
	var offset_y := settings.stage_offset_px if settings != null else 0.0
	var pos := (((size - stage_size) * 0.5) + Vector2(0.0, offset_y)).round()
	return Rect2(pos, stage_size)


# --------------------------------------------------------------------------- #
# 绘制（逻辑坐标：350 × 262.5）
# --------------------------------------------------------------------------- #

func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0 or _lane_count <= 0:
		return

	var scale := stage_scale()
	var base_origin := stage_rect().position
	var origin := base_origin

	# 屏震（屏幕像素）
	var dt := maxf(0.0, chart_time - _last_draw_time)
	_last_draw_time = chart_time

	# 16:9 窗口里，4:3 舞台外面先铺一层底色（和舞台同色，看起来就是一块纯渲染）
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG_DEEP)
	draw_set_transform(origin, 0.0, Vector2(scale, scale))

	# 预渲染窗口就是一块 #080a0e
	draw_rect(Rect2(0, 0, STAGE_W, STAGE_H), Palette.BG_DEEP)

	var lane_count := _lane_count
	var judge_y := roundf(STAGE_H * 0.85)
	var lane_w := minf(STAGE_W * 0.05, (STAGE_W * 0.43) / float(lane_count)) * PV_SCALE
	var half_w := maxf(2.0, lane_w / 2.0 - 0.5)
	var note_half_w := maxf(2.0, half_w - 1.0)

	# pps = judgeY / 可视秒数；可视秒数默认取谱面的 stage.highway_length（和制谱器一致）
	var speed_mult := 1.0
	if settings != null:
		speed_mult = settings.speed_mult
	var highway := 2.0
	var stage_cfg = chart.get("stage", {})
	if stage_cfg is Dictionary:
		highway = float(stage_cfg.get("highway_length", 2.0))
	var visible_sec := maxf(0.05, highway / maxf(0.05, speed_mult))
	var base_pps := judge_y / visible_sec

	var lanes: Array = []
	for i in lane_count:
		lanes.append(_lane_geom(i, judge_y, half_w))

	# 1) 轨道本体
	for i in lane_count:
		_draw_lane_body(lanes[i])

	# 2) 音符
	_bad_fade_notes.clear()
	for i in lane_count:
		_draw_notes(i, lanes[i], base_pps, note_half_w)

	# 3) 判定线
	for i in lane_count:
		_draw_lane_judge(i, lanes[i])

	# 3.5) Bad 淡出的音符画在判定线之上（它已经在判定线下方，别被判定条盖住）
	for item in _bad_fade_notes:
		var binfo: Dictionary = item["info"]
		var bhw := float(item["half_w"])
		draw_colored_polygon(
			_lane_shape(binfo, float(item["d"]), bhw * 2.0, NOTE_TH * 2.0,
				minf(NOTE_RADIUS, minf(bhw, NOTE_TH))),
			Palette.alpha(item["color"], 0.92 * float(item["alpha"])))

	# 回到屏幕坐标：打击特效按屏幕像素画（锚点已经在命中那一刻拍好了）
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_fx()
	# 把舞台外的部分盖掉，保证任何离谱的 x/y/length 都画不出 16:9 舞台
	_draw_letterbox(base_origin, scale)
	# 最后叠一层极简 HUD：顶部进度条 + 左上 Combo + 右上分数/准确率 + 左下曲名 + 右下等级
	_draw_hud()


## laneGeom()：一条轨道在 t 时刻的几何
func _lane_geom(index: int, judge_y: float, half_w: float) -> Dictionary:
	var lane: Dictionary = chart["lanes"][index]
	var p := RhythmChart.lane_params_at(lane, chart_time)
	# 父线 / 爷爷线一起叠进来：子线的 x/y/rotation 都是相对父线的
	var frame := RhythmChart.lane_frame_at(chart["lanes"], index, chart_time)
	var rad := deg_to_rad(float(frame["rot"]))
	return {
		"lane": lane,
		"alpha": RhythmChart.alpha_value(p),
		"speed": RhythmChart.speed_mult(p),
		"half": half_w,
		"len": judge_y * RhythmChart.length_scale(p),
		"cx": STAGE_W * 0.5 + float(frame["x"]),
		"cy": judge_y - float(frame["y"]),      # Y 向上为正
		"dx": sin(rad),
		"dy": -cos(rad),
		"sx": cos(rad),
		"sy": sin(rad),
		"color": RhythmChart.display_color_at(lane, chart_time),
		"x": float(frame["x"]),
		"y": float(frame["y"]),
		"rot": float(frame["rot"]),
		"zone": RhythmChart.lane_zone_at(lane, chart_time),
	}


func _lane_point(info: Dictionary, d: float) -> Vector2:
	return Vector2(float(info["cx"]) + float(info["dx"]) * d,
		float(info["cy"]) + float(info["dy"]) * d)


## bandQuad()：沿轨道方向从 d0 到 d1 的一条带
func _band_quad(info: Dictionary, d0: float, d1: float, half: float) -> PackedVector2Array:
	var a := _lane_point(info, d0)
	var b := _lane_point(info, d1)
	var sx := float(info["sx"])
	var sy := float(info["sy"])
	return PackedVector2Array([
		Vector2(a.x - sx * half, a.y - sy * half),
		Vector2(a.x + sx * half, a.y + sy * half),
		Vector2(b.x + sx * half, b.y + sy * half),
		Vector2(b.x - sx * half, b.y - sy * half),
	])




## 圆角矩形（本地坐标，中心在原点；x 横 / y 竖），返回顺时针点列
static func _rounded_rect(w: float, h: float, r: float, segs := 8) -> PackedVector2Array:
	var hw := w * 0.5
	var hh := h * 0.5
	var rr := clampf(r, 0.0, minf(hw, hh))
	if rr <= 0.01:
		return PackedVector2Array([
			Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh),
		])
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(hw - rr, -hh + rr), -PI * 0.5],   # 右上
		[Vector2(hw - rr, hh - rr), 0.0],          # 右下
		[Vector2(-hw + rr, hh - rr), PI * 0.5],    # 左下
		[Vector2(-hw + rr, -hh + rr), PI],         # 左上
	]
	for c in corners:
		var center: Vector2 = c[0]
		var start := float(c[1])
		for i in segs + 1:
			var a := start + (PI * 0.5) * (float(i) / float(segs))
			pts.append(center + Vector2(cos(a), sin(a)) * rr)
	return pts


## 把本地圆角矩形贴到轨道坐标系：中心在「距判定线 d」处，宽 w（沿轨道横向）、高 h（沿轨道方向）
func _lane_shape(info: Dictionary, d: float, w: float, h: float, r: float) -> PackedVector2Array:
	var local := _rounded_rect(w, h, r)
	var c := _lane_point(info, d)
	var sx := float(info["sx"])
	var sy := float(info["sy"])
	var dx := float(info["dx"])
	var dy := float(info["dy"])
	var out := PackedVector2Array()
	for p in local:
		out.append(Vector2(c.x + sx * p.x + dx * p.y, c.y + sy * p.x + dy * p.y))
	return out


## 本地坐标 (x 沿轨道横向, y 沿轨道方向) → 舞台坐标
func _lane_local_point(info: Dictionary, d: float, x: float, y: float) -> Vector2:
	var c := _lane_point(info, d)
	var sx := float(info["sx"])
	var sy := float(info["sy"])
	var dx := float(info["dx"])
	var dy := float(info["dy"])
	return Vector2(c.x + sx * x + dx * y, c.y + sy * x + dy * y)


## 长条身体：靠尾那一端圆角 + 渐变透明，靠头那一端默认直角（和头无缝接上）
## `r_head > 0` 时靠头那端也圆角——用在「头已经贴到判定线」的时候：
## 此时头被判定线裁掉一半、快看不见了，身体自己带个圆角帽，就不会留下一个方缺口。
## （纯粹是画法，判定、计分都不受影响）
func _draw_hold_body(info: Dictionary, d0: float, d1: float, half: float, r_tail: float,
		r_head: float, col: Color, alpha_mul: float, fade_scale := 1.0) -> void:
	var h := maxf(0.0, d1 - d0)
	if h <= 0.01:
		return
	var rt := clampf(r_tail, 0.0, minf(half, h * 0.5))
	var rh := clampf(r_head, 0.0, minf(half, h * 0.5))
	if rt + rh > h:
		rh = maxf(0.0, h - rt)
	var pts := PackedVector2Array()
	var dist := PackedFloat32Array()                                  # 每个点距判定线多远，用来算渐变
	var segs := 8

	# 靠头那端（d0）：左下圆角 180°→270° → 底边 → 右下圆角 270°→360°
	if rh > 0.01:
		for i in segs + 1:
			var a := PI + (PI * 0.5) * (float(i) / float(segs))
			var dd := d0 + rh + sin(a) * rh
			pts.append(_lane_local_point(info, dd, -half + rh + cos(a) * rh, 0.0))
			dist.append(dd)
	else:
		pts.append(_lane_local_point(info, d0, -half, 0.0))
		dist.append(d0)
	pts.append(_lane_local_point(info, d0, half - rh, 0.0))
	dist.append(d0)
	if rh > 0.01:
		for i in segs + 1:
			var a := PI * 1.5 + (PI * 0.5) * (float(i) / float(segs))
			var dd := d0 + rh + sin(a) * rh
			pts.append(_lane_local_point(info, dd, half - rh + cos(a) * rh, 0.0))
			dist.append(dd)

	# 右侧往上
	pts.append(_lane_local_point(info, d0 + h - rt, half, 0.0))
	dist.append(d0 + h - rt)

	# 靠尾那端（d1）：右上圆角 0°→90° → 顶边 → 左上圆角 90°→180°
	if rt > 0.01:
		for i in segs + 1:
			var a := (PI * 0.5) * (float(i) / float(segs))
			var dd := d0 + h - rt + sin(a) * rt
			pts.append(_lane_local_point(info, dd, half - rt + cos(a) * rt, 0.0))
			dist.append(dd)
	pts.append(_lane_local_point(info, d0 + h, -half + rt, 0.0))
	dist.append(d0 + h)
	if rt > 0.01:
		for i in segs + 1:
			var a := PI * 0.5 + (PI * 0.5) * (float(i) / float(segs))
			var dd := d0 + h - rt + sin(a) * rt
			pts.append(_lane_local_point(info, dd, -half + rt + cos(a) * rt, 0.0))
			dist.append(dd)

	# 左侧往下，闭合
	pts.append(_lane_local_point(info, d0 + rh, -half, 0.0))
	dist.append(d0 + rh)
	# 尾端一段慢慢透明掉：头部保持实心，尾巴渐隐
	# （已经判 Miss / 断掉的 hold 是压暗后再画的，渐变缩一半，免得整条都看不见）
	# 不能是 0：0 会让下面的除法出 NaN，整条直接画不出来
	var fade := maxf(0.001, clampf(h * 0.45, 5.0, 34.0) * (1.0 if alpha_mul >= 0.99 else 0.45) * fade_scale)
	var cols := PackedColorArray()
	for i in pts.size():
		var t := clampf((d1 - float(dist[i])) / fade, 0.0, 1.0)       # 1 = 靠头实心，0 = 尾端透明
		cols.append(Color(col.r, col.g, col.b, alpha_mul * t))
	draw_polygon(pts, cols)


## drawLaneBody()（轨道背景完全透明：只留两侧描边，而且一直落到判定条上，不留缝）
func _draw_lane_body(info: Dictionary) -> void:
	var alpha := float(info["alpha"])
	var lane_len := float(info["len"])
	var half := float(info["half"])
	if alpha <= 0.001 or lane_len < 0.5:
		return
	var col: Color = info["color"]
	var edge := Palette.alpha(col, 0.16 * alpha)
	draw_line(_lane_local_point(info, 0.0, -half, 0.0),
		_lane_local_point(info, lane_len, -half, 0.0), edge, 1.0, true)
	draw_line(_lane_local_point(info, 0.0, half, 0.0),
		_lane_local_point(info, lane_len, half, 0.0), edge, 1.0, true)


## drawLaneJudge()
## 判定线 = 底部一条加粗的横线（粗细跟着轨道宽度走，12 轨也不会变成一堵墙）
func _draw_lane_judge(index: int, info: Dictionary) -> void:
	var alpha := float(info["alpha"])
	if alpha <= 0.001:
		return
	var half := float(info["half"])
	var col: Color = info["color"]
	var line_w := maxf(2.2, half * JUDGE_LINE_RATIO)

	# Bad：这条轨道的判定线闪一下红
	var flash := 0.0
	if index >= 0 and index < _bad_flash.size():
		var fa := chart_time - float(_bad_flash[index])
		if fa >= 0.0 and fa < BAD_FLASH_TIME:
			flash = 1.0 - fa / BAD_FLASH_TIME
	if flash > 0.001:
		var red := Palette.mix(col, BAD_TINT, 0.55 + 0.4 * flash)
		# 先垫一圈淡红光，再画实心条
		draw_colored_polygon(
			_lane_shape(info, 0.0, half * 2.0, line_w * 3.2, line_w * 0.5),
			Palette.alpha(BAD_TINT, 0.22 * flash * alpha))
		draw_colored_polygon(
			_lane_shape(info, 0.0, half * 2.0, line_w, line_w * 0.5),
			Palette.alpha(red, alpha))
		return

	# 平时：底部加粗横条（实心圆角条，两端带圆角）
	draw_colored_polygon(
		_lane_shape(info, 0.0, half * 2.0, line_w, line_w * 0.5),
		Palette.alpha(col, alpha))


## drawPreviewNotes()（长条 / 头 / 剔除规则都照抄）
func _draw_notes(lane_index: int, info: Dictionary, base_pps: float, note_half_w: float) -> void:
	var notes: Array = _notes_by_lane[lane_index]
	if notes.is_empty():
		return

	var lane: Dictionary = info["lane"]
	var lane_len := float(info["len"])
	var col: Color = info["color"]
	var pps := base_pps * float(info["speed"])

	var max_time := INF
	if pps > 0.0001:
		max_time = chart_time + (lane_len + 40.0) / pps
	# 起点要往前多回看 _hold_lookback：不然长条还在画面上、它的头早就进了「4 秒前」的剔除区
	var start_index := _lower_bound(notes, chart_time - _hold_lookback)

	for idx in range(start_index, notes.size()):
		var note: Dictionary = notes[idx]
		var ntime := float(note["time"])
		if ntime > max_time:
			break
		var kind := str(note["type"])
		var nstate := str(note["state"])
		var alpha_mul := 1.0
		var tint: Color = col
		# Bad：保持自己的位置，自己渐变消失（不变红、不回到判定线）
		var fading_bad := note.has("bad_fade_t") and kind != "hold"
		if fading_bad:
			var fa := chart_time - float(note["bad_fade_t"])
			if fa >= BAD_FADE_TIME:
				continue
			# 就停在自己当前的位置上自己淡掉（不回到判定线、不变色）
			_bad_fade_notes.append({
				"info": info,
				"d": (ntime - chart_time) * pps,
				"half_w": note_half_w,
				"color": col,
				"alpha": clampf(1.0 - fa / BAD_FADE_TIME, 0.0, 1.0),
			})
			continue
		elif nstate == "judged" or nstate == "passed":
			# Hold 的 Bad / Miss：不消失，压到 50% 透明继续下落
			if kind == "hold" and bool(note.get("hold_dim", false)):
				alpha_mul = 0.5
			else:
				continue
		elif kind == "hold" and bool(note.get("hold_dim", false)):
			alpha_mul = 0.5                # 头判就是 Bad、还在 hold 中：立刻变半透明继续下落

		var head := (ntime - chart_time) * pps
		var dur := 0.0
		if kind == "hold":
			dur = maxf(0.0, float(note.get("duration", 0.0)))
		var is_hold := dur > 0.001
		var body_mul := float(info["speed"])
		if body_mul <= 0.001:
			body_mul = RhythmChart.hold_speed_mult(lane, chart_time)
		var tail := head + dur * base_pps * body_mul

		if is_hold:
			if tail < -10.0:
				continue                       # 整条都过判定线了
		elif head < -0.5:
			continue                           # 普通音符过线就消失（和预览一致；Bad 的淡出除外）
		if head > lane_len + 40.0:
			break                              # 还没进视野

		var head_d := head if fading_bad else maxf(0.0, head)

		var is_chord := int(note.get("chord", 0)) >= 2
		if is_chord:
			_draw_chord_glow(info, head_d, note_half_w)

		# 长条身体在光效之后画，这样身体能盖住上半边的蓝光，不会把长条「切断」
		if is_hold and tail > 0.0:
			var d0 := maxf(0.0, head)
			var d1 := minf(tail, lane_len)
			if d1 > d0:
				# 尾巴被轨道长度截断时：不渐变、不圆角，直接是一截被轨道切开的实心条
				# （否则渐变会把最后一大段吃掉，看起来像长条自己「消失」了）
				var cut := tail > lane_len + 0.01
				# 头贴到判定线后，头会被裁掉一半、几乎看不见；这时让身体自己带圆角帽
				var head_cap := NOTE_RADIUS if head <= 0.01 else 0.0
				_draw_hold_body(info, d0, d1, note_half_w, 0.0 if cut else NOTE_RADIUS,
					head_cap, tint, alpha_mul, 0.0 if cut else 1.0)

		# 音符头不许越过判定线：贴线时把下半截裁掉，不探到线下面去
		var head_bottom := maxf(0.0, head_d - NOTE_TH)
		var head_top := head_d + NOTE_TH
		var head_h := maxf(0.5, head_top - head_bottom)
		var head_r := minf(NOTE_RADIUS, minf(note_half_w, head_h * 0.5))
		var head_pts := _lane_shape(info, (head_bottom + head_top) * 0.5,
			note_half_w * 2.0, head_h, head_r)
		draw_colored_polygon(head_pts, Palette.alpha(tint, 0.92 * alpha_mul))


## 多押提示：音符外圈一层**柔和的蓝光**（由外到内叠几层低透明度圆角块，没有硬描边）
func _draw_chord_glow(info: Dictionary, d: float, half_w: float) -> void:
	var pulse := 0.9 + 0.1 * sin(chart_time * 7.0)
	for i in 6:
		var k := float(i) / 5.0                     # 0 = 最外 / 1 = 最内
		var grow := 6.0 * (1.0 - k) + 0.4
		var a := (0.030 + 0.055 * k) * pulse
		draw_colored_polygon(
			_lane_shape(info, d, (half_w + grow) * 2.0, (NOTE_TH + grow) * 2.0, NOTE_RADIUS + grow),
			Palette.alpha(CHORD_GLOW, a))


# --------------------------------------------------------------------------- #
# 打击特效（屏幕坐标，和预渲染本体分开）
# --------------------------------------------------------------------------- #

func _draw_fx() -> void:
	if not _has_fx():
		_fx.clear()
		return

	var level := fx_level()
	var keep: Array = []
	for entry in _fx:
		var lane_index := int(entry["lane"])
		if lane_index < 0 or lane_index >= _lane_count:
			continue
		var age := chart_time - float(entry["t"])
		if age < 0.0:
			keep.append(entry)
			continue

		if age > FX_RING_LIFE:
			continue

		# 只保留一圈判定环：更粗、更大；Perfect+ 和 Perfect 用同一个颜色
		var center: Vector2 = entry["pos"]
		var col := _fx_color(str(entry["result"]))
		var k := clampf(age / FX_RING_LIFE, 0.0, 1.0)
		var radius := FX_RING_START + FX_RING_GROW * (1.0 - pow(1.0 - k, 2.0))
		var width := FX_RING_WIDTH * (1.0 - 0.45 * k) * (1.0 if level >= 2 else 0.72)
		draw_arc(center, radius, 0.0, TAU, 64, Palette.alpha(col, (1.0 - k) * 0.9), width, true)
		keep.append(entry)
	_fx = keep


## 判定环颜色：Perfect+ 和 Perfect 用同一个颜色（不再区分）
func _fx_color(result: String) -> Color:
	if result == "perfect_plus":
		result = "perfect"
	return Palette.judge_color(result)

func _draw_letterbox(origin: Vector2, scale: float) -> void:
	var w := size.x
	var h := size.y
	var stage_w := STAGE_W * scale
	var stage_h := STAGE_H * scale
	var bar := Palette.BG_DEEP
	if origin.y > 0.5:
		draw_rect(Rect2(0, 0, w, origin.y), bar)
	var bottom := origin.y + stage_h
	if bottom < h - 0.5:
		draw_rect(Rect2(0, bottom, w, h - bottom), bar)
	if origin.x > 0.5:
		draw_rect(Rect2(0, origin.y, origin.x, stage_h), bar)
	var right := origin.x + stage_w
	if right < w - 0.5:
		draw_rect(Rect2(right, origin.y, w - right, stage_h), bar)


# --------------------------------------------------------------------------- #
# 极简 HUD（屏幕坐标，不参与舞台缩放；布局照制谱器 UI 稿）
#   顶部白条 = 歌曲进度
#   左上 Combo / 右上分数 + 准确率 / 左下曲名 / 右下等级
# --------------------------------------------------------------------------- #

func hud_progress() -> float:
	if judge == null:
		return 0.0
	return clampf(chart_time / maxf(0.1, song_length), 0.0, 1.0)


func hud_score_text() -> String:
	if judge == null:
		return "00000000"
	return "%08d" % int(round(judge.score))


func hud_combo_text() -> String:
	if judge == null:
		return "Combo 0"
	return "Combo %d" % int(judge.combo)


func hud_accuracy_text() -> String:
	if judge == null:
		return "100%"
	var acc := judge.accuracy_live() * 100.0
	return "100%" if acc >= 99.995 else "%.2f%%" % acc


func hud_level_text() -> String:
	var meta: Dictionary = chart.get("meta", {})
	return "Lv.%d" % int(meta.get("level", 1))


func hud_title_text() -> String:
	return str(chart.get("meta", {}).get("title", ""))


func _draw_hud() -> void:
	if judge == null:
		return
	var w := size.x
	var h := size.y
	var pad := h * 0.028
	var big := int(round(h * 0.046))
	var small := int(round(h * 0.028))
	var mid := int(round(h * 0.032))
	var white := Color(1, 1, 1, 0.95)
	var font := UiTheme.sans()

	# 顶部白条：歌曲进度
	var bar_h := maxf(3.0, h * 0.0045)
	draw_rect(Rect2(0, 0, w, bar_h), Color(1, 1, 1, 0.06))
	var progress := hud_progress()
	if progress > 0.0:
		draw_rect(Rect2(0, 0, w * progress, bar_h), white)

	# 左上 Combo
	draw_string(font, Vector2(pad, pad + big * 0.9), hud_combo_text(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, big, white)

	# 右上 分数 + 准确率（分数按固定字宽画，位数变化时右边不动）
	var score_y := pad + big * 0.9
	_draw_fixed_digits(hud_score_text(), w - pad, score_y, big, white, font)
	var acc_txt := hud_accuracy_text()
	var acc_w := font.get_string_size(acc_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, Vector2(w - pad - acc_w, score_y + small * 1.55), acc_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(1, 1, 1, 0.85))

	# 左下 曲名
	var title := hud_title_text()
	if title != "":
		draw_string(font, Vector2(pad, h - pad), title,
			HORIZONTAL_ALIGNMENT_LEFT, w * 0.62, mid, Color(1, 1, 1, 0.92))

	# 右下 等级
	var level_txt := hud_level_text()
	var level_w := font.get_string_size(level_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, mid).x
	draw_string(font, Vector2(w - pad - level_w, h - pad), level_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, mid, Color(1, 1, 1, 0.92))


## 每个字符一个固定步进、右对齐：分数从 8 位变成 7 位时左边不会抖
func _draw_fixed_digits(text: String, right_x: float, baseline: float,
		font_size: int, color: Color, font: Font) -> void:
	var advance := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := right_x - advance * text.length()
	for i in text.length():
		var ch := text.substr(i, 1)
		var ch_w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(x + (advance - ch_w) * 0.5, baseline), ch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += advance


## 命中特效的「锚点」：在**触发那一刻**把这条轨道在屏幕上的位置/朝向/半宽拍下来。
## 特效之后就一直画在这个点上，不跟着轨道动 —— 轨道瞬移（x/y 事件跳变）时不会把特效拽走。
func _lane_fx_anchor(lane_index: int) -> Dictionary:
	var judge_y := roundf(STAGE_H * 0.85)
	var count := maxi(1, _lane_count)
	var lane_w := minf(STAGE_W * 0.05, (STAGE_W * 0.43) / float(count)) * PV_SCALE
	var half_w := maxf(2.0, lane_w / 2.0 - 0.5)
	var info := _lane_geom(lane_index, judge_y, half_w)
	var s := stage_scale()
	return {
		"pos": stage_rect().position + Vector2(float(info["cx"]), float(info["cy"])) * s,
		"side": Vector2(float(info["sx"]), float(info["sy"])),
		"dir": Vector2(float(info["dx"]), float(info["dy"])),
		"half": half_w * s,
	}


static func _lower_bound(arr: Array, t: float) -> int:
	var lo := 0
	var hi := arr.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(arr[mid]["time"]) < t:
			lo = mid + 1
		else:
			hi = mid
	return lo


# --------------------------------------------------------------------------- #
# 信号：产生特效
# --------------------------------------------------------------------------- #

func _on_note_judged(note: Dictionary, result: String, _dt: float) -> void:
	# 判定结果对「音符本身」的影响（和特效开关无关）：Hold 的 Miss 压到 50% 继续挂着
	var kind := str(note.get("type", "tap"))
	if result == "bad":
		var bl := int(note.get("lane", 0))
		if bl >= 0 and bl < _bad_flash.size():
			_bad_flash[bl] = chart_time          # 判定线闪红
	if result == "bad" and kind != "hold":
		note["bad_fade_t"] = chart_time          # 音符自己渐变消失
	if kind == "hold" and (result == "miss" or result == "bad"):
		note["hold_dim"] = true

	# Bad / Miss 都不生成判定环：Bad 靠音符自己变红淡出
	if not _has_fx() or result == "miss" or result == "bad":
		return

	var lane := int(note.get("lane", 0))
	var anchor := _lane_fx_anchor(lane)
	_fx.append({"lane": lane, "t": chart_time, "result": result,
		"pos": anchor["pos"], "side": anchor["side"], "half": anchor["half"]})
	if _fx.size() > MAX_FX:
		_fx.pop_front()


func _on_hold_completed(_note: Dictionary) -> void:
	pass