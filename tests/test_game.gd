extends SceneTree

const Game = preload("res://src/game.gd")
var checks = 0
var failures = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error("FAIL: " + message)
		failures += 1

func _initialize() -> void:
	var g = Game.new()
	check(g.countries.size() == 176, "World has 176 countries")
	check(g.income() == 0 and not g.can_act(), "No income before campaign starts")
	for c in g.countries:
		check(c.businesses.size() >= 1 and c.businesses.size() <= 5, "1–5 businesses per country")
		check(c.businesses.all(func(n): return n == 1), "Every business starts at 1 coin per second")
	g.start(0)
	check(g.home == 0 and g.owned_count() == 1, "Country selection starts campaign")
	var old_coins = g.coins
	var old_income = g.income()
	g.tick()
	check(g.coins == old_coins + old_income, "One second pays exact income")
	var cost = g.business_cost(0, 0)
	check(g.upgrade_business(0, 0), "Owned business can be upgraded")
	check(g.income() == old_income + 1 and g.coins == old_coins + old_income - cost, "Upgrade adds exactly 1 coin per second")
	check(not g.upgrade_business(1, 0), "Cannot upgrade foreign business")
	check(not g.upgrade_business(-1, 0), "Invalid country rejected")
	check(not g.recruit(-1) and not g.upgrade_army(3), "Invalid army kind rejected")
	for i in 3:
		g.coins = 1000
		var before = g.units[i]
		check(g.recruit(i) and g.units[i] == before + [10, 3, 2][i], "All branches recruit")
		check(g.upgrade_army(i) and g.levels[i] == 2, "All branches upgrade")
		var branch = [0, 0, 0]
		branch[i] = 4
		check(is_equal_approx(g.power(branch, g.levels), 4 * Game.UNIT_WEIGHT[i] * 1.25), "Technology raises branch strength by 25 percent")
	g.coins = 0
	check(not g.recruit(0) and not g.spy(1) and not g.upgrade_business(0, 0), "No overspending")
	g.coins = 200
	check(g.spy(1) and not g.spy(2), "Only one concurrent spy")
	for i in 5:
		g.tick()
	check(g.reports.is_empty(), "No report before arrival")
	g.paused = true
	var time_before = g.elapsed
	var balance_before = g.coins
	g.tick()
	check(g.elapsed == time_before and g.coins == balance_before, "Pause stops time and economy")
	check(not g.recruit(0) and not g.upgrade_army(0) and not g.upgrade_business(0, 0), "Pause blocks actions")
	g.paused = false
	g.tick()
	check(g.reports.has("1") and g.mission.is_empty(), "Spy returns after six active seconds")
	var report_units = g.reports["1"].units.duplicate()
	g.countries[1].units[0] += 20
	check(g.reports["1"].units == report_units, "Intelligence is a snapshot")
	g.units = [0, 0, 0]
	check(g.attack(1).is_empty(), "Empty army cannot attack")
	var overseas = -1
	for id in g.countries.size():
		if id != 0 and not g.border(id):
			overseas = id
			break
	g.units = [500, 50, 3]
	check(g.attack(overseas).is_empty(), "Overseas attack requires four ships")
	g.units = [500, 50, 4]
	g.coins = 1000
	old_income = g.income()
	var result = g.attack(overseas)
	check(result.victory and result.overseas and g.countries[overseas].owned, "Naval victory captures country")
	check(g.income() > old_income and g.owned_count() == 2, "Captured businesses pay income")
	check(result.losses[0] > 0 and g.units[0] < 500, "Victory still has losses")
	check(g.attack(overseas).is_empty(), "Cannot attack owned country")
	var target = 1 if overseas != 1 else 2
	g.units = [1, 0, 4]
	g.countries[target].units = [1000, 100, 100]
	result = g.attack(target)
	check(not result.victory and not g.countries[target].owned, "Losing cannot capture country")
	check(g.units.all(func(n): return n >= 0), "Losses cannot make armies negative")
	var land_target = -1
	for id in g.countries.size():
		if not g.countries[id].owned and g.border(id):
			land_target = id
			break
	check(land_target >= 0, "Captured territory unlocks land neighbors")
	if land_target >= 0:
		g.units = [5000, 1000, 0]
		g.coins = 1000
		check(g.attack_cost(land_target) == 25, "Land operation costs 25")
		var land_result = g.attack(land_target)
		check(land_result.victory and not land_result.overseas, "Land operation does not require a navy")
	var path = "user://test_campaign.json"
	g.coins = 1234
	check(g.spy(target), "Active spy can be saved")
	check(g.save_game(path) == OK, "Save succeeds")
	var restored = Game.new()
	check(restored.load_game(path), "Save round trip succeeds")
	check(restored.coins == g.coins and restored.units == g.units and restored.countries == g.countries, "Saved economy and territory preserved")
	check(restored.mission == g.mission and restored.reports == g.reports, "Missions and reports preserved")
	check(g.save_game(path) == OK and FileAccess.file_exists(path + ".bak"), "Replacing a save creates a backup")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	for corrupt in ["invalid json", "{}", "[]", "null"]:
		write_text(path, corrupt)
		check(not restored.load_game(path) and restored.coins == g.coins, "Corrupt save rejected without changing state")
	for entry in [["units", [-1, 1, 1]], ["home", -1], ["countries", []], ["mission", {"target": 999, "arrival": 2}], ["reports", {"999": {"units": [1, 2, 3], "time": 1}}], ["elapsed", 1.5], ["levels", [0, 1, 1]]]:
		var corrupt = saved.duplicate(true)
		corrupt[entry[0]] = entry[1]
		write_text(path, JSON.stringify(corrupt))
		check(not restored.load_game(path), "Invalid save fields rejected: " + entry[0])
	var victory = Game.new()
	victory.start(0)
	for c in victory.countries:
		c.owned = true
	victory.countries[1].owned = false
	victory.units = [10000, 10000, 10000]
	victory.coins = 10000
	check(victory.attack(1).victory and victory.finished, "Capturing last country wins game")
	check(not victory.can_act(), "Completed game stops simulation")
	var frontier = Game.new()
	var russia = 0
	for c in frontier.atlas:
		if c.english == "Russia":
			russia = int(c.id)
	frontier.start(russia)
	for c in frontier.countries:
		c.units = [2000, 100, 100]
	frontier.units = [4, 0, 0]
	frontier.elapsed = 44
	frontier.coins = 100
	frontier.tick()
	check(not frontier.has_operation("enemy"), "One-country empires cannot be invaded")
	for i in 600: frontier.tick()
	check(frontier.owned_count() == 1 and not frontier.finished, "Last country remains safe over a long simulation")
	check(frontier.warnings.is_empty(), "Protected empires receive no invasion threats")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("%s: %d simulation checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func write_text(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
