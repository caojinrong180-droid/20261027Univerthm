extends RefCounted
## 测试用的合成谱面：只在 tests/ 里用，不写盘、不进 charts。
##
## 不是给玩家玩的谱面，只是为了让「游玩 / 判定 / 渲染」能在没有真实谱面的情况下被验证。
## 覆盖 tap / hold，带几条轨道事件（位移 / 旋转 / 透明度 / 流速）。

const BAR := 1.6
const START := 1.2
const BARS := 8


static func raw() -> Dictionary:
	var notes: Array = []
	for bar in BARS:
		var b0 := START + bar * BAR
		var rot := bar % 4
		notes.append({"time": b0, "lane": rot % 4, "type": "tap"})
		notes.append({"time": b0 + 0.4, "lane": (rot + 1) % 4, "type": "tap"})
		notes.append({"time": b0 + 0.8, "lane": (rot + 2) % 4, "type": "hold", "duration": 0.5})
		notes.append({"time": b0 + 1.2, "lane": (rot + 3) % 4, "type": "tap"})

	return {
		"format": "rchart",
		"version": 3,
		"meta": {
			"title": "Synthetic Test", "artist": "unit test", "charter": "tests",
			"illustrator": "Synthetic Illustrator",
			"difficulty": "NORMAL", "level": 5, "cover": "",
		},
		"audio": {"file": "hit.wav", "offset": 0.0, "volume_db": 0.0},
		"timing": {"bpm": 150.0, "beat_offset": 0.0},
		"stage": {"lane_count": 4, "highway_length": 2.0},
		"lanes": [
			{
				"name": "L1", "judge_zone": "left", "color": "#ffffff",
				"x": -150, "y": 0, "alpha": 100, "speed": 10, "length": 10, "rotation": 0,
				"events": {
					"x": [
						{"start": 4.0, "end": 6.0, "ease": "inOutQuad", "from": -150, "to": -110},
						{"start": 6.0, "end": 8.0, "ease": "inOutQuad", "from": -110, "to": -150},
					],
				},
			},
			{
				"name": "L2", "judge_zone": "left", "color": "#ffffff",
				"x": -50, "y": 0, "alpha": 100, "speed": 10, "length": 10, "rotation": 0,
				"events": {
					"rotation": [
						{"start": 8.0, "end": 10.0, "ease": "inOutSine", "from": 0, "to": 8},
						{"start": 10.0, "end": 12.0, "ease": "inOutSine", "from": 8, "to": 0},
					],
				},
			},
			{
				"name": "L3", "judge_zone": "right", "color": "#ffffff",
				"x": 50, "y": 0, "alpha": 100, "speed": 10, "length": 10, "rotation": 0,
				"events": {
					"alpha": [
						{"start": 11.0, "end": 12.0, "ease": "outCubic", "from": 100, "to": 50},
						{"start": 13.0, "end": 14.0, "ease": "inOutCubic", "from": 50, "to": 100},
					],
					# zone 事件：6.2~9.2 秒这条轨道临时改成左判定区
					# （自动演示必须按「当前生效的判定区」按键，用静态值会漏打）
					"zone": [
						{"start": 6.0, "end": 6.2, "ease": "linear", "from": 2, "to": 1},
						{"start": 9.0, "end": 9.2, "ease": "linear", "from": 1, "to": 2},
					],
				},
			},
			{
				"name": "L4", "judge_zone": "right", "color": "#ffffff",
				"x": 150, "y": 0, "alpha": 100, "speed": 10, "length": 10, "rotation": 0,
				"events": {
					"speed": [
						{"start": 12.0, "end": 13.0, "ease": "inOutQuad", "from": 10, "to": 14},
						{"start": 14.0, "end": 15.5, "ease": "inOutQuad", "from": 14, "to": 10},
					],
				},
			},
		],
		"notes": notes,
	}


static func build() -> Dictionary:
	return RhythmChart.parse(raw())["chart"]


## 用内置打击音当测试音频，把「从字节造 AudioStream」这条路径也走一遍
static func stream() -> AudioStream:
	var bytes := FileAccess.get_file_as_bytes("res://audio/hit.wav")
	if bytes.is_empty():
		return null
	return AudioStreamWAV.load_from_buffer(bytes)


static func duration() -> float:
	return START + BARS * BAR
