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
		for key in ["home", "coins", "units", "levels", "mission", "reports", "operations", "conquests", "nukes", "victories", "defeats", "countries"]: state[key] = view[key]
		states[slot] = state.duplicate(true)
	fixtures.append({"action": action, "elapsed": w.elapsed, "owners": w.owners.duplicate(), "states": states})

func _initialize() -> void:
	w.add_faction("a", 0, "69dfbd")
	w.add_faction("b", 1, "73aeef")
	snapshot(["init"])
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
	var file = FileAccess.open("res://build/php-fixtures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(fixtures))
	file.close()
	quit()
