extends SceneTree

const Package = preload("res://src/mod_package.gd")
const Set = preload("res://src/mod_set.gd")
const TEMP = "user://test_mod_set"

func clean(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null: return
	for name in dir.get_directories(): clean(path.path_join(name))
	for name in dir.get_files(): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)

func _initialize() -> void:
	clean(TEMP)
	DirAccess.make_dir_recursive_absolute(TEMP)
	var bytes = FileAccess.get_file_as_bytes("res://website/examples/frontier.atlasmod")
	var doc = Package.read("res://website/examples/frontier.atlasmod")
	var index = JSON.stringify({"version": 1, "mods": [{"id": doc.id, "version": doc.version, "sha256": doc.sha256, "size": bytes.size()}]}).to_utf8_buffer()
	var file = FileAccess.open(TEMP + "/set.atlaspack", FileAccess.WRITE)
	file.store_buffer("ATLASSET".to_ascii_buffer())
	file.store_32(index.size())
	file.store_buffer(index)
	file.store_buffer(bytes)
	file.close()
	var result = Set.unpack(TEMP + "/set.atlaspack", TEMP + "/unpacked")
	assert(result.error.is_empty() and result.profile.size() == 1)
	assert(FileAccess.get_file_as_bytes(result.paths[0]) == bytes)
	var Mods = load("res://src/mods.gd")
	var old_boot = Mods.network_boot_path
	var old_directory = OS.get_environment("ATLAS_MODS_DIR")
	Mods.network_boot_path = TEMP + "/boot.json"
	OS.set_environment("ATLAS_MODS_DIR", TEMP + "/network")
	assert(Mods.install_network_set(TEMP + "/set.atlaspack").is_empty())
	assert(Mods.new().activate_network(), "Installed set activates the exact cached profile")
	Mods.network_boot_path = old_boot
	OS.set_environment("ATLAS_MODS_DIR", old_directory)
	assert(not Set.unpack(TEMP + "/set.atlaspack", TEMP + "/unpacked").error.is_empty(), "Never overwrite an existing directory")
	file = FileAccess.open(TEMP + "/set.atlaspack", FileAccess.READ_WRITE)
	file.seek_end(-1)
	file.store_8(1)
	file.close()
	assert(not Set.unpack(TEMP + "/set.atlaspack", TEMP + "/corrupt").error.is_empty(), "Reject corrupted package")
	assert(not DirAccess.dir_exists_absolute(TEMP + "/corrupt.part"), "Failed imports clean only their staging files")
	clean(TEMP)
	print("PASS: exact mod set roundtrip, overwrite protection, checksum rejection and staging cleanup")
	quit()
