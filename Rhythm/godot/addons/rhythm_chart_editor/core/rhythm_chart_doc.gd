@tool
class_name RhythmChartDocument
extends RefCounted
## 一整份谱面：元信息 + 音频引用 + 时间轴 + 舞台 + 轨道 + 音符。
##
## 这就是 JSON 的内存形态。运行时（游戏里）和编辑器里用的是同一个类，
## 所以制谱器存下来的东西在游戏里读出来一定一致。

signal changed

const FORMAT_ID := "rchart"
## v2：轨道 alpha 从 0.0~1.0 浮点改成 0~255 整数。
## v3：动画从 motion 关键帧改成 events 事件（读到的 v2 motion 会自动合成事件）。
const FORMAT_VERSION := 3

const META_DEFAULTS := {
	"title": "",
	"artist": "",
	"charter": "",
	"difficulty": "NORMAL",
	"level": 1,
	"description": "",
}

const AUDIO_DEFAULTS := {
	"file": "",
	"offset": 0.0,
	"volume_db": 0.0,
}

const STAGE_DEFAULTS := {
	"lane_count": 4,
	"lane_width": 96.0,
	"highway_length": 6.0,
	"scroll_speed": 1.0,
	"judge_line_y": 0.0,
}

const MIN_LANES := 1
const MAX_LANES := 16
## 新建轨道时默认的水平间距（相对 lane_width 的倍数）。
const LANE_SPACING_FACTOR := 1.15

## 文件路径（res:// 或绝对路径），空 = 还没保存过。
var path: String = ""
var meta: Dictionary = META_DEFAULTS.duplicate(true)
var audio: Dictionary = AUDIO_DEFAULTS.duplicate(true)
var timing: RhythmChartTiming = RhythmChartTiming.new()
var stage: Dictionary = STAGE_DEFAULTS.duplicate(true)
var lanes: Array[RhythmChartLane] = []
var notes: Array[RhythmChartNote] = []

## 制谱器专用：当前吸附精度（每拍切几份），不写进 JSON。
var snap_divisor: int = 4

var _next_id: int = 1


static func create_default() -> RhythmChartDocument:
	var doc := RhythmChartDocument.new()
	doc.from_dict({})
	return doc


# ---------------------------------------------------------------- 轨道

func lane_count() -> int:
	return lanes.size()


func _lane_spacing() -> float:
	return float(stage.get("lane_width", 96.0)) * LANE_SPACING_FACTOR


## 只在"没有 lanes 字段、自动补齐默认轨道"时使用：让它们均分在舞台中间。
func _spread_lanes_evenly() -> void:
	var n := lanes.size()
	if n <= 0:
		return
	var spacing := _lane_spacing()
	for i in n:
		lanes[i].position = Vector2((float(i) - float(n - 1) * 0.5) * spacing, 0.0)


func set_lane_count(count: int) -> void:
	var target := clampi(count, MIN_LANES, MAX_LANES)
	while lanes.size() < target:
		var lane := RhythmChartLane.default_for(lanes.size())
		if not lanes.is_empty():
			# 新轨道排在最右侧那条的外面，不然预览里会全叠在一起。
			var rightmost := -1e9
			for existing in lanes:
				rightmost = maxf(rightmost, existing.position.x)
			lane.position = Vector2(rightmost + _lane_spacing(), 0.0)
		lanes.append(lane)
	if lanes.size() > target:
		# 删掉的轨道上的音符要么被夹到最后一轨，要么直接删——这里选删掉并告警。
		for i in range(lanes.size() - 1, target - 1, -1):
			var keep: Array[RhythmChartNote] = []
			for n in notes:
				if n.lane != i:
					keep.append(n)
			notes = keep
		lanes.resize(target)
	stage["lane_count"] = target
	for n in notes:
		if n.lane >= target:
			n.lane = target - 1
	resort_notes()
	emit_changed()


func move_lane(from_index: int, to_index: int) -> void:
	if from_index == to_index:
		return
	if from_index < 0 or from_index >= lanes.size():
		return
	var target := clampi(to_index, 0, lanes.size() - 1)
	var lane := lanes[from_index]
	lanes.remove_at(from_index)
	lanes.insert(target, lane)
	# 音符的 lane 索引跟着轨道一起走。
	for n in notes:
		if n.lane == from_index:
			n.lane = target
		elif from_index < target and n.lane > from_index and n.lane <= target:
			n.lane -= 1
		elif from_index > target and n.lane >= target and n.lane < from_index:
			n.lane += 1
	emit_changed()


# ---------------------------------------------------------------- 音符

func next_note_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func add_note(time: float, lane: int, type: int = RhythmChartNote.Type.TAP) -> RhythmChartNote:
	var n := RhythmChartNote.new()
	n.id = next_note_id()
	n.time = maxf(time, 0.0)
	n.lane = clampi(lane, 0, maxi(lanes.size() - 1, 0))
	n.type = type
	notes.append(n)
	resort_notes()
	emit_changed()
	return n


func remove_note(note: RhythmChartNote) -> bool:
	var idx := notes.find(note)
	if idx < 0:
		return false
	notes.remove_at(idx)
	emit_changed()
	return true


## 找同轨、时间上最近的那个音符（用于点选、删重叠）。
func find_note_near(time_sec: float, lane: int, tolerance_sec: float) -> RhythmChartNote:
	var best: RhythmChartNote = null
	var best_d := tolerance_sec
	for n in notes:
		if n.lane != lane:
			continue
		var d := absf(n.time - time_sec)
		if d <= best_d:
			# 长条被点中尾部也算命中，这里只按头部距离算，够用且可预测。
			best_d = d
			best = n
	return best


func notes_in_range(from_sec: float, to_sec: float) -> Array[RhythmChartNote]:
	var out: Array[RhythmChartNote] = []
	for n in notes:
		if n.end_time() >= from_sec and n.time <= to_sec:
			out.append(n)
	return out


## 二分：返回第一个 time >= t 的下标（notes 按时间升序）。
## 渲染时用它跳过视野之外的音符，避免每帧全量扫描。
func index_at_time(t: float) -> int:
	var lo := 0
	var hi := notes.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if notes[mid].time < t:
			lo = mid + 1
		else:
			hi = mid
	return lo


func resort_notes() -> void:
	notes.sort_custom(func(a: RhythmChartNote, b: RhythmChartNote) -> bool:
		if is_equal_approx(a.time, b.time):
			return a.lane < b.lane
		return a.time < b.time
	)
	# 保证 _next_id 永远大于已有 id，避免手写 JSON 里 id 撞车。
	for n in notes:
		if n.id >= _next_id:
			_next_id = n.id + 1


func total_duration() -> float:
	var t := 0.0
	for n in notes:
		t = maxf(t, n.end_time())
	return t


func note_count_by_type() -> Dictionary:
	var out := {"tap": 0, "hold": 0, "flick": 0, "mine": 0}
	for n in notes:
		var k := RhythmChartNote.type_to_key(n.type)
		out[k] = int(out.get(k, 0)) + 1
	return out


# ---------------------------------------------------------------- 序列化

func to_dict() -> Dictionary:
	var lane_dicts: Array = []
	for l in lanes:
		lane_dicts.append(l.to_dict())
	var note_dicts: Array = []
	for n in notes:
		note_dicts.append(n.to_dict())
	return {
		"format": FORMAT_ID,
		"version": FORMAT_VERSION,
		"meta": meta.duplicate(true),
		"audio": audio.duplicate(true),
		"timing": timing.to_dict(),
		"stage": stage.duplicate(true),
		"lanes": lane_dicts,
		"notes": note_dicts,
	}


## 容错解析：缺字段就用默认值，多出来的字段忽略。
## report 里塞人类可读的警告（轨道越界、类型拼错……），不影响载入。
func from_dict(d: Dictionary, report: Variant = null) -> void:
	var out: Array = report if report is Array else []
	meta = META_DEFAULTS.duplicate(true)
	var raw_meta: Variant = d.get("meta", null)
	if raw_meta is Dictionary:
		for k in META_DEFAULTS.keys():
			if (raw_meta as Dictionary).has(k):
				meta[k] = (raw_meta as Dictionary)[k]

	audio = AUDIO_DEFAULTS.duplicate(true)
	var raw_audio: Variant = d.get("audio", null)
	if raw_audio is Dictionary:
		for k in AUDIO_DEFAULTS.keys():
			if (raw_audio as Dictionary).has(k):
				audio[k] = (raw_audio as Dictionary)[k]

	stage = STAGE_DEFAULTS.duplicate(true)
	var raw_stage: Variant = d.get("stage", null)
	if raw_stage is Dictionary:
		for k in STAGE_DEFAULTS.keys():
			if (raw_stage as Dictionary).has(k):
				stage[k] = (raw_stage as Dictionary)[k]

	timing = RhythmChartTiming.new()
	var raw_timing: Variant = d.get("timing", null)
	if raw_timing is Dictionary:
		timing.from_dict(raw_timing)

	lanes.clear()
	# v1 的 alpha 是 0~1 浮点，读 v1 谱面时按旧语义换算成 0~255
	var legacy_alpha := int(d.get("version", 1)) < 2
	var raw_lanes: Variant = d.get("lanes", [])
	if raw_lanes is Array:
		for lane_data in raw_lanes:
			if lane_data is Dictionary:
				lanes.append(RhythmChartLane.from_dict(lane_data, lanes.size(), legacy_alpha))
	if lanes.is_empty():
		var count := clampi(int(stage.get("lane_count", 4)), MIN_LANES, MAX_LANES)
		for i in count:
			lanes.append(RhythmChartLane.default_for(i))
		_spread_lanes_evenly()
	stage["lane_count"] = lanes.size()

	notes.clear()
	_next_id = 1
	var raw_notes: Variant = d.get("notes", [])
	if raw_notes is Array:
		for note_data in raw_notes:
			if note_data is Dictionary:
				notes.append(RhythmChartNote.from_dict(note_data))

	# 手写 JSON 常见问题：lane 越界 —— 夹回去而不是丢弃。
	for n in notes:
		if n.lane < 0 or n.lane >= lanes.size():
			out.append("音符 id=%d 的 lane=%d 越界，已夹到合法轨道" % [n.id, n.lane])
			n.lane = clampi(n.lane, 0, lanes.size() - 1)

	resort_notes()
	snap_divisor = 4
	emit_changed()


## 深拷贝快照，用于撤销栈。
func snapshot() -> Dictionary:
	return to_dict()


func restore(snap: Dictionary) -> void:
	from_dict(snap)


# ---------------------------------------------------------------- 校验

## 返回人类可读的问题列表。空数组 = 没问题。
func validate(report: Variant = null) -> Array:
	var out: Array = report if report is Array else []
	if lanes.is_empty():
		out.append("谱面没有任何轨道")
	if timing.bpm <= 0.0:
		out.append("BPM 必须大于 0")
	for e in timing.bpm_events:
		if e is Dictionary and float(e.get("bpm", 0.0)) <= 0.0:
			out.append("bpm_events 里有 BPM <= 0 的事件")
	var seen := {}
	for n in notes:
		if n.time < 0.0:
			out.append("音符 id=%d 时间为负" % n.id)
		if n.lane < 0 or n.lane >= lanes.size():
			out.append("音符 id=%d 的轨道 %d 不存在" % [n.id, n.lane])
		if n.type == RhythmChartNote.Type.HOLD and n.duration <= 0.0:
			out.append("音符 id=%d 是长条但 duration <= 0（会被当成 Tap）" % n.id)
		# 同轨同时间堆叠：多半是手滑点出来的，提示一下。
		var key := "%d@%.3f" % [n.lane, n.time]
		if seen.has(key):
			out.append("音符 id=%d 与 id=%d 同轨同位置重叠" % [int(seen[key]), n.id])
		else:
			seen[key] = n.id
	var f := String(audio.get("file", ""))
	if f.is_empty():
		out.append("还没指定音频文件（可以继续编辑，但没法试听）")
	return out


func emit_changed() -> void:
	changed.emit()
