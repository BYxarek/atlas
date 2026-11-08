extends Node3D

enum { INFANTRY, AIRCRAFT, SHIP, SHADOW }

var groups: Array[MultiMeshInstance3D] = []
var counts := PackedInt32Array([0, 0, 0, 0])

func _ready() -> void:
	var unit_material := StandardMaterial3D.new()
	unit_material.vertex_color_use_as_albedo = true
	unit_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	unit_material.roughness = 0.88
	for kind in 3:
		add_group(unit_mesh(kind), unit_material)
	var disc := PlaneMesh.new()
	disc.size = Vector2(7.2, 5.2)
	var shadow := ShaderMaterial.new()
	shadow.shader = preload("res://src/atlas_contact_shadow.gdshader")
	add_group(disc, shadow)
	groups[SHADOW].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func add_group(mesh: Mesh, material: Material) -> void:
	var group := MultiMeshInstance3D.new()
	group.material_override = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = mesh
	group.multimesh = instances
	add_child(group)
	groups.append(group)

func unit_mesh(kind: int) -> ArrayMesh:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.set_smooth_group(-1)
	match kind:
		INFANTRY:
			for x in [-1.45, 0.0, 1.45]:
				var z := 0.45 if x != 0.0 else -0.50
				box(mesh, Rect2(x - 0.42, z - 0.32, 0.84, 0.68), 0.12, 1.65, 0.86)
				box(mesh, Rect2(x - 0.36, z - 0.34, 0.72, 0.70), 1.65, 2.25, 1.0)
				box(mesh, Rect2(x + 0.22, z - 0.90, 0.21, 1.15), 0.97, 1.25, 0.52)
		AIRCRAFT:
			prism(mesh, PackedVector2Array([Vector2(0, -4.1), Vector2(0.73, -1.4), Vector2(0.48, 2.9), Vector2(-0.48, 2.9), Vector2(-0.73, -1.4)]), 0.1, 0.78, 1.0)
			prism(mesh, PackedVector2Array([Vector2(0, -1.8), Vector2(3.4, 1.25), Vector2(3.18, 1.72), Vector2(0, 0.85), Vector2(-3.18, 1.72), Vector2(-3.4, 1.25)]), 0.05, 0.28, 0.88)
			box(mesh, Rect2(-1.32, 2.0, 2.64, 0.65), 0.17, 0.38, 0.82)
			box(mesh, Rect2(-0.16, 2.0, 0.32, 0.62), 0.42, 1.22, 0.96)
		SHIP:
			prism(mesh, PackedVector2Array([Vector2(0, -3.9), Vector2(1.35, -1.9), Vector2(1.38, 2.2), Vector2(0.92, 3.2), Vector2(-0.92, 3.2), Vector2(-1.38, 2.2), Vector2(-1.35, -1.9)]), 0.05, 0.82, 0.78)
			box(mesh, Rect2(-0.90, -0.88, 1.80, 2.12), 0.82, 1.62, 1.0)
			box(mesh, Rect2(-0.47, -0.45, 0.94, 0.68), 1.62, 2.25, 0.88)
			box(mesh, Rect2(-0.14, -2.30, 0.28, 1.24), 0.85, 1.12, 0.54)
	mesh.generate_normals()
	return mesh.commit()

func box(mesh: SurfaceTool, rect: Rect2, low: float, high: float, tone: float) -> void:
	prism(mesh, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), low, high, tone)

func prism(mesh: SurfaceTool, polygon: PackedVector2Array, low: float, high: float, tone: float) -> void:
	mesh.set_color(Color(tone, tone, tone))
	for index in Geometry2D.triangulate_polygon(polygon):
		var p := polygon[index]
		mesh.add_vertex(Vector3(p.x, high, p.y))
	mesh.set_color(Color(tone * 0.82, tone * 0.82, tone * 0.82))
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var top_a := Vector3(a.x, high, a.y)
		var top_b := Vector3(b.x, high, b.y)
		var low_a := Vector3(a.x, low, a.y)
		var low_b := Vector3(b.x, low, b.y)
		for point in [top_a, low_a, top_b, top_b, low_a, low_b]:
			mesh.add_vertex(point)

func update_units(orders: Array, unit_scale: float, shadows: bool) -> void:
	counts.fill(0)
	var needed := counts.duplicate()
	for order in orders: needed[order.kind] += 1
	needed[SHADOW] = orders.size() if shadows else 0
	for kind in groups.size():
		var instances := groups[kind].multimesh
		if instances.instance_count < needed[kind]:
			instances.instance_count = maxi(8, nearest_po2(needed[kind]))
	for order in orders:
		var heading: Vector2 = order.heading
		var basis := Basis(Vector3.UP, -heading.angle() - PI * 0.5).scaled(Vector3.ONE * unit_scale)
		var location: Vector3 = order.position
		write_instance(order.kind, Transform3D(basis, location), order.color)
		if shadows:
			location.y = order.ground + 0.12
			write_instance(SHADOW, Transform3D(basis, location), Color.WHITE)
	for kind in groups.size():
		groups[kind].multimesh.visible_instance_count = counts[kind]

func write_instance(kind: int, transform_3d: Transform3D, color: Color) -> void:
	var instances := groups[kind].multimesh
	var index := counts[kind]
	instances.set_instance_transform(index, transform_3d)
	instances.set_instance_color(index, color)
	counts[kind] += 1
