class_name MenuPointerCollapse
extends ColorRect
## 鼠标轨迹的径向坍缩。只扭曲画面，不接管 GUI 输入或移动按钮。

const MAX_POINTS := 32

@export var enabled := true
@export_range(20.0, 140.0, 1.0) var radius := 38.0
@export_range(0.0, 1.5, 0.05) var strength := 0.85
@export_range(0.2, 2.0, 0.05) var trail_lifetime := 1.15
@export_range(8.0, 40.0, 1.0) var point_spacing := 16.0

@onready var _capture: BackBufferCopy = get_node("../PointerCapture")

var _effect_material: ShaderMaterial
var _samples: Array[Vector3] = []
var _cursor := Vector2.ZERO
var _cursor_age := 9.0
var _last_sample := Vector2.ZERO
var _last_sample_valid := false
var _armed := false


func _ready() -> void:
	_effect_material = material as ShaderMaterial
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear()
	set_process_input(false)
	resized.connect(_clear)
	get_viewport().mouse_exited.connect(_on_pointer_exit)


func start() -> void:
	_armed = true
	set_process_input(enabled)


func stop() -> void:
	_armed = false
	set_process_input(false)
	_clear()


func _input(event: InputEvent) -> void:
	if not _armed or not enabled or strength <= 0.0 or not (event is InputEventMouseMotion):
		return
	var motion := make_input_local(event) as InputEventMouseMotion
	if not Rect2(Vector2.ZERO, size).has_point(motion.position):
		_on_pointer_exit()
		return
	_record_motion(motion.position)


func _record_motion(point: Vector2) -> void:
	_cursor = point
	_cursor_age = 0.0
	if not _last_sample_valid:
		_add_sample(point)
		_last_sample = point
		_last_sample_valid = true
	else:
		var distance := point.distance_to(_last_sample)
		if distance >= point_spacing:
			var spacing := maxf(point_spacing, 1.0)
			var steps := int(floor(distance / spacing))
			var direction := (point - _last_sample) / distance
			# 固定距离取样，避免高频输入把有限的尾迹点挤在鼠标附近。
			for i in range(maxi(1, steps - MAX_POINTS + 2), steps + 1):
				_add_sample(_last_sample + direction * (i * spacing))
			_last_sample += direction * (steps * spacing)
	set_process(true)


func _add_sample(point: Vector2) -> void:
	_samples.append(Vector3(point.x, point.y, 0.0))
	while _samples.size() > MAX_POINTS - 1:
		_samples.pop_front()


func _process(delta: float) -> void:
	if not enabled or strength <= 0.0 or _effect_material == null:
		_clear()
		return
	_cursor_age += delta
	for i in range(_samples.size() - 1, -1, -1):
		_samples[i].z += delta
		if _samples[i].z >= trail_lifetime:
			_samples.remove_at(i)
	if _cursor_age >= trail_lifetime and _samples.is_empty():
		_clear()
		return
	_upload_trail()


func _upload_trail() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		_clear()
		return
	var points := PackedVector4Array()
	points.resize(MAX_POINTS)
	var count := 0
	var bounds := Rect2(_cursor, Vector2.ZERO)
	if _cursor_age < trail_lifetime:
		var age := _cursor_age / trail_lifetime
		points[count] = Vector4(_cursor.x / size.x, _cursor.y / size.y, age, maxf(0.08, pow(1.0 - age, 1.1)))
		count += 1
	var previous := _cursor
	var full_distance := 0.0
	for i in range(_samples.size() - 1, -1, -1):
		var point := Vector2(_samples[i].x, _samples[i].y)
		full_distance += point.distance_to(previous)
		previous = point
	previous = _cursor
	var trail_distance := 0.0
	for i in range(_samples.size() - 1, -1, -1):
		if count >= MAX_POINTS:
			break
		var point := Vector2(_samples[i].x, _samples[i].y)
		trail_distance += point.distance_to(previous)
		previous = point
		var age := _samples[i].z / trail_lifetime
		# 按沿途距离和存留时间共同收细：快速划过时也有清楚的尖尾。
		var taper := clampf(maxf(age, trail_distance / maxf(full_distance, radius)), 0.0, 1.0)
		var width := lerpf(0.08, 0.94, pow(1.0 - taper, 1.25))
		points[count] = Vector4(point.x / size.x, point.y / size.y, age, width)
		bounds = bounds.expand(point)
		count += 1
	_effect_material.set_shader_parameter("viewport_size", size)
	_effect_material.set_shader_parameter("trail_points", points)
	_effect_material.set_shader_parameter("trail_count", count)
	_effect_material.set_shader_parameter("radius_px", radius)
	_effect_material.set_shader_parameter("strength", strength)
	var draw_bounds := bounds.grow(radius + 2.0).intersection(Rect2(Vector2.ZERO, size))
	_effect_material.set_shader_parameter("effect_bounds", Vector4(draw_bounds.position.x, draw_bounds.position.y, draw_bounds.size.x, draw_bounds.size.y))
	_capture.rect = bounds.grow(radius * 1.8 + 12.0).intersection(Rect2(Vector2.ZERO, size))
	_capture.copy_mode = BackBufferCopy.COPY_MODE_RECT
	visible = true


func _on_pointer_exit() -> void:
	_last_sample_valid = false


func _clear() -> void:
	_samples.clear()
	_cursor_age = 9.0
	_last_sample_valid = false
	visible = false
	if is_instance_valid(_capture):
		_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	if _effect_material != null:
		_effect_material.set_shader_parameter("trail_count", 0)
	set_process(false)
