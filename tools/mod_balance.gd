extends SceneTree
## Load packages before loading the actual game simulation.

func _initialize() -> void:
	var folder = OS.get_environment("ATLAS_BALANCE_DIR")
	var Mods = load("res://src/mods.gd")
	Mods.network_boot_path = folder.path_join("unused_boot.json")
	if not Mods.new().activate_network():
		printerr(Engine.get_meta("atlas_mod_error", "Cannot load mod profile"))
		quit(1)
		return
	var Game = load("res://src/game.gd")
	var World = load("res://src/network_world.gd")
	var plan = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("plan.json")))
	var results = []
	for run in int(plan.sessions):
		var world = World.new()
		world.random_state = (int(plan.seed) + run * 7919) % 2147483646 + 1
		var slots = []
		var homes = []
		for offset in Game.COUNTRY_COUNT:
			var home = (offset + run) % Game.COUNTRY_COUNT
			var slot = "bot%d" % slots.size()
			if not world.add_faction(slot, home, "69dfbd"): continue
			slots.append(slot)
			homes.append(home)
			if slots.size() == int(plan.bots): break
		if slots.size() < int(plan.bots):
			printerr("Not enough nonoverlapping scenario starts for bots")
			quit(1)
			return
		var income = {}
		var purchases = {}
		var initial = {}
		var first_expansion = {}
		var timeline = []
		for slot in slots:
			purchases[slot] = range(Game.UNIT_COUNT).map(func(_i): return 0)
			initial[slot] = world.owners.count(slot)
			world.factions[slot].units_recruited.connect(func(kind, amount): purchases[slot][kind] += amount)
		for second in int(plan.seconds):
			world.tick(slots)
			var frame = []
			for slot in slots:
				world.project(slot)
				var g = world.factions[slot]
				income[slot] = float(income.get(slot, 0)) + g.income()
				if not first_expansion.has(slot) and g.owned_count() > initial[slot]: first_expansion[slot] = world.elapsed
				if world.elapsed % 10 == 0 or second == int(plan.seconds) - 1: frame.append({"slot": slot, "territories": g.owned_count(), "coins": g.coins, "income": g.income(), "power": g.power(g.units, g.levels), "researches": g.mod_state.get("researches", []).size()})
			if not frame.is_empty(): timeline.append({"elapsed": world.elapsed, "factions": frame})
			if slots.all(func(slot): return world.factions[slot].finished): break
		var factions = []
		for i in slots.size():
			var slot = slots[i]
			world.project(slot)
			var g = world.factions[slot]
			factions.append({"home": homes[i], "recruited_units": purchases[slot], "first_expansion": first_expansion.get(slot, -1), "won": g.controls_world(), "alive": g.owned_count() > 0, "territories": g.owned_count(), "coins": g.coins, "mean_income": float(income.get(slot, 0)) / maxi(1, world.elapsed), "units": g.units, "levels": g.levels, "researches": g.mod_state.get("researches", []), "victories": g.victories, "defeats": g.defeats})
		results.append({"seed": (int(plan.seed) + run * 7919) % 2147483646 + 1, "elapsed": world.elapsed, "timeline": timeline, "factions": factions})
	var output = FileAccess.open(folder.path_join("results.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"profile": Engine.get_meta("atlas_network_profile", []), "units": Game.Runtime.unit_ids(), "results": results}))
	output.close()
	print("PASS: ", results.size(), " actual mod balance sessions")
	quit()
