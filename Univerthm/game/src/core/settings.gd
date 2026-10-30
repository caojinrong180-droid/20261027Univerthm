class_name AppSettings
extends RefCounted
## 玩家设置。存在 user://settings.cfg，Windows 上大约是
## %APPDATA%\Godot\app_userdata\Rhythm Game\settings.cfg

const PATH := "user://settings.cfg"
const KEY_LAYOUTS := ["asdf_jkl", "dfjk"]
const KEY_LAYOUT_LABELS := {
	"asdf_jkl": "ASDF / JKL;（默认）",
	"dfjk": "DF / JK（4 键）",
}

## 音画偏移，毫秒。正数 = 谱面时间整体推后（唱得比画面晚 / 蓝牙耳机时调它）
var audio_offset_ms := 0.0
## 下落速度倍率：1.0 = 判定线到画面顶走 2 秒，2.0 = 1 秒，0.5 = 4 秒
var speed_mult := 1.0
## 判定窗口倍率：1.0 = 55 / 80 / 140 / 220 ms
var judge_window_scale := 1.0
## 音乐 / 打击音音量 0~1
var music_volume := 0.85
var hit_volume := 0.6
var hit_sound := true
## 打击特效：0 = 关，1 = 标准，2 = 强（火焰更多 + 屏震）
var hit_fx := 2
## 自动演示（也会让选曲界面的「自动演示」临时打开）
var autoplay := false
## 键位布局
var key_layout := "asdf_jkl"
## 画面垂直偏移（屏幕像素，正数往下）。默认 -24 = 在严格居中的基础上往上抬一点
var stage_offset_px := -24.0
## 玩家名（主界面左上角、个人资料里显示 / 修改）
var player_name := "User"
## 主界面看板娘立绘序号（assets/banners/ 里的第几张）
var banner_index := 0
## 调试：全部解锁（跳过选曲页的逐首解锁）
var unlock_all := false


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("play", "audio_offset_ms", audio_offset_ms)
	cf.set_value("play", "speed_mult", speed_mult)
	cf.set_value("play", "judge_window_scale", judge_window_scale)
	cf.set_value("audio", "music_volume", music_volume)
	cf.set_value("audio", "hit_volume", hit_volume)
	cf.set_value("audio", "hit_sound", hit_sound)
	cf.set_value("audio", "hit_fx", hit_fx)
	cf.set_value("play", "autoplay", autoplay)
	cf.set_value("play", "key_layout", key_layout)
	cf.set_value("ui", "stage_offset_px", stage_offset_px)
	cf.set_value("ui", "player_name", player_name)
	cf.set_value("ui", "banner_index", banner_index)
	cf.set_value("debug", "unlock_all", unlock_all)
	var err := cf.save(PATH)
	if err != OK:
		push_warning("设置存不下来: %s" % error_string(err))


static func load_settings() -> AppSettings:
	var s := AppSettings.new()
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return s
	s.audio_offset_ms = clampf(float(cf.get_value("play", "audio_offset_ms", s.audio_offset_ms)), -250.0, 250.0)
	s.speed_mult = clampf(float(cf.get_value("play", "speed_mult", s.speed_mult)), 0.25, 4.0)
	s.judge_window_scale = clampf(float(cf.get_value("play", "judge_window_scale", s.judge_window_scale)), 0.4, 2.5)
	s.music_volume = clampf(float(cf.get_value("audio", "music_volume", s.music_volume)), 0.0, 1.0)
	s.hit_volume = clampf(float(cf.get_value("audio", "hit_volume", s.hit_volume)), 0.0, 1.0)
	s.hit_sound = bool(cf.get_value("audio", "hit_sound", s.hit_sound))
	s.hit_fx = clampi(int(cf.get_value("audio", "hit_fx", s.hit_fx)), 0, 2)
	s.autoplay = bool(cf.get_value("play", "autoplay", s.autoplay))
	var layout := str(cf.get_value("play", "key_layout", s.key_layout))
	if KEY_LAYOUTS.has(layout):
		s.key_layout = layout
	s.stage_offset_px = clampf(float(cf.get_value("ui", "stage_offset_px", s.stage_offset_px)), -400.0, 400.0)
	var nm := str(cf.get_value("ui", "player_name", s.player_name)).strip_edges()
	s.player_name = nm if nm != "" else "User"
	s.banner_index = clampi(int(cf.get_value("ui", "banner_index", s.banner_index)), 0, 99)
	s.unlock_all = bool(cf.get_value("debug", "unlock_all", s.unlock_all))
	return s


func reset() -> void:
	audio_offset_ms = 0.0
	speed_mult = 1.0
	judge_window_scale = 1.0
	music_volume = 0.85
	hit_volume = 0.6
	hit_sound = true
	hit_fx = 2
	autoplay = false
	key_layout = "asdf_jkl"
	stage_offset_px = -24.0
	player_name = "User"
	banner_index = 0
	unlock_all = false


## 毫秒 → 秒，判定时用
func offset_seconds() -> float:
	return audio_offset_ms / 1000.0


## 判定线 → 画面顶 需要几秒（speed_mult 越大越短）
func visible_seconds() -> float:
	return clampf(2.0 / maxf(0.25, speed_mult), 0.15, 8.0)
