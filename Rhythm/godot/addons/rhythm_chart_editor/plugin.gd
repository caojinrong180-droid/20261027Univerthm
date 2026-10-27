@tool
extends EditorPlugin
## 制谱器插件入口。
##
## 形态说明：编辑器本体放在**独立的 Editor 窗口**里。
## 原因：编辑器「主屏幕」分到的矩形会跟左右两个 dock 重叠（高 DPI 下尤其明显），
## 直接铺在上面时右侧面板会被 dock 盖住。独立窗口的尺寸由自己决定，不受 dock 影响。
##
## 顶部「制谱器」标签页作为入口页：切到它会自动打开（或前置）制谱器窗口，
## 也可以从菜单「编辑器 → 打开制谱器窗口」打开。

const SCREEN_SCRIPT := preload("res://addons/rhythm_chart_editor/ui/chart_editor_screen.gd")

var _launcher: Control = null
var _window: Window = null
var _screen: Control = null


func _enter_tree() -> void:
	_launcher = _build_launcher()
	var host := EditorInterface.get_editor_main_screen()
	if host != null:
		# 编辑器启动阶段主屏幕可能正在装配子节点，直接 add_child 会被拒绝，所以延迟挂载。
		host.add_child.call_deferred(_launcher)
	else:
		push_error("Rhythm Chart Editor: 拿不到编辑器主屏幕容器")
	add_tool_menu_item("打开制谱器窗口", _open_window)


func _exit_tree() -> void:
	remove_tool_menu_item("打开制谱器窗口")
	if is_instance_valid(_window):
		_window.queue_free()
	_window = null
	_screen = null
	if is_instance_valid(_launcher):
		if _launcher.is_inside_tree():
			_launcher.queue_free()
		else:
			_launcher.free()
	_launcher = null


# ------------------------------------------------------------ 主屏幕入口页

func _build_launcher() -> Control:
	var page := Control.new()
	page.name = "RhythmChartLauncher"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "制谱器"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var hint := Label.new()
	hint.text = "在独立窗口里打开，不受编辑器左右 dock 影响。\n切到这个标签页会自动打开；也可以点菜单「编辑器 → 打开制谱器窗口」。"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	box.add_child(hint)

	var open_btn := Button.new()
	open_btn.text = "打开制谱器窗口"
	open_btn.custom_minimum_size = Vector2(220, 40)
	open_btn.pressed.connect(_open_window)
	box.add_child(open_btn)
	return page


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_launcher):
		_launcher.visible = visible
	if visible:
		_open_window()


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "制谱器"


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	if theme:
		var icon := theme.get_icon("AudioStreamPlayer", "EditorIcons")
		if icon:
			return icon
	return null


# ------------------------------------------------------------ 独立窗口

func _target_window_size() -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect()
	return Vector2i(
		clampi(int(float(usable.size.x) * 0.82), 900, 2400),
		clampi(int(float(usable.size.y) * 0.82), 600, 1500))


func _open_window() -> void:
	if is_instance_valid(_window):
		_window.show()
		_window.grab_focus()
		return
	_window = Window.new()
	_window.title = "制谱器 · Rhythm Chart Editor"
	_window.min_size = Vector2i(900, 600)
	_window.size = _target_window_size()
	_window.close_requested.connect(func() -> void:
		# 关窗即销毁：下次打开会用最新的脚本重建界面。
		# 否则改了 addon 里的 UI 代码，旧窗口会一直显示旧节点，看起来像"没生效"。
		_close_window()
	)
	EditorInterface.get_base_control().add_child(_window)

	_screen = SCREEN_SCRIPT.new()
	_screen.name = "ChartEditorScreen"
	_window.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_window.popup_centered(_target_window_size())
	call_deferred("_relayout_window")


## 窗口尺寸/子节点布局有时要等一两帧才生效，这里再确认一次。
func _relayout_window() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_window):
		_window.size = _target_window_size()
	if is_instance_valid(_screen):
		_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_screen.queue_redraw()


## 关窗：整个窗口和界面一起销毁，下次打开按最新代码重建。
func _close_window() -> void:
	if is_instance_valid(_window):
		_window.queue_free()
	_window = null
	_screen = null
