@tool
class_name RhythmChartIO
extends RefCounted
## 谱面 JSON 读写。编辑器和游戏运行时都可以直接调用：
##
##     var report := []
##     var doc := RhythmChartIO.load_file("res://charts/neon.json", report)
##     for n in doc.notes: ...


const SUPPORTED_EXTENSIONS: Array = ["json", "rchart"]


static func load_file(path: String, report: Variant = null) -> RhythmChartDocument:
	var out: Array = report if report is Array else []
	if path.strip_edges().is_empty():
		out.append("路径为空")
		return null
	if not FileAccess.file_exists(path):
		out.append("文件不存在：%s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out.append("打开失败：%s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	return doc_from_text(text, path, out)


static func doc_from_text(text: String, source_path: String = "", report: Variant = null) -> RhythmChartDocument:
	var out: Array = report if report is Array else []
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		out.append("JSON 解析失败，第 %d 行：%s" % [json.get_error_line(), json.get_error_message()])
		return null
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		out.append("谱面根节点必须是 JSON 对象（现在是 %s）" % type_string(typeof(data)))
		return null
	var doc := RhythmChartDocument.new()
	doc.from_dict(data, out)
	doc.path = source_path
	doc.validate(out)
	return doc


static func save_file(doc: RhythmChartDocument, path: String) -> Error:
	if doc == null:
		return ERR_INVALID_PARAMETER
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK and mk != ERR_ALREADY_EXISTS:
			return mk
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(doc_to_text(doc))
	f.flush()
	f.close()
	doc.path = path
	return OK


static func doc_to_text(doc: RhythmChartDocument) -> String:
	# Tab 缩进：diff 友好，人也能直接改。
	return JSON.stringify(doc.to_dict(), "\t") + "\n"


static func is_supported_path(path: String) -> bool:
	return SUPPORTED_EXTENSIONS.has(path.get_extension().to_lower())
