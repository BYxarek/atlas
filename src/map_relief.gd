extends SubViewport

const Terrain = preload("res://src/atlas_terrain.gdshader")
const Water = preload("res://src/atlas_water.gdshader")
const Armies = preload("res://src/map_armies.gd")
const Forest = preload("res://src/map_forest.gd")
const TILT = 52.0
const FORESHORTENING = sin(deg_to_rad(TILT))
const HEIGHT_PROJECTION = cos(deg_to_rad(TILT))
const MAX_HEIGHT = 16.0
const EARTH_SIZE = Vector2(1000, 450)

var camera := Camera3D.new()
var political := SubViewport.new()
var colors := Node2D.new()
var domain := Rect2(Vector2.ZERO, EARTH_SIZE)
var texture_axes: Vector2
var terrain_size: Vector2i
var heights := PackedFloat32Array()
var sunlight := DirectionalLight3D.new()
var terrain_material := ShaderMaterial.new()
var water_material := ShaderMaterial.new()
var forest: Node3D
var forest_cover: Texture2D
var inland_water: Texture2D
var natural = false
var armies: Node3D
var detailed = false
var frame_time = 0.0
var water_time = 0.0
var politics_dirty = false

func setup(earth: bool, ocean: Color) -> void:
	natural = earth
	own_world_3d = true
	transparent_bg = true
	gui_disable_input = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not earth: domain = Rect2(0, -16, 1000, 560)
	political.disable_3d = true
	political.transparent_bg = true
	political.gui_disable_input = true
	political.render_target_update_mode = SubViewport.UPDATE_DISABLED
	resize_politics()
	add_child(political)
	political.add_child(colors)

	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees.x = -TILT
	camera.current = true

	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c3d4e6")
	environment.ambient_light_energy = 0.55
	camera.environment = environment
	sunlight.rotation_degrees = Vector3(-42, -32, 0)
	sunlight.light_color = Color("fff0d8")
	sunlight.light_energy = 0.67
	sunlight.directional_shadow_max_distance = 1800.0
	add_child(sunlight)

	var image := load("res://assets/earth_relief.png").get_image() as Image
	terrain_size = image.get_size() if earth else Vector2i(2, 2)
	heights.resize(terrain_size.x * terrain_size.y)
	if earth:
		for y in terrain_size.y:
			for x in terrain_size.x:
				heights[y * terrain_size.x + x] = image.get_pixel(x, y).r * MAX_HEIGHT
	terrain_material.shader = Terrain
	terrain_material.set_shader_parameter("politics", political.get_texture())
	terrain_material.set_shader_parameter("natural", natural)
	if natural:
		forest_cover = load("res://assets/earth_forests.png")
		inland_water = load("res://assets/earth_inland_water.png")
		terrain_material.set_shader_parameter("land_cover", load("res://assets/earth_land.jpg"))
		terrain_material.set_shader_parameter("inland_water", inland_water)
		terrain_material.set_shader_parameter("forest_cover", forest_cover)
	var land := MeshInstance3D.new()
	land.mesh = create_terrain()
	land.material_override = terrain_material
	add_child(land)

	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = domain.size
	sea.mesh = plane
	sea.position = Vector3(domain.get_center().x, -0.08, domain.get_center().y)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_material.shader = Water
	water_material.set_shader_parameter("elevation", ImageTexture.create_from_image(image))
	water_material.set_shader_parameter("ocean", ocean)
	water_material.set_shader_parameter("earth", earth)
	sea.material_override = water_material
	add_child(sea)
	armies = Armies.new()
	add_child(armies)

func create_terrain() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var last := terrain_size - Vector2i.ONE
	var step := domain.size / Vector2(last)
	for y in terrain_size.y:
		for x in terrain_size.x:
			var point := domain.position + Vector2(x, y) * step
			vertices.append(Vector3(point.x, sample(x, y), point.y))
			normals.append(Vector3(
				(sample(x - 1, y) - sample(x + 1, y)) / (2.0 * step.x), 1,
				(sample(x, y - 1) - sample(x, y + 1)) / (2.0 * step.y)
			).normalized())
			uvs.append(Vector2(x, y) / Vector2(last))
			if x < last.x and y < last.y:
				var a := y * terrain_size.x + x
				var b := a + terrain_size.x
				indices.append_array([a, a + 1, b, a + 1, b + 1, b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func sample(x: int, y: int) -> float:
	return heights[clampi(y, 0, terrain_size.y - 1) * terrain_size.x + clampi(x, 0, terrain_size.x - 1)]

func height_at(point: Vector2) -> float:
	if not domain.has_point(point): return 0.0
	var p := (point - domain.position) / domain.size * Vector2(terrain_size - Vector2i.ONE)
	var x := floori(p.x)
	var y := floori(p.y)
	var f := p - Vector2(x, y)
	var right := sample(x + 1, y)
	var bottom := sample(x, y + 1)
	if f.x + f.y <= 1.0:
		return sample(x, y) * (1.0 - f.x - f.y) + right * f.x + bottom * f.y
	return sample(x + 1, y + 1) * (f.x + f.y - 1.0) + right * (1.0 - f.y) + bottom * (1.0 - f.x)

func ground_hit(flat_point: Vector2) -> Vector2:
	# Find the first intersection along the orthographic ray, including steep faces.
	var span := MAX_HEIGHT * HEIGHT_PROJECTION / FORESHORTENING
	var above := flat_point.y + span + 0.01
	for step in range(1, 17):
		var below := flat_point.y + span * (1.0 - step / 16.0)
		if ray_above_ground(flat_point, below):
			above = below
			continue
		for i in 12:
			var middle := (above + below) * 0.5
			if ray_above_ground(flat_point, middle): above = middle
			else: below = middle
		return Vector2(flat_point.x, below)
	return flat_point

func ray_above_ground(flat_point: Vector2, z: float) -> bool:
	return (z - flat_point.y) * FORESHORTENING > height_at(Vector2(flat_point.x, z)) * HEIGHT_PROJECTION

func set_detailed(enabled: bool) -> void:
	if detailed == enabled: return
	detailed = enabled
	resize_politics()
	msaa_3d = Viewport.MSAA_2X if enabled else Viewport.MSAA_DISABLED
	sunlight.shadow_enabled = enabled
	water_material.set_shader_parameter("detailed", enabled)
	render_target_update_mode = SubViewport.UPDATE_ONCE

func resize_politics() -> void:
	var width := 4096 if detailed else (2048 if OS.has_feature("android") else 2560)
	political.size = Vector2i(width, roundi(width * domain.size.y / domain.size.x))
	texture_axes = Vector2(political.size) / domain.size

func update_camera(view_size: Vector2, center: Vector2, pan: Vector2, map_scale: float) -> void:
	var show_trees := natural and map_scale >= 2.85
	if show_trees and forest == null:
		forest = Forest.new()
		add_child(forest)
		forest.setup(self, forest_cover, inland_water)
	if forest != null: forest.visible = show_trees
	var limit := 1920.0 if detailed else 1280.0
	var pixels := Vector2i((view_size * minf(1.0, limit / maxf(view_size.x, view_size.y))).round()).max(Vector2i(2, 2))
	var height := view_size.y / map_scale
	var position := Vector3(center.x, 0, center.y) + camera.basis.z * 1000.0
	position += (-camera.basis.x * pan.x + camera.basis.y * pan.y) / map_scale
	if size == pixels and camera.position.is_equal_approx(position) and is_equal_approx(camera.size, height): return
	terrain_material.set_shader_parameter("river_detail", smoothstep(1.9, 4.2, map_scale))
	size = pixels
	camera.position = position
	camera.size = height
	render_target_update_mode = SubViewport.UPDATE_ONCE

func refresh_politics() -> void:
	colors.queue_redraw()
	political.render_target_update_mode = SubViewport.UPDATE_ONCE
	render_target_update_mode = SubViewport.UPDATE_ONCE
	politics_dirty = false

func animate(delta: float) -> void:
	frame_time += delta
	water_time = fmod(water_time + delta, 600.0)
	var interval := 1.0 / (60.0 if detailed else 30.0)
	if frame_time < interval: return
	frame_time = fmod(frame_time, interval)
	if politics_dirty:
		political.render_target_update_mode = SubViewport.UPDATE_ONCE
		politics_dirty = false
	water_material.set_shader_parameter("wave_time", water_time)
	render_target_update_mode = SubViewport.UPDATE_ONCE
