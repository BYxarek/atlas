extends SceneTree

const Game = preload("res://src/game.gd")
const PATH = "user://test_military.json"
var failures = 0
var checks = 0

func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + text)

func id_for(g: RefCounted, name: String) -> int:
	for country in g.atlas:
		if country.english == name: return int(country.id)
	return -1

func _initialize() -> void:
	var g = Game.new()
	check(g.military.source_year == 2026 and g.military.ranked_map_countries == 143, "Current GFP 2026 calibration covers 143 mapped countries")
	check(g.military.armies.size() == 176, "Every map country has a defined baseline")
	var second = Game.new()
	for i in g.countries.size():
		check(g.countries[i].units == second.countries[i].units and g.countries[i].units.all(func(n): return n >= 0), "Military baseline is deterministic and non-negative")
	var previous = INF
	for name in ["United States of America", "Russia", "China", "India", "South Korea", "France", "Japan", "United Kingdom", "Turkey", "Italy"]:
		var strength = g.power(g.countries[id_for(g, name)].units)
		check(strength < previous, "Top powers follow GFP 2026 order: " + name)
		previous = strength
	var usa = id_for(g, "United States of America")
	var russia = id_for(g, "Russia")
	check(g.power(g.countries[usa].units) >= g.power(g.countries[0].units) * 100, "Leading military is substantially stronger than unranked countries")
	check(g.countries[id_for(g, "Kazakhstan")].units[2] == 0 and g.countries[id_for(g, "Mongolia")].units[2] == 0, "Landlocked countries have no ocean navy")
	g.start(usa)
	check(g.units == Game.START_UNITS and g.coins == Game.START_COINS, "Strongest selected country starts with the same minimum army and treasury")
	var small = Game.new()
	small.start(0)
	check(small.units == g.units and small.coins == g.coins, "Small and strong countries have equal player starts")
	g.units[0] -= 3
	check(g.countries[usa].units[0] != g.units[0], "Player army does not alias country baseline")
	g.save_game(PATH)
	var restored = Game.new()
	check(restored.load_game(PATH) and restored.units == g.units and restored.countries == g.countries, "Current saves retain all army changes exactly")
	var legacy = Game.new()
	legacy.start(0)
	legacy.elapsed = 90
	legacy.units = [77, 10, 8]
	for i in legacy.countries.size():
		var random = RandomNumberGenerator.new()
		random.seed = i * 319 + 71
		random.randi_range(1, 5)
		legacy.countries[i].units = [random.randi_range(18, 70) + 3, random.randi_range(3, 20), random.randi_range(0, 12)]
	legacy.countries[2].owned = true
	legacy.countries[3].units = [1, 0, 0]
	legacy.conquests = [5]
	var old_owned_army = legacy.countries[2].units.duplicate()
	var old_lost_army = legacy.countries[5].units.duplicate()
	var old_attacking_army = legacy.countries[4].units.duplicate()
	legacy.operations = [{"kind": "enemy", "from": 4, "target": 0, "start": 90, "arrival": 95, "overseas": true}]
	legacy.warnings = [{"attacker": 4, "issued": 30, "deadline": 90, "low": 10, "high": 200, "status": "launched"},
		{"attacker": russia, "issued": 90, "deadline": 150, "low": 10, "high": 200, "status": "pending"}]
	legacy.save_game(PATH)
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	data.erase("military_balance")
	var file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(restored.load_game(PATH), "Legacy army distribution migrates successfully")
	check(restored.units == [77, 10, 8] and restored.countries[2].units == old_owned_army, "Migration preserves player and owned forces")
	check(restored.countries[3].units == [1, 0, 0] and restored.countries[5].units == old_lost_army, "Migration preserves damaged and previously conquered armies")
	check(restored.countries[4].units == old_attacking_army, "Migration does not change an army already invading the player")
	check(restored.pending_warning().is_empty(), "Outdated pending threats for recalibrated armies are cancelled")
	var expected = g.military.armies[russia].map(func(n): return int(n))
	expected[0] += 3
	check(restored.countries[russia].units == expected, "Untouched large-country force upgrades while keeping reinforcements")
	check(restored.save_game(PATH) == OK, "Migrated campaign saves the new balance version")
	var round_trip = Game.new()
	check(round_trip.load_game(PATH) and round_trip.countries == restored.countries, "Migration is not repeated on later loads")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
	print("%s: %d military checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
