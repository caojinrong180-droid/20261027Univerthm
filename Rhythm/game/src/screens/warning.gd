extends Control
## 启动画面：光敏性癫痫警告。
## 停留 HOLD_SEC 秒后自动进入开始界面；中途按任意键 / 点一下可以跳过。

## 自动继续时间（秒）
const HOLD_SEC := 5.0
## 刚出现时的保护时间：这之前不响应跳过，避免误触
const SKIP_GUARD := 0.6
const TEXT_WIDTH := 660.0

var _elapsed := 0.0
var _bar: ColorRect
var _bar_holder: Control
var _done := false


func _ready() -> void:
	theme = UiTheme.theme()
	_build()


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var k := clampf(_elapsed / HOLD_SEC, 0.0, 1.0)
	if _bar != null and _bar_holder != null:
		_bar.size = Vector2(_bar_holder.size.x * k, _bar_holder.size.y)
		_bar_holder.queue_redraw()
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


# --------------------------------------------------------------------------- #
# 界面
# --------------------------------------------------------------------------- #

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG_DEEP
	UiKit.full_rect(bg)
	add_child(bg)

	# 顶部一条极细的强调线（和主界面同一种语言）
	var top := ColorRect.new()
	top.color = Palette.alpha(Palette.ACCENT, 0.5)
	top.anchor_right = 1.0
	top.offset_bottom = 2.0
	add_child(top)

	var center := CenterContainer.new()
	UiKit.full_rect(center)
	add_child(center)

	var column := UiKit.vbox(0)
	column.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	center.add_child(column)

	var tag := UiKit.mono_label("PHOTOSENSITIVITY WARNING", 12, Palette.DIM_2)
	column.add_child(tag)
	column.add_child(UiKit.gap(10))

	var title := UiKit.label("光敏性癫痫警告", 34, Palette.TEXT)
	column.add_child(title)
	column.add_child(UiKit.gap(18))

	var rule := ColorRect.new()
	rule.color = Palette.alpha(Palette.WARN, 0.8)
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(rule)
	column.add_child(UiKit.gap(18))

	for line in [
		"本游戏包含快速闪烁的画面、强烈的色彩变化和密集的判定特效。",
		"如果你或你的家人有光敏性癫痫或其他光敏病史，请在医生建议下游玩。",
		"游玩过程中若出现头晕、视觉异常、肌肉抽搐等不适，请立即停止游戏并就医。",
	]:
		var body := UiKit.label(line, 15, Palette.DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
		column.add_child(body)
		column.add_child(UiKit.gap(6))

	column.add_child(UiKit.gap(26))

	# 进度条（自己画，好控制粗细）
	_bar_holder = Control.new()
	_bar_holder.custom_minimum_size = Vector2(TEXT_WIDTH, 2)
	_bar_holder.size_flags_horizontal = Control.SIZE_FILL
	column.add_child(_bar_holder)

	var bar_bg := ColorRect.new()
	bar_bg.color = Palette.alpha(Palette.LINE, 0.9)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_holder.add_child(bar_bg)

	_bar = ColorRect.new()
	_bar.color = Palette.ACCENT
	_bar.size = Vector2(0, 2)
	_bar_holder.add_child(_bar)

	column.add_child(UiKit.gap(12))

	var hint := UiKit.mono_label("点击任意处或按任意键继续", 12, Palette.DIM_2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(hint)
