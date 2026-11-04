extends RefCounted

const L = preload("res://src/i18n.gd")
## Only the host owns this simulation. Clients receive their own filtered view.
const Game = preload("res://src/game.gd")
var countries: Array = []
var owners: Array = []
var factions: Dictionary = {}
var cues: Dictionary = {}
var elapsed = 0

func _init() -> void:
	countries = Game.new().countries.duplicate(true)
	owners.resize(countries.size())
	owners.fill("")

func add_faction(slot: String, home: int, color: String) -> bool:
	if factions.has(slot) or home < 0 or home >= countries.size() or owners[home] != "": return false
	var game = Game.new()
	game.network_game = true
	game.player_color = Color(color)
	game.start(home)
	game.elapsed = elapsed
	factions[slot] = game
	cues[slot] = ["start"]
	var queue = cues[slot]
	game.sound_requested.connect(func(cue):
		if queue.size() < 40: queue.append(cue))
	owners[home] = slot
	return true

func remove_faction(slot: String) -> void:
	if not factions.has(slot): return
	var count = owners.count(slot)
	for i in owners.size():
		if owners[i] == slot:
			countries[i].units = factions[slot].units.map(func(n): return int(n) / maxi(1, count))
			owners[i] = ""
	factions.erase(slot)
	cues.erase(slot)

func project(slot: String) -> void:
	var g = factions[slot]
	g.countries = countries.duplicate(true)
	g.enemy_levels = {}
	for i in owners.size():
		g.countries[i].owned = owners[i] == slot
		if factions.has(owners[i]):
			g.countries[i].units = factions[owners[i]].units.duplicate()
			g.enemy_levels[str(i)] = factions[owners[i]].levels.duplicate()
	g.finished = g.owned_count() == 0 or g.owned_count() == countries.size()

func commit(slot: String) -> void:
	var g = factions[slot]
	for i in owners.size():
		if g.countries[i].owned:
			owners[i] = slot
			countries[i].businesses = g.countries[i].businesses.duplicate()
		elif owners[i] == "": countries[i].units = g.countries[i].units.duplicate()

func command(slot: String, action: String, args: Array) -> bool:
	if not factions.has(slot) or args.size() > 2: return false
	for arg in args:
		if not arg is int or arg < 0 or arg > 175: return false
	project(slot)
	var g = factions[slot]
	var accepted = false
	match action:
		"recruit":
			if args.size() == 1: accepted = g.recruit(args[0])
		"upgrade":
			if args.size() == 1: accepted = g.upgrade_army(args[0])
		"business":
			if args.size() == 2: accepted = g.upgrade_business(args[0], args[1])
		"spy":
			if args.size() == 1: accepted = g.spy(args[0])
		"attack":
			if args.size() == 1: accepted = g.dispatch_attack(args[0])
		"nuke":
			if args.size() == 1: accepted = g.nuclear_strike(args[0])
		"read":
			if args.is_empty():
				g.notifications_seen = g.notification_serial
				accepted = true
	commit(slot)
	return accepted

func tick(bot_slots: Array) -> void:
	elapsed += 1
	for slot in factions.keys():
		project(slot)
		var g = factions[slot]
		if g.finished:
			g.elapsed = elapsed
			g.operations.clear()
			g.mission = {}
			continue
		if slot in bot_slots and elapsed % 4 == 0: bot_turn(slot)
		var due = g.operations.filter(func(op): return op.arrival <= elapsed).duplicate(true)
		g.tick()
		for op in due:
			var target = int(op.target)
			var defender = owners[target]
			if defender == "" or defender == slot or not factions.has(defender): continue
			var other = factions[defender]
			if op.kind == "attack":
				if g.countries[target].owned:
					for i in 3: other.units[i] = maxi(0, other.units[i] - ceili(other.units[i] * 0.35))
					other.defeats += 1
					other.log_event("Игрок захватил %s. Отступившие войска сохранились." % g.atlas[target].name)
					other.effects.append({"kind": "defeat", "target": target})
					cues[defender].append("defeat")
				else:
					other.units = g.countries[target].units.duplicate()
					other.victories += 1
					other.log_event("Атака на %s отбита." % g.atlas[target].name)
					other.effects.append({"kind": "victory", "target": target})
					cues[defender].append("victory")
			elif op.kind == "nuke" and not g.countries[target].owned:
				other.units = g.countries[target].units.duplicate()
				other.log_event("Ядерный удар по %s: армия потеряла 50%% состава." % g.atlas[target].name)
				other.effects.append({"kind": "nuke", "target": target})
				cues[defender].append("nuke")
		commit(slot)
		if slot in bot_slots: g.effects.clear()
	if elapsed % 30 == 0:
		for i in owners.size():
			if owners[i] == "": countries[i].units[0] += 1

func bot_turn(slot: String) -> void:
	var g = factions[slot]
	if g.units[2] < 4: g.recruit(2)
	elif g.coins >= 150 and g.levels[0] < 6: g.upgrade_army(0)
	else: g.recruit((elapsed / 4) % 3)
	if g.has_operation("attack"): return
	var target = -1
	var weakest = INF
	for i in countries.size():
		if owners[i] == slot or g.attack_block(i) != "": continue
		var defense = g.power(g.countries[i].units, g.enemy_levels.get(str(i), [1, 1, 1]))
		var strength = g.power(g.units, g.levels) * (1.0 if g.border(i) else 0.85)
		if defense <= strength * 0.9 and defense < weakest:
			target = i
			weakest = defense
	if target >= 0:
		if not g.reports.has(str(target)): g.spy(target)
		g.dispatch_attack(target)

func view(slot: String, players: Dictionary) -> Dictionary:
	project(slot)
	var data = factions[slot].export_data().duplicate(true)
	var colors = {}
	var names = {}
	var remote = []
	for i in owners.size():
		if owners[i] != "" and players.has(owners[i]):
			colors[str(i)] = players[owners[i]].color
			names[str(i)] = players[owners[i]].name
		if owners[i] != slot: data.countries[i].units = [0, 0, 0]
	for other in factions:
		if other == slot: continue
		for op in factions[other].operations:
			var visible = op.duplicate(true)
			visible.kind = "nuke" if op.kind == "nuke" else "enemy"
			visible.source_color = players[other].color
			remote.append(visible)
	var sounds = cues[slot].duplicate()
	cues[slot].clear()
	var effects = factions[slot].effects.duplicate(true)
	factions[slot].effects.clear()
	return {"game": data, "colors": colors, "names": names, "remote": remote, "sounds": sounds, "effects": effects}

func export_data() -> Dictionary:
	var states = {}
	for slot in factions:
		project(slot)
		states[slot] = factions[slot].export_data().duplicate(true)
	return {"elapsed": elapsed, "countries": countries.duplicate(true), "owners": owners.duplicate(), "factions": states}

func restore_data(data: Variant, players: Dictionary) -> bool:
	if not data is Dictionary or not data.get("elapsed") is float and not data.get("elapsed") is int: return false
	if data.elapsed < 0 or data.elapsed > 100000000 or data.elapsed != floorf(data.elapsed): return false
	if not data.get("countries") is Array or data.countries.size() != 176 or not data.get("owners") is Array or data.owners.size() != 176: return false
	if not data.get("factions") is Dictionary or data.factions.size() > 8: return false
	var restored = {}
	for slot in data.factions:
		if not players.has(slot): return false
		var g = Game.new()
		if not g.restore_data(data.factions[slot], false) or g.elapsed != data.elapsed: return false
		g.network_game = true
		restored[slot] = g
	var validator = Game.new()
	for i in 176:
		if not data.owners[i] is String or (data.owners[i] != "" and not restored.has(data.owners[i])): return false
		var c = data.countries[i]
		if not c is Dictionary or not validator.valid_numbers(c.get("units"), 3) or not c.get("businesses") is Array or c.businesses.size() < 1 or c.businesses.size() > 5 or not validator.valid_numbers(c.businesses, c.businesses.size(), 1): return false
	countries = data.countries.duplicate(true)
	for c in countries:
		c.units = c.units.map(func(n): return int(n))
		c.businesses = c.businesses.map(func(n): return int(n))
	owners = data.owners.duplicate()
	elapsed = int(data.elapsed)
	factions = restored
	cues = {}
	for slot in factions:
		cues[slot] = []
		var queue = cues[slot]
		factions[slot].sound_requested.connect(func(cue):
			if queue.size() < 40: queue.append(cue))
	return true
