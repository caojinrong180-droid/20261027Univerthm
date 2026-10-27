extends Control
## 结算界面：评级 / 分数 / 准确率 / 判定统计 / 连击 / 重试。

var _result: Dictionary = {}


func _ready() -> void:
	theme = UiTheme.theme()
	_result = App.last_result
	if _result.is_empty():
		App.goto_select()
		return
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			App.retry()
		KEY_ESCAPE, KEY_Q:
			App.goto_select()


# --------------------------------------------------------------------------- #

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG_DEEP
	UiKit.full_rect(bg)
	add_child(bg)

	var cover = _result.get("cover")
	if cover is Texture2D:
		var texture_rect := TextureRect.new()
		texture_rect.texture = cover
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.modulate = Color(1, 1, 1, 0.34)
		UiKit.full_rect(texture_rect)
		add_child(texture_rect)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.04, 0.62)
	UiKit.full_rect(shade)
	add_child(shade)

	var center := CenterContainer.new()
	UiKit.full_rect(center)
	add_child(center)

	var panel := UiKit.panel(Palette.PANEL, 14, 1, Palette.LINE, Vector4(38, 30, 38, 30))
	panel.custom_minimum_size = Vector2(860, 0)
	center.add_child(panel)

	var box := UiKit.vbox(14)
	panel.add_child(box)

	box.add_child(_build_header())
	box.add_child(UiKit.rule())
	box.add_child(_build_main())
	box.add_child(UiKit.rule())
	box.add_child(_build_counts())
	box.add_child(_build_early_late())
	box.add_child(_build_badges())
	box.add_child(_build_actions())


func _build_header() -> Control:
	var header := UiKit.hbox(12)
	var text_box := UiKit.vbox(3)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(text_box)

	var title := UiKit.label(str(_result.get("title", "未命名谱面")), 27, Palette.TEXT)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(title)

	var artist := UiKit.label(str(_result.get("artist", "")), 14, Palette.DIM)
	text_box.add_child(artist)

	# 曲绘作者：谱面 meta.illustrator（制谱器「曲绘画师」那栏），空就不占位
	var illustrator := str(_result.get("illustrator", ""))
	if illustrator != "":
		text_box.add_child(UiKit.label("曲绘  %s" % illustrator, 12, Palette.DIM_2))

	var difficulty := str(_result.get("difficulty", "NORMAL"))
	header.add_child(UiKit.chip(difficulty, Palette.difficulty_color(difficulty), 12))
	header.add_child(UiKit.chip("Lv.%d" % int(_result.get("level", 1)), Palette.TEXT, 12))
	if bool(_result.get("autoplay", false)):
		header.add_child(UiKit.chip("AUTO PLAY", Palette.WARN, 12))
	return header


func _build_main() -> Control:
	var main := UiKit.hbox(28)

	var grade := str(_result.get("grade", "D"))
	var grade_label := UiKit.mono_label(grade, 118, _grade_color(grade))
	grade_label.custom_minimum_size = Vector2(150, 0)
	grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main.add_child(grade_label)

	var right := UiKit.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)

	var state_text := "CLEAR"
	var state_color := Palette.OK
	right.add_child(UiKit.label(state_text, 13, state_color))

	var score := UiKit.mono_label("%08d" % int(_result.get("score", 0)), 46, Palette.ACCENT)
	right.add_child(score)

	var accuracy := UiKit.mono_label("%.2f%%" % (float(_result.get("accuracy", 0.0)) * 100.0), 22, Palette.TEXT)
	right.add_child(accuracy)
	right.add_child(UiKit.label("准确率  ·  共 %d 个判定（1,000,000 × 加权 + Perfect+ 额外 10,000）" % int(_result.get("total", 0)), 12, Palette.DIM_2))

	var combo_box := UiKit.vbox(0)
	combo_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	main.add_child(combo_box)
	var combo := UiKit.mono_label(str(int(_result.get("max_combo", 0))), 44, Palette.TEXT)
	combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_box.add_child(combo)
	var combo_caption := UiKit.label("MAX COMBO", 12, Palette.DIM_2)
	combo_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_box.add_child(combo_caption)
	return main


func _build_counts() -> Control:
	var counts: Dictionary = _result.get("counts", {})
	var row := UiKit.hbox(10)
	var items := [
		["PERFECT+", int(counts.get("perfect_plus", 0)), Palette.judge_color("perfect_plus")],
		["PERFECT", int(counts.get("perfect", 0)), Palette.OK],
		["GOOD", int(counts.get("good", 0)), Palette.ACCENT],
		["BAD", int(counts.get("bad", 0)), Palette.WARN],
		["MISS", int(counts.get("miss", 0)), Palette.HOT],
	]
	for item in items:
		var cell := UiKit.panel(Palette.PANEL_2, 8, 1, Palette.LINE, Vector4(14, 8, 14, 8))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cell_box := UiKit.vbox(1)
		cell.add_child(cell_box)
		var value := UiKit.mono_label(str(item[1]), 24, item[2])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell_box.add_child(value)
		var caption := UiKit.label(str(item[0]), 11, Palette.DIM_2)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell_box.add_child(caption)
		row.add_child(cell)

	return row


## 判定偏向：Perfect / Good 各分 Early（按早了）和 Late（按晚了）
func _build_early_late() -> Control:
	var el: Dictionary = _result.get("early_late", {})
	var row := UiKit.hbox(10)
	for item in [
		["PERFECT", "EARLY", int(el.get("perfect_early", 0)), Palette.judge_color("perfect")],
		["PERFECT", "LATE", int(el.get("perfect_late", 0)), Palette.judge_color("perfect")],
		["GOOD", "EARLY", int(el.get("good_early", 0)), Palette.judge_color("good")],
		["GOOD", "LATE", int(el.get("good_late", 0)), Palette.judge_color("good")],
	]:
		var cell := UiKit.flat_panel(Palette.PANEL_2, 7, Vector4(14, 5, 14, 5))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var line := UiKit.hbox(8)
		cell.add_child(line)

		var name_label := UiKit.label("%s %s" % [item[0], item[1]], 11, Palette.DIM_2)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(name_label)

		var value := UiKit.mono_label(str(item[2]), 17, item[3])
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
		row.add_child(cell)
	return row

func _build_badges() -> Control:
	var row := UiKit.hbox(8)
	var has_badge := false
	if bool(_result.get("ap_plus", false)):
		row.add_child(UiKit.chip("ALL PERFECT+", Palette.judge_color("perfect_plus"), 13))
		has_badge = true
	elif bool(_result.get("ap", false)):
		row.add_child(UiKit.chip("ALL PERFECT", Palette.WARN, 13))
		has_badge = true
	elif bool(_result.get("fc", false)):
		row.add_child(UiKit.chip("FULL COMBO", Palette.OK, 13))
		has_badge = true
	row.add_child(UiKit.label("%d 个音符" % int(_result.get("note_count", 0)), 12, Palette.DIM_2))
	row.add_child(UiKit.stretch())
	if not has_badge:
		row.add_child(UiKit.label("多打几遍就 FC 了", 12, Palette.DIM_2))
	row.visible = true
	return row


func _build_actions() -> Control:
	var row := UiKit.hbox(10)
	var retry := UiKit.button("↻  重试（R）", 18, "AccentButton")
	retry.custom_minimum_size = Vector2(200, 46)
	retry.pressed.connect(func(): App.retry())
	row.add_child(retry)
	var back := UiKit.button("选曲（Esc）", 16)
	back.custom_minimum_size = Vector2(160, 46)
	back.pressed.connect(func(): App.goto_select())
	row.add_child(back)
	row.add_child(UiKit.stretch())
	row.add_child(UiKit.label("Enter 触发当前按钮  ·  R 重试  ·  Esc 选曲", 12, Palette.DIM_2))
	retry.call_deferred("grab_focus")
	return row


func _grade_color(grade: String) -> Color:
	match grade:
		"S":
			return Color("#ffd166")
		"A":
			return Palette.OK
		"B":
			return Palette.ACCENT
		"C":
			return Palette.DIM
		"F":
			return Palette.HOT
	return Palette.DIM_2
