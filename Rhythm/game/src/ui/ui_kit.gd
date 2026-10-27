class_name UiKit
extends RefCounted
## 一堆建控件的小函数，界面代码能短一点。
## 界面都是代码搭的（这样换皮只要改 Palette / UiTheme / 这里），
## 想改成编辑器场景也可以照这些结构手工摆。

const PAD := 18


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	return c


static func label(text: String, size := 16, color := Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func mono_label(text: String, size := 16, color := Palette.TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", UiTheme.mono())
	return l


static func button(text: String, size := 16, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if variation != "":
		b.theme_type_variation = variation
	return b


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func margin(child: Control, left := 0, top := 0, right := 0, bottom := 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_child(child)
	return m


static func gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 横向占位
static func stretch() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 纵向占位（把下面的内容顶到底部）
static func stretch_v() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func panel(bg := Palette.PANEL, radius := 10, border_w := 1,
		border_color := Palette.LINE, padding := Vector4(18, 16, 18, 16)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.style_box(bg, radius, border_w, border_color, padding))
	return p


static func flat_panel(bg: Color, radius := 8, padding := Vector4(10, 6, 10, 6)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.style_box(bg, radius, 0, Color(0, 0, 0, 0), padding))
	return p


static func chip(text: String, color: Color, size := 13) -> PanelContainer:
	var p := flat_panel(Palette.alpha(color, 0.16), 5, Vector4(8, 3, 8, 3))
	var l := label(text, size, color)
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


static func rule(color := Palette.LINE_SOFT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.style_box(color, 0, 0, Color(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
	p.custom_minimum_size = Vector2(0, 1)
	return p


## 「名 值 ◀ ▶」一行，用在设置界面。
## 返回 { "row": HBoxContainer, "value": Label }，value 里的文字由调用方刷新。
static func stepper(row_label: String, on_step: Callable, min_width := 210) -> Dictionary:
	var h := hbox(8)
	var name_label := label(row_label, 14, Palette.DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_label)

	var value_box := PanelContainer.new()
	value_box.add_theme_stylebox_override("panel",
		UiTheme.style_box(Palette.PANEL_2, 6, 1, Palette.LINE, Vector4(12, 3, 12, 3)))
	value_box.custom_minimum_size = Vector2(min_width, 28)
	var value_label := mono_label("", 14, Palette.TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_box.add_child(value_label)
	h.add_child(value_box)

	var prev := button("◀", 13, "GhostButton")
	prev.pressed.connect(func(): on_step.call(-1))
	var next := button("▶", 13, "GhostButton")
	next.pressed.connect(func(): on_step.call(1))
	h.add_child(prev)
	h.add_child(next)
	return {"row": h, "value": value_label}


static func hsep_line(width := 0) -> ColorRect:
	var r := ColorRect.new()
	r.color = Palette.LINE_SOFT
	r.custom_minimum_size = Vector2(width, 1)
	return r
