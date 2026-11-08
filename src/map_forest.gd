extends Node3D

const TREE_SHADER = preload("res://src/atlas_tree.gdshader")
const GRID_STEP = 4
const TILE_SIZE = 80.0
const NEEDLELEAF = 0
const BROADLEAF = 1

var tree_count = 0

func setup(relief: SubViewport, cover: Texture2D, inland_water: Texture2D) -> void:
	var map := cover.get_image()
	var extent: Vector2 = relief.domain.size
	var clusters := {}
	var random := RandomNumberGenerator.new()
	random.seed = 45209
	for y in range(2, int(extent.y), GRID_STEP):
		for x in range(2, int(extent.x), GRID_STEP):
			var point := Vector2(x + random.randf_range(-1.8, 1.8), y + random.randf_range(-1.8, 1.8))
			var sample := Vector2i(point / extent * Vector2(map.get_size()))
			var density := map.get_pixelv(sample)
			var probability := density.r + density.g
			if probability < 0.24 or random.randf() > probability: continue
			var kind := NEEDLELEAF if random.randf() * probability < density.r else BROADLEAF
			var tile := Vector2i(point / TILE_SIZE)
			var key := Vector3i(tile.x, tile.y, kind)
			if not clusters.has(key): clusters[key] = []
			var size := random.randf_range(0.73, 1.18)
			var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
			clusters[key].append(Transform3D(basis, Vector3(point.x, relief.height_at(point) - 0.06, point.y)))

	var material := ShaderMaterial.new()
	material.shader = TREE_SHADER
	material.set_shader_parameter("politics", relief.political.get_texture())
	material.set_shader_parameter("inland_water", inland_water)
	var meshes := [create_tree(NEEDLELEAF), create_tree(BROADLEAF)]
	for tile in clusters:
		var trees := MultiMesh.new()
		trees.transform_format = MultiMesh.TRANSFORM_3D
		trees.use_colors = true
		trees.mesh = meshes[tile.z]
		trees.instance_count = clusters[tile].size()
		tree_count += trees.instance_count
		var leaf := Color("294d2b") if tile.z == NEEDLELEAF else Color("3a6230")
		for i in trees.instance_count:
			trees.set_instance_transform(i, clusters[tile][i])
			trees.set_instance_color(i, leaf.lightened(random.randf_range(0.0, 0.12)))
		var patch := MultiMeshInstance3D.new()
		patch.multimesh = trees
		patch.material_override = material
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(patch)

func create_tree(kind: int) -> ArrayMesh:
	var trunk := CylinderMesh.new()
	trunk.radial_segments = 5
	trunk.rings = 0
	trunk.top_radius = 0.105
	trunk.bottom_radius = 0.14
	trunk.height = 0.62
	var tree := SurfaceTool.new()
	tree.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.31, 0)))
	if kind == NEEDLELEAF:
		var crown := CylinderMesh.new()
		crown.radial_segments = 6
		crown.rings = 0
		crown.top_radius = 0.02
		crown.bottom_radius = 0.55
		crown.height = 1.13
		tree.append_from(crown, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.99, 0)))
		tree.append_from(crown, 0, Transform3D(Basis.from_scale(Vector3(0.75, 0.8, 0.75)), Vector3(0, 1.4, 0)))
	else:
		var crown := SphereMesh.new()
		crown.radial_segments = 7
		crown.rings = 3
		crown.radius = 0.62
		crown.height = 1.22
		tree.append_from(crown, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)))
	return tree.commit()
