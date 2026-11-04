extends SceneTree

const World = preload("res://src/network_world.gd")
const Session = preload("res://src/network_session.gd")
const Game = preload("res://src/game.gd")
var failures = 0
var checks = 0

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(text)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var session = Session.new()
	root.add_child(session)
	session.hosting = true
	session.active = true
	session.stage = "lobby"
	session.host_slot = "host"
	session.my_slot = "host"
	session.players.host = session.make_player("Host", "", 1, false)
	check(not session.apply_request(1, "bot", [176]), "Reject overflow without creating any bots")
	check(session.players.size() == 1, "Overflow is atomic")
	for count in [-1, 0, 1.5, "2"]:
		check(not session.apply_request(1, "bot", [count]), "Reject invalid bot count")
	check(session.apply_request(1, "bot", [175]), "Allow one player and 175 bots")
	var homes = {}
	for player in session.players.values(): homes[player.home] = true
	check(homes.size() == 176 and session.players.size() == 176, "Every participant has a distinct country")
	check(not session.apply_request(1, "bot", [1]), "Reject adding to a full room")
	var crowded = World.new()
	for slot in session.players:
		var player = session.players[slot]
		check(crowded.add_faction(slot, player.home, player.color), "Full room can create faction")
	for i in 4: crowded.tick(session.players.keys().filter(func(slot): return slot != "host"))
	var unique_profiles = []
	for profile in crowded.bot_profiles.values():
		check(not profile in unique_profiles, "Every bot has a distinct profile within the session")
		unique_profiles.append(profile)
	var full_view = crowded.view("host", session.players)
	check(Game.new().restore_data(full_view.game, false) and full_view.remote.size() <= 350 and full_view.sounds.size() <= 40, "Full room ticks and sends a valid client view")
	session.active = false
	session.queue_free()

	var w = World.new()
	var players = {"a": {"name": "A", "color": "69dfbd"}, "b": {"name": "B", "color": "73aeef"}}
	w.add_faction("a", 0, "69dfbd")
	w.add_faction("b", 1, "73aeef")
	w.factions.a.units = [1, 0, 4]
	w.command("a", "attack", [1])
	check(1 in w.factions.a.wars and 0 in w.factions.b.wars, "War starts on dispatch and is mutual")
	for i in 4: w.tick([])
	check(w.owners[1] == "b" and 1 in w.view("a", players).game.wars, "Failed assault retains war marker")
	w.project("a")
	w.factions.a.units = [1000, 0, 4]
	w.factions.a.coins = 1000
	w.factions.b.events.clear()
	w.factions.a.dispatch_attack(1)
	w.declare_war("a", 1, true)
	check(w.view("b", players).remote.is_empty() and w.factions.b.events.is_empty(), "Surprise hides both route and advance notification")
	var saved = JSON.parse_string(JSON.stringify(w.export_data()))
	var restored = World.new()
	check(restored.restore_data(saved, players) and restored.view("b", players).remote.is_empty(), "Hidden march survives save/load")
	for i in 4: restored.tick([])
	check(restored.owners[1] == "a" and 1 in restored.factions.b.wars, "Surprise battle captures land and marks lost territory")
	check(restored.factions.b.events.any(func(event): return event.text.contains("Внезапное")), "Surprise is announced at battle")
	var strong = -1
	for id in 176:
		if w.factions.a.rebel_country(id):
			strong = id
			break
	check(strong >= 0, "Map contains strong rebel countries")
	w = World.new()
	w.add_faction("a", 1, "69dfbd")
	w.add_faction("b", strong, "73aeef")
	w.factions.a.units = [1000, 100, 100]
	w.command("a", "attack", [strong])
	for i in 4: w.tick([])
	check(w.owners[strong] == "a" and w.occupations.has(str(strong)), "Conquest records previous owner and uprising timer")
	check(w.occupations[str(strong)].due - w.elapsed >= 120 and w.occupations[str(strong)].due - w.elapsed <= 420, "First uprising timer is between 2 and 7 minutes")
	check(w.factions.a.events.any(func(event): return event.text.contains("%")), "Rebels give a small combat bonus")
	saved = JSON.parse_string(JSON.stringify(w.export_data()))
	check(restored.restore_data(saved, players) and restored.occupations[str(strong)].previous == "b" and int(restored.occupations[str(strong)].due) == w.occupations[str(strong)].due, "Uprising state survives save/load")
	restored.random_state = 1
	while ((restored.random_state * 48271 % 2147483647) * 48271 % 2147483647) % 100 >= 20: restored.roll()
	restored.occupations[str(strong)].due = restored.elapsed + 1
	restored.tick([])
	check(restored.owners[strong] == "b" and not restored.occupations.has(str(strong)), "Uprising restores an eliminated former owner")
	check(strong in restored.factions.a.wars, "Uprising leaves a war marker on lost land")
	saved.occupations[str(strong)].previous = "intruder"
	check(not World.new().restore_data(saved, players), "Reject unknown previous owner in saves")
	var g = Game.new()
	g.start(0)
	g.countries[2].owned = true
	g.units = [10000, 1000, 1000]
	var serial = g.notification_serial
	check(g.launch_enemy_attack(1, 0, true) and g.notification_serial == serial, "Solo surprise bypasses warning without an advance event")
	check(Game.new().restore_data(JSON.parse_string(JSON.stringify(g.export_data())), false), "Solo surprise restores without a warning record")
	print("%s: %d war rule checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
