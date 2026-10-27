extends Node
## 截图驱动：把制谱器主界面和游戏侧参考渲染各抓一张 PNG。
##   godot --path . res://test/shot.tscn --resolution 1600x900 --quit-after 600
## 产物在 user:// 下：shot_editor.png / shot_stage.png

const DEMO := "res://charts/demo_neon_pulse.json"


func _ready() -> void:
	# 根节点初始化期间 add_child 会失败，等一帧再挂界面。
	await get_tree().process_frame
	await _shoot_editor()
	await _shoot_stage()
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame


func _capture(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://" + name)
	print("SHOT ", name, " err=", err, " size=", img.get_size())


func _shoot_editor() -> void:
	var screen_script := load("res://addons/rhythm_chart_editor/ui/chart_editor_screen.gd")
	var screen: Control = screen_script.new()
	get_tree().root.add_child(screen)
	# 在根节点初始化期间 add_child 会推迟 _ready，等一帧再操作内部控件。
	await get_tree().process_frame
	if FileAccess.file_exists(DEMO):
		screen._load_chart_file(DEMO)
	screen._set_playhead(6.4)
	screen._lane_list.select(1)
	screen._on_lane_list_selected(1)
	await _settle(12)
	_capture("shot_editor.png")

	# 再抓一张"窄窗口"版本：验证小尺寸下三栏是否还在
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1015.0, 637.0)
	await _settle(6)
	_capture("shot_editor_small.png")

	# 再抓一张"点过校验谱面"之后的：复现长文本把布局撑坏的问题
	screen._validate_and_report()
	await _settle(4)
	_capture("shot_editor_validate.png")

	screen.queue_free()
	await get_tree().process_frame


func _shoot_stage() -> void:
	var packed := load("res://examples/demo_stage.tscn")
	if packed == null:
		return
	var stage: Node2D = packed.instantiate()
	get_tree().root.add_child(stage)
	await get_tree().process_frame
	stage.autoplay = false
	stage.song_time = 6.4
	await _settle(10)
	_capture("shot_stage.png")
	stage.queue_free()
	await get_tree().process_frame
