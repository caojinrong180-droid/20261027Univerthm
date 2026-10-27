@tool
class_name RhythmChartTiming
extends RefCounted
## 时间轴 / BPM 映射。
##
## 约定：
##   * 谱面时间一律用「秒」，因为音频和判定都是以秒为单位的，不会有累加误差。
##   * 拍号只用于「吸附网格」和「小节线」，不改写已有音符的时间。
##   * beat_offset 是第 0 拍落在多少秒（音频前奏就靠它对齐）。
##   * bpm_events 为空时 = 全曲恒定 bpm；有内容时第 0 个事件必须从 beat 0 开始。

var bpm: float = 120.0
var beat_offset: float = 0.0
## [{ "beat": 0.0, "bpm": 150.0 }, ...]，按 beat 升序。
var bpm_events: Array = []

var _segments: Array = []
var _dirty: bool = true


func set_bpm(value: float) -> void:
	bpm = maxf(value, 1.0)
	_dirty = true


func set_beat_offset(value: float) -> void:
	beat_offset = value
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


# --- 内部：把 bpm_events 展开成 (beat, bpm, sec) 分段 ---

func _rebuild() -> void:
	_dirty = false
	_segments.clear()

	var src: Array = []
	if bpm_events.is_empty():
		src.append({"beat": 0.0, "bpm": maxf(bpm, 1.0)})
	else:
		for e in bpm_events:
			if e is Dictionary:
				src.append({
					"beat": maxf(float(e.get("beat", 0.0)), 0.0),
					"bpm": maxf(float(e.get("bpm", bpm)), 1.0),
				})
		if src.is_empty():
			src.append({"beat": 0.0, "bpm": maxf(bpm, 1.0)})

	src.sort_custom(func(a, b): return float(a["beat"]) < float(b["beat"]))

	# 去重：同一 beat 上多条只保留最后一条。
	var clean: Array = []
	for e in src:
		if not clean.is_empty() and is_equal_approx(float(clean[-1]["beat"]), float(e["beat"])):
			clean[-1] = e
		else:
			clean.append(e)

	# 第一个事件固定在 beat 0，这样 beat 0 一定等于 beat_offset 秒。
	var first_bpm: float = float(clean[0]["bpm"]) if not clean.is_empty() else maxf(bpm, 1.0)
	_segments.append({"beat": 0.0, "bpm": first_bpm, "sec": beat_offset})
	var prev: Dictionary = _segments[0]
	for i in range(clean.size()):
		var e: Dictionary = clean[i]
		if i == 0:
			if not is_zero_approx(float(e["beat"])):
				# 用户把第一个事件写在 beat>0：用这个 bpm 作为基准，忽略它的 beat 偏移。
				prev["bpm"] = float(e["bpm"])
			continue
		var sec: float = float(prev["sec"]) + (float(e["beat"]) - float(prev["beat"])) * 60.0 / float(prev["bpm"])
		var seg := {"beat": float(e["beat"]), "bpm": float(e["bpm"]), "sec": sec}
		_segments.append(seg)
		prev = seg

	if not _segments.is_empty():
		bpm = float(_segments[0]["bpm"])


func _ensure() -> void:
	if _dirty or _segments.is_empty():
		_rebuild()


# --- 拍 <-> 秒 ---

func beat_to_sec(beat: float) -> float:
	_ensure()
	var first: Dictionary = _segments[0]
	if beat < float(first["beat"]):
		return float(first["sec"]) + (beat - float(first["beat"])) * 60.0 / float(first["bpm"])
	var seg: Dictionary = first
	for s in _segments:
		if float(s["beat"]) <= beat + 1e-9:
			seg = s
		else:
			break
	return float(seg["sec"]) + (beat - float(seg["beat"])) * 60.0 / float(seg["bpm"])


func sec_to_beat(sec: float) -> float:
	_ensure()
	var first: Dictionary = _segments[0]
	if sec < float(first["sec"]):
		return float(first["beat"]) + (sec - float(first["sec"])) * float(first["bpm"]) / 60.0
	var seg: Dictionary = first
	for s in _segments:
		if float(s["sec"]) <= sec + 1e-9:
			seg = s
		else:
			break
	return float(seg["beat"]) + (sec - float(seg["sec"])) * float(seg["bpm"]) / 60.0


## 指定拍位上的单拍时长（秒）。
func beat_duration_at(beat: float) -> float:
	_ensure()
	var seg: Dictionary = _segments[0]
	for s in _segments:
		if float(s["beat"]) <= beat + 1e-9:
			seg = s
		else:
			break
	return 60.0 / float(seg["bpm"])


# --- 吸附 ---

## divisor = 每拍切几份：1=整拍, 2=半拍, 3=三连, 4=十六分音符（默认）, 8=三十二分。
## divisor <= 0 时原样返回（= 关闭吸附）。
func snap_sec(sec: float, divisor: int) -> float:
	if divisor <= 0:
		return maxf(sec, 0.0)
	var step := 1.0 / float(divisor)
	var beat := sec_to_beat(sec)
	var snapped_beat := roundf(beat / step) * step
	# 防止 -0.0 之类让吸附跑到负时间。
	return maxf(beat_to_sec(snapped_beat), 0.0)


## 返回 [from_beat, to_beat] 区间内所有网格拍位（含端点附近）。
func grid_beats(from_beat: float, to_beat: float, divisor: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if divisor <= 0 or to_beat < from_beat:
		return out
	var step := 1.0 / float(divisor)
	var b := floorf(from_beat / step) * step
	var guard := 0
	while b <= to_beat + 1e-9 and guard < 20000:
		if b >= from_beat - 1e-9:
			out.append(b)
		b += step
		guard += 1
	return out


func total_beats(duration_sec: float) -> float:
	return sec_to_beat(duration_sec)


# --- 序列化 ---

func to_dict() -> Dictionary:
	_ensure()
	var events: Array = []
	for s in _segments:
		events.append({
			"beat": snappedf(float(s["beat"]), 0.000001),
			"bpm": snappedf(float(s["bpm"]), 0.001),
		})
	if events.size() <= 1:
		events = [{"beat": 0.0, "bpm": snappedf(bpm, 0.001)}]
	return {
		"bpm": snappedf(bpm, 0.001),
		"beat_offset": snappedf(beat_offset, 0.000001),
		"bpm_events": events,
	}


func from_dict(d: Dictionary) -> RhythmChartTiming:
	bpm = maxf(float(d.get("bpm", 120.0)), 1.0)
	beat_offset = float(d.get("beat_offset", 0.0))
	bpm_events.clear()
	var raw: Variant = d.get("bpm_events", [])
	if raw is Array:
		for e in raw:
			if e is Dictionary:
				bpm_events.append({
					"beat": maxf(float(e.get("beat", 0.0)), 0.0),
					"bpm": maxf(float(e.get("bpm", bpm)), 1.0),
				})
	_dirty = true
	_ensure()
	return self


func duplicate_timing() -> RhythmChartTiming:
	var t := RhythmChartTiming.new()
	t.bpm = bpm
	t.beat_offset = beat_offset
	t.bpm_events = bpm_events.duplicate(true)
	t.mark_dirty()
	return t
