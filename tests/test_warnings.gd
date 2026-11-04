extends SceneTree

const Game = preload("res://src/game.gd")
const PATH = "user://test_warnings.json"
var checks = 0
var failures = 0

func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + text)

func empire() -> RefCounted:
	var g = Game.new()
	g.start(0)
	g.countries[2].owned = true
	g.units = [10000, 1000, 1000]
	return g

func _initialize() -> void:
	var protected = Game.new()
	protected.start(0)
	check(not protected.schedule_warning() and not protected.launch_enemy_attack(1, 0), "One-country immunity blocks warnings and direct launches")
	var original_units = protected.units.duplicate()
	protected.resolve_enemy_attack(1, 0, true)
	check(protected.countries[0].owned and protected.units == original_units, "Defense resolution cannot damage last country")
	var launched = 0
	var cancelled = 0
	for seed_value in 32:
		var g = empire()
		g.rng.seed = seed_value
		check(g.schedule_warning(), "Multi-country empire can receive a warning")
		var warning = g.pending_warning()
		var lead = int(warning.deadline - warning.issued)
		check(lead >= 60 and lead <= 300, "Every warning leads possible launch by 1–5 minutes")
		check(g.warning_description(warning).begins_with("Неизвестная страна") and not g.atlas[int(warning.attacker)].name in g.events[0].text, "Unknown attackers are not named in notifications")
		check(warning.low < warning.high and warning.low <= g.power(g.countries[int(warning.attacker)].units) and warning.high >= g.power(g.countries[int(warning.attacker)].units), "Force estimate is a broad range")
		for second in lead - 1: g.tick()
		check(not g.has_operation("enemy") and warning.status == "pending", "No invasion before announced deadline")
		g.tick()
		if g.has_operation("enemy"):
			launched += 1
			check(warning.status == "launched" and g.operations[0].start - warning.issued >= 60 and g.operations[0].start - warning.issued <= 300, "Real launch follows complete warning period")
		else:
			cancelled += 1
			check(warning.status == "cancelled", "False alarms are explicitly resolved")
	check(launched > 0 and cancelled > 0, "Warnings can result in attacks or false alarms")
	var land = Game.new()
	var russia = -1
	var finland = -1
	var china = -1
	for country in land.atlas:
		if country.english == "Russia": russia = int(country.id)
		if country.english == "Finland": finland = int(country.id)
		if country.english == "China": china = int(country.id)
	land.start(russia)
	land.countries[china].owned = true
	land.countries[finland].units = [20, 2, 0]
	land.elapsed = 60
	land.warnings = [{"attacker": finland, "issued": 0, "deadline": 60, "low": 10, "high": 40, "status": "pending"}]
	check(land.launch_enemy_attack(finland, russia) and not land.operations[0].overseas, "Adjacent enemy can launch a land invasion without ships")
	var g = empire()
	g.schedule_warning()
	var warning = g.pending_warning()
	var attacker = int(warning.attacker)
	check(not g.launch_enemy_attack(attacker, 0), "Direct launch cannot bypass warning deadline")
	g.reports[str(attacker)] = {"units": g.countries[attacker].units.duplicate(), "time": g.elapsed}
	check(g.warning_description(warning).begins_with(g.atlas[attacker].name), "Reconnaissance reveals identity in existing warning")
	g.elapsed = 20
	g.paused = true
	var deadline = warning.deadline
	for i in 100: g.tick()
	check(g.elapsed == 20 and warning.deadline == deadline, "Pause freezes countdown")
	g.notifications_seen = g.notification_serial
	check(g.save_game(PATH) == OK, "Pending warning saves")
	var restored = Game.new()
	check(restored.load_game(PATH) and restored.pending_warning().deadline == deadline, "Countdown restores without a new random delay")
	check(restored.notifications_seen == g.notifications_seen and restored.notification_serial == g.notification_serial + 1, "Read state restores and restoration is a new notification")
	g.paused = false
	g.countries[2].owned = false
	g.tick()
	check(g.pending_warning().is_empty() and warning.status == "cancelled", "Dropping to one country cancels pending threat")
	g = empire()
	g.schedule_warning()
	warning = g.pending_warning()
	attacker = int(warning.attacker)
	g.elapsed = int(warning.deadline)
	check(g.launch_enemy_attack(attacker, g.origin_for(attacker)), "Warned enemy can start at the deadline against a reachable territory")
	check(g.save_game(PATH) == OK and restored.load_game(PATH) and restored.has_operation("enemy"), "Announced in-flight invasion restores")
	g.countries[2].owned = false
	original_units = g.units.duplicate()
	g.tick()
	check(not g.has_operation("enemy") and g.units == original_units and g.owned_count() == 1, "Incoming invasion cancels immediately when only one country remains")
	g = empire()
	g.schedule_warning()
	warning = g.pending_warning()
	g.countries[int(warning.attacker)].owned = true
	g.tick()
	check(g.pending_warning().is_empty() and warning.status == "cancelled", "Capturing a threatening country removes its threat")
	g = empire()
	g.schedule_warning()
	g.save_game(PATH)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for key in ["short", "long", "attacker", "estimate", "status", "seen"]:
		var broken = saved.duplicate(true)
		match key:
			"short": broken.warnings[0].deadline = broken.warnings[0].issued + 59
			"long": broken.warnings[0].deadline = broken.warnings[0].issued + 301
			"attacker": broken.warnings[0].attacker = 999
			"estimate": broken.warnings[0].low = broken.warnings[0].high
			"status": broken.warnings[0].status = "invalid"
			"seen": broken.notifications_seen = broken.notification_serial + 1
		write_text(JSON.stringify(broken))
		check(not restored.load_game(PATH), "Corrupt warning fields rejected: " + key)
	var legacy = saved.duplicate(true)
	legacy.version = 2
	legacy.erase("warnings")
	legacy.erase("notification_serial")
	legacy.erase("notifications_seen")
	legacy.operations = [{"kind": "enemy", "from": 1, "target": 0, "start": 0, "arrival": 5, "overseas": true}]
	write_text(JSON.stringify(legacy))
	check(restored.load_game(PATH) and not restored.has_operation("enemy"), "Legacy surprise invasions cannot bypass new warnings")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
	print("%s: %d warning checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func write_text(text: String) -> void:
	var file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
