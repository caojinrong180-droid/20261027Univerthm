class_name RhythmJudge
extends RefCounted
## 判定引擎：按键 → 音符 → 判定 / 连击 / 分数。
##
## 纯逻辑，不依赖场景树，方便单测（tests/run_core_tests.gd）。
## 规则见 docs/GAME_INTEGRATION.md 第 3 节：
##   - 按 |now - note.time| 取最近的那个未判定音符
##   - 轨道 judge_zone = none 时任意键都能打，left 只吃 ASDF，right 只吃 JKL;
##   - hold 头判命中后要一直按住到尾部，中途松开 = 断
##
## 约定：一个音符只产生一次判定（hold 的头判就是它的判定；断了会降级成 miss），

signal note_judged(note: Dictionary, result: String, dt: float)
signal hold_completed(note: Dictionary)
signal hold_broken(note: Dictionary)

const PERFECT_PLUS_SEC := 0.055
const PERFECT_SEC := 0.080
const GOOD_SEC := 0.140
const BAD_SEC := 0.220

## 权重：Perfect+ / Perfect 记满，Good 记 75%，Bad / Miss 记 0
const WEIGHT := {"perfect_plus": 1.0, "perfect": 1.0, "good": 0.75, "bad": 0.0, "miss": 0.0}
## 满分：非 Perfect+ 部分 1,000,000；Perfect+ 单独再算 10,000，所以满 acc 上限 1,010,000
const MAX_SCORE := 1000000.0
const PERFECT_PLUS_BONUS := 10000.0

var chart: Dictionary = {}
var notes: Array = []
var lanes: Array = []
var window_scale := 1.0

var counts := {"perfect_plus": 0, "perfect": 0, "good": 0, "bad": 0, "miss": 0}
## Early / Late：只统计 Perfect 和 Good（dt < 0 = Early，dt > 0 = Late）
var early_late := {"perfect_early": 0, "perfect_late": 0, "good_early": 0, "good_late": 0}
var combo := 0
var max_combo := 0
var score := 0.0
var total_judgeable := 0
var sum_weight := 0.0
var judged_count := 0

## 当前按住的判定区（"left" / "right"），由玩法层每帧灌进来
var pressed_zones: Array = []

var _scan := 0
var _active_holds: Array = []


# --------------------------------------------------------------------------- #
# 初始化
# --------------------------------------------------------------------------- #

func setup(chart_: Dictionary, window_scale_: float = 1.0) -> void:
	chart = chart_
	notes = chart.get("notes", [])
	lanes = chart.get("lanes", [])
	window_scale = maxf(0.1, window_scale_)
	counts = {"perfect_plus": 0, "perfect": 0, "good": 0, "bad": 0, "miss": 0}
	early_late = {"perfect_early": 0, "perfect_late": 0, "good_early": 0, "good_late": 0}
	combo = 0
	max_combo = 0
	score = 0.0
	sum_weight = 0.0
	judged_count = 0
	total_judgeable = RhythmChart.judgeable_count(chart)
	pressed_zones = []
	_scan = 0
	_active_holds = []
	for n in notes:
		n["state"] = "pending"
		n["result"] = ""


func perfect_plus_window() -> float:
	return PERFECT_PLUS_SEC * window_scale


func perfect_window() -> float:
	return PERFECT_SEC * window_scale


func good_window() -> float:
	return GOOD_SEC * window_scale


func bad_window() -> float:
	return BAD_SEC * window_scale


## 按键能命中的最远距离 = Bad 窗口；超过就算没打中
func hit_window() -> float:
	return bad_window()


func active_holds() -> Array:
	return _active_holds


# --------------------------------------------------------------------------- #
# 判定
# --------------------------------------------------------------------------- #

## 处理一次按键。zone 是这个键属于哪个判定区（"left" / "right"）。
## lane_hint >= 0 时只判这条轨道上的音符（自动演示用：同区相邻音符不会互相抢判）。
## 返回 { hit: bool, result: String, note: Dictionary 或 null, dt: float, kind: String }
func press(zone: String, t: float, lane_hint := -1) -> Dictionary:
	var hit = _find_note(zone, t, lane_hint)
	if hit == null:
		return {"hit": false, "result": "", "note": null, "dt": 0.0, "kind": "empty"}

	return _apply_hit(hit, t)


func _find_note(zone: String, t: float, lane_hint := -1) -> Variant:
	var best = null
	var best_abs := INF
	var i := _scan
	while i < notes.size():
		var n: Dictionary = notes[i]
		if float(n["time"]) > t + hit_window():
			break
		i += 1
		if str(n["state"]) != "pending":
			continue
		if lane_hint >= 0 and int(n["lane"]) != lane_hint:
			continue
		var lane: Dictionary = lanes[int(n["lane"])]
		var lz := RhythmChart.lane_zone_at(lane, t)
		if lz != "none" and lz != zone:
			continue
		var dt := t - float(n["time"])
		if absf(dt) > hit_window():
			continue
		if absf(dt) < best_abs:
			best_abs = absf(dt)
			best = n
	return best




func _apply_hit(note: Dictionary, t: float) -> Dictionary:
	var dt := t - float(note["time"])
	var result := _result_for(absf(dt))
	var kind := str(note["type"])
	note["result"] = result
	if kind == "hold":
		note["state"] = "holding"
		_active_holds.append(note)
	else:
		note["state"] = "judged"
	_award(note, result, dt)
	note_judged.emit(note, result, dt)
	return {"hit": true, "result": result, "note": note, "dt": dt, "kind": kind}


func _result_for(abs_dt: float) -> String:
	if abs_dt <= perfect_plus_window():
		return "perfect_plus"
	if abs_dt <= perfect_window():
		return "perfect"
	if abs_dt <= good_window():
		return "good"
	return "bad"


func _award(note: Dictionary, result: String, dt := 0.0) -> void:
	var weight: float = float(WEIGHT.get(result, 0.0))
	note["award_weight"] = weight
	note["awarded"] = true
	# Early / Late：只记 Perfect 和 Good
	var side := ""
	if (result == "perfect" or result == "good") and absf(dt) > 1e-9:
		side = "early" if dt < 0.0 else "late"
		var key := "%s_%s" % [result, side]
		early_late[key] = int(early_late.get(key, 0)) + 1
	note["award_side"] = side

	counts[result] += 1
	judged_count += 1
	sum_weight += weight
	if result == "miss" or result == "bad":
		combo = 0                      # Bad 也断连
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
	_recompute_score()


func _revoke(note: Dictionary) -> void:
	if not bool(note.get("awarded", false)):
		return
	var result := str(note.get("result", "bad"))
	counts[result] = maxi(0, int(counts[result]) - 1)
	var side := str(note.get("award_side", ""))
	if side != "":
		var key := "%s_%s" % [result, side]
		if early_late.has(key):
			early_late[key] = maxi(0, int(early_late[key]) - 1)
	sum_weight -= float(note.get("award_weight", 0.0))
	judged_count = maxi(0, judged_count - 1)
	note["awarded"] = false
	note["award_weight"] = 0.0
	_recompute_score()


## 分数 = 1,000,000 × (加权命中 / 总音符)  +  10,000 × (Perfect+ 数 / 总音符)
## 全 Perfect+ = 1,010,000；全 Perfect = 1,000,000
func _recompute_score() -> void:
	var total := maxf(1.0, float(total_judgeable))
	score = MAX_SCORE * (sum_weight / total) + PERFECT_PLUS_BONUS * (float(counts["perfect_plus"]) / total)




# --------------------------------------------------------------------------- #
# 每帧推进
# --------------------------------------------------------------------------- #

## 推进判定状态：漏打 / hold 完成或断开。
## pressed_zones 由玩法层传入：当前按住哪些判定区。
func update(t: float) -> void:
	# 1) 到期的普通音符（notes 按 time 升序，游标单调前进）
	while _scan < notes.size():
		var n: Dictionary = notes[_scan]
		var state := str(n["state"])
		if state == "pending":
			if t > float(n["time"]) + hit_window():
				_register_miss(n)
				_scan += 1
				continue
			break
		_scan += 1

	# 2) hold：到尾部还在按 = 完成；所有键都松了才算断
	#    持续判定只看「还有没有键按着」——换手 / 换边 / zone 事件切成另一侧都不算断
	for i in range(_active_holds.size() - 1, -1, -1):
		var note: Dictionary = _active_holds[i]
		var end_time := RhythmChart.note_end(note)
		var held := any_zone_held()
		if t >= end_time - 1e-4:
			note["state"] = "judged"
			if held:
				hold_completed.emit(note)
			else:
				_break_hold(note)
			_active_holds.remove_at(i)
		elif not held:
			_break_hold(note)
			_active_holds.remove_at(i)


func _register_miss(note: Dictionary) -> void:
	note["state"] = "judged"
	note["result"] = "miss"
	counts["miss"] += 1
	judged_count += 1
	combo = 0
	note_judged.emit(note, "miss", 0.0)


func _break_hold(note: Dictionary) -> void:
	_revoke(note)
	_register_miss(note)
	hold_broken.emit(note)


## 玩法层每帧把「当前按住哪些判定区」灌进来
func set_pressed_zones(zones: Array) -> void:
	pressed_zones = zones


## 键盘上是否还有键按着（hold 的持续判定只看这个：换手 / 换边都不算断）
func any_zone_held() -> bool:
	return not pressed_zones.is_empty()



## 收尾：把还没处理完的音符一次性结掉（漏打 / hold 判定）
func finish(t: float) -> void:
	for n in notes:
		var state := str(n["state"])
		if state == "pending":
			_register_miss(n)
		elif state == "holding":
			var end_time := RhythmChart.note_end(n)
			n["state"] = "judged"
			if t >= end_time - 1e-4 and any_zone_held():
				hold_completed.emit(n)
			else:
				_break_hold(n)
	_active_holds.clear()


# --------------------------------------------------------------------------- #
# 统计
# --------------------------------------------------------------------------- #

## 游玩中的实时准确率（只算已判定的音符）
func accuracy_live() -> float:
	if judged_count <= 0:
		return 1.0
	return sum_weight / float(judged_count)


## 结算准确率（分母是全部可判定音符，没打到的按 0 算）
func accuracy_final() -> float:
	if total_judgeable <= 0:
		return 1.0
	return sum_weight / float(total_judgeable)


func is_all_perfect() -> bool:
	return total_judgeable > 0 and int(counts["perfect"]) + int(counts["perfect_plus"]) == total_judgeable


## 全 Perfect+（满分 1,010,000 的门槛）
func is_all_perfect_plus() -> bool:
	return total_judgeable > 0 and int(counts["perfect_plus"]) == total_judgeable


func is_full_combo() -> bool:
	return int(counts["miss"]) == 0 and int(counts["bad"]) == 0 and total_judgeable > 0


func grade() -> String:
	if is_all_perfect():
		return "S"
	var acc := accuracy_final()
	if acc >= 0.96:
		return "S"
	if acc >= 0.92:
		return "A"
	if acc >= 0.85:
		return "B"
	if acc >= 0.75:
		return "C"
	return "D"
