class_name TutorialOverlay
extends Control
## 新手教程弹窗：整页教程图（assets/tutorial.png）塞在滚动区里，滚轮 / ↑↓ 往下翻。
## 第一次进主界面自动弹一次（记录在 AppSettings.tutorial_seen），
## 之后在「设置 · 新手教程 · 重新查看」里随时打开（两边用的是同一个弹窗）。

signal closed

const IMAGE_PATH := "res://assets/tutorial.png"
const HINT := "以后可以在「设置 · 新手教程」里再打开。"
const SCROLL_STEP := 72.0

var _panel: NeonPanel
var _scroll: ScrollContainer
var _image: TextureRect
var _done_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(self)
	_build()
	hide()


func open() -> void:
	show()
	modulate.a = 0.0
	if _scroll != null:
		_scroll.scroll_vertical = 0
	_fit_image.call_deferred()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	if _done_button != null:
		_done_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


# --------------------------------------------------------------------------- #
# 键盘：Esc 关掉，方向键 / 翻页键滚图，浮窗开着时按键不再往下传
# --------------------------------------------------------------------------- #

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if key.keycode == KEY_F11:
		return
	get_viewport().set_input_as_handled()
	if key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		close()
		return
	_scroll_by(key.keycode)


func _scroll_by(code: int) -> void:
	if _scroll == null:
		return
	var page := int(maxf(120.0, _scroll.size.y * 0.88))
	match code:
		KEY_DOWN:
			_scroll.scroll_vertical += int(SCROLL_STEP)
		KEY_UP:
			_scroll.scroll_vertical -= int(SCROLL_STEP)
		KEY_PAGEDOWN, KEY_SPACE:
			_scroll.scroll_vertical += page
		KEY_PAGEUP:
			_scroll.scroll_vertical -= page
		KEY_HOME:
			_scroll.scroll_vertical = 0
		KEY_END:
			_scroll.scroll_vertical = int(_image.custom_minimum_size.y)


# --------------------------------------------------------------------------- #
# 界面
# --------------------------------------------------------------------------- #

func _build() -> void:
	var shade := ColorRect.new()
	shade.name = "DimShade"
	shade.color = Color(0.008, 0.004, 0.018, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(shade)
	add_child(shade)

	var centerer := CenterContainer.new()
	centerer.name = "Center"
	centerer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(centerer)
	add_child(centerer)

	_panel = NeonPanel.new()
	_panel.name = "TutorialPanel"
	_panel.fill = Color(0.028, 0.016, 0.058, 0.97)
	_panel.edge = Color("c49bff")
	_panel.cut = 26
	_panel.glow = true
	_panel.custom_minimum_size = Vector2(860, 0)
	centerer.add_child(_panel)

	var column := UiKit.vbox(8)
	_panel.add_child(UiKit.margin(column, 30, 20, 30, 18))

	var head := UiKit.hbox(12)
	column.add_child(head)
	head.add_child(NeonUi.label("新手教程", 28, NeonUi.LIGHT, true))
	head.add_child(NeonUi.label("///", 17, NeonUi.PURPLE, true))
	head.add_child(UiKit.stretch())
	head.add_child(NeonUi.label("TUTORIAL", 11, NeonUi.MUTED))
	var close_button := NeonUi.button("×", false, 17)
	close_button.name = "CloseButton"
	close_button.custom_minimum_size = Vector2(42, 32)
	close_button.pressed.connect(close)
	head.add_child(close_button)

	column.add_child(UiKit.rule(Color("8342cf")))
	var hint := NeonUi.label(HINT, 12, NeonUi.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	_scroll = ScrollContainer.new()
	_scroll.name = "TutorialScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 464)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_theme_constant_override("scroll_deadzone", 0)
	column.add_child(_scroll)
	NeonUi.style_scroll(_scroll)

	_image = TextureRect.new()
	_image.name = "TutorialImage"
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_image.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var texture = load(IMAGE_PATH)
	if texture is Texture2D:
		_image.texture = texture
	else:
		push_warning("教程图载不进来：" + IMAGE_PATH)
	_scroll.add_child(_image)
	_scroll.resized.connect(_fit_image)

	column.add_child(UiKit.rule(Color("4b2a70")))
	var actions := UiKit.hbox(12)
	column.add_child(actions)
	var tip := NeonUi.label("设置 · 新手教程 里可以再看", 11, NeonUi.MUTED)
	actions.add_child(tip)
	actions.add_child(UiKit.stretch())
	_done_button = NeonUi.button("知道了（Esc）", true, 16)
	_done_button.name = "DoneButton"
	_done_button.custom_minimum_size = Vector2(186, 44)
	_done_button.pressed.connect(close)
	actions.add_child(_done_button)


## 图撑满滚动区宽度、高度按原图比例算（不拉伸变形）
func _fit_image() -> void:
	if _image == null or _scroll == null or _image.texture == null:
		return
	var texture := _image.texture
	if texture.get_width() <= 0:
		return
	var width := maxf(200.0, _scroll.size.x - 16.0)
	var height := width * float(texture.get_height()) / float(texture.get_width())
	if absf(_image.custom_minimum_size.y - height) > 0.5:
		_image.custom_minimum_size = Vector2(width, height)
