extends Node
## 真实时间 / 真实音频时钟的自检（需要窗口和声卡，不能 --headless）：

const SyntheticChart = preload("res://tests/fixtures/synthetic_chart.gd")

var passes := 0
var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  ok: " + msg)
	else:
		failures += 1
		print("  FAIL: " + msg)


func _make_wav(seconds := 6.0, freq := 440.0) -> AudioStreamWAV:
	var rate := 44100
	var count := int(seconds * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var v := int(sin(TAU * freq * float(i) / float(rate)) * 6000.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _ready() -> void:
	App.session = {
		"entry": {"key": "test:realtime", "title": "Realtime"},
		"chart": SyntheticChart.build(),
		"stream": _make_wav(),
		"cover": null,
		"warnings": [],
		"errors": [],
	}
	App.autoplay_once = false
	await get_tree().process_frame

	var game = load("res://scenes/gameplay.tscn").instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame

	check(game.has_audio, "从字节建出了 AudioStream")
	check(game.state == 0, "先倒计时")
	await get_tree().create_timer(2.4).timeout
	check(game.state == 1, "倒计时结束后开播")
	check(game.player.playing, "音频播放中")

	# 再等 2.2 秒，谱面时间应该推进到 ~2.2
	await get_tree().create_timer(2.2).timeout
	var chart_time: float = game.chart_time
	var audio_pos: float = game.player.get_playback_position()
	print("  chart_time=%.3f  audio_pos=%.3f  counts=%s" % [chart_time, audio_pos, str(game.judge.counts)])
	check(chart_time > 1.5, "音频时钟把谱面时间推过了 1.5 秒")
	check(absf(chart_time - audio_pos) < 0.35, "谱面时间和音频位置对得上（误差 < 0.35 秒）")
	check(int(game.judge.counts["miss"]) > 0, "没按键的音符按时间判了 MISS")
	check(game.stage != null, "舞台在跑")

	# 打击音：真的能放出来，音量跟着设置走，关掉就不再响
	App.settings.hit_sound = true
	App.settings.hit_volume = 0.5
	game._play_hit()
	check(game.hit_player.playing, "打击音播放")
	check(absf(game.hit_player.volume_db - linear_to_db(0.5)) < 0.05, "打击音音量跟着设置")
	game.hit_player.stop()
	App.settings.hit_sound = false
	game._play_hit()
	check(not game.hit_player.playing, "关掉打击音后不响")
	App.settings.hit_sound = true
	App.settings.hit_volume = 0.6
	App.settings.save()

	# 打击特效：直接触发一次判定信号，确认产出了特效（判定→特效的接线在 smoke 里测）
	App.settings.hit_fx = 2
	game.stage.chart_time = game.chart_time
	game.stage._on_note_judged({"lane": 0}, "perfect", 0.0)
	check(not game.stage._fx.is_empty(), "命中产出判定环")
	check(game.stage._fx.size() == 1, "每次命中只产出一圈判定环")

	print("\n%d passed, %d failed" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)
