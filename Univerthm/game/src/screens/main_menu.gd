extends Control
## 主界面。界面节点都在 scenes/main_menu.tscn 里，可以在编辑器里直接拖；
## 负责界面交互、错峰回弹入场，以及背景和立绘的轻量动态。

signal entrance_finished
signal glow_revealed

const BANNERS_DIR := "res://assets/banners"

## 立绘显示规则（对齐样图：头顶靠上、腿被底边裁掉）
const GIRL_HEIGHT := 880.0
const GIRL_TOP := 90.0
const GIRL_CENTER_X := 940.0

## 同组控件一起动，姓名牌和文字始终对齐。
const ENTRANCE_GROUPS := [
	["Line"], ["NamePlate", "NameLabel"], ["StartButton"],
	["CollectionButton"], ["SettingButton", "ProfileButton"],
	["SwitchButton"], ["Version"],
]

@export_range(0.1, 1.5, 0.05) var fade_in_duration := 0.65
@export_range(0.3, 1.5, 0.05) var entrance_duration := 0.72
@export_range(0.0, 0.2, 0.005) var entrance_stagger := 0.065
@export_range(80.0, 480.0, 10.0) var entrance_distance := 250.0
@export_range(0.0, 2.0, 0.05) var idle_motion_strength := 1.0
@export var pointer_parallax := true
@export_range(1.0, 8.0, 0.1) var glow_reveal_duration := 3.8
@export_range(0.0, 1.5, 0.05) var glow_start_delay := 0.15

@onready var _background: TextureRect = $Background
@onready var _glow: ColorRect = $PurpleGlow
@onready var _ambient_glitch: MenuGlitch = $AmbientGlitch
@onready var _pointer_collapse: MenuPointerCollapse = $MouseCollapse
@onready var _girl: TextureRect = $Banner
@onready var _name_label: Label = $NameLabel
@onready var _start_button: SpriteButton = $StartButton
@onready var _switch_button: SpriteButton = $SwitchButton

var _banners: Array = []
var _menu_buttons: Array[SpriteButton] = []
var _girl_home := Vector2.ZERO
var _motion_time := 0.0
var _pointer := Vector2.ZERO
var _character_reveal := 0.0
var _banner_busy := false
var _banner_tween: Tween
var _background_material: ShaderMaterial
var _glow_material: ShaderMaterial


func _ready() -> void:
	modulate.a = 0.0
	_background.position = Vector2.ZERO
	_background.scale = Vector2.ONE
	_background_material = _background.material as ShaderMaterial
	_glow_material = _glow.material as ShaderMaterial
	_set_glow_reveal(0.0)
	if _background_material != null:
		_background_material.set_shader_parameter("motion_strength", idle_motion_strength)
	theme = UiTheme.theme()
	App.refresh_library()
	_banners = _collect_banners()

	_start_button.pressed.connect(func(): App.goto_select())
	($CollectionButton as SpriteButton).pressed.connect(func(): App.goto_collection())
	($SettingButton as SpriteButton).pressed.connect(func(): App.goto_settings())
	($ProfileButton as SpriteButton).pressed.connect(func(): App.goto_profile())
	_switch_button.pressed.connect(_cycle_banner)

	var nm := _player_name()
	_name_label.text = ("User :  %s" % nm) if nm != "User" else "User :  Player"

	_apply_banner()
	resized.connect(_update_motion_pivots)
	_update_motion_pivots.call_deferred()
	_begin_entrance()


func _begin_entrance() -> void:
	var entry := create_tween().set_parallel(true)
	entry.tween_property(self, "modulate:a", 1.0, fade_in_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	entry.tween_property(self, "_character_reveal", 1.0, 0.95).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_girl.self_modulate.a = 0.0
	for group_index in ENTRANCE_GROUPS.size():
		var delay := 0.10 + group_index * entrance_stagger
		for node_name in ENTRANCE_GROUPS[group_index]:
			var control := get_node(NodePath(node_name)) as Control
			var home_x := control.position.x
			control.position.x = home_x - entrance_distance
			control.self_modulate.a = 0.0
			entry.tween_property(control, "position:x", home_x, entrance_duration).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			entry.tween_property(control, "self_modulate:a", 1.0, 0.24).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			if control is SpriteButton:
				_menu_buttons.append(control)
				control.mouse_filter = Control.MOUSE_FILTER_IGNORE
				control.focus_mode = Control.FOCUS_NONE
	entry.finished.connect(_finish_entrance)


func _finish_entrance() -> void:
	for button in _menu_buttons:
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_ALL
	_start_button.grab_focus()
	_ambient_glitch.start()
	_pointer_collapse.start()
	var glow_entry := create_tween()
	glow_entry.tween_interval(glow_start_delay)
	glow_entry.tween_method(_set_glow_reveal, 0.0, 1.0, glow_reveal_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glow_entry.finished.connect(glow_revealed.emit)
	entrance_finished.emit()


func _set_glow_reveal(progress: float) -> void:
	if _glow_material != null:
		_glow_material.set_shader_parameter("reveal_progress", progress)


func _update_motion_pivots() -> void:
	_girl.pivot_offset = _girl.size * Vector2(0.5, 0.78)
	if _glow_material != null:
		_glow_material.set_shader_parameter("viewport_size", _glow.size)


func _process(delta: float) -> void:
	_motion_time += delta
	var target := Vector2.ZERO
	var mouse := get_local_mouse_position()
	if pointer_parallax and size.x > 0.0 and size.y > 0.0 and Rect2(Vector2.ZERO, size).has_point(mouse):
		target = (mouse / size - Vector2(0.5, 0.5)) * 2.0
	_pointer = _pointer.lerp(target, 1.0 - exp(-delta * 4.5))
	var t := _motion_time
	var strength := idle_motion_strength
	# 扩图背景在材质中整体轻移、呼吸缩放；控件固定，不影响按钮命中区域。
	if _background_material != null:
		_background_material.set_shader_parameter("pointer_offset", _pointer)
		_background_material.set_shader_parameter("motion_time", t)
		_background_material.set_shader_parameter("motion_strength", strength)
	var breath := sin(t * 1.15)
	_girl.scale = Vector2(1.0 + breath * 0.0025 * strength, 1.0 + breath * 0.004 * strength)
	_girl.rotation = sin(t * 0.58) * deg_to_rad(0.14) * strength
	var idle_offset := Vector2(sin(t * 0.53) * 1.5, -sin(t * 1.05) * 3.5) * strength
	var entry_offset := Vector2(42.0, 12.0) * (1.0 - _character_reveal)
	_girl.position = _girl_home + idle_offset + _pointer * Vector2(9.0, 5.0) * strength + entry_offset
	_girl.self_modulate.a = _character_reveal


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		App.quit_game()


# --------------------------------------------------------------------------- #
# 立绘
# --------------------------------------------------------------------------- #

func _collect_banners() -> Array:
	var out: Array = []
	var dir := DirAccess.open(BANNERS_DIR)
	if dir != null:
		for f in dir.get_files():
			var lower := str(f).to_lower()
			if lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".webp"):
				out.append("%s/%s" % [BANNERS_DIR, f])
	out.sort()
	return out


func _banner_index() -> int:
	if _banners.is_empty():
		return 0
	var idx := int(App.settings.banner_index) if App.settings != null else 0
	return clampi(idx, 0, _banners.size() - 1)


func _apply_banner() -> void:
	if _girl == null or _banners.is_empty():
		return
	var path := str(_banners[_banner_index()])
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	_girl.texture = tex
	if tex != null and tex.get_height() > 0:
		var aspect := float(tex.get_width()) / float(tex.get_height())
		_girl.size = Vector2(GIRL_HEIGHT * aspect, GIRL_HEIGHT)
		_girl_home = Vector2(GIRL_CENTER_X - _girl.size.x * 0.5, GIRL_TOP)
		_girl.position = _girl_home
		_update_motion_pivots()
	var art_material := _girl.material as ShaderMaterial
	if art_material != null:
		art_material.set_shader_parameter("motion_strength", idle_motion_strength)


func _cycle_banner() -> void:
	if _banner_busy or _banners.size() <= 1:
		return
	_banner_busy = true
	if App.settings != null:
		App.settings.banner_index = (_banner_index() + 1) % _banners.size()
		App.settings.save()
	_banner_tween = create_tween()
	_banner_tween.tween_property(self, "_character_reveal", 0.0, 0.16).set_trans(Tween.TRANS_SINE)
	_banner_tween.tween_callback(_apply_banner)
	_banner_tween.tween_property(self, "_character_reveal", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_callback(func(): _banner_busy = false)


func _player_name() -> String:
	if App.settings != null and str(App.settings.player_name).strip_edges() != "":
		return str(App.settings.player_name)
	return "User"
