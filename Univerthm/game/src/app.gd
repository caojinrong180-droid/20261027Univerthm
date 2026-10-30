extends Node
## 全局单例（autoload 名 = App）：设置 / 谱面库 / 当前游玩会话 / 结算数据。
##
## 屏幕之间只通过这个单例传数据，不互相引用。

const WARNING_SCENE := "res://scenes/warning.tscn"
const SPLASH_SCENE := "res://scenes/splash.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const COLLECTION_SCENE := "res://scenes/collection.tscn"
const PROFILE_SCENE := "res://scenes/profile.tscn"
const SELECT_SCENE := "res://scenes/song_select.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const RESULTS_SCENE := "res://scenes/results.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const MenuMusic = preload("res://src/audio/menu_music.gd")
const ScreenGlitch = preload("res://src/ui/screen_glitch.gd")

## 谱面扫描根目录：随游戏发布 + 用户拖进来的
const CHART_ROOTS := ["res://charts", "user://charts"]

var settings: AppSettings
var menu_music: MenuMusic
var screen_glitch: ScreenGlitch
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
## 跨场景的一次性提示（选曲界面底部状态栏会显示）
var toast := ""

## 从哪个界面进的设置，返回时回哪（默认回选曲）
var _settings_return := "res://scenes/song_select.tscn"

## 玩家档案统计（user://profile.cfg）：游玩次数 / 平均分 / 平均准确率 / 最高分
## score_total + acc_total 是累计量，平均数 = 累计 / 游玩次数；自动演示不计入。
const STATS_PATH := "user://profile.cfg"
var stats := {
	"plays": 0, "best_score": 0, "best_title": "", "best_acc": 0.0,
	"score_total": 0.0, "acc_total": 0.0,
}
## 通关过的谱面 key（自动演示不计入）。选曲列表按顺序解锁：第 1 首永远能玩，
## 后面每首要先把前一首通关。
var cleared: Array[String] = []
## 已经演过解锁动画的谱面 key：解锁动画每首只演一次，再进同一首直接进倒计时。
var unlock_seen: Array[String] = []
## 每首曲子的最好成绩：谱面 key → { "score": int, "acc": float }（自动演示不计入）。
## 选曲页详情里显示的那个 BEST。
var best_records := {}


func _ready() -> void:
	settings = AppSettings.load_settings()
	load_stats()
	refresh_library()
	menu_music = MenuMusic.new()
	menu_music.name = "MenuMusic"
	add_child(menu_music)
	refresh_music_volume()
	get_tree().scene_changed.connect(_sync_menu_music)
	_sync_menu_music.call_deferred()
	screen_glitch = ScreenGlitch.new()
	screen_glitch.name = "ScreenGlitch"
	add_child(screen_glitch)
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


## F11：全屏 / 窗口切换（全屏就是按屏幕原生分辨率渲染，最清晰）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var win := get_window()
		win.mode = Window.MODE_WINDOWED if win.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()


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

func play_entry(entry: Dictionary, autoplay := false) -> bool:
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
	}
	autoplay_once = autoplay
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)
	return true


func retry() -> void:
	if session.is_empty():
		goto_select()
		return
	autoplay_once = autoplay_enabled()
	play_entry(session["entry"], autoplay_once)


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
			# 每首曲子自己的最好成绩（分数更高才算刷新）
			var old: Dictionary = best_records.get(key, {})
			if score > int(old.get("score", -1)):
				best_records[key] = {
					"score": score,
					"acc": float(res.get("accuracy", 0.0)),
				}
	save_stats()


## 某首曲子的最好成绩 { score, acc }；没打过返回空字典
func best_record(key: String) -> Dictionary:
	var found = best_records.get(key, {})
	return found if found is Dictionary else {}


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


## 通关掉落：列表里第 N 首谱面掉第 N 篇剧情（按文件名自然排序），每篇只掉一次。
## 返回 {} = 这次没有新掉落；否则 { file, title, number }，结算界面据此显示提示。
## 只记「在谱面库里的第几首」——玩家按顺序解锁着往下打，正好一篇对应一首。
func grant_story_drop(result: Dictionary) -> Dictionary:
	var entry = result.get("entry", {})
	if not (entry is Dictionary):
		return {}
	var key := str(entry.get("key", ""))
	if key == "":
		return {}
	var index := -1
	for i in library.size():
		if str(library[i].get("key", "")) == key:
			index = i
			break
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


## 选曲列表里第 index 首能不能玩：
## 第 1 首永远能玩，后面每首要前一首先通关；设置里开了「全部解锁」就都放行。
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
	# （之后的游玩会正常累加，平均值会慢慢往真实水平收敛）。
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
	best_records.clear()
	var records = cf.get_value("progress", "best", {})
	if records is Dictionary:
		for key in records:
			var item = records[key]
			if item is Dictionary:
				best_records[str(key)] = {
					"score": int(item.get("score", 0)),
					"acc": float(item.get("acc", 0.0)),
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
	cf.set_value("progress", "best", best_records)
	cf.save(STATS_PATH)


func goto_select() -> void:
	get_tree().change_scene_to_file(SELECT_SCENE)


## 主界面（启动 → 警告 → 开屏 → 这里 → 点「开始游戏」才进选曲）
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
