extends Node
## 全局单例（autoload 名 = App）：设置 / 谱面库 / 当前游玩会话 / 结算数据。
##
## 屏幕之间只通过这个单例传数据，不互相引用。

const WARNING_SCENE := "res://scenes/warning.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const COLLECTION_SCENE := "res://scenes/collection.tscn"
const PROFILE_SCENE := "res://scenes/profile.tscn"
const SELECT_SCENE := "res://scenes/song_select.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay.tscn"
const RESULTS_SCENE := "res://scenes/results.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

## 谱面扫描根目录：随游戏发布 + 用户拖进来的
const CHART_ROOTS := ["res://charts", "user://charts"]

var settings: AppSettings
var library: Array = []
## 一次游玩：{ entry, chart, stream, cover, warnings, errors }
var session := {}
## 结算：见 gameplay.gd 的 _finish()
var last_result := {}
## 「自动演示」是这一次性的，不写进设置
var autoplay_once := false
## 跨场景的一次性提示（选曲界面底部状态栏会显示）
var toast := ""

## 从哪个界面进的设置，返回时回哪（默认回选曲）
var _settings_return := "res://scenes/song_select.tscn"

## 玩家档案统计（user://profile.cfg）：游玩次数 / 最高分 / 最近一次成绩
const STATS_PATH := "user://profile.cfg"
var stats := {"plays": 0, "best_score": 0, "best_title": "", "best_acc": 0.0}


func _ready() -> void:
	settings = AppSettings.load_settings()
	load_stats()
	refresh_library()


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


## 归档一局成绩（自动演示不计入）
func record_result(res: Dictionary) -> void:
	stats["plays"] = int(stats.get("plays", 0)) + 1
	var score := int(res.get("score", 0))
	if score > int(stats.get("best_score", 0)):
		stats["best_score"] = score
		stats["best_title"] = str(res.get("title", ""))
		stats["best_acc"] = float(res.get("accuracy", 0.0))
	save_stats()


func load_stats() -> void:
	var cf := ConfigFile.new()
	if cf.load(STATS_PATH) != OK:
		return
	stats["plays"] = int(cf.get_value("stats", "plays", 0))
	stats["best_score"] = int(cf.get_value("stats", "best_score", 0))
	stats["best_title"] = str(cf.get_value("stats", "best_title", ""))
	stats["best_acc"] = float(cf.get_value("stats", "best_acc", 0.0))


func save_stats() -> void:
	var cf := ConfigFile.new()
	cf.set_value("stats", "plays", int(stats.get("plays", 0)))
	cf.set_value("stats", "best_score", int(stats.get("best_score", 0)))
	cf.set_value("stats", "best_title", str(stats.get("best_title", "")))
	cf.set_value("stats", "best_acc", float(stats.get("best_acc", 0.0)))
	cf.save(STATS_PATH)


func goto_select() -> void:
	get_tree().change_scene_to_file(SELECT_SCENE)


## 主界面（启动 → 警告 → 这里 → 点「开始游戏」才进选曲）
func goto_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


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
