extends RefCounted
class_name StoryboardSource
## 读故事板工程（rstory v2），给游戏侧提供「某一时刻该画什么、叠哪些后处理」。
##
## 工程结构（web/js/sb_core.js 的 serializeDoc 输出）：
##   { format: "rstory", version: 2,
##     meta: { title, author, note, coverArtist },
##     stage: { width, height, bg, chartAlpha, highway, length, volume, chartBase },
##     scenes: [ { id, kind: "unlock"|"chart"|"free", name, length,
##                 layers: [ { id, type: "text"|"image"|"video"|"shape"|"unlock", ... } ],
##                 shaders: [ { id, preset, start, end, amount, ramp, ease } ] } ] }
## 场景里的时间都是**场景内本地时间**；谱面场长度跟随谱面（chart.duration）。
##
## 这里的语义和网页版一一对应（sb_core 的 sceneSpans / sceneAt / activeShaders）：
##   场景区间 = 前面所有场景长度累加；谱面场长度 = 谱面时长。

const SHADER_PRESETS := {
	"bloom": {"bloom": 1.0, "grain": 0.08},
	"rgb": {"rgb": 0.85},
	"crt": {"scan": 1.0, "rgb": 0.3, "vignette": 0.5},
	"wave": {"wave": 1.0},
	"glitch": {"glitch": 1.0, "rgb": 0.55},
	"heat": {"heat": 1.0, "wave": 0.35},
	"pixel": {"pixel": 1.0},
	"posterize": {"poster": 1.0},
	"vignette": {"vignette": 1.0},
	"grain": {"grain": 1.0, "vignette": 0.3},
	"stretch": {"stretch": 1.0},
	"zoomShake": {"zoom": 1.0, "shake": 1.0},
	"dream": {"bloom": 0.7, "wave": 0.22, "grain": 0.12},
	"flash": {"invert": 1.0, "bloom": 0.4},
}

## 「立刻」型：忽略软边（和网页的 instant 一致）
const INSTANT_PRESETS := ["rgb"]

const WEIGHT_KEYS := [
	"bloom", "rgb", "scan", "wave", "glitch", "heat",
	"pixel", "poster", "grain", "vignette", "invert", "stretch", "zoom", "shake",
]


# --------------------------------------------------------------------------- #
# 解析
# --------------------------------------------------------------------------- #

static func parse(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var doc: Dictionary = {}
	var stage_raw = raw.get("stage", {})
	var stage: Dictionary = stage_raw if typeof(stage_raw) == TYPE_DICTIONARY else {}
	doc["stage"] = {
		"width": 1280, "height": 720,
		"bg": str(stage.get("bg", "#05070c")),
		"chartAlpha": clampf(_num(stage.get("chartAlpha"), 100.0), 0.0, 100.0),
		"highway": maxf(0.05, _num(stage.get("highway"), 2.0)),
		"length": maxf(0.0, _num(stage.get("length"), 0.0)),
		"volume": clampf(_num(stage.get("volume"), 100.0), 0.0, 100.0),
		"chartBase": clampf(_num(stage.get("chartBase"), 350.0), 120.0, 2560.0),
	}

	var scenes_out: Array = []
	var scenes = raw.get("scenes", [])
	if scenes is Array:
		for sc in scenes:
			if typeof(sc) != TYPE_DICTIONARY:
				continue
			var kind := str(sc.get("kind", "free"))
			if kind != "unlock" and kind != "chart" and kind != "free":
				kind = "free"
			var layers_out: Array = []
			var layers = sc.get("layers", [])
			if layers is Array:
				for L in layers:
					if typeof(L) == TYPE_DICTIONARY:
						layers_out.append(_normalize_layer(L))
			var shaders_out: Array = []
			var shaders = sc.get("shaders", [])
			if shaders is Array:
				for fx in shaders:
					if typeof(fx) == TYPE_DICTIONARY:
						shaders_out.append({
							"id": int(_num(fx.get("id"), shaders_out.size() + 1)),
							"preset": str(fx.get("preset", "none")),
							"start": maxf(0.0, _num(fx.get("start"), 0.0)),
							"end": maxf(0.0, _num(fx.get("end"), 0.0)),
							"amount": clampf(_num(fx.get("amount"), 100.0), 0.0, 100.0),
							"ramp": clampf(_num(fx.get("ramp"), 0.28), 0.0, 0.49),
							"ease": str(fx.get("ease", "inOutSine")),
						})
			scenes_out.append({
				"id": int(_num(sc.get("id"), scenes_out.size() + 1)),
				"kind": kind,
				"name": str(sc.get("name", "")),
				"length": maxf(0.0, _num(sc.get("length"), 0.0)),
				"layers": layers_out,
				"shaders": shaders_out,
			})
	doc["scenes"] = scenes_out
	# 资源内容（图片/视频 base64）游戏侧暂时用不到，直接丢掉，省几百 MB
	var meta_raw = raw.get("meta", {})
	doc["meta"] = meta_raw if typeof(meta_raw) == TYPE_DICTIONARY else {}
	doc["format"] = str(raw.get("format", "rstory"))
	doc["version"] = int(raw.get("version", 2))
	doc["assets"] = {}
	return doc


static func _normalize_layer(L: Dictionary) -> Dictionary:
	var type := str(L.get("type", "text"))
	if not (type in ["text", "image", "video", "shape", "unlock"]):
		type = "text"
	var out := {
		"id": int(_num(L.get("id"), 0)),
		"type": type,
		"name": str(L.get("name", "")),
		"start": maxf(0.0, _num(L.get("start"), 0.0)),
		"end": maxf(0.0, _num(L.get("end"), 0.0)),
		"x": clampf(_num(L.get("x"), 0.5), -2.0, 3.0),
		"y": clampf(_num(L.get("y"), 0.5), -2.0, 3.0),
		"scale": clampf(_num(L.get("scale"), 100.0), 1.0, 800.0),
		"rot": _num(L.get("rot"), 0.0),
		"alpha": clampf(_num(L.get("alpha"), 100.0), 0.0, 100.0),
		"blend": str(L.get("blend", "normal")),
		"in": L.get("in", {}),
		"out": L.get("out", {}),
		"events": L.get("events", {}),
	}
	if type == "text":
		out["text"] = str(L.get("text", ""))
		out["style"] = L.get("style", {})
	elif type == "unlock":
		out["unlock"] = L.get("unlock", {})
	elif type == "shape":
		out["shape"] = L.get("shape", {})
	elif type == "image":
		out["image"] = L.get("image", {})
	elif type == "video":
		out["video"] = L.get("video", {})
	return out


# --------------------------------------------------------------------------- #
# 时间轴
# --------------------------------------------------------------------------- #

## 每场的区间：[{ index, scene, kind, start, end, len }]
static func scene_spans(doc: Dictionary, chart_duration: float) -> Array:
	var out: Array = []
	var t := 0.0
	for sc in doc.get("scenes", []):
		var kind := str(sc.get("kind", "free"))
		var len_s := 0.0
		if kind == "chart":
			len_s = maxf(0.1, chart_duration)
		else:
			len_s = maxf(0.1, _num(sc.get("length"), 0.0))
		out.append({
			"index": out.size(),
			"scene": sc,
			"kind": kind,
			"start": t,
			"end": t + len_s,
			"len": len_s,
		})
		t += len_s
	return out


static func total_length(doc: Dictionary, chart_duration: float) -> float:
	var spans := scene_spans(doc, chart_duration)
	return spans[spans.size() - 1]["end"] if spans.size() > 0 else 0.0


## 某一全局时刻落在哪一场
static func scene_at(doc: Dictionary, chart_duration: float, t: float) -> Dictionary:
	var spans := scene_spans(doc, chart_duration)
	if spans.is_empty():
		return {}
	var tt := clampf(t, 0.0, maxf(0.0, spans[spans.size() - 1]["end"] - 0.0001))
	for sp in spans:
		if tt < float(sp["end"]) - 1e-9 or sp == spans[spans.size() - 1]:
			return {
				"index": sp["index"],
				"kind": sp["kind"],
				"scene": sp["scene"],
				"start": sp["start"],
				"len": sp["len"],
				"local": clampf(tt - float(sp["start"]), 0.0, float(sp["len"])),
			}
	return {}


## 某一刻生效的图层（含入场/出场算出来的透明度等）
static func active_layers(scene: Dictionary, local: float) -> Array:
	var out: Array = []
	for L in scene.get("layers", []):
		if not bool(L.get("visible", true)):
			continue
		if local < float(L["start"]) - 1e-6 or local > float(L["end"]) + 1e-6:
			continue
		out.append({"layer": L, "state": layer_state(L, local)})
	return out


## 图层在这一刻的状态（入场/出场 + 关键帧通道）
static func layer_state(L: Dictionary, local: float) -> Dictionary:
	var alpha := float(L.get("alpha", 100.0)) / 100.0
	var wipe := 1.0
	var in_cfg: Dictionary = L.get("in", {}) if typeof(L.get("in", {})) == TYPE_DICTIONARY else {}
	var out_cfg: Dictionary = L.get("out", {}) if typeof(L.get("out", {})) == TYPE_DICTIONARY else {}
	var in_dur := maxf(0.0, _num(in_cfg.get("dur"), 0.0))
	var out_dur := maxf(0.0, _num(out_cfg.get("dur"), 0.0))
	var span := maxf(0.001, float(L["end"]) - float(L["start"]))
	var since := local - float(L["start"])
	var until := float(L["end"]) - local

	var k_in := 1.0 if in_dur <= 0.001 else clampf(since / minf(in_dur, span), 0.0, 1.0)
	var k_out := 1.0 if out_dur <= 0.001 else clampf(until / minf(out_dur, span), 0.0, 1.0)
	var e_in := ease_curve(str(in_cfg.get("ease", "outCubic")), k_in)
	var e_out := ease_curve(str(out_cfg.get("ease", "inCubic")), k_out)
	alpha *= minf(e_in, e_out)
	if str(in_cfg.get("preset", "none")) == "wipe":
		wipe = e_in
	if str(out_cfg.get("preset", "none")) == "wipe":
		wipe = minf(wipe, e_out)

	return {
		"alpha": clampf(alpha, 0.0, 1.0),
		"wipe": wipe,
		"dx": 0.0,
		"dy": 0.0,
		"scale": float(L.get("scale", 100.0)) / 100.0,
		"rot": float(L.get("rot", 0.0)),
	}


## 某一刻生效的后处理「层」（一条 = 一层，按列表顺序）
static func active_shaders(scene: Dictionary, local: float) -> Array:
	var out: Array = []
	for fx in scene.get("shaders", []):
		var v := shader_value(fx, local)
		if v <= 1e-4:
			continue
		var preset := str(fx.get("preset", "none"))
		if not SHADER_PRESETS.has(preset):
			continue
		var base: Dictionary = SHADER_PRESETS[preset]
		var w := {}
		for key in base:
			w[key] = float(base[key]) * v
		out.append({"preset": preset, "value": v, "weights": w, "punchT0": float(fx.get("start", 0.0))})
	return out


## 单条 shader 在这一刻的强度（0~1）：两头软、中间平；「立刻」型不看软边
static func shader_value(fx: Dictionary, t: float) -> float:
	var start := float(fx.get("start", 0.0))
	var end := maxf(start, float(fx.get("end", start)))
	if t < start - 1e-9 or t > end + 1e-9:
		return 0.0
	var span := maxf(1e-6, end - start)
	var k := clampf((t - start) / span, 0.0, 1.0)
	var ramp := clampf(_num(fx.get("ramp"), 0.28), 0.0, 0.49)
	if INSTANT_PRESETS.has(str(fx.get("preset", ""))):
		ramp = 0.0
	var env := 1.0
	if ramp >= 1e-6:
		var curve := str(fx.get("ease", "inOutSine"))
		if k < ramp:
			env = ease_curve(curve, k / ramp)
		elif k > 1.0 - ramp:
			env = ease_curve(curve, (1.0 - k) / ramp)
	return clampf(env * clampf(_num(fx.get("amount"), 100.0) / 100.0, 0.0, 1.0), 0.0, 1.0)


## 把这一刻所有生效层的权重合并成一次 uniform（游戏里只有一个 shader 材质，
## 逐层 pass 用不上时作为兜底：叠起来、同一项相加、封顶 1.5）
static func merged_weights(layers: Array) -> Dictionary:
	var w := {}
	for key in WEIGHT_KEYS:
		w[key] = 0.0
	for entry in layers:
		var ww: Dictionary = entry.get("weights", {})
		for key in ww:
			w[key] = clampf(float(w[key]) + float(ww[key]), 0.0, 1.5)
	return w


# --------------------------------------------------------------------------- #
# 小工具
# --------------------------------------------------------------------------- #

static func _num(v, def: float) -> float:
	var n := 0.0
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		n = float(v)
	elif typeof(v) == TYPE_STRING and str(v).is_valid_float():
		n = float(v)
	else:
		return def
	return n if is_finite(n) else def


## 缓动（和网页 RC.easeAt 同名同曲线）
static func ease_curve(name: String, k: float) -> float:
	var t := clampf(k, 0.0, 1.0)
	match name:
		"linear":
			return t
		"inQuad":
			return t * t
		"outQuad":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"inOutQuad":
			return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
		"inCubic":
			return t * t * t
		"outCubic":
			return 1.0 - pow(1.0 - t, 3.0)
		"inOutCubic":
			return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
		"inSine":
			return 1.0 - cos(t * PI / 2.0)
		"outSine":
			return sin(t * PI / 2.0)
		"inOutSine":
			return -(cos(PI * t) - 1.0) / 2.0
		"outBack":
			var c1 := 1.70158
			var c3 := c1 + 1.0
			return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
		_:
			return t
