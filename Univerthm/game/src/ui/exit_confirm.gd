extends Control
## 主菜单退出确认：角色从侧边入场，弹窗居中回弹。

signal confirmed
signal cancelled

const PleaPortrait = preload("res://src/ui/plea_portrait.gd")
const SPRING_STIFFNESS := 370.0
const SPRING_DAMPING := 22.0

var portrait: TextureRect
var panel: PanelContainer
var prompt: Label
var confirm_button: Button
var cancel_button: Button
var _shade: ColorRect
var _panel_y := 0.0
var _panel_velocity := 0.0
var _panel_scale := 1.0
var _scale_velocity := 0.0
var _opacity := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = ColorRect.new()
	_shade.color = Color(0.012, 0.006, 0.027, 0.76)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	UiKit.full_rect(_shade)
	add_child(_shade)
	portrait = PleaPortrait.new()
	portrait.name = "PleaPortrait"
	add_child(portrait)
	panel = NeonPanel.new()
	panel.name = "DialogPanel"
	panel.fill = Color(0.025, 0.017, 0.064, 0.96)
	panel.edge = Color("c49bff")
	panel.glow = true
	panel.size = Vector2(540, 204)
	panel.pivot_offset = panel.size * 0.5
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 30)
	for edge in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	prompt = UiKit.label("", 25, Color("f0e5ff"))
	prompt.name = "Prompt"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(prompt)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 20)
	column.add_child(actions)
	confirm_button = UiKit.button("退出游戏", 18)
	confirm_button.name = "ConfirmButton"
	confirm_button.custom_minimum_size = Vector2(132, 46)
	confirm_button.pressed.connect(confirmed.emit)
	actions.add_child(confirm_button)
	cancel_button = UiKit.button("留下来", 18)
	cancel_button.name = "CancelButton"
	cancel_button.custom_minimum_size = Vector2(132, 46)
	cancel_button.pressed.connect(close)
	actions.add_child(cancel_button)
	hide()
	set_process(false)


func open(index: int) -> void:
	prompt.text = "真的要退出吗——%s如是问之" % ("Kisai" if index == 1 else "Stra")
	show()
	portrait.show_plea(index)
	var center_y := (size.y - panel.size.y) * 0.5
	_panel_y = center_y + 115.0
	_panel_velocity = -560.0
	_panel_scale = 0.78
	_scale_velocity = 0.0
	_opacity = 0.0
	panel.position = Vector2((size.x - panel.size.x) * 0.5, _panel_y)
	panel.scale = Vector2.ONE * _panel_scale
	panel.modulate.a = 0.0
	_shade.modulate.a = 0.0
	set_process(true)
	cancel_button.grab_focus()


func close() -> void:
	if not visible:
		return
	portrait.hide_plea()
	hide()
	set_process(false)
	cancelled.emit()


func _process(delta: float) -> void:
	var target_y := (size.y - panel.size.y) * 0.5
	var remaining := minf(delta, 0.1)
	while remaining > 0.0:
		var dt := minf(remaining, 0.008)
		_panel_velocity += ((target_y - _panel_y) * SPRING_STIFFNESS - _panel_velocity * SPRING_DAMPING) * dt
		_panel_y += _panel_velocity * dt
		_scale_velocity += ((1.0 - _panel_scale) * SPRING_STIFFNESS - _scale_velocity * SPRING_DAMPING) * dt
		_panel_scale += _scale_velocity * dt
		remaining -= dt
	panel.position = Vector2((size.x - panel.size.x) * 0.5, _panel_y)
	panel.scale = Vector2.ONE * _panel_scale
	_opacity = minf(1.0, _opacity + delta * 5.0)
	panel.modulate.a = _opacity
	_shade.modulate.a = _opacity
