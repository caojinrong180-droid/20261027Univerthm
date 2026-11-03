extends Node
## 临时截图：结算页同时掉剧情 + 曲绘（用完即删）。

const OUT := "res://tests/_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await get_tree().process_frame
	App.last_result = {
		"title": "dream of utopia", "artist": "unit", "charter": "tests",
		"difficulty": "EXPERT", "level": 9, "score": 998765, "accuracy": 0.9843,
		"grade": "S", "max_combo": 128,
		"counts": {"perfect_plus": 120, "perfect": 6, "good": 2, "bad": 0, "miss": 0},
		"total": 128, "note_count": 128,
		"early_late": {"perfect_early": 3, "perfect_late": 1, "good_early": 1, "good_late": 1},
		"fc": true, "ap": false, "ap_plus": false, "autoplay": false, "length": 95.0,
		"entry": {},
		"story_drop": {"file": "Stra的笔记#1.txt", "title": "Stra的笔记#1", "number": 1},
		"cover_drop": {"key": "test:cover", "title": "dream of utopia"},
	}
	var results = load("res://scenes/results.tscn").instantiate()
	get_tree().root.add_child(results)
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/80_drops_both.png")
	print("saved")
	get_tree().quit(0)
