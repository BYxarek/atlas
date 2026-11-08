extends Node

signal lobby_changed
signal view_received(data: Dictionary)
signal discovery_changed
signal closed(reason: String)
signal notice(text: String)
signal directory_changed
const WIRE_VERSION = 11
const World = preload("res://src/network_world.gd")
const Quality = preload("res://src/network_quality.gd")
const PROBE_TIMEOUT_MS = 5000
static var COUNTRY_COUNT: int = preload("res://src/game.gd").COUNTRY_COUNT
static var MAX_PLAYERS: int = COUNTRY_COUNT - preload("res://src/game.gd").MICROSTATES.size()
const DEFAULT_PORT = 24760
const DISCOVERY_PORT = 24761
const COLORS = ["69dfbd", "73aeef", "edc16e", "b697ef", "f291a1", "ed876a", "c9dbed", "a8cc6a"]
var identity_token = ""
var save_directory = "user://multiplayer"
var active = false
var hosting = false
var stage = "offline"
var players: Dictionary = {}
var my_slot = ""
var host_slot = ""
var room_id = ""
var lobby_name = ""
var port = DEFAULT_PORT
var status = ""
var world: RefCounted
var peer: MultiplayerPeer
var directory: RefCounted
var php: Node
var transport: Node
var dedicated_room = false
var directory_client = false
var directory_rooms: Array = []
var directory_status = ""
var server_url = ""
var resuming = false
var responder: PacketPeerUDP
var browser: PacketPeerUDP
var found: Array = []
var banned: Array = []
var scan_time = 0.0
var step_time = 0.0
var joining_since = 0
var player_name = "Игрок"
var rate_limits: Dictionary = {}
var discovery_limits: Dictionary = {}
var occupied: Array = []
var mods = preload("res://src/network_mods.gd").new()
var quality = Quality.new()
var player_pings: Dictionary = {}
var player_pings_at = 0
var quality_supported = false
var probe_sequence = 0
var probe_started = -1
var next_probe = 0

func _init() -> void:
	mods.net = self
	add_child(mods)

func _ready() -> void:
	if transport != null: return
	name = "NetworkSession"
	if not str(Engine.get_meta("atlas_mods", "")).is_empty(): save_directory += "/" + str(Engine.get_meta("atlas_mods"))
	if identity_token.is_empty():
		var config = ConfigFile.new()
		config.load("user://network_identity.cfg")
		var stored = config.get_value("network", "token", "")
		identity_token = stored if stored is String and valid_token(stored) else Crypto.new().generate_random_bytes(24).hex_encode()
		config.set_value("network", "token", identity_token)
		config.save("user://network_identity.cfg")
	multiplayer.connected_to_server.connect(func(): _hello.rpc_id(1, player_name, login_token(), directory_client, WIRE_VERSION, mods.hashes()))
	multiplayer.connection_failed.connect(func(): shutdown("Не удалось подключиться к хосту."))
	multiplayer.server_disconnected.connect(func():
		if active: shutdown("Соединение с хостом потеряно. Хост может открыть сохранённую сетевую партию."))
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.peer_connected.connect(func(id):
		if directory != null: directory.connected(id))

func channel() -> Node:
	return transport if transport != null else self

func login_token() -> String:
	if not directory_client: return identity_token
	var parts = server_url.trim_suffix("/").split("/", true, 4)
	parts[0] = parts[0].to_lower()
	parts[2] = parts[2].to_lower()
	var scope = "/".join(parts)
	if scope.begins_with("wss://"): scope = scope.trim_suffix(":443")
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, identity_token.to_utf8_buffer(), ("atlas-profile-v1|" + scope).to_utf8_buffer()).hex_encode().substr(0, 48)

func can_send(id: int) -> bool:
	if peer == null or not multiplayer.get_peers().has(id): return false
	if peer is WebSocketMultiplayerPeer:
		var socket = peer.get_peer(id)
		return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN
	return true

func is_admin() -> bool:
	return hosting or (not my_slot.is_empty() and my_slot == host_slot)

func host_directory(game_port: int, data_path: String, max_rooms: int = 8) -> Error:
	if not str(Engine.get_meta("atlas_mods", "")).is_empty() and not Engine.get_meta("atlas_network_mode", false): return ERR_UNAVAILABLE
	if active or game_port < 1024 or game_port > 65535 or max_rooms < 1 or max_rooms > 32: return ERR_INVALID_PARAMETER
	var socket = WebSocketMultiplayerPeer.new()
	socket.inbound_buffer_size = 1048576
	socket.outbound_buffer_size = 1048576
	socket.max_queued_packets = 64
	var error = socket.create_server(game_port, "0.0.0.0")
	if error != OK: return error
	peer = socket
	port = game_port
	directory = load("res://src/vps_directory.gd").new()
	directory.hub = self
	directory.data_path = data_path + ("/" + str(Engine.get_meta("atlas_mods")) if not str(Engine.get_meta("atlas_mods", "")).is_empty() else "")
	directory.max_rooms = max_rooms
	error = directory.restore_rooms()
	if error != OK:
		peer.close()
		directory = null
		return error
	active = true
	stage = "directory"
	# Rooms exchange commands only with the server; peers must not relay to each other.
	multiplayer.server_relay = false
	multiplayer.multiplayer_peer = peer
	return OK

func join_directory(url: String, nickname: String) -> Error:
	mods.target = {"kind": "vps", "address": url, "name": nickname}
	if not str(Engine.get_meta("atlas_mods", "")).is_empty() and not Engine.get_meta("atlas_network_mode", false): return ERR_UNAVAILABLE
	var pattern = RegEx.new()
	pattern.compile("^(wss://[A-Za-z0-9.-]+(:[0-9]{1,5})?|ws://(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?)/?$")
	if active or url.length() > 255 or pattern.search(url) == null: return ERR_INVALID_PARAMETER
	var socket = WebSocketMultiplayerPeer.new()
	socket.inbound_buffer_size = 1048576
	socket.outbound_buffer_size = 1048576
	socket.max_queued_packets = 64
	var error = socket.create_client(url)
	if error != OK: return error
	peer = socket
	directory_client = true
	server_url = url
	player_name = clean_name(nickname)
	stage = "connecting"
	active = true
	my_slot = ""
	players = {}
	joining_since = Time.get_ticks_msec()
	multiplayer.multiplayer_peer = peer
	return OK

func join_php(url: String, nickname: String, reconnect_nonce: String = "") -> Error:
	mods.target = {"kind": "php", "address": url, "name": nickname, "nonce": reconnect_nonce}
	if not str(Engine.get_meta("atlas_mods", "")).is_empty() and not Engine.get_meta("atlas_network_mode", false): return ERR_UNAVAILABLE
	var pattern = RegEx.new()
	pattern.compile("^(https://[A-Za-z0-9.-]+(:[0-9]{1,5})?|http://(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?)(/[A-Za-z0-9_.~-]+)*/?$")
	if active or url.length() > 255 or pattern.search(url) == null: return ERR_INVALID_PARAMETER
	server_url = url.trim_suffix("/").trim_suffix("/api.php")
	directory_client = true
	player_name = clean_name(nickname)
	active = true
	stage = "connecting"
	my_slot = ""
	players = {}
	joining_since = Time.get_ticks_msec()
	php = load("res://src/php_transport.gd").new()
	php.net = self
	php.endpoint = server_url + "/api.php"
	add_child(php)
	return OK

func directory_request(action: String, args: Array = []) -> void:
	if action in ["join", "create"]:
		mods.target.action = action
		mods.target.args = args.duplicate()
	if php != null:
		php.enqueue(action, args)
		return
	if active and directory_client: _directory_request.rpc_id(1, action, args)

@rpc("any_peer", "call_remote", "reliable")
func _directory_request(action: String, args: Array) -> void:
	if directory != null: directory.request(multiplayer.get_remote_sender_id(), action, args)

@rpc("authority", "call_remote", "reliable")
func _directory_update(data: Dictionary) -> void:
	if not active or not directory_client: return
	if data.has("quality_echo"):
		if php != null or stage != "lobby" or probe_started < 0 or data.get("room") != room_id or not data.quality_echo is int or data.quality_echo != probe_sequence: return
		var now = Time.get_ticks_msec()
		var elapsed = now - probe_started
		probe_started = -1
		quality.record(elapsed if elapsed < PROBE_TIMEOUT_MS else -1, now)
		update_player_pings(data.get("pings"))
		return
	if not data.get("rooms") is Array or data.rooms.size() > 32: return
	for room in data.rooms:
		if not room is Dictionary or not room.get("id") is String or room.id.length() != 16 or not room.id.is_valid_hex_number(): return
		if not room.get("name") is String or room.name.length() > 40 or not room.get("stage") in ["lobby", "game"]: return
		if not room.get("member") is bool or not room.get("admin") is bool or not room.get("saved") is bool: return
		if not room.get("players") is int or room.players < 1 or room.players > MAX_PLAYERS or not room.get("elapsed") is int or room.elapsed < 0: return
	directory_rooms = data.rooms
	directory_status = str(data.get("status", "")).substr(0, 200)
	if data.get("browse", false):
		if stage != "directory": reset_quality()
		stage = "directory"
		my_slot = ""
		players = {}
	directory_changed.emit()
	if not mods.resume.is_empty() and stage == "directory":
		var retry = mods.resume
		mods.resume = {}
		directory_request.call_deferred(str(retry.get("action", "list")), retry.get("args", []))

func reset_quality() -> void:
	quality = Quality.new()
	player_pings.clear()
	quality_supported = false
	probe_started = -1
	next_probe = 0

func update_player_pings(pings: Variant) -> void:
	player_pings.clear()
	if stage != "lobby" or not pings is Dictionary or pings.size() > MAX_PLAYERS: return
	player_pings_at = Time.get_ticks_msec()
	for slot in pings:
		if players.has(slot) and players[slot].connected and not players[slot].bot and Quality.valid_ping(pings[slot]):
			player_pings[slot] = pings[slot]

func player_ping_ms(slot: String) -> int:
	var now = Time.get_ticks_msec()
	if slot == my_slot: return quality.ping_ms(now)
	return player_pings.get(slot, -1) if now - player_pings_at <= Quality.FRESH_MS else -1

func poll_quality(now: int) -> void:
	if probe_started >= 0:
		if now - probe_started < PROBE_TIMEOUT_MS: return
		quality.record(-1, now)
		probe_started = -1
	if now < next_probe or not can_send(1): return
	probe_sequence += 1
	probe_started = now
	next_probe = now + 2000
	_directory_request.rpc_id(1, "quality", [{"echo": probe_sequence, "ping_ms": quality.ping_ms(now)}])

@rpc("authority", "call_remote", "reliable")
func _directory_notice(text: String) -> void:
	if active and directory_client: notice.emit(text.substr(0, 200))

func valid_token(token: String) -> bool:
	return token.length() == 48 and token.is_valid_hex_number()

func host_room(title: String, nickname: String, game_port: int = DEFAULT_PORT, saved_path: String = "") -> Error:
	if not str(Engine.get_meta("atlas_mods", "")).is_empty() and not Engine.get_meta("atlas_network_mode", false): return ERR_UNAVAILABLE
	if active or game_port < 1024 or game_port > 65535: return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(game_port, MAX_PLAYERS - 1, 2)
	if error != OK: return error
	port = game_port
	directory_client = false
	lobby_name = title.strip_edges().substr(0, 40)
	if lobby_name.is_empty(): lobby_name = "Лобби ATLAS"
	room_id = Crypto.new().generate_random_bytes(8).hex_encode()
	players = {}
	world = null
	banned = []
	my_slot = identity_token.sha256_text().substr(0, 16)
	host_slot = my_slot
	players[my_slot] = make_player(nickname, identity_token.sha256_text(), 1, false)
	if not saved_path.is_empty() and not restore_match(saved_path):
		peer.close()
		return ERR_FILE_CORRUPT
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = true
	stage = "lobby"
	status = "Все игроки должны подключиться и подтвердить готовность."
	responder = PacketPeerUDP.new()
	if responder.bind(DISCOVERY_PORT, "0.0.0.0") != OK:
		responder = null
		status += " Поиск LAN занят другим хостом; подключайтесь по адресу."
	broadcast_lobby()
	return OK

func join_room(address: String, nickname: String, game_port: int = DEFAULT_PORT) -> Error:
	mods.target = {"kind": "lan", "address": address, "name": nickname, "port": game_port}
	if not str(Engine.get_meta("atlas_mods", "")).is_empty() and not Engine.get_meta("atlas_network_mode", false): return ERR_UNAVAILABLE
	if active or address.strip_edges().is_empty() or address.length() > 255 or game_port < 1024 or game_port > 65535: return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address.strip_edges(), game_port, 2)
	if error != OK: return error
	player_name = clean_name(nickname)
	directory_client = false
	active = true
	hosting = false
	stage = "connecting"
	my_slot = ""
	players = {}
	joining_since = Time.get_ticks_msec()
	multiplayer.multiplayer_peer = peer
	return OK

func clean_name(value: String) -> String:
	var result = value.strip_edges().replace("\n", " ").replace("\r", " ").substr(0, 24)
	return "Игрок" if result.is_empty() else result

func make_player(nickname: String, digest: String, peer_id: int, bot: bool) -> Dictionary:
	var color = COLORS[players.size() % COLORS.size()]
	for candidate in COLORS:
		if not players.values().any(func(p): return p.color == candidate):
			color = candidate
			break
	var home = 0
	while home < COUNTRY_COUNT and not country_available("", home): home += 1
	return {"name": clean_name(nickname), "digest": digest, "peer": peer_id, "bot": bot,
		"connected": bot or peer_id > 0, "ready": bot, "home": mini(home, COUNTRY_COUNT - 1), "color": color}

func country_available(slot: String, country: int) -> bool:
	if country < 0 or country >= COUNTRY_COUNT or country in preload("res://src/game.gd").MICROSTATES: return false
	var claimed = preload("res://src/mod_runtime.gd").start_territories(country)
	for id in players:
		if id != slot and preload("res://src/mod_runtime.gd").start_territories(int(players[id].home)).any(func(territory): return territory in claimed): return false
	if not hosting and active: return not country in occupied
	return world == null or world.owners[country] == "" or world.owners[country] == slot

func has_free_country() -> bool:
	for country in COUNTRY_COUNT:
		if country_available("", country): return true
	return false

func slot_for_peer(peer_id: int) -> String:
	for slot in players:
		if players[slot].peer == peer_id and players[slot].connected and not players[slot].bot: return slot
	return ""

@rpc("any_peer", "call_remote", "reliable")
func _hello(nickname: String, token: String, wants_directory: bool = false, version: int = WIRE_VERSION, mod_hashes: Array = []) -> void:
	var sender = multiplayer.get_remote_sender_id()
	if directory != null:
		directory.hello(sender, nickname, token, wants_directory, version, mod_hashes)
		return
	if not hosting or not active: return
	if sender <= 1 or not multiplayer.get_peers().has(sender): return
	if version != WIRE_VERSION or not valid_token(token) or not mods.hashes_valid(mod_hashes):
		_reject_peer(sender, "Incompatible mod protocol")
		return
	if mod_hashes != mods.hashes():
		mods.offer(sender)
		return
	accept_player(sender, nickname, token)

func accept_player(sender: int, nickname: String, token: String) -> bool:
	if nickname.length() > 64 or not valid_token(token):
		_reject_peer(sender, "Неверные данные подключения.")
		return false
	var digest = token.sha256_text()
	if digest in banned:
		_reject_peer(sender, "Хост удалил ваше место из этого лобби.")
		return false
	var slot = ""
	for id in players:
		if players[id].digest == digest and not players[id].bot: slot = id
	if slot != "" and players[slot].connected:
		_reject_peer(sender, "Этот профиль уже подключён к лобби.")
		return false
	if slot == "":
		if players.size() >= MAX_PLAYERS:
			_reject_peer(sender, "Лобби заполнено.")
			return false
		if not has_free_country():
			_reject_peer(sender, "В этом матче не осталось свободных стартовых стран.")
			return false
		slot = digest.substr(0, 16)
		if players.has(slot):
			_reject_peer(sender, "Конфликт профиля.")
			return false
		players[slot] = make_player(nickname, digest, sender, false)
	else:
		players[slot].peer = sender
		players[slot].connected = true
		players[slot].name = clean_name(nickname)
	to_lobby("Игрок подключился. Подтвердите готовность для начала или продолжения партии.")
	return true

func _reject_peer(id: int, reason: String) -> void:
	if can_send(id): channel()._rejected.rpc_id(id, reason)
	if multiplayer.get_peers().has(id): peer.disconnect_peer(id)

@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	shutdown(reason.substr(0, 180))

func request(action: String, args: Array = []) -> bool:
	if not active or my_slot.is_empty(): return false
	if php != null: return php.enqueue("game", args, action)
	if hosting: return apply_request(1, action, args)
	_request.rpc_id(1, action, args)
	return true

@rpc("any_peer", "call_remote", "reliable")
func _request(action: String, args: Array) -> void:
	if directory != null:
		directory.game_request(multiplayer.get_remote_sender_id(), action, args)
		return
	if hosting: apply_request(multiplayer.get_remote_sender_id(), action, args)

func apply_request(sender: int, action: String, args: Array) -> bool:
	var slot = slot_for_peer(sender)
	if slot.is_empty() or action.length() > 24 or args.size() > 2: return false
	var now = Time.get_ticks_msec()
	var limit = rate_limits.get(sender, {"time": now, "count": 0})
	if now - limit.time > 1000: limit = {"time": now, "count": 0}
	limit.count += 1
	rate_limits[sender] = limit
	if limit.count > 30: return false
	if action == "lobby":
		to_lobby("Игра приостановлена участником. Для продолжения нужна готовность всех игроков.")
		return true
	if stage == "game":
		var accepted = world.command(slot, action, args)
		if accepted: send_views()
		return accepted
	if stage != "lobby": return false
	match action:
		"choose":
			if args.size() != 1 or not args[0] is int or not country_available(slot, args[0]): return false
			if world != null and world.factions.has(slot): return false
			players[slot].home = args[0]
			players[slot].ready = false
		"color":
			if args.size() != 1 or not args[0] is String or not args[0] in COLORS: return false
			if players.keys().any(func(id): return id != slot and players[id].color == args[0]): return false
			players[slot].color = args[0]
			if world != null and world.factions.has(slot): world.factions[slot].player_color = Color(args[0])
			players[slot].ready = false
		"ready":
			if args.size() != 1 or not args[0] is bool: return false
			players[slot].ready = args[0]
		"bot":
			var count = args[0] if args.size() == 1 else 1
			if slot != host_slot or args.size() > 1 or not count is int or count < 1 or count > MAX_PLAYERS - players.size(): return false
			var free = 0
			for country in COUNTRY_COUNT:
				if country_available("", country): free += 1
			if count > free: return false
			for i in count:
				var bot_id = "bot_" + Crypto.new().generate_random_bytes(6).hex_encode()
				players[bot_id] = make_player("Бот %d" % players.size(), "", 0, true)
		"kick":
			if slot != host_slot or args.size() != 1 or not args[0] is String or args[0] == host_slot or not players.has(args[0]): return false
			var removed = players[args[0]]
			if not removed.digest.is_empty(): banned.append(removed.digest)
			if banned.size() > 128: banned.pop_front()
			players.erase(args[0])
			if world != null: world.remove_faction(args[0])
			if removed.peer > 1: _reject_peer(removed.peer, "Хост удалил вас из лобби.")
		"start":
			if slot != host_slot or not start_error().is_empty(): return false
			if world == null: world = World.new()
			for id in players:
				if not world.factions.has(id) and not world.add_faction(id, int(players[id].home), players[id].color): return false
			stage = "game"
			step_time = 0
			var error = save_match()
			if error != OK: notice.emit("Ошибка сохранения сетевой партии: " + error_string(error))
			broadcast_lobby()
			send_views()
			return true
		_: return false
	if dedicated_room:
		var error = save_match()
		if error != OK: notice.emit("Ошибка сохранения: " + error_string(error))
	broadcast_lobby()
	return true

func start_error() -> String:
	if players.size() < 2: return "Добавьте хотя бы одного игрока или бота."
	for p in players.values():
		if not p.connected: return "Ожидается возвращение отключившихся игроков. Можно удалить их места."
		if not p.ready: return "Не все игроки готовы."
	return ""

func to_lobby(reason: String) -> void:
	stage = "lobby"
	step_time = 0
	status = reason
	for p in players.values(): p.ready = p.bot
	if world != null or dedicated_room:
		var error = save_match()
		if error != OK: notice.emit("Ошибка сохранения сетевой партии: " + error_string(error))
	broadcast_lobby()

func _peer_left(id: int) -> void:
	mods.offers.erase(id)
	mods.last_sent.erase(id)
	if directory != null:
		directory.disconnected(id)
		return
	if not active or not hosting: return
	var slot = slot_for_peer(id)
	if slot.is_empty(): return
	players[slot].connected = false
	players[slot].peer = 0
	players[slot].ready = false
	if dedicated_room and slot == host_slot:
		for candidate in players:
			if players[candidate].connected and not players[candidate].bot:
				host_slot = candidate
				break
	to_lobby("Игрок отключился. Партия сохранена и ожидает участников в лобби.")

func broadcast_lobby() -> void:
	if not hosting: return
	var public = {}
	for slot in players:
		public[slot] = players[slot].duplicate()
		public[slot].erase("digest")
	var data = {"players": public, "host": host_slot, "name": lobby_name, "room": room_id, "stage": stage, "status": status,
		"port": port, "resuming": world != null, "homes_locked": world.factions.keys() if world != null else [], "occupied": []}
	if dedicated_room: data.quality = true
	if world != null:
		for i in COUNTRY_COUNT:
			if world.owners[i] != "": data.occupied.append(i)
	for slot in players:
		if players[slot].bot or not players[slot].connected: continue
		var packet = data.duplicate(true)
		packet.slot = slot
		if players[slot].peer > 1 and can_send(players[slot].peer): channel()._lobby_update.rpc_id(players[slot].peer, packet)
	my_slot = host_slot
	lobby_changed.emit()

var homes_locked: Array = []
func locked(slot: String) -> bool:
	return world.factions.has(slot) if hosting and world != null else slot in homes_locked

@rpc("authority", "call_remote", "reliable")
func _lobby_update(data: Dictionary) -> void:
	if not data.get("players") is Dictionary or data.players.size() > MAX_PLAYERS or not data.get("stage") in ["lobby", "game"]: return
	for slot in data.players:
		if not valid_player(slot, data.players[slot], false): return
	if not data.players.has(data.get("slot", "")) or not data.players.has(data.get("host", "")): return
	if stage != data.stage or room_id != data.get("room", ""): reset_quality()
	players = data.players
	my_slot = data.slot
	host_slot = data.host
	lobby_name = str(data.get("name", "Лобби")).substr(0, 40)
	room_id = str(data.get("room", "")).substr(0, 16)
	status = str(data.get("status", "")).substr(0, 200)
	stage = data.stage
	quality_supported = data.get("quality") == true
	resuming = data.get("resuming", false) == true
	homes_locked = data.get("homes_locked", []) if data.get("homes_locked") is Array else []
	occupied = data.get("occupied", []) if data.get("occupied") is Array else []
	lobby_changed.emit()

func send_views() -> void:
	if not hosting or stage != "game" or world == null: return
	for slot in players:
		if players[slot].bot or not players[slot].connected: continue
		if players[slot].peer > 1 and not can_send(players[slot].peer): continue
		var data = world.view(slot, players)
		if players[slot].peer == 1: view_received.emit(data)
		else: channel()._view_update.rpc_id(players[slot].peer, data)

@rpc("authority", "call_remote", "reliable")
func _view_update(data: Dictionary) -> void:
	if active and stage == "game": view_received.emit(data)

func valid_player(slot: Variant, p: Variant, private: bool) -> bool:
	if not slot is String or slot.length() < 1 or slot.length() > 32 or not p is Dictionary: return false
	if not p.get("name") is String or p.name.length() > 24 or not p.get("color") in COLORS: return false
	if not p.get("home") is int and not p.get("home") is float: return false
	if p.home < 0 or p.home >= COUNTRY_COUNT or p.home != floorf(p.home): return false
	for key in ["bot", "connected", "ready"]:
		if not p.get(key) is bool: return false
	if not p.get("peer") is int and not p.get("peer") is float: return false
	if p.peer < 0 or p.peer > 2147483647 or p.peer != floorf(p.peer): return false
	if private and (not p.get("digest") is String or (not p.digest.is_empty() and (p.digest.length() != 64 or not p.digest.is_valid_hex_number()))): return false
	return true

func save_path() -> String:
	return save_directory.path_join("session_" + room_id + ".json")

func save_match() -> Error:
	if not hosting or (world == null and not dedicated_room): return OK
	var error = DirAccess.make_dir_recursive_absolute(save_directory)
	if error != OK: return error
	var data = {"version": 1, "room": room_id, "name": lobby_name, "host": host_slot, "players": players,
		"mods": mods.hashes(), "world": world.export_data() if world != null else null, "dedicated": dedicated_room, "banned": banned}
	var file = FileAccess.open(save_path() + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK: return error
	if FileAccess.file_exists(save_path()):
		error = DirAccess.copy_absolute(save_path(), save_path() + ".bak")
		if error != OK: return error
	return DirAccess.rename_absolute(save_path() + ".tmp", save_path())

func restore_match(path: String) -> bool:
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return false
	var data = parser.data
	if not data is Dictionary or data.get("version") != 1 or not data.get("players") is Dictionary or data.players.size() < (1 if dedicated_room else 2) or data.players.size() > MAX_PLAYERS: return false
	if data.get("mods", []) != mods.hashes(): return false
	if dedicated_room != (data.get("dedicated", false) == true): return false
	if not data.get("room") is String or data.room.length() != 16 or not data.room.is_valid_hex_number() or not data.get("name") is String or data.name.length() > 40: return false
	for slot in data.players:
		if not valid_player(slot, data.players[slot], true): return false
	if not data.players.has(data.get("host", "")) or data.players[data.host].bot: return false
	var saved_bans = data.get("banned", [])
	if not saved_bans is Array or saved_bans.size() > 128: return false
	for digest in saved_bans:
		if not digest is String or digest.length() != 64 or not digest.is_valid_hex_number(): return false
	var restored: RefCounted
	if data.get("world") != null:
		restored = World.new()
		if not restored.restore_data(data.get("world"), data.players): return false
	elif not dedicated_room: return false
	players = data.players
	world = restored
	room_id = data.room
	lobby_name = data.name
	host_slot = data.host
	my_slot = host_slot
	banned = saved_bans
	for slot in players:
		players[slot].peer = 0
		players[slot].connected = players[slot].bot
		players[slot].ready = players[slot].bot
	if not dedicated_room:
		players[host_slot].digest = identity_token.sha256_text()
		players[host_slot].peer = 1
		players[host_slot].connected = true
	return true

func saved_matches() -> Array:
	var result: Array = []
	var dir = DirAccess.open(save_directory)
	if dir == null: return result
	for file in dir.get_files():
		if not file.ends_with(".json"): continue
		var path = save_directory.path_join(file)
		var parser = JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: continue
		var data = parser.data
		if data.get("version") != 1 or not data.get("name") is String or not data.get("world") is Dictionary: continue
		var elapsed = data.world.get("elapsed", 0)
		if not elapsed is float and not elapsed is int: continue
		if not is_finite(elapsed) or elapsed < 0 or elapsed > 100000000: continue
		result.append({"path": path, "name": data.name.substr(0, 40), "elapsed": int(elapsed), "modified": FileAccess.get_modified_time(path)})
	result.sort_custom(func(a, b): return a.modified > b.modified)
	return result

func scan_lan() -> Error:
	if browser != null: browser.close()
	browser = PacketPeerUDP.new()
	var error = browser.bind(0, "0.0.0.0")
	if error != OK: return error
	browser.set_broadcast_enabled(true)
	found.clear()
	scan_time = 0
	query_lan()
	discovery_changed.emit()
	return OK

func stop_scan() -> void:
	if browser != null: browser.close()
	browser = null

func query_lan() -> void:
	for address in ["255.255.255.255", "127.0.0.1"]:
		if browser.set_dest_address(address, DISCOVERY_PORT) == OK:
			browser.put_packet("ATLAS_DISCOVER_V1".to_utf8_buffer())

func _process(delta: float) -> void:
	if directory != null:
		directory.tick(delta)
		return
	if active and directory_client and php == null and stage == "lobby" and quality_supported:
		poll_quality(Time.get_ticks_msec())
	if active and not hosting and stage == "connecting" and Time.get_ticks_msec() - joining_since > 12000: shutdown("Время подключения истекло. Проверьте адрес и порт.")
	if hosting and active and stage == "game":
		step_time += delta
		if step_time >= 1:
			step_time -= 1
			var bots = players.keys().filter(func(slot): return players[slot].bot)
			world.tick(bots)
			send_views()
			if world.elapsed % 15 == 0:
				var error = save_match()
				if error != OK: notice.emit("Ошибка сетевого автосохранения: " + error_string(error))
	if responder != null:
		for i in mini(16, responder.get_available_packet_count()):
			var packet = responder.get_packet()
			var address = responder.get_packet_ip()
			var sender_port = responder.get_packet_port()
			if packet.size() != 17 or packet.get_string_from_utf8() != "ATLAS_DISCOVER_V1": continue
			var now = Time.get_ticks_msec()
			if now - discovery_limits.get(address, -1000) < 800: continue
			if discovery_limits.size() > 64: discovery_limits.clear()
			discovery_limits[address] = now
			var data = {"protocol": 1, "room": room_id, "name": lobby_name, "port": port, "players": players.size(), "stage": stage}
			if responder.set_dest_address(address, sender_port) == OK: responder.put_packet(JSON.stringify(data).to_utf8_buffer())
	if browser != null:
		scan_time += delta
		if scan_time >= 1:
			scan_time = 0
			query_lan()
		for i in mini(16, browser.get_available_packet_count()):
			var packet = browser.get_packet()
			var address = browser.get_packet_ip()
			if packet.size() > 1024: continue
			var parser = JSON.new()
			if parser.parse(packet.get_string_from_utf8()) != OK: continue
			var data = parser.data
			if not data is Dictionary or data.get("protocol") != 1 or not data.get("name") is String or data.name.length() > 40: continue
			if not data.get("port") is float and not data.get("port") is int: continue
			if data.port < 1024 or data.port > 65535 or data.port != floorf(data.port): continue
			if not data.get("players") is float and not data.get("players") is int: continue
			if data.players < 1 or data.players > MAX_PLAYERS or data.players != floorf(data.players): continue
			if not data.get("room") is String or data.room.length() != 16 or not data.room.is_valid_hex_number(): continue
			if not data.get("stage") in ["lobby", "game"]: continue
			data.address = address
			data.seen = Time.get_ticks_msec()
			var index = found.find_custom(func(item): return item.room == data.room)
			if index < 0:
				if found.size() < 32:
					found.append(data)
					discovery_changed.emit()
			else:
				var changed = found[index].players != data.players or found[index].stage != data.stage or found[index].name != data.name
				found[index] = data
				if changed: discovery_changed.emit()
		var old_size = found.size()
		found = found.filter(func(item): return Time.get_ticks_msec() - item.seen < 5000)
		if old_size != found.size(): discovery_changed.emit()

func shutdown(reason: String = "Вы покинули лобби.") -> void:
	mods.cancel()
	if php != null:
		php.close()
		php.queue_free()
		php = null
	if directory != null: directory.stop()
	if hosting and world != null: save_match()
	active = false
	hosting = false
	directory_client = false
	stage = "offline"
	reset_quality()
	if peer != null: peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if responder != null: responder.close()
	responder = null
	stop_scan()
	world = null
	closed.emit(reason)

func _exit_tree() -> void:
	if transport != null: return
	if php != null: php.close(false)
	if directory != null: directory.stop()
	active = false
	if peer != null: peer.close()
	if responder != null: responder.close()
	if browser != null: browser.close()

@rpc("authority", "call_remote", "reliable")
func _mod_offer(profile: Array) -> void:
	mods.receive_offer(profile)

@rpc("any_peer", "call_remote", "reliable")
func _mod_chunk_request(hash: String, offset: int) -> void:
	if hosting or directory != null: mods.send_chunk(multiplayer.get_remote_sender_id(), hash, offset)

@rpc("authority", "call_remote", "reliable")
func _mod_chunk(hash: String, offset: int, bytes: PackedByteArray) -> void:
	if active: mods.receive_chunk(hash, offset, bytes)
