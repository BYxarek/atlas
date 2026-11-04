extends SceneTree
const Game = preload("res://src/game.gd")
const World = preload("res://src/network_world.gd")
func _initialize() -> void:
	var g = Game.new()
	g.start(0)
	g.units = [1000, 100, 100]
	g.levels = [2, 3, 4]
	g.resolve_attack(1, true)
	assert(g.battles.size() == 1)
	var report = g.battles[0]
	assert(is_equal_approx(report.effective, g.power(report.attackers, report.attack_levels) * Game.B.naval_multiplier))
	assert(report.attack_losses[0] == report.attackers[0] - g.units[0])
	var resumed = Game.new()
	assert(resumed.restore_data(JSON.parse_string(JSON.stringify(g.export_data())), false))
	assert(resumed.battles == JSON.parse_string(JSON.stringify(g.battles)))
	var bad = g.export_data().duplicate(true)
	bad.battles[0].attack_losses = [-1, 0, 0]
	assert(not Game.new().restore_data(bad, false))
	var players = {"a": {"name": "A", "color": "69dfbd"}, "b": {"name": "B", "color": "73aeef"}}
	var profiles = []
	for seed_value in [17, 2026]:
		var w = World.new()
		w.random_state = seed_value
		w.add_faction("a", 0, "69dfbd")
		w.add_faction("b", 1, "73aeef")
		for i in 4: w.tick(["a", "b"])
		profiles.append(w.bot_profiles.duplicate(true))
		var restored = World.new()
		assert(restored.restore_data(JSON.parse_string(JSON.stringify(w.export_data())), players))
		assert(restored.bot_profiles == w.bot_profiles)
		for i in 40:
			w.tick(["a", "b"])
			restored.tick(["a", "b"])
		var expected = JSON.parse_string(JSON.stringify(w.export_data()))
		var actual = JSON.parse_string(JSON.stringify(restored.export_data()))
		assert(actual == expected, "Restoring must preserve all future decisions")
	assert(profiles[0] != profiles[1], "Same starting countries get different personalities in another session")
	print("PASS: battle reports, validation, session personalities and deterministic resume")
	quit()
