extends Node

const L = preload("res://src/i18n.gd")

var net: Node
var http: HTTPRequest
var endpoint = ""
var session = ""
var pending: Array = []
var current: Dictionary = {}
var sequence = 0
var busy = false
var stopped = false
var next_poll = 0
var poll_ms = 1000
var last_success = 0
var lobby_signature = ""

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 8
	http.body_size_limit = 2097152
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(completed)
	last_success = Time.get_ticks_msec()
	current = {"action": "connect", "name": net.player_name, "token": net.login_token(),
		"nonce": Crypto.new().generate_random_bytes(16).hex_encode(), "protocol": 2}

func enqueue(action: String, args: Array = [], command: String = "") -> bool:
	if stopped or pending.size() >= 16 or session.is_empty(): return false
	if action == "list": next_poll = 0; return true
	sequence += 1
	var item = {"action": action, "args": args, "seq": sequence}
	if not command.is_empty(): item.command = command
	pending.append(item)
	return true

func _process(_delta: float) -> void:
	if stopped or not net.active or busy: return
	var now = Time.get_ticks_msec()
	if now - last_success > 15000:
		net.shutdown(L.text("PHP-сервер не отвечает. Партия сохранится; подключитесь повторно."))
		return
	if now < next_poll: return
	if current.is_empty(): current = pending[0].duplicate(true) if not pending.is_empty() else {"action": "poll"}
	var body = current.duplicate(true)
	if not session.is_empty(): body.session = session
	busy = true
	var error = http.request(endpoint, ["Content-Type: application/json", "Accept: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		busy = false
		next_poll = now + 1000

func numbers(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 1e15: return int(value)
	if value is Array:
		for i in value.size(): value[i] = numbers(value[i])
	elif value is Dictionary:
		for key in value: value[key] = numbers(value[key])
	return value

func completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if stopped or not net.active: return
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500:
		next_poll = Time.get_ticks_msec() + 1000
		return
	var parser = JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		net.shutdown(L.text("PHP-сервер вернул неверный ответ. Проверьте адрес и настройку PHP."))
		return
	var data = numbers(parser.data)
	if code != 200 or data.get("ok") != true:
		net.shutdown(str(data.get("error", L.text("Ошибка PHP-сервера"))).substr(0, 200))
		return
	if current.action == "connect":
		if not data.get("session") is String or data.session.length() != 64 or not data.session.is_valid_hex_number():
			net.shutdown(L.text("Несовместимое подключение к PHP-серверу."))
			return
		session = data.session
	elif current.has("seq"):
		if not data.get("ack") is int or data.ack < current.seq: return
		pending.pop_front()
	current = {}
	last_success = Time.get_ticks_msec()
	if data.get("poll_ms") is int: poll_ms = clampi(data.poll_ms, 750, 5000)
	next_poll = last_success + (poll_ms if pending.is_empty() else 0)
	if data.has("error"): net.notice.emit(str(data.error).substr(0, 200))
	if data.get("mode") == "directory" and data.get("directory") is Dictionary:
		lobby_signature = ""
		net._directory_update(data.directory)
	elif data.get("mode") in ["lobby", "game"] and data.get("lobby") is Dictionary:
		var signature = JSON.stringify(data.lobby)
		if signature != lobby_signature or net.stage != data.mode:
			lobby_signature = signature
			net._lobby_update(data.lobby)
		if data.mode == "game" and data.get("view") is Dictionary: net.view_received.emit(data.view)
	else: net.shutdown(L.text("Несовместимое состояние PHP-сервера."))

func close(send_logout: bool = true) -> void:
	stopped = true
	if http != null: http.cancel_request()
	if not send_logout or session.is_empty() or not is_inside_tree(): return
	var logout = HTTPRequest.new()
	logout.timeout = 5
	logout.max_redirects = 0
	get_parent().add_child(logout)
	logout.request_completed.connect(func(_a, _b, _c, _d): logout.queue_free())
	var error = logout.request(endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"action": "disconnect", "session": session}))
	if error != OK: logout.queue_free()
