extends SceneTree

const Session = preload("res://src/network_session.gd")
var net: Node
var latest: Dictionary = {}
var checks = 0
var closing_reason = ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		push_error("FAIL: " + text)
		quit(1)

func until(condition: Callable, text: String) -> void:
	var deadline = Time.get_ticks_msec() + 12000
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			push_error("TIMEOUT: " + text)
			quit(1)
			return
		await process_frame

func run() -> void:
	var host = "host" in OS.get_cmdline_user_args()
	var atlas = Node.new()
	atlas.name = "Atlas"
	root.add_child(atlas)
	net = Session.new()
	net.identity_token = ("1" if host else "2").repeat(48)
	net.save_directory = "user://test_network_transport"
	atlas.add_child(net)
	net.view_received.connect(func(data): latest = data)
	net.closed.connect(func(reason): closing_reason = reason)
	if host: await run_host()
	else: await run_client()
	if net.active: net.shutdown("")
	atlas.queue_free()
	await process_frame
	print("PASS: %s transport %d checks" % ["HOST" if host else "CLIENT", checks])
	quit()

func run_host() -> void:
	check(net.host_room("Transport test", "Host", 29760) == OK, "Host listens")
	await until(func(): return net.players.size() == 2 and net.players.values().all(func(p): return p.peer == 1 or p.ready), "Client joins and readies")
	var other = net.players.keys().filter(func(id): return id != net.host_slot)[0]
	check(not net.players[other].bot, "Real remote player joined")
	check(net.request("ready", [true]) and net.request("start"), "Start with remote readiness")
	await until(func(): return net.world.factions[other].units[0] == 45, "Remote recruit command reaches authority")
	check(net.world.factions[net.host_slot].units[0] == 35, "Client command affects only its own army")
	check(net.save_match() == OK, "Live match saves")
	net.request("lobby")
	await until(func(): return not net.players[other].connected, "Remote disconnect")
	check(net.stage == "lobby" and not net.start_error().is_empty(), "Disconnect pauses and blocks resume")
	var path = net.save_path()
	net.shutdown("")
	check(net.host_room("Resume", "Host", 29760, path) == OK, "Host reopens saved multiplayer session")
	check(not net.players[other].connected and net.world.factions[other].units[0] == 45, "Saved session waits for original player with progress intact")
	await until(func(): return net.players[other].connected and net.players[other].ready, "Same identity returns")
	check(net.players.size() == 2 and net.world.factions[other].units[0] == 45, "Reconnect preserves slot and army")
	net.request("ready", [true])
	check(net.request("start"), "Resume after everyone returns")
	await until(func(): return net.world.factions[other].units[0] == 55, "Reconnected player can act")
	net.request("lobby")
	check(net.request("kick", [other]), "Host kicks remote player")
	check(not net.world.factions.has(other), "Kick removes faction")
	await until(func(): return net.players.size() == 2 and net.players.values().any(func(p): return p.name == "Newcomer" and p.ready), "New player joins saved match")
	var newcomer = net.players.keys().filter(func(id): return id != net.host_slot)[0]
	check(newcomer != other and not net.world.factions.has(newcomer), "New arrival has a new slot")
	net.request("ready", [true])
	check(net.request("start"), "Start with new participant")
	check(net.world.factions[newcomer].units == [35, 8, 4] and net.world.factions[newcomer].coins == 180, "New participant receives minimum resources")
	await until(func(): return net.world.factions[newcomer].units[0] == 45, "New participant commands work")
	await until(func(): return not net.players[newcomer].connected, "Client finished")
	check(net.save_match() == OK, "Save after disconnect")

func run_client() -> void:
	check(net.scan_lan() == OK, "LAN scan starts")
	await until(func(): return net.found.any(func(item): return item.port == 29760), "LAN query discovers real host")
	check(net.found.any(func(item): return item.name == "Transport test"), "Discovery metadata decoded")
	net.stop_scan()
	check(net.join_room("127.0.0.1", "Veteran", 29760) == OK, "ENet connects")
	await until(func(): return net.stage == "lobby" and not net.my_slot.is_empty(), "Welcome roster")
	var original = net.my_slot
	check(not net.players.values().any(func(p): return p.has("digest")), "Public lobby excludes identity secrets")
	net.request("ready", [true])
	await until(func(): return net.stage == "game" and not latest.is_empty(), "First game view")
	check(latest.game.units == [35, 8, 4] and latest.game.countries[0].units == [0, 0, 0], "Client sees private view only")
	net.request("recruit", [0])
	await until(func(): return net.stage == "lobby", "Host pauses")
	net.shutdown("")
	await create_timer(0.4).timeout
	latest = {}
	net.join_room("127.0.0.1", "Veteran", 29760)
	await until(func(): return net.stage == "lobby" and not net.my_slot.is_empty(), "Reconnect handshake")
	check(net.my_slot == original, "Identity restores old slot")
	net.request("ready", [true])
	await until(func(): return net.stage == "game" and not latest.is_empty(), "Resumed game view")
	check(latest.game.units[0] == 45, "Progress restored on client")
	net.request("recruit", [0])
	await until(func(): return not net.active, "Kicked client disconnects")
	check(not closing_reason.is_empty(), "Kick or disconnect reason reaches client")
	net.identity_token = "3".repeat(48)
	latest = {}
	check(net.join_room("127.0.0.1", "Newcomer", 29760) == OK, "New profile connects")
	await until(func(): return net.stage == "lobby" and not net.my_slot.is_empty(), "Late join lobby")
	check(net.my_slot != original, "New profile receives new slot")
	net.request("ready", [true])
	await until(func(): return net.stage == "game" and not latest.is_empty(), "Late join game view")
	check(latest.game.units == [35, 8, 4], "Late join starts equally")
	net.request("recruit", [0])
	await until(func(): return latest.game.units[0] == 45, "Late command acknowledged")
	net.shutdown("")
