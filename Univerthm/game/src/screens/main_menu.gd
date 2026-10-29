extends Control
## 主界面。界面节点都在 scenes/main_menu.tscn 里，可以在编辑器里直接拖；
## 负责界面交互、错峰回弹入场，以及背景和立绘的轻量动态。

signal entrance_finished
signal glow_revealed

const ExitConfirm = preload("res://src/ui/exit_confirm.gd")

# 固定顺序并显式引用资源，导出后的游戏也能载入全部立绘。
const BANNER_TEXTURES := [
	preload("res://assets/banners/stra1.png"),
	preload("res://assets/banners/stra2.png"),
	preload("res://assets/banners/stra3.png"),
	preload("res://assets/banners/stra4.png"),
	preload("res://assets/banners/Kisai1.png"),
	preload("res://assets/banners/Kisai2.png"),
	preload("res://assets/banners/Kisai3.png"),
	preload("res://assets/banners/Kisai4.png"),
]
const BANNER_BLEND_DURATION := 0.24
const POSES_PER_CHARACTER := 4
const BANNER_SPRING_DECAY := 8.5
const BANNER_SPRING_FREQUENCY := 16.0

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
@onready var _outgoing_girl: TextureRect = $BannerOutgoing
@onready var _name_label: Label = $NameLabel
@onready var _start_button: SpriteButton = $StartButton
@onready var _switch_button: SpriteButton = $SwitchButton
@onready var _version_label: Label = $Version

var _banners: Array[Texture2D] = []
var _banner_masks: Dictionary = {}
var _current_banner := 0
var _active_character := 0 # 0 = Stra, 1 = Kisai
var _menu_buttons: Array[SpriteButton] = []
var _girl_home := Vector2.ZERO
var _motion_time := 0.0
var _pointer := Vector2.ZERO
var _character_reveal := 0.0
var _banner_busy := false
var _banner_tween: Tween
var _entrance_complete := false
var _banner_pending_steps := 0
var _banner_mix := 1.0
# x：横向惯性位移；y：挤压 / 拉伸；z：旋转。速度和位移一起衰减回零。
var _banner_spring := Vector3.ZERO
var _banner_velocity := Vector3.ZERO
var _outgoing_home := Vector2.ZERO
var _outgoing_scale := Vector2.ONE
var _outgoing_rotation := 0.0
var _background_material: ShaderMaterial
var _glow_material: ShaderMaterial
var _exit_confirm


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
	_banners.assign(BANNER_TEXTURES)
	_active_character = clampi(App.character_index, 0, 1)
	_current_banner = _active_character * POSES_PER_CHARACTER

	_start_button.pressed.connect(func(): App.goto_select())
	($CollectionButton as SpriteButton).pressed.connect(func(): App.goto_collection())
	($SettingButton as SpriteButton).pressed.connect(func(): App.goto_settings())
	($ProfileButton as SpriteButton).pressed.connect(func(): App.goto_profile())
	_switch_button.pressed.connect(_cycle_banner)
	_version_label.gui_input.connect(_on_version_input)

	var nm := _player_name()
	_name_label.text = ("User :  %s" % nm) if nm != "User" else "User :  Player"

	_apply_banner()
	_build_exit_confirm()
	_build_ui_sound()
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
	_entrance_complete = true
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
	_advance_banner_spring(delta)
	_update_character_motion()


func _update_character_motion() -> void:
	var t := _motion_time
	var strength := idle_motion_strength
	var breath := sin(t * 1.15)
	var idle_scale := Vector2(1.0 + breath * 0.0025 * strength, 1.0 + breath * 0.004 * strength)
	_girl.scale = idle_scale * Vector2(1.0 + _banner_spring.y, 1.0 - _banner_spring.y * 0.65)
	_girl.rotation = sin(t * 0.58) * deg_to_rad(0.14) * strength + _banner_spring.z
	var idle_offset := Vector2(sin(t * 0.53) * 1.5, -sin(t * 1.05) * 3.5) * strength
	var entry_offset := Vector2(42.0, 12.0) * (1.0 - _character_reveal)
	var spring_offset := Vector2(_banner_spring.x, -absf(_banner_spring.y) * 26.0)
	_girl.position = _girl_home + idle_offset + _pointer * Vector2(9.0, 5.0) * strength + entry_offset + spring_offset
	_girl.self_modulate.a = _character_reveal * _banner_mix
	if _outgoing_girl.visible:
		_outgoing_girl.position = _outgoing_home + Vector2(-28.0, -4.0) * _banner_mix
		_outgoing_girl.scale = _outgoing_scale * (1.0 - 0.025 * _banner_mix)
		_outgoing_girl.rotation = _outgoing_rotation - deg_to_rad(0.7) * _banner_mix
		_outgoing_girl.self_modulate.a = _character_reveal * (1.0 - _banner_mix)


func _gui_input(event: InputEvent) -> void:
	if not _entrance_complete or _exit_confirm.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 在根控件接收未被按钮消费的点击；透明空白和悬浮按钮不会误触角色。
		if _portrait_has_point(_girl, event.position) or _portrait_has_point(_outgoing_girl, event.position):
			accept_event()
			_cycle_banner()


func _on_version_input(event: InputEvent) -> void:
	if not _entrance_complete or _exit_confirm.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_version_label.accept_event()
		_toggle_character()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _exit_confirm.visible:
			_exit_confirm.close()
		else:
			_exit_confirm.open(_active_character)


func _build_exit_confirm() -> void:
	_exit_confirm = ExitConfirm.new()
	_exit_confirm.name = "ExitConfirm"
	UiKit.full_rect(_exit_confirm)
	add_child(_exit_confirm)
	_exit_confirm.confirmed.connect(App.quit_game)


## 主界面的按钮音效（只有这里有）：鼠标移上去 → chose.wav，按下 → click.wav。
## 音效节点在 App 里（跨场景存活，点「开始游戏」换场景时点击音效不会被掐断），
## 入场动画期间按钮的 mouse_filter 还是 IGNORE，所以刚进主界面时不会乱响。
func _build_ui_sound() -> void:
	if App.ui_sound == null:
		return
	for child in get_children():
		if child is SpriteButton:
			var button := child as SpriteButton
			if not button.mouse_entered.is_connected(App.ui_sound.play_hover):
				button.mouse_entered.connect(App.ui_sound.play_hover)
			if not button.pressed.is_connected(App.ui_sound.play_click):
				button.pressed.connect(App.ui_sound.play_click)


# --------------------------------------------------------------------------- #
# 立绘
# --------------------------------------------------------------------------- #

func _banner_index() -> int:
	return _current_banner


func _apply_banner() -> void:
	if _girl == null or _banners.is_empty():
		return
	var tex := _banners[_banner_index()]
	_girl.texture = tex
	if not _banner_masks.has(tex):
		var image := tex.get_image()
		if image.is_compressed():
			image.decompress()
		var mask := BitMap.new()
		mask.create_from_image_alpha(image, 0.12)
		_banner_masks[tex] = mask
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
	if not _entrance_complete or _banners.size() < POSES_PER_CHARACTER * 2:
		return
	if _banner_busy:
		_banner_pending_steps += 1
		return
	var first := _active_character * POSES_PER_CHARACTER
	var next := first + (_current_banner - first + 1) % POSES_PER_CHARACTER
	_start_banner_transition(next)


func _toggle_character() -> void:
	_active_character = 1 - _active_character
	App.character_index = _active_character
	_banner_pending_steps = 0
	_start_banner_transition(_active_character * POSES_PER_CHARACTER)


func _start_banner_transition(next_index: int) -> void:
	# 版本号点击可以打断过渡，使用当前更清晰的一张作为淡出的旧立绘。
	var source := _outgoing_girl if _banner_busy and _banner_mix < 0.5 else _girl
	var old_texture := source.texture
	var old_size := source.size
	var old_pivot := source.pivot_offset
	var old_position := source.position
	var old_scale := source.scale
	var old_rotation := source.rotation
	if _banner_tween != null and _banner_tween.is_running():
		_banner_tween.kill()
	_banner_busy = true
	# 保留上一张当前的屏幕姿态，连续点击时也不会突然跳回原位。
	_outgoing_girl.texture = old_texture
	_outgoing_girl.size = old_size
	_outgoing_girl.pivot_offset = old_pivot
	_outgoing_home = old_position
	_outgoing_scale = old_scale
	_outgoing_rotation = old_rotation
	_outgoing_girl.show()
	_current_banner = next_index
	_apply_banner()
	_banner_mix = 0.0
	_banner_spring = Vector3(44.0, -0.065, deg_to_rad(-1.1))
	_banner_velocity = Vector3(-50.0, 0.2, deg_to_rad(2.0))
	_update_character_motion()
	_banner_tween = create_tween()
	_banner_tween.tween_property(self, "_banner_mix", 1.0, BANNER_BLEND_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_banner_tween.finished.connect(_finish_banner_transition)


func _finish_banner_transition() -> void:
	_banner_mix = 1.0
	_outgoing_girl.hide()
	_outgoing_girl.texture = null
	_banner_busy = false
	_update_character_motion()
	if _banner_pending_steps > 0:
		_banner_pending_steps -= 1
		_cycle_banner()


func _advance_banner_spring(delta: float) -> void:
	# 欠阻尼弹簧的解析解：低帧率和长帧下也保持稳定，不依赖逐帧线性插值。
	var decay := exp(-BANNER_SPRING_DECAY * delta)
	var phase := BANNER_SPRING_FREQUENCY * delta
	var cosine := cos(phase)
	var sine := sin(phase)
	var old_position := _banner_spring
	var old_velocity := _banner_velocity
	var frequency_squared := BANNER_SPRING_DECAY * BANNER_SPRING_DECAY + BANNER_SPRING_FREQUENCY * BANNER_SPRING_FREQUENCY
	_banner_spring = (old_position * cosine + (old_velocity + old_position * BANNER_SPRING_DECAY) / BANNER_SPRING_FREQUENCY * sine) * decay
	_banner_velocity = (old_velocity * cosine - (old_velocity * BANNER_SPRING_DECAY + old_position * frequency_squared) / BANNER_SPRING_FREQUENCY * sine) * decay


func _portrait_has_point(portrait: TextureRect, point: Vector2) -> bool:
	if not portrait.visible or portrait.texture == null or portrait.self_modulate.a < 0.12:
		return false
	var local := portrait.get_transform().affine_inverse() * point
	if not Rect2(Vector2.ZERO, portrait.size).has_point(local):
		return false
	var mask: BitMap = _banner_masks.get(portrait.texture)
	if mask == null:
		return false
	var pixel := Vector2i(local / portrait.size * Vector2(mask.get_size()))
	return mask.get_bitv(pixel)


func _player_name() -> String:
	if App.settings != null and str(App.settings.player_name).strip_edges() != "":
		return str(App.settings.player_name)
	return "User"
