extends Control
## 收藏品：把「看板娘立绘」和谱面的曲绘做成一个小图鉴。
## 点卡片 → 全屏放大预览；Esc / 点任意处关闭；Esc 关闭预览时再按一次回主界面。

const BANNERS_DIR := "res://assets/banners"

var _cards: Array = []            # [{ title, subtitle, tex }]
var _overlay: Control
var _overlay_tex: TextureRect
var _overlay_title: Label
var _overlay_sub: Label


func _ready() -> void:
	theme = UiTheme.theme()
	App.refresh_library()
	_collect()
	if get_child_count() == 0:
		_build()
	_resolve()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _overlay.visible:
			_close_preview()
		else:
			App.goto_menu()


## 先找唯一名（%Name），再退回 find_child —— 代码搭的 / .tscn 都能用
func _find(node_name: String) -> Node:
	var n := get_node_or_null("%" + node_name)
	if n != null:
		return n
	return find_child(node_name, true, false)


func _fill_cards(grid: GridContainer) -> void:
	for child in grid.get_children():
		child.queue_free()
	for card in _cards:
		grid.add_child(_build_card(card))


func _resolve() -> void:
	var back: Button = _find("BackButton")
	if back != null:
		back.pressed.connect(func(): App.goto_menu())
	var grid := _find("CardGrid") as GridContainer
	if grid != null:
		_fill_cards(grid)
	var overlay := _find("Overlay")
	if overlay != null:
		_overlay = overlay
		_close_preview()
	var tex := _find("OverlayTex") as TextureRect
	if tex != null:
		_overlay_tex = tex
	var title := _find("OverlayTitle") as Label
	if title != null:
		_overlay_title = title
	var sub := _find("OverlaySub") as Label
	if sub != null:
		_overlay_sub = sub
	var dim := _find("Dim")
	if dim != null and not dim.gui_input.is_connected(_on_dim_input):
		dim.gui_input.connect(_on_dim_input)


func _on_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		_close_preview()


## 导出成 .tscn 之前：清掉动态卡片、给关键节点起名
func _export_prepare() -> void:
	var grid := find_child("CardGrid", true, false)
	if grid != null:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	for n in ["BackButton", "CardGrid", "Overlay", "OverlayTex", "OverlayTitle", "OverlaySub", "Dim"]:
		var node := find_child(n, true, false)
		if node != null:
			node.unique_name_in_owner = true

# --------------------------------------------------------------------------- #
# 数据
# --------------------------------------------------------------------------- #

func _collect() -> void:
	_cards.clear()
	var dir := DirAccess.open(BANNERS_DIR)
	if dir != null:
		for f in dir.get_files():
			var lower := str(f).to_lower()
			if not (lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".webp")):
				continue
			var path := "%s/%s" % [BANNERS_DIR, f]
			if ResourceLoader.exists(path):
				_cards.append({"title": str(f).get_basename(), "subtitle": "BANNER", "tex": load(path)})
	for entry in App.library:
		if not bool(entry.get("has_cover", false)):
			continue
		var tex: Texture2D = ChartSource.load_cover(entry)
		if tex == null:
			continue
		_cards.append({
			"title": str(entry.get("title", "未命名谱面")),
			"subtitle": str(entry.get("difficulty", "NORMAL")),
			"tex": tex,
		})


# --------------------------------------------------------------------------- #
# 界面
# --------------------------------------------------------------------------- #

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	UiKit.full_rect(bg)
	add_child(bg)

	var column := UiKit.vbox(0)
	UiKit.full_rect(column)
	add_child(column)

	column.add_child(_build_topbar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var inner := UiKit.margin(UiKit.vbox(14), 28, 22, 28, 26)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	if _cards.size() <= 1:
		var empty := UiKit.label("谱面带曲绘时，曲绘也会收进这里（制谱器的「曲绘」那栏）", 14, Palette.DIM_2)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.get_child(0).add_child(empty)

	var grid := GridContainer.new()
	grid.name = "CardGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	inner.get_child(0).add_child(grid)

	_fill_cards(grid)

	column.add_child(_build_statusbar())
	_build_overlay()


func _build_topbar() -> Control:
	var bar := UiKit.panel(Palette.PANEL, 0, 0, Color(0, 0, 0, 0), Vector4(26, 12, 26, 12))
	var h := UiKit.hbox(12)
	bar.add_child(h)

	var back := UiKit.button("← 返回", 14, "GhostButton")
	back.name = "BackButton"
	h.add_child(back)

	var title := UiKit.label("收藏品", 20, Palette.TEXT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(title)

	var chip := UiKit.chip("%d 件" % _cards.size(), Palette.ACCENT, 12)
	chip.name = "CountChip"
	h.add_child(chip)
	h.add_child(UiKit.stretch())

	var hint := UiKit.mono_label("点击卡片放大 · ESC 返回", 12, Palette.DIM_2)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(hint)
	return bar


func _build_card(card: Dictionary) -> Control:
	var b := UiKit.button("", 14)
	b.custom_minimum_size = Vector2(196, 236)
	b.add_theme_stylebox_override("normal",
		UiTheme.style_box(Palette.PANEL_2, 10, 1, Palette.LINE, Vector4(8, 8, 8, 8)))
	b.add_theme_stylebox_override("hover",
		UiTheme.style_box(Palette.PANEL_3, 10, 1, Palette.ACCENT, Vector4(8, 8, 8, 8)))
	b.add_theme_stylebox_override("pressed",
		UiTheme.style_box(Palette.alpha(Palette.ACCENT, 0.16), 10, 1, Palette.ACCENT, Vector4(8, 8, 8, 8)))
	b.add_theme_stylebox_override("focus",
		UiTheme.style_box(Color(0, 0, 0, 0), 10, 1, Palette.ACCENT_DIM, Vector4(8, 8, 8, 8)))
	b.pressed.connect(func(): _open_preview(card))

	var thumb := TextureRect.new()
	thumb.texture = card.get("tex")
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.anchor_right = 1.0
	thumb.anchor_bottom = 1.0
	thumb.offset_left = 8.0
	thumb.offset_top = 8.0
	thumb.offset_right = -8.0
	thumb.offset_bottom = -52.0
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(thumb)

	var clip := ColorRect.new()
	clip.color = Palette.alpha(Palette.BG_DEEP, 0.35)
	clip.anchor_right = 1.0
	clip.anchor_bottom = 1.0
	clip.offset_left = 8.0
	clip.offset_top = 8.0
	clip.offset_right = -8.0
	clip.offset_bottom = -52.0
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(clip)

	var name_label := UiKit.label(str(card.get("title", "")), 14, Palette.TEXT)
	name_label.anchor_top = 1.0
	name_label.anchor_bottom = 1.0
	name_label.anchor_right = 1.0
	name_label.offset_left = 12.0
	name_label.offset_top = -50.0
	name_label.offset_right = -12.0
	name_label.offset_bottom = -30.0
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name_label)

	var sub := UiKit.mono_label(str(card.get("subtitle", "")), 11, Palette.DIM_2)
	sub.anchor_top = 1.0
	sub.anchor_bottom = 1.0
	sub.anchor_right = 1.0
	sub.offset_left = 12.0
	sub.offset_top = -28.0
	sub.offset_right = -12.0
	sub.offset_bottom = -10.0
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sub)
	return b


func _build_statusbar() -> Control:
	var bar := UiKit.panel(Palette.PANEL_2, 0, 0, Color(0, 0, 0, 0), Vector4(26, 8, 26, 8))
	var h := UiKit.hbox(10)
	bar.add_child(h)
	var label := UiKit.mono_label("看板娘 + 曲绘 = 收藏品     ESC 返回主界面", 12, Palette.DIM_2)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(label)
	h.add_child(UiKit.stretch())
	var count := UiKit.mono_label("%d" % _cards.size(), 12, Palette.DIM)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(count)
	return bar


# --------------------------------------------------------------------------- #
# 放大预览
# --------------------------------------------------------------------------- #

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	UiKit.full_rect(_overlay)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.025, 0.04, 0.86)
	UiKit.full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_close_preview())
	_overlay.add_child(dim)

	var frame := UiKit.panel(Palette.PANEL, 12, 1, Palette.LINE, Vector4(14, 14, 14, 14))
	frame.anchor_left = 0.5
	frame.anchor_top = 0.5
	frame.anchor_right = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -300.0
	frame.offset_top = -330.0
	frame.offset_right = 300.0
	frame.offset_bottom = 330.0
	_overlay.add_child(frame)

	var box := UiKit.vbox(8)
	frame.add_child(box)

	_overlay_tex = TextureRect.new()
	_overlay_tex.name = "OverlayTex"
	_overlay_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_overlay_tex.custom_minimum_size = Vector2(570, 560)
	_overlay_tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_overlay_tex)

	_overlay_title = UiKit.label("", 16, Palette.TEXT)
	_overlay_title.name = "OverlayTitle"
	box.add_child(_overlay_title)

	_overlay_sub = UiKit.mono_label("ESC / 点击任意处关闭", 11, Palette.DIM_2)
	_overlay_sub.name = "OverlaySub"
	box.add_child(_overlay_sub)


func _open_preview(card: Dictionary) -> void:
	_overlay_tex.texture = card.get("tex")
	_overlay_title.text = str(card.get("title", ""))
	_overlay_sub.text = "%s    ·    ESC / 点击任意处关闭" % str(card.get("subtitle", ""))
	_overlay.visible = true


func _close_preview() -> void:
	_overlay.visible = false
