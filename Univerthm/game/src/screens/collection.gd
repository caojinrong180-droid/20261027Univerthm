extends Control
## 收藏品图鉴：真实资源计数、分类与全屏预览。
## 分类：全部 / 角色立绘 / 曲绘（卡片网格）+ 剧情（列表，点开读 txt 全文）。

const BANNERS_DIR := "res://assets/banners"
const FILTERS := ["all", "banner", "cover", "story"]
const TAB_LABELS := {"all": "全部", "banner": "角色立绘", "cover": "曲绘", "story": "剧情"}
const TOAST_COLOR := Color("bdf49c")
const STORY_BODY := Color("ded7ef")
const Neon = preload("res://src/ui/neon_ui.gd")

var _cards: Array = []
var _stories: Array = []
var _filter := "all"
var _reading_story := false
var _overlay: Control
var _overlay_tex: TextureRect
var _overlay_kind: Label
var _overlay_title: Label
var _overlay_sub: Label
var _story_section: VBoxContainer
var _story_rows: VBoxContainer
var _story_scroll: ScrollContainer
var _story_text: VBoxContainer
var _toast: Label
var _toast_tween: Tween


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
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _overlay.visible:
			_close_preview()
		else:
			App.goto_menu()
	elif event.keycode == KEY_R and not _overlay.visible:
		get_viewport().set_input_as_handled()
		_reload_stories()
		_show_toast("已重新扫描剧情目录")


## 阅读时键盘翻页；滚轮由 ScrollContainer 自己处理。
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _overlay == null or not _overlay.visible or not _reading_story or _story_scroll == null:
		return
	var page := int(maxf(120.0, _story_scroll.size.y * 0.85))
	var bar := _story_scroll.get_v_scroll_bar()
	var next := _story_scroll.scroll_vertical
	match event.keycode:
		KEY_DOWN:
			next += 90
		KEY_UP:
			next -= 90
		KEY_PAGEDOWN, KEY_SPACE:
			next += page
		KEY_PAGEUP:
			next -= page
		KEY_HOME:
			next = 0
		KEY_END:
			next = int(bar.max_value)
		_:
			return
	_story_scroll.scroll_vertical = clampi(next, 0, maxi(0, int(bar.max_value - bar.page)))
	get_viewport().set_input_as_handled()


func _find(node_name: String) -> Node:
	var node := get_node_or_null("%" + node_name)
	return node if node != null else find_child(node_name, true, false)


func _resolve() -> void:
	_find("BackButton").pressed.connect(func(): App.goto_menu())
	_find("AccentBackButton").pressed.connect(func(): App.goto_menu())
	_overlay = _find("Overlay")
	_overlay_tex = _find("OverlayTex")
	_overlay_kind = _find("OverlayKind")
	_overlay_title = _find("OverlayTitle")
	_overlay_sub = _find("OverlaySub")
	_find("Dim").gui_input.connect(_on_dim_input)
	_find("ClosePreview").pressed.connect(_close_preview)
	_close_preview()
	_ensure_story_tab()
	for key in FILTERS:
		var tab := _find("Tab_" + key) as Button
		if tab != null and not tab.pressed.is_connected(_set_filter.bind(key)):
			tab.pressed.connect(_set_filter.bind(key))
	_find("GalleryScroll").resized.connect(_resize_grid)
	Neon.style_scroll(_find("GalleryScroll"))
	_build_story_ui()
	var window := get_window()
	if not window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.connect(_on_files_dropped)
	_refresh_counts()
	_fill_cards()
	_resize_grid.call_deferred()


# --------------------------------------------------------------------------- #
# 分类 / 计数
# --------------------------------------------------------------------------- #

func _ensure_story_tab() -> void:
	if _find("Tab_story") != null:
		return
	var anchor := _find("Tab_all") as Button
	if anchor == null:
		return
	var tab := Neon.button(TAB_LABELS["story"], false, 14)
	tab.name = "Tab_story"
	tab.custom_minimum_size = Vector2(130, 32)
	tab.toggle_mode = true
	tab.button_group = anchor.button_group
	var row := anchor.get_parent()
	row.add_child(tab)
	var cover := _find("Tab_cover") as Button
	row.move_child(tab, (cover.get_index() + 1) if cover != null else row.get_child_count() - 1)


func _refresh_counts() -> void:
	var banners := 0
	for card in _cards:
		if card.kind == "banner":
			banners += 1
	var covers := _cards.size() - banners
	_find("CountLabel").text = "%02d 件收藏 · %02d 篇剧情" % [_cards.size(), _stories.size()]
	_find("Tab_all").text = "全部  %02d" % (_cards.size() + _stories.size())
	_find("Tab_banner").text = "%s  %02d" % [TAB_LABELS["banner"], banners]
	_find("Tab_cover").text = "%s  %02d" % [TAB_LABELS["cover"], covers]
	var story_tab := _find("Tab_story") as Button
	if story_tab != null:
		story_tab.text = "%s  %02d" % [TAB_LABELS["story"], _stories.size()]
	var story_count := _find("StoryCount") as Label
	if story_count != null:
		story_count.text = "%02d 篇" % _stories.size()
	_find("FooterInfo").text = "COLLECTION  /  %02d ITEMS · %02d STORIES" % [_cards.size(), _stories.size()]


func _set_filter(key: String) -> void:
	_filter = key
	# 剧情是外部文件：切回这一类就重新扫一遍，刚放进来的 txt 会自己出现。
	if key == "all" or key == "story":
		_stories = _unlocked_stories()
		_refresh_counts()
	_fill_cards()


func _reload_stories() -> void:
	_stories = _unlocked_stories()
	_refresh_counts()
	_fill_cards()


## 只列已搜集的剧情：没通关对应谱面掉到的那篇，收藏品页不显示。
func _unlocked_stories() -> Array:
	var owned := StorySource.unlocked_names()
	var out: Array = []
	for entry in StorySource.scan():
		if owned.has(str(entry.get("file", ""))):
			out.append(entry)
	return out


# --------------------------------------------------------------------------- #
# 卡片 / 剧情列表
# --------------------------------------------------------------------------- #

func _fill_cards() -> void:
	var grid := _find("CardGrid") as GridContainer
	_clear_children(grid)
	var show_images := _filter != "story"
	var shown := 0
	if show_images:
		for i in _cards.size():
			var card: Dictionary = _cards[i]
			if _filter != "all" and card.kind != _filter:
				continue
			grid.add_child(_build_card(card, i + 1))
			shown += 1
	grid.visible = show_images
	for key in FILTERS:
		var tab := _find("Tab_" + key) as Button
		if tab == null:
			continue
		tab.set_pressed_no_signal(key == _filter)
		tab._refresh()
	var story_visible := _filter == "all" or _filter == "story"
	if _story_section != null:
		_story_section.visible = story_visible
		if story_visible:
			_fill_stories()
	var empty := _find("EmptyState") as Label
	if empty != null:
		empty.visible = show_images and shown == 0
		if _filter == "banner":
			empty.text = "还没有角色立绘\n把图片放进 assets/banners，会自动收录。"
		elif _filter == "cover":
			empty.text = "还没有曲绘\n带曲绘的谱面导入后，会自动出现在这里。"
		else:
			empty.text = "暂无收藏\n带曲绘的谱面导入后，会自动出现在这里。"
	_resize_grid.call_deferred()


func _fill_stories() -> void:
	_clear_children(_story_rows)
	# 一篇都还没搜集到时留空，不摆提示文字
	if _stories.is_empty():
		return
	for i in _stories.size():
		_story_rows.add_child(_build_story_row(_stories[i], i + 1))


func _build_story_row(story: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.name = "Story_%02d" % index
	button.custom_minimum_size.y = 66
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = "%s · 点击阅读" % str(story.get("title", ""))
	button.add_theme_stylebox_override("normal",
		UiTheme.style_box(Color(0.04, 0.025, 0.08, 0.62), 0, 1, Color("4b3568"), Vector4(16, 8, 16, 8)))
	button.add_theme_stylebox_override("hover",
		UiTheme.style_box(Color(0.15, 0.065, 0.25, 0.82), 0, 1, Color("a06ce8"), Vector4(16, 8, 16, 8)))
	button.add_theme_stylebox_override("pressed",
		UiTheme.style_box(Color(0.21, 0.09, 0.35, 0.9), 0, 1, Color("c79bff"), Vector4(16, 8, 16, 8)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_open_story.bind(story))
	var content := UiKit.hbox(14)
	content.name = "RowContent"
	UiKit.full_rect(content)
	content.offset_left = 18
	content.offset_right = -18
	content.offset_top = 10
	content.offset_bottom = -10
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var number := Neon.label("%02d" % index, 11, Neon.PURPLE, true)
	number.custom_minimum_size.x = 26
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(number)
	var texts := UiKit.vbox(3)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(texts)
	var title := Neon.label(str(story.get("title", "未命名剧情")), 17, Neon.LIGHT, true)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(title)
	var excerpt := Neon.label(str(story.get("subtitle", "")), 11, Neon.MUTED)
	excerpt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(excerpt)
	var parts: Array = []
	if str(story.get("folder", "")) != "":
		parts.append(str(story["folder"]))
	parts.append("%s 字" % _thousands(int(story.get("chars", 0))))
	parts.append("%d 分钟" % int(story.get("minutes", 1)))
	if not bool(story.get("utf8_ok", true)):
		parts.append("编码异常")
	var info := Neon.label("  ·  ".join(parts), 11, Neon.MUTED)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(info)
	return button


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
	_stories = _unlocked_stories()


# --------------------------------------------------------------------------- #
# 剧情界面（列表 + 阅读区，都是代码生成）
# --------------------------------------------------------------------------- #

func _build_story_ui() -> void:
	var grid := _find("CardGrid") as GridContainer
	if grid == null or _overlay_tex == null:
		return
	_story_section = UiKit.vbox(10)
	_story_section.name = "StorySection"
	grid.get_parent().add_child(_story_section)
	var head := UiKit.hbox(10)
	_story_section.add_child(head)
	head.add_child(Neon.label("剧情档案", 17, Neon.LIGHT, true))
	head.add_child(Neon.label("/ STORY ARCHIVE", 11, Neon.PURPLE))
	var rule := UiKit.rule(Color("4a2f6b"))
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(rule)
	var count := Neon.label("00 篇", 12, Neon.MUTED)
	count.name = "StoryCount"
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(count)
	_story_rows = UiKit.vbox(8)
	_story_rows.name = "StoryList"
	_story_section.add_child(_story_rows)

	# 阅读区：和图片预览共用同一个全屏 Overlay，图片 / 文本二选一显示。
	var preview_box := _overlay_tex.get_parent()
	_story_scroll = ScrollContainer.new()
	_story_scroll.name = "StoryScroll"
	_story_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_story_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_story_scroll.custom_minimum_size = Vector2(0, 240)
	Neon.style_scroll(_story_scroll)
	preview_box.add_child(_story_scroll)
	preview_box.move_child(_story_scroll, _overlay_tex.get_index() + 1)
	_story_text = UiKit.vbox(12)
	_story_text.name = "StoryText"
	_story_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_scroll.add_child(_story_text)
	_story_scroll.hide()

	# 顶部状态提示：导入成功 / 刷新结果
	var tabs := _find("Tab_all").get_parent()
	_toast = Neon.label("", 12, TOAST_COLOR)
	_toast.name = "Toast"
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tabs.add_child(_toast)
	var count_label := _find("CountLabel")
	if count_label != null:
		tabs.move_child(_toast, count_label.get_index())


# --------------------------------------------------------------------------- #
# 卡片 / 剧情
# --------------------------------------------------------------------------- #

func _build() -> void:
	Neon.background(self)
	Neon.topbar(self, "收藏品")
	Neon.footer(self, "Esc 返回  ·  点击卡片查看大图  ·  通关掉落剧情", "COLLECTION / 00 ITEMS")
	var panel := Neon.content(self)
	var box := UiKit.vbox(12)
	panel.add_child(box)
	box.add_child(Neon.heading("收藏品", "COLLECTION / VISUAL ARCHIVE", "收藏每一次相遇，留住每一段旋律。"))
	var tabs := UiKit.hbox(10)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for key in FILTERS:
		var tab := Neon.button(TAB_LABELS[key], false, 14)
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
	var note := Neon.label("角色立绘 / 谱面曲绘 / 剧情文本，自动收录", 12, Neon.MUTED)
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
	var kind := Neon.label("藏品鉴赏 / ARTWORK", 13, Neon.PURPLE)
	kind.name = "OverlayKind"
	top.add_child(kind)
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


# --------------------------------------------------------------------------- #
# 预览 / 阅读
# --------------------------------------------------------------------------- #

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close_preview()


func _open_preview(card: Dictionary) -> void:
	_reading_story = false
	if _story_scroll != null:
		_story_scroll.hide()
	_clear_children(_story_text)
	_overlay_tex.show()
	_overlay_tex.texture = card.tex
	if _overlay_kind != null:
		_overlay_kind.text = "藏品鉴赏 / ARTWORK"
	_overlay_title.text = card.title
	_overlay_sub.text = "%s  ·  Esc / 点击关闭" % card.subtitle
	_overlay.show()
	_find("ClosePreview").grab_focus()


func _open_story(story: Dictionary) -> void:
	var data := StorySource.read_story(story)
	_reading_story = true
	_clear_children(_story_text)
	_overlay_tex.hide()
	if _story_scroll != null:
		_story_scroll.show()
		_story_scroll.scroll_vertical = 0
	if _overlay_kind != null:
		_overlay_kind.text = "剧情阅览 / STORY"
	_overlay_title.text = str(story.get("title", "未命名剧情"))
	var meta := "%s  ·  %s 字  ·  约 %d 分钟" % [
		str(story.get("source", "")),
		_thousands(int(story.get("chars", 0))),
		int(story.get("minutes", 1)),
	]
	if not bool(data.get("utf8_ok", true)):
		meta += "  ·  编码可能不是 UTF-8，请另存为 UTF-8"
	_overlay_sub.text = meta + "  ·  ↑↓ / PgDn 翻页  ·  Esc 关闭"
	if str(data.get("error", "")) != "":
		_add_story_notice(str(data["error"]), Color("ff9aa2"))
	else:
		for block in data.get("blocks", []):
			_add_story_block(block)
		if _story_text.get_child_count() == 0:
			_add_story_notice("这篇剧情还是空的。", Neon.MUTED)
	_overlay.show()
	_find("ClosePreview").grab_focus()


func _add_story_block(block: Dictionary) -> void:
	var kind := str(block.get("kind", "text"))
	var text := str(block.get("text", ""))
	if kind == "chapter":
		var head := Neon.label(text, 21, Neon.LIGHT, true)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_story_text.add_child(head)
		_story_text.add_child(UiKit.rule(Color("5a3d7f")))
	elif kind == "rule":
		_story_text.add_child(UiKit.gap(4))
		_story_text.add_child(UiKit.rule(Color("3d2b57")))
		_story_text.add_child(UiKit.gap(4))
	elif text.strip_edges() != "":
		var para := Neon.label(text, 16, STORY_BODY)
		para.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		para.add_theme_constant_override("line_spacing", 7)
		_story_text.add_child(para)


func _add_story_notice(message: String, color: Color) -> void:
	var notice := Neon.label(message, 15, color)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_text.add_child(notice)


func _close_preview() -> void:
	_reading_story = false
	if _story_scroll != null:
		_story_scroll.hide()
	_clear_children(_story_text)
	if _overlay_tex != null:
		_overlay_tex.show()
	if _overlay != null:
		_overlay.hide()


# --------------------------------------------------------------------------- #
# 拖拽导入
# --------------------------------------------------------------------------- #

func _on_files_dropped(files: PackedStringArray) -> void:
	var messages: Array = []
	var imported := 0
	for file in files:
		var result := StorySource.import_file(str(file))
		messages.append(str(result.get("message", "")))
		if bool(result.get("ok", false)):
			imported += 1
	_reload_stories()
	if imported > 0:
		_set_filter("story")
	_show_toast("  ·  ".join(messages))


func _show_toast(message: String) -> void:
	if _toast == null or message.strip_edges() == "":
		return
	_toast.text = message
	_toast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


# --------------------------------------------------------------------------- #
# 小工具
# --------------------------------------------------------------------------- #

func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## 1234 → "1,234"
func _thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func _export_prepare() -> void:
	var grid := _find("CardGrid")
	for child in grid.get_children():
		grid.remove_child(child)
		child.free()
	for list_name in ["StoryList", "StoryText"]:
		var list := _find(list_name)
		if list != null:
			for child in list.get_children():
				list.remove_child(child)
				child.free()
	var section := _find("StorySection") as Control
	if section != null:
		section.hide()
	var scroll := _find("StoryScroll") as Control
	if scroll != null:
		scroll.hide()
	_close_preview()
	for key in ["BackButton", "AccentBackButton", "CardGrid", "GalleryScroll", "CountLabel", "FooterInfo", "EmptyState", "Tab_all", "Tab_banner", "Tab_cover", "Tab_story", "Overlay", "OverlayKind", "OverlayTex", "OverlayTitle", "OverlaySub", "Dim", "ClosePreview", "StorySection", "StoryList", "StoryCount", "StoryScroll", "StoryText", "Toast"]:
		var node := _find(key)
		if node != null:
			node.unique_name_in_owner = true
