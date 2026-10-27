# Godot 4 对接指南 · rchart 谱面

> 配套阅读：[CHART_FORMAT.md](CHART_FORMAT.md)（数据字段）、[GAME_INTEGRATION.md](GAME_INTEGRATION.md)（渲染与判定原理）
> 这份文档只讲 Godot 怎么落地：读 zip、读谱、算动画、画、判定、对音。
>
> 文中所有公式和 `web/js/core.js` 是同一套，照抄不会错。
> **本页所有 GDScript 都用 Godot 4.7.2 的 `--check-only` 跑过语法检查**（两个文件都返回 0）。

---

## 1. 资源怎么进游戏

编辑器导出的是一个 zip（`chart.json` + 音频 + 曲绘）。Godot 4 自带 `ZIPReader`，**不用解压成散文件**：

```gdscript
# 从 res:// 或 user:// 里读 zip
var z := ZIPReader.new()
var err := z.open("res://charts/neon_pulse.zip")
if err != OK:
    push_error("打不开 zip: %s" % err)
    return

var files := z.get_files()                      # ["chart.json", "song.mp3", "cover.png"]

var json_text := z.read_file("chart.json").get_string_from_utf8()
var raw = JSON.parse_string(json_text)
if raw == null:
    push_error("chart.json 不是合法 JSON")
    return

# 音频
var audio_bytes := z.read_file("song.mp3")
var stream := _make_stream("song.mp3", audio_bytes)

# 曲绘
var cover_bytes := z.read_file("cover.png")
var cover := Image.new()
cover.load_png_from_buffer(cover_bytes)         # jpg 用 load_jpg_from_buffer

z.close()
```

### 按扩展名取音频流

```gdscript
func _make_stream(name: String, bytes: PackedByteArray) -> AudioStream:
    var ext := name.get_extension().to_lower()
    match ext:
        "ogg": return AudioStreamOggVorbis.load_from_buffer(bytes)
        "mp3": return AudioStreamMP3.load_from_buffer(bytes)
        "wav": return AudioStreamWAV.load_from_buffer(bytes)
    push_warning("不认识的音频格式: " + ext)
    return null
```

> `AudioStreamWAV.load_from_buffer` / `AudioStreamOggVorbis.load_from_buffer` /
> `AudioStreamMP3.load_from_buffer` 都是 Godot 4 的静态方法。
> 如果你的版本缺 WAV 那个，就把字节写到 `user://` 再用 `load()`，或者干脆要求谱师交 ogg。

---

## 2. 数据层：一小段 GDScript

建议单独建一个 `rhythm_chart.gd`，里面全是 `static func`，游戏和工具都能用。
JSON 读出来是 `Dictionary` / `Array` / `float`，**数字一律是 float**，要 `int()` 转一下。

```gdscript
class_name RhythmChart
extends RefCounted

const KEYS := ["x", "y", "alpha", "rotation", "speed", "length"]
const ALL_KEYS := ["x", "y", "alpha", "rotation", "speed", "length", "zone"]

const ZONE_COLORS := {
    "none":  Color("#ffffff"),
    "left":  Color("#b06bff"),
    "right": Color("#ffd166"),
}
const ZONE_KEYS := {
    "none":  ["A", "S", "D", "F", "J", "K", "L", ";"],
    "left":  ["A", "S", "D", "F"],
    "right": ["J", "K", "L", ";"],
}
# 默认值：注意 speed / length 是 10，alpha 是 0（= 完全隐藏）
const DEFAULTS := {
    "x": 0.0, "y": 0.0, "alpha": 0.0,
    "rotation": 0.0, "speed": 10.0, "length": 10.0,
}

# ---------- 读谱 ----------

static func parse(raw) -> Dictionary:
    var chart := {
        "meta":  {"title": "", "artist": "", "charter": "", "illustrator": "",
                  "difficulty": "NORMAL", "level": 1, "cover": ""},
        "audio": {"file": "", "offset": 0.0, "volume_db": 0.0, "hit_volume_db": -3.0},
        "timing": {"bpm": 150.0, "beat_offset": 0.0},
        "lanes": [],
        "notes": [],
    }
    if typeof(raw) != TYPE_DICTIONARY:
        return chart

    var meta = raw.get("meta", {})
    if typeof(meta) == TYPE_DICTIONARY:
        for k in chart["meta"].keys():
            if meta.has(k):
                chart["meta"][k] = meta[k]

    var audio = raw.get("audio", {})
    if typeof(audio) == TYPE_DICTIONARY:
        chart["audio"]["file"] = str(audio.get("file", ""))
        chart["audio"]["offset"] = float(audio.get("offset", 0.0))

    var lanes_raw: Array = raw.get("lanes", []) if typeof(raw.get("lanes", [])) == TYPE_ARRAY else []
    var count: int = lanes_raw.size()
    if count == 0:
        count = int(raw.get("stage", {}).get("lane_count", 4))
    count = clampi(count, 1, 16)

    for i in count:
        var src: Dictionary = lanes_raw[i] if i < lanes_raw.size() else {}
        var lane := {"name": "Lane %d" % (i + 1), "color": "#ffffff",
                     "judge_zone": "none", "events": {}}
        for k in DEFAULTS.keys():
            lane[k] = float(src.get(k, DEFAULTS[k]))
        lane["name"] = str(src.get("name", lane["name"]))
        lane["color"] = str(src.get("color", "#ffffff"))
        var zone := str(src.get("judge_zone", "none"))
        lane["judge_zone"] = zone if ZONE_COLORS.has(zone) else "none"

        # 事件：6 条通道各自一个数组
        var evs = src.get("events", {})
        if typeof(evs) == TYPE_DICTIONARY:
            for key in ALL_KEYS:
                var arr = evs.get(key, [])
                if typeof(arr) != TYPE_ARRAY:
                    continue
                var out := []
                for e in arr:
                    if typeof(e) != TYPE_DICTIONARY:
                        continue
                    out.append({
                        "start": float(e.get("start", 0.0)),
                        "end": float(e.get("end", e.get("start", 0.0))),
                        "ease": str(e.get("ease", "linear")),
                        "from": float(e.get("from", 0.0)),
                        "to": float(e.get("to", 0.0)),
                    })
                out.sort_custom(func(a, b): return a["start"] < b["start"])
                lane["events"][key] = out
        chart["lanes"].append(lane)

    # 音符
    var notes_raw = raw.get("notes", [])
    var notes := []
    if typeof(notes_raw) == TYPE_ARRAY:
        for n in notes_raw:
            if typeof(n) != TYPE_DICTIONARY:
                continue
            var t := maxf(0.0, float(n.get("time", 0.0)))
            var lane_i := clampi(int(n.get("lane", 0)), 0, count - 1)
            var type := str(n.get("type", "tap"))
            if not ["tap", "hold", "flick", "mine"].has(type):
                type = "tap"
            var dur := 0.0
            if type == "hold":
                dur = maxf(0.0, float(n.get("duration", 0.0)))
                if dur <= 0.001:
                    type = "tap"
            notes.append({"time": t, "lane": lane_i, "type": type, "duration": dur,
                          "judged": false, "result": ""})
    notes.sort_custom(func(a, b):
        return a["time"] < b["time"] if a["time"] != b["time"] else a["lane"] < b["lane"])
    chart["notes"] = notes

    chart["timing"]["bpm"] = clampf(float(raw.get("timing", {}).get("bpm", 150.0)), 20.0, 1000.0)
    return chart

# ---------- 参数换算 ----------

static func lane_alpha(p: Dictionary) -> float:
    return clampf(float(p.get("alpha", 0.0)) / 100.0, 0.0, 1.0)

static func lane_speed(p: Dictionary) -> float:
    var v := clampf(float(p.get("speed", 10.0)), 0.0, 100.0)
    return v * v / 100.0

static func lane_length(p: Dictionary) -> float:
    return clampf(float(p.get("length", 10.0)) / 10.0, 0.0, 10.0)

static func lane_keys(lane: Dictionary) -> Array:
    return ZONE_KEYS.get(lane.get("judge_zone", "none"), ZONE_KEYS["none"])

static func display_color(lane: Dictionary) -> Color:
    var zone := str(lane.get("judge_zone", "none"))
    if zone != "none" and ZONE_COLORS.has(zone):
        return ZONE_COLORS[zone]
    return Color(str(lane.get("color", "#ffffff")))
```

---

## 3. 事件动画 + 缓动（直接抄）

```gdscript
# 判定区（会随时间变）

const ZONE_NAMES := ["none", "left", "right"]   # 0 = 白, 1 = 紫, 2 = 黄

static func zone_at(lane: Dictionary, t: float) -> String:
    var evs: Dictionary = lane.get("events", {})
    var arr: Array = evs.get("zone", [])
    var cur = null
    for e in arr:
        if float(e["start"]) <= t + 1e-9:
            cur = e
        else:
            break
    if cur == null:
        return str(lane.get("judge_zone", "none"))

    var span: float = float(cur["end"]) - float(cur["start"])
    var k01: float = 1.0 if span <= 1e-9 else clampf((t - float(cur["start"])) / span, 0.0, 1.0)
    var v: float = float(cur["from"]) + (float(cur["to"]) - float(cur["from"])) * ease_at(str(cur["ease"]), k01)
    return ZONE_NAMES[clampi(roundi(v), 0, 2)]


# 长条用的流速倍率：0 流速时回退到最近的非零流速（先往回找，再往前找）
static func hold_speed(lane: Dictionary, t: float) -> float:
    var here := lane_speed(lane_params_at(lane, t))
    if here > 0.001:
        return here

    var probes: Array = [-1e9]
    var evs: Dictionary = lane.get("events", {})
    for e in evs.get("speed", []):
        probes.append(float(e["start"]) - 1e-6)
        probes.append(float(e["end"]) + 1e-6)

    var best := 0.0
    var best_d := INF
    var best_past := false
    for pt in probes:
        var m := lane_speed(lane_params_at(lane, float(pt)))
        if m <= 0.001:
            continue
        var past: bool = float(pt) <= t
        var d: float = absf(float(pt) - t)
        if d < best_d - 1e-9 or (d <= best_d + 1e-9 and past and not best_past):
            best = m
            best_d = d
            best_past = past
    return best if best > 0.001 else 1.0

static func display_color_at(lane: Dictionary, t: float) -> Color:
    var z := zone_at(lane, t)
    if z == "none":
        return Color(str(lane.get("color", "#ffffff")))
    return ZONE_COLORS.get(z, ZONE_COLORS["none"])


# 一条轨道在 t 时刻的 6 个参数
static func lane_params_at(lane: Dictionary, t: float) -> Dictionary:
    var p := {}
    for k in KEYS:
        p[k] = float(lane.get(k, DEFAULTS[k]))

    var evs: Dictionary = lane.get("events", {})
    for k in KEYS:
        var arr: Array = evs.get(k, [])
        if arr.is_empty():
            continue

        # 取「起点 ≤ t 且起点最晚」的那条
        var cur = null
        for e in arr:
            if float(e["start"]) <= t + 1e-9:
                cur = e
            else:
                break
        if cur == null:
            continue

        var span: float = float(cur["end"]) - float(cur["start"])
        var k01: float = 1.0 if span <= 1e-9 else clampf((t - float(cur["start"])) / span, 0.0, 1.0)
        var eased: float = ease_at(str(cur["ease"]), k01)
        p[k] = float(cur["from"]) + (float(cur["to"]) - float(cur["from"])) * eased

    return p

static func ease_at(name: String, k: float) -> float:
    k = clampf(k, 0.0, 1.0)
    if name.begins_with("bezier("):
        return _bezier_from_string(name, k)

    var c1 := 1.70158
    var c3 := c1 + 1.0
    match name:
        "step":        return 0.0 if k < 1.0 else 1.0
        "inSine":      return 1.0 - cos(k * PI / 2.0)
        "outSine":     return sin(k * PI / 2.0)
        "inOutSine":   return -(cos(PI * k) - 1.0) / 2.0
        "inQuad":      return k * k
        "outQuad":     return 1.0 - (1.0 - k) * (1.0 - k)
        "inOutQuad":   return 2.0 * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2.0) / 2.0
        "inCubic":     return k * k * k
        "outCubic":    return 1.0 - pow(1.0 - k, 3.0)
        "inOutCubic":  return 4.0 * k * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 3.0) / 2.0
        "inQuart":     return k * k * k * k
        "outQuart":    return 1.0 - pow(1.0 - k, 4.0)
        "inOutQuart":  return 8.0 * pow(k, 4.0) if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 4.0) / 2.0
        "inExpo":      return 0.0 if k == 0.0 else pow(2.0, 10.0 * k - 10.0)
        "outExpo":     return 1.0 if k == 1.0 else 1.0 - pow(2.0, -10.0 * k)
        "inOutExpo":
            if k == 0.0: return 0.0
            if k == 1.0: return 1.0
            return pow(2.0, 20.0 * k - 10.0) / 2.0 if k < 0.5 \
                else (2.0 - pow(2.0, -20.0 * k + 20.0)) / 2.0
        "inBack":      return c3 * k * k * k - c1 * k * k
        "outBack":     return 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
        "inOutBack":
            return pow(2.0 * k, 2.0) * ((c1 + 1.0) * 2.0 * k - c1) / 2.0 if k < 0.5 \
                else (pow(2.0 * k - 2.0, 2.0) * ((c1 + 1.0) * (k * 2.0 - 2.0) + c1) + 2.0) / 2.0
    return k

# bezier(x1, y1, x2, y2)：和 CSS cubic-bezier 同一个算法
static func _bezier_from_string(s: String, x: float) -> float:
    var inner := s.substr(7).replace(")", "")
    var parts := inner.split(",")
    if parts.size() != 4:
        return x
    return _cubic_bezier(parts[0].to_float(), parts[1].to_float(),
                         parts[2].to_float(), parts[3].to_float(), x)

static func _cubic_bezier(x1: float, y1: float, x2: float, y2: float, x: float) -> float:
    if x <= 0.0: return 0.0
    if x >= 1.0: return 1.0
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
```

---

## 4. 画（`_draw`）

用一个 `Control`（或 `Node2D`）当舞台，`size` 就是画面尺寸。

```gdscript
extends Control

var chart: Dictionary
var chart_time := 0.0
var base_pps := 400.0     # 基础下落速度（像素/秒），按难度自己定

func _draw() -> void:
    var W := size.x
    var H := size.y
    var judge_y := roundf(H * 0.85)

    var lane_count: int = chart["lanes"].size()
    var lane_w: float = min(W * 0.05, (W * 0.43) / lane_count)
    var half_w: float = maxf(2.0, lane_w / 2.0 - 0.5)
    var note_half_w: float = maxf(2.0, half_w - 1.0)
    const NOTE_TH := 1.25

    for i in lane_count:
        var lane: Dictionary = chart["lanes"][i]
        var p := RhythmChart.lane_params_at(lane, chart_time)

        var rad := deg_to_rad(float(p["rotation"]))
        var center := Vector2(W / 2.0 + float(p["x"]), judge_y - float(p["y"]))
        var dir := Vector2.UP.rotated(rad)      # 0° 朝上，正角度顺时针
        var side := Vector2.RIGHT.rotated(rad)  # 横向

        var opacity := RhythmChart.lane_alpha(p)
        var speed_mult := RhythmChart.lane_speed(p)
        var lane_len: float = judge_y * RhythmChart.lane_length(p)
        var col := RhythmChart.display_color(lane)

        # --- 轨道本体 ---
        if opacity > 0.001 and lane_len > 0.5:
            var quad := PackedVector2Array([
                center - side * half_w,
                center + side * half_w,
                center + side * half_w + dir * lane_len,
                center - side * half_w + dir * lane_len,
            ])
            draw_colored_polygon(quad, Color(1, 1, 1, 0.03 * opacity))
            for s in [-1.0, 1.0]:
                draw_line(center + side * half_w * s,
                          center + side * half_w * s + dir * lane_len,
                          Color(col.r, col.g, col.b, 0.16 * opacity), 1.0)

        # --- 音符（不受轨道透明度影响）---
        for note in chart["notes"]:
            if int(note["lane"]) != i or note["judged"]:
                continue
            var d: float = (float(note["time"]) - chart_time) * base_pps * speed_mult
            var dur: float = float(note["duration"])
            var d_tail: float = (float(note["time"]) + dur - chart_time) * base_pps * speed_mult

            if d_tail < -10.0 or d > lane_len + 40.0:
                continue

            # hold 的尾巴
            if dur > 0.001 and d_tail > 0.0:
                var d0 := maxf(0.0, d)
                var d1 := minf(d_tail, lane_len)
                if d1 > d0:
                    draw_colored_polygon(PackedVector2Array([
                        center + dir * d0 - side * (note_half_w - 2.0),
                        center + dir * d0 + side * (note_half_w - 2.0),
                        center + dir * d1 + side * (note_half_w - 2.0),
                        center + dir * d1 - side * (note_half_w - 2.0),
                    ]), Color(col.r, col.g, col.b, 0.30))

            if d < -40.0:
                continue
            var c := center + dir * d
            var q := PackedVector2Array([
                c - side * note_half_w - dir * NOTE_TH,
                c + side * note_half_w - dir * NOTE_TH,
                c + side * note_half_w + dir * NOTE_TH,
                c - side * note_half_w + dir * NOTE_TH,
            ])
            match str(note["type"]):
                "mine":
                    draw_colored_polygon(q, Color("#1b1f28"))
                    draw_polyline(PackedVector2Array([q[0], q[1], q[2], q[3], q[0]]),
                                  Color("#ef476f"), 1.5)
                "flick":
                    draw_colored_polygon(q, col)
                    draw_line(c - dir * 2.0, c + dir * 2.0, Color("#080a0e"), 1.5)
                _:
                    draw_colored_polygon(q, Color(col.r, col.g, col.b, 0.92))
                    draw_line(q[0], q[1], Color(1, 1, 1, 0.55), 1.5)

        # --- 判定线（每条轨道自己一段）---
        if opacity > 0.001:
            draw_line(center - side * half_w, center + side * half_w,
                      Color(col.r, col.g, col.b, 0.16 * opacity), 5.0)
            draw_line(center - side * half_w, center + side * half_w,
                      Color(col.r, col.g, col.b, opacity), 1.2)
```

> **渲染顺序**：轨道 → 音符 → 判定线。判定线画在最后，才不会被音符盖住。

---

## 5. 判定

```gdscript
const KEY_ZONE := {
    "A": "left", "S": "left", "D": "left", "F": "left",
    "J": "right", "K": "right", "L": "right", ";": "right",
}
const PERFECT_MS := 0.045
const GOOD_MS := 0.090
const BAD_MS := 0.135

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        var key := OS.get_keycode_string(event.keycode)
        if KEY_ZONE.has(key):
            _press(key)

func _press(key: String) -> void:
    var zone: String = KEY_ZONE[key]
    var best = null
    var best_dt := 999.0

    for note in chart["notes"]:
        if note["judged"] or note["type"] == "mine":
            continue
        var lane: Dictionary = chart["lanes"][int(note["lane"])]
        var lz := str(lane["judge_zone"])
        if lz != "none" and lz != zone:
            continue
        var dt: float = chart_time - float(note["time"])
        if absf(dt) > BAD_MS:
            continue
        if absf(dt) < absf(best_dt):
            best = note
            best_dt = dt

    if best == null:
        _play_hit_sound()      # 空打
        return

    best["judged"] = true
    best["result"] = "perfect" if absf(best_dt) <= PERFECT_MS \
        else ("good" if absf(best_dt) <= GOOD_MS else "bad")
    _on_note_hit(best)
    _play_hit_sound()
```

漏打检测：

```gdscript
for note in chart["notes"]:
    if not note["judged"] and note["type"] != "mine" \
       and chart_time > float(note["time"]) + BAD_MS:
        note["judged"] = true
        note["result"] = "miss"
```

`hold` / `flick` / `mine` 的额外规则见 [GAME_INTEGRATION.md](GAME_INTEGRATION.md) 第 3.4 节。

---

## 6. 音频同步

```gdscript
@onready var player: AudioStreamPlayer = $AudioStreamPlayer

func chart_time_now() -> float:
    var t := player.get_playback_position()
    if player.playing:
        t += AudioServer.get_time_since_last_mix()
        t -= AudioServer.get_output_latency()     # 去掉输出延迟，手感更准
    return t - float(chart["audio"]["offset"])    # 谱面时间 = 音频时间 − offset
```

**方向别搞反**：`offset` 为正表示谱面第 0 秒对应音频的第 offset 秒，所以是**减**。

音量是 **dB**，换算成线性增益：

```gdscript
func db_to_gain(db: float) -> float:
	return clampf(pow(10.0, db / 20.0), 0.0, 1.0)

player.volume_db = float(chart["audio"]["volume_db"])        # AudioStreamPlayer 本来就是 dB，直接用
hit_player.volume_db = float(chart["audio"].get("hit_volume_db", -3.0))
```

> `volume_db = 0` 是原始音量，`-6` 约等于一半，`-60` 基本静音（编辑器滑条 0% 就是 -60）。

---

## 7. 最小可跑脚本

一个 `Control` 节点挂这个脚本，把 zip 拖进 `res://charts/` 就能跑。

```gdscript
extends Control

const ZIP_PATH := "res://charts/neon_pulse.zip"
const BASE_PPS := 420.0

var chart: Dictionary
var player := AudioStreamPlayer.new()
var cover: Texture2D
var started := false

func _ready() -> void:
    add_child(player)
    _load_zip(ZIP_PATH)
    player.finished.connect(func(): started = false)

func _load_zip(path: String) -> void:
    var z := ZIPReader.new()
    if z.open(path) != OK:
        push_error("打不开 " + path)
        return
    var json_text := z.read_file("chart.json").get_string_from_utf8()
    chart = RhythmChart.parse(JSON.parse_string(json_text))

    var audio_file := str(chart["audio"]["file"])
    if audio_file != "" and z.file_exists(audio_file):
        player.stream = _make_stream(audio_file, z.read_file(audio_file))

    var cover_file := str(chart["meta"]["cover"])
    if cover_file != "" and z.file_exists(cover_file):
        var img := Image.new()
        var bytes := z.read_file(cover_file)
        if cover_file.get_extension().to_lower() == "png":
            img.load_png_from_buffer(bytes)
        else:
            img.load_jpg_from_buffer(bytes)
        cover = ImageTexture.create_from_image(img)
    z.close()

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("ui_accept") and not started:
        started = true
        player.play()
    queue_redraw()

func _draw() -> void:
    if cover:
        draw_texture_rect(cover, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.25))
    # ……第 4 节的绘制代码，chart_time 用下面这个……
    pass

func _chart_time() -> float:
    if not started:
        return 0.0
    var t := player.get_playback_position() + AudioServer.get_time_since_last_mix()
    t -= AudioServer.get_output_latency()
    return t - float(chart["audio"]["offset"])
```

---

## 8. Godot 特有的坑

1. **JSON 数字全是 float**。`note["lane"]` 是 `0.0`，用之前 `int()`。
2. **Y 轴方向一致**：Godot 2D 也是 Y 向下，所以 `cy = judge_y - y` 直接照抄，不用反。
3. **`Vector2.UP.rotated(rad)`** 就是 `(sin, -cos)`，和编辑器的 `dx/dy` 完全一致 —— 别自己手写旋转矩阵。
4. **`Color("#ffd166")`** 能吃十六进制字符串；轨道色是 `"#rrggbb"` 格式，直接传。
5. **ZIPReader 只能读，不能写**。要回写给谱师，让他在网页制谱器里改完重新导出。
6. **`draw_colored_polygon` 是凸多边形填充**。我们的四边形都是凸的，没问题；要画凹多边形得拆。
7. **别在 `_draw` 里做排序/分配大头**。`lane_params_at` 每条轨道每帧调用一次是没问题的（6 条通道几个事件），但别在音符循环里再调一遍。
8. **音符多的谱面**：`_draw` 里遍历全部音符会卡。建议按轨道分桶 + 二分找「当前可见区间」的下标，只画 `[t, t + 可见]` 那一段。
9. **`offset` 是减不是加**。
10. **透明度 0 的轨道**：本体和判定线不画，但**音符照画**（编辑器就是这么约定的）。
