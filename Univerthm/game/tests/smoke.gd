extends Node
## headless 冒烟测试：真把选曲 / 游玩 / 结算 / 设置建起来跑一遍，

const SyntheticChart = preload("res://tests/fixtures/synthetic_chart.gd")
const ChaptersData = preload("res://src/core/chapters.gd")

var passes := 0
var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		print("  FAIL: " + msg)


func near(a: float, b: float, msg: String, eps := 0.001) -> void:
	if absf(a - b) <= eps:
		passes += 1
	else:
		failures += 1
		print("  FAIL: %s (got %f, want %f)" % [msg, a, b])


func eq(a, b, msg: String) -> void:
	if a == b:
		passes += 1
	else:
		failures += 1
		print("  FAIL: %s (got %s, want %s)" % [msg, str(a), str(b)])


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("\n%d passed, %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _run() -> void:
	App.refresh_library()
	check(true, "谱面库扫描没崩（当前 %d 个谱面）" % App.library.size())
	_check_stage_geometry()
	await _check_warning_input()
	await _check_splash_input()
	await _check_menu_sound()
	await _check_song_select()
	await _check_map_story()
	await _check_song_select_return()
	await _check_collection()
	await _check_result_story_drop()
	await _check_gameplay_autoplay()
	await _check_story_layers()
	await _check_gameplay_timing()
	await _check_key_input()
	await _check_fx_rules()
	await _check_chord_marking()
	await _check_unlock_once()
	await _check_first_run_flow()
	await _check_first_entry_gate()
	await _check_first_entry_lock()
	await _check_first_entry_warning()
	await _check_from_black()
	await _check_settings()
	print("  smoke done")


## 走 Viewport 的真实输入分发，确保警告页控件不会吞掉「点击任意处继续」。
func _check_warning_input() -> void:
	for target in ["", "Center/Column/Hint", "Center/Column/Title", "Center/Column/GapF"]:
		var warning = load("res://scenes/warning.tscn").instantiate()
		get_tree().root.add_child(warning)
		warning.set_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		var point := Vector2(8, 8)
		if target != "":
			point = warning.get_node(target).get_global_rect().get_center()
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = true
		get_viewport().push_input(click, true)
		check(not warning._done, "警告页防误触时间内点击不跳过：%s" % target)
		click.pressed = false
		get_viewport().push_input(click, true)
		warning._elapsed = warning.SKIP_GUARD
		click.pressed = true
		get_viewport().push_input(click, true)
		check(warning._done, "警告页点击开始离场：%s" % target)
		click.pressed = false
		get_viewport().push_input(click, true)
		warning.queue_free()
		await get_tree().process_frame

	var warning = load("res://scenes/warning.tscn").instantiate()
	get_tree().root.add_child(warning)
	warning.set_process(false)
	warning._elapsed = warning.SKIP_GUARD
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	get_viewport().push_input(key, true)
	check(warning._done, "警告页任意键开始离场")
	key.pressed = false
	get_viewport().push_input(key, true)
	warning.queue_free()
	await get_tree().process_frame

	warning = load("res://scenes/warning.tscn").instantiate()
	get_tree().root.add_child(warning)
	warning.set_process(false)
	warning._process(warning.HOLD_SEC)
	check(warning._done, "警告页停留五秒自动开始离场")
	warning.queue_free()
	await get_tree().process_frame


## 开屏画面：画面任意处点一下、或者按任意键都进主界面；
func _check_splash_input() -> void:
	for target in ["", "Artwork"]:
		var splash = load("res://scenes/splash.tscn").instantiate()
		get_tree().root.add_child(splash)
		splash.set_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		var point := Vector2(8, 8)
		if target != "":
			point = splash.get_node(target).get_global_rect().get_center()
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = true
		get_viewport().push_input(click, true)
		check(not splash._done, "开屏防误触时间内点击不进入主界面：%s" % target)
		click.pressed = false
		get_viewport().push_input(click, true)
		splash._elapsed = splash.SKIP_GUARD
		click.pressed = true
		get_viewport().push_input(click, true)
		check(splash._done, "开屏点击画面进入主界面：%s" % target)
		splash.queue_free()
		await get_tree().process_frame

	var splash = load("res://scenes/splash.tscn").instantiate()
	get_tree().root.add_child(splash)
	splash.set_process(false)
	splash._elapsed = splash.SKIP_GUARD
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	get_viewport().push_input(key, true)
	check(splash._done, "开屏任意键进入主界面")
	splash.queue_free()
	await get_tree().process_frame

	# F11 是全局全屏切换，不该把开屏画面带走
	splash = load("res://scenes/splash.tscn").instantiate()
	get_tree().root.add_child(splash)
	splash.set_process(false)
	splash._elapsed = splash.SKIP_GUARD
	var f11 := InputEventKey.new()
	f11.keycode = KEY_F11
	f11.pressed = true
	splash._input(f11)
	check(not splash._done, "开屏按 F11 不进入主界面（留给全屏切换）")
	# 滚轮也不算点击
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	splash._input(wheel)
	check(not splash._done, "开屏滚轮不进入主界面")
	splash.queue_free()
	await get_tree().process_frame


## 主界面按钮点击音效：按下播 click.wav（别的界面不接；悬停不发声）。
func _check_menu_sound() -> void:
	if App.ui_sound == null:
		check(false, "主界面音效节点没建起来")
		return
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	if menu.has_signal("entrance_finished"):
		await menu.entrance_finished
	await get_tree().process_frame
	var hooked := true
	for target in ["StartButton", "CollectionButton", "SettingButton", "ProfileButton"]:
		var button: SpriteButton = menu.get_node(target)
		hooked = hooked and button.pressed.is_connected(App.ui_sound.play_click)
	check(hooked, "主界面四个按钮都接上了点击音效")
	check(not App.ui_sound.has_method("play_hover"), "悬停音已经拿掉了")
	App.ui_sound.play_click()
	await get_tree().process_frame
	check(App.ui_sound._click.playing, "按下按钮播放点击音效（click.wav）")
	menu.queue_free()
	await get_tree().process_frame


## 判定特效规则：只有一圈判定环（Perfect+ / Perfect / Good 同款，颜色按判定）/ Miss 无特效 / Hold 的 Miss 半透明保留
func _check_fx_rules() -> void:
	_make_session()
	App.autoplay_once = false
	var game = _new_gameplay()
	await get_tree().process_frame
	game.debug_start_now()
	var stage: StageView = game.stage
	stage._fx.clear()

	eq(Palette.judge_color("perfect").to_html(false), "b06bff", "Perfect 颜色 = 紫")
	eq(Palette.judge_color("good").to_html(false), "4c9aff", "Good 颜色 = 蓝")

	stage._on_note_judged({"type": "tap", "lane": 0, "state": "judged"}, "perfect", 0.0)
	check(stage._fx.size() == 1, "Perfect 只有一圈判定环")
	eq(stage._fx_color("perfect_plus").to_html(false), stage._fx_color("perfect").to_html(false), "Perfect+ 与 Perfect 特效同色")

	stage._fx.clear()
	stage._on_note_judged({"type": "tap", "lane": 0, "state": "judged"}, "good", 0.0)
	check(stage._fx.size() == 1, "Good 也有一圈判定环")

	stage._fx.clear()
	var bad_note := {"type": "tap", "lane": 0, "state": "judged"}
	stage._on_note_judged(bad_note, "bad", 0.0)
	check(stage._fx.is_empty(), "Bad 不产生判定环")
	check(bad_note.has("bad_fade_t"), "Bad 的音符变红快速淡出")

	stage._fx.clear()
	var hold_bad := {"type": "hold", "lane": 0, "state": "judged"}
	stage._on_note_judged(hold_bad, "bad", 0.0)
	check(not hold_bad.has("bad_fade_t"), "Hold 的 Bad 不做淡出")
	check(bool(hold_bad.get("hold_dim", false)), "Hold 的 Bad 直接变半透明继续下落")

	stage._fx.clear()
	stage._on_note_judged({"type": "tap", "lane": 0, "state": "judged"}, "miss", 0.0)
	check(stage._fx.is_empty(), "Miss 没有任何特效")

	stage._fx.clear()
	var hold_miss := {"type": "hold", "lane": 0, "state": "judged", "result": "miss"}
	stage._on_note_judged(hold_miss, "miss", 0.0)
	check(bool(hold_miss.get("hold_dim", false)), "Hold 的 Miss 会压到 50% 透明")
	check(stage._fx.is_empty(), "Hold 的 Miss 不放特效")

	stage._fx.clear()
	stage._on_hold_completed({"type": "hold", "lane": 0, "state": "judged", "result": "perfect"})
	check(stage._fx.is_empty(), "长条按到尾部不放判定环")

	game.queue_free()
	await get_tree().process_frame


## 1:1：逻辑舞台的常量和网页版预渲染窗口（editor.js / computePreviewLayout）一致
func _check_stage_geometry() -> void:
	var stage := StageView.new()
	stage.settings = App.settings
	stage.setup(SyntheticChart.build(), null, App.settings, null)
	stage.size = Vector2(1280, 720)
	near(stage.stage_scale(), 720.0 / (350.0 * 9.0 / 16.0), "16:9 窗口（1280×720）时缩放 = 720/196.875")
	check(is_equal_approx(StageView.STAGE_W, 350.0), "逻辑舞台宽 350")
	check(is_equal_approx(StageView.STAGE_H, 350.0 * 9.0 / 16.0), "逻辑舞台高 196.875（16:9）")

	# 超长 hold：绘制回看窗口必须覆盖它，不然头和身体会在 4 秒后被整条剔除
	var long_chart := SyntheticChart.build()
	long_chart["notes"] = [{"time": 1.0, "lane": 0, "type": "hold", "duration": 12.0}]
	var long_stage := StageView.new()
	long_stage.setup(long_chart, null, App.settings, null)
	check(long_stage._hold_lookback >= 12.0, "长条绘制回看窗口覆盖 12 秒的 hold")
	long_stage.free()
	var rect := stage.stage_rect()
	near(rect.size.y, 720.0, "舞台铺满窗口高度")
	near(rect.size.x, 1280.0, "舞台铺满窗口宽度（16:9 没有黑边）", 1.0)
	# 默认 stage_offset_px = -24：在居中的基础上往上抬 24px（顶部裁掉，底部留边）
	near(rect.position.y, -24.0, "默认画面上抬 24px", 1.0)
	near(rect.position.x, 0.0, "16:9 舞台水平方向无黑边", 1.0)
	# 画面垂直偏移可调
	App.settings.stage_offset_px = 10.0
	near(stage.stage_rect().position.y, 10.0, "画面垂直偏移生效", 1.0)
	App.settings.stage_offset_px = -24.0
	check(is_equal_approx(StageView.NOTE_TH, 2.0), "音符半厚 2.0")
	check(is_equal_approx(StageView.PV_SCALE, 1.75), "轨道 / 音符整体放大 1.75×")
	var judge_y := roundf(StageView.STAGE_H * 0.85)
	check(judge_y == 167.0, "judgeY = round(H*0.85) = 167")
	var lane_w := minf(StageView.STAGE_W * 0.05, (StageView.STAGE_W * 0.43) / 4.0) * StageView.PV_SCALE
	near(lane_w, 30.625, "4 轨时 laneWidth = 17.5 × 1.75 = 30.6")
	var half_w := maxf(2.0, lane_w / 2.0 - 0.5)
	near(half_w, 14.8125, "halfW = 14.81")
	near(maxf(2.0, half_w - 1.0), 13.8125, "音符半宽 13.81")
	var info := stage._lane_geom(0, judge_y, half_w)
	near(float(info["cx"]), 175.0 - 150.0, "cx = W/2 + x")
	near(float(info["cy"]), 167.0, "cy = judgeY - y")
	near(float(info["len"]), 167.0, "length 10 → 轨道长度 = judgeY")
	check(is_equal_approx(float(info["dx"]), 0.0), "rotation 0 → dx = 0")
	check(is_equal_approx(float(info["dy"]), -1.0), "rotation 0 → dy = -1（朝上）")
	stage.free()


func _check_song_select() -> void:
	var select = load("res://scenes/song_select.tscn").instantiate()
	get_tree().root.add_child(select)
	await get_tree().process_frame
	await get_tree().process_frame
	check(select.get_child_count() > 0, "选曲界面建起来了")
	check(select._rows.size() == App.library.size(), "列表行数 = 谱面数")
	# 顶上标题 = 当前章节名（不再是写死的一句话）
	eq(str(select._library_title.text), ChaptersData.display_title(App.chapter_key),
		"列表标题跟着当前章节")
	eq(ChaptersData.display_title("all"), "全部曲目", "全部曲目章节的标题")
	eq(ChaptersData.display_title("main_0"), "主线·序 ｜ 一切的开端", "序章章节的标题")
	if App.library.is_empty():
		check(select._selected == -1, "空谱面库时不选中")
		check(select._list_count.text == "0 个谱面", "空谱面库计数文案")
	else:
		check(select._detail_title.text != "", "详情标题已填（焦点在第一行）")

	# 地图模式：背景固定成章节地图（不换成曲绘、也不磨砂）
	var map_bg := load("res://assets/C0_Map.png") as Texture2D
	check(map_bg != null, "章节地图背景资源在")
	var saved_unlock_all := App.settings.unlock_all
	var saved_chapter := App.chapter_key
	App.settings.unlock_all = true          # 解锁全部之后才允许切普通列表
	App.chapter_key = "main_0"              # 地图是序章独占，这里切到序章再看地图
	select._show_map = true
	select._apply_view()
	await get_tree().process_frame
	if map_bg != null:
		eq(select._background_b.texture, map_bg, "地图模式背景 = C0_Map")
		check(select._background_b.material == null, "地图背景不套曲绘的模糊材质")
		select._set_background(null)
		eq(select._background_b.texture, map_bg, "换选曲子也不会把背景切成曲绘")
	select._show_map = false
	select._apply_view()
	await get_tree().process_frame
	check(not select._show_map, "解锁全部之后能切回普通列表")
	check(select._background_a.material != null or select._background_b.material != null,
		"切回列表时模糊材质装回去了")
	# 非序章章节：只有普通列表，按钮也不显示
	App.chapter_key = "all"
	select._apply_view()
	await get_tree().process_frame
	check(not select._show_map, "全部曲目章节不进地图")
	check(not select._map.visible, "全部曲目章节不显示地图")
	check(not select._view_button.visible, "全部曲目章节不显示切换按钮")
	App.settings.unlock_all = saved_unlock_all
	App.chapter_key = saved_chapter
	select.queue_free()
	await get_tree().process_frame


## 序章地图上的剧情收藏品：点它直接开阅读浮层（不用跳去收藏品界面）
func _check_map_story() -> void:
	var saved_chapter := App.chapter_key
	App.chapter_key = "main_0"          # 地图是序章独占，测试先切到序章
	var screen = load("res://scenes/song_select.tscn").instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	check(screen._reader != null, "选曲页带剧情阅读浮层")
	var stories := StorySource.scan(["res://剧情"])
	if stories.is_empty():
		check(true, "没有剧情文件，跳过收藏品阅读的检查")
		App.chapter_key = saved_chapter
		screen.queue_free()
		await get_tree().process_frame
		return
	screen._reader.open(stories[0])
	await get_tree().process_frame
	check(screen._reader.is_open(), "点收藏品能直接打开阅读")
	eq(screen._reader.story_title(), str(stories[0].get("title", "")), "读的是这一篇的标题")
	check(screen._reader.body_block_count() > 0, "正文块已生成")
	screen._reader.close()
	await get_tree().process_frame
	check(not screen._reader.is_open(), "关闭之后浮层收起")

	# 一路接过去：地图信号 → 选曲页 → 阅读浮层
	if not App.library.is_empty():
		screen._map.story_clicked.emit(0)
		await get_tree().process_frame
		check(screen._reader.is_open(), "地图的收藏品点击接到了阅读浮层")
		eq(screen._reader.story_title(), str(App.story_for_chart(0).get("title", "")), "读的是这首对应那篇")
		screen._reader.close()
		await get_tree().process_frame

	# 命中判定：只有收到过的收藏品点得中
	var map = screen._map
	if map != null and not map._nodes.is_empty():
		map._nodes[0]["story"] = true
		var geom: Dictionary = map._collectible_geom(0)
		var center: Vector2 = geom["center"]
		eq(map._collectible_at(center), 0, "点中收藏品那一小块")
		check(map._collectible_at(center + Vector2(420.0, 420.0)) < 0, "点别处不算点中收藏品")
		map._nodes[0]["story"] = false
		check(map._collectible_at(center) < 0, "没收到的收藏品点不中")
		# 拖动范围：内容四周还留了一圈空白，能比「贴边」再多挪
		if map.size.x > 100.0:
			var content: Vector2 = map._content_size()
			check(map._clamp_pan(Vector2(9999.0, 9999.0)).x > 0.0, "能往右下多拉一圈空白")
			check(map._clamp_pan(Vector2(-9999.0, -9999.0)).x < map.size.x - content.x,
				"往左上也比原来能拉得更远")
		# 点方框留了容差：贴边、差几个像素也算点中
		var rect: Rect2 = map.node_position(0)
		eq(map._node_at(rect.get_center()), 0, "点方框中心命中")
		eq(map._node_at(rect.position + Vector2(-6.0, -6.0)), 0, "方框外扩几像素也算点中")
		check(map._node_at(rect.position + Vector2(-80.0, -80.0)) < 0, "离得远就不算点中")

	# 右侧详情收起时不能留一条「看不见但吃点击」的死区
	# （测试环境里 chapter 可能是 all，先显式切到地图视图，后面的遮罩逻辑都依赖它）
	screen._show_map = true
	screen._apply_view()
	await get_tree().process_frame
	if screen._detail_scroll != null:
		screen._set_sheet(false, false)
		await get_tree().process_frame
		eq(screen._detail_scroll.mouse_filter, Control.MOUSE_FILTER_IGNORE, "详情收起时不接鼠标")
		check(screen._sheet_hide_distance() >= screen._detail_scroll.size.x + 24.0,
			"收起时至少挪出去一整块板宽")
		if screen._base_ready:
			check(screen._detail_scroll.position.x >= screen.size.x, "收起后详情整块移到屏幕外")
		screen._set_sheet(true, false)
		await get_tree().process_frame
		eq(screen._detail_scroll.mouse_filter, Control.MOUSE_FILTER_STOP, "详情展开时正常接点击")

	# ??? 的神秘曲：曲绘换成纯黑占位（assets/none.jpg）；普通曲子还是真曲绘
	var none_cover := load("res://assets/none.jpg") as Texture2D
	check(none_cover != null, "纯黑占位曲绘 none.jpg 在")
	if screen._row_hidden.size() > App.FIRST_ENTRY_INDEX and screen._row_hidden[App.FIRST_ENTRY_INDEX]:
		screen._on_map_focused(App.FIRST_ENTRY_INDEX)
		await get_tree().process_frame
		check(screen._selected_hidden, "选中的是 ??? 的神秘曲")
		eq(screen._cover.texture, none_cover, "??? 的曲绘换成纯黑 none.jpg")
		check(not screen._cover_mask.visible, "有了纯黑曲绘就不用再挂遮罩")
		# 地图上那个方框也一样
		if not screen._map._nodes.is_empty():
			var node_cover = screen._map._nodes[App.FIRST_ENTRY_INDEX]["node"].cover
			eq(node_cover, none_cover, "地图方框里的曲绘也是纯黑占位")
		screen._on_map_focused(0)
		await get_tree().process_frame
		check(not screen._selected_hidden, "选中的是普通曲子")
		check(screen._cover.texture != none_cover, "普通曲子用真曲绘")
		screen._on_map_focused(App.FIRST_ENTRY_INDEX)
		await get_tree().process_frame
	App.chapter_key = saved_chapter
	screen.queue_free()
	await get_tree().process_frame


## 收藏品：未搜集剧情显示锁定槽位，搜集后可点开读全文
func _check_collection() -> void:
	# 这个测试会真的写搜集进度，跑完要把玩家的 user://collection.cfg 原样放回去
	var unlock_backup := _backup_file(StorySource.UNLOCK_PATH)
	# Debug 的「全部解锁」现在把收藏品也算已搜集，这里先关掉，按真实搜集状态断言
	var saved_unlock_all := App.settings.unlock_all
	App.settings.unlock_all = false
	var builtins := StorySource.scan(["res://剧情"])
	eq(builtins.size(), 3, "序章三篇剧情随游戏资源可扫描")
	for i in builtins.size():
		var story: Dictionary = builtins[i]
		check(str(story.get("title", "")).begins_with("Stra的笔记#%d" % (i + 1)), "序章剧情标题与掉落顺序一致")
		check((StorySource.read_story(story).get("blocks", []) as Array).size() >= 5, "序章剧情有可阅读的正文")
	var story_path := "user://剧情/_smoke_story.txt"
	DirAccess.make_dir_recursive_absolute("user://剧情")
	var fh := FileAccess.open(story_path, FileAccess.WRITE)
	fh.store_string("标题：冒烟剧情\n# 第一章\n正文第一段。\n\n第二段。")
	fh.close()

	var screen = load("res://scenes/collection.tscn").instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	check(screen._find("Tab_story") != null, "收藏品有「剧情」分类")
	var author_row := screen._find("AuthorNote") as Button
	check(author_row != null and not author_row.disabled, "作者的话作为常驻文档可直接阅读")
	if author_row != null:
		author_row.pressed.emit()
		await get_tree().process_frame
		eq(str(screen._overlay_title.text), "作者的话", "作者文档显示独立标题")
		eq(str(screen._overlay_kind.text), "文档阅览 / DOCUMENT", "作者文档使用文档阅览标记")
		check(screen._story_text.get_child_count() >= 2, "作者文档正文在收藏品内可读")
		screen._close_preview()
	check(screen._find("StoryCount").text.contains("01 份文档"), "作者文档计入文档数量")
	check(not _lists_story(screen, "_smoke_story.txt"), "没搜集到的剧情不可阅读")
	var smoke_index := -1
	for i in screen._story_catalog.size():
		if str(screen._story_catalog[i].get("file", "")) == "_smoke_story.txt":
			smoke_index = i
			break
	check(smoke_index >= 0, "未搜集的剧情仍占一个档案槽位")
	if smoke_index >= 0:
		var locked_row := screen._story_rows.get_child(smoke_index + 1) as Button
		check(locked_row.disabled and not locked_row.tooltip_text.contains("冒烟剧情"), "锁定槽位不能阅读且不泄露标题")

	# 掉落：第 1 首谱面 → 第 1 篇；已经搜集过就不重复掉
	check(StorySource.grant_unlock("_smoke_story.txt"), "掉落记为已搜集")
	check(not StorySource.grant_unlock("_smoke_story.txt"), "重复掉落不再是新的")
	screen._set_filter("story")
	await get_tree().process_frame
	check(_lists_story(screen, "_smoke_story.txt"), "搜集后出现在剧情列表")
	if smoke_index >= 0:
		check(not (screen._story_rows.get_child(smoke_index) as Button).disabled, "搜集后档案可点击")
	check(screen._story_section.visible, "剧情分类显示列表")
	check(not screen._find("CardGrid").visible, "剧情分类隐藏卡片网格")
	eq(screen._find("StoryList").get_child_count(), screen._story_catalog.size(),
		"剧情列表只放正文档（「作者的话」挪去了「其他」）")
	# 「其他」分类：常驻文档归到这里
	check(screen._find("Tab_other") != null, "收藏品有「其他」分类")
	screen._set_filter("other")
	await get_tree().process_frame
	eq(screen._find("StoryList").get_child_count(), 1, "「其他」分类里只有作者的话")
	check(screen._find("CardGrid") == null or not screen._find("CardGrid").visible, "「其他」分类不显示卡片网格")

	if not App.library.is_empty():
		var stories := StorySource.scan()
		var drop := App.grant_story_drop({"entry": {"key": str(App.library[0].get("key", ""))}})
		if stories.is_empty():
			check(drop.is_empty(), "没有剧情文件时不掉落")
		elif drop.is_empty():
			check(StorySource.is_unlocked(str(stories[0].get("file", ""))),
				"已经搜集过第 1 篇就不再掉")
		else:
			eq(str(drop.get("title", "")), str(stories[0].get("title", "")),
				"第 1 首谱面掉第 1 篇剧情")
			eq(int(drop.get("number", 0)), 1, "掉落编号 = 谱面序号")
		check(not _find_story_file("_smoke_story.txt").is_empty(), "临时剧情仍在盘上")

	var picked := {}
	for entry in screen._stories:
		if str(entry.get("file", "")) == "_smoke_story.txt":
			picked = entry
	if not picked.is_empty():
		screen._open_story(picked)
		await get_tree().process_frame
		check(screen._overlay.visible, "点开剧情打开预览层")
		check(screen._story_scroll.visible and not screen._overlay_tex.visible, "阅读时显示正文、隐藏图片")
		check(screen._story_text.get_child_count() >= 3, "正文块已生成（小标题 + 段落）")
		eq(str(screen._overlay_title.text), "冒烟剧情", "阅读区标题 = 剧情标题")
		eq(str(screen._overlay_kind.text), "剧情阅览 / STORY", "阅读区标签切换成剧情")
		check(screen._find("BlurBackdrop") != null, "阅读浮层带背景虚化层")
		check(screen._overlay_tween != null, "出现时有缓动补间")
		screen._close_preview()
		await get_tree().create_timer(0.3).timeout
		check(not screen._overlay.visible, "关掉阅读区（收起动画走完才藏）")
	screen._set_filter("all")
	await get_tree().process_frame
	check(screen._find("CardGrid").visible, "全部分类仍显示卡片")
	check(screen._story_section.visible, "全部分类下面也带剧情列表")

	# 曲绘掉落：完整玩过一遍之前不进收藏品（只动内存，不写玩家存档）
	var cover_entry := {}
	for item in App.library:
		if bool(item.get("has_cover", false)):
			cover_entry = item
			break
	if not cover_entry.is_empty() and not App.settings.unlock_all:
		var cover_key := str(cover_entry.get("key", ""))
		if not App.is_cleared(cover_key):
			var before := _cover_card_count(screen)
			check(not App.cover_collected(cover_key), "没玩过的曲目：曲绘还没掉")
			App.cleared.append(cover_key)
			check(App.cover_collected(cover_key), "完整玩过一次：曲绘算已搜集")
			screen._collect()
			screen._fill_cards()
			eq(_cover_card_count(screen), before + 1, "通关后这张曲绘进了收藏品")
			App.cleared.erase(cover_key)
			screen._collect()
			screen._fill_cards()
			eq(_cover_card_count(screen), before, "回滚后曲绘从收藏品里消失")

	screen.queue_free()
	await get_tree().process_frame

	# 收拾现场：临时剧情 + 搜集进度
	_restore_file(StorySource.UNLOCK_PATH, unlock_backup)
	App.settings.unlock_all = saved_unlock_all
	DirAccess.remove_absolute(ProjectSettings.globalize_path(story_path))
	check(not FileAccess.file_exists(story_path), "冒烟剧情已清理")
	check(not await _lists_story_after_reload("_smoke_story.txt"), "清理后剧情重新上锁")


## 谱面场的故事板文字图层要真的画出来（新手教程就是靠它讲玩法）
func _check_story_layers() -> void:
	App.autoplay_once = false
	App.session = {
		"entry": {"key": "test:storyboard"},
		"chart": SyntheticChart.build(),
		"stream": SyntheticChart.stream(),
		"cover": null,
		"storyboard": {"scenes": [{
			"kind": "chart",
			"length": 0.0,
			"layers": [
				{"id": 1, "type": "text", "start": 0.5, "end": 2.0, "x": 0.5, "y": 0.4,
					"text": "故事板文字", "style": {"size": 40, "weight": 800, "color": "#ffffff"}},
				{"id": 2, "type": "text", "start": 0.5, "end": 2.0, "x": 0.5, "y": 0.7,
					"text": "隐藏的", "visible": false},
			],
			"shaders": [],
		}]},
		"warnings": [],
		"errors": [],
	}
	var game = _new_gameplay()
	await get_tree().process_frame
	check(game._story_layers != null, "有文字图层就建出 StoryLayers")
	if game._story_layers == null:
		game.queue_free()
		await get_tree().process_frame
		return
	game.debug_set_audio_clock(false)
	game.debug_start_now()
	game.debug_advance(0.2)
	await get_tree().process_frame
	eq(game._story_layers.visible_texts().size(), 0, "时间没到：不显示")
	game.debug_advance(0.6)
	await get_tree().process_frame
	var texts: Array = game._story_layers.visible_texts()
	check(texts.has("故事板文字"), "到点就显示文字")
	check(not texts.has("隐藏的"), "visible=false 的图层不画")
	var label := game._story_layers.get_node_or_null("TextLayer1") as Label
	check(label != null, "图层节点按 id 命名")
	if label != null:
		var center := label.position + label.size * 0.5
		near(center.x, game._story_layers.size.x * 0.5, "x = 0.5 居中", 2.0)
		near(center.y, game._story_layers.size.y * 0.4, "y = 0.4 偏上", 2.0)
	game.debug_advance(2.0)
	await get_tree().process_frame
	eq(game._story_layers.visible_texts().size(), 0, "过了 end 时间就收掉")
	game.queue_free()
	await get_tree().process_frame

	# 真包：新手教程的故事板就是靠它讲玩法的（14 条文字图层）
	var entry: Dictionary = App.tutorial_entry()
	if not entry.is_empty():
		var loaded := ChartSource.load_entry(entry)
		var sb: Dictionary = loaded.get("storyboard", {})
		var chart_scene := {}
		for sp in StoryboardSource.scene_spans(sb, RhythmChart.chart_duration(loaded["chart"])):
			if str(sp["kind"]) == "chart":
				chart_scene = sp["scene"]
		var active := StoryboardSource.active_layers(chart_scene, 1.0)
		check(active.size() >= 1, "教程故事板 1 秒时有文字层（%d 条）" % active.size())
		if not active.is_empty():
			check(str(active[0]["layer"].get("text", "")).begins_with("欢迎来到"), "第一条是欢迎语")



## 结算最下方：有新掉落时显示「收藏品 · xxx 已搜集」（剧情 / 曲绘可能同时掉）
func _check_result_story_drop() -> void:
	var original: Dictionary = App.last_result
	var base := {
		"title": "Synthetic Test", "artist": "unit test", "charter": "tests",
		"difficulty": "NORMAL", "level": 5, "score": 1000000, "accuracy": 1.0,
		"grade": "S", "max_combo": 32, "counts": {}, "total": 32, "note_count": 32,
		"early_late": {}, "fc": true, "ap": true, "ap_plus": true,
		"autoplay": false, "length": 20.0, "entry": {},
	}
	App.last_result = base.duplicate()
	App.last_result["story_drop"] = {"file": "Stra的笔记#1.txt", "title": "Stra的笔记#1", "number": 1}
	App.last_result["cover_drop"] = {"key": "test:cover", "title": "dream of utopia"}
	var results = load("res://scenes/results.tscn").instantiate()
	get_tree().root.add_child(results)
	await get_tree().process_frame
	await get_tree().process_frame
	var drop_text := results.find_child("StoryDropText", true, false) as Label
	check(drop_text != null, "结算最下方有剧情掉落提示")
	if drop_text != null:
		eq(drop_text.text, "收藏品 · Stra的笔记#1 已搜集", "剧情掉落提示文案")
	var cover_text := results.find_child("CoverDropText", true, false) as Label
	check(cover_text != null, "同一趟掉的曲绘也在提示里")
	if cover_text != null:
		eq(cover_text.text, "收藏品 · 曲绘「dream of utopia」已搜集", "曲绘掉落提示文案")
	results.queue_free()
	await get_tree().process_frame

	# 只掉曲绘、不掉剧情时也要显示
	App.last_result = base.duplicate()
	App.last_result["cover_drop"] = {"key": "test:cover", "title": "dream of utopia"}
	results = load("res://scenes/results.tscn").instantiate()
	get_tree().root.add_child(results)
	await get_tree().process_frame
	await get_tree().process_frame
	check(results.find_child("StoryDropText", true, false) == null, "没有剧情掉落时不显示那一行")
	check(results.find_child("CoverDropText", true, false) != null, "只有曲绘掉落时照样提示")
	results.queue_free()
	await get_tree().process_frame

	# 没有新掉落就整条不占位
	App.last_result = base.duplicate()
	results = load("res://scenes/results.tscn").instantiate()
	get_tree().root.add_child(results)
	await get_tree().process_frame
	await get_tree().process_frame
	check(results.find_child("CollectDrops", true, false) == null, "没有新掉落时不显示提示条")
	results.queue_free()
	await get_tree().process_frame
	App.last_result = original


func _lists_story(screen: Node, file_name: String) -> bool:
	for entry in screen._stories:
		if str(entry.get("file", "")) == file_name:
			return true
	return false


## 收藏品里曲绘卡片的张数
func _cover_card_count(screen: Node) -> int:
	var count := 0
	for card in screen._cards:
		if str(card.get("kind", "")) == "cover":
			count += 1
	return count


## 换个新的收藏品页（重扫后）这颗临时剧情还在不在列表里
func _lists_story_after_reload(file_name: String) -> bool:
	var screen = load("res://scenes/collection.tscn").instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var listed := _lists_story(screen, file_name)
	screen.queue_free()
	return listed


func _find_story_file(file_name: String) -> Dictionary:
	for entry in StorySource.scan():
		if str(entry.get("file", "")) == file_name:
			return entry
	return {}


func _backup_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "bytes": PackedByteArray()}
	return {"exists": true, "bytes": FileAccess.get_file_as_bytes(path)}


func _restore_file(path: String, backup: Dictionary) -> void:
	if bool(backup.get("exists", false)):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(backup.get("bytes", PackedByteArray()))
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 真切换当前场景，确保 Esc 在离开选曲前已消费，返回后长按也不会退出。
func _check_song_select_return() -> void:
	var runner := get_tree().current_scene
	get_tree().current_scene = null
	for focus_back in [false, true]:
		App.goto_select()
		await get_tree().scene_changed
		var select := get_tree().current_scene
		if focus_back:
			select.find_child("BackButton", true, false).grab_focus()
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		get_viewport().push_input(key, true)
		check(get_viewport().is_input_handled(), "选曲 Esc 在场景切换前消费，返回按钮焦点：%s" % focus_back)
		await get_tree().scene_changed
		eq(get_tree().current_scene.scene_file_path, App.CHAPTER_SCENE, "选曲 Esc 返回章节选择")
		key.echo = true
		get_viewport().push_input(key, true)
		await get_tree().process_frame
		eq(get_tree().current_scene.scene_file_path, App.CHAPTER_SCENE, "返回后长按 Esc 保持在章节选择")
		key.echo = false
		key.pressed = false
		get_viewport().push_input(key, true)
		get_tree().current_scene.queue_free()
		get_tree().current_scene = null
		await get_tree().process_frame
	get_tree().current_scene = runner


func _make_session() -> void:
	var chart := SyntheticChart.build()
	App.session = {
		"entry": {"key": "test:synthetic", "title": "Synthetic Test"},
		"chart": chart,
		"stream": SyntheticChart.stream(),
		"cover": null,
		"warnings": [],
		"errors": [],
	}


func _new_gameplay() -> Node:
	var game = load("res://scenes/gameplay.tscn").instantiate()
	game.debug_mode = true
	get_tree().root.add_child(game)
	return game


func _check_gameplay_autoplay() -> void:
	_make_session()
	App.autoplay_once = true
	var game = _new_gameplay()
	await get_tree().process_frame

	var chart: Dictionary = App.session["chart"]
	var judgeable := RhythmChart.judgeable_count(chart)
	check(game.judge != null, "判定引擎建起来了")
	check(game.judge.total_judgeable == judgeable, "可判定音符数 %d" % judgeable)
	check(game.state == 0, "初始是倒计时状态")
	check(game.autoplay, "自动演示已开启")
	check(game._zone_for_key(KEY_A) == "left", "A → 左判定区")
	check(game._zone_for_key(KEY_J) == "right", "J → 右判定区")
	check(game._zone_for_key(KEY_G) == "", "G 不参与判定")

	game.debug_start_now()
	check(game.state == 1, "进入播放状态")

	game._pause()
	check(game.state == game.State.PAUSED, "Esc 暂停")
	game._resume()
	check(game.state == game.State.RESUME, "继续 → 先数 3 秒")
	check(game._countdown_label.visible, "倒计时数字露出来")
	check(game._countdown_label.text == "3", "倒计时从 3 开始")
	for i in 180:
		game.debug_advance(1.0 / 60.0)
	check(game.state == game.State.PLAYING, "数完回到播放")
	check(not game._countdown_label.visible, "倒计时数字收起")

	var dt := 1.0 / 60.0
	var guard := 0
	while game.state != 3 and guard < 4000:
		game.debug_advance(dt)
		guard += 1
	check(game.state == 3, "自动演示跑到结算（%.1f 秒 / %d 帧）" % [game.chart_time, guard])

	var result: Dictionary = game.debug_run_result
	check(not result.is_empty(), "有结算数据")
	if not result.is_empty():
		print("  自动演示：score=%d acc=%.2f%% combo=%d counts=%s" % [
			int(result["score"]), float(result["accuracy"]) * 100.0,
			int(result["max_combo"]), str(result["counts"])])
		check(int(result["total"]) == judgeable, "结算 total = 可判定数")
		check(int(result["counts"]["miss"]) == 0, "自动演示 0 miss")
		check(int(result["counts"]["perfect"]) + int(result["counts"]["perfect_plus"]) == int(result["total"]), "自动演示全 PERFECT（含 Perfect+）")
		check(int(result["counts"]["perfect_plus"]) == int(result["total"]), "自动演示全 Perfect+")
		check(int(result["score"]) == 1010000, "全 Perfect+ 满分 1,010,000")
		check(bool(result["ap_plus"]), "自动演示 ALL PERFECT+")
		check(float(result["accuracy"]) >= 0.999, "自动演示 100% 准确率")
		check(str(result["grade"]) == "S", "自动演示评级 S")
		check(bool(result["ap"]), "自动演示 AP")
		check(int(result["max_combo"]) >= int(result["total"]), "最大连击 ≥ 可判定数")
		check(int(result["note_count"]) == judgeable, "谱面里每颗音符都计入判定数")
	check(not game.stage._fx.is_empty(), "自动演示全程有判定环")
	game.queue_free()
	await get_tree().process_frame

	App.last_result = result
	var results_scene = load("res://scenes/results.tscn").instantiate()
	get_tree().root.add_child(results_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	check(results_scene.get_child_count() > 0, "结算界面建起来了")
	results_scene.queue_free()
	await get_tree().process_frame
	App.autoplay_once = false


func _check_gameplay_timing() -> void:
	var original_offset: float = App.settings.audio_offset_ms
	App.settings.audio_offset_ms = 100.0
	for offset in [-2.0, 2.0]:
		var raw := {"audio": {"offset": offset, "volume_db": -12.0},
			"notes": [{"time": 0.5, "lane": 0}]}
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.mix_rate = 8000
		var samples := PackedByteArray()
		samples.resize(80000)
		stream.data = samples
		App.session = {"chart": RhythmChart.parse(raw)["chart"], "stream": stream}
		App.autoplay_once = true
		var game = _new_gameplay()
		await get_tree().process_frame
		var audio_end: float = stream.get_length() - offset - 0.1
		near(game.stage.song_length, audio_end, "进度条按音频偏移换算总时长")
		near(game._end_time, audio_end + 0.4, "结算时刻按音频偏移换算")
		near(game.player.volume_db, linear_to_db(App.settings.music_volume) - 12.0,
			"游戏音乐同时使用玩家音量和谱面音量")
		game.debug_set_audio_clock(false)
		game.debug_start_now()
		game.debug_advance(9.5)
		check(game.state == 1, "音频末尾之前不提前结算")
		game.debug_advance(1.0)
		check(game.state == 3, "音频末尾之后正常结算")
		game.queue_free()
		await get_tree().process_frame
	App.settings.audio_offset_ms = original_offset

	_make_session()
	App.autoplay_once = true
	var stalled = _new_gameplay()
	await get_tree().process_frame
	stalled.debug_set_audio_clock(false)
	stalled.debug_start_now()
	var guard := 0
	while stalled.state != 3 and guard < 1000:
		stalled.debug_advance(0.6)
		guard += 1
	check(stalled.state == 3, "卡顿时自动演示仍能完成结算")
	eq(int(stalled.judge.counts["perfect_plus"]), stalled.judge.total_judgeable,
		"卡顿到每帧 600ms 时自动演示仍全 Perfect+")
	eq(int(stalled.judge.counts["miss"]), 0, "自动演示卡顿不漏打")
	stalled.queue_free()
	await get_tree().process_frame
	App.autoplay_once = false


func _check_key_input() -> void:
	_make_session()
	App.autoplay_once = false
	var game = _new_gameplay()
	await get_tree().process_frame
	game.debug_start_now()
	var dt := 1.0 / 60.0
	# 第一个音符在 1.2 秒、0 轨（左判定区）
	while game.chart_time < 1.2:
		game.debug_advance(dt)
	game._on_key_down(KEY_A, "left")
	check(int(game.judge.counts["perfect_plus"]) >= 1, "手动按键命中第一个音符")
	check(game._zones.has("left"), "按住时左判定区亮着")
	check(not game.stage._fx.is_empty(), "命中产生判定环")
	check(game.stage.hud_combo_text() == "Combo %d" % int(game.judge.combo), "HUD Combo 文本跟判定器一致")
	check(game.stage.hud_score_text().length() == 8, "HUD 分数是 8 位补零")
	check(game.stage.hud_accuracy_text().ends_with("%"), "HUD 准确率带 %")
	check(game.stage.hud_level_text().begins_with("Lv."), "HUD 等级是 Lv.x")
	check(game.stage.hud_title_text() != "", "HUD 有曲名")
	check(game.stage.song_length > 0.0, "HUD 进度有总时长")
	game._on_key_up(KEY_A)
	check(not game._zones.has("left"), "松开后判定区灭掉")

	# 暂停只保留三个动作，暂停期间时间与原设置保持不变。
	var original_sound: bool = App.settings.hit_sound
	var original_volume: float = App.settings.hit_volume
	var original_fx: int = App.settings.hit_fx
	game._pause()
	check(game.state == 2, "暂停面板打开")
	check(game._pause_layer.buttons.size() == 3, "暂停只包含三个动作")
	for button in game._pause_layer.buttons:
		check(button.text == "", "暂停按钮无文字")
	var paused_time: float = game.chart_time
	game.debug_advance(0.5)
	near(game.chart_time, paused_time, "暂停不推进谱面时钟")
	game._resume()
	check(game.state == game.State.RESUME, "关掉暂停 → 3 秒倒计时")
	near(game.chart_time, paused_time, "倒计时期间画面冻在暂停点")
	for i in 180:
		game.debug_advance(1.0 / 60.0)
	check(game.state == game.State.PLAYING, "倒计时结束继续玩")
	check(not game._pause_layer.visible, "恢复后隐藏暂停 UI")
	near(game.chart_time, paused_time, "倒计时不推进谱面时钟")
	check(App.settings.hit_sound == original_sound, "暂停不修改打击音")
	near(App.settings.hit_volume, original_volume, "暂停不修改打击音量")
	check(App.settings.hit_fx == original_fx, "暂停不修改打击特效")
	game.queue_free()
	await get_tree().process_frame

	# 从暂停菜单「重开」：同一首重新来，但不要开场倒计时
	_make_session()
	App.session["skip_countdown"] = true
	var quick = _new_gameplay()
	await get_tree().process_frame
	check(quick.state == quick.State.PLAYING, "重开：直接进播放，没有开场倒计时")
	check(not bool(App.session.get("skip_countdown", false)), "跳过标记用完就清掉")
	quick.queue_free()
	await get_tree().process_frame

	# 特效设成「关」时不该产生任何打击特效
	App.settings.hit_fx = 0
	_make_session()
	var muted = _new_gameplay()
	await get_tree().process_frame
	muted.debug_start_now()
	while muted.chart_time < 1.2:
		muted.debug_advance(dt)
	muted._on_key_down(KEY_A, "left")
	check(int(muted.judge.counts["perfect_plus"]) >= 1, "特效关掉后判定照常")
	check(muted.stage._fx.is_empty(), "特效关：没有判定环")
	App.settings.hit_fx = 2
	App.settings.save()
	muted.queue_free()
	await get_tree().process_frame


## 多押标记：同一时刻（±20ms）≥2 个音符才算
func _check_chord_marking() -> void:
	var chart := SyntheticChart.build()
	chart["notes"] = [
		{"time": 1.0, "lane": 0, "type": "tap"},
		{"time": 1.0, "lane": 1, "type": "tap"},
		{"time": 1.01, "lane": 2, "type": "tap"},
		{"time": 2.0, "lane": 2, "type": "hold", "duration": 0.5},
		{"time": 3.0, "lane": 0, "type": "tap"},
	]
	var stage := StageView.new()
	stage.settings = App.settings
	stage.setup(chart, null, App.settings, null)
	var notes: Array = chart["notes"]
	eq(int(notes[0].get("chord", 0)), 3, "同刻三押 → chord=3")
	eq(int(notes[1].get("chord", 0)), 3, "三押第二颗也标记")
	eq(int(notes[2].get("chord", 0)), 3, "20ms 内也算同刻")
	eq(int(notes[3].get("chord", 0)), 0, "hold 不和前面的 tap 算同刻")
	eq(int(notes[4].get("chord", 0)), 0, "单独音符没有多押标记")
	stage.free()
	await get_tree().process_frame


## 解锁动画每首谱面只演一次：记录落盘在 user://profile.cfg 的 progress/unlock_seen
func _check_unlock_once() -> void:
	# 这个测试会写玩家档案，跑完把 user://profile.cfg 原样放回去
	var backup := _backup_file(App.STATS_PATH)
	var key := "test:unlock_once"
	check(not App.has_seen_unlock(key), "没演过解锁动画时 has_seen_unlock = false")
	check(not App.has_seen_unlock(""), "没有 key 的谱面不记已看")
	App.mark_unlock_seen(key)
	check(App.has_seen_unlock(key), "演过一次后 has_seen_unlock = true")
	App.load_stats()
	check(App.has_seen_unlock(key), "已看记录写进了 profile.cfg")
	App.forget_unlock_seen()
	check(not App.has_seen_unlock(key), "forget_unlock_seen 后又能再演一次")
	_restore_file(App.STATS_PATH, backup)
	App.load_stats()


## 第一次进游戏那条流程：黑屏 → 辅助校准 → 新手教程谱面（White Noise 的包）→ 主界面
func _check_first_run_flow() -> void:
	# 教程谱面包：能读出来、里面确实是那首 White Noise
	var entry: Dictionary = App.tutorial_entry()
	check(not entry.is_empty(), "新手教程谱面包能读出来：" + App.TUTORIAL_ZIP)
	if not entry.is_empty():
		eq(str(entry.get("title", "")), "White Noise", "教程谱面的曲名")
		eq(str(entry.get("kind", "")), "zip", "教程谱面走 zip 那条路")
		var loaded := ChartSource.load_entry(entry)
		check(loaded["chart"] != null, "教程谱面能完整加载")
		check(loaded["stream"] is AudioStream, "教程谱面的音频也读出来了")
	# 教程谱面不在曲库里（放在 charts/ 外面）
	var in_library := false
	for item in App.library:
		if str(item.get("key", "")) == str(entry.get("key", "")):
			in_library = true
	check(not in_library, "教程谱面不进曲库（选曲页看不到）")
	# 打不开的包返回 {}
	check(ChartSource.entry_from_zip("res://tutorial/not_here.zip").is_empty(),
		"读不到的包返回空 entry")

	# 黑屏场景：一块全黑底 + 校准弹窗，弹窗一开始是关着的（延迟一会儿才开）
	var screen = load("res://scenes/first_run.tscn").instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var black = screen.get_node_or_null("Black")
	check(black != null, "首次启动页有全黑底")
	if black != null:
		eq((black as ColorRect).color, Color(0, 0, 0, 1), "底色是纯黑")
	check(screen._calibration != null, "首次启动页带辅助校准弹窗")
	if screen._calibration != null:
		check(not screen._calibration.visible, "校准弹窗等黑一下才弹")
		check(screen._calibration.first_run, "首次流程用的是强制校准版本")
		check(screen._calibration.find_child("CloseButton", true, false) == null,
			"首次流程没有右上角「×」")
		var skip = screen._calibration.find_child("SkipButton", true, false)
		check(skip != null and str(skip.text) == "跳过", "左下角那颗是「跳过」")
	screen.queue_free()
	await get_tree().process_frame

	# 谱面这一侧：session 带 tutorial 标记时认得出来（打完 / 退出都回主界面）
	_make_session()
	App.session["tutorial"] = true
	App.autoplay_once = false
	var game = load("res://scenes/gameplay.tscn").instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	check(game._tutorial, "谱面认得出这一趟是教程")
	game.queue_free()
	await get_tree().process_frame

	# 「教程走过了」这个标记：写完立刻生效，splash 之后就不再走首次流程
	var saved_seen := App.settings.tutorial_seen
	App.settings.tutorial_seen = false
	App.settings.save()
	check(not App.settings.tutorial_seen, "清掉标记后算「第一次」")
	App.finish_tutorial()
	check(App.settings.tutorial_seen, "finish_tutorial 记下看过了")
	check(bool(AppSettings.load_settings().tutorial_seen), "标记已经写进 settings.cfg")
	App.settings.tutorial_seen = saved_seen
	App.settings.save()
	_make_session()


## 神秘曲（列表第 3 首）的「第一次踏入」：红色警告 + 当次禁用 Esc，通关结算后才落盘
func _check_first_entry_gate() -> void:
	var backup := _backup_file(App.STATS_PATH)
	var saved := App.entered.duplicate()
	var key := App.first_entry_key()
	if key == "":
		check(true, "谱面库不足 3 首，跳过神秘曲第一次踏入的检查")
		return
	App.entered.clear()
	check(App.needs_first_entry(key), "神秘曲没踏入过 → 要弹红色警告")
	check(not App.needs_first_entry("test:synthetic"), "别的曲子不弹警告")
	check(not App.has_entered(key), "还没正式踏入")

	# 之前演过解锁动画（unlock_seen 里有它）也照样能再看：这一趟以「正式踏入」为准
	App.unlock_seen.append(key)
	check(App.should_play_unlock(key), "还没正式踏入时，解锁动画每次都能再看")
	check(not App.should_mark_unlock_seen(key), "这一趟不当场记账（等结算）")

	App.commit_entry(key)
	check(App.has_entered(key), "结算后记为已踏入")
	check(not App.needs_first_entry(key), "踏入过就不再弹警告")
	check(App.has_seen_unlock(key), "commit_entry 连「解锁动画演过了」一起记")
	check(not App.should_play_unlock(key), "踏入之后解锁动画不再演")
	check(App.should_mark_unlock_seen(key), "普通曲子的记账规则不变")
	App.load_stats()
	check(App.has_entered(key), "已踏入记录写进了 profile.cfg")

	# 收拾现场
	_restore_file(App.STATS_PATH, backup)
	App.load_stats()
	App.entered = saved


## 第一次踏入那一趟：Esc 既不暂停也不回选曲；普通曲子照旧能暂停
func _check_first_entry_lock() -> void:
	var backup := _backup_file(App.STATS_PATH)
	var saved := App.entered.duplicate()
	var key := App.first_entry_key()
	if key == "":
		check(true, "谱面库不足 3 首，跳过 Esc 锁的检查")
		return
	App.entered.clear()

	_make_session()
	App.session["entry"] = {"key": key, "title": "神秘曲"}
	App.autoplay_once = false
	var game = _new_gameplay()
	await get_tree().process_frame
	check(game._first_entry, "神秘曲第一次进入 → 这一趟锁 Esc")
	game.debug_start_now()
	game._unhandled_input(_esc_event())
	check(game.state == game.State.PLAYING, "Esc 不暂停")
	check(not game._pause_layer.visible, "暂停面板没出来")
	game._pause()
	check(game.state == game.State.PLAYING, "直接调 _pause() 也不给暂停")
	game.queue_free()
	await get_tree().process_frame

	_make_session()
	App.autoplay_once = false
	var normal = _new_gameplay()
	await get_tree().process_frame
	check(not normal._first_entry, "普通曲子不锁 Esc")
	normal.debug_start_now()
	normal._unhandled_input(_esc_event())
	check(normal.state == normal.State.PAUSED, "普通曲子 Esc 照旧暂停")
	normal.queue_free()
	await get_tree().process_frame

	# 解锁动画不能跳过：UNLOCK 期间按键只会被吃掉，状态原地不动
	_make_session()
	App.autoplay_once = false
	var locked = _new_gameplay()
	await get_tree().process_frame
	locked.state = locked.State.UNLOCK
	locked._unhandled_input(_esc_event())
	check(locked.state == locked.State.UNLOCK, "解锁动画期间按 Esc 不跳过")
	locked._unhandled_input(_key_event(KEY_SPACE))
	check(locked.state == locked.State.UNLOCK, "空格也不跳过")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	locked._unhandled_input(click)
	check(locked.state == locked.State.UNLOCK, "鼠标点击也不跳过")
	await get_tree().process_frame
	check(locked.state == locked.State.UNLOCK, "片子没播完就一直停在解锁动画")
	locked.queue_free()
	await get_tree().process_frame

	_restore_file(App.STATS_PATH, backup)
	App.load_stats()
	App.entered = saved


func _esc_event() -> InputEventKey:
	return _key_event(KEY_ESCAPE)


func _key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


## 选曲页：点神秘曲先弹红色警告，选「否」留在列表
func _check_first_entry_warning() -> void:
	var backup := _backup_file(App.STATS_PATH)
	var saved := App.entered.duplicate()
	var key := App.first_entry_key()
	if key == "":
		check(true, "谱面库不足 3 首，跳过红色警告框的检查")
		return
	App.entered.clear()
	# 神秘曲平时还锁在「通关前一首」后面，这里先放开解锁，单测警告框本身
	var saved_unlock_all := App.settings.unlock_all
	App.settings.unlock_all = true
	var screen = load("res://scenes/song_select.tscn").instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var gated_index := App.library.find_custom(func(e): return str(e.get("key", "")) == key)
	check(gated_index >= 0, "神秘曲在曲库里")
	screen._focus_row(gated_index)
	await get_tree().process_frame
	check(not screen._selected_locked, "神秘曲已解锁（临时全解锁）")
	screen._play_selected(false)
	await get_tree().process_frame
	check(screen._warning != null and screen._warning.is_open(), "点神秘曲先弹红色警告")
	check(not screen._leaving, "警告没答完不会离开选曲页")
	eq(str(screen._warning._body.text), "进入后游戏将不能暂停。", "警告正文只剩一句话")
	check(screen._warning._flash != null, "警告框带闪白层")
	check(screen._warning._flash_tween != null, "弹出时闪白补间跑起来了")
	check(screen._warning._stinger != null and screen._warning._stinger.stream != null,
		"警告框带合成的短音效")
	screen._warning._choose(false)
	await get_tree().process_frame
	check(not screen._warning.is_open(), "选「否」关掉警告框")
	check(not screen._leaving, "选「否」留在选曲列表")
	check(App.session.is_empty() or str(App.session.get("entry", {}).get("key", "")) != key,
		"选「否」没有进谱面")

	# 选「是」：接进入过场（详情板移到中间 → 音效 → 放大 → 全黑），黑透才切场景
	screen._play_selected(false)
	await get_tree().process_frame
	check(screen._warning.is_open(), "再点一次又弹警告")
	screen._warning._choose(true)
	await get_tree().process_frame
	check(screen._entering, "选「是」之后播进入过场")
	check(screen._entry_tween != null and screen._entry_tween.is_valid(), "过场补间在跑")
	check(screen._entry_player.stream != null, "过场带合成的进入音效")
	check(screen._leaving, "过场期间不再响应操作")
	check(str(App.session.get("entry", {}).get("key", "")) != key, "过场没走完就不切场景")
	# 掐掉补间，别真的把场景换掉
	if screen._entry_tween != null and screen._entry_tween.is_valid():
		screen._entry_tween.kill()
	screen._entering = false
	screen._leaving = false

	# 自动演示的解锁：原本要「游玩过一次」；开了「全部解锁（Debug）」就直接放开
	var saved_plays := int(App.stats.get("plays", 0))
	App.stats["plays"] = 0
	App.settings.unlock_all = false
	check(not App.autoplay_unlocked(), "没打过 & 没全解锁 → 自动演示锁着")
	App.settings.unlock_all = true
	check(App.autoplay_unlocked(), "全解锁之后自动演示也放开了")
	App.stats["plays"] = saved_plays

	# 自动演示：不算「踏入」，所以不弹警告，直接看演出
	screen._play_selected(true)
	await get_tree().process_frame
	check(not (screen._warning != null and screen._warning.is_open()), "??? 的自动演示不弹警告")
	check(screen._entering or screen._leaving, "??? 的自动演示直接走进场过场")
	if screen._entry_tween != null and screen._entry_tween.is_valid():
		screen._entry_tween.kill()
	screen._entering = false
	screen._leaving = false
	screen.queue_free()
	await get_tree().process_frame
	App.settings.unlock_all = saved_unlock_all
	_restore_file(App.STATS_PATH, backup)
	App.load_stats()
	App.entered = saved


## 从选曲页的「变黑」接过来：谱面这一侧先全黑，再淡出到解锁动画 / 舞台
func _check_from_black() -> void:
	_make_session()
	App.session["entry"] = {"key": "test:from_black"}
	App.session["from_black"] = true
	App.autoplay_once = false
	var game = load("res://scenes/gameplay.tscn").instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	var cover = game.get_node_or_null("FromBlack")
	check(cover != null, "进谱面时自带一层全黑")
	if cover != null:
		check(float(cover.color.a) > 0.99, "接过来的时候是全黑")
		check(cover.get_index() == game.get_child_count() - 1, "黑幕盖在最上层")
	# 有解锁动画时黑屏要压 5 秒才起播（??? 那首的节奏）
	var gameplay_script := load("res://src/game/gameplay.gd")
	check(float(gameplay_script.FROM_BLACK_HOLD_UNLOCK) >= 4.99, "解锁动画前的黑屏是 5 秒")
	await get_tree().create_timer(0.6).timeout
	if cover != null and is_instance_valid(cover):
		check(float(cover.color.a) < 0.99, "压一会儿之后黑幕开始淡出")
	game.queue_free()
	await get_tree().process_frame
	_make_session()


func _check_settings() -> void:
	var screen = load("res://scenes/settings.tscn").instantiate()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	check(screen.get_child_count() > 0, "设置界面建起来了")
	check(screen._rows.size() >= 5, "设置项数量（音画偏移 / 音乐音量 / 打击音音量 / 打击音 / 打击特效）")
	screen._refresh()
	check(App.settings.key_layout in AppSettings.KEY_LAYOUTS, "键位布局合法")
	# 底部那颗「新手教程」现在直接进教程谱面（不再弹教程图）
	var tutorial_button := screen.find_child("TutorialButton", true, false) as Button
	check(tutorial_button != null, "设置页底部有新手教程按钮")
	if tutorial_button != null:
		eq(tutorial_button.text, "新手教程", "教程按钮文案")
		check(tutorial_button.tooltip_text.contains("教程谱面"), "教程按钮的提示指向教程谱面")
	screen.queue_free()
	await get_tree().process_frame

	App.settings.audio_offset_ms = -15.0
	App.settings.speed_mult = 1.5
	App.settings.save()
	var reloaded := AppSettings.load_settings()
	check(absf(reloaded.audio_offset_ms + 15.0) < 0.001, "偏移存得住")
	check(absf(reloaded.speed_mult - 1.5) < 0.001, "流速存得住")
	App.settings.reset()
	App.settings.save()
