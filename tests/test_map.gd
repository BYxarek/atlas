extends SceneTree

const Game = preload("res://src/game.gd")
const World = preload("res://src/network_world.gd")
const Map = preload("res://src/world_map.gd")

func id_for(game: RefCounted, name: String) -> int:
	for c in game.atlas:
		if c.english == name: return int(c.id)
	return -1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = Game.new()
	assert(game.atlas.size() == 244 and game.military.armies.size() == 244)
	assert(game.atlas[0].english == "Fiji" and game.atlas[175].english == "South Sudan", "Existing territory IDs remain stable")
	var map = Map.new()
	map.setup(game)
	root.add_child(map)
	map.size = Vector2(1440, 900)
	await process_frame
	for c in game.atlas:
		assert(c.id >= 0 and c.id < Game.COUNTRY_COUNT)
		assert(game.atlas[int(c.sovereign)].sovereign == c.sovereign, "Dependencies point directly to an independent country")
		if int(c.sovereign) != int(c.id): assert(c.id in game.atlas[int(c.sovereign)].dependencies)
		for neighbor in c.neighbors: assert(c.id in game.atlas[int(neighbor)].neighbors, "Borders are mutual")
		for polygon in map.fill_polygons[int(c.id)]:
			assert(not Geometry2D.triangulate_polygon(polygon).is_empty(), "Every island can render: " + c.english)
	for name in ["Vatican", "Monaco", "San Marino", "Liechtenstein", "Andorra", "Malta", "Singapore", "Bahrain", "Nauru", "Tuvalu"]:
		var id = id_for(game, name)
		assert(id >= Game.LEGACY_COUNTRY_COUNT, "Missing small states have their own IDs")
		if id in Game.MICROSTATES:
			assert(not game.country_visible(id) and map.pick(map.screen_point(id)) != id, "Enclosed microstates start hidden")
			game.countries[id]["microstate"] = "war"
		assert(map.pick(map.screen_point(id)) == id, "Small state can be selected: " + name)
	assert(float(id_for(game, "Italy")) in game.atlas[id_for(game, "Vatican")].neighbors)
	game.start(0)
	var denmark = id_for(game, "Denmark")
	var greenland = id_for(game, "Greenland")
	assert(game.atlas[greenland].sovereign == denmark)
	assert(game.atlas[id_for(game, "Palestine")].sovereign == id_for(game, "Palestine"))
	assert(game.atlas[id_for(game, "Niue")].sovereign == id_for(game, "Niue"))
	assert(map.territory_color(denmark) == map.UNKNOWN and map.territory_color(greenland) == map.UNKNOWN)
	game.country_colors[str(denmark)] = "73aeef"
	assert(map.territory_color(denmark) == map.UNKNOWN, "Public multiplayer ownership does not reveal an unexplored color")
	game.country_colors.clear()
	game.reports[str(denmark)] = {"units": [1, 0, 0], "time": 0}
	game.reports[str(greenland)] = {"units": [1, 0, 0], "time": 0}
	assert(map.territory_color(denmark) == map.territory_color(greenland) and map.territory_color(denmark) != map.UNKNOWN)
	var colors = []
	for id in map.political_groups:
		game.reports[str(id)] = {"units": [1, 0, 0], "time": 0}
		assert(not map.territory_color(id) in colors, "Political groups have distinct colors")
		colors.append(map.territory_color(id))
	game.countries[greenland].owned = true
	assert(map.territory_color(greenland) == game.player_color.darkened(0.12), "Player conquest overrides geographic affiliation")
	game.countries[greenland].owned = false
	game.reports.clear()
	var legacy = game.export_data().duplicate(true)
	legacy.countries = legacy.countries.slice(0, Game.LEGACY_COUNTRY_COUNT)
	var restored = Game.new()
	assert(restored.restore_data(legacy, false), "Old solo saves expand without losing progress")
	assert(restored.countries.size() == 244 and restored.home == game.home and restored.coins == game.coins)
	assert(restored.countries.slice(0, Game.LEGACY_COUNTRY_COUNT) == legacy.countries)
	legacy.countries.pop_back()
	assert(not Game.new().restore_data(legacy, false), "Unknown truncated maps remain invalid")
	var world = World.new()
	var players = {"a": {"name": "A", "color": "69dfbd"}}
	world.add_faction("a", 0, "69dfbd")
	var saved = world.export_data().duplicate(true)
	saved.countries = saved.countries.slice(0, Game.LEGACY_COUNTRY_COUNT)
	saved.owners = saved.owners.slice(0, Game.LEGACY_COUNTRY_COUNT)
	saved.factions.a.countries = saved.factions.a.countries.slice(0, Game.LEGACY_COUNTRY_COUNT)
	var resumed = World.new()
	assert(resumed.restore_data(saved, players), "Old network saves expand both territory and faction arrays")
	assert(resumed.owners.size() == 244 and resumed.owners[0] == "a" and resumed.owners[243] == "")
	assert(resumed.command("a", "spy", [243]), "New territories accept network commands")
	var outcomes = {}
	for seed_value in range(1, 9):
		var campaign = Game.new()
		campaign.rng.seed = seed_value
		campaign.start(0)
		campaign.units = [100000, 10000, 1000]
		campaign.coins = 10000
		var italy = id_for(campaign, "Italy")
		var vatican = id_for(campaign, "Vatican")
		assert(not campaign.spy(vatican) and campaign.attack_block(vatican) != "", "Hidden microstates cannot be targeted")
		assert(campaign.attack(italy).victory)
		for name in ["Vatican", "San Marino"]:
			var id = id_for(campaign, name)
			var state = campaign.countries[id].microstate
			outcomes[state] = true
			assert(campaign.country_visible(id))
			assert(campaign.countries[id].owned == (state == "accepted"))
			assert((id in campaign.wars) == (state == "war"))
			assert(not id in campaign.conquests, "Peaceful accession does not grant conquest rewards")
		var before = campaign.countries[vatican].duplicate(true)
		var loaded = Game.new()
		assert(loaded.restore_data(campaign.export_data().duplicate(true), false))
		assert(loaded.countries[vatican] == before, "Save preserves the revealed decision")
		campaign.countries[italy].owned = false
		assert(campaign.attack(italy).victory)
		assert(campaign.countries[vatican] == before, "Recapture does not roll the decision again")
	assert(outcomes.has("accepted") and outcomes.has("war"), "Both chance outcomes occur")
	var canada = id_for(game, "Canada")
	var usa = id_for(game, "United States of America")
	var brazil = id_for(game, "Brazil")
	map.set_zoom(2.0)
	map.pan = Vector2(65, -48)
	var center_before: Vector2 = map.screen_ground(map.size * 0.5)
	map.set_tilted(true)
	await process_frame
	assert(map.map_axes().y < map.map_axes().x)
	assert(map.screen_ground(map.size * 0.5).distance_to(center_before) < 0.002)
	var anchor: Vector2 = map.screen_point(brazil)
	map.set_zoom(2.25, anchor)
	await process_frame
	assert(map.screen_point(brazil).distance_to(anchor) < 0.01 and map.pick(anchor) == brazil)
	var on_map: Vector2 = map.centers[brazil]
	var height: float = map.relief.height_at(on_map)
	var projected: Vector2 = map.relief.camera.unproject_position(Vector3(on_map.x, height, on_map.y)) * map.size / Vector2(map.relief.size)
	assert(projected.distance_to(anchor) < 0.1, "The 3D relief and 2D map stay aligned after zoom and pan")
	assert(map.relief.height_at(map.project_point(Vector2(86, 28))) > 8.0, "Himalayas use real land elevation")
	assert(map.relief.height_at(map.project_point(Vector2(-140, 0))) == 0.0, "Ocean remains at sea level")
	assert(map.relief.natural and map.relief.terrain_material.get_shader_parameter("land_cover") is Texture2D)
	assert(map.relief.forest.visible and map.relief.forest.tree_count > 1000, "Forest patches appear on close zoom")
	map.reset_view()
	await process_frame
	assert(not map.relief.forest.visible, "Individual trees are culled on the overview map")
	map.set_tilted(false)
	map.reset_view()
	for wins in [false, true]:
		map.set_tilted(wins)
		game.reset()
		game.start(canada)
		game.units = [1000 if wins else 1, 0, 0]
		game.countries[usa].units = [10, 0, 0]
		map.clear_motion()
		assert(game.dispatch_attack(usa))
		var arrival = int(game.operations.front().arrival)
		game.elapsed = arrival - 1
		map.visual_time = arrival - 0.1
		map.update_fronts(0.0)
		var front = map.fronts.values().front()
		assert(front.scale.is_equal_approx((map.relief.texture_axes if wins else map.map_axes()) / 1000.0))
		if wins:
			assert(front.get_parent() == map.relief.colors, "The front is rendered on the same surface as country borders")
			map.set_tilted(false)
			assert(front.get_parent() == map)
			map.set_tilted(true)
			assert(front.get_parent() == map.relief.colors, "Changing view preserves the current battle")
		var disputed: float = front.amount
		assert(disputed > 0.0 and disputed < 1.0 and not game.countries[usa].owned)
		assert(game.tick() and game.countries[usa].owned == wins)
		map.sync_ownership()
		map.update_fronts(0.4)
		assert(front.result == ("capture" if wins else "retreat"))
		assert(front.amount > disputed if wins else front.amount < disputed)
		map.update_fronts(1.2)
		assert(map.fronts.is_empty() and game.countries[usa].owned == wins)
	game.reports[str(usa)] = {"units": [1, 0, 0], "time": game.elapsed}
	map.clear_motion()
	game.remote_operations = [{"kind": "enemy", "from": canada, "target": usa,
		"start": game.elapsed - 1, "arrival": game.elapsed + 1, "source_color": "73aeef"}]
	map.update_fronts(0.0)
	var invasion = map.fronts.values().front()
	game.elapsed += 1
	game.remote_operations.clear()
	game.countries[usa].owned = false
	game.country_colors[str(usa)] = "73aeef"
	map.sync_ownership()
	assert(map.fronts.size() == 1 and invasion.result == "capture" and invasion.captured_by == "73aeef")
	# Remote snapshots can report a capture without showing the preceding attack.
	map.clear_motion()
	game.country_colors[str(usa)] = "ed876a"
	map.sync_ownership()
	assert(map.fronts.size() == 1 and map.fronts.values().front().captured_by == "ed876a")
	map.clear_motion()
	assert(map.fronts.is_empty())
	map.queue_free()
	await process_frame
	print("PASS: map geometry, selection, legacy saves, capture and retreat animations")
	quit()
