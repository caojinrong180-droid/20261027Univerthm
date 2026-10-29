extends TextureRect
## 主界面退出确认时的求情立绘。位置由阻尼弹簧驱动，从角色对应的侧边入场。

const STRA_PLEA := preload("res://assets/banners/stra5.png")
const KISAI_PLEA := preload("res://assets/banners/Kisai5.png")
const STIFFNESS := 380.0
const DAMPING := 23.0

var character_index := 0
var _target_x := 0.0
var _x := 0.0
var _velocity := 0.0
var _opacity := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hide()
	set_process(false)


func show_plea(index: int) -> void:
	character_index = clampi(index, 0, 1)
	texture = KISAI_PLEA if character_index == 1 else STRA_PLEA
	_layout()
	_x = -size.x - 52.0 if character_index == 1 else get_parent().size.x + 52.0
	_velocity = 0.0
	_opacity = 0.0
	position.x = _x
	modulate.a = 0.0
	show()
	set_process(true)


func hide_plea() -> void:
	hide()
	set_process(false)


func _layout() -> void:
	var area: Vector2 = get_parent().size
	var height := minf(area.y * 0.95, 760.0)
	var ratio := float(texture.get_width()) / float(texture.get_height())
	size = Vector2(height * ratio, height)
	position.y = (area.y - height) * 0.5
	_target_x = 18.0 if character_index == 1 else area.x - size.x - 18.0


func _process(delta: float) -> void:
	_layout()
	var remaining := minf(delta, 0.1)
	while remaining > 0.0:
		var dt := minf(remaining, 0.008)
		_velocity += ((_target_x - _x) * STIFFNESS - _velocity * DAMPING) * dt
		_x += _velocity * dt
		remaining -= dt
	position.x = _x
	_opacity = minf(1.0, _opacity + delta * 4.8)
	modulate.a = _opacity
