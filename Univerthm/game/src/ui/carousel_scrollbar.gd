class_name CarouselScrollbar
extends Control
## 书脊横排下面那条细滚动条：一条轨道 + 一个可拖的滑块。
## 只负责「显示滚到哪」和「把拖动变成滚动命令」，真正的滑动还是 SpineCarousel 干的。
## 内容装得下（没有溢出）时自己隐身。

const TRACK_IDLE := Color(0.76, 0.68, 1.0, 0.16)
const TRACK_HOT := Color(0.8, 0.72, 1.0, 0.3)
const THUMB_IDLE := Color(0.72, 0.51, 1.0, 0.72)
const THUMB_HOT := Color(0.86, 0.72, 1.0, 0.95)
const TRACK_HEIGHT := 2.0
const THUMB_HEIGHT := 6.0

## 拖的就是这条横排（在 chapter_select 里连上）
@export var carousel: SpineCarousel

var _hovering := false
var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(on: bool) -> void:
	_hovering = on
	queue_redraw()


func _process(_delta: float) -> void:
	if carousel == null:
		return
	var needed := carousel.overflows()
	if visible != needed:
		visible = needed
	queue_redraw()


func _draw() -> void:
	if carousel == null:
		return
	var mid := size.y * 0.5
	_pill(Rect2(0.0, mid - TRACK_HEIGHT * 0.5, size.x, TRACK_HEIGHT), TRACK_HOT if _hovering else TRACK_IDLE)
	var view := clampf(carousel.view_ratio(), 0.0, 1.0)
	if view >= 1.0:
		return
	var length := maxf(8.0, size.x * view)
	var x := clampf(carousel.scroll_progress(), 0.0, 1.0) * maxf(0.0, size.x - length)
	_pill(Rect2(x, mid - THUMB_HEIGHT * 0.5, length, THUMB_HEIGHT), THUMB_HOT if (_hovering or _dragging) else THUMB_IDLE)


## 圆头小条：中间一个矩形 + 两头各一个圆
func _pill(rect: Rect2, color: Color) -> void:
	var radius := rect.size.y * 0.5
	draw_rect(Rect2(rect.position.x + radius, rect.position.y, maxf(0.0, rect.size.x - radius * 2.0), rect.size.y), color)
	draw_circle(Vector2(rect.position.x + radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.position.x + rect.size.x - radius, rect.position.y + radius), radius, color)


func _gui_input(event: InputEvent) -> void:
	if carousel == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_drag_to(event.position.x)
		queue_redraw()
		accept_event()
		return
	if event is InputEventMouseMotion and _dragging:
		_drag_to(event.position.x)
		accept_event()


## 拖到哪个 x：滑块的中间跟着鼠标走
func _drag_to(x: float) -> void:
	if carousel == null:
		return
	var view := clampf(carousel.view_ratio(), 0.0, 1.0)
	var length := maxf(8.0, size.x * view)
	var span := maxf(1.0, size.x - length)
	carousel.scroll_to_progress(clampf((x - length * 0.5) / span, 0.0, 1.0))
