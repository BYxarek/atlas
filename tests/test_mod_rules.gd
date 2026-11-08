extends SceneTree

const Rules = preload("res://src/mod_rules.gd")
const Mods = preload("res://src/mods.gd")
const Package = preload("res://src/mod_package.gd")
const TEMP = "user://test_portable_rules"
var checks = 0
var failures = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func cleanup(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null: return
	for child in dir.get_directories(): cleanup(path.path_join(child))
	for child in dir.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	cleanup(TEMP)
	DirAccess.make_dir_recursive_absolute(TEMP + "/network")
	var base = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))
	var a = {"id": "economy", "changes": {"start_coins": 1000}}
	var b = {"id": "navy", "changes": {"naval_cost": 35}}
	var combined = Rules.compose([a, b], base)
	check(combined.error.is_empty() and combined.balance.start_coins == 1000 and combined.balance.naval_cost == 35, "Disjoint patches compose")
	b.changes.start_coins = 500
	combined = Rules.compose([a, b], base)
	check(combined.balance.start_coins == 500 and combined.sources.start_coins == "navy" and combined.conflicts.size() == 1, "Conflicts retain source and winning value")
	check(not Rules.compose([{"id": "bad", "changes": {"typo": 1}}], base).error.is_empty(), "Unknown patch key rejected")
	var doc = Rules.numbers(JSON.parse_string(FileAccess.get_file_as_string("res://examples/frontier/mod.json")))
	var compiled = Rules.compose([doc], base)
	check(compiled.error.is_empty() and compiled.balance.start_units.size() == 4, "Compile new content and custom map")
	var bad = doc.duplicate(true)
	bad.content.technologies[0].requires = ["artillery"]
	check(not Rules.compose([bad], base).error.is_empty(), "Research cycle rejected")
	bad = doc.duplicate(true)
	bad.content.events[0].actions[0].type = "execute"
	check(not Rules.compose([bad], base).error.is_empty(), "Code actions rejected")
	bad = doc.duplicate(true)
	bad.content.map[0].neighbors = []
	check(not Rules.compose([bad], base).error.is_empty(), "Nonreciprocal borders rejected")
	bad = doc.duplicate(true)
	bad.content.events[0].actions.resize(17)
	check(not Rules.compose([bad], base).error.is_empty(), "Action budget enforced at validation")
	var pack = PCKPacker.new()
	check(pack.pck_start(TEMP + "/empty.pck") == OK and pack.flush() == OK, "Build empty native payload")
	check(Package.create("res://examples/frontier/mod.json", TEMP + "/empty.pck", TEMP + "/network/frontier.atlasmod") == OK, "Package portable content")
	var manager = Mods.new()
	manager.directory = TEMP + "/solo"
	manager.config_path = TEMP + "/solo.cfg"
	check(manager.install(TEMP + "/network/frontier.atlasmod").is_empty(), "Install portable solo package")
	var manifest_path = TEMP + "/solo/frontier/mod.json"
	var approved_hash = manager.read_manifest(manifest_path).sha256
	var changed_manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	changed_manifest.changes.start_coins += 1
	var changed_file = FileAccess.open(manifest_path, FileAccess.WRITE)
	changed_file.store_string(JSON.stringify(changed_manifest))
	changed_file.close()
	check(manager.read_manifest(manifest_path).sha256 != approved_hash, "Portable JSON changes invalidate solo approval and save identity")
	var old_env = OS.get_environment("ATLAS_MODS_DIR")
	OS.set_environment("ATLAS_MODS_DIR", TEMP + "/network")
	var old_boot = Mods.network_boot_path
	Mods.network_boot_path = TEMP + "/boot.json"
	check(Mods.new().activate_network(), "Activate before loading simulation")
	var Game = load("res://src/game.gd")
	check(Game.COUNTRY_COUNT == 3 and Game.UNIT_COUNT == 4, "Map and unit limits follow content")
	var g = Game.new()
	g.start(0)
	check(g.coins == 600 and g.countries[2].owned and g.mod_state.fired.has("welcome"), "Scenario and one-time starting event")
	Game.Runtime.emit_event(g, "start", 0)
	check(g.coins == 600, "Once event cannot repeat")
	check(not g.recruit(3), "New unit locked by technology")
	check(Game.Runtime.research(g, 0) and Game.Runtime.research(g, 1), "Research dependencies unlock in order")
	check(g.mod_state.researches == ["metallurgy", "artillery"] and g.mod_state.flags.scientist == true, "Research and flags persisted")
	check(g.recruit(3) and g.units[3] == 2, "New troop can recruit")
	check(Game.Runtime.construct(g, 0, 0) and g.countries[0].structures.forge == 1 and g.income() == 6, "New building contributes income")
	check(is_equal_approx(g.power(g.units, g.levels), 93.5), "Custom research and units contribute correct combat strength")
	g.tick()
	g.tick()
	check(g.units[3] == 4 and g.mod_state.fired.has("supply"), "Tick reward executes once")
	var snapshot = g.export_data().duplicate(true)
	var restored = Game.new()
	check(restored.restore_data(snapshot, false) and restored.mod_state == g.mod_state and restored.countries[0].structures.forge == 1, "Content state survives save/load")
	var original = restored.coins
	snapshot.mod_state.random_state = 0
	check(not restored.restore_data(snapshot) and restored.coins == original, "Invalid mod state rejected before mutation")
	var Media = load("res://src/mod_media.gd")
	check(Media.flag(0) != null and Media.flag(0).get_width() == 1, "Network flag decoded as data")
	check(Media.sound("victory") is AudioStreamWAV, "Network sound decoded as data")
	var world = load("res://src/network_world.gd").new()
	check(world.add_faction("a", 0, "69dfbd") and world.owners[2] == "a", "Network scenario assigns initial territories")
	check(world.add_faction("b", 1, "73aeef"), "Second faction starts without overlap")
	check(world.command("a", "research", [0]) and world.command("a", "construct", [0, 0]), "Network commands reach portable content")
	world.tick([])
	world.tick([])
	check(world.factions.a.units.size() == 4 and world.view("a", {"a": {"color": "69dfbd", "name": "A"}, "b": {"color": "73aeef", "name": "B"}}).game.countries[1].units.size() == 4, "Filtered views preserve dynamic army width")
	var saved = JSON.parse_string(JSON.stringify(world.export_data()))
	var resumed = load("res://src/network_world.gd").new()
	check(resumed.restore_data(saved, {"a": {}, "b": {}}), "Network save validates buildings, research and events")
	var scene = load("res://main.tscn").instantiate()
	scene.settings_path = TEMP + "/settings.cfg"
	scene.store = scene.SaveStore.new(TEMP + "/saves")
	root.add_child(scene)
	await process_frame
	scene.game.start(0)
	scene.selected = 0
	scene.open_card("army")
	check(scene.card_body.find_children("*", "Button", true, false).any(func(button): return "40" in button.text), "New troop recruitment shown in UI")
	scene.open_card("economy")
	check(scene.card_body.find_children("*", "Button", true, false).any(func(button): return "25" in button.text), "Mod buildings shown in economy")
	scene.mod_tools.show_tools()
	check(scene.page == "mod_tools" and scene.game.paused, "Rule inspector opens and pauses campaign")
	var previous_campaign = scene.game.campaign_id
	scene.mod_tools.test_campaign()
	check(scene.page == "game" and scene.game.campaign_id != previous_campaign and scene.store.list_saves().size() == 2, "Quick test preserves prior campaign and creates a separate save")
	for player in scene.sound.players + scene.sound.loops.values(): player.stop()
	await create_timer(0.2).timeout
	scene.queue_free()
	await process_frame
	await create_timer(1.0).timeout
	var objective = Engine.get_meta("atlas_content").duplicate(true)
	objective.victory = {"type": "hold", "countries": [0, 2], "seconds": 2}
	Engine.set_meta("atlas_content", objective)
	Game.Runtime.tick(g)
	g.elapsed += 2
	Game.Runtime.tick(g)
	check(g.finished and g.mod_state.result == "win", "Hold objective completes")
	Mods.network_boot_path = old_boot
	OS.set_environment("ATLAS_MODS_DIR", old_env)
	cleanup(TEMP)
	print("PASS: %d portable rules checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
