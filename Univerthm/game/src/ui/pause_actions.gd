extends Control
## 三个动作在中心并排，采用阻尼弹簧保留滑入的惯性与回弹。

signal action_requested(action: int)

const Icon = preload("res://src/ui/action_icon.gd")
const ACRYLIC_SHADER = preload("res://shaders/pause_acrylic.gdshader")

var buttons: Array[Button] = []
var acrylic: ColorRect
var _positions: Array[Vector2] = []
var _velocities: Array[Vector2] = []
var _elapsed := 0.0
var _pending := -1
var _pending_time := 0.0
var _capture: BackBufferCopy
var _material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 复制必须在板块之前：兼容渲染器里 screen_tex 只拿得到「已经画完」的东西。
	_capture = BackBufferCopy.new()
	_capture.name = "ScreenCapture"
	_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_capture)
	visibility_changed.connect(_sync_capture)
	_material = ShaderMaterial.new()
	_material.shader = ACRYLIC_SHADER
	acrylic = ColorRect.new()
	acrylic.name = "AcrylicBoard"
	acrylic.material = _material
	acrylic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(acrylic)
	add_child(acrylic)
	for i in 3:
		var button := Icon.new()
		button.kind = i
		button.name = ["ResumeButton", "RetryButton", "BackButton"][i]
		button.size = Vector2(152, 140)
		button.pressed.connect(_activate.bind(i))
		add_child(button)
		buttons.append(button)
		_positions.append(Vector2.ZERO)
		_velocities.append(Vector2.ZERO)
	hide()
	set_process(false)


func open() -> void:
	show()
	_sync_capture()
	_elapsed = 0.0
	_pending = -1
	acrylic.modulate.a = 0.0
	var width := minf(152.0, size.x * 0.2)
	for i in 3:
		buttons[i].size = Vector2(width, width * 0.92)
		_positions[i] = _target(i) + Vector2(-size.x * 0.72 - i * 55, 45)
		_velocities[i] = Vector2(900, -70)
		buttons[i].position = _positions[i]
		buttons[i].modulate.a = 0.0
		buttons[i].disabled = false
	buttons[0].grab_focus()
	set_process(true)


func close() -> void:
	hide()
	_pending = -1
	for button in buttons:
		button.release_focus()
	set_process(false)


## 只在板子真的露出来的时候复制屏幕，收起后彻底不碰渲染管线。
func _sync_capture() -> void:
	_capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if visible else BackBufferCopy.COPY_MODE_DISABLED


func _target(index: int) -> Vector2:
	var width := buttons[index].size.x
	var gap := minf(32, size.x * 0.035)
	return size * 0.5 + Vector2((index - 1) * (width + gap), 0) - buttons[index].size * 0.5


func _activate(index: int) -> void:
	if _pending != -1:
		return
	_pending = index
	_pending_time = 0.1
	buttons[index]._scale_velocity = -5.0


func _process(delta: float) -> void:
	_elapsed += delta
	acrylic.modulate.a = minf(1.0, _elapsed / 0.12)
	for i in 3:
		if _elapsed < i * 0.035:
			continue
		buttons[i].modulate.a = minf(1.0, (_elapsed - i * 0.035) / 0.1)
		var left := minf(delta, 0.1)
		while left > 0:
			var dt := minf(left, 0.008)
			_velocities[i] += ((_target(i) - _positions[i]) * 390.0 - _velocities[i] * 25.0) * dt
			_positions[i] += _velocities[i] * dt
			left -= dt
		buttons[i].position = _positions[i]
	if _pending >= 0:
		_pending_time -= delta
		if _pending_time <= 0:
			var action := _pending
			_pending = -1
			action_requested.emit(action)
