extends CanvasLayer
## 非游玩界面的周期故障层；主界面沿用自己带面部保护的效果。

const Glitch = preload("res://src/ui/menu_glitch.gd")
const SCREENS := [
	"res://scenes/warning.tscn", "res://scenes/splash.tscn",
	"res://scenes/song_select.tscn",
	"res://scenes/settings.tscn", "res://scenes/collection.tscn",
	"res://scenes/profile.tscn", "res://scenes/results.tscn",
	"res://scenes/gameplay.tscn",
]

var effect: Glitch
var _capture: BackBufferCopy
var _running := false


func _ready() -> void:
	layer = 10
	_capture = BackBufferCopy.new()
	_capture.name = "ScreenCapture"
	_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_capture)
	effect = Glitch.new()
	effect.name = "AmbientGlitch"
	effect.protected_art = NodePath()
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/menu_local_glitch.gdshader")
	shader_material.set_shader_parameter("protected_rect", Vector4.ZERO)
	effect.material = shader_material
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effect.visibility_changed.connect(_sync_capture)
	add_child(effect)
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed.call_deferred()


func _on_scene_changed() -> void:
	_set_running(false)
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path not in SCREENS:
		return
	scene.tree_exiting.connect(_on_scene_exit, CONNECT_ONE_SHOT)
	if scene.has_signal("state_changed"):
		scene.connect("state_changed", _sync_state)
	_sync_state()


func _sync_state() -> void:
	var scene := get_tree().current_scene
	var allowed := scene != null and scene.scene_file_path in SCREENS
	if allowed and scene.has_method("is_chart_playing"):
		allowed = not scene.is_chart_playing()
	_set_running(allowed)


func _set_running(running: bool) -> void:
	if _running == running:
		return
	_running = running
	if running:
		effect.start()
	else:
		effect.stop()


func _on_scene_exit() -> void:
	_set_running(false)


func _sync_capture() -> void:
	# 显式复制当前界面（含暂停层），空闲和打歌时完全停止复制。
	_capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if effect.visible else BackBufferCopy.COPY_MODE_DISABLED
