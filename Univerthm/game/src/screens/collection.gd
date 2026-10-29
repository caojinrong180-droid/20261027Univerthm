extends Control
## 收藏品图鉴：真实资源计数、分类与全屏预览。

const BANNERS_DIR := "res://assets/banners"
const Neon = preload("res://src/ui/neon_ui.gd")

var _cards: Array = []
var _filter := "all"
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _overlay.visible:
			_close_preview()
		else:
			App.goto_menu()


func _find(node_name: String) -> Node:
	var node := get_node_or_null("%" + node_name)
	return node if node != null else find_child(node_name, true, false)


func _resolve() -> void:
	_find("BackButton").pressed.connect(func(): App.goto_menu())
	_find("AccentBackButton").pressed.connect(func(): App.goto_menu())
	_overlay = _find("Overlay")
	_overlay_tex = _find("OverlayTex")
	_overlay_title = _find("OverlayTitle")
	_overlay_sub = _find("OverlaySub")
	_find("Dim").gui_input.connect(_on_dim_input)
	_find("ClosePreview").pressed.connect(_close_preview)
	_close_preview()
	for key in ["all", "banner", "cover"]:
		var tab := _find("Tab_" + key) as Button
		tab.pressed.connect(_set_filter.bind(key))
	_find("GalleryScroll").resized.connect(_resize_grid)
	Neon.style_scroll(_find("GalleryScroll"))
	_refresh_counts()
	_fill_cards()
	_resize_grid.call_deferred()


func _refresh_counts() -> void:
	var banners := 0
	for card in _cards:
		if card.kind == "banner":
			banners += 1
	_find("CountLabel").text = "%02d 件收藏" % _cards.size()
	_find("Tab_all").text = "全部  %02d" % _cards.size()
	_find("Tab_banner").text = "角色立绘  %02d" % banners
	_find("Tab_cover").text = "曲绘  %02d" % (_cards.size() - banners)
	_find("FooterInfo").text = "COLLECTION  /  %02d ITEMS" % _cards.size()


func _set_filter(key: String) -> void:
	_filter = key
	_fill_cards()


func _fill_cards() -> void:
	var grid := _find("CardGrid") as GridContainer
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var shown := 0
	for i in _cards.size():
		var card: Dictionary = _cards[i]
		if _filter != "all" and card.kind != _filter:
			continue
		grid.add_child(_build_card(card, i + 1))
		shown += 1
	for key in ["all", "banner", "cover"]:
		_find("Tab_" + key).set_pressed_no_signal(key == _filter)
		_find("Tab_" + key)._refresh()
	_find("EmptyState").visible = shown == 0
	_resize_grid.call_deferred()


func _resize_grid() -> void:
	var scroll := _find("GalleryScroll") as ScrollContainer
	var grid := _find("CardGrid") as GridContainer
	grid.columns = maxi(1, int((scroll.size.x + 18.0) / 232.0))
	var width := maxf(180.0, floorf((scroll.size.x - 14.0 - (grid.columns - 1) * 18.0) / grid.columns))
	for child in grid.get_children():
		child.custom_minimum_size.x = width
	# 动态排布改变高度后刷新滚动范围。
	scroll.update_minimum_size()
	scroll.get_combined_minimum_size()
	scroll.queue_sort()


func _collect() -> void:
	_cards.clear()
	var dir := DirAccess.open(BANNERS_DIR)
	if dir != null:
		for file in dir.get_files():
			if not str(file).get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
				continue
			var path := "%s/%s" % [BANNERS_DIR, file]
			if ResourceLoader.exists(path):
				var title := str(file).get_basename()
				if title.begins_with("exec-"):
					title = "角色立绘 %02d" % (_cards.size() + 1)
				_cards.append({"title": title, "subtitle": "CHARACTER / 角色立绘", "kind": "banner", "tex": load(path)})
	# 首张立绘之后展示曲绘，让默认分类同时呈现两类收藏。
	var cover_index := mini(1, _cards.size())
	for entry in App.library:
		if not bool(entry.get("has_cover", false)):
			continue
		var tex: Texture2D = ChartSource.load_cover(entry)
		if tex != null:
			_cards.insert(cover_index, {"title": str(entry.get("title", "未命名谱面")), "subtitle": str(entry.get("difficulty", "NORMAL")), "kind": "cover", "tex": tex})
			cover_index += 1


func _build() -> void:
	Neon.background(self)
	Neon.topbar(self, "收藏品")
	Neon.footer(self, "Esc 返回  ·  点击卡片查看大图", "COLLECTION / 00 ITEMS")
	var panel := Neon.content(self)
	var box := UiKit.vbox(12)
	panel.add_child(box)
	box.add_child(Neon.heading("收藏品", "COLLECTION / VISUAL ARCHIVE", "收藏每一次相遇，留住每一段旋律。"))
	var tabs := UiKit.hbox(10)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for key in ["all", "banner", "cover"]:
		var tab := Neon.button("全部", false, 14)
		tab.name = "Tab_" + key
		tab.custom_minimum_size = Vector2(130, 32)
		tab.toggle_mode = true
		tab.button_group = group
		tabs.add_child(tab)
	tabs.add_child(UiKit.stretch())
	var count := Neon.label("00 件收藏", 14, Neon.MUTED)
	count.name = "CountLabel"
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tabs.add_child(count)

	var scroll := ScrollContainer.new()
	scroll.name = "GalleryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := UiKit.vbox(12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	var grid := GridContainer.new()
	grid.name = "CardGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	inner.add_child(grid)
	var empty := Neon.label("暂无收藏\n带曲绘的谱面导入后，会自动出现在这里。", 17, Neon.MUTED)
	empty.name = "EmptyState"
	empty.custom_minimum_size.y = 160
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(empty)
	box.add_child(UiKit.rule(Color("624480")))
	var actions := UiKit.hbox(16)
	box.add_child(actions)
	var back := Neon.button("← 返回（Esc）", true)
	back.name = "AccentBackButton"
	back.custom_minimum_size.x = 200
	actions.add_child(back)
	actions.add_child(UiKit.stretch())
	var note := Neon.label("角色立绘 / 谱面曲绘，自动收录", 12, Neon.MUTED)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(note)
	_build_overlay()


func _build_card(card: Dictionary, index: int) -> Button:
	var button := Neon.button("", false)
	button.name = "Collectible_%02d" % index
	button.custom_minimum_size = Vector2(214, 278)
	button.tooltip_text = "%s · 点击放大" % card.title
	button.pressed.connect(_open_preview.bind(card))
	var art_frame := Neon.panel(Vector4.ZERO)
	art_frame.fill = Color("100b1e")
	art_frame.edge = Color("583b7c")
	art_frame.cut = 14
	art_frame.accents = false
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.anchor_right = 1
	art_frame.anchor_bottom = 1
	art_frame.offset_left = 10
	art_frame.offset_top = 10
	art_frame.offset_right = -10
	art_frame.offset_bottom = -66
	button.add_child(art_frame)
	var thumb := TextureRect.new()
	thumb.texture = card.tex
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if card.kind == "banner" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_child(UiKit.margin(thumb, 6, 6, 6, 6))
	var number := Neon.panel(Vector4(7, 2, 7, 2))
	number.position = Vector2(17, 14)
	number.fill = Color(0.025, 0.015, 0.055, 0.92)
	number.edge = Color("76509b")
	number.cut = 5
	number.accents = false
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.add_child(Neon.label("%02d" % index, 11, Neon.LIGHT, true))
	button.add_child(number)
	var title := Neon.label(card.title, 18, Neon.LIGHT, true)
	title.anchor_top = 1
	title.anchor_bottom = 1
	title.anchor_right = 1
	title.offset_left = 18
	title.offset_right = -20
	title.offset_top = -61
	title.offset_bottom = -33
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_child(title)
	var sub := Neon.label(card.subtitle, 10, Neon.PURPLE)
	sub.anchor_top = 1
	sub.anchor_bottom = 1
	sub.anchor_right = 1
	sub.offset_left = 18
	sub.offset_right = -24
	sub.offset_top = -31
	sub.offset_bottom = -13
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_child(sub)
	return button


func _build_overlay() -> void:
	var overlay := Control.new()
	overlay.name = "Overlay"
	UiKit.full_rect(overlay)
	overlay.hide()
	add_child(overlay)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.015, 0.008, 0.035, 0.94)
	UiKit.full_rect(dim)
	overlay.add_child(dim)
	var frame := Neon.panel(Vector4(24, 16, 24, 18))
	frame.name = "PreviewFrame"
	frame.glow = true
	frame.anchor_left = 0.22
	frame.anchor_right = 0.78
	frame.anchor_bottom = 1
	frame.offset_top = 28
	frame.offset_bottom = -28
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(frame)
	var box := UiKit.vbox(10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)
	var top := UiKit.hbox(10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	top.add_child(Neon.label("藏品鉴赏 / ARTWORK", 13, Neon.PURPLE))
	top.add_child(UiKit.stretch())
	var close := Neon.button("× 关闭", false, 13)
	close.name = "ClosePreview"
	close.custom_minimum_size = Vector2(90, 30)
	top.add_child(close)
	var tex := TextureRect.new()
	tex.name = "OverlayTex"
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tex)
	box.add_child(UiKit.rule(Color("624480")))
	var title := Neon.label("", 22, Neon.LIGHT, true)
	title.name = "OverlayTitle"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	var sub := Neon.label("", 12, Neon.MUTED)
	sub.name = "OverlaySub"
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(sub)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close_preview()


func _open_preview(card: Dictionary) -> void:
	_overlay_tex.texture = card.tex
	_overlay_title.text = card.title
	_overlay_sub.text = "%s  ·  Esc / 点击关闭" % card.subtitle
	_overlay.show()
	_find("ClosePreview").grab_focus()


func _close_preview() -> void:
	if _overlay != null:
		_overlay.hide()


func _export_prepare() -> void:
	var grid := _find("CardGrid")
	for child in grid.get_children():
		grid.remove_child(child)
		child.free()
	for key in ["BackButton", "AccentBackButton", "CardGrid", "GalleryScroll", "CountLabel", "FooterInfo", "EmptyState", "Tab_all", "Tab_banner", "Tab_cover", "Overlay", "OverlayTex", "OverlayTitle", "OverlaySub", "Dim", "ClosePreview"]:
		_find(key).unique_name_in_owner = true
