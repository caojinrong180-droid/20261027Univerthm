class_name ChartSource
extends RefCounted
## 谱面发现 + 加载。
##
## 支持的三种形态（都来自网页制谱器 / 手写）：
##   1. zip        —— 制谱器 Ctrl+S 导出的包：chart.json + 音频 + 曲绘
##   2. 文件夹     —— 目录里有 chart.json，音频 / 曲绘放同目录（demo 就是这种）
##   3. 单个 json  —— chart.json / xxx.rchart，音频去同目录、res://audio、user://audio 找
##
## 扫描根目录：res://charts（随游戏发布）+ user://charts（拖进来的谱面）

const CHART_EXTS := ["json", "rchart"]
const AUDIO_EXTS := ["mp3", "ogg", "wav"]
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp"]
const MAX_SCAN_DEPTH := 3


# --------------------------------------------------------------------------- #
# 扫描
# --------------------------------------------------------------------------- #

static func scan(roots: Array) -> Array:
	var entries: Array = []
	var seen := {}
	for root in roots:
		_scan_dir(str(root), 0, entries, seen)
	entries.sort_custom(func(a, b):
		var ta := str(a["title"]).to_lower()
		var tb := str(b["title"]).to_lower()
		if ta == tb:
			return str(a["key"]) < str(b["key"])
		return ta < tb)
	return entries


static func _scan_dir(dir_path: String, depth: int, entries: Array, seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	var subdirs: Array = []
	var files: Array = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		if dir.current_is_dir():
			subdirs.append(name)
		else:
			files.append(name)
		name = dir.get_next()
	dir.list_dir_end()

	# 这个目录自己就是一谱面（有 chart.json）→ 当成一个包，不再往子目录钻
	if depth > 0 and files.has("chart.json"):
		var entry = _entry_from_folder(dir_path)
		if entry != null:
			_add_entry(entries, seen, entry)
		return

	for f in files:
		var file_name := str(f)
		var ext := file_name.get_extension().to_lower()
		var path := _join(dir_path, file_name)
		if ext == "zip":
			var zip_entry = _entry_from_zip(path)
			if zip_entry != null:
				_add_entry(entries, seen, zip_entry)
		elif CHART_EXTS.has(ext):
			var json_entry = _entry_from_json(path, dir_path)
			if json_entry != null:
				_add_entry(entries, seen, json_entry)

	if depth < MAX_SCAN_DEPTH:
		for sub in subdirs:
			_scan_dir(_join(dir_path, str(sub)), depth + 1, entries, seen)


static func _add_entry(entries: Array, seen: Dictionary, entry: Dictionary) -> void:
	var key := str(entry.get("key", ""))
	if key == "" or seen.has(key):
		return
	seen[key] = true
	entries.append(entry)


static func _entry_from_folder(dir_path: String) -> Variant:
	var json_path := _join(dir_path, "chart.json")
	var chart = _parse_json_file(json_path)
	if chart == null:
		return null
	return _make_entry("folder:" + dir_path, "folder", dir_path, chart, dir_path, json_path)


static func _entry_from_json(json_path: String, search_dir: String) -> Variant:
	var chart = _parse_json_file(json_path)
	if chart == null:
		return null
	return _make_entry("json:" + json_path, "json", json_path, chart, search_dir, json_path)


static func _entry_from_zip(zip_path: String) -> Variant:
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		return null
	var chart_name := _zip_find(z.get_files(), "chart.json")
	if chart_name == "":
		z.close()
		return null
	var bytes := z.read_file(chart_name)
	z.close()
	var chart = _parse_json_bytes(bytes)
	if chart == null:
		return null
	return _make_entry("zip:" + zip_path, "zip", zip_path, chart, "", chart_name)


static func _make_entry(key: String, kind: String, path: String, chart: Dictionary,
		search_dir: String, chart_file: String) -> Dictionary:
	var meta: Dictionary = chart.get("meta", {})
	var audio_file := str(chart.get("audio", {}).get("file", ""))
	var cover_file := str(meta.get("cover", ""))
	var notes_arr = chart.get("notes", [])
	var note_count: int = notes_arr.size() if notes_arr is Array else 0

	var has_audio := false
	var has_cover := false
	var zip_files: Array = []
	if kind == "zip":
		var z := ZIPReader.new()
		if z.open(path) == OK:
			zip_files = z.get_files()
			z.close()
		if audio_file == "":
			for f in zip_files:
				if AUDIO_EXTS.has(str(f).get_extension().to_lower()):
					audio_file = str(f).get_file()
					break
		has_audio = audio_file != "" and _zip_find(zip_files, audio_file) != ""
		has_cover = cover_file != "" and _zip_find(zip_files, cover_file) != ""
	else:
		if audio_file == "":
			for f in _list_files(search_dir):
				if AUDIO_EXTS.has(str(f).get_extension().to_lower()):
					audio_file = str(f)
					break
		has_audio = audio_file != "" and _resolve_media(search_dir, audio_file) != ""
		if cover_file == "":
			for f in _list_files(search_dir):
				if IMAGE_EXTS.has(str(f).get_extension().to_lower()):
					cover_file = str(f)
					break
		has_cover = cover_file != "" and _resolve_media(search_dir, cover_file) != ""

	return {
		"key": key,
		"kind": kind,
		"path": path,
		"chart_file": chart_file,
		"search_dir": search_dir,
		"chart": chart,                       # 扫描时解析好的（只用来显示 / 统计，游玩时会重新解析）
		"title": str(meta.get("title", "未命名谱面")),
		"artist": str(meta.get("artist", "")),
		"charter": str(meta.get("charter", "")),
		"illustrator": str(meta.get("illustrator", "")),
		"difficulty": str(meta.get("difficulty", "NORMAL")),
		"level": int(meta.get("level", 1)),
		"note_count": note_count,
		"duration": RhythmChart.chart_duration(chart),
		"audio_file": audio_file,
		"cover_file": cover_file,
		"has_audio": has_audio,
		"has_cover": has_cover,
		"source": _display_source(kind, path),
	}


static func _display_source(kind: String, path: String) -> String:
	if path.begins_with("res://"):
		return path.trim_prefix("res://")
	if path.begins_with("user://"):
		return "用户目录 / " + path.trim_prefix("user://")
	return path


# --------------------------------------------------------------------------- #
# 加载（跑一遍谱面）
# --------------------------------------------------------------------------- #

## 返回 { chart, stream, cover, warnings, errors }
static func load_entry(entry: Dictionary) -> Dictionary:
	var result := {"chart": null, "stream": null, "cover": null, "storyboard": {}, "warnings": [], "errors": []}
	if str(entry.get("kind", "")) == "zip":
		_load_zip(entry, result)
	else:
		_load_loose(entry, result)
	return result


static func _load_loose(entry: Dictionary, result: Dictionary) -> void:
	var json_path := str(entry.get("chart_file", ""))
	var chart = _parse_json_file(json_path)
	if chart == null:
		result["errors"].append("读不了谱面: " + json_path)
		return
	result["chart"] = chart

	# 故事板（可选）：同目录有 storyboard.json 就一起读
	var search_dir0 := str(entry.get("search_dir", ""))
	var sb_path := _join(search_dir0, "storyboard.json")
	if FileAccess.file_exists(sb_path):
		var sb_bytes := FileAccess.get_file_as_bytes(sb_path)
		var sb_raw = _parse_raw_json_bytes(sb_bytes)
		if sb_raw != null and sb_raw is Dictionary:
			result["storyboard"] = StoryboardSource.parse(sb_raw)

	var search_dir := str(entry.get("search_dir", ""))
	var audio_name := str(chart.get("audio", {}).get("file", ""))
	if audio_name == "":
		for f in _list_files(search_dir):
			if AUDIO_EXTS.has(str(f).get_extension().to_lower()):
				audio_name = str(f)
				break
	if audio_name != "":
		var audio_path := _resolve_media(search_dir, audio_name)
		if audio_path == "":
			result["warnings"].append("找不到音频: " + audio_name)
		else:
			var bytes := FileAccess.get_file_as_bytes(audio_path)
			var stream := _make_stream(audio_path, bytes)
			if stream == null:
				result["warnings"].append("音频格式读不了: " + audio_path)
			else:
				result["stream"] = stream

	var cover_name := str(chart.get("meta", {}).get("cover", ""))
	if cover_name == "":
		for f in _list_files(search_dir):
			if IMAGE_EXTS.has(str(f).get_extension().to_lower()):
				cover_name = str(f)
				break
	if cover_name != "":
		var cover_path := _resolve_media(search_dir, cover_name)
		if cover_path != "":
			result["cover"] = _make_texture(cover_path, FileAccess.get_file_as_bytes(cover_path))


static func _load_zip(entry: Dictionary, result: Dictionary) -> void:
	var zip_path := str(entry.get("path", ""))
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		result["errors"].append("打不开 zip: " + zip_path)
		return
	var files := z.get_files()
	var chart_name := _zip_find(files, str(entry.get("chart_file", "chart.json")))
	if chart_name == "":
		z.close()
		result["errors"].append("zip 里没有 chart.json")
		return
	var chart = _parse_json_bytes(z.read_file(chart_name))
	if chart == null:
		z.close()
		result["errors"].append("zip 里的 chart.json 不是合法 JSON")
		return
	result["chart"] = chart

	# 故事板（可选）：包里带 storyboard.json 就一起读进来
	var sb_files: Array = []
	var zb := ZIPReader.new()
	if zb.open(zip_path) == OK:
		sb_files = zb.get_files()
		var sb_name := _zip_find(sb_files, "storyboard.json")
		if sb_name != "":
			var sb_raw = _parse_raw_json_bytes(zb.read_file(sb_name))
			if sb_raw != null and sb_raw is Dictionary:
				result["storyboard"] = StoryboardSource.parse(sb_raw)
		zb.close()

	var audio_name := str(chart.get("audio", {}).get("file", ""))
	if audio_name == "":
		for f in files:
			if AUDIO_EXTS.has(str(f).get_extension().to_lower()):
				audio_name = str(f)
				break
	var audio_in_zip := _zip_find(files, audio_name)
	if audio_in_zip != "":
		var stream := _make_stream(audio_in_zip, z.read_file(audio_in_zip))
		if stream == null:
			result["warnings"].append("音频格式读不了: " + audio_in_zip)
		else:
			result["stream"] = stream
	elif audio_name != "":
		result["warnings"].append("zip 里没有音频: " + audio_name)

	var cover_name := str(chart.get("meta", {}).get("cover", ""))
	if cover_name == "":
		for f in files:
			if IMAGE_EXTS.has(str(f).get_extension().to_lower()):
				cover_name = str(f)
				break
	var cover_in_zip := _zip_find(files, cover_name)
	if cover_in_zip != "":
		result["cover"] = _make_texture(cover_in_zip, z.read_file(cover_in_zip))
	z.close()


## 只读曲绘（选曲界面预览用，不重新解析整个谱面）
static func load_cover(entry: Dictionary) -> Texture2D:
	var kind := str(entry.get("kind", ""))
	var cover_name := str(entry.get("cover_file", ""))
	if cover_name == "":
		return null
	if kind == "zip":
		var z := ZIPReader.new()
		if z.open(str(entry.get("path", ""))) != OK:
			return null
		var name := _zip_find(z.get_files(), cover_name)
		var tex: Texture2D = null
		if name != "":
			tex = _make_texture(name, z.read_file(name))
		z.close()
		return tex
	var path := _resolve_media(str(entry.get("search_dir", "")), cover_name)
	if path == "":
		return null
	return _make_texture(path, FileAccess.get_file_as_bytes(path))


# --------------------------------------------------------------------------- #
# 文件小工具
# --------------------------------------------------------------------------- #

static func _join(dir_path: String, name: String) -> String:
	if dir_path == "":
		return name
	if dir_path.ends_with("/"):
		return dir_path + name
	return dir_path + "/" + name


static func _list_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with(".") and not dir.current_is_dir():
			out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## 媒体名 → 实际路径。先看谱面同目录，再看 res://audio、user://audio。
static func _resolve_media(search_dir: String, name: String) -> String:
	if name == "":
		return ""
	var candidates: Array = []
	if search_dir != "":
		candidates.append(_join(search_dir, name))
	candidates.append("res://audio/" + name)
	candidates.append("user://audio/" + name)
	candidates.append("res://" + name)
	candidates.append("user://" + name)
	for c in candidates:
		if FileAccess.file_exists(str(c)):
			return str(c)
	# 大小写 / 子目录兜底
	if search_dir != "":
		for f in _list_files(search_dir):
			if str(f).get_file().to_lower() == name.get_file().to_lower():
				return _join(search_dir, str(f))
	return ""


static func _zip_find(files: Array, name: String) -> String:
	if name == "":
		return ""
	if files.has(name):
		return name
	for f in files:
		if str(f).to_lower() == name.to_lower():
			return str(f)
	var want := name.get_file().to_lower()
	for f in files:
		if str(f).get_file().to_lower() == want:
			return str(f)
	return ""


static func _parse_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return null
	return _parse_json_text(text)


static func _parse_json_bytes(bytes: PackedByteArray) -> Variant:
	if bytes.is_empty():
		return null
	return _parse_json_text(bytes.get_string_from_utf8())


## 原生 JSON 解析（不做谱面归一化）—— 故事板 json 必须走这条
static func _parse_raw_json_bytes(bytes: PackedByteArray) -> Variant:
	if bytes.is_empty():
		return null
	return JSON.parse_string(bytes.get_string_from_utf8())


static func _parse_json_text(text: String) -> Variant:
	var raw = JSON.parse_string(text)
	if raw == null:
		return null
	var res := RhythmChart.parse(raw)
	return res.get("chart")


static func _make_stream(name: String, bytes: PackedByteArray) -> AudioStream:
	if bytes.is_empty():
		return null
	match name.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	return null


static func _make_texture(name: String, bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := ERR_UNAVAILABLE
	match name.get_extension().to_lower():
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
		_:
			return null
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


## 把拖进窗口的文件复制到 user://charts（zip / json）
static func import_file(src_path: String) -> Dictionary:
	var ext := src_path.get_extension().to_lower()
	if not (ext == "zip" or CHART_EXTS.has(ext)):
		return {"ok": false, "message": "只认 .zip / .json / .rchart"}
	var target_dir := "user://charts"
	DirAccess.make_dir_recursive_absolute(target_dir)
	var dest := _join(target_dir, src_path.get_file())
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		return {"ok": false, "message": "文件读不出来: " + src_path}
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "message": "写不进 user://charts"}
	f.store_buffer(bytes)
	f.close()
	return {"ok": true, "message": "已导入 " + src_path.get_file()}


## 解锁动画（烘焙好的帧序列）
## 返回 { ok, fps, frames: Array[PackedByteArray], width, duration, audio: PackedByteArray }
## 包里由 tools/bake_unlock.ps1 生成：unlock_frames/*.jpg + unlock_audio.ogg + unlock.json
static func load_unlock(entry: Dictionary) -> Dictionary:
	var none := {"ok": false}
	var kind := str(entry.get("kind", ""))

	if kind == "zip":
		var zip_path := str(entry.get("path", ""))
		var z := ZIPReader.new()
		if z.open(zip_path) != OK:
			return none
		var files := z.get_files()
		var meta_name := ""
		var frame_names: Array = []
		var audio_name := ""
		for f in files:
			var name := str(f)
			if name == "unlock.json":
				meta_name = name
			elif name.begins_with("unlock_frames/") and name.get_extension().to_lower() == "jpg":
				frame_names.append(name)
			elif name == "unlock_audio.ogg":
				audio_name = name
		if meta_name == "" or frame_names.is_empty():
			z.close()
			return none
		var meta_raw = _parse_raw_json_bytes(z.read_file(meta_name))
		if typeof(meta_raw) != TYPE_DICTIONARY:
			z.close()
			return none
		frame_names.sort()
		var frames: Array = []
		for fn_name in frame_names:
			frames.append(z.read_file(str(fn_name)))
		var audio := PackedByteArray()
		if audio_name != "":
			audio = z.read_file(audio_name)
		z.close()
		return {
			"ok": true,
			"fps": maxf(1.0, _fnum(meta_raw.get("fps"), 15.0)),
			"width": int(_fnum(meta_raw.get("width"), 1280.0)),
			"duration": _fnum(meta_raw.get("duration"), float(frames.size()) / 15.0),
			"frames": frames,
			"audio": audio,
		}

	# 松散目录
	var dir := str(entry.get("search_dir", ""))
	var meta_path := _join(dir, "unlock.json")
	if not FileAccess.file_exists(meta_path):
		return none
	var meta2 = _parse_raw_json_bytes(FileAccess.get_file_as_bytes(meta_path))
	if typeof(meta2) != TYPE_DICTIONARY:
		return none
	var frames2: Array = []
	for f in _list_files(_join(dir, "unlock_frames")):
		if str(f).get_extension().to_lower() == "jpg":
			frames2.append(f)
	frames2.sort()
	var datas: Array = []
	for f in frames2:
		datas.append(FileAccess.get_file_as_bytes(_join(_join(dir, "unlock_frames"), f)))
	var audio2 := PackedByteArray()
	var audio_path := _join(dir, "unlock_audio.ogg")
	if FileAccess.file_exists(audio_path):
		audio2 = FileAccess.get_file_as_bytes(audio_path)
	return {
		"ok": not datas.is_empty(),
		"fps": maxf(1.0, _fnum(meta2.get("fps"), 15.0)),
		"width": int(_fnum(meta2.get("width"), 1280.0)),
		"duration": _fnum(meta2.get("duration"), float(datas.size()) / 15.0),
		"frames": datas,
		"audio": audio2,
	}


static func _fnum(v, def: float) -> float:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_STRING and str(v).is_valid_float():
		return float(v)
	return def
