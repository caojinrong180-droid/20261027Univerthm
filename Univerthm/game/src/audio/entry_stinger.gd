extends RefCounted
class_name EntryStinger
## 进入谱面过场的音效：一团往上升的气流 + 一下亮铃 + 底下压着的低频。
##
## 和警告框那声「闷雷」不同，这个是**上行**的（`160Hz → 720Hz` 扫上去），
## 到约 0.55 秒位置叠一记亮铃，正好对上画面「稍微放大」的那一刻；最后收在黑场里。
## 依旧全部按公式合成 16bit 单声道 WAV，不往仓库塞音频文件。

const DURATION := 1.25
const MIX_RATE := 44100
## 亮铃落在第几秒
const CHIME_AT := 0.55


static func make_stream() -> AudioStreamWAV:
	var count := int(DURATION * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 20261103
	var sweep_phase := 0.0
	var low_phase := 0.0
	var chime_phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		# 上行的气流：频率一路扫上去，音量先起后落
		var sweep_freq := lerpf(160.0, 720.0, minf(1.0, t / 0.55))
		sweep_phase += TAU * sweep_freq / float(MIX_RATE)
		var sweep_env := minf(1.0, t / 0.12) * exp(-maxf(0.0, t - 0.2) * 3.2)
		var sweep := sin(sweep_phase) * sweep_env * 0.32
		# 叠加的噪声明亮一点，像风吹过去
		var air := noise.randf_range(-1.0, 1.0) * sweep_env * 0.16
		# 底下垫的 84Hz，把「重」撑住
		low_phase += TAU * 84.0 / float(MIX_RATE)
		var low := sin(low_phase) * exp(-t * 2.2) * 0.3
		# 亮铃：三个泛音，衰减快
		var chime := 0.0
		if t >= CHIME_AT:
			var ct := t - CHIME_AT
			chime_phase += TAU * 880.0 / float(MIX_RATE)
			chime = (sin(chime_phase)
				+ sin(chime_phase * 1.5) * 0.55
				+ sin(chime_phase * 2.0) * 0.3) * minf(1.0, ct / 0.004) * exp(-ct * 4.2) * 0.42
		var sample := sweep + air + low + chime
		sample = sample / (1.0 + absf(sample)) * 1.9         # 软限幅
		var attack := minf(1.0, t / 0.01)
		var fade_out := minf(1.0, maxf(0.0, (DURATION - t) / 0.12))
		var value := int(clampf(sample * attack * fade_out * 0.72, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
