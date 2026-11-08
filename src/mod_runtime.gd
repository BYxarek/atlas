extends RefCounted

const Rules = preload("res://src/mod_rules.gd")

static func content() -> Dictionary:
	return Engine.get_meta("atlas_content", Rules.defaults())

static func unit_ids() -> Array:
	return Rules.UNIT_IDS + content().get("units", []).map(func(unit): return unit.id)

static func state(g: RefCounted) -> void:
	if g.mod_state.is_empty(): g.mod_state = {"fired": {}, "flags": {}, "researches": [], "random_state": 71 + maxi(g.home, 0) * 319, "hold_since": -1, "result": ""}

static func start_territories(home: int) -> Array:
	var start = content().get("scenario", {}).get("starts", {}).get(str(home), {})
	return Rules.unique([home] + start.get("owned", []).map(func(id): return int(id)))

static func start(g: RefCounted) -> void:
	state(g)
	var setup = content().get("scenario", {}).get("starts", {}).get(str(g.home), {})
	if setup.has("coins"): g.coins = setup.coins
	for key in ["units", "levels"]:
		if setup.has(key): g.set(key, setup[key].map(func(n): return int(n)))
	g.mod_state.researches = setup.get("researches", []).duplicate()
	for id in start_territories(g.home): g.countries[id].owned = true
	emit_event(g, "start", g.home)

static func requirements(g: RefCounted, ids: Array) -> bool:
	return ids.all(func(id): return id in g.mod_state.get("researches", []))

static func unit_available(g: RefCounted, index: int) -> bool:
	return index < 3 or requirements(g, content().units[index - 3].get("requires", []))

static func unit_bonus(g: RefCounted, index: int) -> float:
	var bonus = 0.0
	var id = unit_ids()[index]
	for tech in content().get("technologies", []):
		if tech.get("unit", "infantry") == id and tech.id in g.mod_state.get("researches", []): bonus += float(tech.get("bonus", 0))
	return bonus

static func extra_income(g: RefCounted) -> int:
	var total = 0
	for country in g.countries:
		if not country.owned: continue
		for definition in content().get("buildings", []): total += int(definition.income) * int(country.get("structures", {}).get(definition.id, 0))
	for tech in content().get("technologies", []):
		if tech.id in g.mod_state.get("researches", []): total += int(tech.get("income", 0))
	return total

static func construct(g: RefCounted, country: int, index: int) -> bool:
	var definitions = content().get("buildings", [])
	if not g.can_act() or country < 0 or country >= g.countries.size() or not g.countries[country].owned or index < 0 or index >= definitions.size(): return false
	var item = definitions[index]
	if not requirements(g, item.get("requires", [])): return false
	var structures = g.countries[country].get("structures", {})
	var level = int(structures.get(item.id, 0))
	var cost = item.cost * (level + 1)
	if level >= 1000000 or g.coins < cost: return false
	g.coins -= cost
	structures[item.id] = level + 1
	g.countries[country].structures = structures
	g.sound_requested.emit("coins")
	emit_event(g, "building_built", country)
	return true

static func research(g: RefCounted, index: int) -> bool:
	var definitions = content().get("technologies", [])
	if not g.can_act() or index < 0 or index >= definitions.size(): return false
	var item = definitions[index]
	if item.id in g.mod_state.get("researches", []) or g.coins < item.cost or not requirements(g, item.get("requires", [])): return false
	state(g)
	g.coins -= item.cost
	g.mod_state.researches.append(item.id)
	g.sound_requested.emit("upgrade")
	emit_event(g, "research_completed", g.home)
	return true

static func allied(home: int, other_home: int) -> bool:
	for group in content().get("scenario", {}).get("alliances", []):
		if home in group and other_home in group: return true
	return false

static func emit_event(g: RefCounted, trigger: String, country: int = -1) -> void:
	var definitions = content().get("events", [])
	if definitions.is_empty(): return
	state(g)
	var budget = 64
	for event in definitions:
		if event.when != trigger: continue
		if g.mod_state.fired.has(event.id) and (event.get("once", true) or g.elapsed - int(g.mod_state.fired[event.id]) < int(event.get("cooldown", 1))): continue
		var condition = event.get("conditions", {})
		if condition.has("country_id") and int(condition.country_id) != country: continue
		if g.elapsed < condition.get("elapsed_min", 0) or g.coins < condition.get("coins_min", 0): continue
		if not condition.get("owns", []).all(func(id): return g.countries[int(id)].owned) or not requirements(g, condition.get("researches", [])): continue
		var match_flags = true
		for key in condition.get("flags", {}):
			if typeof(g.mod_state.flags.get(key)) != typeof(condition.flags[key]) or g.mod_state.flags.get(key) != condition.flags[key]: match_flags = false
		if not match_flags: continue
		if condition.get("chance", 100) < 100:
			g.mod_state.random_state = (int(g.mod_state.random_state) * 48271) % 2147483647
			if int(g.mod_state.random_state) % 100 >= condition.chance: continue
		if event.actions.size() > budget: break
		budget -= event.actions.size()
		g.mod_state.fired[event.id] = g.elapsed
		for action in event.actions:
			match action.type:
				"add_coins": g.coins = clampf(g.coins + action.get("amount", 0), 0, 1e12)
				"add_units":
					var index = unit_ids().find(action.get("unit", "infantry"))
					g.units[index] = clampi(g.units[index] + int(action.get("amount", 0)), 0, 100000000)
				"show_message": g.log_event(action.get("text", ""))
				"set_flag": g.mod_state.flags[action.key] = action.value
				"grant_research":
					if not action.technology in g.mod_state.researches: g.mod_state.researches.append(action.technology)
				"capture_country": g.countries[int(action.country_id)].owned = true
				"release_country": g.countries[int(action.country_id)].owned = false
				"win", "lose":
					g.mod_state.result = action.type
					g.finished = true
		if not g.mod_state.result.is_empty(): break

static func victory(g: RefCounted) -> Variant:
	if g.mod_state.get("result", "") != "": return g.mod_state.result == "win"
	var goal = content().get("victory", {})
	match goal.get("type", "world"):
		"coins": return g.coins >= goal.amount
		"countries": return goal.countries.all(func(id): return g.countries[int(id)].owned)
		"hold": return g.mod_state.get("hold_since", -1) >= 0 and g.elapsed - int(g.mod_state.hold_since) >= int(goal.seconds)
		"time": return g.elapsed >= int(goal.seconds)
	return null

static func tick(g: RefCounted) -> void:
	var goal = content().get("victory", {})
	if goal.get("type") == "hold":
		state(g)
		if not goal.countries.all(func(id): return g.countries[int(id)].owned): g.mod_state.hold_since = -1
		elif g.mod_state.hold_since < 0: g.mod_state.hold_since = g.elapsed
	emit_event(g, "tick")
	if g.owned_count() == 0:
		g.mod_state.result = "lose"
		g.finished = true
	if victory(g) == true and not g.finished:
		state(g)
		g.mod_state.result = "win"
		g.finished = true
		g.sound_requested.emit("campaign_win")

static func valid_state(value: Variant, elapsed: int) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if not Rules.keys(value, ["fired", "flags", "researches", "random_state", "hold_since", "result"]): return false
	if not value.get("fired") is Dictionary or value.fired.size() > 128 or not value.get("flags") is Dictionary or value.flags.size() > 128: return false
	var events = content().get("events", []).map(func(event): return event.id)
	for id in value.fired:
		if not id in events or not Rules.number(value.fired[id], 0, elapsed): return false
	for key in value.flags:
		if not Rules.identifier(key) or not Rules.flag_value(value.flags[key]): return false
	return Rules.ids(value.get("researches"), content().get("technologies", []).map(func(tech): return tech.id)) and Rules.number(value.get("random_state"), 1, 2147483646) and Rules.number(value.get("hold_since"), -1, elapsed) and value.get("result") in ["", "win", "lose"]

static func valid_structures(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 32: return false
	var available = content().get("buildings", []).map(func(item): return item.id)
	for key in value:
		if not key in available or not Rules.number(value[key], 1): return false
	return true

static func bot_invest(g: RefCounted) -> bool:
	for p in content().ai.get("priorities", []):
		var reserve = int(p.get("reserve", 0))
		var limit = int(p.get("max_level", 10))
		var index = unit_ids().find(p.get("id"))
		match p.action:
			"research":
				var list = content().technologies
				for i in list.size():
					if list[i].id == p.id and g.coins - list[i].cost >= reserve and research(g, i): return true
			"recruit":
				if g.units[index] < limit and g.coins - g.B.unit_cost[index] >= reserve and g.recruit(index): return true
			"upgrade":
				if g.levels[index] < limit and g.coins - g.upgrade_cost(index) >= reserve and g.upgrade_army(index): return true
			"construct", "business":
				for id in g.countries.size():
					if not g.countries[id].owned: continue
					if p.action == "business":
						for i in g.countries[id].businesses.size():
							if g.countries[id].businesses[i] < limit and g.coins - g.business_cost(id, i) >= reserve and g.upgrade_business(id, i): return true
					else:
						for i in content().buildings.size():
							var item = content().buildings[i]
							var level = int(g.countries[id].get("structures", {}).get(item.id, 0))
							if item.id == p.id and level < limit and g.coins - item.cost * (level + 1) >= reserve and construct(g, id, i): return true
	return false
