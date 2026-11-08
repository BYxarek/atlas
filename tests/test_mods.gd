extends SceneTree

const Mods = preload("res://src/mods.gd")
const TEMP = "user://test_mod_system"
var checks = 0
var failures = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func write_json(path: String, data: Variant) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

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
	DirAccess.make_dir_recursive_absolute(TEMP + "/source")
	var original = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))
	original.start_coins = 12345
	write_json(TEMP + "/balance.json", original)
	var pack = PCKPacker.new()
	check(pack.pck_start(TEMP + "/source/content.pck") == OK, "Create pack")
	check(pack.add_file("res://assets/balance.json", TEMP + "/balance.json") == OK, "Add balance override")
	var source = "res://src/game.gd"
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): source = args[0]
	var script_file = FileAccess.open(TEMP + "/game.gd", FileAccess.WRITE)
	var code = FileAccess.get_file_as_string(source)
	check(code.contains("coins = START_COINS"), "Read mod source script")
	script_file.store_string(code.replace("coins = START_COINS", "coins = START_COINS + 7"))
	script_file.close()
	check(pack.add_file("res://src/game.gd", TEMP + "/game.gd") == OK, "Add logic override")
	check(pack.add_file_removal("res://src/game.gd.remap") == OK, "Override compiled export remapping")
	check(pack.flush() == OK, "Flush pack")
	var manifest = {"api": 1, "id": "test-mod", "name": "Test", "version": "1", "game_version": "0.3.0", "requires": [], "conflicts": []}
	write_json(TEMP + "/source/mod.json", manifest)
	var mods = Mods.new()
	mods.directory = TEMP + "/installed"
	mods.config_path = TEMP + "/mods.cfg"
	mods.marker_path = TEMP + "/starting"
	check(not mods.valid_id("../escape") and not mods.valid_id("C:\\escape") and not mods.valid_id(1), "Reject unsafe IDs")
	manifest.id = "../escape"
	write_json(TEMP + "/source/bad.json", manifest)
	check(mods.read_manifest(TEMP + "/source/bad.json").is_empty(), "Reject traversal manifest")
	manifest.id = "test-mod"
	check(mods.install(TEMP + "/source/mod.json").is_empty(), "Install package")
	check(not mods.install(TEMP + "/source/mod.json").is_empty(), "Never overwrite installed package")
	check(mods.installed.size() == 1, "Discover installed mod")
	check(not mods.validate(["absent"]).is_empty(), "Reject missing mod")
	check(not mods.validate(["test-mod", "test-mod"]).is_empty(), "Reject duplicates")
	mods.installed[0].requires = ["base"]
	check(not mods.validate(["test-mod"]).is_empty(), "Reject missing dependency")
	var base = mods.installed[0].duplicate(true)
	base.id = "base"
	base.requires = []
	mods.installed.append(base)
	check(mods.validate(["base", "test-mod"]).is_empty(), "Dependency must load first")
	check(not mods.validate(["test-mod", "base"]).is_empty(), "Reject dependency after dependent")
	mods.installed[0].conflicts = ["base"]
	check(not mods.validate(["base", "test-mod"]).is_empty(), "Reject conflicts")
	mods.scan()
	mods.installed[0].game_version = "wrong"
	check(not mods.validate(["test-mod"]).is_empty(), "Reject game version mismatch")
	mods.scan()
	check(mods.save_selection(["test-mod"]).is_empty(), "Persist approved selection")
	var approved = ConfigFile.new()
	approved.load(mods.config_path)
	approved.set_value("hashes", "test-mod", "wrong")
	approved.save(mods.config_path)
	check(mods.activate() and Engine.get_meta("atlas_mods") == "" and Engine.has_meta("atlas_mod_error"), "Changed pack requires approval; vanilla fallback")
	check(mods.save_selection(["test-mod"]).is_empty(), "Save same selection")
	check(mods.activate() and Engine.get_meta("atlas_mods") == "", "Unrelated order/settings changes do not approve changed code")
	check(mods.save_selection([]).is_empty(), "Disable changed pack")
	check(mods.save_selection(["test-mod"]).is_empty(), "Reapprove pack")
	check(mods.activate() and not str(Engine.get_meta("atlas_mods")).is_empty(), "Activate approved pack")
	check(mods.activate() and Engine.get_meta("atlas_mods") == "", "Interrupted startup activates recovery")
	DirAccess.remove_absolute(mods.marker_path)
	check(mods.activate() and not str(Engine.get_meta("atlas_mods")).is_empty(), "Recovery can retry selected set")
	DirAccess.remove_absolute(mods.marker_path)
	# Dynamic loading is essential: preloading Game would cache the original balance.
	var game_script = load("res://src/game.gd")
	var game = game_script.new()
	game.start(0)
	check(game.coins == 12352, "PCK overrides simulation data AND code before static initialization")
	var store = load("res://src/saves.gd").new()
	check(store.directory.begins_with("user://mod_saves/"), "Modded saves isolated from vanilla")
	var snapshot = game.export_data().duplicate(true)
	check(snapshot.mods == Engine.get_meta("atlas_mods"), "Save records exact profile")
	check(game.save_game(TEMP + "/campaign.json") == OK and game.load_game(TEMP + "/campaign.json"), "Modded save round trip")
	var network = load("res://src/network_session.gd").new()
	check(network.join_room("127.0.0.1", "Test") == ERR_UNAVAILABLE, "LAN guarded with active mods")
	check(network.join_php("https://example.com", "Test") == ERR_UNAVAILABLE, "PHP guarded with active mods")
	check(network.join_directory("wss://example.com", "Test") == ERR_UNAVAILABLE, "VPS guarded with active mods")
	network.free()
	Engine.set_meta("atlas_mods", "")
	var previous = game.coins
	check(not game.restore_data(snapshot) and game.coins == previous, "Reject another profile before mutation")
	check(load("res://src/saves.gd").new().directory == "user://saves", "Vanilla save directory preserved")
	var scene = load("res://main.tscn").instantiate()
	scene.store = load("res://src/saves.gd").new(TEMP + "/saves")
	scene.settings_path = TEMP + "/settings.cfg"
	root.add_child(scene)
	await process_frame
	scene.mod_menu.manager.directory = mods.directory
	scene.mod_menu.manager.config_path = mods.config_path
	scene.mod_menu.show_menu()
	check(scene.page == "mods" and scene.game.paused, "Mod manager opens and pauses simulation")
	check(scene.mod_menu.manager.selected == ["test-mod"], "UI reads persisted selection")
	manifest.id = "second-mod"
	write_json(TEMP + "/source/second.json", manifest)
	check(scene.mod_menu.manager.install(TEMP + "/source/second.json").is_empty(), "Install second mod for order UI")
	scene.mod_menu.commit(["test-mod", "second-mod"])
	var moves = scene.menu_body.find_children("*", "Button", true, false).filter(func(b): return b.text == scene.L.text("Ниже") and not b.disabled)
	check(moves.size() == 1, "Only first mod can move down")
	if not moves.is_empty(): moves[0].press()
	check(scene.mod_menu.manager.selected == ["second-mod", "test-mod"], "Move button persists new load order")
	scene.mod_menu.commit([])
	check(scene.mod_menu.manager.selected.is_empty(), "Disable all persists")
	scene.network.active = true
	scene.network.mods.receive_offer([{"api": 1, "id": "room-mod", "name": "Room mod", "version": "1", "game_version": "0.3.0", "size": 100, "sha256": "a".repeat(64), "pck_sha256": "b".repeat(64)}])
	check(scene.page == "mods_download" and scene.network.my_slot.is_empty(), "Room requirements open consent screen before seat allocation")
	check(not scene.network.mods.downloading, "No download without consent")
	scene.menu_body.get_children().back().press()
	check(scene.page == "menu" and not scene.network.active, "Cancel mod offer returns to menu without connecting")
	await create_timer(0.35).timeout
	for player in scene.sound.players + scene.sound.loops.values(): player.stop()
	await create_timer(0.2).timeout
	scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	cleanup(TEMP)
	print("PASS: %d mod checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
