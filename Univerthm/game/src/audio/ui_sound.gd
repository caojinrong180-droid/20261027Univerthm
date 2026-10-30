class_name UiSound
extends Node
## 主菜单的界面音效：**按下按钮** → `click.wav`（悬停不发声）。
##
## 挂成 App 的子节点（和 MenuMusic 一样跨场景存活），这样点「开始游戏」换场景时
## 点击音效不会被掐断。只有主界面把按钮接上来，其它界面不放。

const CLICK_SOUND := "res://audio/click.wav"

## 音量（dB），想调大小改这里就行
@export var click_volume_db := -9.0

var _click: AudioStreamPlayer


func _ready() -> void:
	# 主界面的入场动画、换场景都在跑，音效不能跟着停
	process_mode = Node.PROCESS_MODE_ALWAYS
	_click = AudioStreamPlayer.new()
	_click.name = "ClickPlayer"
	_click.bus = "Master"
	_click.volume_db = click_volume_db
	_click.stream = load(CLICK_SOUND)
	if _click.stream == null:
		push_warning("界面音效载不进来：" + CLICK_SOUND)
	add_child(_click)


## 按下按钮时调用（鼠标左键点、回车 / 空格确认都算）。
func play_click() -> void:
	if _click != null and _click.stream != null:
		_click.play()
