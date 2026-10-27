@tool
class_name RhythmChartNote
extends RefCounted
## 一个音符。时间单位统一为「秒」，长条用 duration 表示按住时长。
##
## 这是运行时和制谱器共用的数据类，不含任何编辑器依赖。

enum Type {
	TAP = 0,
	HOLD = 1,
	FLICK = 2,
	MINE = 3,
}

const TYPE_KEYS: Array = ["tap", "hold", "flick", "mine"]
const TYPE_LABELS: Array = ["Tap", "Hold", "Flick", "Mine"]

var id: int = 0
var time: float = 0.0
var lane: int = 0
var type: Type = Type.TAP
var duration: float = 0.0
var velocity: float = 1.0


func is_long() -> bool:
	return type == Type.HOLD and duration > 0.0


func end_time() -> float:
	return time + maxf(duration, 0.0)


func length_sec() -> float:
	return maxf(duration, 0.0) if type == Type.HOLD else 0.0


## 把字段收进合法范围，返回自身（链式用）。
func normalize() -> RhythmChartNote:
	id = maxi(id, 0)
	time = maxf(time, 0.0)
	lane = maxi(lane, 0)
	duration = maxf(duration, 0.0) if type == Type.HOLD else 0.0
	velocity = clampf(velocity, 0.0, 1.0)
	return self


func duplicate_note() -> RhythmChartNote:
	var n := RhythmChartNote.new()
	n.id = id
	n.time = time
	n.lane = lane
	n.type = type
	n.duration = duration
	n.velocity = velocity
	return n


func to_dict() -> Dictionary:
	# 只写非默认字段，JSON 更干净；但 id/time/lane/type 永远写，方便人读。
	var d := {
		"id": id,
		"time": _r(time),
		"lane": lane,
		"type": type_to_key(type),
	}
	if type == Type.HOLD:
		d["duration"] = _r(maxf(duration, 0.0))
	if not is_equal_approx(velocity, 1.0):
		d["velocity"] = _r(velocity, 3)
	return d


static func _r(v: float, digits: int = 6) -> float:
	return snappedf(v, pow(10.0, -digits))


static func type_to_key(t: Type) -> String:
	return String(TYPE_KEYS[clampi(int(t), 0, TYPE_KEYS.size() - 1)])


## 双击切换类型用：tap -> hold -> flick -> mine -> tap。
static func cycle_type(t: Type) -> Type:
	match t:
		Type.TAP:
			return Type.HOLD
		Type.HOLD:
			return Type.FLICK
		Type.FLICK:
			return Type.MINE
		_:
			return Type.TAP


static func type_to_label(t: Type) -> String:
	return String(TYPE_LABELS[clampi(int(t), 0, TYPE_LABELS.size() - 1)])


## 未知 / 拼错的类型退回 TAP，不让一份手写 JSON 整个崩掉。
static func type_from_key(s: String) -> Type:
	var i := TYPE_KEYS.find(s.strip_edges().to_lower())
	return Type.TAP if i < 0 else (i as Type)


static func from_dict(d: Dictionary) -> RhythmChartNote:
	var n := RhythmChartNote.new()
	n.id = int(d.get("id", 0))
	n.time = float(d.get("time", 0.0))
	n.lane = int(d.get("lane", 0))
	n.type = type_from_key(String(d.get("type", "tap")))
	n.duration = float(d.get("duration", 0.0))
	n.velocity = float(d.get("velocity", 1.0))
	return n.normalize()
