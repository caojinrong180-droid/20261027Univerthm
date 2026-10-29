@tool
extends Button
## 连接写在组件中，打包为 .tscn 后悬停与键盘焦点仍然有效。

@export var primary := false


func _ready() -> void:
	for sig in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		if not sig.is_connected(_refresh):
			sig.connect(_refresh)
	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)
	_refresh()


func _on_toggled(_value: bool) -> void:
	_refresh()


func _refresh() -> void:
	var frame := get_node_or_null("ButtonFrame")
	if frame == null:
		return
	var active := is_hovered() or has_focus() or button_pressed
	frame.edge = Color("e5caff") if active else (Color("cdadff") if primary else Color("75608e"))
	if active:
		frame.fill = Color("7130db") if primary or button_pressed else Color(0.09, 0.035, 0.17, 0.96)
	else:
		frame.fill = Color("5416c5") if primary else Color(0.025, 0.02, 0.055, 0.92)
	frame.glow = active or primary
