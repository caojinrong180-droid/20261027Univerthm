class_name AvatarCircle
extends Control
## 圆头像：一个带描边的圆 + 名字首字。改 player_name 就会跟着变。

@export var player_name := "User" : set = set_player_name
@export var ring_color := Color("#4cc9f0")
@export var text_color := Color("#dfe4ee")


func set_player_name(value: String) -> void:
	player_name = value
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c, r, Color(ring_color.r, ring_color.g, ring_color.b, 0.18))
	draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(ring_color.r, ring_color.g, ring_color.b, 0.8), 2.0, true)
	var initial := player_name.substr(0, 1).to_upper()
	if initial == "":
		return
	var font := UiTheme.mono()
	var fs := int(maxf(16.0, r * 1.0))
	var w := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w * 0.5, c.y + float(fs) * 0.36), initial,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
