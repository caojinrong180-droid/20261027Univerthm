extends Node
## 一次性工具：把「代码搭出来的界面」打包成 .tscn（可以在编辑器里直接改）。

const SCREENS := [
	"res://scenes/profile.tscn",
	"res://scenes/collection.tscn",
	"res://scenes/settings.tscn",
]

const SyntheticChart = preload("res://tests/fixtures/synthetic_chart.gd")


func _ready() -> void:
	await get_tree().process_frame
	# 让界面有数据可用
	var chart: Dictionary = SyntheticChart.build()
	App.library = [{
		"key": "synthetic", "title": "Synthetic Test", "artist": "unit test",
		"charter": "tests", "illustrator": "Synthetic Illustrator",
		"difficulty": "NORMAL", "level": 5, "note_count": chart["notes"].size(),
		"has_cover": false, "source": "res://tests/fixtures/synthetic_chart.gd",
		"audio": "", "chart": chart,
	}]
	App.stats = {
		"plays": 12, "best_score": 998765, "best_title": "Synthetic Test", "best_acc": 0.9843,
		"score_total": 998765.0 * 12.0, "acc_total": 0.9843 * 12.0,
	}
	App.settings.player_name = "Player"
	App.last_result = {
		"title": "Synthetic Test", "artist": "unit test", "charter": "tests",
		"illustrator": "Synthetic Illustrator", "difficulty": "NORMAL", "level": 5,
		"score": 998765, "accuracy": 0.9843, "grade": "S", "max_combo": 128,
		"counts": {"perfect_plus": 120, "perfect": 6, "good": 2, "bad": 0, "miss": 0},
		"total": 128, "note_count": 128, "fc": true, "ap": false, "ap_plus": false,
		"early_late": {"perfect_early": 3, "perfect_late": 1, "good_early": 1, "good_late": 1},
		"autoplay": false, "length": 42.0, "entry": {}, "cover": null,
	}

	for path in SCREENS:
		await _export(path)
	print("done")
	get_tree().quit(0)


func _clean_names(node: Node) -> void:
	for c in node.get_children():
		var n := String(c.name)
		if n.begins_with('@'):
			var clean := n.replace('@', '')
			if not clean.is_empty():
				c.name = clean
		_clean_names(c)


func _set_owner(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_set_owner(c, root)


func _export(path: String) -> void:
	var packed_src: PackedScene = load(path)
	if packed_src == null:
		print("  !! 打不开 ", path)
		return
	var inst: Node = packed_src.instantiate()
	get_tree().root.add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	if inst.has_method("_export_prepare"):
		inst.call("_export_prepare")
		await get_tree().process_frame
	await get_tree().process_frame
	_clean_names(inst)
	_set_owner(inst, inst)
	var packed := PackedScene.new()
	var err := packed.pack(inst)
	if err != OK:
		print("  !! 打包失败 ", path, " ", err)
		inst.queue_free()
		return
	err = ResourceSaver.save(packed, path)
	print("  %s -> %s (%d)" % [path, error_string(err), inst.get_child_count()])
	inst.queue_free()
	await get_tree().process_frame
