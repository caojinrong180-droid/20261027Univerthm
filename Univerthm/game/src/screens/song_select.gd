extends Control
## 极简曲绘选曲：点击选择试听，独立确认后开始游玩。

const Neon = preload("res://src/ui/neon_ui.gd")
const Preview = preload("res://src/audio/song_preview.gd")
const EntryWarning = preload("res://src/ui/first_entry_warning.gd")
const StoryReader = preload("res://src/ui/story_reader.gd")
const ChaptersData = preload("res://src/core/chapters.gd")
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
## 底栏提示：普通列表 / 序章地图两套
const VIEW_HINT_LIST := "↑↓ 选择   ·   Enter 开始   ·   A 自动演示"
const VIEW_HINT_MAP := "拖动平移   ·   滚轮缩放   ·   点击选中   ·   点收藏品读剧情   ·   Tab 切列表"

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
## 进入曲目那一声：素材 `audio/enter_the_song.wav`（源文件 sound/Enter_the_song.wav）
const ENTRY_SOUND = preload("res://audio/enter_the_song.wav")
## 点地图上的剧情收藏品那一声：素材 `audio/info.wav`（源文件 sound/Info.wav）
const INFO_SOUND = preload("res://audio/info.wav")
## 过场里背景那层虚化（抄屏 + 磨砂）
const ENTRY_BLUR_SHADER = preload("res://shaders/entry_bg_blur.gdshader")
## 进入过场：只把「曲绘 + 曲名」这两样从详情板的位置飞到屏幕正中并放大，其它信息不进过场
const ENTRY_COVER_RATIO := 0.44   # 正中曲绘边长 = 屏高 × 这个
const ENTRY_TITLE_ZOOM := 1.65    # 曲名放大到几倍（32px → 约 53px）
const ENTRY_FLY_TIME := 0.46      # 飞过去 + 放大（背景同时虚化）的时长
const ENTRY_HOLD_TIME := 0.16     # 停一下再压黑
const ENTRY_BLACK_TIME := 0.4     # 黑场压上来的时长
## 地图模式：右侧详情滑出来多快；收起时挪出去多远由 _sheet_hide_distance() 现算（SHEET_HIDE 只是下限）
const SHEET_HIDE := 320.0
const SHEET_SPEED := 7.0
## 地图模式的固定背景（章节地图原图，不换成曲绘、也不跟着地图拖动）
const MAP_BG_PATH := "res://assets/C0_Map.png"

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
## 列表顶上那行标题（显示当前章节名，不是写死的一句话）
var _library_title: Label
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
## 曲绘背景那套模糊材质（地图模式会临时摘掉，切回列表再装回去）
var _bg_materials: Array = []
var _background_tween: Tween
var _list_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
## 左边的曲目列表（普通视图）
var _library: Control
## 左边的曲目地图（序章专用视图，方框 = 曲绘）
var _map: Control
var _view_button: Button
var _show_map := false
## 地图模式下右侧详情没选中前先藏着，选中才滑出来
var _sheet_open := false
var _sheet_offset := 0.0
var _sheet_base := Vector2.ZERO
## 详情面板该停在哪记下来没有（等容器排好版才记，不然会把它摆错位置）
var _base_ready := false
## 右侧「曲绘糊上去」的衬底（地图模式选中后淡入）。
## 神秘曲未揭晓时曲绘本身就是纯黑占位（assets/none.jpg），糊出来自然一片黑，不需要额外压板。
var _sheet_back: TextureRect
var _leaving := false
## 神秘曲第一次踏入的红色警告（点「是」之后才真的进谱面）
var _warning: Node
## 警告框确认前先记下这次要进哪首 / 是不是自动演示
var _pending_entry := {}
var _pending_autoplay := false
## 进入谱面的过场：把「详情板」整块挪到屏幕中央 → 音效 → 稍微放大 → 全黑 → 切场景
var _entry_black: ColorRect
var _entry_cover: TextureRect
var _entry_title: Label
var _entry_capture: BackBufferCopy
var _entry_blur: ColorRect
var _entry_player: AudioStreamPlayer
var _info_player: AudioStreamPlayer
var _entry_tween: Tween
var _entering := false
## 点地图上的剧情收藏品时用的阅读浮层
var _reader: Node

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
	_library_title = $Main/MusicBody/Library/HeadPad/Head/LibraryTitle
	# 顶上的标题跟着当前章节走（「全部曲目」/「主线·序 ｜ 一切的开端」…）
	if _library_title != null:
		_library_title.text = ChaptersData.display_title(App.chapter_key)
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
	_bg_materials = [_background_a.material, _background_b.material]
	_library = $Main/MusicBody/Library
	_map = $MapPanel
	_view_button = $ViewToggle
	_build_sheet_backdrop()

	# 滚动条是 ScrollContainer 的内部节点，皮肤只能在运行时套
	for scroll in [_list_scroll, _detail_scroll]:
		Neon.style_scroll(scroll)
	_settings_button.pressed.connect(_open_settings)
	_back_button.pressed.connect(_back)
	_view_button.pressed.connect(_toggle_view)
	_map.focused.connect(_on_map_focused)
	_map.activated.connect(_on_map_activated)
	_map.blank_clicked.connect(_on_map_blank)
	_map.story_clicked.connect(_on_map_story)
	_import_button.pressed.connect(_open_chart_folder)
	_play_button.pressed.connect(_play_selected.bind(false))
	_auto_button.pressed.connect(_play_selected.bind(true))
	# 地图是序章（主线·序）独占：其它章节只有普通列表，连切换按钮都不显示
	_show_map = _map_available()

	_preview = Preview.new()
	_preview.name = "SongPreview"
	add_child(_preview)
	# 剧情阅读浮层：地图上点收藏品直接在这里读（垫在警告框下面）
	_reader = StoryReader.new()
	_reader.name = "StoryReader"
	add_child(_reader)
	# 红色警告框盖在最上层：关着的时候 mouse_filter 也跟着藏起来
	_warning = EntryWarning.new()
	_warning.name = "FirstEntryWarning"
	add_child(_warning)
	_warning.chosen.connect(_on_warning_chosen)
	_build_entry_fx()
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
	# 红色警告框开着的时候，按键归它管（Esc = 否），别顺手退回主界面
	if _warning != null and _warning.is_open():
		return
	# 在读剧情：按键归阅读浮层（Esc 只会关掉它）
	if _reader != null and _reader.is_open():
		return
	# 正在变黑 / 正在切场景：这一刻的按键全部丢掉
	if _leaving:
		return
	if event.keycode not in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_A, KEY_F5, KEY_S, KEY_ESCAPE, KEY_TAB]:
		return
	# 场景切换会立即移除当前节点，必须在导航前消费按键。
	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_UP, KEY_LEFT:
			if not _rows.is_empty():
				_focus_row(wrapi(_selected - 1, 0, _rows.size()))
		KEY_DOWN, KEY_RIGHT:
			if not _rows.is_empty():
				_focus_row(wrapi(_selected + 1, 0, _rows.size()))
		KEY_TAB:
			_toggle_view()
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
	_sync_map()
	_focus_row(selected_index)
	_layout.call_deferred()


## 地图是不是这个章节才有的：**地图是序章（main_0）独占**，
## 「全部曲目」这类章节只有普通列表，连切换按钮都不给。
func _map_available() -> bool:
	return App.chapter_key == "main_0"


## 左侧视图：地图（序章）⇄ 普通列表
## 地图只有序章有；序章里**解锁全部曲目之后**才允许切到普通列表（这是设计，不是 bug）。
func _toggle_view() -> void:
	if not _map_available():
		return
	if _show_map and not App.all_charts_unlocked():
		_show_toast("解锁全部曲目后可切换普通列表")
		return
	_show_map = not _show_map
	_apply_view()


func _apply_view() -> void:
	# 没有地图的章节（全部曲目等）永远是普通列表
	if not _map_available():
		_show_map = false
	# 记录被清掉（删档）之后普通列表就不该再开着：退回地图
	elif not _show_map and not App.all_charts_unlocked():
		_show_map = true
	if _library != null:
		_library.visible = not _show_map
	if _map != null:
		_map.visible = _show_map
	if _view_button != null:
		# 没有地图的章节直接把「地图 / 普通列表」按钮藏起来
		_view_button.visible = _map_available()
		_view_button.text = "普通列表" if _show_map else "地图"
		var list_ready := App.all_charts_unlocked()
		_view_button.disabled = _show_map and not list_ready
		_view_button.tooltip_text = "切换地图 / 普通列表 · Tab" if not _view_button.disabled else "解锁全部曲目后可切换普通列表"
	var hint := get_node_or_null("Footer/FooterHint") as Label
	if hint != null:
		hint.text = VIEW_HINT_MAP if _show_map else VIEW_HINT_LIST
	# 地图模式下详情只占右边一半（滑出来的那张板），列表模式回到整列
	if _detail_scroll != null:
		if _show_map:
			_body.alignment = BoxContainer.ALIGNMENT_END
			_detail_scroll.size_flags_horizontal = Control.SIZE_SHRINK_END
			_detail_scroll.custom_minimum_size.x = maxf(420.0, size.x * 0.46)
		else:
			_body.alignment = BoxContainer.ALIGNMENT_BEGIN
			_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_detail_scroll.custom_minimum_size.x = 0.0
		_base_ready = false
	# 地图模式：右边详情先收起来（这一步直接摆好，不放动画），等玩家点了方框再滑出来；
	# 普通列表模式详情常驻。点空白收回时才走滑动动画。
	if _show_map:
		_set_sheet(false, false)
		# 背景固定成章节地图（原图、不磨砂、不跟着拖动）
		_set_map_background()
	else:
		_set_sheet(true, false)
		# 从地图切回列表：模糊材质装回去，背景恢复成当前选中曲目的曲绘
		_restore_background_materials()
		_set_background(_cover.texture if _cover != null else null)
	if _map != null and _show_map:
		_map.focus_node(_selected)


## 右侧详情「滑出来 / 收回去」：地图模式下默认藏在右边屏幕外。
## animate = false 只用在刚切进地图那一下（直接摆到收起的位置，不放动画）。
func _set_sheet(open: bool, animate := true) -> void:
	_sheet_open = open
	if not animate:
		_sheet_offset = 0.0 if open else _sheet_hide_distance()
		_apply_sheet(0.0)
	set_process(true)


## 详情板要藏到屏幕外多远：足够把「它自己的整块宽度 + 右边距」推出画面。
## 以前固定 320，而板子有 588 宽还会被容器摆在 579 的位置 —— 收起之后右边 380 像素
## 是「看不见但照吃点击」的死区，点地图上那一片的方框就会像没反应。
func _sheet_hide_distance() -> float:
	if _detail_scroll == null:
		return SHEET_HIDE
	var reach := maxf(0.0, size.x - _sheet_base.x)      # base 还没量出来时按整屏算
	return maxf(SHEET_HIDE, maxf(_detail_scroll.size.x, reach) + 28.0)


## 右侧那半边「曲绘糊上去」的衬底：地图模式选中曲子后淡入（神秘曲不用它，见 _build_sheet_scrim）
func _build_sheet_backdrop() -> void:
	_sheet_back = TextureRect.new()
	_sheet_back.name = "DetailSheetBackdrop"
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/cover_blur.gdshader")
	_sheet_back.material = material
	_sheet_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sheet_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_sheet_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_back.anchor_left = 0.46
	_sheet_back.anchor_right = 1.0
	_sheet_back.anchor_bottom = 1.0
	_sheet_back.modulate.a = 0.0
	add_child(_sheet_back)
	move_child(_sheet_back, _map.get_index() + 1)


## 进入过场要用的东西：背景虚化层 + 最上层的黑幕 + 合成出来的进入音效
## 顺序就是画序：抄屏 → 虚化层 → （曲绘 / 曲名插到黑幕前面）→ 黑幕
func _build_entry_fx() -> void:
	_entry_capture = BackBufferCopy.new()
	_entry_capture.name = "EntryCapture"
	_entry_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_entry_capture)
	_entry_blur = ColorRect.new()
	_entry_blur.name = "EntryBlur"
	var material := ShaderMaterial.new()
	material.shader = ENTRY_BLUR_SHADER
	_entry_blur.material = material
	_entry_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_blur.color = Color(1, 1, 1, 1)
	_entry_blur.modulate.a = 0.0
	UiKit.full_rect(_entry_blur)
	add_child(_entry_blur)
	_entry_black = ColorRect.new()
	_entry_black.name = "EntryBlack"
	_entry_black.color = Color(0, 0, 0, 0)
	_entry_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(_entry_black)
	add_child(_entry_black)
	_entry_player = AudioStreamPlayer.new()
	_entry_player.name = "EntryStinger"
	_entry_player.stream = ENTRY_SOUND
	add_child(_entry_player)
	_info_player = AudioStreamPlayer.new()
	_info_player.name = "InfoSound"
	_info_player.stream = INFO_SOUND
	add_child(_info_player)


func _process(delta: float) -> void:
	if _detail_scroll == null:
		return
	# 等容器把详情排到它该在的位置，再把那个位置记成「滑出来的终点」
	if not _base_ready:
		if _detail_scroll.size.x <= 0.0:
			return
		_sheet_base = _detail_scroll.position
		_base_ready = true
	var target := 0.0 if _sheet_open else _sheet_hide_distance()
	var step := minf(1.0, delta * SHEET_SPEED)
	_sheet_offset = lerpf(_sheet_offset, target, step)
	if absf(_sheet_offset - target) < 0.5:
		_sheet_offset = target
		_apply_sheet(0.0)
		set_process(false)
		return
	_apply_sheet(delta)


## 把当前的滑动位置 / 透明度刷到详情和那半边背景上；delta <= 0 时背景直接到位
func _apply_sheet(delta: float) -> void:
	if _detail_scroll == null:
		return
	# 收起时这块板是透明的，但控件还在 —— 必须让它别接鼠标，
	# 否则地图右边会留一条「看不见、点了也没用」的死区（点方框没反应就是它）
	_detail_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if _sheet_open else Control.MOUSE_FILTER_IGNORE
	# 位置往右推出去，同时淡掉（容器重排会覆盖位置，所以每帧重新 apply）
	_detail_scroll.position = _sheet_base + Vector2(_sheet_offset, 0.0)
	_detail_scroll.modulate.a = 1.0 - clampf(_sheet_offset / maxf(1.0, _sheet_hide_distance()), 0.0, 1.0)
	# 右半边衬底：糊的就是当前曲绘。神秘曲的曲绘本身已经是纯黑占位（none.jpg），
	# 所以这里不用再单独压黑板，糊出来自然是一片黑。
	if _sheet_back != null:
		var back_target := 0.92 if _sheet_open else 0.0
		var fall := minf(1.0, delta * SHEET_SPEED) if delta > 0.0 else 1.0
		_sheet_back.modulate.a = lerpf(_sheet_back.modulate.a, back_target, fall)
		var cover := _cover.texture if _cover != null else null
		var material := _sheet_back.material as ShaderMaterial
		if cover != null and material != null:
			material.set_shader_parameter("tex", cover)
		_sheet_back.texture = cover


## 把当前曲库 / 解锁状态 / 收藏品搜集情况喂给地图
func _sync_map() -> void:
	if _map == null:
		return
	var stories: Array = []
	for i in App.library.size():
		stories.append(App.story_collected_for_chart(i))
	_map.build(App.library, _row_locked, stories, _row_hidden)
	_map.focus_node(_selected)
	_apply_view()


func _on_map_focused(index: int) -> void:
	if index < 0 or index >= App.library.size():
		return
	_focus_row(index)
	_set_sheet(true)


func _on_map_activated(index: int) -> void:
	_focus_row(index)
	_play_selected(false)


## 点地图空白处：右侧详情收回去
func _on_map_blank() -> void:
	if _show_map and _sheet_open:
		_set_sheet(false)


## 点地图上的剧情收藏品：直接开阅读浮层，不用跳去收藏品界面
func _on_map_story(index: int) -> void:
	var story := App.story_for_chart(index)
	if story.is_empty():
		_show_toast("这首还没有配剧情收藏品")
		return
	if _reader != null:
		_play_info_sound()
		_reader.open(story)


## 「神秘曲」：第 3 首在打出成绩之前，所有信息都是 ???、曲绘换成纯黑占位（assets/none.jpg）。
func _is_hidden_song(index: int) -> bool:
	if index < 0 or index != SECRET_INDEX or index >= App.library.size():
		return false
	return App.is_hidden_chart(str(App.library[index].get("key", "")))


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
	if not _show_map:
		_rows[index].grab_focus()
	if changed and _selected != index:
		_on_row_focused(App.library[index], index)
	if _show_map and _map != null:
		_map.focus_node(index)


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
	if _map != null and _show_map:
		_map.focus_node(index)
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


## 曲绘：神秘曲没揭晓时换成纯黑占位（assets/none.jpg），打出成绩后自然还是走缓存里的真曲绘。
func _cover_for(entry: Dictionary) -> Texture2D:
	var key := str(entry.get("key", ""))
	if App.is_hidden_chart(key):
		return App.none_cover()
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
		# 神秘曲：曲名 / 作者 / staff / 难度 / 时长全都遮掉（曲绘走占位图，纯黑）
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
	# 未揭晓时 _cover_for() 直接给纯黑占位，不用再挂一层遮罩
	_cover.texture = _cover_for(entry)
	_cover_empty.visible = not hidden and _cover.texture == null
	_cover_mask.visible = false
	_set_background(_cover.texture)
	_apply_lock_visual(_selected_locked)
	# 详情板滑到位之后 _process 会自我关掉（省得每帧空转），
	# 所以换歌时右半边那层「糊曲绘」得在这儿手动刷一次，否则它会一直停在上一首上。
	if _base_ready:
		_apply_sheet(0.0)


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
func _apply_lock_visual(locked: bool) -> void:
	_lock_layer.visible = locked
	_refresh_action_buttons()
	if locked:
		var need := _unlock_requirement_title(_selected)
		_lock_text.text = "通关「%s」后解锁" % need if need != "" else "未解锁"
	if _background_dim != null:
		if _lock_tween != null and _lock_tween.is_valid():
			_lock_tween.kill()
		# 地图模式的背景是章节地图，别因为选中了没解锁的曲子就把它压暗
		var target := Color(0, 0, 0, LOCK_BG_DIM if locked and not _show_map else 0.0)
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
func _refresh_action_buttons() -> void:
	var empty := App.library.is_empty()
	var autoplay_ready := App.autoplay_unlocked()
	_play_button.disabled = empty or _selected_locked
	_auto_button.disabled = empty or _selected_locked or not autoplay_ready
	_auto_button.tooltip_text = "自动演示 · A" if autoplay_ready else "游玩一次谱面解锁"
	_auto_button.add_theme_color_override("font_color", AUTO_READY_COLOR if autoplay_ready else AUTO_LOCKED_COLOR)
	_auto_button.add_theme_color_override("font_hover_color", AUTO_READY_COLOR if autoplay_ready else AUTO_LOCKED_COLOR)


func _set_background(texture: Texture2D) -> void:
	# 地图模式背景是固定的章节地图：选曲、切歌都不换成曲绘（见 _set_map_background）
	if _show_map:
		return
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


## 地图模式：背景换成章节地图（原图，不磨砂、也不跟着地图拖动）。
## 两张背景层都填同一张，免得从曲绘切过来时闪一下旧的模糊图；
## 曲绘那套模糊材质在场景里挂着，这里先摘掉，否则地图会被糊掉。
func _set_map_background() -> void:
	var texture := load(MAP_BG_PATH) as Texture2D
	if texture == null:
		return
	if _background_tween != null and _background_tween.is_valid():
		_background_tween.kill()
	for layer in _backgrounds:
		layer.material = null
		layer.texture = texture
		layer.modulate.a = 1.0


## 从地图切回列表：把曲绘那套模糊材质装回去
func _restore_background_materials() -> void:
	for i in _backgrounds.size():
		if i < _bg_materials.size():
			_backgrounds[i].material = _bg_materials[i]


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
	if _warning != null and _warning.is_open():
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
	# 神秘曲的第一次踏入：先问「踏出这一步就不能反悔了」，选「否」留在列表。
	# 自动演示不算「踏入」（不记成绩、不落盘），所以不弹这块警告，直接看演出。
	if not autoplay and App.needs_first_entry(str(entry.get("key", ""))):
		_pending_entry = entry
		_pending_autoplay = autoplay
		_preview.stop()
		if _warning != null:
			_warning.open()
		return
	_start_entry(entry, autoplay)


## 警告框选完：否 → 什么都不做（人还留在选曲列表），是 → 真的进谱面
func _on_warning_chosen(confirmed: bool) -> void:
	var entry: Dictionary = _pending_entry
	var autoplay := _pending_autoplay
	_pending_entry = {}
	_pending_autoplay = false
	if not confirmed or entry.is_empty():
		if _selected >= 0 and _selected < _rows.size():
			_rows[_selected].grab_focus()
			# 神秘曲 / 未解锁的曲子本来就不试听，取消之后也别顺手放出来
			if not _selected_locked and not _selected_hidden:
				_preview.select(App.library[_selected])
		return
	# 是：走和普通进入同一套过场，但那一声换成「特殊进入音」（App.play_final_entry_sound()）
	_start_entry(entry, autoplay, true)


## 进入谱面的过场：
##   ① 曲绘 + 曲名飞到屏幕正中并放大，背景跟着虚化；
##   ② 响一声（普通谱面是上行的合成音；神秘曲第一次踏入换成 `audio/enter_the_final.wav`）；
##   ③ 停一下，黑场压上来；
##   ④ 全黑之后才真的换场景（谱面那侧再从黑里淡出来）。
func _start_entry(entry: Dictionary, autoplay: bool, special_sound := false) -> void:
	_preview.stop()
	_leaving = true
	_entering = true
	if special_sound:
		if App != null:
			App.play_final_entry_sound()
	else:
		_play_entry_sound()
	_run_entry_intro(entry, autoplay)


## 进入曲目那一声（普通谱面）：素材 audio/enter_the_song.wav
func _play_entry_sound() -> void:
	if _entry_player == null or _entry_player.stream == null:
		return
	var volume := 1.0
	if App.settings != null:
		volume = clampf(App.settings.music_volume, 0.0, 1.0)
	_entry_player.volume_db = linear_to_db(maxf(0.001, volume)) - 1.0
	_entry_player.play()


## 点地图上的剧情收藏品那一声：素材 audio/info.wav
func _play_info_sound() -> void:
	if _info_player == null or _info_player.stream == null:
		return
	var volume := 1.0
	if App.settings != null:
		volume = clampf(App.settings.music_volume, 0.0, 1.0)
	_info_player.stop()
	_info_player.volume_db = linear_to_db(maxf(0.001, volume)) - 1.0
	_info_player.play()


func _run_entry_intro(entry: Dictionary, autoplay: bool) -> void:
	if _detail_scroll == null:
		_launch_entry(entry, autoplay)
		return
	# 详情板先确保是展开的（地图模式用 Enter 直接开始时它可能还收着）
	_set_sheet(true, false)
	# 开始 / 自动演示两颗按钮不属于「歌曲信息」，过场里隐掉（留着占位，避免重排）
	for button in [_play_button, _auto_button]:
		if button != null:
			button.modulate.a = 0.0
	set_process(false)                       # 别让 _apply_sheet 每帧改回原位
	if _entry_tween != null and _entry_tween.is_valid():
		_entry_tween.kill()

	# 过场只留曲绘 + 曲名：先把这两样从详情板的位置原样接过来，详情板自己隐掉
	_build_entry_stage()
	_detail_scroll.modulate.a = 0.0
	if _sheet_back != null:
		_sheet_back.modulate.a = 0.0

	# 背景虚化层：开始抄屏，然后跟着飞行一起淡进来
	if _entry_capture != null:
		_entry_capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	if _entry_blur != null:
		_entry_blur.modulate.a = 0.0

	var cover_size := clampf(size.y * ENTRY_COVER_RATIO, 240.0, 520.0)
	var cover_center := Vector2(size.x * 0.5, size.y * 0.44)
	var title_center := Vector2(size.x * 0.5, cover_center.y + cover_size * 0.5 + 46.0)
	_entry_cover.modulate.a = 1.0
	_entry_title.modulate.a = 1.0
	_entry_title.pivot_offset = _entry_title.size * 0.5

	_entry_tween = create_tween().set_parallel(true)
	_entry_tween.tween_property(_entry_cover, "position", cover_center - Vector2(cover_size, cover_size) * 0.5, ENTRY_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(_entry_cover, "size", Vector2(cover_size, cover_size), ENTRY_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(_entry_title, "position", title_center - _entry_title.size * 0.5, ENTRY_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(_entry_title, "scale", Vector2(ENTRY_TITLE_ZOOM, ENTRY_TITLE_ZOOM), ENTRY_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 背景同时虚化：虚化层 alpha 0 → 1（它叠在抄下来的屏上，曲绘/曲名画在它上面所以不糊）
	if _entry_blur != null:
		_entry_tween.tween_property(_entry_blur, "modulate:a", 1.0, ENTRY_FLY_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 停一下，再压黑（黑幕是最后加的子节点，盖在曲绘/曲名上面）
	_entry_tween.chain().tween_interval(ENTRY_HOLD_TIME)
	if _entry_black != null:
		_entry_tween.chain().tween_property(_entry_black, "color:a", 1.0, ENTRY_BLACK_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_entry_tween.chain().tween_callback(_on_intro_finished.bind(entry, autoplay))


## 过场用的两样东西：曲绘 + 曲名。起点直接取详情板里那一块的实际位置，
## 所以看上去就是「它俩从板上脱离、飞到屏幕正中」。
func _build_entry_stage() -> void:
	if _entry_cover == null:
		_entry_cover = TextureRect.new()
		_entry_cover.name = "EntryCover"
		_entry_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_entry_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_entry_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(_entry_cover)
		# 黑幕是最后加进来的，曲绘要压在它下面才盖得住
		if _entry_black != null:
			move_child(_entry_cover, _entry_black.get_index())
	if _entry_title == null:
		_entry_title = Label.new()
		_entry_title.name = "EntryTitle"
		_entry_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_entry_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_entry_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_entry_title)
		if _entry_black != null:
			move_child(_entry_title, _entry_black.get_index())

	var cover_rect := _cover_frame.get_global_rect()
	if cover_rect.size.x < 8.0:
		cover_rect = Rect2(Vector2(size.x * 0.5 - 126.0, size.y * 0.3), Vector2(252.0, 252.0))
	_entry_cover.texture = _cover.texture
	_entry_cover.position = cover_rect.position
	_entry_cover.size = cover_rect.size
	_entry_cover.scale = Vector2.ONE

	var title_rect := _detail_title.get_global_rect()
	_entry_title.text = _detail_title.text
	_entry_title.add_theme_font_override("font", _detail_title.get_theme_font("font"))
	_entry_title.add_theme_font_size_override("font_size", _detail_title.get_theme_font_size("font_size"))
	_entry_title.add_theme_color_override("font_color", _detail_title.get_theme_color("font_color"))
	# 不折行：直接按这行字本来的大小摆，飞过去的时候才好算中心
	_entry_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_entry_title.size = _entry_title.get_minimum_size()
	_entry_title.position = Vector2(
		title_rect.position.x + (title_rect.size.x - _entry_title.size.x) * 0.5,
		title_rect.position.y
	)
	_entry_title.scale = Vector2.ONE


func _on_intro_finished(entry: Dictionary, autoplay: bool) -> void:
	_entering = false
	_launch_entry(entry, autoplay)


## 真正换场景（屏幕此刻已经是全黑，所以让谱面那边从黑里淡出来）
func _launch_entry(entry: Dictionary, autoplay: bool) -> void:
	_entering = false
	if not App.play_entry(entry, autoplay, true):
		_leaving = false
		if _entry_tween != null and _entry_tween.is_valid():
			_entry_tween.kill()
		if _detail_scroll != null:
			_detail_scroll.modulate.a = 1.0
			_detail_scroll.scale = Vector2.ONE
			_detail_scroll.position = _sheet_base
		if _entry_cover != null:
			_entry_cover.modulate.a = 0.0
		if _entry_title != null:
			_entry_title.modulate.a = 0.0
		if _entry_blur != null:
			_entry_blur.modulate.a = 0.0
		if _entry_capture != null:
			_entry_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		set_process(true)
		for button in [_play_button, _auto_button]:
			if button != null:
				button.modulate.a = 1.0
		if _entry_black != null:
			_entry_black.color = Color(0, 0, 0, 0)
		_show_toast(App.toast)
		App.toast = ""
		_preview.select(entry)


func _open_settings() -> void:
	_preview.stop()
	App.goto_settings()


func _back() -> void:
	_preview.stop()
	App.goto_chapters()


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
