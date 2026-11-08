extends SceneTree
const World = preload("res://src/network_world.gd")
var w = World.new()
var fixtures = []
var players = {"a": {"name": "A", "color": "69dfbd"}, "b": {"name": "B", "color": "73aeef"}}

func snapshot(action: Array) -> void:
	var states = {}
	for slot in w.factions:
		var view = w.view(slot, players).game
		var state = {}
		for key in ["home", "coins", "units", "levels", "mission", "reports", "operations", "conquests", "nukes", "victories", "defeats", "countries", "battles"]: state[key] = view[key]
		if w.countries.any(func(c): return c.has("microstate")): state.wars = view.wars
		states[slot] = state.duplicate(true)
	fixtures.append({"action": action, "elapsed": w.elapsed, "owners": w.owners.duplicate(), "states": states,
		"occupations": w.occupations.duplicate(true), "random_state": w.random_state, "bot_profiles": w.bot_profiles.duplicate(true)})

func _initialize() -> void:
	w.add_faction("a", 0, "69dfbd")
	w.add_faction("b", 1, "73aeef")
	snapshot(["init", w.random_state])
	for action in [["recruit", 0], ["business", 0, 0], ["upgrade", 1], ["spy", 1]]:
		w.command("a", action[0], action.slice(1))
		snapshot(["command", "a"] + action)
	for i in 6: w.tick([])
	snapshot(["tick", 6])
	w.command("a", "attack", [1])
	snapshot(["command", "a", "attack", 1])
	for i in 4: w.tick([])
	snapshot(["tick", 4])
	players.c = {"name": "C", "color": "edc16e"}
	w.add_faction("c", 2, "edc16e")
	snapshot(["add", "c", 2, "edc16e"])
	w.factions.a.nukes = 1
	w.factions.a.conquests = range(3, 13)
	snapshot(["nukes"])
	w.command("a", "nuke", [2])
	snapshot(["command", "a", "nuke", 2])
	for i in 3: w.tick([])
	snapshot(["tick", 3])
	for turn in 15:
		for i in 4: w.tick(["c"])
		snapshot(["bots", 4, "c"])
	w.remove_faction("c")
	players.erase("c")
	snapshot(["remove", "c"])
	w = World.new()
	w.random_state = 2026
	w.add_faction("a", 1, "69dfbd")
	w.add_faction("b", 3, "73aeef")
	snapshot(["reset", 2026])
	w.factions.a.units = [1000, 100, 100]
	snapshot(["army", "a", 1000, 100, 100])
	w.command("a", "attack", [3])
	snapshot(["command", "a", "attack", 3])
	for i in 4: w.tick([])
	snapshot(["tick", 4])
	for turn in 10:
		for i in 60: w.tick([])
		snapshot(["tick", 60])
	for seed_value in [17, 2026, 987654]:
		w = World.new()
		w.random_state = seed_value
		players = {}
		for i in 4:
			var slot = "bot%d" % i
			players[slot] = {"name": slot, "color": "69dfbd"}
			w.add_faction(slot, i * 37, "69dfbd")
		snapshot(["session", seed_value])
		for minute in 15:
			for i in 60: w.tick(players.keys())
			snapshot(["all_bots", 60])
			if minute == 7:
				var saved = JSON.parse_string(JSON.stringify(w.export_data()))
				var resumed = World.new()
				assert(resumed.restore_data(saved, players), "Long session must restore")
				w = resumed
				snapshot(["roundtrip"])
	var microstate_outcomes = {}
	for seed_value in [1, 5, 17, 2026]:
		w = World.new()
		w.random_state = seed_value
		players = {"a": {"name": "A", "color": "69dfbd"}, "b": {"name": "B", "color": "73aeef"}}
		w.add_faction("a", 1, "69dfbd")
		w.add_faction("b", 3, "73aeef")
		snapshot(["reset", seed_value])
		w.factions.a.units = [100000, 10000, 1000]
		snapshot(["army", "a", 100000, 10000, 1000])
		for name in ["Italy", "France"]:
			var target = -1
			for c in w.factions.a.atlas:
				if c.english == name: target = int(c.id)
			assert(w.command("a", "attack", [target]))
			snapshot(["command", "a", "attack", target])
			for i in 4: w.tick([])
			snapshot(["tick", 4])
		for id in World.Game.MICROSTATES:
			if w.countries[id].has("microstate"): microstate_outcomes[w.countries[id].microstate] = true
		var resumed = World.new()
		assert(resumed.restore_data(JSON.parse_string(JSON.stringify(w.export_data())), players))
		w = resumed
		snapshot(["roundtrip"])
	assert(microstate_outcomes.has("accepted") and microstate_outcomes.has("war"))
	var file = FileAccess.open("res://build/php-fixtures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(fixtures))
	file.close()
	quit()
