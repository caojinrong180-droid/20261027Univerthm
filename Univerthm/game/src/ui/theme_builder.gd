class_name UiTheme
extends RefCounted
## 统一主题：字体 / 按钮 / 面板 / 滚动条 / 进度条。

static var _cached: Theme = null
static var _sans_font: Font = null
static var _mono_font: Font = null


## 字体：拉丁字母优先 Bahnschrift（DIN 风，HUD / 界面都走它），中文自动回落到系统黑体
static func sans() -> Font:
	if _sans_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"Bahnschrift", "Segoe UI Variable", "Segoe UI",
			"Noto Sans SC", "Microsoft YaHei UI", "Microsoft YaHei",
			"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC",
			"WenQuanYi Micro Hei", "sans-serif",
		])
		f.font_weight = 500
		f.allow_system_fallback = true
		_sans_font = f
	return _sans_font


## 数字 / 数值：Noto Sans SC（等宽数字、0 是干净的椭圆、中文也全）
static func mono() -> Font:
	if _mono_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"Noto Sans SC", "Microsoft YaHei UI",
			"Segoe UI", "sans-serif",
		])
		f.font_weight = 500
		f.allow_system_fallback = true
		_mono_font = f
	return _mono_font


static func style_box(bg: Color, radius := 8, border_w := 0,
		border_color := Color(0, 0, 0, 0), padding := Vector4(14, 8, 14, 8)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border_color
	sb.content_margin_left = padding.x
	sb.content_margin_top = padding.y
	sb.content_margin_right = padding.z
	sb.content_margin_bottom = padding.w
	sb.anti_aliasing = true
	return sb


static func theme() -> Theme:
	if _cached == null:
		_cached = _build()
	return _cached


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = sans()
	t.default_font_size = 16

	# ---- Label ----
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_color("font_color", "DimLabel", Palette.DIM)
	t.set_font_size("font_size", "Label", 16)

	# ---- Button ----
	var btn_pad := Vector4(18, 10, 18, 10)
	t.set_color("font_color", "Button", Palette.TEXT)
	t.set_color("font_hover_color", "Button", Palette.TEXT)
	t.set_color("font_pressed_color", "Button", Palette.ACCENT)
	t.set_color("font_focus_color", "Button", Palette.TEXT)
	t.set_color("font_disabled_color", "Button", Palette.DIM_2)
	t.set_font_size("font_size", "Button", 16)
	t.set_stylebox("normal", "Button", style_box(Palette.PANEL_3, 8, 1, Palette.LINE, btn_pad))
	t.set_stylebox("hover", "Button", style_box(Color("#232a36"), 8, 1, Color("#313a4b"), btn_pad))
	t.set_stylebox("pressed", "Button", style_box(Color("#2b3340"), 8, 1, Palette.ACCENT_DIM, btn_pad))
	t.set_stylebox("disabled", "Button", style_box(Palette.alpha(Palette.PANEL_3, 0.4), 8, 1, Palette.LINE, btn_pad))
	t.set_stylebox("focus", "Button", style_box(Color(0, 0, 0, 0), 8, 1, Palette.ACCENT, btn_pad))

	# 主按钮（青色实心）
	t.set_type_variation("AccentButton", "Button")
	t.set_color("font_color", "AccentButton", Palette.BG)
	t.set_color("font_hover_color", "AccentButton", Palette.BG)
	t.set_color("font_pressed_color", "AccentButton", Palette.BG)
	t.set_color("font_focus_color", "AccentButton", Palette.BG)
	t.set_stylebox("normal", "AccentButton", style_box(Palette.ACCENT, 8, 0, Color(0, 0, 0, 0), Vector4(20, 12, 20, 12)))
	t.set_stylebox("hover", "AccentButton", style_box(Color("#6fd6f7"), 8, 0, Color(0, 0, 0, 0), Vector4(20, 12, 20, 12)))
	t.set_stylebox("pressed", "AccentButton", style_box(Color("#39a9cc"), 8, 0, Color(0, 0, 0, 0), Vector4(20, 12, 20, 12)))
	t.set_stylebox("focus", "AccentButton", style_box(Color(0, 0, 0, 0), 8, 2, Color("#c8f4ff"), Vector4(20, 12, 20, 12)))

	# 透明按钮（工具栏用）
	t.set_type_variation("GhostButton", "Button")
	t.set_color("font_color", "GhostButton", Palette.DIM)
	t.set_color("font_hover_color", "GhostButton", Palette.TEXT)
	t.set_color("font_focus_color", "GhostButton", Palette.TEXT)
	t.set_stylebox("normal", "GhostButton", style_box(Color(0, 0, 0, 0), 8, 0, Color(0, 0, 0, 0), Vector4(12, 7, 12, 7)))
	t.set_stylebox("hover", "GhostButton", style_box(Palette.PANEL_3, 8, 0, Color(0, 0, 0, 0), Vector4(12, 7, 12, 7)))
	t.set_stylebox("pressed", "GhostButton", style_box(Color("#2b3340"), 8, 0, Color(0, 0, 0, 0), Vector4(12, 7, 12, 7)))
	t.set_stylebox("focus", "GhostButton", style_box(Color(0, 0, 0, 0), 8, 1, Palette.ACCENT, Vector4(12, 7, 12, 7)))

	# ---- Panel / PanelContainer ----
	t.set_stylebox("panel", "PanelContainer", style_box(Palette.PANEL, 10, 1, Palette.LINE, Vector4(18, 16, 18, 16)))
	t.set_stylebox("panel", "Panel", style_box(Palette.PANEL, 10, 1, Palette.LINE, Vector4(0, 0, 0, 0)))
	t.set_stylebox("panel", "PopupPanel", style_box(Palette.PANEL, 10, 1, Palette.LINE, Vector4(12, 10, 12, 10)))

	# ---- ProgressBar ----
	t.set_stylebox("background", "ProgressBar", style_box(Palette.PANEL_3, 3, 0, Color(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", style_box(Palette.ACCENT, 3, 0, Color(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
	t.set_color("font_color", "ProgressBar", Palette.DIM)

	# ---- 滚动条 ----
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, style_box(Color(0, 0, 0, 0), 4, 0, Color(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
		t.set_stylebox("scroll_focus", bar, style_box(Color(0, 0, 0, 0), 4, 0, Color(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
		t.set_stylebox("grabber", bar, style_box(Palette.LINE, 4, 0, Color(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
		t.set_stylebox("grabber_highlight", bar, style_box(Color("#313a4b"), 4, 0, Color(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
		t.set_stylebox("grabber_pressed", bar, style_box(Palette.ACCENT_DIM, 4, 0, Color(0, 0, 0, 0), Vector4(0, 0, 0, 0)))

	return t
