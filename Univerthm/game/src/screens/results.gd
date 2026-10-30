extends Control
## 结算界面：沿用设置 / 个人资料 / 收藏那套宇宙霓虹语言——

const Neon = preload("res://src/ui/neon_ui.gd")

const MUSIC_PATH := "res://audio/result.mp3"
const MUSIC_FADE_IN := 0.9
const MUSIC_FADE_OUT := 0.22
## 中段滑入：从舞台右边界外滑回，TRANS_CUBIC + EASE_OUT 就是「先快后慢」
const SLIDE_SECONDS := 0.55
const SLIDE_OVERSHOOT := 60.0

const RULE := Color("624480")
const RULE_SOFT := Color("543574")
const CAPTION_EN := Color("88769d")
const CELL_FILL := Color(0.025, 0.018, 0.05, 0.82)
const CELL_EDGE := Color("59406d")
const QUIET_FILL := Color(0.02, 0.014, 0.04, 0.72)

var _result: Dictionary = {}
var _stage: Control
var _slider: Control
var _scroll: ScrollContainer
var _music: AudioStreamPlayer
var _leaving := false


func _ready() -> void:
	theme = UiTheme.theme()
	_result = App.last_result
	if _result.is_empty():
		App.goto_select()
		return
	_build()
	_start_music()
	_slide_in()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# 场景切换会立即移除当前节点，必须在导航前消费按键。
	match (event as InputEventKey).keycode:
		KEY_R:
			get_viewport().set_input_as_handled()
			_leave(App.retry)
		KEY_ESCAPE, KEY_Q:
			get_viewport().set_input_as_handled()
			_leave(App.goto_select)


# --------------------------------------------------------------------------- #
# 声音 / 进出场
# --------------------------------------------------------------------------- #

func _start_music() -> void:
	var source := load(MUSIC_PATH) as AudioStream
	if source == null:
		push_warning("结算音乐无法载入：" + MUSIC_PATH)
		return
	_music = AudioStreamPlayer.new()
	_music.name = "ResultMusic"
	_music.stream = source
	_music.volume_db = -60.0
	add_child(_music)
	_music.play()
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", _music_db(), MUSIC_FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _music_db() -> float:
	var volume := 1.0 if App.settings == null else clampf(App.settings.music_volume, 0.0001, 1.0)
	return linear_to_db(volume)


## 中段从舞台右边界外滑回原位；动的是 offset 而不是 position，窗口缩放后也不会错位。
func _slide_in() -> void:
	if _stage == null or _slider == null:
		return
	# 等容器完成第一轮排布，才知道舞台有多宽（最多等 10 帧，免得卡在极端情况里）。
	var guard := 0
	while is_inside_tree() and _stage.size.x <= 1.0 and guard < 10:
		guard += 1
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var travel := _stage.size.x + SLIDE_OVERSHOOT
	_slider.offset_left = travel
	_slider.offset_right = travel
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_slider, "offset_left", 0.0, SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_slider, "offset_right", 0.0, SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 离场：音乐先淡出 0.22 秒再换场景，避免直接被切掉。
func _leave(action: Callable) -> void:
	if _leaving:
		action.call()
		return
	_leaving = true
	if _music == null or not _music.playing:
		action.call()
		return
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", -60.0, MUSIC_FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(action)


func _exit_tree() -> void:
	if _music != null and is_instance_valid(_music):
		_music.stop()


# --------------------------------------------------------------------------- #
# 搭界面
# --------------------------------------------------------------------------- #

func _build() -> void:
	Neon.background(self)
	Neon.topbar(self, "结算")
	Neon.footer(self, "Enter 触发当前按钮  ·  R 重试  ·  Esc 选曲", "RESULT / PERFORMANCE")
	var head_back := find_child("BackButton", true, false) as Button
	if head_back != null:
		head_back.pressed.connect(func(): _leave(App.goto_select))

	var panel := Neon.content(self)
	var column := UiKit.vbox(8)
	panel.add_child(column)
	column.add_child(Neon.heading("结算", "RESULT / PERFORMANCE", "每一次敲击，都在这里留下痕迹。"))

	# 舞台负责裁剪（滑入时不能漏到面板外面），滑块负责位移，滚动容器负责溢出。
	_stage = Control.new()
	_stage.name = "SlideStage"
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	column.add_child(_stage)

	_slider = Control.new()
	_slider.name = "SlideBody"
	_slider.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.add_child(_slider)
	_slider.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_scroll = ScrollContainer.new()
	_scroll.name = "ResultScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_slider.add_child(_scroll)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Neon.style_scroll(_scroll)

	var body := UiKit.vbox(8)
	body.name = "ResultBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)
	body.add_child(_build_track())
	body.add_child(Neon.section("成绩", "UNIVERTHM / SCORE"))
	body.add_child(_build_score())
	body.add_child(Neon.section("判定", "JUDGEMENT"))
	body.add_child(_build_counts())
	body.add_child(_build_early_late())

	column.add_child(UiKit.rule(RULE))
	column.add_child(_build_actions())
	var drop := _build_story_drop()
	if drop != null:
		column.add_child(drop)


## 曲目：左边曲名 / 作者 / 谱师与曲绘，右边难度、等级、时长、自动演示。
func _build_track() -> Control:
	var row := UiKit.hbox(16)
	var texts := UiKit.vbox(2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)

	var title := Neon.label(str(_result.get("title", "未命名谱面")), 22, Neon.LIGHT, true)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(title)
	var artist := str(_result.get("artist", ""))
	if artist != "":
		texts.add_child(Neon.label(artist, 12, Neon.MUTED))
	var credits := "谱师  " + str(_result.get("charter", "—"))
	var illustrator := str(_result.get("illustrator", ""))
	if illustrator != "":
		credits += "    /    曲绘  " + illustrator
	texts.add_child(Neon.label(credits, 10, CAPTION_EN))

	var tags := UiKit.hbox(8)
	tags.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tags)
	tags.add_child(_tag(str(_result.get("difficulty", "NORMAL")), Color("481b88"), Neon.LIGHT))
	tags.add_child(_tag("Lv.%d" % int(_result.get("level", 1)), Color("2a153f"), Color("d7b8ff")))
	tags.add_child(_tag(_format_time(float(_result.get("length", 0.0))), Color("2a153f"), Neon.MUTED))
	if bool(_result.get("autoplay", false)):
		tags.add_child(_tag("AUTO PLAY", Color("40320f"), Palette.WARN))
	return row


## 成绩：评级牌 + 分数 / 准确率 / 最大连击。
func _build_score() -> Control:
	var row := UiKit.hbox(10)
	row.add_child(_build_grade_plate())
	row.add_child(_stat_cell("分数", "SCORE", "%08d" % int(_result.get("score", 0)), 36, Neon.LIGHT, 100))
	row.add_child(_stat_cell("准确率", "ACCURACY",
		"%.2f%%" % (float(_result.get("accuracy", 0.0)) * 100.0), 26, Neon.LIGHT, 100))
	row.add_child(_stat_cell("最大连击", "MAX COMBO",
		str(int(_result.get("max_combo", 0))), 26, Neon.PURPLE, 100))
	return row


## 评级牌：大字母 + 满判定徽记（有才显示）。
func _build_grade_plate() -> NeonPanel:
	var plate := Neon.panel(Vector4(18, 7, 18, 8))
	plate.name = "GradePlate"
	plate.fill = CELL_FILL
	plate.edge = CELL_EDGE
	plate.cut = 12
	plate.custom_minimum_size = Vector2(156, 100)
	var box := UiKit.vbox(0)
	plate.add_child(box)

	var top := UiKit.hbox(6)
	box.add_child(top)
	top.add_child(Neon.label("评级", 12, Neon.MUTED))
	top.add_child(UiKit.stretch())
	top.add_child(Neon.label("GRADE", 8, CAPTION_EN))

	var grade := str(_result.get("grade", "D"))
	var letter := Neon.label(grade, 54, _grade_color(grade), true)
	letter.name = "GradeLetter"
	letter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(letter)

	var badge := _badge_text()
	if badge != "":
		var mark := Neon.label(badge, 10, Neon.PURPLE, true)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(mark)
	return plate


## 判定数量：五格，数值沿用打歌时的判定色。
func _build_counts() -> Control:
	var counts: Dictionary = _result.get("counts", {})
	var row := UiKit.hbox(8)
	for item in [
		["PERFECT+", "perfect_plus"],
		["PERFECT", "perfect"],
		["GOOD", "good"],
		["BAD", "bad"],
		["MISS", "miss"],
	]:
		var key := str(item[1])
		row.add_child(_stat_cell(str(item[0]), "",
			str(int(counts.get(key, 0))), 26, Palette.judge_color(key), 72))
	return row


## 判定偏向：Perfect / Good 各分早按、晚按，压成一行小牌。
func _build_early_late() -> Control:
	var early_late: Dictionary = _result.get("early_late", {})
	var row := UiKit.hbox(8)
	for item in [
		["PERFECT EARLY", "perfect_early", Palette.judge_color("perfect")],
		["PERFECT LATE", "perfect_late", Palette.judge_color("perfect")],
		["GOOD EARLY", "good_early", Palette.judge_color("good")],
		["GOOD LATE", "good_late", Palette.judge_color("good")],
	]:
		var cell := Neon.panel(Vector4(14, 3, 14, 3))
		cell.fill = QUIET_FILL
		cell.edge = RULE_SOFT
		cell.cut = 9
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var line := UiKit.hbox(8)
		cell.add_child(line)
		var caption := Neon.label(str(item[0]), 10, Neon.MUTED)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(caption)
		var value := Neon.label(str(int(early_late.get(item[1], 0))), 15, item[2], true)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
		row.add_child(cell)
	return row


func _build_actions() -> Control:
	var row := UiKit.hbox(14)
	var retry := Neon.button("↻  重试（R）", true)
	retry.name = "RetryButton"
	retry.custom_minimum_size.x = 200
	retry.pressed.connect(func(): _leave(App.retry))
	row.add_child(retry)

	var back := Neon.button("选曲（Esc）", false, 16)
	back.name = "BackToSelectButton"
	back.custom_minimum_size.x = 160
	back.pressed.connect(func(): _leave(App.goto_select))
	row.add_child(back)

	row.add_child(UiKit.stretch())
	var note := Neon.label("%d 个音符  ·  满分 1,010,000" % int(_result.get("note_count", 0)), 12, Neon.MUTED)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(note)
	retry.call_deferred("grab_focus")
	return row


# --------------------------------------------------------------------------- #
# 小零件
# --------------------------------------------------------------------------- #

## 掉落提示：最下方那条「收藏品 · Stra的笔记#1 已搜集」。
func _build_story_drop() -> Control:
	var drop = _result.get("story_drop", {})
	if not (drop is Dictionary) or drop.is_empty():
		return null
	var title := str(drop.get("title", ""))
	if title == "":
		return null
	var strip := Neon.panel(Vector4(14, 5, 14, 6))
	strip.name = "StoryDrop"
	strip.fill = Color(0.045, 0.06, 0.03, 0.62)
	strip.edge = Color("66854a")
	strip.cut = 10
	strip.accents = false
	var row := UiKit.hbox(10)
	strip.add_child(row)
	row.add_child(_tag("NEW", Color("2c4318"), Color("bdf49c")))
	var text := Neon.label("收藏品 · %s 已搜集" % title, 15, Color("bdf49c"), true)
	text.name = "StoryDropText"
	# 带省略号的 Label 最小宽度只有 1px，必须自己吃满剩余宽度，不然会被旁边的占位控件挤没
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(text)
	return strip

## 切角小标签：难度 / 等级 / 时长 / AUTO PLAY。
func _tag(text: String, fill: Color, text_color: Color) -> NeonPanel:
	var tag := Neon.panel(Vector4(12, 1, 12, 1))
	tag.slanted = true
	tag.cut = 9
	tag.fill = fill
	tag.edge = Color("75608e")
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(Neon.label(text, 11, text_color, true))
	return tag


## 「小标题 + 右上角英文 + 大数值」的一格，和个人资料的统计卡同一套。
func _stat_cell(caption: String, english: String, value: String, font_size: int,
		value_color: Color, height: int) -> NeonPanel:
	var cell := Neon.panel(Vector4(16, 7, 16, 8))
	cell.fill = CELL_FILL
	cell.edge = CELL_EDGE
	cell.cut = 12
	cell.custom_minimum_size = Vector2(0, height)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var contents := UiKit.vbox(0)
	cell.add_child(contents)

	var top := UiKit.hbox(6)
	contents.add_child(top)
	top.add_child(Neon.label(caption, 12, Neon.MUTED))
	top.add_child(UiKit.stretch())
	top.add_child(Neon.label(english, 8, CAPTION_EN))

	var val := Neon.label(value, font_size, value_color, true)
	val.size_flags_vertical = Control.SIZE_EXPAND_FILL
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	contents.add_child(val)
	return cell


func _badge_text() -> String:
	if bool(_result.get("ap_plus", false)):
		return "ALL PERFECT+"
	if bool(_result.get("ap", false)):
		return "ALL PERFECT"
	if bool(_result.get("fc", false)):
		return "FULL COMBO"
	return ""


func _format_time(seconds: float) -> String:
	var total := int(round(maxf(0.0, seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


## 评级色：紫白阶梯，F 用警示粉（和 MISS 同色）。
func _grade_color(grade: String) -> Color:
	match grade:
		"S":
			return Color("f2e6ff")
		"A":
			return Color("d7b8ff")
		"B":
			return Neon.PURPLE
		"C":
			return Color("8f7aa8")
		"F":
			return Palette.HOT
	return Color("7a6890")
