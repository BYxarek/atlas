extends RefCounted
## Ordered, checksummed packages; unpack only to a new directory.

const Package = preload("res://src/mod_package.gd")

static func unpack(path: String, destination: String) -> Dictionary:
	var input = FileAccess.open(path, FileAccess.READ)
	if input == null or input.get_length() < 14 or input.get_length() > Package.MAX_TOTAL + 65548: return {"error": "Invalid mod set size"}
	if input.get_buffer(8).get_string_from_ascii() != "ATLASSET": return {"error": "Invalid ATLASSET header"}
	var size = input.get_32()
	if size < 2 or size > 65536 or input.get_position() + size > input.get_length(): return {"error": "Invalid mod set index"}
	var index = Package.Rules.numbers(JSON.parse_string(input.get_buffer(size).get_string_from_utf8()))
	if not index is Dictionary or index.get("version") != 1 or not index.get("mods") is Array or index.mods.is_empty() or index.mods.size() > 32: return {"error": "Invalid mod set index"}
	var total = 0
	var ids = []
	for item in index.mods:
		if not item is Dictionary or not Package.valid_id(item.get("id")) or item.id in ids or not item.get("version") is String or not Package.hash_valid(item.get("sha256")) or not Package.Rules.number(item.get("size"), 16, Package.MAX_SIZE): return {"error": "Invalid mod set entry"}
		ids.append(item.id)
		total += int(item.size)
	if total > Package.MAX_TOTAL or input.get_position() + total != input.get_length(): return {"error": "Mod set size mismatch"}
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination): return {"error": "Destination must be a new directory"}
	var staging = destination + ".part"
	if DirAccess.dir_exists_absolute(staging) or FileAccess.file_exists(staging): return {"error": "Staging directory already exists"}
	if DirAccess.make_dir_recursive_absolute(staging) != OK: return {"error": "Cannot create staging directory"}
	var documents = []
	var profile = []
	var paths = []
	var problem = ""
	for i in index.mods.size():
		var item = index.mods[i]
		var target = staging.path_join("%02d_%s.atlasmod" % [i, item.id])
		paths.append(target)
		var output = FileAccess.open(target, FileAccess.WRITE)
		if output == null:
			problem = "Cannot write package"
			break
		var remaining = int(item.size)
		while remaining > 0:
			var bytes = input.get_buffer(mini(Package.CHUNK, remaining))
			if bytes.is_empty():
				problem = "Unexpected end of mod set"
				break
			output.store_buffer(bytes)
			remaining -= bytes.size()
		output.flush()
		var error = output.get_error()
		output.close()
		var data = Package.read(target)
		if not problem.is_empty() or error != OK or data.is_empty() or data.id != item.id or data.version != item.version or data.sha256 != item.sha256 or not Package.portable(data):
			problem = "Package checksum, identity or portable rules mismatch: " + item.id
			break
		documents.append(data)
		profile.append(Package.descriptor(data))
	if problem.is_empty() and not Package.profile_valid(profile): problem = "Invalid mod set order, dependencies, conflicts or versions"
	if problem.is_empty(): problem = Package.Rules.compose(documents, Engine.get_meta("atlas_base_balance", JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))).error
	if problem.is_empty() and DirAccess.rename_absolute(staging, destination) != OK: problem = "Cannot finalize mod set directory"
	if not problem.is_empty():
		for target in paths: DirAccess.remove_absolute(target)
		DirAccess.remove_absolute(staging)
		return {"error": problem}
	return {"error": "", "profile": profile, "paths": paths.map(func(p): return destination.path_join(p.get_file()))}
