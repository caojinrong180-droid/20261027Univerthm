extends Control
## 启动画面：光敏性癫痫警告。界面节点在 scenes/warning.tscn 里（可以直接在编辑器里改字）。
## 停留 HOLD_SEC 秒后自动进主界面；中途按任意键 / 点一下可以跳过。

## 自动继续时间（秒）
const HOLD_SEC := 5.0
## 刚出现时的保护时间：这之前不响应跳过，避免误触
const SKIP_GUARD := 0.6

var _elapsed := 0.0
var _done := false

@onready var _bar: ColorRect = $Center/Column/BarHolder/Bar
@onready var _bar_holder: Control = $Center/Column/BarHolder


func _ready() -> void:
	theme = UiTheme.theme()


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var k := clampf(_elapsed / HOLD_SEC, 0.0, 1.0)
	if _bar != null and _bar_holder != null:
		_bar.size = Vector2(_bar_holder.size.x * k, _bar_holder.size.y)
	if _elapsed >= HOLD_SEC:
		_leave()


func _unhandled_input(event: InputEvent) -> void:
	if _done or _elapsed < SKIP_GUARD:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		skip = true
	elif event is InputEventMouseButton and event.pressed:
		skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_leave()


func _leave() -> void:
	if _done:
		return
	_done = true
	App.goto_menu()
