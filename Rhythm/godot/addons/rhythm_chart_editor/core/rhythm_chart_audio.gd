@tool
class_name RhythmChartAudio
extends RefCounted
## 音频加载小工具。
##
## 关键点：项目里的 ogg/mp3 正常 load() 就行，
## 但制谱时经常要听一首"还不在项目里"的曲子（桌面上的音频文件），
## 这时走 AudioStreamXXX.load_from_file(绝对路径)。

const SUPPORTED: Array = ["ogg", "mp3", "wav"]


static func load_stream(path: String) -> AudioStream:
	var p := path.strip_edges()
	if p.is_empty():
		return null
	var ext := p.get_extension().to_lower()
	if not SUPPORTED.has(ext):
		push_warning("RhythmChartAudio: 只支持 ogg / mp3 / wav，收到 %s" % p)
		return null

	if p.begins_with("res://") or p.begins_with("user://"):
		if ResourceLoader.exists(p):
			var res := ResourceLoader.load(p)
			if res is AudioStream:
				return res
		return _load_external(ProjectSettings.globalize_path(p), ext)

	return _load_external(p, ext)


static func _load_external(abs_path: String, ext: String) -> AudioStream:
	if not FileAccess.file_exists(abs_path):
		return null
	var stream: AudioStream = null
	match ext:
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(abs_path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(abs_path)
		"wav":
			stream = AudioStreamWAV.load_from_file(abs_path)
	return stream


static func get_length(stream: AudioStream) -> float:
	if stream == null:
		return 0.0
	return stream.get_length()


## 给 FileDialog 用的过滤器字符串。
static func dialog_filters() -> PackedStringArray:
	return PackedStringArray(["*.ogg, *.mp3, *.wav ; 音频文件"])
