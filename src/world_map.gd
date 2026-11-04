extends Control

const L = preload("res://src/i18n.gd")

signal country_selected(id: int)
signal zoom_changed(value: float)
var game: RefCounted
var selected = -1
var hovered = -1
var zoom = 1.0
var pan = Vector2.ZERO
var polygons: Array = []
var bounds: Array = []
var centers: Array = []
var dragging = false
var moved = false
var press_position = Vector2.ZERO
var visual_time = 0.0
var pulses: Array = []
var motion_layer: Control
var touches: Dictionary = {}
const LAND = [Color("293f45"), Color("334348"), Color("344346"), Color("2c4348"), Color("354549"), Color("2b4148"), Color("31474a")]

func setup(state: RefCounted) -> void:
	game = state
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for country in game.atlas:
		var rings: Array = []
		var boxes: Array = []
		for ring in country.rings:
			var polygon = PackedVector2Array()
			for point in ring:
				polygon.append(project_point(Vector2(point[0], point[1])))
			rings.append(polygon)
			var box = Rect2(polygon[0], Vector2.ZERO)
			for p in polygon:
				box = box.expand(p)
			boxes.append(box)
		polygons.append(rings)
		bounds.append(boxes)
		centers.append(project_point(Vector2(country.center[0], country.center[1])))
	resized.connect(queue_redraw)
	motion_layer = MotionLayer.new()
	motion_layer.map = self
	motion_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(motion_layer)
	motion_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

class MotionLayer extends Control:
	var map: Control
	func _draw() -> void:
		map.draw_motion(self)

func _process(delta: float) -> void:
	if game == null:
		return
	if not game.paused and game.home >= 0:
		visual_time = clampf(visual_time + delta, game.elapsed, game.elapsed + 0.99)
		for pulse in pulses:
			pulse.age += delta
		pulses = pulses.filter(func(pulse): return pulse.age < 2.6)
	while not game.effects.is_empty():
		var effect = game.effects.pop_front()
		effect.age = 0.0
		pulses.append(effect)
	motion_layer.queue_redraw()

func clear_motion() -> void:
	pulses.clear()
	visual_time = game.elapsed
	motion_layer.queue_redraw()

func screen_point(id: int) -> Vector2:
	return centers[id] * map_scale() + map_origin()

func draw_motion(canvas: Control) -> void:
	var routes = game.operations.duplicate()
	routes.append_array(game.remote_operations)
	if not game.mission.is_empty():
		var agent = game.mission.duplicate()
		agent.kind = "spy"
		routes.append(agent)
	for op in routes:
		if op.kind == "enemy" and op.get("surprise", false): continue
		var a = screen_point(int(op.from))
		var b = screen_point(int(op.target))
		var progress = clampf((visual_time - op.start) / maxf(1, op.arrival - op.start), 0, 1)
		var bend = minf(120, a.distance_to(b) * 0.24)
		var color = game.player_color
		if op.kind == "spy": color = Color("7ac5ef")
		if op.kind == "enemy": color = Color("f58c83")
		if op.has("source_color"): color = Color(op.source_color)
		if op.kind == "nuke": color = Color("ffd198")
		var previous = a
		for step in range(1, 41):
			var t = step / 40.0
			var point = a.lerp(b, t) + Vector2(0, -sin(t * PI) * bend)
			if step % 2 == 0:
				canvas.draw_line(previous, point, Color(color, 0.45), 1.5, true)
			previous = point
		for index in (3 if op.kind in ["attack", "enemy"] else 1):
			var t = clampf(progress - index * 0.055, 0, 1)
			var point = a.lerp(b, t) + Vector2(0, -sin(t * PI) * bend)
			var angle = (b - a + Vector2(0, -cos(t * PI) * bend * PI)).angle()
			canvas.draw_circle(point, 12, Color(color, 0.10))
			var shape = PackedVector2Array()
			var vertices: Array
			if op.kind == "spy":
				vertices = [Vector2(7, 0), Vector2(0, -5), Vector2(-7, 0), Vector2(0, 5)]
			elif op.kind == "nuke":
				vertices = [Vector2(12, 0), Vector2(-5, -4), Vector2(-9, -8), Vector2(-7, 0), Vector2(-9, 8), Vector2(-5, 4)]
			elif index == 1:
				vertices = [Vector2(11, 0), Vector2(1, -3), Vector2(-5, -11), Vector2(-7, -10), Vector2(-4, -2), Vector2(-10, -4), Vector2(-9, 0), Vector2(-10, 4), Vector2(-4, 2), Vector2(-7, 10), Vector2(-5, 11), Vector2(1, 3)]
			elif op.get("overseas", false):
				vertices = [Vector2(10, 0), Vector2(-7, -5), Vector2(-4, 0), Vector2(-7, 5)]
			else:
				vertices = [Vector2(8, 0), Vector2(0, -5), Vector2(-7, -5), Vector2(-7, 5), Vector2(0, 5)]
			for vertex in vertices:
				shape.append(point + vertex.rotated(angle))
			canvas.draw_colored_polygon(shape, color)
	for pulse in pulses:
		var point = screen_point(int(pulse.target))
		var t = pulse.age / 2.6
		var nuclear = pulse.kind == "nuke"
		var color = Color("ffd198") if nuclear else (game.player_color if pulse.kind == "victory" else Color("f58c83"))
		canvas.draw_circle(point, lerpf(10, 140 if nuclear else 65, t), Color(color, (1.0 - t) * 0.2))
		canvas.draw_arc(point, lerpf(8, 150 if nuclear else 70, t), 0, TAU, 60, Color(color, 1.0 - t), 3 if nuclear else 2, true)
		if nuclear:
			canvas.draw_circle(point, lerpf(18, 45, t), Color(1, 0.93, 0.76, pow(1.0 - t, 3)))

func project_point(point: Vector2) -> Vector2:
	return Vector2((point.x + 180.0) / 360.0 * 1000.0, (85.0 - point.y) / 145.0 * 450.0)

func map_scale() -> float:
	return minf(size.x / 1060.0, size.y / 510.0) * zoom

func map_origin() -> Vector2:
	return size * 0.5 - Vector2(500, 225) * map_scale() + pan

func set_zoom(value: float, pivot: Vector2 = Vector2(-1, -1)) -> void:
	if pivot.x < 0:
		pivot = size * 0.5
	var before = (pivot - map_origin()) / map_scale()
	zoom = clampf(value, 1.0, 9.0)
	pan += pivot - (before * map_scale() + map_origin())
	clamp_pan()
	zoom_changed.emit(zoom)
	queue_redraw()

func clamp_pan() -> void:
	var limit = size * (zoom - 1.0) * 0.55
	pan = pan.clamp(-limit, limit)

func reset_view() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	zoom_changed.emit(zoom)
	queue_redraw()

func focus_country(id: int) -> void:
	selected = id
	zoom = 3.0
	pan = (Vector2(500, 225) - centers[id]) * map_scale()
	clamp_pan()
	zoom_changed.emit(zoom)
	queue_redraw()

func pick(point: Vector2) -> int:
	var p = (point - map_origin()) / map_scale()
	for i in polygons.size():
		for j in polygons[i].size():
			if bounds[i][j].has_point(p) and Geometry2D.is_point_in_polygon(p, polygons[i][j]):
				return i
	var nearest = -1
	var distance = 9.0 / map_scale()
	for i in centers.size():
		var d = centers[i].distance_to(p)
		if d < distance:
			nearest = i
			distance = d
	return nearest

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				press_position = event.position
				moved = false
			else: moved = true
		else:
			if touches.size() == 1 and not moved:
				var id = pick(event.position)
				if id >= 0:
					selected = id
					country_selected.emit(id)
			touches.erase(event.index)
		accept_event()
		return
	if event is InputEventScreenDrag and touches.has(event.index):
		var previous: Vector2 = touches[event.index]
		var before = touches.values()
		touches[event.index] = event.position
		if touches.size() >= 2:
			var after = touches.values()
			var old_distance = before[0].distance_to(before[1])
			if old_distance > 1: set_zoom(zoom * after[0].distance_to(after[1]) / old_distance, (after[0] + after[1]) / 2)
			moved = true
		elif event.position.distance_to(press_position) > 8 or moved:
			moved = true
			pan += event.position - previous
			clamp_pan()
		queue_redraw()
		accept_event()
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			set_zoom(zoom * 1.18, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			set_zoom(zoom / 1.18, event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				dragging = true
				moved = false
				press_position = event.position
			else:
				if dragging and not moved and event.button_index == MOUSE_BUTTON_LEFT:
					var id = pick(event.position)
					if id >= 0:
						selected = id
						country_selected.emit(id)
				dragging = false
			queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		if dragging:
			if event.position.distance_to(press_position) > 4:
				moved = true
			if moved:
				pan += event.relative
				clamp_pan()
				queue_redraw()
		else:
			var id = pick(event.position)
			if id != hovered:
				hovered = id
				tooltip_text = L.country(game.atlas[id]) if id >= 0 else ""
				queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0c1821"))
	if game == null:
		return
	var s = map_scale()
	draw_set_transform(map_origin(), 0, Vector2(s, s))
	for longitude in range(-180, 181, 30):
		var x = project_point(Vector2(longitude, 0)).x
		draw_line(Vector2(x, -40), Vector2(x, 500), Color("172731"), 0.6 / s, true)
	for latitude in range(-60, 91, 30):
		var y = project_point(Vector2(0, latitude)).y
		draw_line(Vector2(0, y), Vector2(1000, y), Color("172731"), 0.6 / s, true)
	for i in polygons.size():
		var color = LAND[i % LAND.size()]
		if game.country_colors.has(str(i)): color = Color(game.country_colors[str(i)]).darkened(0.38)
		if game.countries[i].owned:
			color = game.player_color.darkened(0.38)
		if i == hovered:
			color = color.lightened(0.17)
		if i == selected:
			color = game.player_color.darkened(0.1) if game.countries[i].owned else Color("837358")
		for polygon in polygons[i]:
			if polygon.size() >= 3:
				draw_colored_polygon(polygon, color)
				draw_polyline(polygon, Color("12252d"), 0.8 / s, true)
	if selected >= 0:
		for polygon in polygons[selected]:
			draw_polyline(polygon, Color("f0cf96"), 1.8 / s, true)
		var center: Vector2 = centers[selected]
		draw_circle(center, 7 / s, Color(0.95, 0.82, 0.59, 0.15))
		draw_circle(center, 3 / s, Color("f0cf96"))
	if game.home >= 0 and game.countries[game.home].owned:
		var center: Vector2 = centers[game.home]
		draw_circle(center, 5 / s, game.player_color, false, 1.6 / s, true)
	draw_set_transform(Vector2.ZERO)
	var font = ThemeDB.fallback_font
	for id in game.wars:
		if game.countries[int(id)].owned: continue
		var point = screen_point(int(id))
		draw_circle(point, 9, Color("501e2b"))
		draw_line(point + Vector2(-4, -4), point + Vector2(4, 4), Color("ff9a9a"), 2, true)
		draw_line(point + Vector2(-4, 4), point + Vector2(4, -4), Color("ff9a9a"), 2, true)
		draw_line(point + Vector2(-5, 1), point + Vector2(-1, 5), Color("ff9a9a"), 1.5, true)
		draw_line(point + Vector2(1, 5), point + Vector2(5, 1), Color("ff9a9a"), 1.5, true)
	for ocean in [[L.text("Т И Х И Й  О К Е А Н"), Vector2(-145, 0)], [L.text("А Т Л А Н Т И К А"), Vector2(-35, 8)], [L.text("И Н Д И Й С К И Й"), Vector2(76, -27)]]:
		var p = project_point(ocean[1]) * s + map_origin()
		draw_string(font, p - Vector2(65, 0), ocean[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("44606a"))
	for id in game.reports:
		var country = int(id)
		var name = str(L.country(game.atlas[country]))
		var font_size = int(clampf(11 + zoom, 12, 17))
		var point = screen_point(country) + Vector2(0, -10)
		point.x -= font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
		draw_string_outline(font, point, name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color("0b1720"))
		draw_string(font, point, name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e9e4ce"))
