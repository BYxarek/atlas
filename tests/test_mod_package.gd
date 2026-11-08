extends SceneTree

const Package = preload("res://src/mod_package.gd")
const Mods = preload("res://src/mods.gd")
const TEMP = "user://test_mod_package"
var checks = 0
var failures = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func write_json(path: String, value: Variant) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func cleanup(path: String) -> void:
	var folder = DirAccess.open(path)
	if folder == null: return
	for child in folder.get_directories(): cleanup(path.path_join(child))
	for child in folder.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func _initialize() -> void:
	cleanup(TEMP)
	DirAccess.make_dir_recursive_absolute(TEMP)
	var base = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))
	var balance = base.duplicate(true)
	balance.start_coins = 1000
	check(Package.balance_valid(balance, base), "Shared balance accepted")
	for key in ["nuclear_threshold", "spy_seconds", "bot_seconds", "unit_weight"]:
		var bad = balance.duplicate(true)
		bad[key] = [0, 1, 1] if key == "unit_weight" else 0
		check(not Package.balance_valid(bad, base), "Reject zero divisor or invalid weight: " + key)
	var bad = balance.duplicate(true)
	bad.surprise_chance = 101
	check(not Package.balance_valid(bad, base), "Reject invalid probability")
	bad = balance.duplicate(true)
	bad.start_coins = "1000"
	check(not Package.balance_valid(bad, base), "Reject wrong rule type")
	var manifest = {"api": 1, "id": "test-package", "name": "Test", "version": "1", "game_version": "0.3.0"}
	write_json(TEMP + "/mod.json", manifest)
	var pack = PCKPacker.new()
	check(pack.pck_start(TEMP + "/content.pck") == OK, "PCK create")
	check(pack.add_file_from_buffer("res://assets/balance.json", JSON.stringify(balance).to_utf8_buffer()) == OK and pack.flush() == OK, "PCK content")
	check(Package.create(TEMP + "/mod.json", TEMP + "/content.pck", TEMP + "/one.atlasmod", balance) == OK, "Single file build")
	check(Package.create(TEMP + "/mod.json", TEMP + "/content.pck", TEMP + "/one.atlasmod", balance) == ERR_ALREADY_EXISTS, "Never overwrite package")
	var data = Package.read(TEMP + "/one.atlasmod")
	check(not data.is_empty() and data.network_balance.start_coins == 1000, "Manifest, rules and PCK in one file")
	var profile = [Package.descriptor(data)]
	check(Package.profile_valid(profile), "Portable profile valid")
	check(not Package.profile_valid(profile + profile), "Reject duplicate packages")
	var wrong = profile.duplicate(true)
	wrong[0].requires = ["missing"]
	check(not Package.profile_valid(wrong), "Reject missing dependency")
	wrong = profile.duplicate(true)
	wrong[0].size = Package.MAX_SIZE + 1
	check(not Package.profile_valid(wrong), "Reject oversized network package")
	wrong = profile.duplicate(true)
	wrong[0].sha256 = "../path"
	check(not Package.profile_valid(wrong), "Reject unsafe cache filename")
	check(Package.extract(data, TEMP + "/extracted.pck") == OK and FileAccess.get_sha256(TEMP + "/extracted.pck") == data.pck_sha256, "Exact PCK extraction")
	var manager = Mods.new()
	manager.directory = TEMP + "/installed"
	manager.config_path = TEMP + "/mods.cfg"
	check(manager.install(TEMP + "/one.atlasmod").is_empty() and manager.installed.size() == 1, "Install single-file solo mod")
	check(not manager.install(TEMP + "/one.atlasmod").is_empty(), "Preserve installed mod")
	var corrupted = FileAccess.get_file_as_bytes(TEMP + "/one.atlasmod")
	corrupted[corrupted.size() - 1] ^= 1
	var file = FileAccess.open(TEMP + "/corrupted.atlasmod", FileAccess.WRITE)
	file.store_buffer(corrupted)
	file.close()
	check(Package.read(TEMP + "/corrupted.atlasmod").is_empty(), "Reject corrupted PCK")
	file = FileAccess.open(TEMP + "/truncated.atlasmod", FileAccess.WRITE)
	file.store_buffer(corrupted.slice(0, 14))
	file.close()
	check(Package.read(TEMP + "/truncated.atlasmod").is_empty(), "Reject truncated package")
	var old_boot = Mods.network_boot_path
	Mods.network_boot_path = TEMP + "/network_boot.json"
	check(Mods.write_network_boot(profile, {"kind": "lan", "address": "127.0.0.1", "name": "Player"}) == OK, "Persist exact network profile")
	check(JSON.parse_string(FileAccess.get_file_as_string(Mods.network_boot_path)).target.kind == "lan", "Reconnect target persists")
	Mods.network_boot_path = old_boot
	var old_env = OS.get_environment("ATLAS_MODS_DIR")
	OS.set_environment("ATLAS_MODS_DIR", TEMP + "/network_mods")
	check(Mods.install_network(TEMP + "/one.atlasmod").is_empty(), "Install same file into network folder")
	check(Mods.network_catalog().size() == 1, "Discover network package")
	OS.set_environment("ATLAS_MODS_DIR", old_env)
	cleanup(TEMP)
	print("PASS: %d package checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
