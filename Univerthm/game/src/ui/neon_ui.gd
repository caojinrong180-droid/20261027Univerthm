class_name NeonUi
extends RefCounted
## 收藏与档案共用的宇宙主题；不改变其他界面的全局配色。

const Frame = preload("res://src/ui/neon_panel.gd")
const Action = preload("res://src/ui/neon_button.gd")
const PURPLE := Color("a869ff")
const LIGHT := Color("f5f0ff")
const MUTED := Color("b2a7c9")
const DARK := Color(0.025, 0.02, 0.055, 0.92)
static var _bold: SystemFont


static func bold() -> Font:
	if _bold == null:
		_bold = SystemFont.new()
		_bold.font_names = PackedStringArray(["Bahnschrift", "Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
		_bold.font_weight = 800
	return _bold


static func label(text: String, font_size := 16, color := LIGHT, heavy := false) -> Label:
	var l := UiKit.label(text, font_size, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if heavy:
		l.add_theme_font_override("font", bold())
	return l


static func panel(padding := Vector4(24, 20, 24, 20)) -> NeonPanel:
	var p := Frame.new()
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = padding.x
	sb.content_margin_top = padding.y
	sb.content_margin_right = padding.z
	sb.content_margin_bottom = padding.w
	p.add_theme_stylebox_override("panel", sb)
	return p


static func button(text: String, primary := false, font_size := 17) -> Button:
	var b := Action.new()
	b.primary = primary
	b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(110, 40)
	b.add_theme_font_override("font", bold())
	b.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, LIGHT)
	var frame := Frame.new()
	frame.name = "ButtonFrame"
	frame.slanted = true
	frame.cut = 14
	frame.fill = Color("5416c5") if primary else DARK
	frame.edge = Color("cdadff") if primary else Color("75608e")
	frame.glow = primary
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.show_behind_parent = true
	UiKit.full_rect(frame)
	b.add_child(frame)
	return b


static func background(root: Control) -> void:
	var bg := TextureRect.new()
	bg.name = "SpaceBackground"
	bg.texture = preload("res://assets/menu_black_hole.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(bg)
	root.add_child(bg)
	var shade := ColorRect.new()
	shade.name = "BackgroundShade"
	shade.color = Color(0.015, 0.005, 0.035, 0.2)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(shade)
	root.add_child(shade)


static func topbar(root: Control, title: String) -> void:
	var bar := panel(Vector4(30, 3, 16, 3))
	bar.name = "TopBar"
	bar.cut = 18
	bar.fill = Color(0.015, 0.01, 0.035, 0.82)
	bar.anchor_right = 1
	bar.offset_left = 10
	bar.offset_right = -10
	bar.offset_top = -4
	bar.offset_bottom = 54
	root.add_child(bar)
	var row := UiKit.hbox(18)
	bar.add_child(row)
	var logo := label("Univerthm", 31, LIGHT, true)
	var italic := SystemFont.new()
	italic.font_names = PackedStringArray(["Arial", "sans-serif"])
	italic.font_weight = 900
	italic.font_italic = true
	logo.add_theme_font_override("font", italic)
	row.add_child(logo)
	var badge := panel(Vector4(18, 3, 18, 3))
	badge.slanted = true
	badge.cut = 12
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(label(title, 16, LIGHT, true))
	row.add_child(badge)
	row.add_child(UiKit.stretch())
	var back := button("← 返回", false, 17)
	back.name = "BackButton"
	row.add_child(back)


static func footer(root: Control, hint: String, right_text: String) -> void:
	var bar := panel(Vector4(26, 5, 26, 5))
	bar.name = "StatusBar"
	bar.cut = 12
	bar.anchor_right = 1
	bar.anchor_top = 1
	bar.anchor_bottom = 1
	bar.offset_left = 10
	bar.offset_right = -10
	bar.offset_top = -43
	bar.offset_bottom = -10
	root.add_child(bar)
	var row := UiKit.hbox(12)
	bar.add_child(row)
	row.add_child(label("▰", 17, PURPLE))
	row.add_child(label(hint, 12, MUTED))
	row.add_child(label("///", 16, PURPLE, true))
	row.add_child(UiKit.stretch())
	var right := label(right_text, 12, MUTED)
	right.name = "FooterInfo"
	row.add_child(right)


static func content(root: Control) -> NeonPanel:
	var p := panel(Vector4(32, 18, 32, 20))
	p.name = "ContentPanel"
	p.cut = 30
	p.glow = true
	p.anchor_left = 0.075
	p.anchor_right = 0.925
	p.anchor_bottom = 1
	p.offset_top = 94
	p.offset_bottom = -84
	root.add_child(p)
	return p


static func heading(title: String, english: String, subtitle: String) -> Control:
	var box := UiKit.vbox(0)
	var row := UiKit.hbox(14)
	box.add_child(row)
	row.add_child(label(title, 52, LIGHT, true))
	row.add_child(label("///", 30, PURPLE, true))
	row.add_child(UiKit.stretch())
	var en := label(english, 12, MUTED)
	en.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(en)
	var line := UiKit.rule(Color("8342cf"))
	box.add_child(line)
	box.add_child(UiKit.gap(5))
	box.add_child(label(subtitle, 14, MUTED))
	return box


static func section(title: String, note := "") -> Control:
	var row := UiKit.hbox(12)
	var badge := panel(Vector4(18, 2, 24, 2))
	badge.slanted = true
	badge.cut = 12
	badge.fill = Color("481b88")
	badge.add_child(label(title, 16, LIGHT, true))
	row.add_child(badge)
	var line := UiKit.rule(Color("76509b"))
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	if note != "":
		row.add_child(label(note, 11, MUTED))
	return row


static func style_scroll(scroll: ScrollContainer) -> void:
	# 为滚动轨道留出实际宽度，使多行藏品和窄屏档案可见、可拖动。
	var bar := scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", UiTheme.style_box(Color(0.06, 0.035, 0.1, 0.7), 0, 0, Color.TRANSPARENT, Vector4(3, 0, 3, 0)))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, UiTheme.style_box(PURPLE if state != "grabber" else Color("674393"), 0, 0, Color.TRANSPARENT, Vector4(3, 12, 3, 12)))
