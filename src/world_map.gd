extends Control

const L = preload("res://src/i18n.gd")
const Rules = preload("res://src/mod_runtime.gd")
const MapRelief = preload("res://src/map_relief.gd")
const Armies = preload("res://src/map_armies.gd")
const MAP_CENTER = Vector2(500, 225)
const RETREAT_SECONDS = 1.15
const CAPTURE_SECONDS = 0.85

signal country_selected(id: int)
signal zoom_changed(value: float)
var game: RefCounted
var selected = -1
var hovered = -1
var zoom = 1.0
var pan = Vector2.ZERO
var tilted = false
var detailed_map = false
var relief: SubViewport
var polygons: Array = []
var fill_polygons: Array = []
var bounds: Array = []
var centers: Array = []
var dragging = false
var moved = false
var press_position = Vector2.ZERO
var visual_time = 0.0
var pulses: Array = []
var fronts: Dictionary = {}
var owners: Array[String] = []
var owner_colors: Array[Color] = []
var details_layer: Control
var motion_layer: Control
var touches: Dictionary = {}
var small_countries: Array[int] = []
var political_groups: Array[int] = []
const Media = preload("res://src/mod_media.gd")
var UNKNOWN = Media.color("unknown", Color("687786"))
const LAND = [Color("439b81"), Color("598fc2"), Color("b59b59"), Color("947ab7"), Color("c17e69"), Color("479eac"), Color("87a85b"), Color("bd75a0")]

func setup(state: RefCounted) -> void:
	game = state
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for country in game.atlas:
		if not country.dependencies.is_empty(): political_groups.append(int(country.id))
		var rings: Array = []
		var fills: Array = []
		var boxes: Array = []
		for ring in country.rings:
			var polygon = PackedVector2Array()
			var fill = PackedVector2Array()
			for point in ring:
				polygon.append(project_point(Vector2(point[0], point[1])))
				# Local coordinates keep tiny island polygons above the triangulator's precision limit.
				fill.append(Vector2((float(point[0]) - float(ring[0][0])) / 360.0 * 1000000.0, (float(ring[0][1]) - float(point[1])) / 145.0 * 450000.0))
			rings.append(polygon)
			fills.append(fill)
			var box = Rect2(polygon[0], Vector2.ZERO)
			for p in polygon:
				box = box.expand(p)
			boxes.append(box)
		polygons.append(rings)
		fill_polygons.append(fills)
		bounds.append(boxes)
		centers.append(project_point(Vector2(country.center[0], country.center[1])))
		if boxes.all(func(box): return box.size.length() < 4.0):
			small_countries.append(int(country.id))
	resized.connect(queue_redraw)
	details_layer = MotionLayer.new()
	details_layer.map = self
	details_layer.details = true
	details_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(details_layer)
	motion_layer = MotionLayer.new()
	motion_layer.map = self
	motion_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(motion_layer)
	motion_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

class MotionLayer extends Control:
	var map: Control
	var details = false
	func _draw() -> void:
		if details: map.draw_details(self)
		else: map.draw_motion(self)

class BattleFront extends Node2D:
	const SHADER = preload("res://src/battle_front.gdshader")
	var map: Control
	var op: Dictionary
	var target: int
	var defender: Color
	var attacker: Color
	var captured_by: String
	var progress = 0.0
	var amount = 0.0
	var result = ""
	var age = 0.0

	func _draw() -> void:
		var direction: Vector2 = map.centers[target] - map.centers[int(op.from)]
		if absf(direction.x) > 500.0: direction.x -= signf(direction.x) * 1000.0
		direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
		for j in map.fill_polygons[target].size():
			var polygon: PackedVector2Array = map.fill_polygons[target][j]
			if polygon.size() < 3: continue
			var distances := PackedVector2Array()
			var low = INF
			var high = -INF
			var start: Vector2 = map.polygons[target][j][0]
			for point in polygon:
				var distance = point.dot(direction)
				low = minf(low, distance)
				high = maxf(high, distance)
				distances.append(Vector2(distance, (point.x + point.y + (start.x + start.y) * 1000.0) / 4800.0))
			for i in distances.size():
				distances[i].x = (distances[i].x - low) / maxf(high - low, 0.001)
			draw_set_transform(map.polygons[target][j][0] * 1000.0)
			# UV.x places the moving edge without clipping or triangulating every frame.
			draw_polygon(polygon, PackedColorArray([Color.WHITE]), distances)

	func align_to_map() -> void:
		position = -map.relief.domain.position * map.relief.texture_axes if map.tilted else map.map_origin()
		scale = (map.relief.texture_axes if map.tilted else map.map_axes()) / 1000.0
		material.set_shader_parameter("striped", map.tilted)

	func show_front() -> void:
		material.set_shader_parameter("front", amount)
		material.set_shader_parameter("tint", map.territory_paint(target, defender) if result == "capture" else attacker)
		material.set_shader_parameter("captured", result == "capture")

func _process(delta: float) -> void:
	if game == null:
		return
	if game.home >= 0 and (not game.paused or game.finished):
		visual_time = clampf(visual_time + delta, game.elapsed, game.elapsed + 0.99)
		for pulse in pulses:
			pulse.age += delta
		pulses = pulses.filter(func(pulse): return pulse.age < 2.6)
		update_fronts(delta)
		if tilted: relief.animate(delta)
	while not game.effects.is_empty():
		var effect = game.effects.pop_front()
		effect.age = 0.0
		pulses.append(effect)
	motion_layer.queue_redraw()

func clear_motion() -> void:
	pulses.clear()
	for front in fronts.values():
		front.hide()
		front.queue_free()
	fronts.clear()
	if tilted: relief.refresh_politics()
	owners.clear()
	owner_colors.clear()
	sync_ownership()
	visual_time = game.elapsed
	motion_layer.queue_redraw()

func territory_owner(id: int) -> String:
	if game.countries[id].owned: return "player"
	return game.country_colors.get(str(id), "")

func add_front(key: Array, op: Dictionary) -> BattleFront:
	var front = BattleFront.new()
	front.map = self
	front.op = op
	front.target = int(op.target)
	front.material = ShaderMaterial.new()
	front.material.shader = BattleFront.SHADER
	place_front(front)
	fronts[key] = front
	return front

func place_front(front: BattleFront) -> void:
	var layer: Node = relief.colors if tilted else self
	if front.get_parent() == null: layer.add_child(front)
	elif front.get_parent() != layer: front.reparent(layer, false)
	if not tilted: move_child(front, details_layer.get_index())
	front.align_to_map()
	front.show_front()

func sync_ownership() -> void:
	for id in polygons.size():
		var owner = territory_owner(id)
		var color = territory_color(id)
		if id >= owners.size():
			owners.append(owner)
			owner_colors.append(color)
			continue
		if owner != owners[id] and color != owner_colors[id] and game.country_visible(id):
			var capture: BattleFront
			for front in fronts.values():
				if front.target != id or not front.result.is_empty() or front.op.arrival > game.elapsed: continue
				var attacker = "player" if front.op.kind == "attack" else str(front.op.get("source_color", ""))
				if attacker == owner:
					capture = front
					break
			if capture == null:
				capture = add_front(["capture", id, game.elapsed, owner], {"from": id, "target": id})
			capture.result = "capture"
			capture.captured_by = owner
			capture.defender = owner_colors[id]
			capture.show_front()
		owners[id] = owner
		owner_colors[id] = color

func update_fronts(delta: float) -> void:
	var had_fronts := not fronts.is_empty()
	var active = {}
	for op in game.operations + game.remote_operations:
		if op.kind not in ["attack", "enemy"] or op.get("surprise", false): continue
		var id = int(op.target)
		if not game.country_visible(id): continue
		var key = [op.kind, int(op.from), id, int(op.start), int(op.arrival), op.get("source_color", "")]
		active[key] = true
		if not fronts.has(key):
			var front = add_front(key, op)
			front.attacker = Color(op.get("source_color", "f58c83")) if op.kind == "enemy" else game.player_color
	for key in fronts.keys():
		var front = fronts[key]
		var op = front.op
		if front.result.is_empty() and not active.has(key):
			front.result = "retreat"
		if front.result.is_empty():
			front.progress = route_progress(op)
			front.amount = 0.62 * smoothstep(0.32, 1.0, front.progress)
		else:
			front.age += delta
			var duration = CAPTURE_SECONDS if front.result == "capture" else RETREAT_SECONDS
			if front.age >= duration or (front.result == "retreat" and front.progress <= 0.0) or (front.result == "capture" and territory_owner(front.target) != front.captured_by):
				front.hide()
				front.queue_free()
				fronts.erase(key)
				continue
			var t = smoothstep(0.0, duration, front.age)
			var initial = 0.62 * smoothstep(0.32, 1.0, front.progress)
			front.amount = lerpf(initial, 1.0 if front.result == "capture" else 0.0, t)
		front.show_front()
	if tilted and (had_fronts or not fronts.is_empty()): relief.politics_dirty = true

func screen_point(id: int) -> Vector2:
	return project_map(centers[id])

func project_map(point: Vector2, lift: float = 0.0) -> Vector2:
	var screen := point * map_axes() + map_origin()
	if tilted: screen.y -= (relief.height_at(point) + lift) * map_scale() * MapRelief.HEIGHT_PROJECTION
	return screen

func screen_ground(point: Vector2) -> Vector2:
	var flat := (point - map_origin()) / map_axes()
	return relief.ground_hit(flat) if tilted else flat

func route_progress(op: Dictionary) -> float:
	return clampf((visual_time - op.start) / maxf(1, op.arrival - op.start), 0, 1)

func draw_motion(canvas: Control) -> void:
	var routes = game.operations.duplicate()
	var models := []
	var use_models := tilted and map_scale() >= 2.6
	var model_scale := minf(1.14, 5.2 / maxf(1.0, map_scale()))
	routes.append_array(game.remote_operations)
	if not game.mission.is_empty():
		var agent = game.mission.duplicate()
		agent.kind = "spy"
		routes.append(agent)
	for front in fronts.values():
		if front.result == "retreat":
			var retreat = front.op.duplicate()
			retreat["return_progress"] = front.progress
			retreat["return_fraction"] = 1.0 - smoothstep(0.0, RETREAT_SECONDS, front.age)
			routes.append(retreat)
	for op in routes:
		if op.kind == "enemy" and op.get("surprise", false): continue
		var a = screen_point(int(op.from))
		var b = screen_point(int(op.target))
		var progress: float = op.get("return_progress", route_progress(op))
		var returning = op.has("return_progress")
		var return_fraction: float = op.get("return_fraction", 1.0)
		var troops = op.kind in ["attack", "enemy"]
		var ground_route = tilted and troops
		var from_map: Vector2 = centers[int(op.from)]
		var to_map: Vector2 = centers[int(op.target)]
		var overseas: bool = op.get("overseas", false)
		var offset = route_delta(from_map, to_map)
		var sea_bend = minf(32.0, offset.length() * 0.16) if overseas else 0.0
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
			if ground_route:
				point = project_map(troop_point(from_map, offset, sea_bend, t))
				if absf(point.x - previous.x) > map_axes().x * 500.0:
					previous = point
					continue
			if troops and t <= progress * return_fraction:
				canvas.draw_line(previous, point, Color(color, 0.68), 2.0, true)
			elif not returning and step % 2 == 0:
				canvas.draw_line(previous, point, Color(color, 0.45), 1.5, true)
			previous = point
		for index in (3 if troops and (use_models or not tilted) else 1):
			var t = (progress - index * 0.055) * return_fraction
			if t < 0.0 or t > 1.0: continue
			var point = a.lerp(b, t) + Vector2(0, -sin(t * PI) * bend)
			var angle = (b - a + Vector2(0, -cos(t * PI) * bend * PI)).angle()
			if returning: angle += PI
			if ground_route:
				var on_map = troop_point(from_map, offset, sea_bend, t)
				point = project_map(on_map)
				var heading = offset - Vector2(0, cos(t * PI) * sea_bend * PI)
				if returning: heading = -heading
				angle = (heading * map_axes()).angle()
				if use_models:
					on_map += heading.normalized().orthogonal() * (index - 1) * 4.6 * model_scale
					point = project_map(on_map)
					var ground = relief.height_at(on_map)
					var afloat = overseas and ground < 0.55 and not contains_country(op.from, on_map) and not contains_country(op.target, on_map)
					var aircraft = index == 1 and (op.kind != "attack" or game.units[1] > 0)
					var kind = Armies.AIRCRAFT if aircraft else (Armies.SHIP if afloat else Armies.INFANTRY)
					var lift = 5.5 + sin(t * TAU) * 0.8 if kind == Armies.AIRCRAFT else 0.22
					models.append({"kind": kind, "position": Vector3(on_map.x, ground + lift, on_map.y),
						"heading": heading, "color": color.lightened(0.25), "ground": ground})
					if kind != Armies.AIRCRAFT: draw_troop_trail(canvas, point, angle, kind == Armies.SHIP)
					continue
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
			if tilted and troops:
				canvas.draw_ellipse(point + Vector2(2, 1), 10, 4, Color(0.02, 0.06, 0.09, 0.55))
				for depth in range(3, 0, -1):
					canvas.draw_set_transform(Vector2(0, -depth))
					canvas.draw_colored_polygon(shape, color.darkened(0.62))
				canvas.draw_set_transform(Vector2(0, -4))
				canvas.draw_colored_polygon(shape, color.lightened(0.24))
				canvas.draw_set_transform(Vector2.ZERO)
				if op.kind == "attack":
					var font = ThemeDB.fallback_font
					var label = str(game.units.reduce(func(total, count): return total + count, 0))
					canvas.draw_string_outline(font, point + Vector2(10, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color("10222f"))
					canvas.draw_string(font, point + Vector2(10, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("edf7fb"))
			else:
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
		elif tilted and pulse.age < 0.27:
			var flash = 1.0 - pulse.age / 0.27
			canvas.draw_circle(point, lerpf(15, 3, flash), Color(1.0, 0.79, 0.48, flash * 0.8))
	if tilted:
		relief.armies.update_units(models, model_scale, not detailed_map)

func route_delta(from: Vector2, to: Vector2) -> Vector2:
	var delta := to - from
	if absf(delta.x) > 500.0: delta.x -= signf(delta.x) * 1000.0
	return delta

func troop_point(from: Vector2, offset: Vector2, bend: float, t: float) -> Vector2:
	var point := from + offset * t - Vector2(0, sin(t * PI) * bend)
	point.x = fposmod(point.x, 1000.0)
	return point

func draw_troop_trail(canvas: Control, point: Vector2, angle: float, ship: bool) -> void:
	var forward := Vector2.from_angle(angle)
	if ship:
		for side in [-1, 1]:
			var tail := point - forward * 19.0 + forward.orthogonal() * 7.0 * float(side)
			canvas.draw_line(point - forward * 5.0, tail, Color(0.70, 0.92, 0.96, 0.40), 1.4, true)
	else:
		for puff in 3:
			var age := fposmod(visual_time * 3.2 + puff / 3.0, 1.0)
			var position := point - forward * (6.0 + age * 18.0) + forward.orthogonal() * (puff - 1) * 2.2
			canvas.draw_circle(position, 2.0 + age * 4.0, Color(0.76, 0.64, 0.46, (1.0 - age) * 0.29))

func project_point(point: Vector2) -> Vector2:
	return Vector2((point.x + 180.0) / 360.0 * 1000.0, (85.0 - point.y) / 145.0 * 450.0)

func map_scale() -> float:
	return minf(size.x / 1060.0, size.y / 510.0) * zoom

func map_axes() -> Vector2:
	return map_scale() * Vector2(1, MapRelief.FORESHORTENING if tilted else 1.0)

func map_origin() -> Vector2:
	return size * 0.5 - MAP_CENTER * map_axes() + pan

func set_tilted(enabled: bool) -> void:
	if tilted == enabled: return
	var center_on_map := screen_ground(size * 0.5) if map_scale() > 0 else MAP_CENTER
	if enabled and relief == null:
		relief = MapRelief.new()
		relief.setup(not Rules.content().has("map"), Media.color("ocean", Color("123451")))
		add_child(relief)
		relief.colors.draw.connect(draw_political)
		relief.set_detailed(detailed_map)
	tilted = enabled
	pan += size * 0.5 - project_map(center_on_map)
	for front in fronts.values(): place_front(front)
	if tilted: relief.refresh_politics()
	else: relief.render_target_update_mode = SubViewport.UPDATE_DISABLED
	queue_redraw()

func set_detailed_map(enabled: bool) -> void:
	detailed_map = enabled
	if relief != null: relief.set_detailed(enabled)
	if tilted:
		for front in fronts.values(): front.align_to_map()
	refresh_map()

func refresh_map() -> void:
	if tilted: relief.refresh_politics()
	queue_redraw()

func set_zoom(value: float, pivot: Vector2 = Vector2(-1, -1)) -> void:
	if pivot.x < 0:
		pivot = size * 0.5
	var before = screen_ground(pivot)
	zoom = clampf(value, 1.0, 9.0)
	pan += pivot - project_map(before)
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
	pan += size * 0.5 - screen_point(id)
	clamp_pan()
	zoom_changed.emit(zoom)
	refresh_map()

func pick(point: Vector2) -> int:
	var marker = -1
	var marker_distance = 8.0
	for id in small_countries:
		if not game.country_visible(id): continue
		var distance = screen_point(id).distance_to(point)
		if distance < marker_distance:
			marker = id
			marker_distance = distance
	if marker >= 0: return marker
	var p = screen_ground(point)
	for i in polygons.size():
		if not game.country_visible(i): continue
		if contains_country(i, p): return i
	var nearest = -1
	var distance = 9.0
	for i in centers.size():
		if not game.country_visible(i): continue
		var d = screen_point(i).distance_to(point)
		if d < distance:
			nearest = i
			distance = d
	return nearest

func contains_country(id: int, point: Vector2) -> bool:
	for j in polygons[id].size():
		if bounds[id][j].has_point(point) and Geometry2D.is_point_in_polygon(point, polygons[id][j]): return true
	return false

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
				refresh_map()

func territory_color(id: int) -> Color:
	if game.countries[id].owned: return game.player_color.darkened(0.12)
	if not game.reports.has(str(id)): return UNKNOWN
	if game.country_colors.has(str(id)): return Color(game.country_colors[str(id)]).darkened(0.12)
	var sovereign = int(game.atlas[id].sovereign)
	var group = political_groups.find(sovereign)
	return LAND[(group if group >= 0 else sovereign) % LAND.size()]

func highlighted_color(id: int) -> Color:
	return highlight_territory(id, territory_color(id))

func territory_paint(id: int, color: Color) -> Color:
	if tilted and relief.natural and color == UNKNOWN: color = Color(0.5, 0.5, 0.5)
	return highlight_territory(id, color)

func highlight_territory(id: int, color: Color) -> Color:
	if id == hovered: color = color.lightened(0.17)
	if id == selected: color = color.lightened(0.2)
	return color

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Media.color("ocean", Color("123451")))
	if game == null or map_scale() <= 0.0:
		return
	var axes = map_axes()
	var origin = map_origin()
	if tilted:
		relief.update_camera(size, MAP_CENTER, pan, axes.x)
		draw_texture_rect(relief.get_texture(), Rect2(Vector2.ZERO, size), false)
		details_layer.queue_redraw()
		return
	for front in fronts.values(): front.align_to_map()
	draw_set_transform(origin, 0, axes)
	for longitude in range(-180, 181, 30):
		var x = project_point(Vector2(longitude, 0)).x
		draw_line(Vector2(x, -40), Vector2(x, 500), Color("214763"), 0.6 / axes.x, true)
	for latitude in range(-60, 91, 30):
		var y = project_point(Vector2(0, latitude)).y
		draw_line(Vector2(0, y), Vector2(1000, y), Color("214763"), 0.6 / axes.x, true)
	draw_countries(self, origin, axes)
	details_layer.queue_redraw()

func draw_political() -> void:
	var axes: Vector2 = relief.texture_axes
	var origin: Vector2 = -relief.domain.position * axes
	draw_countries(relief.colors, origin, axes, 0.38 * axes.x)
	if selected >= 0 and game.country_visible(selected):
		relief.colors.draw_set_transform(origin, 0, axes)
		for polygon in polygons[selected]:
			relief.colors.draw_polyline(polygon, Color("ffda80"), 0.75, true)

func draw_countries(canvas: CanvasItem, origin: Vector2, axes: Vector2, border_width: float = 0.8) -> void:
	for i in polygons.size():
		if not game.country_visible(i): continue
		var color = territory_paint(i, territory_color(i))
		for j in fill_polygons[i].size():
			var polygon = fill_polygons[i][j]
			canvas.draw_set_transform(origin + polygons[i][j][0] * axes, 0, axes / 1000.0)
			if polygon.size() >= 3:
				canvas.draw_colored_polygon(polygon, color)
				canvas.draw_polyline(polygon, Color("17364b"), border_width * 1000.0 / axes.x, true)

func draw_details(canvas: Control) -> void:
	var axes = map_axes()
	for id in small_countries:
		if not game.country_visible(id): continue
		canvas.draw_circle(screen_point(id), 4.5, Color("ffda80") if id == selected else Color("17364b"))
		canvas.draw_circle(screen_point(id), 3.0, highlighted_color(id))
	if selected >= 0:
		if not tilted:
			canvas.draw_set_transform(map_origin(), 0, axes)
			for polygon in polygons[selected]:
				canvas.draw_polyline(polygon, Color("ffda80"), 1.8 / axes.x, true)
			canvas.draw_set_transform(Vector2.ZERO)
		var center := screen_point(selected)
		canvas.draw_circle(center, 7, Color(0.95, 0.82, 0.59, 0.15))
		canvas.draw_circle(center, 3, Color("ffda80"))
	if game.home >= 0 and game.countries[game.home].owned:
		canvas.draw_circle(screen_point(game.home), 5, game.player_color, false, 1.6, true)
	var font = ThemeDB.fallback_font
	for id in game.atlas.size():
		var flag = Media.flag(id)
		if flag != null and game.country_visible(id) and (game.countries[id].owned or game.reports.has(str(id))): canvas.draw_texture_rect(flag, Rect2(screen_point(id) + Vector2(-12, -25), Vector2(24, 16)), false)
	for id in game.wars:
		if game.countries[int(id)].owned: continue
		var point = screen_point(int(id))
		canvas.draw_circle(point, 9, Color("501e2b"))
		canvas.draw_line(point + Vector2(-4, -4), point + Vector2(4, 4), Color("ff9a9a"), 2, true)
		canvas.draw_line(point + Vector2(-4, 4), point + Vector2(4, -4), Color("ff9a9a"), 2, true)
		canvas.draw_line(point + Vector2(-5, 1), point + Vector2(-1, 5), Color("ff9a9a"), 1.5, true)
		canvas.draw_line(point + Vector2(1, 5), point + Vector2(5, 1), Color("ff9a9a"), 1.5, true)
	for ocean in [[L.text("Т И Х И Й  О К Е А Н"), Vector2(-145, 0)], [L.text("А Т Л А Н Т И К А"), Vector2(-35, 8)], [L.text("И Н Д И Й С К И Й"), Vector2(76, -27)]]:
		var p = project_point(ocean[1]) * axes + map_origin()
		canvas.draw_string(font, p - Vector2(65, 0), ocean[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("7daac5"))
	for id in game.reports:
		var country = int(id)
		var name = str(L.country(game.atlas[country]))
		var font_size = int(clampf(11 + zoom, 12, 17))
		var point = screen_point(country) + Vector2(0, -10)
		point.x -= font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
		canvas.draw_string_outline(font, point, name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color("0b1720"))
		canvas.draw_string(font, point, name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e9e4ce"))
