extends SceneTree

const Session = preload("res://src/network_session.gd")
var net: Node
var latest: Dictionary = {}
var checks = 0
var folder = ""
var role = ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		push_error("FAIL: " + text)
		quit(1)

func until(condition: Callable, text: String) -> void:
	var deadline = Time.get_ticks_msec() + 25000
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			push_error("TIMEOUT " + role + ": " + text)
			quit(1)
			return
		await process_frame

func mark(value: String) -> void:
	var file = FileAccess.open(folder.path_join(value), FileAccess.WRITE)
	file.store_string("ok")
	file.close()

func marked(value: String) -> bool:
	return FileAccess.file_exists(folder.path_join(value))

func connect_server() -> void:
	latest = {}
	var error = net.join_php("http://127.0.0.1:30761", role) if OS.get_environment("ATLAS_PHP_TEST") == "1" else net.join_directory("ws://127.0.0.1:30760", role)
	check(error == OK, "Connect to server transport")
	await until(func(): return net.stage == "directory", "Server directory")

func enter_named(title: String) -> void:
	await until(func(): return net.directory_rooms.any(func(r): return r.name == title), "Find room " + title)
	var entry = net.directory_rooms.filter(func(r): return r.name == title)[0]
	latest = {}
	net.directory_request("join", [entry.id])
	await until(func(): return net.stage == "lobby", "Join " + title)

func leave_room() -> void:
	net.directory_request("leave")
	await until(func(): return net.stage == "directory", "Leave room")

func start_with_bot(title: String) -> void:
	net.directory_request("create", [title])
	await until(func(): return net.stage == "lobby", "Create " + title)
	check(net.is_admin() and net.my_slot == net.host_slot, "Remote creator administers room")
	net.request("bot")
	await until(func(): return net.players.size() == 2, "Bot added remotely")
	net.request("ready", [true])
	net.request("start")
	await until(func(): return net.stage == "game" and not latest.is_empty(), "Start " + title)
	check(latest.game.units == [35, 8, 4] and latest.game.coins == 180, "VPS equal starting resources")

func run() -> void:
	role = "Admin" if "admin" in OS.get_cmdline_user_args() else "Guest"
	folder = OS.get_environment("ATLAS_TEST_DIR")
	var atlas = Node.new()
	atlas.name = "Atlas"
	root.add_child(atlas)
	net = Session.new()
	net.identity_token = ("5" if role == "Admin" else "6").repeat(48)
	atlas.add_child(net)
	net.view_received.connect(func(data): latest = data)
	net.notice.connect(func(text): print("NOTICE: ", text))
	check(net.join_directory("ws://example.com:30760", role) == ERR_INVALID_PARAMETER, "Reject unencrypted remote server")
	await connect_server()
	if role == "Admin": await admin_flow()
	else: await guest_flow()
	if net.active: net.shutdown("")
	atlas.queue_free()
	await process_frame
	print("PASS: VPS %s %d checks" % [role, checks])
	quit()

func admin_flow() -> void:
	await start_with_bot("Alpha")
	net.request("recruit", [0])
	await until(func(): return latest.game.units[0] == 45, "Alpha recruits")
	await until(func(): return latest.game.elapsed >= 2, "Authoritative game clock advances")
	mark("alpha_started")
	await until(func(): return marked("beta_started"), "Beta isolation fixture")
	check(latest.game.units[0] == 45 and net.lobby_name == "Alpha", "Second room commands do not alter first room")
	await until(func(): return net.stage == "lobby" and net.players.size() == 3, "Guest joins running match")
	check(not net.start_error().is_empty(), "New arrival resets readiness")
	await until(func(): return net.players.values().any(func(p): return p.name == "Guest" and p.ready), "Guest ready")
	net.request("ready", [true])
	net.request("start")
	await until(func(): return net.stage == "game", "Start with late player")
	await until(func(): return net.stage == "lobby" and net.players.values().any(func(p): return p.name == "Guest" and not p.connected), "Guest disconnect pauses match")
	check(latest.game.units[0] == 45, "Other human economy remains private")
	await leave_room()
	check(net.directory_rooms.size() == 2, "Directory serves multiple rooms")
	net.shutdown("")
	mark("admin_restart_ready")
	await until(func(): return marked("restarted"), "VPS restart")
	await connect_server()
	check(net.directory_rooms.size() == 2 and net.directory_rooms.any(func(r): return r.name == "Alpha" and r.member and r.admin and r.saved), "Room and administrator survive VPS restart")
	await enter_named("Alpha")
	await until(func(): return net.players.values().any(func(p): return p.name == "Guest" and p.ready), "Original guest returns")
	net.request("ready", [true])
	net.request("start")
	await until(func(): return net.stage == "game" and not latest.is_empty(), "Resume server save")
	check(latest.game.units[0] == 45, "Army retained across full server restart")
	mark("alpha_resumed")
	await until(func(): return marked("guest_resumed"), "Guest confirms restoration")
	await leave_room()
	mark("admin_left")
	await until(func(): return marked("complete"), "Guest administers and cleans rooms")

func guest_flow() -> void:
	await until(func(): return marked("alpha_started"), "Alpha exists")
	await start_with_bot("Beta")
	net.request("recruit", [0])
	net.request("recruit", [0])
	await until(func(): return latest.game.units[0] == 55, "Beta separate economy")
	await until(func(): return latest.game.elapsed >= 2, "Independent room clock advances")
	mark("beta_started")
	await leave_room()
	check(net.directory_rooms.size() == 2 and net.directory_rooms.all(func(r): return not r.has("world") and not r.has("digest")), "Public directory contains no private armies or identity secrets")
	await enter_named("Alpha")
	check(not net.is_admin(), "Joining player has no admin privilege")
	var count = net.players.size()
	net.request("bot")
	net.request("ready", [true])
	await until(func(): return net.stage == "game" and not latest.is_empty(), "Late join ready and start")
	check(net.players.size() == count and latest.game.units == [35, 8, 4], "Unauthorized bot command rejected; late join starts minimal")
	net.request("recruit", [0])
	await until(func(): return latest.game.units[0] == 45, "Late player's army develops")
	var original = net.my_slot
	net.shutdown("")
	mark("guest_restart_ready")
	await until(func(): return marked("restarted"), "VPS restart")
	await connect_server()
	await enter_named("Beta")
	check(net.is_admin(), "Independent room administrator retained")
	net.request("ready", [true])
	net.request("start")
	await until(func(): return net.stage == "game" and not latest.is_empty(), "Beta resumes")
	check(latest.game.units[0] >= 55, "Independent room army restored")
	await leave_room()
	await enter_named("Alpha")
	check(net.my_slot == original, "Same profile restores original place")
	net.request("ready", [true])
	await until(func(): return net.stage == "game" and not latest.is_empty(), "Alpha resumes")
	check(latest.game.units[0] == 45, "Late join progress survives restart")
	mark("guest_resumed")
	await until(func(): return marked("admin_left") and net.stage == "lobby" and net.is_admin(), "Admin rights transfer on departure")
	var old_admin = net.players.keys().filter(func(id): return net.players[id].name == "Admin")[0]
	net.request("kick", [old_admin])
	await until(func(): return not net.players.has(old_admin), "New admin can remove disconnected player")
	await leave_room()
	for title in ["Beta", "Alpha"]:
		var entry = net.directory_rooms.filter(func(r): return r.name == title)[0]
		net.directory_request("delete", [entry.id])
		await until(func(): return not net.directory_rooms.any(func(r): return r.name == title), "Delete " + title)
	check(net.directory_rooms.is_empty(), "Admin can delete abandoned server saves")
	mark("complete")
