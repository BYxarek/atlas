extends RefCounted
## Packs are trusted native code. This loader deliberately has no game preloads.

const ROOT = "user://mods"
const CONFIG = "user://mods.cfg"
const API = 1
const STARTING = "user://mods_starting"
const Package = preload("res://src/mod_package.gd")
const NETWORK_ROOT = "user://network_mods"
const NETWORK_BOOT = "user://network_boot.json"
static var network_boot_path = NETWORK_BOOT
var directory = ROOT
var config_path = CONFIG
var marker_path = STARTING
var installed: Array = []
var selected: Array = []
var errors: Array = []

func valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64: return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

func read_manifest(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Package.MAX_MANIFEST: return {}
	var data = Package.Rules.numbers(JSON.parse_string(file.get_as_text()))
	if not data is Dictionary or not valid_id(data.get("id")): return {}
	for key in ["name", "version", "game_version"]:
		if not data.get(key) is String or data[key].is_empty() or data[key].length() > 160: return {}
	if not data.get("api") in [1, 2]: return {}
	for key in ["requires", "conflicts"]:
		if not data.get(key, []) is Array or data.get(key, []).size() > 64: return {}
		for id in data.get(key, []):
			if not valid_id(id) or id == data.id: return {}
	if not data.get("description", "") is String or data.get("description", "").length() > 4096: return {}
	data.path = path.get_base_dir().path_join("content.pck")
	if not FileAccess.file_exists(data.path): return {}
	var pack = FileAccess.open(data.path, FileAccess.READ)
	if pack == null or pack.get_length() < 4 or pack.get_32() != 0x43504447: return {}
	data.sha256 = FileAccess.get_sha256(data.path)
	if data.sha256.is_empty(): return {}
	if data.api == 2: data.sha256 = (data.sha256 + FileAccess.get_sha256(path)).sha256_text()
	return data

func scan() -> void:
	installed = []
	errors = []
	DirAccess.make_dir_recursive_absolute(directory)
	var dir = DirAccess.open(directory)
	if dir == null:
		errors.append("Cannot open mods directory")
		return
	for folder in dir.get_directories():
		if not valid_id(folder): continue
		var data = read_manifest(directory.path_join(folder).path_join("mod.json"))
		if data.is_empty() or data.id != folder:
			errors.append("Invalid mod: " + folder)
		else: installed.append(data)
	installed.sort_custom(func(a, b): return a.id < b.id)
	var config = ConfigFile.new()
	var status = config.load(config_path)
	selected = []
	if status != OK and status != ERR_FILE_NOT_FOUND: errors.append("Cannot read mods configuration")
	var value = config.get_value("mods", "enabled", [])
	if value is Array: selected = value
	else: errors.append("Invalid mods configuration")

func find_mod(id: String) -> Dictionary:
	for mod in installed:
		if mod.id == id: return mod
	return {}

func validate(order: Array) -> String:
	var seen: Array = []
	for id in order:
		if not valid_id(id) or id in seen: return "Invalid or duplicate mod ID"
		var mod = find_mod(id)
		if mod.is_empty(): return "Missing mod: " + id
		if mod.game_version != ProjectSettings.get_setting("application/config/version"): return "Incompatible game version: " + id
		for dependency in mod.get("requires", []):
			if not dependency in seen: return "%s requires %s earlier in load order" % [id, dependency]
		for conflict in mod.get("conflicts", []):
			if conflict in order: return "%s conflicts with %s" % [id, conflict]
		seen.append(id)
	return ""

func save_selection(order: Array) -> String:
	var problem = validate(order)
	if not problem.is_empty(): return problem
	var config = ConfigFile.new()
	var status = config.load(config_path)
	if status != OK and status != ERR_FILE_NOT_FOUND: return "Cannot read mods configuration"
	var previous = config.get_value("mods", "enabled", [])
	if not previous is Array: previous = []
	config.set_value("mods", "enabled", order)
	for id in order:
		if not id in previous: config.set_value("hashes", id, find_mod(id).sha256)
	var error = config.save(config_path + ".tmp")
	if error == OK: error = DirAccess.rename_absolute(config_path + ".tmp", config_path)
	if error != OK: return error_string(error)
	selected = order.duplicate()
	return ""

func activate() -> bool:
	Engine.set_meta("atlas_mods", "")
	Engine.set_meta("atlas_mod_list", [])
	if not Engine.has_meta("atlas_base_balance"): Engine.set_meta("atlas_base_balance", JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))
	Engine.set_meta("atlas_rule_documents", [])
	Engine.set_meta("atlas_content", Package.Rules.defaults())
	Engine.set_meta("atlas_rule_sources", {})
	Engine.set_meta("atlas_rule_conflicts", [])
	Engine.set_meta("atlas_network_mode", false)
	Engine.set_meta("atlas_network_profile", [])
	Engine.remove_meta("atlas_mod_error")
	if "--no-mods" in OS.get_cmdline_user_args(): return true
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args() or FileAccess.file_exists(network_boot_path): return activate_network()
	if FileAccess.file_exists(marker_path):
		Engine.set_meta("atlas_mod_error", "Previous mod startup failed. Mods skipped; review them in the menu.")
		return true
	scan()
	var problem = validate(selected)
	var config = ConfigFile.new()
	config.load(config_path)
	var identity: Array = []
	for id in selected:
		var mod = find_mod(str(id))
		if mod.is_empty(): continue
		if config.get_value("hashes", id, "") != mod.sha256: problem = "Mod changed; enable it again to approve: " + id
		identity.append([id, mod.version, mod.sha256])
	var portable_mods = selected.map(func(id): return find_mod(str(id))).filter(func(mod): return mod.get("api") == 2)
	var composed = Package.Rules.compose(portable_mods, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))
	if not composed.error.is_empty(): problem = composed.error
	if not problem.is_empty():
		Engine.set_meta("atlas_mod_error", problem)
		return true
	if not selected.is_empty():
		var marker = FileAccess.open(marker_path, FileAccess.WRITE)
		if marker == null:
			Engine.set_meta("atlas_mod_error", "Cannot create mod recovery marker")
			return true
		marker.store_string("starting")
		marker.close()
	for id in selected:
		if not ProjectSettings.load_resource_pack(find_mod(id).path, true):
			Engine.set_meta("atlas_mod_error", "Cannot load pack: " + id)
			return false # Loaded packs cannot be unmounted; never continue with a partial set.
	if not portable_mods.is_empty():
		composed = Package.Rules.compose(portable_mods, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))
		if not composed.error.is_empty(): return network_failure(composed.error)
	if not identity.is_empty(): Engine.set_meta("atlas_mods", JSON.stringify(identity).sha256_text())
	Engine.set_meta("atlas_mod_list", selected.duplicate())
	Engine.set_meta("atlas_rule_documents", portable_mods)
	if not portable_mods.is_empty() and not apply_rules(composed, "solo_" + str(Engine.get_meta("atlas_mods"))): return false
	return true

func install(path: String) -> String:
	if path.get_extension().to_lower() == "atlasmod": return install_package(path)
	var mod = read_manifest(path)
	if mod.is_empty(): return "Invalid mod.json or missing content.pck"
	var target = directory.path_join(mod.id)
	if DirAccess.dir_exists_absolute(target): return "Mod already installed: " + mod.id
	var staging = directory.path_join(".install-" + mod.id)
	if DirAccess.dir_exists_absolute(staging): return "Remove incomplete installation: " + staging
	var error = DirAccess.make_dir_recursive_absolute(staging)
	if error == OK: error = DirAccess.copy_absolute(mod.path, staging.path_join("content.pck"))
	if error == OK: error = DirAccess.copy_absolute(path, staging.path_join("mod.json"))
	if error == OK: error = DirAccess.rename_absolute(staging, target)
	if error != OK:
		DirAccess.remove_absolute(staging.path_join("content.pck"))
		DirAccess.remove_absolute(staging.path_join("mod.json"))
		DirAccess.remove_absolute(staging)
		return error_string(error)
	scan()
	return ""

func install_package(path: String) -> String:
	var data = Package.read(path)
	if data.is_empty(): return "Invalid .atlasmod package"
	var target = directory.path_join(data.id)
	if DirAccess.dir_exists_absolute(target): return "Mod already installed: " + data.id
	var staging = directory.path_join(".install-" + data.id)
	if DirAccess.dir_exists_absolute(staging): return "Remove incomplete installation: " + staging
	var error = DirAccess.make_dir_recursive_absolute(staging)
	if error == OK: error = Package.extract(data, staging.path_join("content.pck"))
	if error == OK:
		var file = FileAccess.open(staging.path_join("mod.json"), FileAccess.WRITE)
		if file == null: error = FileAccess.get_open_error()
		else:
			for key in ["path", "offset", "size", "sha256"]: data.erase(key)
			file.store_string(JSON.stringify(data))
			file.flush()
			error = file.get_error()
			file.close()
	if error == OK: error = DirAccess.rename_absolute(staging, target)
	if error != OK:
		for name in ["mod.json", "content.pck"]: DirAccess.remove_absolute(staging.path_join(name))
		DirAccess.remove_absolute(staging)
		return error_string(error)
	scan()
	return ""

static func network_directory() -> String:
	var path = OS.get_environment("ATLAS_MODS_DIR")
	return NETWORK_ROOT if path.is_empty() else path

static func network_catalog(path: String = "") -> Array:
	if path.is_empty(): path = network_directory()
	DirAccess.make_dir_recursive_absolute(path)
	var folder = DirAccess.open(path)
	if folder == null: return [{"error": "Cannot open network_mods"}]
	var result = []
	for filename in folder.get_files():
		if filename.get_extension().to_lower() != "atlasmod": continue
		var data = Package.read(path.path_join(filename))
		if data.is_empty(): return [{"error": "Invalid package: " + filename}]
		result.append(data)
	return result

static func write_network_boot(profile: Array, target: Dictionary = {}) -> Error:
	if not Package.profile_valid(profile): return ERR_INVALID_DATA
	var file = FileAccess.open(network_boot_path + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"profile": profile, "target": target}))
	file.flush()
	var error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(network_boot_path + ".tmp", network_boot_path)
	return error

static func install_network(path: String) -> String:
	var data = Package.read(path)
	var base = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))
	if data.is_empty() or not Package.portable(data): return "Mod has no compatible shared network rules"
	var folder = network_directory()
	var target = folder.path_join(data.id + ".atlasmod")
	DirAccess.make_dir_recursive_absolute(folder)
	if FileAccess.file_exists(target): return "Network mod already installed: " + data.id
	var error = DirAccess.copy_absolute(path, target + ".tmp")
	if error == OK: error = DirAccess.rename_absolute(target + ".tmp", target)
	return "" if error == OK else error_string(error)

func activate_network() -> bool:
	var catalog = network_catalog()
	var boot = JSON.parse_string(FileAccess.get_file_as_string(network_boot_path)) if FileAccess.file_exists(network_boot_path) else {}
	var profile = boot.get("profile", []) if boot is Dictionary else []
	var server = OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args()
	if not server and boot is Dictionary and boot.has("profile"):
		catalog.append_array(network_catalog(network_directory().path_join("cache")))
	if server or not boot is Dictionary or not boot.has("profile"):
		profile = []
		for data in catalog:
			if data.has("error"): return network_failure(data.error)
			profile.append(Package.descriptor(data))
	if not Package.profile_valid(profile): return network_failure("Invalid network mod profile or load order")
	var base = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))
	var documents = []
	var files = {}
	for item in profile:
		var matches = catalog.filter(func(data): return data.get("sha256") == item.sha256)
		if matches.is_empty(): return network_failure("Missing network mod: " + item.id)
		var data = matches[0]
		if not Package.portable(data): return network_failure("Mod has no compatible shared network rules: " + item.id)
		documents.append(data)
		files[item.sha256] = data.path
	Engine.set_meta("atlas_network_mode", true)
	Engine.set_meta("atlas_network_profile", profile)
	Engine.set_meta("atlas_network_files", files)
	Engine.set_meta("atlas_mods", Package.fingerprint(profile))
	Engine.set_meta("atlas_mod_list", profile.map(func(item): return item.id))
	Engine.set_meta("atlas_base_balance", base)
	Engine.set_meta("atlas_rule_documents", documents)
	var composed = Package.Rules.compose(documents, base)
	if not composed.error.is_empty(): return network_failure(composed.error)
	if not profile.is_empty() and not apply_rules(composed, "network_" + Package.fingerprint(profile)): return false
	return true

func apply_rules(composed: Dictionary, identity: String) -> bool:
	Engine.set_meta("atlas_content", composed.content)
	Engine.set_meta("atlas_rule_sources", composed.sources)
	Engine.set_meta("atlas_rule_conflicts", composed.conflicts)
	var resources = {"assets/balance.json": composed.balance}
	var atlas = composed.content.get("map", JSON.parse_string(FileAccess.get_file_as_string("res://assets/world.json")))
	var military = JSON.parse_string(FileAccess.get_file_as_string("res://assets/military.json"))
	var armies = []
	for i in atlas.size():
		var army = military.armies[i].duplicate() if i < military.armies.size() and not composed.content.has("map") else [18, 3, 0]
		while army.size() < composed.balance.start_units.size(): army.append(0)
		army = composed.content.scenario.get("armies", {}).get(str(i), army)
		armies.append(army)
	military.armies = armies
	resources["assets/military.json"] = military
	if composed.content.has("map"): resources["assets/world.json"] = atlas
	var prefix = "user://" + identity + "_v2"
	var pack = PCKPacker.new()
	if pack.pck_start(prefix + ".pck.tmp") != OK: return network_failure("Cannot build mod rules")
	for path in resources:
		var error = pack.add_file_from_buffer("res://" + path, JSON.stringify(resources[path]).to_utf8_buffer())
		if error != OK: return network_failure(error_string(error))
	if pack.flush() != OK: return network_failure("Cannot flush mod rules")
	var status = DirAccess.rename_absolute(prefix + ".pck.tmp", prefix + ".pck")
	if status != OK and not FileAccess.file_exists(prefix + ".pck"): return network_failure(error_string(status))
	if not ProjectSettings.load_resource_pack(prefix + ".pck", true): return network_failure("Cannot load mod rules")
	return true

func network_failure(problem: String) -> bool:
	Engine.set_meta("atlas_mod_error", problem)
	return false

static func install_network_set(path: String) -> String:
	var cache = network_directory().path_join("cache")
	DirAccess.make_dir_recursive_absolute(cache)
	var staging = cache.path_join(".set_%d" % Time.get_ticks_usec())
	var result = preload("res://src/mod_set.gd").unpack(path, staging)
	if not result.error.is_empty(): return result.error
	var problem = ""
	for i in result.paths.size():
		var file = result.paths[i]
		var hash = result.profile[i].sha256
		var target = cache.path_join(hash + ".atlasmod")
		if FileAccess.file_exists(target) and FileAccess.get_sha256(target) == hash: continue
		var error = DirAccess.copy_absolute(file, target + ".part")
		if error == OK and FileAccess.get_sha256(target + ".part") != hash: error = ERR_FILE_CORRUPT
		if error == OK: error = DirAccess.rename_absolute(target + ".part", target)
		if error != OK:
			DirAccess.remove_absolute(target + ".part")
			problem = error_string(error)
			break
	for file in result.paths: DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(staging)
	if problem.is_empty():
		var error = write_network_boot(result.profile)
		if error != OK: problem = error_string(error)
	return problem
