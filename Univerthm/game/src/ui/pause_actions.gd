extends Control
## 三个动作在中心并排，采用阻尼弹簧保留滑入的惯性与回弹。

signal action_requested(action: int)
const Icon = preload("res://src/ui/action_icon.gd")
const PleaPortrait = preload("res://src/ui/plea_portrait.gd")
var buttons: Array[Button] = []
var _positions: Array[Vector2] = []
var _velocities: Array[Vector2] = []
var _elapsed := 0.0
var _pending := -1
var _pending_time := 0.0
var _shade: ColorRect
var portrait: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = ColorRect.new()
	_shade.color = Color(0.012, 0.006, 0.027, 0.76)
	UiKit.full_rect(_shade)
	add_child(_shade)
	portrait = PleaPortrait.new()
	portrait.name = "PleaPortrait"
	add_child(portrait)
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
	portrait.show_plea(App.character_index)
	_elapsed = 0.0
	_pending = -1
	_shade.modulate.a = 0.0
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
	portrait.hide_plea()
	hide()
	_pending = -1
	for button in buttons:
		button.release_focus()
	set_process(false)


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
	_shade.modulate.a = minf(1.0, _elapsed / 0.12)
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
