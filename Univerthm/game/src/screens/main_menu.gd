extends Control
## 主界面。界面节点都在 scenes/main_menu.tscn 里，可以在编辑器里直接拖；
## 这个脚本只负责：连线、换立绘、写名字、Esc 退出。

const BANNERS_DIR := "res://assets/banners"

## 立绘显示规则（对齐样图：头顶靠上、腿被底边裁掉）
const GIRL_HEIGHT := 880.0
const GIRL_TOP := 90.0
const GIRL_CENTER_X := 940.0

@onready var _girl: TextureRect = $Banner
@onready var _name_label: Label = $NameLabel
@onready var _start_button: SpriteButton = $StartButton
@onready var _switch_button: SpriteButton = $SwitchButton

var _banners: Array = []


func _ready() -> void:
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
	_start_button.call_deferred("grab_focus")


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
		_girl.position = Vector2(GIRL_CENTER_X - _girl.size.x * 0.5, GIRL_TOP)


func _cycle_banner() -> void:
	if _banners.size() <= 1:
		return
	if App.settings != null:
		App.settings.banner_index = (_banner_index() + 1) % _banners.size()
		App.settings.save()
	_apply_banner()


func _player_name() -> String:
	if App.settings != null and str(App.settings.player_name).strip_edges() != "":
		return str(App.settings.player_name)
	return "User"
