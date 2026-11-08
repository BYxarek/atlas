extends SceneTree

func _initialize() -> void:
	var Mods = load("res://src/mods.gd")
	Mods.network_boot_path = OS.get_environment("ATLAS_TEST_DIR").path_join("fixture_boot.json")
	assert(Mods.new().activate_network())
	var world = load("res://src/network_world.gd").new()
	world.random_state = 2026
	assert(world.add_faction("a", 0, "69dfbd"))
	assert(world.add_faction("b", 1, "73aeef"))
	var fixtures = []
	var actions = [["research", [0]], ["research", [1]], ["construct", [0, 0]], ["recruit", [3]], ["tick", [2]], ["attack", [1]], ["tick", [3]], ["tick", [4]], ["reset", []], ["bot_tick", [10]], ["bot_tick", [10]], ["bot_tick", [20]]]
	for action in actions:
		if action[0] == "reset":
			world = load("res://src/network_world.gd").new()
			world.random_state = 2026
			assert(world.add_faction("a", 0, "69dfbd") and world.add_faction("b", 1, "73aeef"))
		elif action[0] in ["tick", "bot_tick"]:
			for i in int(action[1][0]): world.tick(["a", "b"] if action[0] == "bot_tick" else [])
		else: assert(world.command("a", action[0], action[1]))
		var states = {}
		for slot in world.factions:
			var g = world.factions[slot]
			states[slot] = {"coins": g.coins, "units": g.units.duplicate(), "levels": g.levels.duplicate(), "mod_state": g.mod_state.duplicate(true), "income": g.income()}
		fixtures.append({"action": action, "random_state": world.random_state, "bot_profiles": world.bot_profiles.duplicate(true), "elapsed": world.elapsed, "owners": world.owners.duplicate(), "countries": world.countries.duplicate(true), "states": states})
	var file = FileAccess.open(OS.get_environment("ATLAS_TEST_DIR").path_join("fixtures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(fixtures))
	file.close()
	print("PASS: portable content fixtures")
	quit()
