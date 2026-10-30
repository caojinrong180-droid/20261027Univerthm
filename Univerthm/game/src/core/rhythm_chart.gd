class_name RhythmChart
extends RefCounted
## rchart v3 数据层：读谱 / 容错 / 参数换算 / 缓动。

const MAX_LANES := 16
const NOTE_TYPES := ["tap", "hold"]
const KEYS := ["x", "y", "alpha", "rotation", "speed", "length"]

## 轨道参数默认值 / 合法范围（CHART_FORMAT 7.1）
const DEFAULTS := {
	"x": 0.0, "y": 0.0, "alpha": 0.0, "rotation": 0.0, "speed": 10.0, "length": 10.0,
}
const LIMITS := {
	"x": Vector2(-2000.0, 2000.0),
	"y": Vector2(-2000.0, 2000.0),
	"alpha": Vector2(0.0, 100.0),
	"rotation": Vector2(-3600.0, 3600.0),
	"speed": Vector2(0.0, 100.0),
	"length": Vector2(0.0, 100.0),
}

## 判定区颜色 / 能吃哪些键（CHART_FORMAT 7.2）
const ZONE_COLORS := {
	"none": Color("#ffffff"),
	"left": Color("#b06bff"),
	"right": Color("#ffd166"),
}
const ZONE_KEYS := {
	"none": ["A", "S", "D", "F", "J", "K", "L", ";"],
	"left": ["A", "S", "D", "F"],
	"right": ["J", "K", "L", ";"],
}
const DEFAULT_LANE_COLOR := "#ffffff"


# --------------------------------------------------------------------------- #
# 小工具
# --------------------------------------------------------------------------- #

static func _num(v, def: float) -> float:
	if v is float or v is int:
		return float(v)
	if v is String and v.is_valid_float():
		return v.to_float()
	return def


static func _int_of(v, def: int) -> int:
	if v is float or v is int:
		return int(round(float(v)))
	if v is String and v.is_valid_float():
		return int(round(v.to_float()))
	return def


static func _str_of(v, def: String) -> String:
	return v if v is String else def


static func _round3(v: float) -> float:
	return round(v * 1000.0) / 1000.0


static func _hex_color(v, def: String) -> String:
	if v is String:
		var s: String = v.strip_edges()
		if s.length() == 7 and s[0] == "#":
			var ok := true
			for i in range(1, 7):
				if not "0123456789abcdefABCDEF".contains(s[i]):
					ok = false
					break
			if ok:
				return s.to_lower()
	return def


static func normalize_zone(v) -> String:
	var s := _str_of(v, "none")
	return s if ZONE_COLORS.has(s) else "none"


# --------------------------------------------------------------------------- #
# 读谱
# --------------------------------------------------------------------------- #

## 把从 JSON 解析出来的原始 Dictionary 变成规范谱面。
static func parse(raw) -> Dictionary:
	var warnings: Array[String] = []

	if typeof(raw) != TYPE_DICTIONARY:
		warnings.append("内容不是 JSON 对象，打不开")
		return {"chart": null, "warnings": warnings}
	if raw.has("format") and raw["format"] != "rchart":
		warnings.append("文件格式不是 rchart 谱面，打不开")
		return {"chart": null, "warnings": warnings}

	var chart := {
		"meta": {
			"title": "未命名谱面", "artist": "", "charter": "", "illustrator": "",
			"difficulty": "NORMAL", "level": 1, "cover": "",
		},
		"audio": {"file": "", "offset": 0.0, "volume_db": 0.0},
		"timing": {"bpm": 150.0, "beat_offset": 0.0},
		"stage": {"lane_count": 4, "highway_length": 2.0},
		"lanes": [],
		"notes": [],
	}

	# ---- meta ----
	var meta = raw.get("meta", {})
	if typeof(meta) == TYPE_DICTIONARY:
		chart["meta"]["title"] = _str_of(meta.get("title"), chart["meta"]["title"])
		chart["meta"]["artist"] = _str_of(meta.get("artist"), "")
		chart["meta"]["charter"] = _str_of(meta.get("charter"), "")
		# 曲绘作者（制谱器「曲绘画师」那栏）；老谱面没有就空串
		chart["meta"]["illustrator"] = _str_of(meta.get("illustrator"), "")
		chart["meta"]["difficulty"] = _str_of(meta.get("difficulty"), "NORMAL")
		chart["meta"]["level"] = clampi(_int_of(meta.get("level"), 1), 1, 99)
		chart["meta"]["cover"] = _str_of(meta.get("cover"), "")

	# ---- audio ----
	var audio = raw.get("audio", {})
	if typeof(audio) == TYPE_DICTIONARY:
		chart["audio"]["file"] = _str_of(audio.get("file"), "")
		chart["audio"]["offset"] = _round3(_num(audio.get("offset"), 0.0))
		chart["audio"]["volume_db"] = _num(audio.get("volume_db"), 0.0)

	# ---- timing（本版不支持变速，bpm_events 只取第一个）----
	var timing = raw.get("timing", {})
	var bpm := 150.0
	if typeof(timing) == TYPE_DICTIONARY:
		bpm = _num(timing.get("bpm"), 150.0)
		var bpm_events = timing.get("bpm_events", [])
		if bpm_events is Array and bpm_events.size() > 1:
			warnings.append("谱面有变速（bpm_events），本版只按第一个 BPM 读")
			var first = bpm_events[0]
			if typeof(first) == TYPE_DICTIONARY:
				bpm = _num(first.get("bpm"), bpm)
		if not (bpm > 0.0):
			warnings.append("BPM 不合法，已改成 150")
			bpm = 150.0
	chart["timing"]["bpm"] = clampf(_round3(bpm), 20.0, 1000.0)
	chart["timing"]["beat_offset"] = _round3(_num(timing.get("beat_offset") if typeof(timing) == TYPE_DICTIONARY else 0.0, 0.0))

	# ---- stage / 轨道数 ----
	var stage = raw.get("stage", {})
	var stage_dict: Dictionary = stage if typeof(stage) == TYPE_DICTIONARY else {}
	var raw_lanes = raw.get("lanes", [])
	var lane_count := 0
	if raw_lanes is Array and raw_lanes.size() > 0:
		lane_count = raw_lanes.size()
	else:
		lane_count = _int_of(stage_dict.get("lane_count"), 4)
	lane_count = clampi(lane_count, 1, MAX_LANES)
	chart["stage"]["lane_count"] = lane_count
	chart["stage"]["highway_length"] = clampf(_num(stage_dict.get("highway_length"), 2.0), 0.25, 30.0)

	# ---- lanes ----
	for i in lane_count:
		var src: Dictionary = {}
		if raw_lanes is Array and i < raw_lanes.size() and typeof(raw_lanes[i]) == TYPE_DICTIONARY:
			src = raw_lanes[i]
		var lane := {
			"name": _str_of(src.get("name"), "Lane %d" % (i + 1)),
			"color": _hex_color(src.get("color"), DEFAULT_LANE_COLOR),
			"judge_zone": normalize_zone(src.get("judge_zone")),
			# 父线：静态字段是 0 起（-1 = 不跟）
			"parent": -1,
			"events": {},
		}
		for key in KEYS:
			var lim: Vector2 = LIMITS[key]
			lane[key] = _round3(clampf(_num(src.get(key), DEFAULTS[key]), lim.x, lim.y))
		var parent_i := _int_of(src.get("parent"), -1)
		lane["parent"] = parent_i if (parent_i >= 0 and parent_i < lane_count) else -1

		# 事件：6 条通道各自一个数组
		var evs = src.get("events", {})
		if typeof(evs) == TYPE_DICTIONARY:
			for key in KEYS:
				var arr = evs.get(key, [])
				if not (arr is Array):
					continue
				var out: Array = []
				for e in arr:
					if typeof(e) != TYPE_DICTIONARY:
						continue
					var start := _num(e.get("start"), 0.0)
					var end := _num(e.get("end"), start)
					if end < start:
						end = start
					var ease_name := _str_of(e.get("ease"), "linear")
					if not is_known_ease(ease_name):
						warnings.append("未知缓动 '%s'，按 linear 处理" % ease_name)
						ease_name = "linear"
					out.append({
						"start": start,
						"end": end,
						"ease": ease_name,
						"from": _num(e.get("from"), DEFAULTS[key]),
						"to": _num(e.get("to"), DEFAULTS[key]),
					})
				out.sort_custom(func(a, b): return float(a["start"]) < float(b["start"]))
				lane["events"][key] = out

			# zone 通道（判定区）：数值 0/1/2 → none/left/right，和 core.js 的 zone 事件一致
			var zarr = evs.get("zone", [])
			if zarr is Array:
				var zout: Array = []
				for e in zarr:
					if typeof(e) != TYPE_DICTIONARY:
						continue
					var zstart := _num(e.get("start"), 0.0)
					var zend := _num(e.get("end"), zstart)
					if zend < zstart:
						zend = zstart
					var zease := _str_of(e.get("ease"), "linear")
					if not is_known_ease(zease):
						zease = "linear"
					zout.append({
						"start": zstart,
						"end": zend,
						"ease": zease,
						"from": clampf(_num(e.get("from"), 0.0), 0.0, 2.0),
						"to": clampf(_num(e.get("to"), 0.0), 0.0, 2.0),
					})
				zout.sort_custom(func(a, b): return float(a["start"]) < float(b["start"]))
				lane["events"]["zone"] = zout

			# parent 通道（父线）：0 = 不跟，i + 1 = 挂在第 i 条轨道上
			var parr = evs.get("parent", [])
			if parr is Array:
				var pout: Array = []
				for e in parr:
					if typeof(e) != TYPE_DICTIONARY:
						continue
					var pstart := _num(e.get("start"), 0.0)
					var pend := _num(e.get("end"), pstart)
					if pend < pstart:
						pend = pstart
					var pease := _str_of(e.get("ease"), "linear")
					if not is_known_ease(pease):
						pease = "linear"
					pout.append({
						"start": pstart,
						"end": pend,
						"ease": pease,
						"from": clampf(_num(e.get("from"), 0.0), 0.0, float(lane_count)),
						"to": clampf(_num(e.get("to"), 0.0), 0.0, float(lane_count)),
					})
				pout.sort_custom(func(a, b): return float(a["start"]) < float(b["start"]))
				if not pout.is_empty():
					lane["events"]["parent"] = pout
		chart["lanes"].append(lane)

	# ---- notes ----
	var raw_notes = raw.get("notes", [])
	var notes: Array = []
	var bad := 0
	if raw_notes is Array:
		for rn in raw_notes:
			if typeof(rn) != TYPE_DICTIONARY:
				bad += 1
				continue
			var t := maxf(0.0, _round3(_num(rn.get("time"), 0.0)))
			var lane_i := _int_of(rn.get("lane"), 0)
			if lane_i < 0 or lane_i > lane_count - 1:
				warnings.append("有音符的轨道越界，已夹到合法范围")
				lane_i = clampi(lane_i, 0, lane_count - 1)
			var type := _str_of(rn.get("type"), "tap")
			if not NOTE_TYPES.has(type):
				# flick / mine 已经不支持了：直接丢掉，不当成 tap 混进来
				continue
			var dur := 0.0
			if type == "hold":
				dur = maxf(0.0, _round3(_num(rn.get("duration"), 0.0)))
				if dur <= 0.001:
					type = "tap"
					dur = 0.0
			notes.append({
				"time": t, "lane": lane_i, "type": type, "duration": dur,
				# 运行时状态（判定引擎会改这几个字段）
				"state": "pending", "result": "",
			})
	if bad > 0:
		warnings.append("丢掉了 %d 条格式不对的音符" % bad)

	notes.sort_custom(func(a, b):
		if float(a["time"]) == float(b["time"]):
			return int(a["lane"]) < int(b["lane"])
		return float(a["time"]) < float(b["time"]))
	chart["notes"] = notes

	# 同轨同位置的重复音符只是告警，不删（判定时按先后处理）
	var dup := 0
	for i in range(1, notes.size()):
		var p = notes[i - 1]
		var c = notes[i]
		if int(p["lane"]) == int(c["lane"]) and absf(float(p["time"]) - float(c["time"])) <= 0.0001:
			dup += 1
	if dup > 0:
		warnings.append("有 %d 组同轨同位置的重复音符" % dup)

	return {"chart": chart, "warnings": warnings}


# --------------------------------------------------------------------------- #
# 参数换算（GAME_INTEGRATION 2.1 / CHART_FORMAT 7.3）
# --------------------------------------------------------------------------- #

## 透明度：0 = 完全隐藏，100 = 完全不透明
static func alpha_value(p: Dictionary) -> float:
	return clampf(float(p.get("alpha", 0.0)) / 100.0, 0.0, 1.0)


## 音符流速：平方曲线，10 = 1.00×，20 = 4.00×
static func speed_mult(p: Dictionary) -> float:
	var v := clampf(float(p.get("speed", 10.0)), 0.0, 100.0)
	return v * v / 100.0


## 轨道长度：10 = 标准全长（判定线 → 画面顶），0 = 只剩判定线
static func length_scale(p: Dictionary) -> float:
	return clampf(float(p.get("length", 10.0)) / 10.0, 0.0, 10.0)


## 流速 0 的轨道上「提前多少秒把音符画出来」。
static func zero_speed_lookahead(lane: Dictionary, t: float, visible_px: float, base_pps: float) -> float:
	var sp := hold_speed_mult(lane, t)
	if sp <= 0.001:
		return 0.6
	return clampf(visible_px / (base_pps * sp), 0.2, 4.0)


## 流速 0 的轨道上，某个音符该不该画（lookahead 见 zero_speed_lookahead）。
static func note_visible_at(speed_value: float, note_time: float, t: float, lookahead := 0.02) -> bool:
	if speed_value > 0.001:
		return true
	return note_time <= t + lookahead


## 长条（hold）用的流速倍率。
static func hold_speed_mult(lane: Dictionary, t: float) -> float:
	var here := speed_mult(lane_params_at(lane, t))
	if here > 0.001:
		return here

	var probes: Array = [-1.0e9]
	var evs = lane.get("events", {})
	if evs is Dictionary:
		var arr = evs.get("speed", [])
		if arr is Array:
			for e in arr:
				probes.append(float(e["start"]) - 1e-6)
				probes.append(float(e["end"]) + 1e-6)

	var best := 0.0
	var best_distance := INF
	var best_past := false
	for pt in probes:
		var m := speed_mult(lane_params_at(lane, float(pt)))
		if not (m > 0.001):
			continue
		var past := float(pt) <= t
		var distance := absf(float(pt) - t)
		if distance < best_distance - 1e-9 or (distance <= best_distance + 1e-9 and past and not best_past):
			best = m
			best_distance = distance
			best_past = past
	return best if best > 0.001 else 1.0


static func lane_keys(lane: Dictionary) -> Array:
	return ZONE_KEYS.get(normalize_zone(lane.get("judge_zone")), ZONE_KEYS["none"])


static func display_color(lane: Dictionary) -> Color:
	var zone := normalize_zone(lane.get("judge_zone"))
	if zone != "none":
		return ZONE_COLORS[zone]
	return Color(_hex_color(lane.get("color"), DEFAULT_LANE_COLOR))


## 取「起点 ≤ t 且起点最晚」的那条事件。
static func _event_at(arr: Array, t: float):
	var cur = null
	for e in arr:
		if float(e["start"]) <= t + 1e-9:
			cur = e
		else:
			break
	if cur == null and t < 0.0 and not arr.is_empty():
		return arr[0]
	return cur


## 判定区在某时刻是哪个：有 zone 事件就按事件（数值 0/1/2 插值后取整），没有就用静态值。
static func lane_zone_at(lane: Dictionary, t: float) -> String:
	var static_zone := normalize_zone(lane.get("judge_zone"))
	var evs = lane.get("events", {})
	if not (evs is Dictionary):
		return static_zone
	var arr = evs.get("zone", [])
	if not (arr is Array) or arr.is_empty():
		return static_zone
	var cur = _event_at(arr, t)
	if cur == null:
		return static_zone
	var span: float = float(cur["end"]) - float(cur["start"])
	var k: float = 1.0 if span <= 1e-9 else clampf((t - float(cur["start"])) / span, 0.0, 1.0)
	var v := float(cur["from"]) + (float(cur["to"]) - float(cur["from"])) * ease_at(str(cur["ease"]), k)
	var idx := clampi(int(round(v)), 0, 2)
	return ["none", "left", "right"][idx]


## 某一刻该轨道画什么颜色（判定区会随时间变）—— 和 core.js 的 displayColorAt 一致
static func display_color_at(lane: Dictionary, t: float) -> Color:
	var zone := lane_zone_at(lane, t)
	if zone != "none":
		return ZONE_COLORS[zone]
	return Color(_hex_color(lane.get("color"), DEFAULT_LANE_COLOR))


## 这条轨道在 t 时刻的 6 个参数（含事件动画）
static func lane_params_at(lane: Dictionary, t: float) -> Dictionary:
	var p := {}
	for key in KEYS:
		p[key] = float(lane.get(key, DEFAULTS[key]))

	var evs = lane.get("events", {})
	if typeof(evs) != TYPE_DICTIONARY:
		return p

	for key in KEYS:
		var arr = evs.get(key, [])
		if not (arr is Array) or arr.is_empty():
			continue
		# 取「起点 ≤ t 且起点最晚」的那条（t 早于第一条事件时按第一条关键帧外推）
		var cur = _event_at(arr, t)
		if cur == null:
			continue
		var span: float = float(cur["end"]) - float(cur["start"])
		var k: float = 1.0 if span <= 1e-9 else clampf((t - float(cur["start"])) / span, 0.0, 1.0)
		var eased := ease_at(str(cur["ease"]), k)
		p[key] = float(cur["from"]) + (float(cur["to"]) - float(cur["from"])) * eased
	return p


## 某一刻这条轨道的父线序号（-1 = 没有父线）
static func lane_parent_at(lane: Dictionary, t: float, lane_count: int) -> int:
	var idx := _int_of(lane.get("parent"), -1)
	var evs = lane.get("events", {})
	if evs is Dictionary:
		var arr = evs.get("parent", [])
		if arr is Array and not arr.is_empty():
			var cur = _event_at(arr, t)
			if cur != null:
				var span: float = float(cur["end"]) - float(cur["start"])
				var k: float = 1.0 if span <= 1e-9 else clampf((t - float(cur["start"])) / span, 0.0, 1.0)
				var eased := ease_at(str(cur["ease"]), k)
				var v := float(cur["from"]) + (float(cur["to"]) - float(cur["from"])) * eased
				idx = int(roundf(v)) - 1
	if idx < 0 or idx >= lane_count:
		return -1
	return idx


## 轨道坐标系（已把父线 / 爷爷线叠进来）：
static func lane_frame_at(lanes: Array, index: int, t: float) -> Dictionary:
	var chain: Array = []
	var seen := {}
	var cur := index
	while cur >= 0 and cur < lanes.size() and chain.size() < 8 and not seen.has(cur):
		seen[cur] = true
		chain.append(cur)
		cur = lane_parent_at(lanes[cur], t, lanes.size())

	var ox := 0.0
	var oy := 0.0
	var rot := 0.0
	for i in range(chain.size() - 1, -1, -1):        # 从根往叶子累加
		var p := lane_params_at(lanes[chain[i]], t)
		var rad := deg_to_rad(rot)
		var px := float(p["x"])
		var py := float(p["y"])
		ox += cos(rad) * px + sin(rad) * py
		oy += -sin(rad) * px + cos(rad) * py
		rot += float(p["rotation"])
	return {"x": ox, "y": oy, "rot": rot}

## 音符结束时间（hold 是 time + duration）
static func note_end(note: Dictionary) -> float:
	if str(note.get("type", "tap")) == "hold":
		return float(note.get("time", 0.0)) + float(note.get("duration", 0.0))
	return float(note.get("time", 0.0))


## 谱面最后一个音符结束的时间
static func chart_duration(chart: Dictionary) -> float:
	var last := 0.0
	for n in chart.get("notes", []):
		last = maxf(last, note_end(n))
	return last


## 计入分数的音符数（地雷不算）
static func judgeable_count(chart: Dictionary) -> int:
	var c := 0
	for n in chart.get("notes", []):
		c += 1
	return c


# --------------------------------------------------------------------------- #
# 缓动（CHART_FORMAT 第 9 节，数值和网页版一致）
# --------------------------------------------------------------------------- #

const EASE_NAMES := [
	"linear", "step",
	"inSine", "outSine", "inOutSine",
	"inQuad", "outQuad", "inOutQuad",
	"inCubic", "outCubic", "inOutCubic",
	"inQuart", "outQuart", "inOutQuart",
	"inExpo", "outExpo", "inOutExpo",
	"inBack", "outBack", "inOutBack",
]


static func is_known_ease(name: String) -> bool:
	return EASE_NAMES.has(name) or name.begins_with("bezier(")


static func ease_at(name: String, k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	if name.begins_with("bezier("):
		return _bezier_from_string(name, k)

	var c1 := 1.70158
	var c3 := c1 + 1.0
	match name:
		"step":
			return 0.0 if k < 1.0 else 1.0
		"inSine":
			return 1.0 - cos(k * PI / 2.0)
		"outSine":
			return sin(k * PI / 2.0)
		"inOutSine":
			return -(cos(PI * k) - 1.0) / 2.0
		"inQuad":
			return k * k
		"outQuad":
			return 1.0 - (1.0 - k) * (1.0 - k)
		"inOutQuad":
			return 2.0 * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2.0) / 2.0
		"inCubic":
			return k * k * k
		"outCubic":
			return 1.0 - pow(1.0 - k, 3.0)
		"inOutCubic":
			return 4.0 * k * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 3.0) / 2.0
		"inQuart":
			return k * k * k * k
		"outQuart":
			return 1.0 - pow(1.0 - k, 4.0)
		"inOutQuart":
			return 8.0 * pow(k, 4.0) if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 4.0) / 2.0
		"inExpo":
			return 0.0 if k == 0.0 else pow(2.0, 10.0 * k - 10.0)
		"outExpo":
			return 1.0 if k == 1.0 else 1.0 - pow(2.0, -10.0 * k)
		"inOutExpo":
			if k == 0.0:
				return 0.0
			if k == 1.0:
				return 1.0
			return pow(2.0, 20.0 * k - 10.0) / 2.0 if k < 0.5 \
				else (2.0 - pow(2.0, -20.0 * k + 20.0)) / 2.0
		"inBack":
			return c3 * k * k * k - c1 * k * k
		"outBack":
			return 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
		"inOutBack":
			return pow(2.0 * k, 2.0) * ((c1 + 1.0) * 2.0 * k - c1) / 2.0 if k < 0.5 \
				else (pow(2.0 * k - 2.0, 2.0) * ((c1 + 1.0) * (k * 2.0 - 2.0) + c1) + 2.0) / 2.0
	return k


## "bezier(0.25, 0.1, 0.25, 1)" —— 和 CSS cubic-bezier 同一套算法
static func _bezier_from_string(s: String, x: float) -> float:
	var inner := s.trim_prefix("bezier(").trim_suffix(")")
	var parts := inner.split(",")
	if parts.size() != 4:
		return x
	var v := []
	for p in parts:
		var ps := p.strip_edges()
		if not ps.is_valid_float():
			return x
		v.append(ps.to_float())
	return _cubic_bezier(v[0], v[1], v[2], v[3], x)


static func _cubic_bezier(x1: float, y1: float, x2: float, y2: float, x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	var t := x
	for i in 8:
		var ct := _bez(t, x1, x2)
		var d := _bez_slope(t, x1, x2)
		if absf(d) < 1e-6:
			break
		t = clampf(t - (ct - x) / d, 0.0, 1.0)
	return _bez(t, y1, y2)


static func _bez(t: float, a1: float, a2: float) -> float:
	var A := 1.0 - 3.0 * a2 + 3.0 * a1
	var B := 3.0 * a2 - 6.0 * a1
	var C := 3.0 * a1
	return ((A * t + B) * t + C) * t


static func _bez_slope(t: float, a1: float, a2: float) -> float:
	var A := 1.0 - 3.0 * a2 + 3.0 * a1
	var B := 3.0 * a2 - 6.0 * a1
	var C := 3.0 * a1
	return 3.0 * A * t * t + 2.0 * B * t + C
