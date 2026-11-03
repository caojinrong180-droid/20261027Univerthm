extends RefCounted
class_name WarningStinger
## 「不可反悔」警告框的短音效：一声低频轰鸣 + 一下金属尾音 + 起手的白噪冲击。
##
## 没有音频素材，全部按公式合成成 16bit 单声道 WAV（`AudioStreamWAV`），
## 所以不用往仓库里塞 ogg，也不吃导入。约 1.4 秒，够「宏大」又不拖时间。

const DURATION := 1.4
const MIX_RATE := 44100


## 直接给 AudioStreamPlayer 用
static func make_stream() -> AudioStreamWAV:
	var count := int(DURATION * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 20261030
	var low_phase := 0.0
	var mid_phase := 0.0
	var shimmer_phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		# 低频轰鸣：62Hz 一路掉到 38Hz，指数衰减，撑住「重」
		var low_freq := lerpf(62.0, 38.0, minf(1.0, t / 0.9))
		low_phase += TAU * low_freq / float(MIX_RATE)
		var low := sin(low_phase) * exp(-t * 2.4)
		# 中频两个分音（146 / 219）撑出厚度
		mid_phase += TAU * 146.0 / float(MIX_RATE)
		var mid := (sin(mid_phase) * 0.62 + sin(mid_phase * 1.5) * 0.38) * exp(-t * 3.4)
		# 高处一串金属泛音，散得快
		shimmer_phase += TAU * 932.0 / float(MIX_RATE)
		var shimmer := (sin(shimmer_phase) + sin(shimmer_phase * 1.41) * 0.5) * 0.17 * exp(-t * 6.5)
		# 起手那一下白噪冲击（非常短）
		var transient := noise.randf_range(-1.0, 1.0) * exp(-t * 52.0) * 0.55
		var sample := low * 0.85 + mid * 0.5 + shimmer + transient
		# 软限幅，别削出方波
		sample = sample / (1.0 + absf(sample)) * 1.9
		var attack := minf(1.0, t / 0.005)     # 5ms 起音，避免爆音
		var value := int(clampf(sample * attack * 0.78, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
