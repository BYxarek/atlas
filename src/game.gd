extends RefCounted

const L = preload("res://src/i18n.gd")
## All simulation state is separate from the scene and can be tested headlessly.
signal sound_requested(cue: String)
signal units_recruited(kind: int, amount: int)

static var COUNTRY_COUNT: int = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world.json")).size()
const LEGACY_COUNTRY_COUNT = 176
static var MICROSTATES: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world.json")).filter(func(c): return not c.enclave_hosts.is_empty()).map(func(c): return int(c.id))
const SAVE_PATH = "user://campaign.json"
const Runtime = preload("res://src/mod_runtime.gd")
static var UNIT_NAMES: Array = ["Пехота", "Авиация", "Флот"] + Runtime.content().get("units", []).map(func(unit): return unit.name)
static var B: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))
static var UNIT_COUNT: int = B.unit_cost.size()
static var UNIT_COST = B.unit_cost
static var UNIT_WEIGHT = B.unit_weight
static var NUCLEAR_THRESHOLD: int = int(B.nuclear_threshold)
static var START_UNITS: Array = B.start_units.map(func(n): return int(n))
static var START_COINS = B.start_coins
var atlas: Array = []
var military: Dictionary = {}
var countries: Array = []
var home = -1
var coins = 180.0
var elapsed = 0
var units: Array = START_UNITS.duplicate()
var levels: Array = base_levels()
var mission: Dictionary = {}
var reports: Dictionary = {}
var events: Array = []
var paused = false
var finished = false
var player_color = Color("69dfbd")
var campaign_id = ""
var operations: Array = []
var conquests: Array = []
var nukes = 0
var victories = 0
var defeats = 0
var effects: Array = []
var warnings: Array = []
var notification_serial = 0
var notifications_seen = 0
var rng = RandomNumberGenerator.new()
var network_game = false
var enemy_levels: Dictionary = {}
var enemy_bonuses: Dictionary = {}
var country_colors: Dictionary = {}
var country_owners: Dictionary = {}
var remote_operations: Array = []
var wars: Array = []
var rebel_bonus = 1
var battles: Array = []
var mod_state: Dictionary = {}
var allied_countries: Array = []

func _init() -> void:
	atlas = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world.json"))
	assert(atlas.size() == COUNTRY_COUNT)
	military = JSON.parse_string(FileAccess.get_file_as_string("res://assets/military.json"))
	rng.randomize()
	reset()

func reset() -> void:
	network_game = false
	enemy_levels = {}
	enemy_bonuses = {}
	country_colors = {}
	country_owners = {}
	remote_operations = []
	wars = []
	battles = []
	mod_state = {}
	allied_countries = []
	countries.clear()
	for i in atlas.size():
		var local_rng = RandomNumberGenerator.new()
		local_rng.seed = i * 319 + 71
		var businesses: Array = []
		for j in (1 if Runtime.content().has("map") else local_rng.randi_range(1, 5)):
			businesses.append(1)
		countries.append({"owned": false, "businesses": businesses,
			"units": military.armies[i].map(func(n): return int(n))})
	home = -1
	coins = 180.0
	elapsed = 0
	units = START_UNITS.duplicate()
	levels = base_levels()
	mission = {}
	reports = {}
	events = []
	paused = false
	finished = false
	player_color = Color("69dfbd")
	campaign_id = "campaign_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	operations = []
	conquests = []
	nukes = 0
	victories = 0
	defeats = 0
	effects = []
	warnings = []
	notification_serial = 0
	notifications_seen = 0

func start(id: int) -> void:
	if id < 0 or id >= countries.size() or not country_visible(id) or home != -1:
		return
	home = id
	countries[id].owned = true
	units = START_UNITS.duplicate()
	coins = START_COINS
	Runtime.start(self)
	log_event("Поднят ваш флаг: %s. История начинается." % atlas[id].name)
	sound_requested.emit("start")

func owned_count() -> int:
	var total = 0
	for c in countries:
		if c.owned:
			total += 1
	return total

func country_visible(id: int) -> bool:
	return atlas[id].enclave_hosts.is_empty() or countries[id].owned or countries[id].get("microstate", "hidden") != "hidden"

func controls_world() -> bool:
	var objective = Runtime.victory(self)
	if objective != null: return bool(objective) and owned_count() > 0
	for i in countries.size():
		if countries[i].owned: continue
		if not country_visible(i) and float(home) in atlas[i].enclave_hosts: continue
		return false
	return home >= 0

func settle_microstate(id: int, peaceful: bool) -> void:
	countries[id]["microstate"] = "accepted" if peaceful else "war"
	if peaceful:
		countries[id].owned = true
		log_event("Микрогосударство %s приняло вашу власть и мирно присоединилось." % atlas[id].name)
		sound_requested.emit("victory")
	else:
		if not id in wars: wars.append(id)
		log_event("Микрогосударство %s отвергло вашу власть и объявило вам войну!" % atlas[id].name)
		sound_requested.emit("warning")

func resolve_microstates(host: int) -> void:
	for id in MICROSTATES:
		if not country_visible(id) and float(host) in atlas[id].enclave_hosts:
			settle_microstate(id, rng.randi_range(0, 99) < B.microstate_accept_chance)

func income() -> int:
	var total = 0
	for c in countries:
		if c.owned:
			for level in c.businesses:
				total += int(level)
	return total + Runtime.extra_income(self)

static func base_levels() -> Array:
	return range(UNIT_COUNT).map(func(_i): return 1)

func power(army: Array, upgrades: Array = [], bonuses: Array = []) -> float:
	if upgrades.is_empty(): upgrades = base_levels()
	var result = 0.0
	for i in UNIT_COUNT:
		result += army[i] * UNIT_WEIGHT[i] * (1.0 + (upgrades[i] - 1) * B.technology_bonus + (float(bonuses[i]) if not bonuses.is_empty() else (Runtime.unit_bonus(self, i) if is_same(army, units) else 0.0)))
	return result

func migrate_legacy_armies() -> int:
	var updated = 0
	for i in countries.size():
		if countries[i].owned or i == home or i in conquests: continue
		if operations.any(func(op): return op.kind == "enemy" and int(op.from) == i): continue
		var legacy_rng = RandomNumberGenerator.new()
		legacy_rng.seed = i * 319 + 71
		legacy_rng.randi_range(1, 5)
		var reinforcements = elapsed / 30
		var legacy = [legacy_rng.randi_range(18, 70) + reinforcements, legacy_rng.randi_range(3, 20), legacy_rng.randi_range(0, 12)]
		if countries[i].units == legacy:
			countries[i].units = military.armies[i].map(func(n): return int(n))
			countries[i].units[0] += reinforcements
			for warning in warnings:
				if warning.status == "pending" and int(warning.attacker) == i: warning.status = "cancelled"
			updated += 1
	return updated

func border(id: int) -> bool:
	for neighbor in atlas[id].neighbors:
		if countries[int(neighbor)].owned:
			return true
	return false

func recruit(kind: int) -> bool:
	if not can_act() or kind < 0 or kind >= UNIT_COUNT or not Runtime.unit_available(self, kind) or coins < UNIT_COST[kind]:
		return false
	coins -= UNIT_COST[kind]
	units[kind] += int(B.recruit_units[kind])
	units_recruited.emit(kind, int(B.recruit_units[kind]))
	sound_requested.emit("coins")
	return true

func upgrade_cost(kind: int) -> int:
	return int(B.technology_cost) * levels[kind]

func upgrade_army(kind: int) -> bool:
	if not can_act() or kind < 0 or kind >= UNIT_COUNT or not Runtime.unit_available(self, kind) or coins < upgrade_cost(kind):
		return false
	coins -= upgrade_cost(kind)
	levels[kind] += 1
	log_event("%s: технология уровня %d." % [UNIT_NAMES[kind], levels[kind]])
	sound_requested.emit("upgrade")
	return true

func business_cost(id: int, slot: int) -> int:
	return int(B.business_cost) * countries[id].businesses[slot]

func upgrade_business(id: int, slot: int) -> bool:
	if not can_act() or id < 0 or id >= countries.size() or not countries[id].owned:
		return false
	if slot < 0 or slot >= countries[id].businesses.size() or coins < business_cost(id, slot):
		return false
	coins -= business_cost(id, slot)
	countries[id].businesses[slot] += 1
	sound_requested.emit("coins")
	return true

func spy(id: int) -> bool:
	if not can_act() or id < 0 or id >= countries.size() or not country_visible(id) or countries[id].owned or not mission.is_empty() or coins < B.spy_cost:
		return false
	coins -= B.spy_cost
	mission = {"target": id, "from": origin_for(id), "start": elapsed, "arrival": elapsed + int(B.spy_seconds)}
	log_event("Агент направлен: %s. Отчёт через %d секунд." % [atlas[id].name, B.spy_seconds])
	sound_requested.emit("spy_send")
	return true

func attack_cost(id: int) -> int:
	return int(B.attack_cost if border(id) else B.naval_cost)

func attack_block(id: int) -> String:
	if not can_act():
		return "Кампания приостановлена"
	if id < 0 or id >= countries.size() or not country_visible(id) or countries[id].owned:
		return "Выберите чужую страну"
	if id in allied_countries or Runtime.allied(home, id): return "Allied country"
	if has_operation("attack"):
		return "Армия уже на марше"
	if not border(id) and units[2] < B.naval_ships:
		return "Для морской операции нужно %d кораблей" % B.naval_ships
	if power(units, levels) < 1:
		return "Наберите войска"
	if coins < attack_cost(id):
		return "Недостаточно монет"
	return ""

func attack(id: int) -> Dictionary:
	if attack_block(id) != "":
		return {}
	coins -= attack_cost(id)
	return resolve_attack(id, not border(id))

func resolve_attack(id: int, overseas: bool) -> Dictionary:
	if countries[id].owned:
		return {}
	sound_requested.emit("battle_naval" if overseas else "battle")
	if not id in wars: wars.append(id)
	var attackers = units.duplicate()
	var defenders = countries[id].units.duplicate()
	var defender_levels = enemy_levels.get(str(id), base_levels())
	var support = 0
	var strength = power(units, levels)
	var defense = power(countries[id].units, enemy_levels.get(str(id), base_levels()), enemy_bonuses.get(str(id), []))
	if rebel_country(id):
		support = rebel_bonus if network_game else rng.randi_range(1, 10)
		defense *= 1.0 - support / 100.0
		log_event("Повстанцы в %s помогли наступлению: сила обороны снижена на %d%%." % [atlas[id].name, support])
	var effective = strength * (B.naval_multiplier if overseas else 1.0)
	var victory = effective >= defense
	var loss_rate = clampf(defense / maxf(effective, 1.0) * B.attack_loss, B.attack_loss_min, B.attack_loss_max)
	var losses: Array = []
	for i in UNIT_COUNT:
		var lost = mini(units[i], ceili(units[i] * loss_rate))
		units[i] -= lost
		losses.append(lost)
	if victory:
		victories += 1
		countries[id].owned = true
		if not network_game and rebel_country(id): countries[id]["rebellion"] = {"previous_owned": false, "due": elapsed + rng.randi_range(120, 420)}
		if id != home and not id in conquests:
			conquests.append(id)
			if conquests.size() % NUCLEAR_THRESHOLD == 0:
				nukes += 1
				log_event("Ядерный арсенал: получен 1 удар за %d уникальных захватов." % conquests.size())
				sound_requested.emit("unlock")
		coins += B.loot
		Runtime.emit_event(self, "country_captured", id)
		log_event("Победа! %s под вашим контролем. Трофеи: %d монет." % [atlas[id].name, B.loot])
		if not network_game: resolve_microstates(id)
		if not network_game and controls_world():
			finished = true
			log_event("МИР ОБЪЕДИНЁН. Вы завершили мировую кампанию!")
	else:
		defeats += 1
		for i in UNIT_COUNT:
			countries[id].units[i] = maxi(0, countries[id].units[i] - ceili(countries[id].units[i] * B.defender_hold_loss))
		log_event("Отступление из %s. Усильте армию перед новой атакой." % atlas[id].name)
	var defender_losses = defenders.map(func(n): return ceili(n * (B.defender_retreat_loss if victory and network_game and enemy_levels.has(str(id)) else (1.0 if victory else B.defender_hold_loss))))
	record_battle(id, true, victory, attackers, defenders, levels, defender_levels, effective, defense, overseas, support, losses, defender_losses)
	effects.append({"kind": "victory" if victory else "defeat", "target": id})
	sound_requested.emit("campaign_win" if finished else ("victory" if victory else "defeat"))
	return {"victory": victory, "losses": losses, "overseas": overseas}

func record_battle(target: int, attacking: bool, won: bool, attackers: Array, defenders: Array, attack_levels: Array, defense_levels: Array, effective: float, defense: float, overseas: bool, rebels: int, attack_losses: Array, defense_losses: Array) -> void:
	battles.push_front({"target": target, "time": elapsed, "attacking": attacking, "won": won,
		"attackers": attackers.duplicate(), "defenders": defenders.duplicate(), "attack_levels": attack_levels.duplicate(),
		"defense_levels": defense_levels.duplicate(), "effective": effective, "defense": defense,
		"overseas": overseas, "rebels": rebels, "attack_losses": attack_losses.duplicate(), "defense_losses": defense_losses.duplicate()})
	if battles.size() > 20: battles.resize(20)

func origin_for(id: int) -> int:
	for neighbor in atlas[id].neighbors:
		if countries[int(neighbor)].owned:
			return int(neighbor)
	if home >= 0 and countries[home].owned:
		return home
	for i in countries.size():
		if countries[i].owned:
			return i
	return maxi(0, home)

func has_operation(kind: String) -> bool:
	return operations.any(func(op): return op.kind == kind)

func dispatch_attack(id: int) -> bool:
	if attack_block(id) != "":
		return false
	coins -= attack_cost(id)
	if not id in wars: wars.append(id)
	operations.append({"kind": "attack", "from": origin_for(id), "target": id,
		"start": elapsed, "arrival": elapsed + int(B.attack_seconds), "overseas": not border(id)})
	log_event("Армия выдвинулась: %s. Прибытие через %d секунд." % [atlas[id].name, B.attack_seconds])
	sound_requested.emit("march_naval" if not border(id) else "march")
	return true

func nuclear_strike(id: int) -> bool:
	if not can_act() or nukes < 1 or id < 0 or id >= countries.size() or not country_visible(id) or countries[id].owned or has_operation("nuke"):
		return false
	nukes -= 1
	operations.append({"kind": "nuke", "from": origin_for(id), "target": id,
		"start": elapsed, "arrival": elapsed + int(B.nuke_seconds)})
	log_event("Ядерная ракета запущена: %s. Подлёт — %d секунд." % [atlas[id].name, B.nuke_seconds])
	sound_requested.emit("rocket_launch")
	return true

func launch_enemy_attack(attacker: int, target: int, surprise: bool = false) -> bool:
	if not can_act() or owned_count() <= 1 or has_operation("enemy") or attacker < 0 or attacker >= countries.size() or target < 0 or target >= countries.size():
		return false
	if not country_visible(attacker): return false
	var warning = pending_warning()
	if not surprise and (warning.is_empty() or int(warning.attacker) != attacker or elapsed < warning.deadline or elapsed - warning.issued > 300):
		return false
	if countries[attacker].owned or not countries[target].owned:
		return false
	var overseas = not atlas[attacker].neighbors.any(func(neighbor): return int(neighbor) == target)
	if overseas and countries[attacker].units[2] < B.naval_ships:
		return false
	if not surprise: warning.status = "launched"
	operations.append({"kind": "enemy", "from": attacker, "target": target,
		"start": elapsed, "arrival": elapsed + 5, "overseas": overseas, "surprise": surprise})
	if not surprise:
		if not attacker in wars: wars.append(attacker)
		log_event("ТРЕВОГА: %s атакует %s. До боя — 5 секунд!" % [enemy_name(attacker), atlas[target].name])
		sound_requested.emit("invasion")
	return true

func resolve_enemy_attack(attacker: int, target: int, overseas: bool) -> void:
	if owned_count() <= 1:
		log_event("Вторжение отменено: последняя страна находится под защитой.")
		return
	if countries[attacker].owned or not countries[target].owned:
		log_event("Вражеское наступление отменено: контроль территории изменился.")
		sound_requested.emit("all_clear")
		return
	sound_requested.emit("battle_naval" if overseas else "battle")
	if not attacker in wars: wars.append(attacker)
	var attackers = countries[attacker].units.duplicate()
	var defenders = units.duplicate()
	var assault = power(countries[attacker].units) * (B.naval_multiplier if overseas else 1.0)
	var defense = power(units, levels)
	var lost_territory = assault > defense
	var loss_rate = clampf(assault / maxf(defense, 1.0) * 0.2, 0.04, 0.6)
	for i in UNIT_COUNT:
		units[i] = maxi(0, units[i] - ceili(units[i] * loss_rate))
		countries[attacker].units[i] = maxi(0, countries[attacker].units[i] - ceili(countries[attacker].units[i] * (0.12 if lost_territory else 0.35)))
	record_battle(target, false, not lost_territory, attackers, defenders, base_levels(), levels, assault, defense, overseas, 0, attackers.map(func(n): return ceili(n * (0.12 if lost_territory else 0.35))), range(UNIT_COUNT).map(func(i): return defenders[i] - units[i]))
	if lost_territory:
		defeats += 1
		countries[target].owned = false
		if not target in wars: wars.append(target)
		if rebel_country(target): countries[target]["rebellion"] = {"previous_owned": true, "due": elapsed + rng.randi_range(120, 420)}
		# Half the surviving attackers stay behind as the new garrison.
		for i in UNIT_COUNT:
			var garrison = floori(countries[attacker].units[i] * 0.5)
			countries[attacker].units[i] -= garrison
			countries[target].units[i] = garrison
		log_event("Потеря территории: %s. Противник: %s. Её доход утрачен." % [atlas[target].name, enemy_name(attacker)])
		if owned_count() == 0:
			finished = true
			log_event("ПОРАЖЕНИЕ: потеряны все территории. Кампания завершена.")
	else:
		victories += 1
		log_event("Оборона удержана: %s. Противник: %s. Атака отбита!" % [atlas[target].name, enemy_name(attacker)])
	effects.append({"kind": "defeat" if lost_territory else "victory", "target": target})
	sound_requested.emit("campaign_lose" if finished else ("defeat" if lost_territory else "victory"))

func can_act() -> bool:
	return home >= 0 and not paused and not finished

func pending_warning() -> Dictionary:
	for warning in warnings:
		if warning.status == "pending":
			return warning
	return {}

func warning_description(warning: Dictionary) -> String:
	var id = int(warning.attacker)
	return "%s · сила примерно %d–%d" % [enemy_name(id), warning.low, warning.high]

func enemy_name(id: int) -> String:
	return atlas[id].name if reports.has(str(id)) else "Неизвестная страна"

func schedule_warning() -> bool:
	if not can_act() or owned_count() <= 1 or not pending_warning().is_empty() or has_operation("enemy"):
		return false
	var candidates: Array = []
	for i in countries.size():
		if country_visible(i) and not countries[i].owned and border(i): candidates.append(i)
	if candidates.is_empty():
		for i in countries.size():
			if country_visible(i) and not countries[i].owned and countries[i].units[2] >= 4: candidates.append(i)
	if candidates.is_empty(): return false
	var enemy = candidates[rng.randi_range(0, candidates.size() - 1)]
	var strength = power(countries[enemy].units)
	var lead = rng.randi_range(60, 300)
	var warning = {"attacker": enemy, "issued": elapsed, "deadline": elapsed + lead,
		"low": maxi(0, floori(strength * 0.65 / 10) * 10),
		"high": maxi(10, ceili(strength * 1.35 / 10) * 10), "status": "pending"}
	warnings.push_front(warning)
	if warnings.size() > 40: warnings.resize(40)
	log_event("Возможная атака: %s. Ожидаемый срок — через %d:%02d. Данные не подтверждены." % [warning_description(warning), lead / 60, lead % 60])
	sound_requested.emit("warning")
	return true

func cancel_protected_attacks() -> bool:
	if owned_count() > 1: return false
	var warning = pending_warning()
	var changed = not warning.is_empty() or has_operation("enemy")
	if not warning.is_empty(): warning.status = "cancelled"
	operations = operations.filter(func(op): return op.kind != "enemy")
	if changed:
		log_event("Угроза снята: пока у вас одна страна, нападения запрещены.")
		sound_requested.emit("all_clear")
	return changed

func tick() -> bool:
	if not can_act():
		return false
	elapsed += 1
	coins += income()
	var changed = cancel_protected_attacks()
	for op in operations.duplicate():
		if elapsed < op.arrival:
			continue
		operations.erase(op)
		var target = int(op.target)
		match op.kind:
			"attack": resolve_attack(target, op.overseas)
			"enemy":
				if op.get("surprise", false): log_event("Внезапное нападение на %s!" % atlas[target].name)
				resolve_enemy_attack(int(op.from), target, op.overseas)
			"nuke":
				if countries[target].owned:
					nukes += 1
					log_event("Ядерный удар отменён: цель уже ваша. Заряд возвращён.")
					sound_requested.emit("all_clear")
				else:
					for i in UNIT_COUNT:
						countries[target].units[i] = floori(countries[target].units[i] * 0.5)
					effects.append({"kind": "nuke", "target": target})
					log_event("Ядерный удар: %s. Каждый род войск сокращён на 50%%." % atlas[target].name)
					sound_requested.emit("nuke")
		changed = true
		if finished:
			operations.clear()
			mission = {}
			break
	if finished:
		return true
	if not mission.is_empty() and elapsed >= mission.arrival:
		var id = int(mission.target)
		reports[str(id)] = {"units": countries[id].units.duplicate(), "time": elapsed}
		mission = {}
		Runtime.emit_event(self, "mission_completed", id)
		log_event("Разведка завершена: %s. Состав войск раскрыт." % atlas[id].name)
		sound_requested.emit("report")
		changed = true
	Runtime.tick(self)
	if network_game: return changed
	for id in countries.size():
		var rebellion = countries[id].get("rebellion", {})
		if rebellion.is_empty() or elapsed < rebellion.due: continue
		rebellion.due = elapsed + rng.randi_range(120, 420)
		if rng.randf() >= 0.2: continue
		countries[id].owned = rebellion.previous_owned
		if not id in wars: wars.append(id)
		countries[id].erase("rebellion")
		log_event("Повстанцы вернули %s прежнему владельцу." % atlas[id].name)
		sound_requested.emit("victory" if countries[id].owned else "defeat")
		changed = true
	finished = owned_count() == 0 or owned_count() == countries.size()
	if finished:
		operations.clear()
		mission = {}
		return true
	if elapsed % 30 == 0:
		for c in countries:
			if not c.owned:
				c.units[0] += 1
		changed = true
	changed = cancel_protected_attacks() or changed
	var warning = pending_warning()
	if not warning.is_empty():
		if countries[int(warning.attacker)].owned:
			warning.status = "cancelled"
			log_event("Угроза снята: страна-источник теперь под вашим контролем.")
			sound_requested.emit("all_clear")
			changed = true
		elif elapsed >= warning.deadline:
			if rng.randf() >= 0.6 or not launch_enemy_attack(int(warning.attacker), origin_for(int(warning.attacker))):
				warning.status = "cancelled"
				log_event("Слух не подтвердился: %s. Наступление не началось." % warning_description(warning))
				sound_requested.emit("all_clear")
			changed = true
	elif elapsed % 45 == 0:
		if owned_count() > 1 and rng.randf() < 0.2:
			var candidates = range(countries.size()).filter(func(id): return country_visible(id) and not countries[id].owned and (border(id) or countries[id].units[2] >= 4))
			if not candidates.is_empty():
				var attacker = candidates[rng.randi_range(0, candidates.size() - 1)]
				changed = launch_enemy_attack(attacker, origin_for(attacker), true) or changed
		else: changed = schedule_warning() or changed
	return changed

func log_event(message: String) -> void:
	notification_serial += 1
	events.push_front({"time": elapsed, "text": message})
	if events.size() > 40:
		events.resize(40)

func export_data() -> Dictionary:
	return {"version": 3, "mod_state": mod_state, "allied_countries": allied_countries, "mods": Engine.get_meta("atlas_mods", ""), "home": home, "coins": coins, "elapsed": elapsed,
		"units": units, "levels": levels, "countries": countries, "mission": mission,
		"reports": reports, "events": events, "player_color": player_color.to_html(false),
		"campaign_id": campaign_id, "operations": operations, "conquests": conquests,
		"nukes": nukes, "victories": victories, "defeats": defeats, "warnings": warnings,
		"notification_serial": notification_serial, "notifications_seen": notifications_seen,
		"military_balance": military.balance_version, "wars": wars, "battles": battles, "rules_version": B.version}

func rebel_country(id: int) -> bool:
	return id % 3 == 0 and power(military.armies[id]) >= 300

func save_game(path: String = SAVE_PATH) -> Error:
	if home < 0:
		return ERR_UNCONFIGURED
	var data = export_data()
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	# Keep the last valid campaign until its replacement has been written completely.
	if FileAccess.file_exists(path):
		var backup_error = DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK:
			return backup_error
	return DirAccess.rename_absolute(path + ".tmp", path)

func valid_numbers(value: Variant, count: int, minimum: int = 0) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number in value:
		if not (number is float or number is int) or not is_finite(float(number)) or number < minimum or number > 100000000 or float(number) != floorf(float(number)):
			return false
	return true

func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return false
	return restore_data(parser.data)

func restore_data(data: Variant, announce_restore: bool = true) -> bool:
	if not data is Dictionary or data.get("mods", "") != Engine.get_meta("atlas_mods", ""): return false
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != 2 and data.get("version") != 3):
		return false
	if data.get("rules_version", B.version) != B.version: return false
	var saved_allies = data.get("allied_countries", [])
	if not valid_numbers(saved_allies, saved_allies.size() if saved_allies is Array else -1) or saved_allies.any(func(id): return id >= COUNTRY_COUNT): return false
	if data.get("countries") is Array and data.countries.size() == LEGACY_COUNTRY_COUNT:
		data = data.duplicate(true)
		var defaults = get_script().new().countries
		data.countries.append_array(defaults.slice(LEGACY_COUNTRY_COUNT))
	for key in ["home", "coins", "elapsed"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])):
			return false
	if data.home < 0 or data.home >= countries.size() or data.home != floorf(data.home) or data.coins < 0 or data.coins > 1e12 or data.elapsed < 0 or data.elapsed > 1e9 or data.elapsed != floorf(data.elapsed):
		return false
	if not Runtime.valid_state(data.get("mod_state", {}), int(data.get("elapsed", 0))): return false
	var saved_battles = data.get("battles", [])
	if not saved_battles is Array or saved_battles.size() > 20: return false
	for battle in saved_battles:
		if not battle is Dictionary: return false
		if not valid_numbers([battle.get("target"), battle.get("time"), battle.get("rebels")], 3) or battle.target >= countries.size() or battle.time > data.elapsed or battle.rebels > 10: return false
		for key in ["attacking", "won", "overseas"]:
			if not battle.get(key) is bool: return false
		for key in ["attackers", "defenders", "attack_losses", "defense_losses", "attack_levels", "defense_levels"]:
			if not valid_numbers(battle.get(key), UNIT_COUNT, 1 if key.ends_with("levels") else 0): return false
		for key in ["effective", "defense"]:
			if not (battle.get(key) is int or battle.get(key) is float) or not is_finite(float(battle[key])) or battle[key] < 0 or battle[key] > 1e18: return false
	if not valid_numbers(data.get("units"), UNIT_COUNT) or not valid_numbers(data.get("levels"), UNIT_COUNT, 1):
		return false
	if not data.get("countries") is Array or data.countries.size() != countries.size():
		return false
	for i in data.countries.size():
		var c = data.countries[i]
		if not c is Dictionary or not c.get("owned") is bool or not valid_numbers(c.get("units"), UNIT_COUNT):
			return false
		if c.has("microstate") and (atlas[i].enclave_hosts.is_empty() or not c.microstate in ["accepted", "war"]): return false
		if not c.get("businesses") is Array or c.businesses.size() < 1 or c.businesses.size() > 5 or not valid_numbers(c.businesses, c.businesses.size(), 1):
			return false
		if not Runtime.valid_structures(c.get("structures", {})): return false
		var rebellion = c.get("rebellion", {})
		if not rebellion is Dictionary: return false
		if not rebellion.is_empty() and (not rebellion.get("previous_owned") is bool or not valid_numbers([rebellion.get("due")], 1) or rebellion.due > data.elapsed + 420): return false
	var saved_mission = data.get("mission", {})
	var saved_wars = data.get("wars", [])
	if not saved_wars is Array or saved_wars.size() > countries.size() or not valid_numbers(saved_wars, saved_wars.size()): return false
	for id in saved_wars:
		if id >= countries.size(): return false
	if not saved_mission is Dictionary:
		return false
	if not saved_mission.is_empty():
		if not valid_numbers([saved_mission.get("target"), saved_mission.get("arrival")], 2) or saved_mission.target >= countries.size() or saved_mission.arrival > data.elapsed + int(B.spy_seconds):
			return false
		if not valid_numbers([saved_mission.get("from", data.home), saved_mission.get("start", maxi(0, int(saved_mission.arrival) - 6))], 2) or saved_mission.get("from", data.home) >= countries.size() or saved_mission.get("start", 0) > data.elapsed:
			return false
	var saved_reports = data.get("reports", {})
	if not saved_reports is Dictionary:
		return false
	for key in saved_reports:
		var report = saved_reports[key]
		if not str(key).is_valid_int() or int(key) < 0 or int(key) >= countries.size() or not report is Dictionary:
			return false
		if not valid_numbers(report.get("units"), UNIT_COUNT) or not valid_numbers([report.get("time")], 1) or report.time > data.elapsed:
			return false
	var saved_color = data.get("player_color", "69dfbd")
	if not saved_color is String or saved_color.length() != 6 or not Color.html_is_valid(saved_color):
		return false
	var saved_id = data.get("campaign_id", "legacy")
	if not saved_id is String or saved_id.is_empty() or saved_id.length() > 64:
		return false
	for character in saved_id:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	var saved_conquests = data.get("conquests", [])
	if not saved_conquests is Array or saved_conquests.size() > countries.size() or not valid_numbers(saved_conquests, saved_conquests.size()):
		return false
	var unique_conquests: Array = []
	for id in saved_conquests:
		if id >= countries.size() or id == data.home or int(id) in unique_conquests:
			return false
		unique_conquests.append(int(id))
	if not valid_numbers([data.get("nukes", 0), data.get("victories", 0), data.get("defeats", 0)], 3) or data.get("nukes", 0) > saved_conquests.size() / NUCLEAR_THRESHOLD:
		return false
	var saved_ops = data.get("operations", [])
	if not saved_ops is Array or saved_ops.size() > 3:
		return false
	var kinds: Array = []
	for op in saved_ops:
		if not op is Dictionary or not op.get("kind") in ["attack", "enemy", "nuke"] or op.kind in kinds:
			return false
		if not valid_numbers([op.get("from"), op.get("target"), op.get("start"), op.get("arrival")], 4):
			return false
		if op.from >= countries.size() or op.target >= countries.size() or op.start > data.elapsed or op.arrival <= op.start or op.arrival > data.elapsed + int(B.spy_seconds):
			return false
		if op.kind != "nuke" and not op.get("overseas") is bool:
			return false
		if not op.get("surprise", false) is bool: return false
		kinds.append(op.kind)
	var saved_events = data.get("events", [])
	if not saved_events is Array or saved_events.size() > 40:
		return false
	for entry in saved_events:
		if not entry is Dictionary or not entry.get("text") is String or entry.text.length() > 400 or not valid_numbers([entry.get("time")], 1) or entry.time > data.elapsed:
			return false
	var saved_warnings = data.get("warnings", [])
	if not saved_warnings is Array or saved_warnings.size() > 40: return false
	var pending_count = 0
	for warning in saved_warnings:
		if not warning is Dictionary or not warning.get("status") in ["pending", "cancelled", "launched"]: return false
		if not valid_numbers([warning.get("attacker"), warning.get("issued"), warning.get("deadline"), warning.get("low"), warning.get("high")], 5): return false
		if warning.attacker >= countries.size() or warning.issued > data.elapsed or warning.deadline - warning.issued < 60 or warning.deadline - warning.issued > 300 or warning.low >= warning.high: return false
		if warning.status == "pending":
			pending_count += 1
			if warning.deadline < data.elapsed: return false
	if pending_count > 1: return false
	if data.get("military_balance", 0) != 0 and data.get("military_balance") != military.balance_version: return false
	var saved_serial = data.get("notification_serial", saved_events.size())
	var saved_seen = data.get("notifications_seen", 0)
	if not valid_numbers([saved_serial, saved_seen], 2) or saved_seen > saved_serial: return false
	if data.version == 3:
		for op in saved_ops:
			if op.kind == "enemy" and not op.get("surprise", false) and not saved_warnings.any(func(w): return w.status == "launched" and w.attacker == op.from and w.deadline <= op.start and op.start - w.issued <= 300): return false
	else:
		# Legacy surprise invasions cannot bypass the new one-minute warning rule.
		saved_ops = saved_ops.filter(func(op): return op.kind != "enemy")
	home = int(data.home)
	coins = float(data.coins)
	elapsed = int(data.elapsed)
	units = data.units.map(func(n): return int(n))
	levels = data.levels.map(func(n): return int(n))
	countries = data.countries
	for c in countries:
		c.units = c.units.map(func(n): return int(n))
		c.businesses = c.businesses.map(func(n): return int(n))
	if not saved_mission.is_empty():
		saved_mission = {"target": int(saved_mission.target), "arrival": int(saved_mission.arrival),
			"from": int(saved_mission.get("from", home)), "start": int(saved_mission.get("start", maxi(0, int(saved_mission.arrival) - 6)))}
	for key in saved_reports:
		saved_reports[key].units = saved_reports[key].units.map(func(n): return int(n))
		saved_reports[key].time = int(saved_reports[key].time)
	mission = saved_mission
	reports = saved_reports
	events = saved_events
	player_color = Color(saved_color)
	campaign_id = saved_id
	conquests = unique_conquests
	nukes = int(data.get("nukes", 0))
	victories = int(data.get("victories", 0))
	defeats = int(data.get("defeats", 0))
	operations = saved_ops
	battles = saved_battles.duplicate(true)
	wars = saved_wars.map(func(id): return int(id))
	warnings = saved_warnings
	notification_serial = int(saved_serial)
	notifications_seen = int(saved_seen)
	if data.get("military_balance", 0) == 0:
		var updated = migrate_legacy_armies()
		if updated > 0: log_event("Военный баланс GFP 2026: обновлено %d нетронутых чужих армий. Старые разведданные могут устареть." % updated)
	effects = []
	paused = false
	mod_state = Runtime.Rules.numbers(data.get("mod_state", {}).duplicate(true))
	allied_countries = saved_allies.map(func(id): return int(id))
	finished = controls_world() or owned_count() == 0 or mod_state.get("result", "") == "lose"
	cancel_protected_attacks()
	if announce_restore: log_event("Кампания восстановлена. Добро пожаловать, командующий.")
	return true
