class_name UiSound
extends Node
## 主菜单的界面音效：**鼠标移到按钮上** → `chose.wav`，**按下按钮** → `click.wav`。
##
## 挂成 App 的子节点（和 MenuMusic 一样跨场景存活），这样点「开始游戏」换场景时
## 点击音效不会被掐断。只有主界面把按钮接上来，其它界面不放这两声。

const HOVER_SOUND := "res://audio/chose.wav"
const CLICK_SOUND := "res://audio/click.wav"
## 连着的悬停事件之间至少隔这么久：按钮上浮时鼠标会来回蹭边缘，别连成一串
const HOVER_RETRIGGER_MS := 80

## 两声音量（dB），想调大小改这里就行
@export var hover_volume_db := -12.0
@export var click_volume_db := -9.0

var _hover: AudioStreamPlayer
var _click: AudioStreamPlayer
var _last_hover_ms := -100000


func _ready() -> void:
	# 主界面的入场动画、换场景都在跑，音效不能跟着停
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hover = _make_player("HoverPlayer", HOVER_SOUND, hover_volume_db)
	_click = _make_player("ClickPlayer", CLICK_SOUND, click_volume_db)


func _make_player(player_name: String, path: String, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = "Master"
	player.volume_db = volume
	player.stream = load(path)
	if player.stream == null:
		push_warning("界面音效载不进来：" + path)
	add_child(player)
	return player


## 鼠标移到一个按钮上时调用（接到按钮的 mouse_entered 上）。
func play_hover() -> void:
	if _hover == null or _hover.stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms < HOVER_RETRIGGER_MS:
		return
	_last_hover_ms = now
	_hover.play()


## 按下按钮时调用（鼠标左键点、回车 / 空格确认都算）。
func play_click() -> void:
	if _click != null and _click.stream != null:
		_click.play()
