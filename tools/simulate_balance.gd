extends SceneTree

const World = preload("res://src/network_world.gd")

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	var sessions = int(args[0]) if args.size() > 0 else 3
	var seconds = int(args[1]) if args.size() > 1 else 900
	assert(sessions > 0 and sessions <= 100 and seconds > 0 and seconds <= 86400)
	var results = []
	for run in sessions:
		var w = World.new()
		w.random_state = 2026 + run * 7919
		var slots = []
		var homes = {}
		for i in 6:
			var slot = "bot%d" % i
			var home = (i * 29 + run * 11) % 176
			slots.append(slot)
			homes[slot] = home
			assert(w.add_faction(slot, home, "69dfbd"))
		var first_conquest = -1
		var peak = {}
		var lost_ground = {}
		var previous_counts = {}
		var recovered = {}
		for second in seconds:
			w.tick(slots)
			for slot in slots:
				var count = w.owners.count(slot)
				if first_conquest < 0 and count > 1: first_conquest = w.elapsed
				if count < int(previous_counts.get(slot, 1)): lost_ground[slot] = true
				if lost_ground.has(slot) and count > int(previous_counts.get(slot, 1)): recovered[slot] = true
				previous_counts[slot] = count
				peak[slot] = maxi(count, int(peak.get(slot, 1)))
			if w.owners.count(w.owners[0]) == 176: break
		var factions = []
		for slot in slots:
			var g = w.factions[slot]
			factions.append({"slot": slot, "home": homes[slot], "profile": w.bot_profiles.get(slot, {}),
				"territories": w.owners.count(slot), "peak": peak[slot], "regained_after_loss": recovered.get(slot, false),
				"army": g.units, "technology": g.levels, "coins": g.coins, "victories": g.victories, "defeats": g.defeats})
		results.append({"seed": 2026 + run * 7919, "elapsed": w.elapsed, "finished": w.owners.count(w.owners[0]) == 176,
			"first_conquest": first_conquest, "factions": factions})
	var file = FileAccess.open("res://build/balance-report.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("PASS: %d balance sessions; build/balance-report.json" % sessions)
	quit()
