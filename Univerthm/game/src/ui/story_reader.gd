extends Control
class_name StoryReader
## 剧情阅读浮层。选曲地图上点「剧情收藏品」时直接在原地读，不用跳去收藏品界面。
##
## 结构：背景虚化（BackBufferCopy + 亚克力 shader，抄下地图再磨砂压暗）+ 一块切角面板
## （标签 / 标题 / 一行信息 / 可滚动正文）+ 关闭按钮。
## 出现时面板带一点缩放淡入的缓动（TRANS_BACK 收尾），背景同步化开。
##
## 正文块和收藏品界面同一套：`StorySource.read_story()` 给出的 blocks（章节 / 分隔线 / 段落）。
## Esc、关闭按钮、点背景，三个关法。

signal closed

const ACRYLIC_SHADER = preload("res://shaders/pause_acrylic.gdshader")
## 出现 / 收起的时长（秒）：面板缩放淡入、背景化开各一份
const IN_TIME := 0.28
const OUT_TIME := 0.16
## 出现时面板从多大开始放大（1.0 = 不缩放）
const IN_SCALE := 0.93
## 出现时面板从下面多少像素滑上来（收起时反向往上飘一点）
const IN_SLIDE := 24.0
## 面板的基准上下边距（滑入动画要在它基础上加减）
const CARD_TOP := 34.0
const CARD_BOTTOM := -34.0

const BODY_COLOR := Color(0.86, 0.84, 0.92, 1)
const HINT_COLOR := Color(0.72, 0.68, 0.8, 1)

var _capture: BackBufferCopy
var _blur: ColorRect
var _card: NeonPanel
var _kind: Label
var _title: Label
var _meta: Label
var _hint: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _close: Button
var _tween: Tween
var _closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(self)

	# 背景虚化：先抄画面，再用亚克力 shader 磨砂 + 压暗（和暂停那块板同一个 shader）
	_capture = BackBufferCopy.new()
	_capture.name = "ScreenCapture"
	_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_capture)
	_blur = ColorRect.new()
	_blur.name = "BlurBackdrop"
	var material := ShaderMaterial.new()
	material.shader = ACRYLIC_SHADER
	material.set_shader_parameter("blur_px", 9.0)
	material.set_shader_parameter("dim", 0.38)
	material.set_shader_parameter("frost", 0.42)
	material.set_shader_parameter("grain", 0.0)
	material.set_shader_parameter("sheen", 0.0)
	material.set_shader_parameter("rim", 0.0)
	material.set_shader_parameter("lift", 0.04)
	material.set_shader_parameter("tint", Color(0.3, 0.22, 0.48, 1.0))
	_blur.material = material
	_blur.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(_blur)
	_blur.gui_input.connect(_on_backdrop_input)
	add_child(_blur)
	visibility_changed.connect(_sync_capture)

	_card = NeonUi.panel(Vector4(34, 22, 34, 22))
	_card.name = "ReaderCard"
	_card.glow = true
	_card.anchor_left = 0.21
	_card.anchor_right = 0.79
	_card.anchor_bottom = 1.0
	_card.offset_top = CARD_TOP
	_card.offset_bottom = CARD_BOTTOM
	add_child(_card)

	var box := UiKit.vbox(8)
	_card.add_child(box)

	var top := UiKit.hbox(10)
	box.add_child(top)
	_kind = NeonUi.label("剧情阅览 / STORY", 13, NeonUi.PURPLE)
	_kind.name = "ReaderKind"
	top.add_child(_kind)
	top.add_child(UiKit.stretch())
	_close = NeonUi.button("× 关闭", false, 13)
	_close.name = "ReaderClose"
	_close.custom_minimum_size = Vector2(96, 32)
	_close.pressed.connect(close)
	top.add_child(_close)

	_title = NeonUi.label("", 24, NeonUi.LIGHT, true)
	_title.name = "ReaderTitle"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)

	_meta = NeonUi.label("", 12, NeonUi.MUTED)
	_meta.name = "ReaderMeta"
	_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_meta)

	box.add_child(UiKit.rule(Color("624480")))

	_scroll = ScrollContainer.new()
	_scroll.name = "ReaderScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 260)
	NeonUi.style_scroll(_scroll)
	box.add_child(_scroll)
	_body = UiKit.vbox(12)
	_body.name = "ReaderBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	_hint = NeonUi.label("滚轮滚动   ·   Esc 关闭", 11, HINT_COLOR)
	_hint.name = "ReaderHint"
	box.add_child(_hint)

	hide()


## 打开一篇剧情：story 来自 StorySource.scan()
func open(story: Dictionary) -> void:
	var data := StorySource.read_story(story)
	var file_name := str(story.get("file", ""))
	_title.text = str(story.get("title", file_name.get_basename()))
	if _kind != null:
		_kind.text = "文档阅览 / DOCUMENT" if str(story.get("folder", "")).begins_with("设定") \
			else "剧情阅览 / STORY"
	_meta.text = "%s   ·   %d 字   ·   约 %d 分钟" % [
		str(story.get("source", "")),
		int(story.get("chars", 0)),
		int(story.get("minutes", 1)),
	]
	_clear_body()
	if str(data.get("error", "")) != "":
		_add_notice(str(data["error"]), Color("ff9aa2"))
	elif not bool(data.get("utf8_ok", true)):
		_add_notice("这篇的编码可能不是 UTF-8，请在收藏品界面导入或另存为 UTF-8。", Color("ffd27a"))
	for block in data.get("blocks", []):
		_add_block(block)
	if _body.get_child_count() == 0:
		_add_notice("这一篇还是空的。", NeonUi.MUTED)
	_scroll.scroll_vertical = 0
	# 上一次的收起动画可能还在跑：先掐掉，否则它的结束回调会把刚打开的浮层又藏回去
	_kill_tween()
	_closing = false
	show()
	_sync_capture()
	_animate_in()
	if _close != null:
		_close.grab_focus()


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	if _close != null:
		_close.release_focus()
	_animate_out()


func is_open() -> bool:
	return visible and not _closing


## 当前读的是哪一篇（没有就返回空串）
func story_title() -> String:
	return "" if _title == null else _title.text


func body_block_count() -> int:
	return 0 if _body == null else _body.get_child_count()


# --------------------------------------------------------------------------- #
# 出现 / 收起的缓动
# --------------------------------------------------------------------------- #

func _animate_in() -> void:
	_kill_tween()
	await get_tree().process_frame
	if not visible or _closing:
		return
	# 缩放要绕面板中心：等这一帧排完版再取尺寸，不然绕的是左上角
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(IN_SCALE, IN_SCALE)
	_card.modulate.a = 0.0
	_card.offset_top = CARD_TOP + IN_SLIDE
	_card.offset_bottom = CARD_BOTTOM + IN_SLIDE
	_blur.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_card, "scale", Vector2.ONE, IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "offset_top", CARD_TOP, IN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "offset_bottom", CARD_BOTTOM, IN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "modulate:a", 1.0, 0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_blur, "modulate:a", 1.0, 0.24) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _animate_out() -> void:
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_card, "modulate:a", 0.0, OUT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(_card, "scale", Vector2(0.985, 0.985), OUT_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_card, "offset_top", CARD_TOP + IN_SLIDE * 0.45, OUT_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_card, "offset_bottom", CARD_BOTTOM + IN_SLIDE * 0.45, OUT_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_blur, "modulate:a", 0.0, OUT_TIME)
	_tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	hide()
	_card.modulate.a = 1.0
	_card.scale = Vector2.ONE
	_card.offset_top = CARD_TOP
	_card.offset_bottom = CARD_BOTTOM
	_blur.modulate.a = 1.0
	_closing = false
	closed.emit()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## 只在浮层真的露出来的时候抄屏幕，收起后彻底不碰渲染管线
func _sync_capture() -> void:
	_capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if visible else BackBufferCopy.COPY_MODE_DISABLED


# --------------------------------------------------------------------------- #
# 正文
# --------------------------------------------------------------------------- #

func _clear_body() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _add_block(block: Dictionary) -> void:
	var kind := str(block.get("kind", "text"))
	var text := str(block.get("text", ""))
	if kind == "chapter":
		var head := NeonUi.label(text, 20, NeonUi.LIGHT, true)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(head)
		_body.add_child(UiKit.rule(Color("5a3d7f")))
	elif kind == "rule":
		_body.add_child(UiKit.gap(4))
		_body.add_child(UiKit.rule(Color("3d2b57")))
		_body.add_child(UiKit.gap(4))
	elif text.strip_edges() != "":
		var para := NeonUi.label(text, 16, BODY_COLOR)
		para.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		para.add_theme_constant_override("line_spacing", 7)
		_body.add_child(para)


func _add_notice(message: String, color: Color) -> void:
	var notice := NeonUi.label(message, 15, color)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(notice)


# --------------------------------------------------------------------------- #
# 输入
# --------------------------------------------------------------------------- #

## 点背景（面板之外）关掉
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		elif key in [KEY_DOWN, KEY_UP, KEY_PAGEUP, KEY_PAGEDOWN]:
			# 键盘翻页：整页幅度，跟收藏品界面的手感一致
			get_viewport().set_input_as_handled()
			var page := int(maxf(120.0, _scroll.size.y * 0.82))
			var step := page if key in [KEY_PAGEDOWN, KEY_DOWN] else -page
			var bar := _scroll.get_v_scroll_bar()
			_scroll.scroll_vertical = clampi(_scroll.scroll_vertical + step, 0, maxi(0, int(bar.max_value - bar.page)))
