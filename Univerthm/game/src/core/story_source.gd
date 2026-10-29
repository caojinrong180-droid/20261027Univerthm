class_name StorySource
extends RefCounted
## 剧情文本发现 + 读取。
##
## 只认纯文本：把 `.txt` 放进 `res://剧情`（随游戏发布）或 `user://剧情`（收藏品页的「剧情目录」），
## 收藏品页的「剧情」分类就会自动列出来，点标题读全文。子文件夹也认（最多两层，比如 `剧情/序章/`）。
##
## 排版约定（都可以不写，写了更好看）：
##   标题：xxx          ← 第一行可写标题（也认「题目：」「title:」）
##   # 第一章 xxx       ← 行首 # / 【】 / 「第X章」当作小标题
##   ---                ← 一条分隔线
##   空行               ← 分段；一行以句号 / 问号 / 感叹号结尾也算一段结束
##
## 编码：优先 UTF-8（带不带 BOM 都行）；Windows 记事本存的 UTF-16（Unicode）也会自动认。
## GBK / ANSI 读不了，界面会提示另存为 UTF-8。

const STORY_ROOTS := ["res://剧情", "user://剧情"]
const TEXT_EXTS := ["txt"]
const MAX_SCAN_DEPTH := 2
## 估算阅读时长用的速度（字 / 分钟）
const CHARS_PER_MINUTE := 350.0
## 列表里摘要最多显示多少字
const EXCERPT_CHARS := 48
const HEADING_MARKS := ["章", "节", "回", "话", "幕"]
const RULE_CHARS := "—-_=*~·。.・　 "
## 一行以这些符号结尾就断成一段（中文小说一行一段、英文硬折行都能对上）
const SENTENCE_ENDS := '。！？…」』）)】》”’.!?'


# --------------------------------------------------------------------------- #
# 扫描
# --------------------------------------------------------------------------- #

## 返回 [{ key, path, file, title, subtitle, chars, chapters, paragraphs, minutes, utf8_ok, source }]
static func scan(roots: Array = STORY_ROOTS) -> Array:
	var entries: Array = []
	var seen := {}
	for root in roots:
		_scan_dir(str(root), 0, str(root), entries, seen)
	entries.sort_custom(func(a, b):
		var fa := str(a.get("folder", "")) + "/" + str(a.get("file", ""))
		var fb := str(b.get("folder", "")) + "/" + str(b.get("file", ""))
		var cmp := fa.naturalnocasecmp_to(fb)
		if cmp == 0:
			cmp = str(a.get("path", "")).naturalnocasecmp_to(str(b.get("path", "")))
		return cmp < 0)
	return entries


static func _scan_dir(dir_path: String, depth: int, root: String, entries: Array, seen: Dictionary) -> void:
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

	for f in files:
		if not TEXT_EXTS.has(str(f).get_extension().to_lower()):
			continue
		var path := _join(dir_path, str(f))
		var entry = _make_entry(path, _relative_folder(path, root))
		if entry == null or seen.has(entry["key"]):
			continue
		seen[entry["key"]] = true
		entries.append(entry)

	if depth < MAX_SCAN_DEPTH:
		for sub in subdirs:
			_scan_dir(_join(dir_path, str(sub)), depth + 1, root, entries, seen)


## 剧情在根目录下哪一个子文件夹：`剧情/序章/x.txt` → `序章`
static func _relative_folder(path: String, root: String) -> String:
	var dir := path.get_base_dir()
	if root == "" or dir == root:
		return ""
	if dir.begins_with(root + "/"):
		return dir.trim_prefix(root + "/")
	return dir.get_file()


static func _make_entry(path: String, folder := "") -> Variant:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var info := parse_bytes(bytes, path.get_file())
	return {
		"key": "story:" + path,
		"path": path,
		"file": path.get_file(),
		"folder": folder,
		"title": str(info["title"]),
		"subtitle": str(info["excerpt"]),
		"chars": int(info["chars"]),
		"chapters": int(info["chapters"]),
		"paragraphs": int(info["paragraphs"]),
		"minutes": int(info["minutes"]),
		"utf8_ok": bool(info["utf8_ok"]),
		"source": _display_source(path),
	}


## 读一篇剧情全文（点开列表时才读）：{ ok, error, title, blocks, chars, ... }
static func read_story(entry: Dictionary) -> Dictionary:
	var path := str(entry.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return {"ok": false, "error": "找不到剧情文件：%s" % path, "blocks": []}
	var info := parse_bytes(FileAccess.get_file_as_bytes(path), str(entry.get("file", path.get_file())))
	info["ok"] = true
	info["error"] = ""
	return info


# --------------------------------------------------------------------------- #
# 解析
# --------------------------------------------------------------------------- #

## 字节 → { ok, blocks, … }；file 用来兜底标题。
static func parse_bytes(bytes: PackedByteArray, file := "") -> Dictionary:
	var decoded := decode(bytes)
	var info := parse(str(decoded["text"]), file)
	info["utf8_ok"] = bool(decoded["utf8_ok"])
	return info


## 纯文本 → { title, blocks, chars, chapters, paragraphs, excerpt, minutes, utf8_ok }
## blocks: [{ kind: "text" | "chapter" | "rule", text: String }]
static func parse(text: String, fallback_title := "") -> Dictionary:
	var blocks: Array = []
	var title := ""
	var para := ""
	var chars := 0
	var chapters := 0
	var paragraphs := 0
	var seen_content := false
	for raw in _normalize(text).split("\n"):
		var line := str(raw).strip_edges()
		if line == "":
			if para != "":
				blocks.append({"kind": "text", "text": para})
				paragraphs += 1
				para = ""
			continue
		if not seen_content:
			var meta := _meta_title(line)
			if meta != "":
				title = meta
				seen_content = true
				chars += _count_chars(meta)
				continue
		var heading := _heading_text(line)
		if heading != "":
			if para != "":
				blocks.append({"kind": "text", "text": para})
				paragraphs += 1
				para = ""
			if not seen_content:
				title = heading
			else:
				blocks.append({"kind": "chapter", "text": heading})
				chapters += 1
			seen_content = true
			chars += _count_chars(heading)
			continue
		if _is_rule(line):
			if para != "":
				blocks.append({"kind": "text", "text": para})
				paragraphs += 1
				para = ""
			if not blocks.is_empty():
				blocks.append({"kind": "rule", "text": ""})
			continue
		seen_content = true
		chars += _count_chars(line)
		para = _join_line(para, line)
		# 一行写完就断段：一行一段的中文小说不会粘成一块，英文硬折行也接得回原段。
		if _ends_sentence(line):
			blocks.append({"kind": "text", "text": para})
			paragraphs += 1
			para = ""
	if para != "":
		blocks.append({"kind": "text", "text": para})
		paragraphs += 1
	if title == "":
		title = _title_from_file(fallback_title)

	var excerpt := ""
	for block in blocks:
		if str(block["kind"]) == "text":
			excerpt = _excerpt(str(block["text"]))
			break
	return {
		"title": title,
		"blocks": blocks,
		"chars": chars,
		"chapters": chapters,
		"paragraphs": paragraphs,
		"excerpt": excerpt,
		"minutes": maxi(1, int(ceilf(chars / CHARS_PER_MINUTE))),
		"utf8_ok": true,
	}


## 字节 → { text, utf8_ok }；认 UTF-8 / UTF-8 BOM / UTF-16 LE·BE（记事本的「Unicode」）
static func decode(bytes: PackedByteArray) -> Dictionary:
	var utf8_ok := true
	var text := ""
	if bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xFE:
		text = _decode_utf16(bytes, 2, true)
	elif bytes.size() >= 2 and bytes[0] == 0xFE and bytes[1] == 0xFF:
		text = _decode_utf16(bytes, 2, false)
	else:
		var offset := 0
		if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
			offset = 3
		text = bytes.slice(offset).get_string_from_utf8()
		if text.contains("\ufffd"):
			utf8_ok = false
	return {"text": text, "utf8_ok": utf8_ok}


static func _decode_utf16(bytes: PackedByteArray, offset: int, little_endian: bool) -> String:
	var out := ""
	var i := offset
	while i + 1 < bytes.size():
		var unit := _unit_at(bytes, i, little_endian)
		i += 2
		if unit == 0:
			continue
		if unit >= 0xD800 and unit <= 0xDBFF and i + 1 < bytes.size():
			var low := _unit_at(bytes, i, little_endian)
			if low >= 0xDC00 and low <= 0xDFFF:
				i += 2
				unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
		out += String.chr(unit)
	return out


static func _unit_at(bytes: PackedByteArray, i: int, little_endian: bool) -> int:
	if little_endian:
		return bytes[i] | (bytes[i + 1] << 8)
	return (bytes[i] << 8) | bytes[i + 1]


static func _normalize(text: String) -> String:
	var out := text.replace("\r\n", "\n").replace("\r", "\n")
	if out.begins_with("\ufeff"):
		out = out.substr(1)
	return out


static func _meta_title(line: String) -> String:
	for key in ["标题", "题目", "title", "Title", "TITLE"]:
		if not line.begins_with(key):
			continue
		var rest := line.substr(key.length()).strip_edges()
		if rest.begins_with(":") or rest.begins_with("："):
			return rest.substr(1).strip_edges()
	return ""


static func _heading_text(line: String) -> String:
	if line.begins_with("#"):
		return line.lstrip("#").strip_edges()
	if line.length() >= 3 and line.begins_with("【") and line.ends_with("】"):
		return line.substr(1, line.length() - 2).strip_edges()
	if _is_chapter_line(line):
		return line
	return ""


static func _is_chapter_line(line: String) -> bool:
	if line.length() > 24 or not line.begins_with("第"):
		return false
	for mark in HEADING_MARKS:
		var idx := line.find(mark)
		if idx > 1 and idx <= 8:
			return true
	return false


static func _is_rule(line: String) -> bool:
	if line.length() < 3:
		return false
	for ch in line:
		if not RULE_CHARS.contains(ch):
			return false
	return true


## 中文按行折行的文本直接接上；两边都是 ASCII 时补一个空格，英文段落不会粘成一坨。
static func _join_line(prev: String, line: String) -> String:
	if prev == "":
		return line
	var last := prev.unicode_at(prev.length() - 1)
	var first := line.unicode_at(0)
	if last < 128 and first < 128:
		return prev + " " + line
	return prev + line


## 判断一行是否已经说完一句话（结尾是句号 / 问号 / 感叹号 / 收尾引号……）
static func _ends_sentence(line: String) -> bool:
	if line == "":
		return true
	return SENTENCE_ENDS.contains(line[line.length() - 1])


static func _count_chars(text: String) -> int:
	var n := 0
	for ch in text:
		if ch == " " or ch == "\t" or ch == "\u3000":
			continue
		n += 1
	return n


static func _excerpt(text: String) -> String:
	var flat := text.replace("\n", " ").strip_edges()
	if flat.length() <= EXCERPT_CHARS:
		return flat
	return flat.substr(0, EXCERPT_CHARS) + "…"


## 「01_第一章 相遇.txt」→「第一章 相遇」
static func _title_from_file(file: String) -> String:
	var base := file.get_basename().strip_edges()
	if base == "":
		return "未命名剧情"
	var digits := 0
	while digits < base.length():
		var code := base.unicode_at(digits)
		if code < 48 or code > 57:
			break
		digits += 1
	if digits > 0:
		var rest := base.substr(digits).lstrip("_-— .、·:：")
		if rest.strip_edges() != "":
			base = rest
	return base.strip_edges()


# --------------------------------------------------------------------------- #
# 导入 / 路径
# --------------------------------------------------------------------------- #

## 把拖进窗口的 txt 复制到 user://剧情
static func import_file(src_path: String) -> Dictionary:
	if not TEXT_EXTS.has(src_path.get_extension().to_lower()):
		return {"ok": false, "message": "%s 不是 .txt，已忽略" % src_path.get_file()}
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		return {"ok": false, "message": "读不出来：%s" % src_path.get_file()}
	DirAccess.make_dir_recursive_absolute("user://剧情")
	var dest := "user://剧情/" + src_path.get_file()
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "message": "写不进剧情目录"}
	f.store_buffer(bytes)
	f.close()
	return {"ok": true, "message": "已导入 %s" % src_path.get_file()}


static func _display_source(path: String) -> String:
	if path.begins_with("res://"):
		return path.trim_prefix("res://")
	if path.begins_with("user://"):
		return "剧情目录 / " + path.trim_prefix("user://")
	return path


static func _join(dir_path: String, name: String) -> String:
	if dir_path == "":
		return name
	if dir_path.ends_with("/"):
		return dir_path + name
	return dir_path + "/" + name
