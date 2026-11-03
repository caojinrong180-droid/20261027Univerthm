extends Node
## 全局单例（autoload 名 = App）：设置 / 谱面库 / 当前游玩会话 / 结算数据。

const WARNING_SCENE := "res://scenes/warning.tscn"
const SPLASH_SCENE := "res://scenes/splash.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const CHAPTER_SCENE := "res://scenes/chapter_select.tscn"
const COLLECTION_SCENE := "res://scenes/collection.tscn"
const PROFILE_SCENE := "res://scenes/profile.tscn"
const SELECT_SCENE := "res://scenes/song_select.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const RESULTS_SCENE := "res://scenes/results.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
## 第一次进游戏的那条流程：黑屏 → 辅助校准 → 新手教程谱面 → 主界面
const FIRST_RUN_SCENE := "res://scenes/first_run.tscn"
## 新手教程谱面（White Noise 的包；放在 charts/ 外面，所以不会进曲库）
const TUTORIAL_ZIP := "res://tutorial/White_noise.zip"
const MenuMusic = preload("res://src/audio/menu_music.gd")

## 谱面扫描根目录：随游戏发布 + 用户拖进来的
const CHART_ROOTS := ["res://charts", "user://charts"]

var settings: AppSettings
var menu_music: MenuMusic
## 主菜单按钮点击音效；只有主界面把它接上去
var ui_sound: UiSound
var library: Array = []
## 选曲页往返设置 / 游玩时保留当前选择。
var selected_chart_key := ""
## 一次游玩：{ entry, chart, stream, cover, warnings, errors }
var session := {}
## 结算：见 gameplay.gd 的 _finish()
var last_result := {}
## 「自动演示」是这一次性的，不写进设置
var autoplay_once := false
## 当前主角：0 = Stra，1 = Kisai。只在本次游戏运行期间保留。
var character_index := 0
## 每次启动只在首次进入主界面时自动弹一次新手教程；返回主界面不重复弹。
var tutorial_shown_this_run := false
## 跨场景的一次性提示（选曲界面底部状态栏会显示）
var toast := ""

## 从哪个界面进的设置，返回时回哪（默认回选曲）
var _settings_return := "res://scenes/song_select.tscn"

## 玩家档案统计（user://profile.cfg）：游玩次数 / 平均分 / 平均准确率 / 最高分
const STATS_PATH := "user://profile.cfg"
var stats := {
	"plays": 0, "best_score": 0, "best_title": "", "best_acc": 0.0,
	"score_total": 0.0, "acc_total": 0.0,
}
## 通关过的谱面 key（自动演示不计入）。选曲列表按顺序解锁：第 1 首永远能玩，
var cleared: Array[String] = []
## 已经演过解锁动画的谱面 key：解锁动画每首只演一次，再进同一首直接进倒计时。
var unlock_seen: Array[String] = []
## 已经「正式踏入」过的谱面 key。目前只有神秘曲（第 3 首）的第一次踏入会在意它：
## 通关结算时才落盘，所以第一次踏入途中强制关游戏 = 没踏入过，下次还要重新过红色警告。
var entered: Array[String] = []
## 「神秘曲」在列表里的第几首（0 开始，2 = 第 3 首）：第一次踏入要红色确认 + 当次禁用 Esc。
const FIRST_ENTRY_INDEX := 2
## 每首曲子的最好成绩：谱面 key → { "score": int, "acc": float, "fc": bool, "ap": bool }
## （自动演示不计入）。章节选择页的 CL / FC / AP 就是从这里数出来的。
var best_records := {}
## 当前选中的章节 key（章节选择页写入，选曲页据此过滤）
var chapter_key := "all"


## 神秘曲（「???」）第一次踏入、在警告框里选「是」之后放的那声特殊音效。
## 挂在 App 上播，换场景（进谱面）也不会被掐掉，能一路响进谱面里。
const FINAL_ENTRY_SOUND := preload("res://audio/enter_the_final.wav")
var _final_entry_sound: AudioStreamPlayer


## 放「特殊进入音」：音量跟设置里的「音乐音量」走，重入会从头再来
func play_final_entry_sound() -> void:
	if _final_entry_sound == null:
		_final_entry_sound = AudioStreamPlayer.new()
		_final_entry_sound.name = "FinalEntrySound"
		add_child(_final_entry_sound)
	var volume := 1.0
	if settings != null:
		volume = clampf(settings.music_volume, 0.0, 1.0)
	_final_entry_sound.stream = FINAL_ENTRY_SOUND
	_final_entry_sound.volume_db = linear_to_db(maxf(0.001, volume)) - 1.0
	_final_entry_sound.play()


func _ready() -> void:
	settings = AppSettings.load_settings()
	apply_fullscreen()
	load_stats()
	refresh_library()
	menu_music = MenuMusic.new()
	menu_music.name = "MenuMusic"
	add_child(menu_music)
	refresh_music_volume()
	get_tree().scene_changed.connect(_sync_menu_music)
	_sync_menu_music.call_deferred()
	ui_sound = UiSound.new()
	ui_sound.name = "UiSound"
	add_child(ui_sound)


func refresh_music_volume() -> void:
	if menu_music != null and settings != null:
		menu_music.set_music_volume(settings.music_volume)


func _sync_menu_music() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		_sync_menu_music_for_scene(scene.scene_file_path)


func _sync_menu_music_for_scene(path: String) -> void:
	match path:
		# 开屏画面就开始淡入，一路连着主界面播，不会在换场景时断一下。
		SPLASH_SCENE, MENU_SCENE, COLLECTION_SCENE, PROFILE_SCENE:
			menu_music.enter_menu()
		SETTINGS_SCENE:
			pass # 设置往返保持声源、播放位置和淡入进度。
		_:
			# 主界面「开始游戏」进入选曲时即淡出；后续游玩 / 结算也不重播。
			menu_music.fade_out()


## F11：全屏 / 窗口切换（全屏就是按屏幕原生分辨率渲染，最清晰）。
## 和设置页的「全屏」开关是同一个值，会存进 settings.cfg。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		set_fullscreen(settings == null or not settings.fullscreen)
		get_viewport().set_input_as_handled()


## 把当前设置里的全屏开关应用到窗口（启动时和每次切换都调它）
func apply_fullscreen() -> void:
	var want := settings != null and settings.fullscreen
	get_window().mode = Window.MODE_FULLSCREEN if want else Window.MODE_WINDOWED


## 全屏开关：存设置 + 立刻应用
func set_fullscreen(on: bool) -> void:
	if settings != null:
		settings.fullscreen = on
		settings.save()
	apply_fullscreen()


func refresh_library() -> void:
	library = ChartSource.scan(CHART_ROOTS)


func autoplay_enabled() -> bool:
	return autoplay_once or settings.autoplay


## 「自动演示」按钮的解锁条件：游玩过一次谱面（自动演示自己不算次数）
func autoplay_unlocked() -> bool:
	return int(stats.get("plays", 0)) > 0


# --------------------------------------------------------------------------- #
# 场景切换
# --------------------------------------------------------------------------- #

## from_black：进谱面时屏幕已经是全黑的（选曲页先慢慢压黑再切场景），
## 谱面这一侧就从黑里淡出来，把「变黑 → 解锁动画」接成一段。
func play_entry(entry: Dictionary, autoplay := false, from_black := false) -> bool:
	toast = ""
	var loaded := ChartSource.load_entry(entry)
	if loaded["chart"] == null:
		toast = "读不了这个谱面：%s" % str(loaded["errors"])
		return false
	session = {
		"entry": entry,
		"chart": loaded["chart"],
		"stream": loaded["stream"],
		"cover": loaded["cover"],
		"storyboard": loaded.get("storyboard", {}),
		"unlock_video": loaded.get("unlock_video", {}),
		"warnings": loaded["warnings"],
		"errors": loaded["errors"],
		"from_black": from_black,
	}
	autoplay_once = autoplay
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)
	return true


# --------------------------------------------------------------------------- #
# 新手教程：第一次进游戏时先做偏移校准，再打 White Noise 这个包，打完才进主界面
# --------------------------------------------------------------------------- #

var _tutorial_entry: Dictionary = {}


## 新手教程谱面的 entry（按 zip 路径自己建，不走曲库扫描 → 不会出现在选曲页 / 地图上）
func tutorial_entry() -> Dictionary:
	if _tutorial_entry.is_empty():
		_tutorial_entry = ChartSource.entry_from_zip(TUTORIAL_ZIP)
	return _tutorial_entry


## 开始打新手教程谱面：和普通进入共用一套 session，只是多一个 tutorial 标记
## （谱面里看到它就按「教程」处理：打完 / 中途退出都直接回主界面，不记成绩、不进结算）
func play_tutorial() -> bool:
	var entry := tutorial_entry()
	if entry.is_empty():
		toast = "找不到新手教程谱面：%s" % TUTORIAL_ZIP
		return false
	if not play_entry(entry, false, false):
		return false
	session["tutorial"] = true
	return true


## 教程走完了：记下「看过」，以后启动就不再走这条流程
func finish_tutorial() -> void:
	if settings == null or settings.tutorial_seen:
		return
	settings.tutorial_seen = true
	settings.save()


## 第一次进游戏的黑屏流程（辅助校准 → 新手教程谱面 → 主界面）
func goto_first_run() -> void:
	get_tree().change_scene_to_file(FIRST_RUN_SCENE)


## 重开同一首。skip_countdown = true 时不走开场倒计时（从暂停菜单重开用这个）
func retry(skip_countdown := false) -> void:
	if session.is_empty():
		goto_select()
		return
	var entry = session["entry"]
	autoplay_once = autoplay_enabled()
	if play_entry(entry, autoplay_once) and skip_countdown:
		session["skip_countdown"] = true


## 归档一局成绩（自动演示不计入，也不解锁下一首）
func record_result(res: Dictionary) -> void:
	stats["plays"] = int(stats.get("plays", 0)) + 1
	var score := int(res.get("score", 0))
	var accuracy := float(res.get("accuracy", 0.0))
	# 平均分 / 平均准确率：累计量相加，显示时再除以游玩次数
	stats["score_total"] = float(stats.get("score_total", 0.0)) + float(score)
	stats["acc_total"] = float(stats.get("acc_total", 0.0)) + accuracy
	if score > int(stats.get("best_score", 0)):
		stats["best_score"] = score
		stats["best_title"] = str(res.get("title", ""))
		stats["best_acc"] = accuracy
	var entry = res.get("entry", {})
	if entry is Dictionary:
		var key := str(entry.get("key", ""))
		if key != "":
			if not cleared.has(key):
				cleared.append(key)
			# 每首曲子自己的最好成绩（分数更高才刷新；FC / AP 达成过就永久保留）
			var old: Dictionary = best_records.get(key, {})
			if score > int(old.get("score", -1)):
				old["score"] = score
				old["acc"] = accuracy
			if bool(res.get("fc", false)):
				old["fc"] = true
			if bool(res.get("ap", false)):
				old["ap"] = true
			best_records[key] = old
	save_stats()


## 某首曲子的最好成绩 { score, acc }；没打过返回空字典
func best_record(key: String) -> Dictionary:
	var found = best_records.get(key, {})
	return found if found is Dictionary else {}


## 章节包含哪些谱面。现在所有谱面都算进每个章节；以后按章节分谱面就改这里。
func chapter_charts(_key: String) -> Array:
	return library


## 章节的 CL / FC / AP 进度：{ total, cl, fc, ap }
func chapter_progress(key: String) -> Dictionary:
	var charts := chapter_charts(key)
	var result := {"total": charts.size(), "cl": 0, "fc": 0, "ap": 0}
	for entry in charts:
		var chart_key := str(entry.get("key", ""))
		if is_cleared(chart_key):
			result["cl"] = int(result["cl"]) + 1
		var record := best_record(chart_key)
		if bool(record.get("fc", false)):
			result["fc"] = int(result["fc"]) + 1
		if bool(record.get("ap", false)):
			result["ap"] = int(result["ap"]) + 1
	return result


## 这个章节的谱面是不是全解锁了（序章的「地图」界面要全解锁才开）
func all_charts_unlocked() -> bool:
	for i in library.size():
		if not is_chart_unlocked(i):
			return false
	return not library.is_empty()


## 第 index 首曲目掉的是哪篇剧情：{ file, title }；没配到返回空字典
func story_for_chart(index: int) -> Dictionary:
	if index < 0:
		return {}
	var stories := StorySource.scan()
	if index >= stories.size():
		return {}
	return stories[index]


## 每首曲目的收藏品搜集了没有（选曲地图上挂的那个小四边形用）。
## Debug 的「全部解锁」打开时，收藏品也一律算已搜集。
func story_collected_for_chart(index: int) -> bool:
	var story := story_for_chart(index)
	if story.is_empty():
		return false
	return story_collected(str(story.get("file", "")))


## 这一篇剧情算不算「已搜集」：Debug 全解锁时一律算
func story_collected(story_name: String) -> bool:
	if story_name == "":
		return false
	if settings != null and settings.unlock_all:
		return true
	return StorySource.is_unlocked(story_name)


## 这一首的曲绘搜集了没有：完整玩过一遍才算（自动演示不算）；Debug 全解锁时一律算
func cover_collected(key: String) -> bool:
	if key == "":
		return false
	if settings != null and settings.unlock_all:
		return true
	return is_cleared(key)


## 删除游玩记录：次数 / 平均分 / 最好成绩 / 通关列表 / 每首最好成绩 / 解锁动画记录 /
## 神秘曲的「已踏入」记录 / 已搜集剧情。
## 设置（音量、偏移、名字、看板娘、调试开关）和个人信息都不动，曲目会重新上锁。
func reset_progress() -> void:
	stats = {
		"plays": 0, "best_score": 0, "best_title": "", "best_acc": 0.0,
		"score_total": 0.0, "acc_total": 0.0,
	}
	cleared.clear()
	unlock_seen.clear()
	entered.clear()
	best_records.clear()
	save_stats()
	StorySource.clear_unlocks()


## 「初始化游戏」：把存档 / 设置 / 收藏品全删掉，内存状态退回**第一次启动之前**，
## 然后回到光敏性警告界面（第一次开游戏看到的那一页）。
## 玩家自己导入的谱面（`user://charts`）不动——那是内容，不是存档。
func factory_reset() -> void:
	for path in [AppSettings.PATH, STATS_PATH, StorySource.UNLOCK_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	stats = {
		"plays": 0, "best_score": 0, "best_title": "", "best_acc": 0.0,
		"score_total": 0.0, "acc_total": 0.0,
	}
	cleared.clear()
	unlock_seen.clear()
	entered.clear()
	best_records.clear()
	settings = AppSettings.load_settings()      # 文件删了 → 拿一整套默认值：音量 / 偏移 / 速度 /
	#                                              判定窗口 / 打击音与特效 / 键位 / 画面偏移 /
	#                                              玩家名 / 看板娘序号 / 教程标记 / Debug 全解锁 / 全屏
	apply_fullscreen()
	character_index = 0                          # 主界面看板娘（运行时那一份）也回第一张
	tutorial_shown_this_run = false
	selected_chart_key = ""
	chapter_key = "all"
	autoplay_once = false
	session = {}
	last_result = {}
	toast = ""
	refresh_library()
	refresh_music_volume()
	# 回到标题（开屏）界面：之后点任意键就按「第一次进游戏」走校准 + 新手教程那一套
	goto_splash()


## 平均分；还没有任何一局（或老存档没累计值）时返回 -1，界面显示「—」
func average_score() -> float:
	var plays := int(stats.get("plays", 0))
	if plays <= 0:
		return -1.0
	return float(stats.get("score_total", 0.0)) / float(plays)


## 平均准确率（0~1）；没有数据返回 -1
func average_accuracy() -> float:
	var plays := int(stats.get("plays", 0))
	if plays <= 0:
		return -1.0
	return float(stats.get("acc_total", 0.0)) / float(plays)


## 这一首通关过没有
func is_cleared(key: String) -> bool:
	return cleared.has(key)


## 这首谱面的解锁动画演过了没有（只在第一次进谱面时演）
func has_seen_unlock(key: String) -> bool:
	return key != "" and unlock_seen.has(key)


## 记下「解锁动画已演过」，落盘到 user://profile.cfg。key 为空（来路不明的谱面）不记。
func mark_unlock_seen(key: String) -> void:
	if key == "" or unlock_seen.has(key):
		return
	unlock_seen.append(key)
	save_stats()


## 调试用：清掉已看记录，让下一次进谱面重新演解锁动画
func forget_unlock_seen() -> void:
	if unlock_seen.is_empty():
		return
	unlock_seen.clear()
	save_stats()


## 「神秘曲」在列表里的 key；库不够长就返回空串（没有这回事）
func first_entry_key() -> String:
	if FIRST_ENTRY_INDEX < 0 or FIRST_ENTRY_INDEX >= library.size():
		return ""
	return str(library[FIRST_ENTRY_INDEX].get("key", ""))


## 这一首踏进去过没有（见 entered）
func has_entered(key: String) -> bool:
	return key != "" and entered.has(key)


## 神秘曲还没揭晓时用的纯黑占位曲绘（assets/none.jpg）
const NONE_COVER_PATH := "res://assets/none.jpg"
var _none_cover: Texture2D = null


## 这张是不是「还没揭晓的神秘曲」：列表第 3 首、而且还没有成绩。
## 未揭晓时它的曲绘一律显示成纯黑占位（`none_cover()`），打出成绩之后自然换回真曲绘。
func is_hidden_chart(key: String) -> bool:
	if key == "":
		return false
	var gated := first_entry_key()
	if gated == "" or key != gated:
		return false
	return best_record(key).is_empty()


## 纯黑占位曲绘（懒加载，全局共用一张）
func none_cover() -> Texture2D:
	if _none_cover == null:
		_none_cover = load(NONE_COVER_PATH) as Texture2D
	return _none_cover


## 这一次进谱面是不是「神秘曲的第一次踏入」：
## 选曲页要弹红色警告（踏出这一步就不能反悔），谱面里当次不许按 Esc 暂停 / 退出。
func needs_first_entry(key: String) -> bool:
	var gated := first_entry_key()
	return gated != "" and key == gated and not entered.has(key)


## 正式踏入：通关结算时调。没打完就关游戏的局不会走到这里，所以下次还是「第一次」。
## 解锁动画的「演过了」也在这里一起记：对神秘曲来说，那一趟演出的记号和「踏入」是同一件事。
func commit_entry(key: String) -> void:
	if key == "":
		return
	var changed := false
	if not entered.has(key):
		entered.append(key)
		changed = true
	if not unlock_seen.has(key):
		unlock_seen.append(key)
		changed = true
	if changed:
		save_stats()


## 这一趟要不要演解锁动画：每首只演一次。神秘曲的第一次踏入例外——那一趟以「正式踏入」为准，
## 所以还在「第一次」的时候（哪怕之前演过、后来强关游戏了）都还能再看一遍。
func should_play_unlock(key: String) -> bool:
	if key == "":
		return false
	if needs_first_entry(key):
		return true
	return not unlock_seen.has(key)


## 演的时候要不要当场记账：神秘曲第一次踏入那一趟不记，等结算时由 commit_entry() 一起写。
func should_mark_unlock_seen(key: String) -> bool:
	return key != "" and not needs_first_entry(key)


## 谱面库里这个 key 是第几首（找不到 -1）
func library_index(key: String) -> int:
	for i in library.size():
		if str(library[i].get("key", "")) == key:
			return i
	return -1


## 结算结果对应的谱面库条目（找不到返回 {}）
func library_entry_for(result: Dictionary) -> Dictionary:
	var entry = result.get("entry", {})
	if not (entry is Dictionary):
		return {}
	var index := library_index(str(entry.get("key", "")))
	return library[index] if index >= 0 else {}


## 通关掉落：列表里第 N 首谱面掉第 N 篇剧情（按文件名自然排序），每篇只掉一次。
func grant_story_drop(result: Dictionary) -> Dictionary:
	var key := str(library_entry_for(result).get("key", ""))
	if key == "":
		return {}
	var index := library_index(key)
	if index < 0:
		return {}
	var stories := StorySource.scan()
	if index >= stories.size():
		return {}
	var story: Dictionary = stories[index]
	var story_name := str(story.get("file", ""))
	if not StorySource.grant_unlock(story_name):
		return {}
	return {
		"file": story_name,
		"title": str(story.get("title", story_name.get_basename())),
		"number": index + 1,
	}


## 曲绘掉落：一首曲子第一次被完整玩完（自动演示不算）就进收藏品。
## 曲绘的解锁状态直接由「通关过没有」决定，不额外存一份。
func grant_cover_drop(result: Dictionary) -> Dictionary:
	var item := library_entry_for(result)
	if item.is_empty() or not bool(item.get("has_cover", false)):
		return {}
	if is_cleared(str(item.get("key", ""))):
		return {}  # 已经有了：重打不再提示
	return {"key": str(item.get("key", "")), "title": str(item.get("title", ""))}


## 选曲列表里第 index 首能不能玩：
func is_chart_unlocked(index: int) -> bool:
	if settings != null and settings.unlock_all:
		return true
	if index <= 0:
		return true
	if index >= library.size():
		return false
	var prev: Dictionary = library[index - 1]
	return is_cleared(str(prev.get("key", "")))


func load_stats() -> void:
	var cf := ConfigFile.new()
	if cf.load(STATS_PATH) != OK:
		return
	stats["plays"] = int(cf.get_value("stats", "plays", 0))
	stats["best_score"] = int(cf.get_value("stats", "best_score", 0))
	stats["best_title"] = str(cf.get_value("stats", "best_title", ""))
	stats["best_acc"] = float(cf.get_value("stats", "best_acc", 0.0))
	# 老存档没有累计量：按「每局都等于最高分」补齐，免得平均数一读出来就是 0
	if cf.has_section_key("stats", "score_total"):
		stats["score_total"] = float(cf.get_value("stats", "score_total", 0.0))
		stats["acc_total"] = float(cf.get_value("stats", "acc_total", 0.0))
	else:
		stats["score_total"] = float(stats["best_score"]) * float(stats["plays"])
		stats["acc_total"] = float(stats["best_acc"]) * float(stats["plays"])
	cleared.clear()
	for key in cf.get_value("progress", "cleared", PackedStringArray()):
		var text := str(key)
		if text != "":
			cleared.append(text)
	unlock_seen.clear()
	for key in cf.get_value("progress", "unlock_seen", PackedStringArray()):
		var seen := str(key)
		if seen != "":
			unlock_seen.append(seen)
	entered.clear()
	for key in cf.get_value("progress", "entered", PackedStringArray()):
		var went_in := str(key)
		if went_in != "":
			entered.append(went_in)
	best_records.clear()
	var records = cf.get_value("progress", "best", {})
	if records is Dictionary:
		for key in records:
			var item = records[key]
			if item is Dictionary:
				best_records[str(key)] = {
					"score": int(item.get("score", 0)),
					"acc": float(item.get("acc", 0.0)),
					"fc": bool(item.get("fc", false)),
					"ap": bool(item.get("ap", false)),
				}


func save_stats() -> void:
	var cf := ConfigFile.new()
	cf.set_value("stats", "plays", int(stats.get("plays", 0)))
	cf.set_value("stats", "best_score", int(stats.get("best_score", 0)))
	cf.set_value("stats", "best_title", str(stats.get("best_title", "")))
	cf.set_value("stats", "best_acc", float(stats.get("best_acc", 0.0)))
	cf.set_value("stats", "score_total", float(stats.get("score_total", 0.0)))
	cf.set_value("stats", "acc_total", float(stats.get("acc_total", 0.0)))
	cf.set_value("progress", "cleared", PackedStringArray(cleared))
	cf.set_value("progress", "unlock_seen", PackedStringArray(unlock_seen))
	cf.set_value("progress", "entered", PackedStringArray(entered))
	cf.set_value("progress", "best", best_records)
	cf.save(STATS_PATH)


func goto_select() -> void:
	get_tree().change_scene_to_file(SELECT_SCENE)


## 章节选择（主界面「开始游戏」→ 这里 → 选完章节才进选曲）
func goto_chapters() -> void:
	get_tree().change_scene_to_file(CHAPTER_SCENE)


## 主界面（启动 → 警告 → 开屏 → 这里 → 点「开始游戏」才进章节选择）
func goto_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## 开屏画面（标题 logo + 点任意键进入游戏）
func goto_splash() -> void:
	get_tree().change_scene_to_file(SPLASH_SCENE)


func goto_collection() -> void:
	get_tree().change_scene_to_file(COLLECTION_SCENE)


func goto_profile() -> void:
	get_tree().change_scene_to_file(PROFILE_SCENE)


func goto_warning() -> void:
	get_tree().change_scene_to_file(WARNING_SCENE)


func goto_settings() -> void:
	# 记住是从哪个界面进来的，返回时回原处（开始界面 / 选曲界面）
	var cur := get_tree().current_scene
	if cur != null and str(cur.scene_file_path) != "":
		_settings_return = str(cur.scene_file_path)
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func back_from_settings() -> void:
	get_tree().change_scene_to_file(_settings_return)


func goto_results() -> void:
	get_tree().change_scene_to_file(RESULTS_SCENE)


func quit_game() -> void:
	get_tree().quit()
