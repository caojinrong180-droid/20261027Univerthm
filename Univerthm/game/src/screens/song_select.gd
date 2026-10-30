extends Control
## 极简曲绘选曲：点击选择试听，独立确认后开始游玩。
##
## 界面本身在 `scenes/song_select.tscn` 里（顶部栏 / 曲库列表 / 右侧详情 / 底栏都能在
## 编辑器里直接拖），曲目行是 `scenes/song_row.tscn`。这条脚本只管数据和动效：
## 谱面行的增删、背景淡入、试听、拖拽导入。
##
## 列表刻意**没有切歌位移**：换选时行原地不动，只有高亮换人。
## 唯一的动效是鼠标悬停：没选中的行滑出去一点、选中的行把框拉长，都带缓动。
##
## 界面本身在 `scenes/song_select.tscn` 里（顶部栏 / 曲库列表 / 右侧详情 / 底栏都能在
## 编辑器里直接拖），曲目行是 `scenes/song_row.tscn`。这条脚本只管数据和动效：
## 谱面行的增删、悬停动画、背景淡入、试听、拖拽导入。

const Neon = preload("res://src/ui/neon_ui.gd")
const Preview = preload("res://src/audio/song_preview.gd")
const ROW_SCENE = preload("res://scenes/song_row.tscn")
## 曲目行的框高（列表里只留标题 + 作者，行做细一点）
const ROW_HEIGHT := 72.0
## 悬停动画时长（秒）
const HOVER_ANIM := 0.18
## 悬停时没选中的行整行往右滑这么远（底框 + 文字一起滑，鼠标命中区不动）
const HOVER_POP := 14.0
## 悬停时没选中的行同时上下各长一点，看起来像从列表里弹出来
const HOVER_POP_GROW := 3.0
## 悬停时已经选中的行不位移，只把框往右拉长这么多
const HOVER_EXTEND := 20.0
const ROW_IDLE_BG := Color(0.02, 0.01, 0.04, 0.22)
const ROW_HOVER_BG := Color(0.5, 0.26, 0.8, 0.16)
const ROW_SELECTED_BG := Color(0.22, 0.09, 0.36, 0.62)
const ROW_SELECTED_BORDER := Color(0.66, 0.43, 1, 0.5)
## 行内容的左边距（和 scenes/song_row.tscn 里的一致）
const ROW_CONTENT_INSET := 18.0
## 选中的曲目没解锁时，背景压暗到什么程度
const LOCK_BG_DIM := 0.55
## 「神秘曲」是列表里的第几首（0 开始，2 = 第 3 首）：没成绩之前信息全遮住
const SECRET_INDEX := 2
## 详情里「BEST」那行的颜色：有记录 / 暂无记录
const BEST_COLOR := Color(0.858824, 0.8, 1, 1)
const BEST_EMPTY_COLOR := Color(0.45, 0.43, 0.52, 1)
## 「自动演示」可用 / 未解锁时的字色
const AUTO_READY_COLOR := Color(0.7647059, 0.7372549, 0.81960785, 1)
const AUTO_LOCKED_COLOR := Color(0.42, 0.4, 0.48, 1)

var _rows: Array = []
## 每个列表项解锁没有（按 App.library 的顺序，第 1 首永远解锁）
var _row_locked: Array[bool] = []
## 每个列表项是不是还没揭晓的「神秘曲」
var _row_hidden: Array[bool] = []
var _selected_locked := false
## 选中的是不是「神秘曲」（第 3 首没成绩之前）
var _selected_hidden := false
var _lock_tween: Tween
var _selected := -1
var _hovered := -1
## 每行的悬停动画进度（instance_id → 0.0~1.0）和在跑的 Tween
var _row_hover_t := {}
var _row_tweens := {}
var _body: BoxContainer
var _list_box: VBoxContainer
var _empty_state: VBoxContainer
var _list_count: Label
var _detail_title: Label
var _detail_artist: Label
var _detail_illust: Label
var _detail_meta: Label
var _detail_best: Label
var _cover: TextureRect
var _cover_empty: Label
var _cover_frame: PanelContainer
var _lock_layer: Control
var _lock_text: Label
var _cover_mask: ColorRect
var _toast: Label
var _toast_tween: Tween
var _play_button: Button
var _auto_button: Button
var _cover_cache := {}
var _background_cache := {}
var _preview: Node
var _backgrounds: Array[TextureRect] = []
var _background_tween: Tween
var _list_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _leaving := false

@onready var _background_a: TextureRect = $BlurredCover0
@onready var _background_b: TextureRect = $BlurredCover1
@onready var _settings_button: Button = $TopBar/Toolbar/SettingsButton
@onready var _back_button: Button = $TopBar/Toolbar/BackButton
@onready var _import_button: Button = $Main/MusicBody/Library/EmptyState/ImportButton
@onready var _background_dim: ColorRect = $BackgroundDim


func _ready() -> void:
	theme = UiTheme.theme()
	_body = $Main/MusicBody
	_list_scroll = $Main/MusicBody/Library/SongListScroll
	_list_box = $Main/MusicBody/Library/SongListScroll/ListPad/SongList
	_empty_state = $Main/MusicBody/Library/EmptyState
	_list_count = $Main/MusicBody/Library/HeadPad/Head/ListCount
	_detail_scroll = $Main/MusicBody/DetailScroll
	_cover_frame = $Main/MusicBody/DetailScroll/DetailBox/CoverCenter/CoverFrame
	_cover = _cover_frame.get_node("Art/SelectedCover")
	_cover_empty = _cover_frame.get_node("Art/CoverEmpty")
	_detail_title = $Main/MusicBody/DetailScroll/DetailBox/SongTitle
	_detail_artist = $Main/MusicBody/DetailScroll/DetailBox/SongArtist
	_detail_illust = $Main/MusicBody/DetailScroll/DetailBox/SongCredits
	_detail_meta = $Main/MusicBody/DetailScroll/DetailBox/SongMeta
	_detail_best = $Main/MusicBody/DetailScroll/DetailBox/SongBest
	_play_button = $Main/MusicBody/DetailScroll/DetailBox/Actions/StartButton
	_auto_button = $Main/MusicBody/DetailScroll/DetailBox/Actions/AutoplayButton
	_toast = $Footer/Toast
	_background_dim = $BackgroundDim
	_lock_layer = _cover_frame.get_node("Art/LockLayer")
	_lock_text = _lock_layer.get_node("LockBox/LockText")
	_cover_mask = _cover_frame.get_node("Art/CoverMask")
	_backgrounds.assign([_background_a, _background_b])

	# 滚动条是 ScrollContainer 的内部节点，皮肤只能在运行时套
	for scroll in [_list_scroll, _detail_scroll]:
		Neon.style_scroll(scroll)
	_settings_button.pressed.connect(_open_settings)
	_back_button.pressed.connect(_back)
	_import_button.pressed.connect(_open_chart_folder)
	_play_button.pressed.connect(_play_selected.bind(false))
	_auto_button.pressed.connect(_play_selected.bind(true))

	_preview = Preview.new()
	_preview.name = "SongPreview"
	add_child(_preview)
	if App.menu_music != null:
		App.menu_music.stop_immediately()
	App.refresh_library()
	_refresh_list()
	if App.toast != "":
		_show_toast(App.toast)
		App.toast = ""
	if not get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.connect(_on_files_dropped)
	resized.connect(_layout)
	_layout.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode not in [KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER, KEY_A, KEY_F5, KEY_S, KEY_ESCAPE]:
		return
	# 场景切换会立即移除当前节点，必须在导航前消费按键。
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_UP:
			if not _rows.is_empty():
				_focus_row(wrapi(_selected - 1, 0, _rows.size()))
		KEY_DOWN:
			if not _rows.is_empty():
				_focus_row(wrapi(_selected + 1, 0, _rows.size()))
		KEY_ENTER, KEY_KP_ENTER:
			_play_selected(false)
		KEY_A:
			_play_selected(true)
		KEY_F5:
			_refresh_library()
		KEY_S:
			_open_settings()
		KEY_ESCAPE:
			_back()


func _layout() -> void:
	var narrow := size.x < 900
	_body.vertical = narrow
	_body.add_theme_constant_override("separation", 22 if narrow else 66)
	_list_scroll.custom_minimum_size.y = 140 if narrow else 0
	var cover_size := clampf(size.y - 468, 170, 280)
	_cover_frame.custom_minimum_size = Vector2(cover_size, cover_size)
	for scroll in [_list_scroll, _detail_scroll]:
		scroll.update_minimum_size()
		scroll.get_combined_minimum_size()
		scroll.queue_sort()


func _refresh_library() -> void:
	_cover_cache.clear()
	_background_cache.clear()
	_preview.stop()
	App.refresh_library()
	_refresh_list()
	_show_toast("已刷新曲库")


func _refresh_list() -> void:
	for tween in _row_tweens.values():
		if tween is Tween and tween.is_valid():
			tween.kill()
	_row_tweens.clear()
	_row_hover_t.clear()
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_row_locked.clear()
	_row_hidden.clear()
	_selected = -1
	_hovered = -1
	_list_count.text = "%d 个谱面" % App.library.size()
	var empty := App.library.is_empty()
	_empty_state.visible = empty
	if empty:
		_clear_detail()
		return
	var selected_index := 0
	for i in App.library.size():
		if str(App.library[i].get("key", "")) == App.selected_chart_key:
			selected_index = i
		# 行直接交给 VBox 排：宽度铺满、高度 = ROW_HEIGHT，切歌时没有位移动画。
		var hidden := _is_hidden_song(i)
		var row := _make_row(App.library[i], i, hidden)
		_list_box.add_child(row)
		_rows.append(row)
		_row_locked.append(not App.is_chart_unlocked(i))
		_row_hidden.append(hidden)
	_refresh_row_styles()
	_focus_row(selected_index)
	_layout.call_deferred()


## 「神秘曲」：第 3 首在打出成绩之前，所有信息都是 ???、曲绘纯黑。
## 打完第一次（有了成绩记录）就恢复正常显示。
func _is_hidden_song(index: int) -> bool:
	if index != SECRET_INDEX or index >= App.library.size():
		return false
	var record := App.best_record(str(App.library[index].get("key", "")))
	return record.is_empty()


## 一条曲目行：布局在 scenes/song_row.tscn 里，这里只填文字和接信号。
func _make_row(entry: Dictionary, index: int, hidden := false) -> Button:
	var row: Button = ROW_SCENE.instantiate()
	row.name = "Song_%02d" % index
	row.custom_minimum_size.y = ROW_HEIGHT
	# 每行一个常驻底框：悬停动画直接改它的 expand_margin / 颜色，不重建资源
	var box := UiTheme.style_box(ROW_IDLE_BG, 0, 0, Color.TRANSPARENT, Vector4.ZERO)
	row.set_meta("row_box", box)
	for state in ["normal", "hover", "pressed"]:
		row.add_theme_stylebox_override(state, box)
	row.get_node("RowContent/Texts/SongTitle").text = "???" if hidden else str(entry.get("title", "未命名谱面"))
	row.get_node("RowContent/Texts/SongArtist").text = "???" if hidden else str(entry.get("artist", ""))
	row.pressed.connect(_focus_row.bind(index))
	row.focus_entered.connect(_on_row_focused.bind(entry, index))
	row.mouse_entered.connect(_set_row_hover.bind(index, true))
	row.mouse_exited.connect(_set_row_hover.bind(index, false))
	# 键盘方向键只移动曲目焦点，Enter 由选曲页确认开始。
	row.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_play_selected(false)
				row.accept_event()
			elif event.keycode in [KEY_UP, KEY_DOWN]:
				_focus_row(wrapi(index + (-1 if event.keycode == KEY_UP else 1), 0, _rows.size()))
				row.accept_event())
	return row


func _focus_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var changed := _selected != index
	_rows[index].grab_focus()
	if changed and _selected != index:
		_on_row_focused(App.library[index], index)


func _on_row_focused(entry: Dictionary, index: int) -> void:
	if _selected == index:
		return
	_selected = index
	_selected_locked = index < _row_locked.size() and _row_locked[index]
	_selected_hidden = index < _row_hidden.size() and _row_hidden[index]
	App.selected_chart_key = str(entry.get("key", ""))
	for i in _rows.size():
		_rows[i].get_node("SelectedMark").visible = i == index
	_refresh_row_styles()
	_list_scroll.ensure_control_visible(_rows[index])
	_update_detail(entry)
	if _selected_locked:
		# 没解锁的曲子不试听
		_preview.stop()
	elif _selected_hidden:
		# 还没揭晓的神秘曲也不试听（放歌名/曲子信息就等于剧透了）
		_preview.stop()
	else:
		_preview.select(entry)


## 鼠标移进 / 移出一行：只影响行的底框和内容，不改布局、不动鼠标命中区。
func _set_row_hover(index: int, hovered: bool) -> void:
	if hovered:
		_hovered = index
	elif _hovered == index:
		_hovered = -1
	_refresh_row_styles()
	for i in _rows.size():
		_animate_row_hover(_rows[i], i, 1.0 if i == _hovered else 0.0)


## 把每行刷到它当前的悬停进度（选中状态变了就立刻换色，几何沿用当前进度）。
func _refresh_row_styles() -> void:
	for i in _rows.size():
		var row: Button = _rows[i]
		_row_visual(row, i, float(_row_hover_t.get(row.get_instance_id(), 0.0)))


## 一行的样子：hover_t = 0 常态、1 完全悬停。
## 没选中：整行往右滑 + 上下各长一点（底框和文字一起走，命中区不动）。
## 选中了：不位移，只把紫框往右拉长。
func _row_visual(row: Button, index: int, hover_t: float) -> void:
	if not is_instance_valid(row):
		return
	var selected := index == _selected
	var box: StyleBoxFlat = row.get_meta("row_box", null)
	var content: Control = row.get_node("RowContent")
	if box == null or content == null:
		return
	box.bg_color = ROW_SELECTED_BG if selected else ROW_IDLE_BG.lerp(ROW_HOVER_BG, hover_t)
	box.set_border_width_all(1 if selected else 0)
	box.border_color = ROW_SELECTED_BORDER if selected else Color.TRANSPARENT
	if selected:
		box.expand_margin_left = 0.0
		box.expand_margin_right = HOVER_EXTEND * hover_t
		box.expand_margin_top = 0.0
		box.expand_margin_bottom = 0.0
		content.offset_left = ROW_CONTENT_INSET
	else:
		box.expand_margin_left = -HOVER_POP * hover_t
		box.expand_margin_right = HOVER_POP * hover_t
		box.expand_margin_top = HOVER_POP_GROW * hover_t
		box.expand_margin_bottom = HOVER_POP_GROW * hover_t
		content.offset_left = ROW_CONTENT_INSET + HOVER_POP * hover_t


## 从当前进度缓动到目标进度（进出都用 EASE_OUT，松手那一下更干脆）。
func _animate_row_hover(row: Button, index: int, target: float) -> void:
	var id := row.get_instance_id()
	var from := float(_row_hover_t.get(id, 0.0))
	var running: Tween = _row_tweens.get(id)
	if running != null and running.is_valid():
		running.kill()
	_row_tweens.erase(id)
	if is_equal_approx(from, target) or HOVER_ANIM <= 0.0:
		_row_hover_t[id] = target
		_row_visual(row, index, target)
		return
	var tween := create_tween()
	tween.tween_method(_row_hover_step.bind(row, index), from, target, HOVER_ANIM) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_row_tweens[id] = tween


func _row_hover_step(value: float, row: Button, index: int) -> void:
	if not is_instance_valid(row):
		return
	_row_hover_t[row.get_instance_id()] = value
	_row_visual(row, index, value)


func _cover_for(entry: Dictionary) -> Texture2D:
	var key := str(entry.get("key", ""))
	if not _cover_cache.has(key):
		_cover_cache[key] = ChartSource.load_cover(entry)
	return _cover_cache[key]


func _update_detail(entry: Dictionary) -> void:
	var hidden := _selected_hidden
	var credits := "谱师  " + str(entry.get("charter", "—"))
	var illust := str(entry.get("illustrator", ""))
	if illust != "":
		credits += "    /    曲绘  " + illust
	if hidden:
		# 神秘曲：曲名 / 作者 / staff / 难度 / 时长全都遮掉，曲绘纯黑
		_detail_title.text = "???"
		_detail_artist.text = "???"
		_detail_illust.text = "???"
		_detail_meta.text = "???    /    Lv.??    /    ??:??"
	else:
		_detail_title.text = str(entry.get("title", "未命名谱面"))
		_detail_artist.text = str(entry.get("artist", ""))
		_detail_illust.text = credits
		_detail_meta.text = "%s    /    Lv.%d    /    %s" % [str(entry.get("difficulty", "NORMAL")), int(entry.get("level", 1)), _format_time(float(entry.get("duration", 0.0)))]
	_update_best_line(str(entry.get("key", "")))
	_cover.texture = null if hidden else _cover_for(entry)
	_cover_empty.visible = not hidden and _cover.texture == null
	_cover_mask.visible = hidden
	# 神秘曲连背景也用默认星空，不能从模糊背景里把曲绘漏出来
	_set_background(null if hidden else _cover.texture)
	_apply_lock_visual(_selected_locked)


## 详情里的最好成绩：分数 + ACC（和结算界面同一套格式），没打过就写「暂无记录」
func _update_best_line(key: String) -> void:
	var record := App.best_record(key)
	if record.is_empty():
		_detail_best.text = "BEST    暂无记录"
		_detail_best.add_theme_color_override("font_color", BEST_EMPTY_COLOR)
		return
	_detail_best.text = "BEST    %08d    ·    %.2f%%" % [
		int(record.get("score", 0)),
		float(record.get("acc", 0.0)) * 100.0,
	]
	_detail_best.add_theme_color_override("font_color", BEST_COLOR)


## 没解锁的曲子：右侧曲绘压一个白锁 + 整个背景压暗，开始 / 自动演示都点不动。
## 锁下面写清楚要通关哪一首（按列表顺序，就是它的前一首）。
func _apply_lock_visual(locked: bool) -> void:
	_lock_layer.visible = locked
	_refresh_action_buttons()
	if locked:
		var need := _unlock_requirement_title(_selected)
		_lock_text.text = "通关「%s」后解锁" % need if need != "" else "未解锁"
	if _background_dim != null:
		if _lock_tween != null and _lock_tween.is_valid():
			_lock_tween.kill()
		var target := Color(0, 0, 0, LOCK_BG_DIM if locked else 0.0)
		if locked:
			_background_dim.color = target
		else:
			_lock_tween = create_tween()
			_lock_tween.tween_property(_background_dim, "color", target, 0.18)


## 解锁第 index 首要先通关哪一首（列表里的前一首）的曲名；没有就返回空串
func _unlock_requirement_title(index: int) -> String:
	if index <= 0 or index >= App.library.size():
		return ""
	return str(App.library[index - 1].get("title", ""))


## 「开始 / 自动演示」两个按钮的可用状态：
## 没解锁 / 空库 → 都点不动；「自动演示」还要先游玩过一次谱面。
func _refresh_action_buttons() -> void:
	var empty := App.library.is_empty()
	var autoplay_ready := App.autoplay_unlocked()
	_play_button.disabled = empty or _selected_locked
	_auto_button.disabled = empty or _selected_locked or not autoplay_ready
	_auto_button.tooltip_text = "自动演示 · A" if autoplay_ready else "游玩一次谱面解锁"
	_auto_button.add_theme_color_override("font_color", AUTO_READY_COLOR if autoplay_ready else AUTO_LOCKED_COLOR)
	_auto_button.add_theme_color_override("font_hover_color", AUTO_READY_COLOR if autoplay_ready else AUTO_LOCKED_COLOR)


func _set_background(texture: Texture2D) -> void:
	if texture == null:
		texture = preload("res://assets/menu_deep_space.png")
	texture = _soft_background(texture)
	if _background_tween != null and _background_tween.is_valid():
		_background_tween.kill()
	if _backgrounds[1].modulate.a > 0.5:
		_backgrounds[0].texture = _backgrounds[1].texture
	_backgrounds[1].texture = texture
	_backgrounds[1].modulate.a = 0.0
	_background_tween = create_tween()
	_background_tween.tween_property(_backgrounds[1], "modulate:a", 1.0, 0.32)


func _soft_background(texture: Texture2D) -> Texture2D:
	var key := texture.get_instance_id()
	if _background_cache.has(key):
		return _background_cache[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	if image.is_compressed():
		image.decompress()
	var factor := 96.0 / maxf(image.get_width(), image.get_height())
	image.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	var soft := ImageTexture.create_from_image(image)
	if _background_cache.size() >= 4:
		_background_cache.erase(_background_cache.keys()[0])
	_background_cache[key] = soft
	return soft


func _clear_detail() -> void:
	_preview.stop()
	_detail_title.text = "下一段旋律，等待开启"
	_detail_artist.text = "导入谱面后，曲绘与音乐会在这里相遇。"
	_detail_illust.text = ""
	_detail_meta.text = ""
	_detail_best.text = ""
	_cover.texture = null
	_cover_mask.visible = false
	_cover_empty.show()
	_selected_locked = false
	_selected_hidden = false
	_set_background(null)
	_apply_lock_visual(false)


func _format_time(seconds: float) -> String:
	var total := int(round(maxf(0, seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


func _play_selected(autoplay: bool) -> void:
	if _leaving or _selected < 0 or _selected >= App.library.size():
		return
	if _selected_locked:
		var need := _unlock_requirement_title(_selected)
		_show_toast("先通关「%s」才能玩这首" % need if need != "" else "这首还没解锁")
		return
	if autoplay and not App.autoplay_unlocked():
		_show_toast("游玩一次谱面解锁自动演示")
		return
	_play_entry(App.library[_selected], autoplay)


func _play_entry(entry: Dictionary, autoplay: bool) -> void:
	_preview.stop()
	_leaving = true
	if not App.play_entry(entry, autoplay):
		_leaving = false
		_show_toast(App.toast)
		App.toast = ""
		_preview.select(entry)


func _open_settings() -> void:
	_preview.stop()
	App.goto_settings()


func _back() -> void:
	_preview.stop()
	App.goto_menu()


func _open_chart_folder() -> void:
	DirAccess.make_dir_recursive_absolute("user://charts")
	OS.shell_open(ProjectSettings.globalize_path("user://charts"))


func _on_files_dropped(files: PackedStringArray) -> void:
	var messages: Array = []
	for file in files:
		var result := ChartSource.import_file(str(file))
		messages.append(str(result.get("message", "")))
	_preview.stop()
	_cover_cache.clear()
	_background_cache.clear()
	App.refresh_library()
	_refresh_list()
	_show_toast("  ·  ".join(messages))


func _show_toast(message: String) -> void:
	if message == "":
		return
	_toast.text = message
	_toast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _exit_tree() -> void:
	if is_instance_valid(_preview):
		_preview.stop()
