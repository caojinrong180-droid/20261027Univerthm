extends Control
class_name UnlockFrames
## 解锁动画 = 谱面包里导入的那个视频（由 tools/bake_unlock.ps1 烘焙成帧序列）。

signal finished

var fps := 15.0
var duration := 0.0
var _frames: Array = []          # Array[PackedByteArray]
var _tex_cache := {}             # index -> ImageTexture（只留最近几帧）
var _cache_order: Array = []
var _const_cache_limit := 8
var _elapsed := 0.0
var _last_index := -1
var _done := false

var _rect: TextureRect = null
var _audio: AudioStreamPlayer = null
var _started := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.024, 0.035, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_rect = TextureRect.new()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## data 来自 ChartSource.load_unlock()
func setup(data: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not bool(data.get("ok", false)):
		return false
	_frames = data.get("frames", [])
	if _frames.is_empty():
		return false
	fps = maxf(1.0, float(data.get("fps", 15.0)))
	duration = float(data.get("duration", float(_frames.size()) / fps))
	if duration <= 0.05:
		duration = float(_frames.size()) / fps

	var audio_bytes: PackedByteArray = data.get("audio", PackedByteArray())
	if audio_bytes.size() > 0:
		var stream := AudioStreamOggVorbis.load_from_buffer(audio_bytes)
		if stream != null:
			_audio = AudioStreamPlayer.new()
			_audio.stream = stream
			add_child(_audio)
	return true


func start() -> void:
	_started = true
	_elapsed = 0.0
	_last_index = -1
	_done = false
	_show_frame(0)
	if _audio != null:
		_audio.play()


func skip() -> void:
	if _done:
		return
	_done = true
	if _audio != null:
		_audio.stop()
	finished.emit()


func _process(delta: float) -> void:
	if _done or not _started:
		return
	_elapsed += delta
	if _elapsed >= duration - 0.02:
		_done = true
		if _audio != null:
			_audio.stop()
		finished.emit()
		return
	var idx := int(_elapsed * fps)
	idx = clampi(idx, 0, _frames.size() - 1)
	if idx != _last_index:
		_show_frame(idx)


func _show_frame(idx: int) -> void:
	_last_index = idx
	var tex: ImageTexture = _tex_cache.get(idx, null)
	if tex == null:
		var bytes: PackedByteArray = _frames[idx]
		var img := Image.new()
		if bytes.size() > 0 and img.load_jpg_from_buffer(bytes) == OK:
			tex = ImageTexture.create_from_image(img)
			_tex_cache[idx] = tex
			_cache_order.append(idx)
			while _cache_order.size() > _const_cache_limit:
				var old = _cache_order.pop_front()
				_tex_cache.erase(old)
	if tex != null and _rect != null:
		_rect.texture = tex
