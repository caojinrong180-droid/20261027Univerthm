class_name SpineCarousel
extends Control
## 章节选择的书脊横排：滚轮左右滑，滑到头只能多走一点点，松手橡皮筋回拉。

@export var separation := 0.0
## 滚一格滚轮走多远
@export var wheel_step := 96.0
## 到头之后还能拖出去多少（占一格的比例 / 像素上限）
@export var overshoot_ratio := 0.4
@export var overshoot_limit := 88.0
## 回弹和目标跟随的手感
@export var spring := 16.0
@export var bounce := 9.0

var _offset := 0.0
var _target := 0.0
var _overshoot := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_layout_now)
	_layout_now()
	set_process(true)


func _process(delta: float) -> void:
	var step := minf(1.0, delta * spring)
	var fall := minf(1.0, delta * bounce)
	if absf(_overshoot) < 0.05:
		_overshoot = 0.0
	else:
		_overshoot = lerpf(_overshoot, 0.0, fall)
	_target = clampf(_target, 0.0, _max_scroll())
	if absf(_offset - _target) < 0.05:
		_offset = _target
	else:
		_offset = lerpf(_offset, _target, step)
	_layout_now()


## 当前能滑多远（内容比可视区窄就是 0）
func _max_scroll() -> float:
	return maxf(0.0, _content_width() - size.x)


## 内容撑出去了没（给下面的滚动条判断要不要显身）
func overflows() -> bool:
	return _max_scroll() > 0.5


## 可视区占内容的比例（0~1）：滚动条滑块该多长
func view_ratio() -> float:
	var total := _content_width()
	if total <= 0.0:
		return 1.0
	return clampf(size.x / total, 0.0, 1.0)


## 现在滚到哪（0~1）
func scroll_progress() -> float:
	var reach := _max_scroll()
	if reach <= 0.0:
		return 0.0
	return clampf(_target / reach, 0.0, 1.0)


## 拖滚动条：直接给目标进度
func scroll_to_progress(ratio: float) -> void:
	_target = clampf(ratio, 0.0, 1.0) * _max_scroll()
	_overshoot = 0.0


func _content_width() -> float:
	var cards := _spines()
	if cards.is_empty():
		return 0.0
	var total := 0.0
	for card in cards:
		total += card.custom_minimum_size.x
	return total + separation * float(cards.size() - 1)


func _spines() -> Array:
	var out := []
	for child in get_children():
		if child is Control and child.visible:
			out.append(child)
	return out


## 把第 index 本滑进可视区：书比屏幕多的时候，键盘 / 悬停选到画面外那本要能滑出来。
func ensure_visible(index: int) -> void:
	var cards := _spines()
	if index < 0 or index >= cards.size():
		return
	# 进场景那一帧容器还没排好（size.x == 0），这时候按「可视区 0 宽」算会把整排推到老右，
	# 所以尺寸没量出来就直接不动——默认停在最左边。
	if size.x <= 0.0:
		return
	var left := 0.0
	for i in index:
		left += (cards[i] as Control).custom_minimum_size.x + separation
	var right := left + (cards[index] as Control).custom_minimum_size.x
	if left < _target:
		_target = left
	elif right > _target + size.x:
		_target = right - size.x
	_target = clampf(_target, 0.0, _max_scroll())


func _layout_now() -> void:
	var shift := _offset + _overshoot
	var x := -shift
	for card in _spines():
		var item := card as Control
		item.size = item.custom_minimum_size
		item.position = Vector2(x, (size.y - item.size.y) * 0.5)
		x += item.size.x + separation


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed:
		return
	var direction := 0.0
	match click.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			direction = -1.0
		MOUSE_BUTTON_WHEEL_DOWN:
			direction = 1.0
		_:
			return
	var next := clampf(_target + direction * wheel_step, 0.0, _max_scroll())
	if is_equal_approx(next, _target):
		# 已经滑到头：只给一小段橡皮筋，松手就拉回去
		_overshoot = clampf(_overshoot + direction * wheel_step * overshoot_ratio, -overshoot_limit, overshoot_limit)
	else:
		_target = next
		_overshoot = 0.0
	accept_event()
