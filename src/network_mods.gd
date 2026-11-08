extends Node

signal required(profile: Array)
signal progress(done: int, total: int)
signal downloaded
signal failed(message: String)

const Package = preload("res://src/mod_package.gd")
const Mods = preload("res://src/mods.gd")
var net: Node
var offered: Array = []
var offers: Dictionary = {}
var target: Dictionary = {}
var resume: Dictionary = {}
var cache = Mods.network_directory().path_join("cache")
var queue: Array = []
var receiving: FileAccess
var offset = 0
var total_bytes = 0
var done_bytes = 0
var downloading = false
var deadline = 0
var http: HTTPRequest
var last_sent: Dictionary = {}

func profile() -> Array:
	return Engine.get_meta("atlas_network_profile", [])

func hashes() -> Array:
	return profile().map(func(item): return item.sha256)

func hashes_valid(values: Array) -> bool:
	if values.size() > 32: return false
	var seen = []
	for value in values:
		if not Package.hash_valid(value) or value in seen: return false
		seen.append(value)
	return true

func offer(id: int) -> void:
	offers[id] = Time.get_ticks_msec()
	net._mod_offer.rpc_id(id, profile())

func receive_offer(value: Array) -> void:
	if not net.active or not Package.profile_valid(value) or downloading: return
	offered = value
	deadline = 0
	net.stage = "mods"
	required.emit(value)

func begin() -> void:
	if net.stage != "mods" or downloading: return
	DirAccess.make_dir_recursive_absolute(cache)
	queue = offered.duplicate(true)
	total_bytes = 0
	done_bytes = 0
	for item in queue: total_bytes += int(item.size)
	downloading = true
	next_file()

func next_file() -> void:
	receiving = null
	while not queue.is_empty():
		var item = queue[0]
		var path = cache.path_join(item.sha256 + ".atlasmod")
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != item.sha256: break
		var cached = Package.read(path)
		if cached.is_empty(): break
		if not shared_rules_valid(cached): fail("Invalid shared network rules"); return
		done_bytes += int(item.size)
		queue.pop_front()
	if queue.is_empty():
		downloading = false
		var documents = offered.map(func(item): return Package.read(cache.path_join(item.sha256 + ".atlasmod")))
		var composed = Package.Rules.compose(documents, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))
		if not composed.error.is_empty(): fail(composed.error); return
		var error = Mods.write_network_boot(offered, target)
		if error != OK: fail(error_string(error)); return
		downloaded.emit()
		return
	offset = 0
	receiving = FileAccess.open(cache.path_join(queue[0].sha256 + ".part"), FileAccess.WRITE)
	if receiving == null: fail(error_string(FileAccess.get_open_error())); return
	request_chunk()

func request_chunk() -> void:
	deadline = Time.get_ticks_msec() + 15000
	if net.php == null:
		net._mod_chunk_request.rpc_id(1, queue[0].sha256, offset)
		return
	if http == null:
		http = HTTPRequest.new()
		http.timeout = 10
		http.body_size_limit = 131072
		http.max_redirects = 0
		add_child(http)
		http.request_completed.connect(http_chunk)
	var error = http.request(net.server_url + "/mods.php?hash=" + queue[0].sha256 + "&offset=" + str(offset))
	if error != OK: fail(error_string(error))

func http_chunk(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not downloading: return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or not data.get("data") is String or data.data.length() > 90000:
		fail("Cannot download network mod")
		return
	if data.get("hash") != queue[0].sha256 or data.get("offset") != offset: fail("Invalid mod chunk"); return
	receive_chunk(data.hash, offset, Marshalls.base64_to_raw(data.data))

func receive_chunk(hash: String, position: int, bytes: PackedByteArray) -> void:
	if not downloading or queue.is_empty() or receiving == null: return
	var item = queue[0]
	if hash != item.sha256 or position != offset or bytes.size() != mini(Package.CHUNK, int(item.size) - offset):
		fail("Invalid network mod chunk")
		return
	receiving.store_buffer(bytes)
	if receiving.get_error() != OK: fail("Cannot write network mod"); return
	offset += bytes.size()
	progress.emit(done_bytes + offset, total_bytes)
	if offset < int(item.size): request_chunk(); return
	receiving.flush()
	receiving.close()
	receiving = null
	var part = cache.path_join(hash + ".part")
	var data = Package.read(part)
	if data.is_empty() or data.sha256 != hash or Package.descriptor(data) != item or not shared_rules_valid(data):
		fail("Network mod checksum or manifest mismatch")
		return
	var error = DirAccess.rename_absolute(part, cache.path_join(hash + ".atlasmod"))
	if error != OK: fail(error_string(error)); return
	done_bytes += int(item.size)
	queue.pop_front()
	next_file()

func shared_rules_valid(data: Dictionary) -> bool:
	return Package.portable(data)

func send_chunk(id: int, hash: String, position: int) -> void:
	if not offers.has(id) or Time.get_ticks_msec() - offers[id] > 600000 or not Package.hash_valid(hash): return
	if position < 0 or position % Package.CHUNK != 0: return
	var now = Time.get_ticks_msec()
	var limit = last_sent.get(id, {"time": now, "count": 0})
	if now - limit.time >= 1000: limit = {"time": now, "count": 0}
	limit.count += 1
	last_sent[id] = limit
	if limit.count > 64: return
	var files = Engine.get_meta("atlas_network_files", {})
	if not files.has(hash): return
	var source = FileAccess.open(files[hash], FileAccess.READ)
	if source == null or position >= source.get_length(): return
	source.seek(position)
	net._mod_chunk.rpc_id(id, hash, position, source.get_buffer(Package.CHUNK))

func fail(message: String) -> void:
	cancel()
	failed.emit(message)

func cancel() -> void:
	if http != null: http.cancel_request()
	if receiving != null: receiving.close()
	receiving = null
	if not queue.is_empty(): DirAccess.remove_absolute(cache.path_join(queue[0].sha256 + ".part"))
	queue = []
	downloading = false
	deadline = 0

func _process(_delta: float) -> void:
	if downloading and Time.get_ticks_msec() > deadline: fail("Network mod download timed out")

func _exit_tree() -> void:
	cancel()
