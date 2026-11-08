extends SceneTree

const Mods = preload("res://src/mods.gd")
var net: Node
var folder: String
var kind: String
var role: String
var latest: Dictionary = {}
var downloaded = false
var offer_seen = false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		push_error("FAIL: " + message)
		quit(1)

func until(condition: Callable, message: String) -> void:
	var deadline = Time.get_ticks_msec() + 20000
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			push_error("TIMEOUT: " + message)
			quit(1)
			return
		await process_frame

func run() -> void:
	var args = OS.get_cmdline_user_args()
	role = args[0]
	kind = args[1]
	folder = OS.get_environment("ATLAS_TEST_DIR")
	Mods.network_boot_path = folder.path_join("client_boot.json")
	if role in ["host", "resume"]:
		check(Mods.new().activate_network(), "Activate common network package")
	var atlas = Node.new()
	atlas.name = "Atlas"
	root.add_child(atlas)
	net = load("res://src/network_session.gd").new()
	net.identity_token = ("1" if role == "host" else "2").repeat(48)
	net.save_directory = folder.path_join("saves")
	atlas.add_child(net)
	net.mods.cache = OS.get_environment("ATLAS_MODS_DIR").path_join("cache")
	net.view_received.connect(func(data): latest = data)
	net.mods.required.connect(func(_profile): offer_seen = true)
	net.mods.downloaded.connect(func(): downloaded = true)
	net.mods.failed.connect(func(message): check(false, message))
	if role == "host":
		check((net.host_room("Mods", "Host", 31760) if kind == "lan" else net.host_directory(31760, folder.path_join("server"))) == OK, "Start modded host")
		FileAccess.open(folder.path_join("listening"), FileAccess.WRITE).close()
		if kind == "lan":
			await until(func(): return net.players.size() == 2 and net.players.values().all(func(p): return p.peer == 1 or p.ready), "Verified client joins")
			check(net.request("ready", [true]) and net.request("start"), "Start verified modded game")
		await until(func(): return FileAccess.file_exists(folder.path_join("done")), "Client receives game")
	else:
		var nonce = ""
		if role == "resume": nonce = JSON.parse_string(FileAccess.get_file_as_string(Mods.network_boot_path)).target.get("nonce", "")
		var error = net.join_room("127.0.0.1", "Client", 31760) if kind == "lan" else (net.join_php("http://127.0.0.1:31761", "Client", nonce) if kind == "php" else net.join_directory("ws://127.0.0.1:31760", "Client"))
		check(error == OK, "Connect")
		if kind != "lan":
			await until(func(): return net.stage == "directory", "Directory before admission")
			net.directory_request("create", ["Shared mods"])
		if role == "download":
			await until(func(): return offer_seen, "Offer missing mods")
			check(net.my_slot.is_empty() and net.stage == "mods", "No seat before installing mods")
			check(net.mods.offered.size() == 1, "Exact package profile offered")
			net.mods.begin()
			await until(func(): return downloaded, "Download chunks and verify package")
			check(FileAccess.file_exists(Mods.network_boot_path), "Persist profile and reconnect target")
		else:
			await until(func(): return net.stage == "lobby", "Matching profile admitted")
			if kind != "lan":
				net.request("bot")
				await until(func(): return net.players.size() == 2, "Bot")
			net.request("ready", [true])
			if kind != "lan": net.request("start")
			await until(func(): return not latest.is_empty(), "Modded simulation view")
			check(latest.game.units.size() == 4 and latest.game.mod_state.fired.has("welcome"), "Portable units and events on " + kind)
			check(latest.game.coins >= 1000, "Same shared rules on " + kind)
			check(latest.game.get("mods") == Engine.get_meta("atlas_mods"), "Exact save and view profile on " + kind)
			FileAccess.open(folder.path_join("done"), FileAccess.WRITE).close()
	if net.active: net.shutdown("")
	atlas.queue_free()
	await process_frame
	print("PASS: ", kind, " ", role, " shared mod download/admission/rules")
	quit()
