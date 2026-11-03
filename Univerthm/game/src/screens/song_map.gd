extends Control
## 序章专用的「地图」选曲：整屏铺开的路线图——方框 = 曲绘，旁边磕出来的小四边形 = 这首掉落的收藏品。
## 内容是比屏幕更宽的一整张图，按住左键可以拖（有边界，拖不出去），滚轮也能左右挪。
## 点方框 = 选中（右侧详情滑出来），双击或 Enter = 进曲目。

signal focused(index: int)
signal activated(index: int)
## 点在空白处（没点中方框、也没拖动）
signal blank_clicked
## 点了已经收到的剧情收藏品（那个平行四边形）：直接把剧情读出来
signal story_clicked(index: int)

const BOLD_FONT := preload("res://src/ui/fonts/bold_font.tres")
const PATH_COLOR := Color(0.88, 0.84, 1, 0.5)
const PATH_WIDTH := 1.8
const CAPTION_H := 30.0
## 每个方框往上抬多少（像素）
const RISE := 168.0
## 相邻节点的水平间距 = 屏幕宽 * 这个数（比原来拉得更开）
const SLOT_RATIO := 0.62
const NODE_MAX := 320.0
const MARGIN := 130.0
const DRAG_SLOP := 10.0
## 方框的点击判定往外扩这么多像素：差一点点也算点中
const NODE_HIT_PAD := 10.0
## 剧情收藏品离曲绘方框多远（像素，会再乘缩放）：往下挂 / 往上挂各一份
const STORY_DROP_BELOW := 132.0
const STORY_DROP_ABOVE := 96.0
## 收藏品在方框中心右边多少（占方框宽度的比例）：斜着挂出去，别贴着方框
const STORY_SIDE_SHIFT := 0.26
## 魔王曲（等级最高那首）的曲绘保持原尺寸，其它曲子的曲绘小一点
const BOSS_SCALE := 1.16
const SIDE_SCALE := 0.78
## 滚轮缩放范围（实际缩放是缓动追目标的，所以数值不会一格一格跳）
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 1.12
## 缩放追目标的速度（越大越快，越小越绵）
const ZOOM_SPRING := 11.0


## 魔王曲 = 等级最高的那首（并列取后面那首）
func _boss_index(entries: Array) -> int:
	var best := -1
	var level := -1.0
	for i in entries.size():
		var value := float(entries[i].get("level", 0))
		if value >= level:
			level = value
			best = i
	return best


## 地图上的一个方框：曲绘 + 下面一行曲名，选中时框变亮变粗
class MapNode extends Button:
	var index := 0
	var cover: Texture2D
	var caption := ""
	var picked := false
	var locked := false
	## 还没揭晓（魔王曲没成绩之前）：曲绘纯黑、名字 ???
	var masked := false

	func _ready() -> void:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		# 方框不自己接鼠标：整张图统一由 MapPanel 判定「点中哪个」和「拖动」
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 鼠标样式保持系统默认，不去改它
		mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, Vector2(size.x, maxf(8.0, size.y - CAPTION_H)))
		if masked:
			# 还没揭晓的魔王曲：曲绘纯黑，一点图都不透
			draw_rect(box, Color.BLACK)
		elif cover != null:
			draw_texture_rect(cover, box, false)
		else:
			draw_rect(box, Color(0.07, 0.05, 0.11, 0.92))
		if locked and not masked:
			draw_rect(box, Color(0.015, 0.01, 0.03, 0.74))
		var edge := Color(0.98, 0.96, 1, 0.98) if picked else Color(0.85, 0.75, 1, 0.45)
		draw_rect(box, edge, false, 2.4 if picked else 1.2)
		if caption != "":
			var color := Color(0.98, 0.96, 1, 1) if picked else Color(0.76, 0.73, 0.82, 1)
			if locked or masked:
				color = Color(0.42, 0.4, 0.48, 1)
			draw_string(BOLD_FONT, Vector2(0.0, size.y - 8.0), caption,
				HORIZONTAL_ALIGNMENT_LEFT, size.x, 15, color)

	func _has_point(point: Vector2) -> bool:
		return Rect2(Vector2.ZERO, size).has_point(point)


var _nodes: Array = []
var _cover_cache := {}
## 每个节点的相对大小：魔王曲（等级最高那首）保持原尺寸，其它小一点
var _scales: Array = []
var _pan := Vector2.ZERO
var _dragging := false
var _dragged := false
var _drag_from := Vector2.ZERO
var _drag_pan := Vector2.ZERO
## 按下时落在这个方框上（松开还在同一个里才算点中它）
var _press_index := -1
## 按下时落在这个收藏品上（比方框优先：收藏品是能点开剧情的小块）
var _press_story := -1
## 滚轮缩放（1 就是原尺寸）；_zoom 是当前值，_zoom_target 是缓动目标
var _zoom := 1.0
var _zoom_target := 1.0
var _zoom_pivot := Vector2.ZERO
var _zoom_done := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_relayout)
	mouse_exited.connect(_reset_cursor)
	set_process(false)


## entries = App.library；locked[i] = 这首还没解锁；stories[i] = 这首的收藏品收到过没有；
## hidden[i] = 还没揭晓的神秘曲（魔王曲没成绩之前：曲绘纯黑、名字 ???）
func build(entries: Array, locked: Array, stories: Array, hidden := []) -> void:
	for node in _nodes:
		if is_instance_valid(node["node"]):
			node["node"].queue_free()
	_nodes.clear()
	_scales.clear()
	var boss := _boss_index(entries)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var node := MapNode.new()
		node.index = i
		node.name = "Node_%02d" % i
		var is_locked: bool = i < locked.size() and locked[i]
		var is_hidden: bool = i < hidden.size() and hidden[i]
		# 未揭晓的神秘曲：曲绘直接用纯黑占位（assets/none.jpg），不再另外糊一块黑
		node.masked = false
		node.cover = _cover_for(entry)
		node.caption = "???" if (is_locked or is_hidden) else str(entry.get("title", "未命名谱面"))
		node.locked = is_locked
		add_child(node)
		_nodes.append({"node": node, "story": i < stories.size() and stories[i]})
		_scales.append(BOSS_SCALE if i == boss else SIDE_SCALE)
	# 进来先看整张图的中间：内容比屏幕大的时候不至于一上来就卡在左上角
	_pan = _clamp_pan(-(_content_size() - size) * 0.5)
	_relayout()
	queue_redraw()


func _cover_for(entry: Dictionary) -> Texture2D:
	var key := str(entry.get("key", ""))
	# 神秘曲没揭晓：用纯黑占位曲绘（不缓存，揭晓后自然换回真图）
	if App.is_hidden_chart(key):
		return App.none_cover()
	var cached = _cover_cache.get(key)
	if cached == null:
		cached = ChartSource.load_cover(entry)
		_cover_cache[key] = cached
	return cached


func focus_node(index: int) -> void:
	for i in _nodes.size():
		var node: MapNode = _nodes[i]["node"]
		node.picked = i == index
		node.queue_redraw()


func node_position(index: int) -> Rect2:
	if index < 0 or index >= _nodes.size():
		return Rect2()
	var node: MapNode = _nodes[index]["node"]
	return Rect2(node.position, node.size)


# --------------------------------------------------------------------------- #
# 给选曲页那层「黑色半透明遮罩」用的公开接口
# （遮罩盖在地图上以后，地图收不到鼠标了，点/拖/滚轮由它转过来）
# --------------------------------------------------------------------------- #

## 屏幕坐标落在哪个方框上（含 10 像素容差）
func node_at(pos: Vector2) -> int:
	return _node_at(pos)


## 屏幕坐标落在哪块「已收到」的收藏品上
func story_at(pos: Vector2) -> int:
	return _collectible_at(pos)


## 按屏幕位移平移地图（拖动时用）
func pan_by(delta: Vector2) -> void:
	_pan = _clamp_pan(_pan + delta)
	_relayout()


## 以某点为中心缩放（滚轮时用），factor > 1 放大
func zoom_at_point(pos: Vector2, factor: float) -> void:
	_zoom_at(pos, factor)


func _slot() -> float:
	return maxf(size.x * SLOT_RATIO, 380.0)


func _base_size() -> Vector2:
	return Vector2(minf(_slot() * 0.52, NODE_MAX), 0.0)


## 拖动时可以多拉出去多少（视口尺寸的倍数，四周各一份）：
## 内容之外留一圈空，上下左右都能再挪一段，不会一拉就顶死
const PAN_SLACK := 0.62


## 内容比屏幕宽/高就允许拖，拖不出去。整体再乘上缩放（滚轮缩放）
func _content_size() -> Vector2:
	var count := _nodes.size()
	if count == 0:
		return Vector2.ZERO
	var box := _base_size()
	var width := MARGIN * 2.0 + _slot() * float(count - 1) + box.x * BOSS_SCALE
	var height := MARGIN * 2.0 + box.x * BOSS_SCALE + RISE * float(count - 1)
	return Vector2(width, height) * _zoom


## 实际能拖到的那片范围：内容四周各加一圈空白（= 视口 × PAN_SLACK）
func _world_size() -> Vector2:
	return _content_size() + size * (PAN_SLACK * 2.0)


func _clamp_pan(pan: Vector2) -> Vector2:
	var world := _world_size()
	var slack := size * PAN_SLACK
	return Vector2(
		_clamp_axis(pan.x, size.x, world.x, slack.x),
		_clamp_axis(pan.y, size.y, world.y, slack.y))


## 单根轴：世界比视口小就不让拖（回到原点），否则可以在「右下贴边 … 四周多留一圈」之间挪
func _clamp_axis(value: float, view: float, world: float, slack: float) -> float:
	if world <= view:
		return 0.0
	return clampf(value, view - world, slack)


func _relayout() -> void:
	var count := _nodes.size()
	if count == 0:
		return
	var box := _base_size()
	var content := _content_size()
	_pan = _clamp_pan(_pan)
	# 内容比屏幕矮就整体垂直居中；比屏幕高就靠拖动看
	var origin := Vector2(0.0, maxf(0.0, (size.y - content.y) * 0.5))
	for i in count:
		var node: MapNode = _nodes[i]["node"]
		var scale: float = float(_scales[i]) if i < _scales.size() else 1.0
		var w := minf(box.x * scale, _slot() * 0.9) * _zoom
		var h := w * 1.02
		var x := (MARGIN + _slot() * float(i)) * _zoom
		var y := (MARGIN + RISE * float(count - 1 - i)) * _zoom
		node.position = Vector2(x, y) + origin + _pan
		node.size = Vector2(w, h + CAPTION_H)
	queue_redraw()


func _draw() -> void:
	if _nodes.is_empty():
		return
	# 路线：穿过每个方框的中心，中间插一个拐点，画出手绘折线的感觉
	var points := PackedVector2Array()
	for i in _nodes.size():
		var node: MapNode = _nodes[i]["node"]
		var center := node.position + Vector2(node.size.x * 0.5, (node.size.y - CAPTION_H) * 0.5)
		if i > 0:
			var prev: MapNode = _nodes[i - 1]["node"]
			var from := prev.position + Vector2(prev.size.x, (prev.size.y - CAPTION_H) * 0.5)
			var target_x := center.x - node.size.x * 0.5
			points.append(Vector2(lerpf(from.x, target_x, 0.42), from.y))
			points.append(Vector2(lerpf(from.x, target_x, 0.52), center.y))
		points.append(Vector2(center.x - node.size.x * 0.5, center.y))
		points.append(center)
		points.append(Vector2(center.x + node.size.x * 0.5, center.y))
	if points.size() >= 2:
		draw_polyline(points, PATH_COLOR, PATH_WIDTH, true)
	for i in _nodes.size():
		_draw_collectible(i)


## 收藏品的几何：中心点 + 四个角 + 尺寸。画和「点中没有」共用这一份
func _collectible_geom(index: int) -> Dictionary:
	var node: MapNode = _nodes[index]["node"]
	var box := Rect2(node.position, Vector2(node.size.x, node.size.y - CAPTION_H))
	var below := index % 2 == 0
	var anchor := Vector2(box.get_center().x + box.size.x * STORY_SIDE_SHIFT, box.end.y if below else box.position.y)
	var piece := Vector2(70.0, 30.0) * _zoom
	var skew := 12.0 * _zoom
	var drop := (STORY_DROP_BELOW if below else STORY_DROP_ABOVE) * _zoom
	var center := anchor + Vector2(0.0, drop) if below else anchor - Vector2(0.0, drop)
	var quad := PackedVector2Array([
		center + Vector2(-piece.x * 0.5 + skew, piece.y * 0.5),
		center + Vector2(piece.x * 0.5 + skew, piece.y * 0.5),
		center + Vector2(piece.x * 0.5 - skew, -piece.y * 0.5),
		center + Vector2(-piece.x * 0.5 - skew, -piece.y * 0.5),
	])
	return {"anchor": anchor, "center": center, "quad": quad, "piece": piece}


## 收藏品：方框旁边一条细线连着一个平行四边形，收到过就点亮，里面画一个简约的「文本」图标
func _draw_collectible(index: int) -> void:
	var geom := _collectible_geom(index)
	var quad: PackedVector2Array = geom["quad"]
	var got: bool = bool(_nodes[index].get("story", false))
	draw_line(geom["anchor"], geom["center"], TETHER_COLOR, 1.4, true)
	var loop := quad.duplicate()
	loop.append(quad[0])
	if got:
		draw_colored_polygon(quad, Color(0.62, 0.38, 0.95, 0.55))
		draw_polyline(loop, Color(0.88, 0.8, 1, 0.9), 1.4, true)
	else:
		draw_polyline(loop, Color(0.7, 0.66, 0.8, 0.42), 1.1, true)
	_draw_text_icon(geom, got)


## 简约文本图标：三条横线，最后一行短一截，像一页正文（没有用任何图片资源）
func _draw_text_icon(geom: Dictionary, got: bool) -> void:
	var center: Vector2 = geom["center"]
	var piece: Vector2 = geom["piece"]
	var ink := Color(0.96, 0.93, 1, 0.92) if got else Color(0.72, 0.68, 0.82, 0.38)
	var gap := piece.y * 0.25
	var half := piece.x * 0.19
	var thick := maxf(1.0, 1.5 * _zoom)
	for i in 3:
		var y := center.y + (i - 1) * gap
		var right := center.x + (half if i < 2 else half * 0.34)
		draw_line(Vector2(center.x - half, y), Vector2(right, y), ink, thick, true)


## 点在哪一块收藏品上（不管收没收到）
func _collectible_index_at(pos: Vector2) -> int:
	for i in range(_nodes.size() - 1, -1, -1):
		var geom := _collectible_geom(i)
		var quad: PackedVector2Array = geom["quad"]
		var center: Vector2 = geom["center"]
		var grown := PackedVector2Array()
		for corner in quad:
			grown.append(center + (corner - center) * 1.3)   # 稍微放大一点好点
		if _point_in_quad(pos, grown):
			return i
	return -1


## 点在哪一块「已经收到」的收藏品上；没收到的那块只是淡淡一个框，点开不了剧情
func _collectible_at(pos: Vector2) -> int:
	var index := _collectible_index_at(pos)
	if index < 0 or not bool(_nodes[index].get("story", false)):
		return -1
	return index


func _point_in_quad(point: Vector2, quad: PackedVector2Array) -> bool:
	if quad.size() < 4:
		return false
	return _point_in_tri(point, quad[0], quad[1], quad[2]) \
		or _point_in_tri(point, quad[0], quad[2], quad[3])


func _point_in_tri(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (point - b).cross(a - b)
	var d2 := (point - c).cross(b - c)
	var d3 := (point - a).cross(c - a)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)


## 悬停在能点的收藏品上换成手型，别的地方保持箭头
func _sync_cursor(pos: Vector2) -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _collectible_at(pos) >= 0 else Control.CURSOR_ARROW


func _reset_cursor() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW


const TETHER_COLOR := Color(0.85, 0.8, 1, 0.42)


## 滚轮：只改「目标缩放」，实际缩放由 _process 每帧缓动追上去（所以是平滑放大缩小）
func _zoom_at(pivot: Vector2, factor: float) -> void:
	var next := clampf(_zoom_target * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(_zoom_target, next):
		return
	_zoom_target = next
	_zoom_pivot = pivot
	set_process(true)


## 每帧把当前缩放追向目标缩放，并让鼠标底下那个点在缩放过程中保持不动
func _process(delta: float) -> void:
	if is_equal_approx(_zoom, _zoom_target) and _zoom_done:
		set_process(false)
		return
	var anchor := (_zoom_pivot - _pan) / maxf(_zoom, 0.001)
	_zoom = lerpf(_zoom, _zoom_target, minf(1.0, delta * ZOOM_SPRING))
	if absf(_zoom - _zoom_target) < 0.0015:
		_zoom = _zoom_target
		_zoom_done = true
	else:
		_zoom_done = false
	_pan = _clamp_pan(_zoom_pivot - anchor * _zoom)
	_relayout()


## 屏幕坐标（本控件内）落在哪个方框上；没点到返回 -1。
## 命中判定往外扩 NODE_HIT_PAD：贴着边、差几个像素也要算点中，不然手一抖就「没反应」
func _node_at(pos: Vector2) -> int:
	for i in range(_nodes.size() - 1, -1, -1):
		var node: MapNode = _nodes[i]["node"]
		if Rect2(node.position, node.size).grow(NODE_HIT_PAD).has_point(pos):
			return i
	return -1


## 任意位置都能拖：方框自己不接鼠标，按下/拖动/松开全在这里判定
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT:
			if click.pressed:
				_dragging = true
				_dragged = false
				_drag_from = click.position
				_drag_pan = _pan
				# 按下时就把「点的是什么」定下来：
				# 收到的收藏品 > 收藏品那块（没收到也算点这首）> 方框；都没有就是空白
				var story_index := _collectible_index_at(click.position)
				if story_index >= 0 and bool(_nodes[story_index].get("story", false)):
					_press_story = story_index
					_press_index = -1
				else:
					_press_story = -1
					_press_index = story_index if story_index >= 0 else _node_at(click.position)
			else:
				_dragging = false
				# 只有「没拖动」才算点击；松手时不再重新判定命中的是谁
				# （否则按下去时明明点在框里、松手漂出去两三像素就白点了）
				if not _dragged:
					if _press_story >= 0:
						story_clicked.emit(_press_story)
					elif _press_index >= 0:
						if click.double_click:
							activated.emit(_press_index)
						else:
							focused.emit(_press_index)
					else:
						# 点在空白处：让右侧详情收回去
						blank_clicked.emit()
				_press_index = -1
				_press_story = -1
			accept_event()
		elif click.pressed and click.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# 滚轮缩放：以鼠标位置为中心，缩完内容不会从指针底下跑掉
			var factor := ZOOM_STEP
			if click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				factor = 1.0 / ZOOM_STEP
			_zoom_at(click.position, factor)
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_sync_cursor(motion.position)
		if _dragging:
			var delta := motion.position - _drag_from
			if delta.length() > DRAG_SLOP:
				_dragged = true
			_pan = _clamp_pan(_drag_pan + delta)
			_relayout()
			accept_event()



