extends RefCounted

const L = preload("res://src/i18n.gd")
## Only the host owns this simulation. Clients receive their own filtered view.
const Game = preload("res://src/game.gd")
var countries: Array = []
var owners: Array = []
var factions: Dictionary = {}
var cues: Dictionary = {}
var elapsed = 0
var occupations: Dictionary = {}
var bot_profiles: Dictionary = {}
var random_state = randi_range(1, 2147483646)

func roll(limit: int = 100) -> int:
	# Keep random outcomes identical in Godot and PHP and reproducible after a save.
	random_state = (random_state * 48271) % 2147483647
	return random_state % limit

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
	bot_profiles.erase(slot)
	for key in occupations.keys():
		if occupations[key].previous == slot or occupations[key].owner == slot: occupations.erase(key)

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
			if args.size() == 1:
				accepted = g.dispatch_attack(args[0])
				if accepted: declare_war(slot, args[0], false)
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
		if slot in bot_slots and elapsed % int(Game.B.bot_seconds) == 0: bot_turn(slot)
		var due = g.operations.filter(func(op): return op.arrival <= elapsed).duplicate(true)
		for op in due:
			if op.kind == "attack" and not g.countries[int(op.target)].owned and g.rebel_country(int(op.target)):
				g.rebel_bonus = roll(10) + 1
		g.tick()
		for op in due:
			var target = int(op.target)
			var defender = owners[target]
			if defender == "" or defender == slot or not factions.has(defender): continue
			var other = factions[defender]
			if op.kind == "attack":
				var origin = int(op.from)
				if not origin in other.wars: other.wars.append(origin)
				if op.get("surprise", false): other.log_event("Внезапное нападение на %s!" % g.atlas[target].name)
				if not g.battles.is_empty():
					var report = g.battles.front().duplicate(true)
					report.attacking = false
					report.won = not report.won
					other.battles.push_front(report)
					if other.battles.size() > 20: other.battles.resize(20)
				if g.countries[target].owned:
					for i in 3: other.units[i] = maxi(0, other.units[i] - ceili(other.units[i] * Game.B.defender_retreat_loss))
					other.defeats += 1
					if not target in other.wars: other.wars.append(target)
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
		for op in due:
			var target = int(op.target)
			if op.kind == "attack" and g.countries[target].owned and owners[target] != slot and g.rebel_country(target):
				occupations[str(target)] = {"previous": owners[target], "owner": slot, "due": elapsed + 120 + roll(301)}
		commit(slot)
		if slot in bot_slots: g.effects.clear()
	if elapsed % 30 == 0:
		for i in owners.size():
			if owners[i] == "": countries[i].units[0] += 1
	for key in occupations.keys():
		var occupation = occupations[key]
		var id = int(key)
		if owners[id] != occupation.owner:
			occupations.erase(key)
			continue
		if elapsed < occupation.due: continue
		occupation.due = elapsed + 120 + roll(301)
		if roll() >= 20: continue
		var former = occupation.previous
		if former != "" and not factions.has(former): former = ""
		owners[id] = former
		var loser = factions[occupation.owner]
		if not id in loser.wars: loser.wars.append(id)
		loser.log_event("Повстанцы вернули %s прежнему владельцу." % loser.atlas[id].name)
		cues[occupation.owner].append("defeat")
		if former != "":
			factions[former].log_event("Повстанцы вернули вам %s." % loser.atlas[id].name)
			cues[former].append("victory")
		else: countries[id].units = [10, 0, 0]
		occupations.erase(key)

func declare_war(slot: String, target: int, surprise: bool) -> void:
	var g = factions[slot]
	if not target in g.wars: g.wars.append(target)
	var defender = owners[target]
	if defender == "" or defender == slot: return
	var other = factions[defender]
	var origin = g.origin_for(target)
	if surprise:
		g.operations.back()["surprise"] = true
		return
	if not origin in other.wars: other.wars.append(origin)
	other.log_event("%s объявляет вам войну! Цель наступления: %s." % [g.atlas[origin].name, g.atlas[target].name])
	cues[defender].append("warning")

func bot_turn(slot: String) -> void:
	var g = factions[slot]
	if not bot_profiles.has(slot):
		var candidate = {}
		while candidate.is_empty() or candidate in bot_profiles.values():
			candidate = {"style": roll(3), "risk": 70 + roll(41), "economy": 15 + roll(51), "branch": roll(3)}
		bot_profiles[slot] = candidate
	var profile = bot_profiles[slot]
	var invest = roll() < int(profile.economy) + (int(Game.B.bot_economy_bonus) if profile.style == 0 else 0)
	var improved = false
	if invest:
		var cheapest = INF
		var country = -1
		var business = -1
		for i in countries.size():
			if owners[i] != slot: continue
			for j in countries[i].businesses.size():
				var cost = g.business_cost(i, j)
				if cost < cheapest:
					cheapest = cost
					country = i
					business = j
		if country >= 0: improved = g.upgrade_business(country, business)
	if not improved:
		var branch = int(profile.branch)
		if g.units[2] < Game.B.naval_ships: g.recruit(2)
		elif g.coins >= Game.B.bot_upgrade_coins and g.levels[branch] < Game.B.bot_max_level: g.upgrade_army(branch)
		else: g.recruit(branch if roll() < Game.B.bot_favorite_chance else roll(3))
	if g.has_operation("attack"): return
	var target = -1
	var weakest = INF
	var threshold = (float(profile.risk) + (int(Game.B.bot_style_risk) if profile.style == 1 else (-int(Game.B.bot_style_risk) if profile.style == 2 else 0))) / 100.0
	for i in countries.size():
		if owners[i] == slot or g.attack_block(i) != "": continue
		var defense = g.power(g.countries[i].units, g.enemy_levels.get(str(i), [1, 1, 1]))
		var strength = g.power(g.units, g.levels) * (1.0 if g.border(i) else Game.B.naval_multiplier)
		if defense <= strength * threshold and defense < weakest:
			target = i
			weakest = defense
	if target >= 0:
		if not g.reports.has(str(target)): g.spy(target)
		if g.dispatch_attack(target): declare_war(slot, target, roll() < Game.B.surprise_chance)

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
			if op.get("surprise", false): continue
			var visible = op.duplicate(true)
			visible.kind = "nuke" if op.kind == "nuke" else "enemy"
			visible.source_color = players[other].color
			remote.append(visible)
	var sounds = cues[slot].slice(0, 40)
	cues[slot].clear()
	var effects = factions[slot].effects.slice(0, 40).duplicate(true)
	factions[slot].effects.clear()
	return {"game": data, "colors": colors, "names": names, "remote": remote, "sounds": sounds, "effects": effects}

func export_data() -> Dictionary:
	var states = {}
	for slot in factions:
		project(slot)
		states[slot] = factions[slot].export_data().duplicate(true)
	return {"elapsed": elapsed, "countries": countries.duplicate(true), "owners": owners.duplicate(), "factions": states, "occupations": occupations.duplicate(true), "random_state": random_state, "bot_profiles": bot_profiles.duplicate(true)}

func restore_data(data: Variant, players: Dictionary) -> bool:
	if not data is Dictionary or not data.get("elapsed") is float and not data.get("elapsed") is int: return false
	if data.elapsed < 0 or data.elapsed > 100000000 or data.elapsed != floorf(data.elapsed): return false
	if not data.get("countries") is Array or data.countries.size() != 176 or not data.get("owners") is Array or data.owners.size() != 176: return false
	if not data.get("factions") is Dictionary or data.factions.size() > 176: return false
	var profiles = data.get("bot_profiles", {})
	if not profiles is Dictionary or profiles.size() > 176: return false
	for slot in profiles:
		if not players.has(slot) or not data.factions.has(slot) or not profiles[slot] is Dictionary: return false
		var p = profiles[slot]
		var validator_profile = Game.new()
		if not validator_profile.valid_numbers([p.get("style"), p.get("risk"), p.get("economy"), p.get("branch")], 4): return false
		if p.style > 2 or p.branch > 2 or p.risk < 70 or p.risk > 110 or p.economy < 15 or p.economy > 65: return false
	var restored = {}
	var saved_random = data.get("random_state", 1)
	if not (saved_random is int or saved_random is float) or saved_random < 1 or saved_random > 2147483646 or saved_random != floorf(saved_random): return false
	for slot in data.factions:
		if not players.has(slot): return false
		var g = Game.new()
		if not g.restore_data(data.factions[slot], false) or g.elapsed != data.elapsed: return false
		g.network_game = true
		restored[slot] = g
	var validator = Game.new()
	var saved_occupations = data.get("occupations", {})
	if not saved_occupations is Dictionary or saved_occupations.size() > 176: return false
	for key in saved_occupations:
		var entry = saved_occupations[key]
		if not str(key).is_valid_int() or int(key) < 0 or int(key) >= 176 or not entry is Dictionary: return false
		if not entry.get("previous") is String or (entry.previous != "" and not restored.has(entry.previous)) or not restored.has(entry.get("owner", "")): return false
		if not validator.valid_numbers([entry.get("due")], 1) or entry.due > data.elapsed + 420: return false
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
	bot_profiles = profiles.duplicate(true)
	for profile in bot_profiles.values():
		for key in profile: profile[key] = int(profile[key])
	factions = restored
	occupations = saved_occupations.duplicate(true)
	random_state = int(saved_random)
	cues = {}
	for slot in factions:
		cues[slot] = []
		var queue = cues[slot]
		factions[slot].sound_requested.connect(func(cue):
			if queue.size() < 40: queue.append(cue))
	return true
