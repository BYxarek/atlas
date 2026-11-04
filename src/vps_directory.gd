extends RefCounted

var hub: Node
var data_path = "user://server"
var max_rooms = 8
var rooms: Dictionary = {}
var users: Dictionary = {}
var pending: Dictionary = {}
var limits: Dictionary = {}
var refresh_time = 0.0
var stopped = false

func restore_rooms() -> Error:
	var error = DirAccess.make_dir_recursive_absolute(data_path)
	if error != OK: return error
	var probe = FileAccess.open(data_path.path_join(".write-test"), FileAccess.WRITE)
	if probe == null: return FileAccess.get_open_error()
	probe.close()
	DirAccess.remove_absolute(data_path.path_join(".write-test"))
	var folder = DirAccess.open(data_path)
	for filename in folder.get_files():
		if not filename.begins_with("session_") or not filename.ends_with(".json"): continue
		var room = make_room()
		if rooms.size() >= max_rooms or not room.restore_match(data_path.path_join(filename)) or rooms.has(room.room_id):
			push_error("Cannot load server room: " + filename + ". File preserved; check backup or room limit.")
			room.queue_free()
			continue
		room.stage = "lobby"
		room.status = "Сервер восстановил партию. Ожидаем возвращения и готовности участников."
		rooms[room.room_id] = room
	return OK

func make_room() -> Node:
	var room = load("res://src/network_session.gd").new()
	room.transport = hub
	room.peer = hub.peer
	room.dedicated_room = true
	room.hosting = true
	room.active = true
	room.save_directory = data_path
	room.name = "Room_" + Crypto.new().generate_random_bytes(8).hex_encode()
	hub.add_child(room)
	room.notice.connect(func(text):
		push_error(text)
		for p in room.players.values():
			if not p.bot and p.connected and hub.can_send(p.peer): hub._directory_notice.rpc_id(p.peer, text))
	return room

func connected(id: int) -> void:
	if pending.size() + users.size() >= max_rooms * 8 + 16:
		hub.peer.disconnect_peer(id)
		return
	pending[id] = Time.get_ticks_msec()

func hello(id: int, nickname: String, token: String, wants_directory: bool, version: int) -> void:
	if id <= 1 or users.has(id): return
	if not wants_directory or version != hub.WIRE_VERSION or nickname.length() > 64 or not hub.valid_token(token):
		hub._reject_peer(id, "Нужна совместимая версия ATLAS и подключение к VPS-серверу.")
		return
	var digest = token.sha256_text()
	if users.values().any(func(user): return user.digest == digest):
		hub._reject_peer(id, "Этот профиль уже подключён к серверу.")
		return
	pending.erase(id)
	users[id] = {"name": hub.clean_name(nickname), "token": token, "digest": digest, "room": "", "created": -10000}
	send_list(id, true)

func request(id: int, action: String, args: Array) -> void:
	if not users.has(id) or action.length() > 16 or args.size() > 1: return
	var now = Time.get_ticks_msec()
	var limit = limits.get(id, {"time": now, "count": 0})
	if now - limit.time >= 1000: limit = {"time": now, "count": 0}
	limit.count += 1
	limits[id] = limit
	if limit.count > 10: return
	var user = users[id]
	if action == "leave":
		leave_room(id)
		send_list(id, true)
		return
	if not user.room.is_empty(): return
	match action:
		"list": send_list(id)
		"create":
			if args.size() != 1 or not args[0] is String or args[0].length() > 40: return
			if rooms.size() >= max_rooms:
				fail(id, "Сервер заполнен. Удалите свою старую комнату или выберите другой сервер.")
				return
			if now - user.created < 10000:
				fail(id, "Подождите несколько секунд перед созданием новой комнаты.")
				return
			var room = make_room()
			room.room_id = Crypto.new().generate_random_bytes(8).hex_encode()
			room.lobby_name = args[0].strip_edges().replace("\n", " ").replace("\r", " ")
			if room.lobby_name.is_empty(): room.lobby_name = "Партия ATLAS"
			room.host_slot = user.digest.substr(0, 16)
			room.my_slot = room.host_slot
			room.players[room.host_slot] = room.make_player(user.name, user.digest, id, false)
			room.stage = "lobby"
			room.status = "Комната работает на VPS. Добавьте ботов или пригласите игроков."
			var error = room.save_match()
			if error != OK:
				room.queue_free()
				fail(id, "Не удалось сохранить комнату: " + error_string(error))
				return
			rooms[room.room_id] = room
			user.room = room.room_id
			user.created = now
			room.broadcast_lobby()
		"join":
			if args.size() != 1 or not args[0] is String or not rooms.has(args[0]):
				fail(id, "Комната не найдена.")
				return
			var room = rooms[args[0]]
			var existing = room.players.values().any(func(p): return p.digest == user.digest and not p.bot)
			if user.digest in room.banned or (not existing and (room.players.size() >= 8 or not room.has_free_country())):
				fail(id, "В комнате нет свободного места или ваш профиль был удалён.")
				return
			if room.accept_player(id, user.name, user.token): user.room = args[0]
		"delete":
			if args.size() != 1 or not args[0] is String or not rooms.has(args[0]): return
			var room = rooms[args[0]]
			if room.players[room.host_slot].digest != user.digest:
				fail(id, "Удалить комнату может только её администратор.")
				return
			if room.players.values().any(func(p): return p.connected and not p.bot):
				fail(id, "Все игроки должны выйти из комнаты перед удалением.")
				return
			var error = DirAccess.remove_absolute(room.save_path())
			if error != OK:
				fail(id, "Не удалось удалить сохранение: " + error_string(error))
				return
			for suffix in [".bak", ".tmp"]:
				if FileAccess.file_exists(room.save_path() + suffix): DirAccess.remove_absolute(room.save_path() + suffix)
			room.active = false
			rooms.erase(args[0])
			room.queue_free()
			send_list(id)

func fail(id: int, text: String) -> void:
	if hub.can_send(id): hub._directory_notice.rpc_id(id, text)

func game_request(id: int, action: String, args: Array) -> void:
	if users.has(id) and rooms.has(users[id].room): rooms[users[id].room].apply_request(id, action, args)

func leave_room(id: int) -> void:
	if not users.has(id): return
	var room_id = users[id].room
	users[id].room = ""
	if rooms.has(room_id): rooms[room_id]._peer_left(id)

func disconnected(id: int) -> void:
	leave_room(id)
	users.erase(id)
	pending.erase(id)
	limits.erase(id)

func send_list(id: int, browse: bool = false) -> void:
	if not users.has(id) or not hub.can_send(id): return
	var result = []
	for room in rooms.values():
		result.append({"id": room.room_id, "name": room.lobby_name, "players": room.players.size(), "stage": room.stage,
			"elapsed": room.world.elapsed if room.world != null else 0, "saved": room.world != null,
			"member": room.players.values().any(func(p): return not p.bot and p.digest == users[id].digest),
			"admin": room.players[room.host_slot].digest == users[id].digest})
	hub._directory_update.rpc_id(id, {"rooms": result, "browse": browse, "status": "Комнаты: %d / %d" % [rooms.size(), max_rooms]})

func tick(delta: float) -> void:
	if stopped: return
	for id in pending.keys():
		if Time.get_ticks_msec() - pending[id] > 10000:
			pending.erase(id)
			hub.peer.disconnect_peer(id)
	refresh_time += delta
	if refresh_time >= 2:
		refresh_time = 0
		for id in users:
			if users[id].room.is_empty(): send_list(id)

func stop() -> void:
	if stopped: return
	stopped = true
	for room in rooms.values():
		var error = room.save_match()
		if error != OK: push_error("Cannot save server room: " + error_string(error))
		room.active = false
