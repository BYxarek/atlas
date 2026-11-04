extends SceneTree

const World = preload("res://src/network_world.gd")
const Session = preload("res://src/network_session.gd")
var checks = 0
var failures = 0

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + text)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var w = World.new()
	var players = {"a": {"name": "A", "color": "69dfbd"}, "b": {"name": "B", "color": "73aeef"}}
	check(w.add_faction("a", 0, "69dfbd") and w.add_faction("b", 1, "73aeef"), "Create separate factions")
	check(not w.add_faction("c", 0, "edc16e"), "Reject occupied country")
	check(w.factions.a.units == w.factions.b.units and w.factions.a.coins == w.factions.b.coins, "Equal starts")
	check(not w.command("a", "business", [1, 0]) and not w.command("a", "recruit", [9]), "Reject foreign economy and invalid troop kind")
	check(not w.command("a", "recruit", [0.0]) and not w.command("a", "attack", [-1]), "Validate client command arguments")
	check(w.command("a", "recruit", [0]), "Recruit own troops")
	check(w.factions.a.units[0] == 45 and w.factions.b.units[0] == 35 and w.factions.b.coins == 180, "Economies and armies remain separate")
	var view = w.view("a", players)
	check(view.game.countries[1].units == [0, 0, 0] and not view.has("factions"), "Snapshot hides foreign armies and private state")
	check(view.colors["1"] == "73aeef" and view.names["1"] == "B", "Public ownership and colors")
	check(w.command("a", "spy", [1]), "Dispatch private scout")
	for i in 6: w.tick([])
	check(w.factions.a.reports["1"].units == w.factions.b.units and w.factions.b.reports.is_empty(), "Scout report is accurate and private")
	w.factions.a.units = [1000, 100, 100]
	check(w.command("a", "attack", [1]), "Attack another player's last country")
	check(w.view("b", players).remote.size() == 1, "Enemy march is visible")
	for i in 4: w.tick([])
	check(w.owners[1] == "a" and w.factions.b.owned_count() == 0, "PvP can capture final country")
	check(w.factions.b.defeats == 1 and w.factions.a.victories == 1, "Both players receive battle outcome")
	check(not w.command("b", "recruit", [0]), "Eliminated player cannot spend")
	var saved = JSON.parse_string(JSON.stringify(w.export_data()))
	var restored = World.new()
	check(restored.restore_data(saved, players), "Network world JSON roundtrip")
	check(restored.owners == w.owners and restored.factions.a.units == w.factions.a.units, "Network roundtrip preserves ownership and armies")
	var bad = saved.duplicate(true)
	bad.owners[0] = "intruder"
	check(not restored.restore_data(bad, players), "Reject invalid save owner")
	w.remove_faction("a")
	check(w.owners[0] == "" and w.owners[1] == "" and not w.factions.has("a"), "Kicking returns territories to neutrals")
	w = World.new()
	w.add_faction("a", 0, "69dfbd")
	w.add_faction("b", 1, "73aeef")
	w.factions.a.units = [150, 8, 4]
	w.factions.b.units = [150, 8, 4]
	w.factions.b.levels = [8, 8, 8]
	w.command("a", "attack", [1])
	for i in 4: w.tick([])
	check(w.owners[1] == "b" and w.factions.a.defeats == 1 and w.factions.b.victories == 1, "Upgraded defense can beat equal-sized attacking army")
	w.factions.a.conquests = range(2, 12)
	w.factions.a.nukes = 1
	var before = w.factions.b.units.duplicate()
	check(w.command("a", "nuke", [1]), "Launch multiplayer nuclear strike")
	check(w.view("b", players).remote.any(func(op): return op.kind == "nuke"), "Other players see missile animation")
	for i in 3: w.tick([])
	check(w.factions.b.units == before.map(func(n): return floori(n * 0.5)), "Nuclear strike halves player army")
	check(w.view("b", players).effects.any(func(effect): return effect.kind == "nuke"), "Defender receives explosion effect")
	for i in 120: w.tick(["b"])
	check(w.factions.b.units != [150, 8, 4] or w.factions.b.owned_count() > 1, "Bots recruit, develop and fight")
	var n = Session.new()
	n.identity_token = "a".repeat(48)
	n.save_directory = "user://test_network_saves"
	root.add_child(n)
	n.directory_client = true
	n.server_url = "wss://one.example.com"
	var credential = n.login_token()
	check(n.valid_token(credential) and credential != n.identity_token, "VPS receives a derived credential instead of the local profile secret")
	n.server_url = "wss://one.example.com:443/"
	check(n.login_token() == credential, "Default TLS port and trailing slash retain same profile")
	n.server_url = "wss://two.example.com"
	check(n.login_token() != credential, "Different VPS servers receive separate credentials")
	n.directory_client = false
	check(n.login_token() == n.identity_token, "Legacy LAN profile remains compatible")
	check(n.host_room("Test", "Host", 28760) == OK, "Create ENet host")
	check(n.request("bot"), "Host adds bot")
	check(not n.request("start"), "Cannot start until everyone ready")
	check(n.request("ready", [true]) and n.request("start"), "Readiness permits start")
	n.world.tick([])
	check(n.save_match() == OK, "Atomic network save")
	var path = n.save_path()
	n.request("lobby")
	check(n.stage == "lobby" and not n.players[n.my_slot].ready, "Return to lobby resets human readiness")
	n.shutdown("")
	check(n.host_room("Ignored", "Host", 28760, path) == OK and n.world.elapsed == 1, "Reopen saved multiplayer lobby")
	check(n.request("ready", [true]) and n.request("start"), "Resume after all players ready")
	check(n.saved_matches().size() > 0, "Saved matches listed separately")
	n.shutdown("")
	n.queue_free()
	await process_frame
	var scene = load("res://main.tscn").instantiate()
	scene.settings_path = "user://test_ui_settings.cfg"
	root.add_child(scene)
	scene.network.identity_token = "c".repeat(48)
	scene.network.save_directory = "user://test_network_ui"
	scene.online.show_browser()
	check(scene.page == "online" and scene.online.rooms.get_child_count() > 0, "Online browser screen opens")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("res://build/online-preview.png")
	check(scene.network.host_room("Тестовое лобби", "Командующий", 28760) == OK and scene.page == "lobby", "Host lobby screen opens")
	scene.network.request("bot")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("res://build/lobby-preview.png")
	scene.network.request("ready", [true])
	scene.network.request("start")
	check(scene.page == "game" and scene.game.network_game and scene.game.coins == 180, "Authoritative view enters game UI")
	scene.show_pause()
	check(scene.page == "pause" and scene.network.stage == "game", "Local menu leaves match running")
	scene.network.request("lobby")
	check(scene.page == "lobby", "Shared pause displays lobby")
	scene.network.shutdown("")
	check(scene.page == "menu" and scene.game.home == -1 and not scene.game.network_game, "Leave network resets proxy state")
	scene.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("PASS: %d network checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
