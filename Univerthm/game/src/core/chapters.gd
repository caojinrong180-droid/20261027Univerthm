extends RefCounted
## 章节表：选章节界面和选曲界面共用这一份（改章节只改这里）。
##
## - `key` 写进 `App.chapter_key`
## - `spine` 书脊上竖着写的字；`name` 右侧那行章节名
## - `unlocked = false` 的锁着不能进
## - `cover` 书脊上的章节封面（不写就是纯色书脊）
## - `index` 右边那行「章节 · ___」

const LIST := [
	{
		"key": "all",
		"index": "全部",
		"spine": "全部曲目",
		"name": "全部曲目",
		"unlocked": true,
		"cover": preload("res://assets/covers/ALL.png"),
	},
	{"key": "single", "index": "单曲", "spine": "单曲", "name": "单曲合集", "unlocked": false},
	{
		"key": "main_0",
		"index": "序",
		"spine": "主线·序",
		"name": "一切的开端",
		"unlocked": true,
		"cover": preload("res://assets/covers/C0.png"),
	},
	{"key": "main_1", "index": "一", "spine": "主线·一", "name": "尚未开放", "unlocked": false},
	{
		"key": "heartbeat",
		"index": "联动",
		"spine": "心跳电波！",
		"name": "心跳电波 ON AIR!精选集",
		"unlocked": false,
		"cover": preload("res://assets/covers/XTDB.png"),
	},
	{
		"key": "drum_cube",
		"index": "联动",
		"spine": "鼓立方",
		"name": "鼓立方精选集",
		"unlocked": false,
		"cover": preload("res://assets/covers/glf.png"),
	},
]


## 按 key 找章节；找不到返回 {}
static func find(key: String) -> Dictionary:
	for chapter in LIST:
		if str(chapter.get("key", "")) == key:
			return chapter
	return {}


## 章节序号（0 开始），找不到返回 -1
static func index_of(key: String) -> int:
	for i in LIST.size():
		if str(LIST[i].get("key", "")) == key:
			return i
	return -1


## 选曲页顶上那行标题：`spine` 和 `name` 不一样的时候带上书脊名
static func display_title(key: String) -> String:
	var chapter := find(key)
	if chapter.is_empty():
		return "全部曲目"
	var spine := str(chapter.get("spine", ""))
	var name := str(chapter.get("name", ""))
	if spine == "" or spine == name:
		return name if name != "" else spine
	return "%s ｜ %s" % [spine, name]
