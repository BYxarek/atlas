extends SceneTree

const Game = preload("res://src/game.gd")
const Store = preload("res://src/saves.gd")
var checks = 0
var failures = 0
const PATH = "user://test_features.json"
const DIRECTORY = "user://test_feature_saves"

func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + text)

func advance(g: RefCounted, seconds: int) -> void:
	for i in seconds: g.tick()

func _initialize() -> void:
	var g = Game.new()
	g.start(0)
	g.coins = 10000
	g.units = [10000, 1000, 1000]
	var cost = g.attack_cost(1)
	check(g.dispatch_attack(1), "Army can be dispatched")
	check(g.coins == 10000 - cost and not g.countries[1].owned, "Launch reserves cost, not territory")
	check(not g.dispatch_attack(2), "One outgoing army operation at a time")
	advance(g, 3)
	check(not g.countries[1].owned, "No capture before army arrival")
	g.paused = true
	advance(g, 10)
	check(g.elapsed == 3 and g.operations.size() == 1, "Pause freezes movement and arrival")
	g.paused = false
	advance(g, 1)
	check(g.countries[1].owned and not g.has_operation("attack"), "Capture resolves at arrival")
	check(g.coins == 10000 - cost + 4 * g.countries[0].businesses.size() + 30, "Operation charged once")
	for id in range(2, 11):
		g.units = [10000, 10000, 10000]
		check(g.attack(id).victory, "Unique conquest succeeds")
	check(g.conquests.size() == 10 and g.nukes == 1, "Ten unique conquests award one nuclear charge")
	g.countries[1].owned = false
	check(g.attack(1).victory and g.nukes == 1 and g.conquests.size() == 10, "Recapture cannot farm nuclear charges")
	g.countries[11].units = [11, 7, 3]
	check(not g.nuclear_strike(0), "Nuclear weapons cannot target owned territory")
	check(g.nuclear_strike(11) and g.nukes == 0, "Nuclear charge spent at launch")
	check(not g.nuclear_strike(12), "Cannot spend missing charge")
	advance(g, 2)
	check(g.countries[11].units == [11, 7, 3], "No nuclear damage before arrival")
	g.player_color = Color("b697ef")
	check(g.save_game(PATH) == OK, "In-flight operation saves")
	var restored = Game.new()
	check(restored.load_game(PATH) and restored.has_operation("nuke"), "Nuclear flight restores")
	check(restored.player_color == g.player_color and restored.nukes == 0 and restored.conquests == g.conquests, "Color, nuclear inventory and milestones restore")
	advance(restored, 1)
	check(restored.countries[11].units == [5, 3, 1], "Nuclear strike halves every branch, rounding remainder down")
	check(not restored.countries[11].owned, "Nuclear strike does not conquer country")
	var low = defense_game(1)
	var high = defense_game(5)
	check(low.launch_enemy_attack(1, 0) and high.launch_enemy_attack(1, 0), "Foreign armies can attack the player")
	advance(low, 5)
	advance(high, 5)
	check(not low.countries[0].owned and low.owned_count() == 1 and low.income() == low.countries[2].businesses.size(), "Losing defense removes captured territory and its income")
	check(not high.finished and high.countries[0].owned and high.victories == 1, "Higher technology wins defense with the same troop counts")
	check(low.defeats == 1 and low.can_act(), "Surviving last country can continue playing under protection")
	check(low.countries[0].units[0] + low.countries[1].units[0] <= 80, "Conquering enemy splits survivors instead of duplicating its army")
	check(low.save_game(PATH) == OK and restored.load_game(PATH) and restored.owned_count() == 1, "A surviving last-country campaign restores")
	var partial = defense_game(1)
	partial.countries[2].owned = true
	partial.launch_enemy_attack(1, 0)
	advance(partial, 5)
	check(not partial.finished and partial.can_act() and partial.owned_count() == 1, "Losing original homeland does not end a surviving empire")
	check(partial.save_game(PATH) == OK and restored.load_game(PATH), "Save can restore a lost original homeland")
	var cancel = defense_game(1)
	cancel.launch_enemy_attack(1, 0)
	cancel.countries[1].owned = true
	advance(cancel, 5)
	check(cancel.countries[0].owned, "Capturing attacker cancels its invasion")
	var store = Store.new(DIRECTORY)
	clear_store()
	check(store.autosave(g) == OK and store.list_saves().size() == 1, "Campaign has its own automatic slot")
	g.coins += 5
	check(store.autosave(g) == OK and store.list_saves().size() == 1, "Autosave updates same slot")
	check(FileAccess.file_exists(DIRECTORY.path_join("auto_" + g.campaign_id + ".json.bak")), "Autosave preserves previous backup")
	check(store.manual_save(g) == OK and store.manual_save(g) == OK and store.list_saves().size() == 3, "Manual snapshots are distinct")
	var second_campaign = Game.new()
	second_campaign.start(1)
	check(store.autosave(second_campaign) == OK and store.list_saves().size() == 4, "New campaign does not overwrite earlier autosaves")
	var f = FileAccess.open(DIRECTORY.path_join("broken.json"), FileAccess.WRITE)
	f.store_string("invalid")
	f.close()
	check(store.list_saves().filter(func(entry): return not entry.valid).size() == 1, "Save browser safely lists corrupt files")
	g.save_game(PATH)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for entry in [["player_color", "invalid"], ["campaign_id", "../../escape"], ["nukes", 9], ["conquests", [1, 1]], ["operations", [{"kind": "attack", "from": 999, "target": 1, "start": 0, "arrival": 5, "overseas": true}]]]:
		var broken = saved.duplicate(true)
		broken[entry[0]] = entry[1]
		f = FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify(broken))
		f.close()
		check(not restored.load_game(PATH), "Invalid extended save rejected: " + entry[0])
	var old = saved.duplicate(true)
	old.version = 1
	for key in ["player_color", "campaign_id", "nukes", "conquests", "operations", "victories", "defeats", "warnings", "notification_serial", "notifications_seen"]: old.erase(key)
	f = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	check(restored.load_game(PATH) and restored.player_color == Color("69dfbd"), "Legacy v1 saves remain loadable")
	clear_store()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
	print("%s: %d feature checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func defense_game(level: int) -> RefCounted:
	var g = Game.new()
	g.start(0)
	g.countries[2].owned = true
	g.elapsed = 60
	g.warnings = [{"attacker": 1, "issued": 0, "deadline": 60, "low": 80, "high": 240, "status": "pending"}]
	g.units = [35, 8, 4]
	g.levels = [level, level, level]
	g.countries[1].units = [80, 20, 8]
	return g

func clear_store() -> void:
	var directory = DirAccess.open(DIRECTORY)
	if directory:
		for file in directory.get_files(): DirAccess.remove_absolute(DIRECTORY.path_join(file))
		DirAccess.remove_absolute(DIRECTORY)
