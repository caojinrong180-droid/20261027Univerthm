@tool
class_name RhythmChartLane
extends RefCounted
## 一条轨道。
##
## 三层属性：
##   1. 静态视觉：position / rotation_deg / alpha(0~255) / length_scale —— 轨道"初始长什么样"
##   2. 玩法属性：judge_zone —— 这条轨道的音符允许哪些键打
##   3. 事件动画：events —— 一条条独立事件（起止时间 + 起止值 + 缓动），按谱面时间求值
##
## 事件形如（PhiEdit / Phigros 的事件模型）：
##   { "start": 0.0, "end": 4.0, "from": -150.0, "to": 50.0, "ease": "inOutQuad" }
##   * 在 [start, end] 区间内，值从 from 缓动到 to
##   * 过了 end 保持 to；还没到任何事件 → 用静态值
##   * 事件可以重叠：起点最晚的那条生效
##   * ease 支持内置名字 + `bezier(x1,y1,x2,y2)` 自定义曲线（同 CSS cubic-bezier）
##
## 判定区：
##   NONE  白色：ASDFJKL; 任意键
##   LEFT  紫色：只有 ASDF
##   RIGHT 黄色：只有 JKL;

enum JudgeZone {
	NONE = 0,
	LEFT = 1,
	RIGHT = 2,
}

const DEFAULT_COLOR := "#ffffff"
const ZONE_KEYS: Array = ["none", "left", "right"]
const ZONE_LABELS: Array = ["None（白 · 任意键）", "Left（紫 · ASDF）", "Right（黄 · JKL;）"]
const ZONE_SHORT: Array = ["白", "紫", "黄"]
const ZONE_COLORS: Array = ["#ffffff", "#b06bff", "#ffd166"]

## 可做动画的属性（也是 events 的 key）。
const EVENT_TYPES: Array = ["x", "y", "rotation", "alpha", "length"]
const EVENT_LABELS: Array = ["移动 X", "移动 Y", "旋转", "透明度", "长度"]
## 事件区底部标签页用的短名字（位置窄）。
const EVENT_TAB_LABELS: Array = ["X轴", "Y轴", "角度", "透明度", "长度"]

## 内置缓动；也可以直接写 "bezier(0.25, 0.1, 0.25, 1)"。
const EASINGS: Array = [
	"linear", "step",
	"inSine", "outSine", "inOutSine",
	"inQuad", "outQuad", "inOutQuad",
	"inCubic", "outCubic", "inOutCubic",
	"inExpo", "outExpo",
	"inBack", "outBack",
]

var name: String = "Lane"
var color: Color = Color(DEFAULT_COLOR)
var position: Vector2 = Vector2.ZERO
var rotation_deg: float = 0.0
## 0 ~ 255（0 = 全透明，255 = 不透明）。
var alpha: int = 255
var length_scale: float = 1.0
var visible: bool = true
var volume: float = 1.0
var judge_zone: JudgeZone = JudgeZone.NONE
## 事件动画：{ "x": [事件...], "alpha": [...] }，只存有内容的事件类型。
## 事件 = { "start": 0.0, "end": 4.0, "from": -150.0, "to": 50.0, "ease": "inOutQuad" }
var events: Dictionary = {}


static func default_for(index: int) -> RhythmChartLane:
	var lane := RhythmChartLane.new()
	lane.name = "Lane %d" % (index + 1)
	lane.color = Color(DEFAULT_COLOR)
	lane.judge_zone = JudgeZone.NONE
	return lane


# ------------------------------------------------------------ 判定区工具

static func zone_to_key(z: JudgeZone) -> String:
	return String(ZONE_KEYS[clampi(int(z), 0, ZONE_KEYS.size() - 1)])


static func zone_from_key(s: String) -> JudgeZone:
	var i := ZONE_KEYS.find(s.strip_edges().to_lower())
	return JudgeZone.NONE if i < 0 else (i as JudgeZone)


static func zone_from_index(index: int) -> JudgeZone:
	return clampi(index, 0, ZONE_KEYS.size() - 1) as JudgeZone


static func zone_label(z: JudgeZone) -> String:
	return String(ZONE_LABELS[clampi(int(z), 0, ZONE_LABELS.size() - 1)])


static func zone_short(z: JudgeZone) -> String:
	return String(ZONE_SHORT[clampi(int(z), 0, ZONE_SHORT.size() - 1)])


static func zone_color(z: JudgeZone) -> Color:
	return Color(String(ZONE_COLORS[clampi(int(z), 0, ZONE_COLORS.size() - 1)]))


func display_color() -> Color:
	if judge_zone == JudgeZone.NONE:
		return color
	return zone_color(judge_zone)


func allowed_keys() -> PackedStringArray:
	match judge_zone:
		JudgeZone.LEFT:
			return PackedStringArray(["A", "S", "D", "F"])
		JudgeZone.RIGHT:
			return PackedStringArray(["J", "K", "L", ";"])
		_:
			return PackedStringArray(["A", "S", "D", "F", "J", "K", "L", ";"])


# ------------------------------------------------------------ 缓动函数

## t ∈ [0,1] → 缓动后的 [0,1]（允许轻微越界，比如 outBack 会冲过头）。
static func apply_ease(ease_name: String, t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	var n := ease_name.strip_edges()
	if n.begins_with("bezier"):
		return _bezier_ease(n, x)
	match n.to_lower():
		"step", "hold", "constant":
			return 0.0 if x < 1.0 else 1.0
		"insine":
			return 1.0 - cos(x * PI * 0.5)
		"outsine":
			return sin(x * PI * 0.5)
		"inoutsine":
			return -(cos(PI * x) - 1.0) * 0.5
		"inquad":
			return x * x
		"outquad":
			return 1.0 - (1.0 - x) * (1.0 - x)
		"inoutquad":
			return 2.0 * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 2.0) * 0.5
		"incubic":
			return x * x * x
		"outcubic":
			return 1.0 - pow(1.0 - x, 3.0)
		"inoutcubic":
			return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5
		"inexpo":
			return 0.0 if x <= 0.0 else pow(2.0, 10.0 * (x - 1.0))
		"outexpo":
			return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)
		"inback":
			var c1 := 1.70158
			return pow(c1 + 1.0, 2.0) * x * x * x - c1 * x * x
		"outback":
			var c1b := 1.70158
			return 1.0 + (c1b + 1.0) * pow(x - 1.0, 3.0) + c1b * pow(x - 1.0, 2.0)
		_:
			return x


## cubic-bezier(x1,y1,x2,y2)：先解 x(s)=t，再取 y(s)。
static func _bezier_ease(spec: String, t: float) -> float:
	var nums := _parse_floats(spec)
	if nums.size() < 4:
		return t
	var x1: float = nums[0]
	var y1: float = nums[1]
	var x2: float = nums[2]
	var y2: float = nums[3]
	var lo := 0.0
	var hi := 1.0
	var s := t
	for i in 26:
		s = (lo + hi) * 0.5
		if _bezier_axis(s, x1, x2) < t:
			lo = s
		else:
			hi = s
	return _bezier_axis((lo + hi) * 0.5, y1, y2)


static func _bezier_axis(s: float, a1: float, a2: float) -> float:
	var u := 1.0 - s
	return 3.0 * u * u * s * a1 + 3.0 * u * s * s * a2 + s * s * s


static func _parse_floats(text: String) -> Array:
	var out: Array = []
	var buf := ""
	for i in text.length():
		var c := text[i]
		if (c >= "0" and c <= "9") or c == "-" or c == "+" or c == ".":
			buf += c
		else:
			if not buf.is_empty() and buf != "-" and buf != "." and buf != "+":
				out.append(buf.to_float())
			buf = ""
	if not buf.is_empty() and buf != "-" and buf != "." and buf != "+":
		out.append(buf.to_float())
	return out


# ------------------------------------------------------------ 关键帧求值

# ------------------------------------------------------------ 事件求值

func get_events(type: String) -> Array:
	var list: Variant = events.get(type, [])
	return list if list is Array else []


func set_events(type: String, list: Array) -> void:
	if list.is_empty():
		events.erase(type)
	else:
		list.sort_custom(func(a, b): return float(a.get("start", 0.0)) < float(b.get("start", 0.0)))
		events[type] = list


func has_events() -> bool:
	for key in events.keys():
		if not get_events(String(key)).is_empty():
			return true
	return false


## 当前属性有没有事件（有的话静态值不生效）。
func has_events_for(type: String) -> bool:
	return not get_events(type).is_empty()


func base_value(prop: String) -> float:
	match prop:
		"x":
			return position.x
		"y":
			return position.y
		"rotation":
			return rotation_deg
		"alpha":
			return float(alpha)
		"length":
			return length_scale
	return 0.0


## 事件求值：取"起点 <= time 且起点最大"的那条事件。
## 落在事件区间内 → 从 from 缓动到 to；过了 end → 保持 to；还没到第一条 → 静态值。
static func evaluate_events(list: Array, time: float, fallback: float) -> float:
	if list.is_empty():
		return fallback
	var picked: Dictionary = {}
	var best_start := -INF
	for e in list:
		if not (e is Dictionary):
			continue
		var s := float(e.get("start", 0.0))
		if s <= time + 1e-9 and s > best_start:
			best_start = s
			picked = e
	if picked.is_empty():
		return fallback
	var s0 := float(picked.get("start", 0.0))
	var e0 := float(picked.get("end", s0))
	var v0 := float(picked.get("from", fallback))
	var v1 := float(picked.get("to", fallback))
	if e0 <= s0 + 1e-9 or time >= e0:
		return v1
	var local := (time - s0) / (e0 - s0)
	return lerpf(v0, v1, apply_ease(String(picked.get("ease", "linear")), local))


func resolved_value(prop: String, time: float) -> float:
	return evaluate_events(get_events(prop), time, base_value(prop))


func resolved_x(time: float) -> float:
	return resolved_value("x", time)


func resolved_y(time: float) -> float:
	return resolved_value("y", time)


func resolved_position(time: float) -> Vector2:
	return Vector2(resolved_x(time), resolved_y(time))


func resolved_rotation(time: float) -> float:
	return resolved_value("rotation", time)


func resolved_alpha_255(time: float) -> float:
	return clampf(resolved_value("alpha", time), 0.0, 255.0)


func resolved_alpha(time: float) -> float:
	return resolved_alpha_255(time) / 255.0


func resolved_length_scale(time: float) -> float:
	return maxf(resolved_value("length", time), 0.0)


## 静态透明度换算成 0~1。
func alpha_f() -> float:
	return clampf(float(alpha) / 255.0, 0.0, 1.0)


## 造一条事件并保持按起点排序。
static func append_event(list: Array, start: float, end: float, from_v: float, to_v: float,
		ease: String = "linear") -> Array:
	var out: Array = list.duplicate(true)
	var s := maxf(start, 0.0)
	var e := maxf(end, s)
	out.append({"start": s, "end": e, "from": from_v, "to": to_v, "ease": ease})
	out.sort_custom(func(a, b): return float(a.get("start", 0.0)) < float(b.get("start", 0.0)))
	return out


## v2 的 motion 关键帧 → 事件（相邻两帧合成一条事件），迁移用。
static func events_from_motion(motion: Dictionary) -> Dictionary:
	var out := {}
	for type in EVENT_TYPES:
		var src: Variant = motion.get(type, null)
		if not (src is Array):
			continue
		var kfs: Array = []
		for kf in src:
			if kf is Dictionary:
				kfs.append(kf)
		kfs.sort_custom(func(a, b): return float(a.get("time", 0.0)) < float(b.get("time", 0.0)))
		if kfs.size() < 2:
			continue
		var list: Array = []
		for i in range(kfs.size() - 1):
			var a: Dictionary = kfs[i]
			var b: Dictionary = kfs[i + 1]
			list.append({
				"start": float(a.get("time", 0.0)),
				"end": float(b.get("time", 0.0)),
				"from": float(a.get("value", 0.0)),
				"to": float(b.get("value", 0.0)),
				"ease": String(a.get("ease", "linear")),
			})
		if not list.is_empty():
			out[type] = list
	return out


# ------------------------------------------------------------ 通用

func clamp_values() -> RhythmChartLane:
	rotation_deg = wrapf(rotation_deg, -360.0, 360.0)
	alpha = clampi(alpha, 0, 255)
	length_scale = clampf(length_scale, 0.1, 8.0)
	volume = clampf(volume, 0.0, 1.0)
	position.x = clampf(position.x, -100000.0, 100000.0)
	position.y = clampf(position.y, -100000.0, 100000.0)
	return self


func duplicate_lane() -> RhythmChartLane:
	var l := RhythmChartLane.new()
	l.name = name
	l.color = color
	l.position = position
	l.rotation_deg = rotation_deg
	l.alpha = alpha
	l.length_scale = length_scale
	l.visible = visible
	l.volume = volume
	l.judge_zone = judge_zone
	l.events = events.duplicate(true)
	return l


func events_to_dict() -> Dictionary:
	var out := {}
	for type in EVENT_TYPES:
		var list := get_events(String(type))
		if list.is_empty():
			continue
		var arr: Array = []
		for e in list:
			if e is Dictionary:
				arr.append({
					"start": snappedf(float(e.get("start", 0.0)), 0.000001),
					"end": snappedf(float(e.get("end", 0.0)), 0.000001),
					"from": snappedf(float(e.get("from", 0.0)), 0.001),
					"to": snappedf(float(e.get("to", 0.0)), 0.001),
					"ease": String(e.get("ease", "linear")),
				})
		out[type] = arr
	return out


func events_from_dict(raw: Variant) -> void:
	events = {}
	if not (raw is Dictionary):
		return
	for type in EVENT_TYPES:
		var src: Variant = (raw as Dictionary).get(type, null)
		if not (src is Array):
			continue
		var list: Array = []
		for e in src:
			if e is Dictionary:
				var s := maxf(float(e.get("start", 0.0)), 0.0)
				var en := maxf(float(e.get("end", s)), s)
				list.append({
					"start": s,
					"end": en,
					"from": float(e.get("from", 0.0)),
					"to": float(e.get("to", 0.0)),
					"ease": String(e.get("ease", "linear")),
				})
		if not list.is_empty():
			set_events(String(type), list)


func to_dict() -> Dictionary:
	var d := {
		"name": name,
		"color": "#" + color.to_html(false),
		"judge_zone": zone_to_key(judge_zone),
		"position": {
			"x": snappedf(position.x, 0.01),
			"y": snappedf(position.y, 0.01),
		},
		"rotation_deg": snappedf(rotation_deg, 0.01),
		"alpha": alpha,
		"length_scale": snappedf(length_scale, 0.001),
		"visible": visible,
		"volume": snappedf(volume, 0.001),
	}
	var ev := events_to_dict()
	if not ev.is_empty():
		d["events"] = ev
	return d
	


static func from_dict(d: Dictionary, index: int = 0, legacy_alpha: bool = false) -> RhythmChartLane:
	var lane := default_for(index)
	lane.name = String(d.get("name", lane.name))
	var col := String(d.get("color", ""))
	if not col.is_empty():
		lane.color = Color.from_string(col, lane.color)
	lane.judge_zone = zone_from_key(String(d.get("judge_zone", "none")))

	# v1 的 alpha 是 0.0~1.0 浮点，v2 起是 0~255 整数
	var raw_alpha: Variant = d.get("alpha", 255)
	var alpha_num := float(raw_alpha)
	if legacy_alpha:
		lane.alpha = int(round(alpha_num * 255.0))
	else:
		lane.alpha = int(round(alpha_num))

	var pos: Dictionary = d.get("position", {})
	if pos is Dictionary:
		lane.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	lane.rotation_deg = float(d.get("rotation_deg", 0.0))
	lane.length_scale = float(d.get("length_scale", 1.0))
	lane.visible = bool(d.get("visible", true))
	lane.volume = float(d.get("volume", 1.0))

	# v3：事件动画。v2 的 motion 关键帧会自动合成事件（兼容旧文件）
	var raw_events: Variant = d.get("events", null)
	if raw_events is Dictionary:
		lane.events_from_dict(raw_events)
	else:
		var raw_motion: Variant = d.get("motion", null)
		if raw_motion is Dictionary:
			lane.events = events_from_motion(raw_motion)
	return lane.clamp_values()
