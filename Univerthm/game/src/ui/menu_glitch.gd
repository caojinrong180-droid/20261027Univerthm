class_name MenuGlitch
extends ColorRect
## 间歇性局部图像故障。主界面位于立绘之后、UI 之前，其它界面复用到顶层。

signal burst_started(region: Rect2)
signal burst_finished

@export var enabled := true
@export_range(0.0, 2.0, 0.05) var strength := 1.0
@export_range(0.8, 10.0, 0.1) var min_interval := 2.4
@export_range(0.8, 12.0, 0.1) var max_interval := 5.2
@export_range(0.08, 0.5, 0.01) var burst_duration := 0.22
@export_node_path("Control") var protected_art := NodePath("../Banner")

const ZONES := [
	Rect2(0.02, 0.10, 0.46, 0.19), Rect2(0.03, 0.55, 0.50, 0.30),
	Rect2(0.52, 0.41, 0.44, 0.30), Rect2(0.37, 0.16, 0.58, 0.32),
]

var _rng := RandomNumberGenerator.new()
var _active := false
var _wait_remaining := 0.0
var _burst_elapsed := 0.0
var _current_duration := 0.22
var _effect_material: ShaderMaterial
var _art: Control


func _ready() -> void:
	_effect_material = material as ShaderMaterial
	if not protected_art.is_empty():
		_art = get_node_or_null(protected_art) as Control
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


func start() -> void:
	if not enabled or _effect_material == null:
		return
	_active = false
	visible = false
	_wait_remaining = _random_gap() * 0.65
	set_process(true)


func stop() -> void:
	_active = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not enabled or strength <= 0.0:
		_active = false
		visible = false
		return
	if _active:
		_burst_elapsed += delta
		var phase := clampf(_burst_elapsed / _current_duration, 0.0, 1.0)
		_effect_material.set_shader_parameter("burst_phase", phase)
		_update_face_mask()
		if phase >= 1.0:
			_active = false
			visible = false
			_wait_remaining = _random_gap()
			burst_finished.emit()
	else:
		_wait_remaining -= delta
		if _wait_remaining <= 0.0:
			_begin_burst()


func _random_gap() -> float:
	return _rng.randf_range(maxf(0.8, minf(min_interval, max_interval)), maxf(0.8, maxf(min_interval, max_interval)))


func _pick_region(zone_index: int, extent_scale := 1.0) -> Rect2:
	var zone: Rect2 = ZONES[zone_index]
	var extent := Vector2(_rng.randf_range(0.16, 0.31), _rng.randf_range(0.035, 0.09)) * extent_scale
	var origin := zone.position + Vector2(_rng.randf(), _rng.randf()) * (zone.size - extent)
	return Rect2(origin, extent)


func _begin_burst() -> void:
	var zone := _rng.randi_range(0, ZONES.size() - 1)
	var a := _pick_region(zone)
	var b := _pick_region((zone + _rng.randi_range(1, ZONES.size() - 1)) % ZONES.size(), 0.65)
	_current_duration = burst_duration * _rng.randf_range(0.72, 1.18)
	_burst_elapsed = 0.0
	_effect_material.set_shader_parameter("region_a", Vector4(a.position.x, a.position.y, a.size.x, a.size.y))
	_effect_material.set_shader_parameter("region_b", Vector4(b.position.x, b.position.y, b.size.x, b.size.y))
	_effect_material.set_shader_parameter("burst_seed", _rng.randf_range(0.0, 512.0))
	_effect_material.set_shader_parameter("strength", strength)
	_effect_material.set_shader_parameter("burst_phase", 0.0)
	_update_face_mask()
	_active = true
	visible = true
	burst_started.emit(a)


func _update_face_mask() -> void:
	if not is_instance_valid(_art) or size.x <= 0.0 or size.y <= 0.0:
		return
	var transform := get_global_transform().affine_inverse() * _art.get_global_transform()
	var top_left := transform * (_art.size * Vector2(0.27, 0.0))
	var bottom_right := transform * (_art.size * Vector2(0.76, 0.30))
	var face := Rect2(top_left, bottom_right - top_left).abs().grow(5.0)
	_effect_material.set_shader_parameter("protected_rect", Vector4(face.position.x / size.x, face.position.y / size.y, face.size.x / size.x, face.size.y / size.y))
