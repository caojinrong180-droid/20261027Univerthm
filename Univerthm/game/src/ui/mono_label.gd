class_name MonoLabel
extends Label
## 等宽字体的 Label。挂在场景里的 Label 上就会用等宽字体，不用写代码。

func _ready() -> void:
	add_theme_font_override("font", UiTheme.mono())
