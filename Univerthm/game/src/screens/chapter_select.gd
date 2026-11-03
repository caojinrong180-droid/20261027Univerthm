extends Control
## 章节选择：主界面「开始游戏」之后的第一站，选完章节才进选曲页。
## 左边六本「书脊」（全部曲目 / 单曲 / 主线·序 / 主线·一 / 心跳电波！精选集 / 鼓立方精选集），
## 右边是当前章节的编号、名字和 CL / FC / AP 进度。现在只开放「全部曲目」和「主线·序」，其余锁着。
## 背景是 `assets/chose_bg.png` 一张铺满全屏的星空图（毛玻璃效果已经烘在图里了，运行时不再糊）。

const LockIcon = preload("res://src/ui/lock_icon.gd")

## 章节表：key 写进 App.chapter_key；spine = 书脊上竖着写的字；unlocked = false 的锁着不能进；
## cover = 书脊上的章节封面（不写就是纯色书脊）；index = 右边那行「章节 · ___」。
## 以后要按章节分谱面，改 App.chapter_charts() 就行，这里不用动。
const CHAPTERS := [
	{
		"key": "all",
		"index": "全部",
		"spine": "全部曲目",
		"name": "全部曲目",
		"unlocked": true,
		"cover": preload("res://assets/covers/ALL.png"),
	},
	{"key": "single", "index": "单曲", "spine": "单曲", "name": "单曲合集", "unlocked": false},
	{
		"key": "main_0",
		"index": "序",
		"spine": "主线·序",
		"name": "一切的开端",
		"unlocked": true,
		"cover": preload("res://assets/covers/C0.png"),
	},
	{"key": "main_1", "index": "一", "spine": "主线·一", "name": "尚未开放", "unlocked": false},
	{"key": "heartbeat", "index": "联动", "spine": "心跳电波！", "name": "心跳电波！精选集", "unlocked": false},
	{"key": "drum_cube", "index": "联动", "spine": "鼓立方", "name": "鼓立方精选集", "unlocked": false},
]

const SPINE_IDLE := Color(0.87451, 0.894118, 0.933333)
const SPINE_LOCKED := Color(0.4, 0.38, 0.47)
const CARD_IDLE := Color(0.031, 0.02, 0.062, 0.55)
const CARD_IDLE_EDGE := Color(0.85, 0.75, 1, 0.28)
const CARD_PICKED := Color(0.24, 0.1, 0.4, 0.8)
const CARD_PICKED_EDGE := Color(0.72, 0.51, 1, 0.85)
const CARD_LOCKED := Color(0.02, 0.015, 0.04, 0.45)
const CARD_LOCKED_EDGE := Color(0.4, 0.36, 0.5, 0.22)
const CARD_IDLE_FOCUS := Color(0.5, 0.36, 0.78, 0.6)

var _cards: Array[Button] = []
var _carousel: SpineCarousel
var _scrollbar: CarouselScrollbar
var _index_label: Label
var _name_label: Label
var _stats := {}
var _toast: Label
var _selected := 0
var _toast_tween: Tween


func _ready() -> void:
	theme = UiTheme.theme()
	_index_label = $Main/Body/Info/IndexLabel
	_name_label = $Main/Body/Info/NameLabel
	_stats = {
		"CL": $Main/Body/Info/StatCL,
		"FC": $Main/Body/Info/StatFC,
		"AP": $Main/Body/Info/StatAP,
	}
	_toast = $Footer/Row/Toast
	_toast.modulate.a = 0.0
	_carousel = $Main/Body/CardsColumn/Cards as SpineCarousel
	_scrollbar = $Main/Body/CardsColumn/Scroll as CarouselScrollbar
	if _scrollbar != null:
		_scrollbar.carousel = _carousel
	var back := $TopBar/Toolbar/BackButton as Button
	back.pressed.connect(_leaveToMenu)
	for i in CHAPTERS.size():
		var card := $Main/Body/CardsColumn/Cards.get_child(i) as ChapterSpine
		_cards.append(card)
		card.spine_text = str(CHAPTERS[i].get("spine", CHAPTERS[i].get("name", "")))
		if card is ChapterSpine:
			(card as ChapterSpine).cover = CHAPTERS[i].get("cover", null) as Texture2D
		if not _is_open(i):
			_add_lock_icon(card)
		card.mouse_entered.connect(_pick.bind(i))
		card.focus_entered.connect(_pick.bind(i))
		card.pressed.connect(_enter.bind(i))
	App.refresh_library()
	# 进界面这一次不滑动：书脊那排永远从最左边开始（选中的那本一定在前几本里）
	_pick(_default_index(), false)


func _default_index() -> int:
	for i in CHAPTERS.size():
		if str(CHAPTERS[i].get("key", "")) == App.chapter_key and _is_open(i):
			return i
	for i in CHAPTERS.size():
		if _is_open(i):
			return i
	return 0


func _is_open(index: int) -> bool:
	return index >= 0 and index < CHAPTERS.size() and bool(CHAPTERS[index].get("unlocked", false))


## 锁着的书脊顶部放一枚纯白小挂锁（贴在斜过去的书脊中线上）
func _add_lock_icon(card: Button) -> void:
	var lock := LockIcon.new()
	lock.name = "LockIcon"
	lock.color = Color(0.86, 0.84, 0.94, 0.5)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lock)
	lock.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var shift := 0.0
	if card is ChapterSpine:
		shift = (card as ChapterSpine).skew * 0.5
	lock.offset_left = shift - 11.0
	lock.offset_right = shift + 11.0
	lock.offset_top = 26.0
	lock.offset_bottom = 54.0


func _pick(index: int, allow_scroll := true) -> void:
	if index < 0 or index >= _cards.size():
		return
	_selected = index
	_refresh_cards()
	_refresh_info()
	# 书比屏幕多一本的时候，选到画面外那本要把它滑进来。
	# 进场景那一次不算（allow_scroll = false）：那时容器还没排好，一滑就滑到中间去了。
	if allow_scroll and _carousel != null:
		_carousel.ensure_visible(index)
	if is_inside_tree() and not _cards[index].has_focus():
		_cards[index].grab_focus()


func _refresh_cards() -> void:
	for i in _cards.size():
		var card := _cards[i]
		var open := _is_open(i)
		var picked := i == _selected
		var fill := CARD_LOCKED if not open else (CARD_PICKED if picked else CARD_IDLE)
		var edge := CARD_LOCKED_EDGE if not open else (CARD_PICKED_EDGE if picked else CARD_IDLE_EDGE)
		if card is ChapterSpine:
			var spine := card as ChapterSpine
			spine.fill = fill
			spine.edge = edge
			spine.edge_width = 1.6 if picked else 1.0
			spine.focus_edge = CARD_PICKED_EDGE if picked else CARD_IDLE_FOCUS
			spine.text_color = SPINE_IDLE if open else SPINE_LOCKED
		var lock := card.get_node_or_null("LockIcon")
		if lock != null:
			lock.visible = not open
			lock.modulate.a = 1.0 if picked else 0.65


func _refresh_info() -> void:
	var chapter: Dictionary = CHAPTERS[_selected]
	_index_label.text = "章节 · %s" % str(chapter.get("index", ""))
	_name_label.text = str(chapter.get("name", ""))
	var open := _is_open(_selected)
	var progress := App.chapter_progress(str(chapter.get("key", "all")))
	var total := int(progress.get("total", 0))
	for row in ["CL", "FC", "AP"]:
		var label: Label = _stats[row]
		if not open:
			label.text = "%s   —" % row
			continue
		label.text = "%s   %d/%d" % [row, int(progress.get(row.to_lower(), 0)), total]


func _enter(index: int) -> void:
	if index < 0 or index >= CHAPTERS.size():
		return
	if not _is_open(index):
		_show_toast("「%s」还没开放" % str(CHAPTERS[index].get("name", "")))
		return
	App.chapter_key = str(CHAPTERS[index].get("key", "all"))
	App.goto_select()


func _leaveToMenu() -> void:
	App.goto_menu()


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	match key:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_leaveToMenu()
		KEY_LEFT, KEY_UP:
			get_viewport().set_input_as_handled()
			_pick(wrapi(_selected - 1, 0, _cards.size()))
		KEY_RIGHT, KEY_DOWN:
			get_viewport().set_input_as_handled()
			_pick(wrapi(_selected + 1, 0, _cards.size()))
		KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_enter(_selected)
