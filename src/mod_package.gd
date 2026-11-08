extends RefCounted

const MAGIC = "ATLASMOD"
const MAX_SIZE = 64 * 1024 * 1024
const MAX_TOTAL = 128 * 1024 * 1024
const CHUNK = 65536
const MAX_MANIFEST = 4 * 1024 * 1024
const Rules = preload("res://src/mod_rules.gd")
const FRACTIONS = ["technology_bonus", "naval_multiplier", "attack_loss", "attack_loss_min", "attack_loss_max", "defender_retreat_loss", "defender_hold_loss"]

static func valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64: return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func hash_valid(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number() and value == value.to_lower()

static func manifest_valid(data: Variant) -> bool:
	if not data is Dictionary or not valid_id(data.get("id")) or (data.get("api") != 1 and data.get("api") != 2): return false
	if not (data.api is int or data.api is float): return false
	for key in ["name", "version", "game_version"]:
		if not data.get(key) is String or data[key].is_empty() or data[key].length() > 160: return false
	for key in ["requires", "conflicts"]:
		if not data.get(key, []) is Array or data.get(key, []).size() > 32: return false
		for id in data.get(key, []):
			if not valid_id(id) or id == data.id: return false
	return data.get("description", "") is String and data.get("description", "").length() <= 4096

static func read(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 16 or file.get_length() > MAX_SIZE: return {}
	if file.get_buffer(8).get_string_from_ascii() != MAGIC: return {}
	var length = file.get_32()
	if length < 2 or length > MAX_MANIFEST or length + 16 > file.get_length(): return {}
	var data = Rules.numbers(JSON.parse_string(file.get_buffer(length).get_string_from_utf8()))
	if not manifest_valid(data) or not hash_valid(data.get("pck_sha256")): return {}
	var offset = file.get_position()
	if file.get_32() != 0x43504447: return {}
	file.seek(offset)
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length(): hash.update(file.get_buffer(CHUNK))
	if hash.finish().hex_encode() != data.pck_sha256: return {}
	data.path = path
	data.offset = offset
	data.size = file.get_length()
	data.sha256 = FileAccess.get_sha256(path)
	return data

static func extract(data: Dictionary, destination: String) -> Error:
	var source = FileAccess.open(data.path, FileAccess.READ)
	var output = FileAccess.open(destination, FileAccess.WRITE)
	if source == null or output == null: return FileAccess.get_open_error()
	source.seek(data.offset)
	while source.get_position() < source.get_length(): output.store_buffer(source.get_buffer(CHUNK))
	output.flush()
	var error = output.get_error()
	output.close()
	if error == OK and FileAccess.get_sha256(destination) != data.pck_sha256: return ERR_FILE_CORRUPT
	return error

static func create(manifest_path: String, pck_path: String, output_path: String, network_balance: Variant = null) -> Error:
	if FileAccess.file_exists(output_path): return ERR_ALREADY_EXISTS
	var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest_valid(data): return ERR_INVALID_DATA
	data.pck_sha256 = FileAccess.get_sha256(pck_path)
	if network_balance != null: data.network_balance = network_balance
	var bytes = JSON.stringify(data).to_utf8_buffer()
	var source = FileAccess.open(pck_path, FileAccess.READ)
	if source == null: return FileAccess.get_open_error()
	if source.get_length() < 4 or source.get_32() != 0x43504447: return ERR_INVALID_DATA
	source.seek(0)
	if bytes.size() > MAX_MANIFEST or source.get_length() + bytes.size() + 12 > MAX_SIZE: return ERR_INVALID_DATA
	var output = FileAccess.open(output_path + ".tmp", FileAccess.WRITE)
	if output == null: return FileAccess.get_open_error()
	output.store_buffer(MAGIC.to_ascii_buffer())
	output.store_32(bytes.size())
	output.store_buffer(bytes)
	while source.get_position() < source.get_length(): output.store_buffer(source.get_buffer(CHUNK))
	output.flush()
	var error = output.get_error()
	output.close()
	if error == OK: error = DirAccess.rename_absolute(output_path + ".tmp", output_path)
	return error

static func descriptor(data: Dictionary) -> Dictionary:
	var result = {}
	for key in ["api", "id", "name", "version", "game_version", "sha256", "size", "pck_sha256"]: result[key] = data[key]
	for key in ["requires", "conflicts"]: result[key] = data.get(key, [])
	result.api = int(result.api)
	result.size = int(result.size)
	return result

static func profile_valid(profile: Variant) -> bool:
	if not profile is Array or profile.size() > 32: return false
	var ids = []
	var total = 0
	for item in profile:
		if not manifest_valid(item) or item.id in ids or not hash_valid(item.get("sha256")) or not hash_valid(item.get("pck_sha256")): return false
		if item.game_version != ProjectSettings.get_setting("application/config/version"): return false
		if not (item.get("size") is int or item.get("size") is float) or item.size < 16 or item.size > MAX_SIZE or item.size != floorf(item.size): return false
		for dependency in item.get("requires", []):
			if not dependency in ids: return false
		for conflict in item.get("conflicts", []):
			if profile.any(func(other): return other is Dictionary and other.get("id") == conflict): return false
		ids.append(item.id)
		total += int(item.size)
	return total <= MAX_TOTAL

static func fingerprint(profile: Array) -> String:
	return "" if profile.is_empty() else JSON.stringify(profile.map(func(m): return [m.id, m.version, m.sha256])).sha256_text()

static func portable(data: Dictionary) -> bool:
	if data.get("api") == 2: return data.get("changes", {}) is Dictionary and data.get("content", {}) is Dictionary
	return balance_valid(data.get("network_balance"), JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))

static func balance_valid(value: Variant, base: Dictionary) -> bool:
	if not value is Dictionary or value.size() != base.size() or value.get("version") != base.version: return false
	for key in base:
		if not value.has(key): return false
		var values = value[key] if base[key] is Array else [value[key]]
		if not values is Array or values.size() != (3 if base[key] is Array else 1): return false
		for number in values:
			if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > 1000000: return false
			if not key in FRACTIONS and number != floorf(float(number)): return false
			if key in ["nuclear_threshold", "spy_seconds", "attack_seconds", "nuke_seconds", "bot_seconds", "naval_ships", "bot_max_level", "unit_weight"] and number < 1: return false
			if (key.ends_with("chance") or key == "bot_economy_bonus") and number > 100: return false
			if key in FRACTIONS and number > 1: return false
	return value.attack_loss_min <= value.attack_loss_max
