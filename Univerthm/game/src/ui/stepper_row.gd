class_name StepperRow
extends HBoxContainer
## 设置里那种「名字 [数值] ◀ ▶」的一行。场景里放一个、挂这个脚本、改 title 就能用。
## 也可以在代码里 StepperRow.new() 然后 set_title()。

signal stepped(dir: int)

@export var title := "" : set = set_title
@export var value_width := 210

var _title_label: Label
var _value_label: Label


func _ready() -> void:
	if get_child_count() == 0:
		_build()
	_title_label = get_node_or_null("Title") as Label
	_value_label = get_node_or_null("ValueBox/Value") as Label
	if _title_label != null:
		_title_label.text = title
	var prev := get_node_or_null("Prev") as Button
	if prev != null and not prev.pressed.is_connected(_on_prev):
		prev.pressed.connect(_on_prev)
	var next := get_node_or_null("Next") as Button
	if next != null and not next.pressed.is_connected(_on_next):
		next.pressed.connect(_on_next)


func set_title(value: String) -> void:
	title = value
	if _title_label != null:
		_title_label.text = value


func set_value(text: String) -> void:
	if _value_label == null:
		_value_label = get_node_or_null("ValueBox/Value") as Label
	if _value_label != null:
		_value_label.text = text


func _on_prev() -> void:
	stepped.emit(-1)


func _on_next() -> void:
	stepped.emit(1)


## 代码搭界面时用（场景里已经有这些节点）
func _build() -> void:
	add_theme_constant_override("separation", 8)

	_title_label = UiKit.label(title, 14, Palette.DIM)
	_title_label.name = "Title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_title_label)

	var value_box := PanelContainer.new()
	value_box.name = "ValueBox"
	value_box.add_theme_stylebox_override("panel",
		UiTheme.style_box(Palette.PANEL_2, 6, 1, Palette.LINE, Vector4(12, 3, 12, 3)))
	value_box.custom_minimum_size = Vector2(value_width, 28)
	add_child(value_box)

	_value_label = UiKit.mono_label("", 14, Palette.TEXT)
	_value_label.name = "Value"
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_box.add_child(_value_label)

	var prev := UiKit.button("◀", 13, "GhostButton")
	prev.name = "Prev"
	add_child(prev)
	var next := UiKit.button("▶", 13, "GhostButton")
	next.name = "Next"
	add_child(next)
