extends RefCounted
## Portable rules: the PHP interpreter implements this same bounded data contract.

const UNIT_IDS = ["infantry", "aircraft", "navy"]
const MAX_UNITS = 16
const MAX_COUNTRIES = 512
const TRIGGERS = ["start", "tick", "country_captured", "research_completed", "building_built", "mission_completed"]
const ACTIONS = ["add_coins", "add_units", "show_message", "set_flag", "grant_research", "capture_country", "release_country", "win", "lose"]
const COLORS = ["ink", "muted", "accent", "ocean", "unknown"]

static func numbers(value: Variant, depth: int = 0) -> Variant:
	if depth > 32: return null
	if value is float and is_finite(value) and value == floorf(value) and absf(value) <= 1e12: return int(value)
	if value is Array: return value.map(func(item): return numbers(item, depth + 1))
	if value is Dictionary:
		for key in value: value[key] = numbers(value[key], depth + 1)
	return value

static func identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64: return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func number(value: Variant, low: float = 0, high: float = 1000000, integer: bool = true) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= low and value <= high and (not integer or value == floorf(value))

static func text(value: Variant, maximum: int = 1024) -> bool:
	return value is String and value.length() <= maximum

static func keys(value: Variant, allowed: Array) -> bool:
	return value is Dictionary and value.keys().all(func(key): return key in allowed)

static func ids(value: Variant, available: Array) -> bool:
	return value is Array and value.size() <= 64 and value.all(func(id): return id in available) and value.size() == unique(value).size()

static func unique(values: Array) -> Array:
	var result = []
	for value in values:
		if not value in result: result.append(value)
	return result

static func defaults() -> Dictionary:
	return {"units": [], "buildings": [], "technologies": [], "scenario": {}, "victory": {}, "events": [], "translations": {}, "theme": {}, "panels": [], "assets": {}, "ai": {}}

static func compose(mods: Array, base: Dictionary) -> Dictionary:
	var balance = base.duplicate(true)
	var content = defaults()
	var sources = {}
	var conflicts = []
	for mod in mods:
		var changes = mod.get("changes", {})
		if mod.has("network_balance"):
			if not mod.network_balance is Dictionary: return failure("Invalid network_balance")
			changes = mod.network_balance.duplicate(true).merged(changes, true) if changes is Dictionary else null
		if not changes is Dictionary: return failure("Invalid changes in " + str(mod.get("id")))
		for key in changes:
			if not base.has(key): return failure("Unknown balance key: " + str(key))
			if sources.has(key) and balance[key] != changes[key]: conflicts.append({"field": key, "previous": sources[key], "winner": mod.id})
			balance[key] = changes[key]
			sources[key] = mod.id
		var extra = mod.get("content", {})
		if not keys(extra, defaults().keys() + ["map"]): return failure("Unknown content field in " + str(mod.id))
		for key in extra:
			if key in ["units", "buildings", "technologies", "events", "panels"]:
				if not extra[key] is Array: return failure("Expected content array: " + key)
				content[key].append_array(extra[key])
			elif key in ["translations", "theme", "assets"]:
				if not extra[key] is Dictionary: return failure("Expected content object: " + key)
				if key == "translations":
					for locale in extra[key]:
						if not extra[key][locale] is Dictionary: return failure("Expected translation catalog")
						if not content.translations.has(locale): content.translations[locale] = {}
						content.translations[locale].merge(extra[key][locale], true)
				else: content[key].merge(extra[key], true)
			else: content[key] = extra[key]
	var problem = validate(content, balance, base)
	if not problem.is_empty(): return failure(problem)
	for unit in content.units:
		balance.unit_cost.append(unit.cost)
		balance.unit_weight.append(unit.weight)
		balance.recruit_units.append(unit.recruit)
		balance.start_units.append(unit.get("start", 0))
	return {"error": "", "balance": balance, "content": content, "sources": sources, "conflicts": conflicts}

static func failure(problem: String) -> Dictionary:
	return {"error": problem}

static func validate(c: Dictionary, balance: Dictionary, base: Dictionary) -> String:
	# Keep legacy balance validation in Package, without a preload cycle.
	if not load("res://src/mod_package.gd").balance_valid(balance, base): return "Invalid composed balance"
	var unit_ids = UNIT_IDS.duplicate()
	if c.units.size() > MAX_UNITS - 3 or c.buildings.size() > 32 or c.technologies.size() > 32 or c.events.size() > 128 or c.panels.size() > 16: return "Content limit exceeded"
	var tech_ids = []
	for tech in c.technologies:
		if not keys(tech, ["id", "name", "cost", "requires", "unit", "bonus", "income"]) or not identifier(tech.get("id")) or tech.id in tech_ids or not text(tech.get("name"), 160) or not number(tech.get("cost"), 1): return "Invalid technology"
		tech_ids.append(tech.id)
	for unit in c.units:
		if not keys(unit, ["id", "name", "cost", "weight", "recruit", "start", "requires"]) or not identifier(unit.get("id")) or unit.id in unit_ids or not text(unit.get("name"), 160): return "Invalid unit"
		for key in ["cost", "weight", "recruit"]:
			if not number(unit.get(key), 1): return "Invalid unit " + key
		if not number(unit.get("start", 0)) or not ids(unit.get("requires", []), tech_ids): return "Invalid unit requirements"
		unit_ids.append(unit.id)
	var building_ids = []
	for building in c.buildings:
		if not keys(building, ["id", "name", "cost", "income", "requires"]) or not identifier(building.get("id")) or building.id in building_ids or not text(building.get("name"), 160): return "Invalid building"
		if not number(building.get("cost"), 1) or not number(building.get("income")) or not ids(building.get("requires", []), tech_ids): return "Invalid building values"
		building_ids.append(building.id)
	var visited = []
	for tech in c.technologies:
		if not ids(tech.get("requires", []), visited) or not tech.get("unit", "infantry") in unit_ids or not number(tech.get("bonus", 0), 0, 1, false) or not number(tech.get("income", 0)): return "Technology dependencies must be earlier; invalid bonus"
		visited.append(tech.id)
	var ai = c.ai
	if not keys(ai, ["priorities", "attack_ratio", "targets", "retreat_ratio"]): return "content.ai: unknown field"
	if not number(ai.get("attack_ratio", 1), 0, 2, false) or not number(ai.get("retreat_ratio", 0), 0, 2, false) or not ai.get("targets", "weakest") in ["weakest", "income", "nearest"]: return "content.ai: invalid attack/retreat/targets"
	if not ai.get("priorities", []) is Array or ai.get("priorities", []).size() > 32: return "content.ai.priorities: limit 32"
	for i in ai.get("priorities", []).size():
		var p = ai.priorities[i]
		if not keys(p, ["action", "id", "reserve", "max_level"]) or not p.get("action") in ["research", "construct", "recruit", "upgrade", "business"] or not number(p.get("reserve", 0), 0, 100000000) or not number(p.get("max_level", 10), 1): return "content.ai.priorities[%d]: invalid rule" % i
		var available = tech_ids if p.action == "research" else (building_ids if p.action == "construct" else unit_ids)
		if p.action != "business" and not p.get("id") in available: return "content.ai.priorities[%d].id: unknown reference" % i
	var atlas = c.get("map", JSON.parse_string(FileAccess.get_file_as_string("res://assets/world.json")))
	var count = atlas.size() if atlas is Array else 0
	if count < 3 or count > MAX_COUNTRIES: return "Map must contain 3..512 countries"
	if c.has("map"):
		for i in count:
			var country = atlas[i]
			if not country is Dictionary or country.get("id") != i or not text(country.get("name"), 160) or not text(country.get("english"), 160) or not text(country.get("continent"), 80): return "Invalid map country"
			if not point(country.get("center")) or not country.get("rings") is Array or country.rings.is_empty() or country.rings.size() > 64: return "Invalid map geometry"
			var points = 0
			for ring in country.rings:
				if not ring is Array or ring.size() < 3 or ring.size() > 2000 or not ring.all(point): return "Invalid map ring"
				points += ring.size()
			if points > 10000 or not number(country.get("sovereign"), 0, count - 1): return "Invalid map references"
			for key in ["neighbors", "enclave_hosts", "dependencies"]:
				if not country.get(key) is Array or country[key].size() > count or not country[key].all(func(id): return number(id, 0, count - 1)) or i in country[key]: return "Invalid map links"
		for i in count:
			for neighbor in atlas[i].neighbors:
				if not i in atlas[int(neighbor)].neighbors: return "Map borders must be reciprocal"
	var scenario = c.scenario
	if not keys(scenario, ["name", "default_home", "starts", "armies", "alliances"]) or not text(scenario.get("name", ""), 160) or not number(scenario.get("default_home", 0), 0, count - 1): return "Invalid scenario"
	var branches = unit_ids.size()
	if not scenario.get("starts", {}) is Dictionary or scenario.get("starts", {}).size() > count or not scenario.get("armies", {}) is Dictionary: return "Invalid scenario starts"
	var reserved = []
	for key in scenario.get("starts", {}):
		if not str(key).is_valid_int() or not number(int(key), 0, count - 1): return "Invalid start country"
		var start = scenario.starts[key]
		if not keys(start, ["coins", "units", "levels", "owned", "researches"]) or not number(start.get("coins", balance.start_coins), 0, 100000000): return "Invalid scenario resources"
		for field in ["units", "levels"]:
			if start.has(field) and not army(start[field], branches, 1 if field == "levels" else 0): return "Invalid scenario army"
		if not ids(start.get("researches", []), tech_ids): return "Invalid initial research"
		var owned = start.get("owned", [])
		if not owned is Array or owned.size() > count or not owned.all(func(id): return number(id, 0, count - 1)): return "Invalid initial territories"
		var claimed = unique([int(key)] + owned)
		for id in claimed:
			if id in reserved or not atlas[int(id)].enclave_hosts.is_empty(): return "Scenario starts overlap or include hidden microstate"
		reserved.append_array(claimed)
	for key in scenario.get("armies", {}):
		if not str(key).is_valid_int() or not number(int(key), 0, count - 1) or not army(scenario.armies[key], branches): return "Invalid scenario garrison"
	if not scenario.get("alliances", []) is Array or scenario.get("alliances", []).size() > 32: return "Invalid alliances"
	var allies = []
	for group in scenario.get("alliances", []):
		if not group is Array or group.size() < 2 or group.size() > count: return "Invalid alliance"
		for id in group:
			if not number(id, 0, count - 1) or id in allies: return "Alliance groups overlap"
			allies.append(id)
	var goal = c.victory
	if not keys(goal, ["type", "amount", "countries", "seconds"]): return "Invalid victory condition"
	if not goal.is_empty():
		if not goal.get("type") in ["world", "coins", "countries", "hold", "time"]: return "Unknown victory type"
		if goal.type == "coins" and not number(goal.get("amount"), 1, 100000000): return "Invalid victory amount"
		if goal.type in ["countries", "hold"] and (not goal.get("countries") is Array or goal.countries.is_empty() or not goal.countries.all(func(id): return number(id, 0, count - 1))): return "Invalid victory countries"
		if goal.type in ["hold", "time"] and not number(goal.get("seconds"), 1): return "Invalid victory time"
	var event_ids = []
	var flag_ids = []
	for event_index in c.events.size():
		var event = c.events[event_index]
		var event_path = "content.events[%d]" % event_index
		if not keys(event, ["id", "when", "conditions", "actions", "once", "cooldown"]) or not identifier(event.get("id")) or event.id in event_ids or not event.get("when") in TRIGGERS: return event_path + ": Invalid event"
		if not event.get("once", true) is bool or not number(event.get("cooldown", 1), 1): return event_path + ": Invalid event schedule"
		var condition = event.get("conditions", {})
		if not keys(condition, ["country_id", "elapsed_min", "coins_min", "owns", "researches", "flags", "chance"]): return event_path + ": Unknown event condition"
		if not number(condition.get("country_id", 0), 0, count - 1) or not number(condition.get("elapsed_min", 0)) or not number(condition.get("coins_min", 0), 0, 100000000) or not number(condition.get("chance", 100), 0, 100): return event_path + ": Invalid event condition values"
		if not condition.get("owns", []) is Array or not condition.get("owns", []).all(func(id): return number(id, 0, count - 1)) or not ids(condition.get("researches", []), tech_ids): return event_path + ": Invalid event condition references"
		if not condition.get("flags", {}) is Dictionary or condition.get("flags", {}).size() > 32: return event_path + ": Invalid flags"
		for flag in condition.get("flags", {}):
			if not identifier(flag) or not flag_value(condition.flags[flag]): return event_path + ": Invalid flag condition"
		if not event.get("actions") is Array or event.actions.is_empty() or event.actions.size() > 16: return event_path + ": Invalid event actions"
		for action_index in event.actions.size():
			var action = event.actions[action_index]
			var action_path = event_path + ".actions[%d]" % action_index
			if not keys(action, ["type", "amount", "unit", "text", "key", "value", "technology", "country_id"]) or not action.get("type") in ACTIONS: return action_path + ": Unknown event action"
			if not number(action.get("amount", 0), -1000000) or not action.get("unit", "infantry") in unit_ids or not text(action.get("text", ""), 400): return action_path + ": Invalid action values"
			if action.type == "set_flag" and (not identifier(action.get("key")) or not flag_value(action.get("value"))): return action_path + ": Invalid flag action"
			if action.type == "set_flag" and not action.key in flag_ids: flag_ids.append(action.key)
			if flag_ids.size() > 128: return event_path + ": Too many event flags"
			if action.type == "grant_research" and not action.get("technology") in tech_ids: return action_path + ": Unknown research reward"
			if action.type in ["capture_country", "release_country"] and not number(action.get("country_id"), 0, count - 1): return action_path + ": Invalid event country"
		event_ids.append(event.id)
	if not keys(c.theme, COLORS): return "Unknown theme color"
	for value in c.theme.values():
		if not text(value, 9) or not Color.html_is_valid(value): return "Invalid theme color"
	if not keys(c.translations, ["ru", "en"]): return "Supported translation locales: ru, en"
	for catalog in c.translations.values():
		if not catalog is Dictionary or catalog.size() > 512: return "Translation limit exceeded"
		for key in catalog:
			if not text(key) or not text(catalog[key]): return "Invalid translation"
	var panel_ids = []
	for panel in c.panels:
		if not keys(panel, ["id", "title", "text", "action"]) or not identifier(panel.get("id")) or not text(panel.get("title"), 160) or not text(panel.get("text", "")): return "Invalid UI panel"
		if panel.id in panel_ids: return "Duplicate UI panel"
		panel_ids.append(panel.id)
		if not panel.get("action", "") in ["", "army", "economy", "countries", "notifications"]: return "Unknown UI command"
	if not c.assets is Dictionary or c.assets.size() > 64: return "Invalid media catalog"
	for key in c.assets:
		if key.begins_with("flag:") and not number(int(key.trim_prefix("flag:")), 0, count - 1): return "Invalid flag country"
		if not text(key, 160) or not media(c.assets[key], key): return "Invalid media: " + str(key)
	return ""

static func media(value: Variant, key: String) -> bool:
	if not keys(value, ["mime", "data"]): return false
	if not value.get("mime") in ["image/png", "audio/wav"] or not value.get("data") is String or value.data.length() > 262144: return false
	if not (key.begins_with("flag:") and key.trim_prefix("flag:").is_valid_int()) and not (key.begins_with("sound:") and identifier(key.trim_prefix("sound:"))): return false
	var bytes = Marshalls.base64_to_raw(value.data)
	if bytes.is_empty() or bytes.size() > 196608 or Marshalls.raw_to_base64(bytes) != value.data: return false
	if key.begins_with("sound:"): return value.mime == "audio/wav" and bytes.size() >= 44 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE"
	if value.mime == "image/png": return bytes.size() >= 24 and bytes.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) and big32(bytes, 16) > 0 and big32(bytes, 16) <= 1024 and big32(bytes, 20) > 0 and big32(bytes, 20) <= 1024
	return false

static func flag_value(value: Variant) -> bool:
	return value is bool or number(value, -1000000)

static func army(value: Variant, count: int, minimum: int = 0) -> bool:
	return value is Array and value.size() == count and value.all(func(n): return number(n, minimum, 100000000))

static func point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number(value[0], -180, 180, false) and number(value[1], -90, 90, false)

static func big32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | bytes[offset + 3]
