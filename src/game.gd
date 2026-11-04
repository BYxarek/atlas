extends RefCounted

const L = preload("res://src/i18n.gd")
## All simulation state is separate from the scene and can be tested headlessly.
signal sound_requested(cue: String)

const SAVE_PATH = "user://campaign.json"
const UNIT_NAMES = ["Пехота", "Авиация", "Флот"]
const UNIT_COST = [12, 28, 36]
const UNIT_WEIGHT = [1.0, 3.0, 4.0]
const NUCLEAR_THRESHOLD = 10
const START_UNITS = [35, 8, 4]
const START_COINS = 180.0
var atlas: Array = []
var military: Dictionary = {}
var countries: Array = []
var home = -1
var coins = 180.0
var elapsed = 0
var units: Array = [35, 8, 4]
var levels: Array = [1, 1, 1]
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
var country_colors: Dictionary = {}
var country_owners: Dictionary = {}
var remote_operations: Array = []

func _init() -> void:
	atlas = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world.json"))
	military = JSON.parse_string(FileAccess.get_file_as_string("res://assets/military.json"))
	rng.randomize()
	reset()

func reset() -> void:
	network_game = false
	enemy_levels = {}
	country_colors = {}
	country_owners = {}
	remote_operations = []
	countries.clear()
	for i in atlas.size():
		var local_rng = RandomNumberGenerator.new()
		local_rng.seed = i * 319 + 71
		var businesses: Array = []
		for j in local_rng.randi_range(1, 5):
			businesses.append(1)
		countries.append({"owned": false, "businesses": businesses,
			"units": military.armies[i].map(func(n): return int(n))})
	home = -1
	coins = 180.0
	elapsed = 0
	units = [35, 8, 4]
	levels = [1, 1, 1]
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
	if id < 0 or id >= countries.size() or home != -1:
		return
	home = id
	countries[id].owned = true
	units = START_UNITS.duplicate()
	coins = START_COINS
	log_event("Поднят ваш флаг: %s. История начинается." % atlas[id].name)
	sound_requested.emit("start")

func owned_count() -> int:
	var total = 0
	for c in countries:
		if c.owned:
			total += 1
	return total

func income() -> int:
	var total = 0
	for c in countries:
		if c.owned:
			for level in c.businesses:
				total += int(level)
	return total

func power(army: Array, upgrades: Array = [1, 1, 1]) -> float:
	var result = 0.0
	for i in 3:
		result += army[i] * UNIT_WEIGHT[i] * (1.0 + (upgrades[i] - 1) * 0.25)
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
	if not can_act() or kind < 0 or kind > 2 or coins < UNIT_COST[kind]:
		return false
	coins -= UNIT_COST[kind]
	units[kind] += [10, 3, 2][kind]
	sound_requested.emit("coins")
	return true

func upgrade_cost(kind: int) -> int:
	return 65 * levels[kind]

func upgrade_army(kind: int) -> bool:
	if not can_act() or kind < 0 or kind > 2 or coins < upgrade_cost(kind):
		return false
	coins -= upgrade_cost(kind)
	levels[kind] += 1
	log_event("%s: технология уровня %d." % [UNIT_NAMES[kind], levels[kind]])
	sound_requested.emit("upgrade")
	return true

func business_cost(id: int, slot: int) -> int:
	return 25 * countries[id].businesses[slot]

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
	if not can_act() or id < 0 or id >= countries.size() or countries[id].owned or not mission.is_empty() or coins < 20:
		return false
	coins -= 20
	mission = {"target": id, "from": origin_for(id), "start": elapsed, "arrival": elapsed + 6}
	log_event("Агент направлен: %s. Отчёт через 6 секунд." % atlas[id].name)
	sound_requested.emit("spy_send")
	return true

func attack_cost(id: int) -> int:
	return 25 if border(id) else 55

func attack_block(id: int) -> String:
	if not can_act():
		return "Кампания приостановлена"
	if id < 0 or id >= countries.size() or countries[id].owned:
		return "Выберите чужую страну"
	if has_operation("attack"):
		return "Армия уже на марше"
	if not border(id) and units[2] < 4:
		return "Для морской операции нужно 4 корабля"
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
	var strength = power(units, levels)
	var defense = power(countries[id].units, enemy_levels.get(str(id), [1, 1, 1]))
	var effective = strength * (0.85 if overseas else 1.0)
	var victory = effective >= defense
	var loss_rate = clampf(defense / maxf(effective, 1.0) * 0.23, 0.04, 0.55)
	var losses: Array = []
	for i in 3:
		var lost = mini(units[i], ceili(units[i] * loss_rate))
		units[i] -= lost
		losses.append(lost)
	if victory:
		victories += 1
		countries[id].owned = true
		if id != home and not id in conquests:
			conquests.append(id)
			if conquests.size() % NUCLEAR_THRESHOLD == 0:
				nukes += 1
				log_event("Ядерный арсенал: получен 1 удар за %d уникальных захватов." % conquests.size())
				sound_requested.emit("unlock")
		coins += 30
		log_event("Победа! %s под вашим контролем. Трофеи: 30 монет." % atlas[id].name)
		if owned_count() == countries.size():
			finished = true
			log_event("МИР ОБЪЕДИНЁН. Вы завершили мировую кампанию!")
	else:
		defeats += 1
		for i in 3:
			countries[id].units[i] = maxi(0, countries[id].units[i] - ceili(countries[id].units[i] * 0.12))
		log_event("Отступление из %s. Усильте армию перед новой атакой." % atlas[id].name)
	effects.append({"kind": "victory" if victory else "defeat", "target": id})
	sound_requested.emit("campaign_win" if finished else ("victory" if victory else "defeat"))
	return {"victory": victory, "losses": losses, "overseas": overseas}

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
	operations.append({"kind": "attack", "from": origin_for(id), "target": id,
		"start": elapsed, "arrival": elapsed + 4, "overseas": not border(id)})
	log_event("Армия выдвинулась: %s. Прибытие через 4 секунды." % atlas[id].name)
	sound_requested.emit("march_naval" if not border(id) else "march")
	return true

func nuclear_strike(id: int) -> bool:
	if not can_act() or nukes < 1 or id < 0 or id >= countries.size() or countries[id].owned or has_operation("nuke"):
		return false
	nukes -= 1
	operations.append({"kind": "nuke", "from": origin_for(id), "target": id,
		"start": elapsed, "arrival": elapsed + 3})
	log_event("Ядерная ракета запущена: %s. Подлёт — 3 секунды." % atlas[id].name)
	sound_requested.emit("rocket_launch")
	return true

func launch_enemy_attack(attacker: int, target: int) -> bool:
	if not can_act() or owned_count() <= 1 or has_operation("enemy") or attacker < 0 or attacker >= countries.size() or target < 0 or target >= countries.size():
		return false
	var warning = pending_warning()
	if warning.is_empty() or int(warning.attacker) != attacker or elapsed < warning.deadline or elapsed - warning.issued > 300:
		return false
	if countries[attacker].owned or not countries[target].owned:
		return false
	var overseas = not atlas[attacker].neighbors.any(func(neighbor): return int(neighbor) == target)
	if overseas and countries[attacker].units[2] < 4:
		return false
	warning.status = "launched"
	operations.append({"kind": "enemy", "from": attacker, "target": target,
		"start": elapsed, "arrival": elapsed + 5, "overseas": overseas})
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
	var assault = power(countries[attacker].units) * (0.85 if overseas else 1.0)
	var defense = power(units, levels)
	var lost_territory = assault > defense
	var loss_rate = clampf(assault / maxf(defense, 1.0) * 0.2, 0.04, 0.6)
	for i in 3:
		units[i] = maxi(0, units[i] - ceili(units[i] * loss_rate))
		countries[attacker].units[i] = maxi(0, countries[attacker].units[i] - ceili(countries[attacker].units[i] * (0.12 if lost_territory else 0.35)))
	if lost_territory:
		defeats += 1
		countries[target].owned = false
		# Half the surviving attackers stay behind as the new garrison.
		for i in 3:
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
		if not countries[i].owned and border(i): candidates.append(i)
	if candidates.is_empty():
		for i in countries.size():
			if not countries[i].owned and countries[i].units[2] >= 4: candidates.append(i)
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
			"enemy": resolve_enemy_attack(int(op.from), target, op.overseas)
			"nuke":
				if countries[target].owned:
					nukes += 1
					log_event("Ядерный удар отменён: цель уже ваша. Заряд возвращён.")
					sound_requested.emit("all_clear")
				else:
					for i in 3:
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
		log_event("Разведка завершена: %s. Состав войск раскрыт." % atlas[id].name)
		sound_requested.emit("report")
		changed = true
	if network_game: return changed
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
		changed = schedule_warning() or changed
	return changed

func log_event(message: String) -> void:
	notification_serial += 1
	events.push_front({"time": elapsed, "text": message})
	if events.size() > 40:
		events.resize(40)

func export_data() -> Dictionary:
	return {"version": 3, "home": home, "coins": coins, "elapsed": elapsed,
		"units": units, "levels": levels, "countries": countries, "mission": mission,
		"reports": reports, "events": events, "player_color": player_color.to_html(false),
		"campaign_id": campaign_id, "operations": operations, "conquests": conquests,
		"nukes": nukes, "victories": victories, "defeats": defeats, "warnings": warnings,
		"notification_serial": notification_serial, "notifications_seen": notifications_seen,
		"military_balance": military.balance_version}

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
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != 2 and data.get("version") != 3):
		return false
	for key in ["home", "coins", "elapsed"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])):
			return false
	if data.home < 0 or data.home >= countries.size() or data.home != floorf(data.home) or data.coins < 0 or data.coins > 1e12 or data.elapsed < 0 or data.elapsed > 1e9 or data.elapsed != floorf(data.elapsed):
		return false
	if not valid_numbers(data.get("units"), 3) or not valid_numbers(data.get("levels"), 3, 1):
		return false
	if not data.get("countries") is Array or data.countries.size() != countries.size():
		return false
	for c in data.countries:
		if not c is Dictionary or not c.get("owned") is bool or not valid_numbers(c.get("units"), 3):
			return false
		if not c.get("businesses") is Array or c.businesses.size() < 1 or c.businesses.size() > 5 or not valid_numbers(c.businesses, c.businesses.size(), 1):
			return false
	var saved_mission = data.get("mission", {})
	if not saved_mission is Dictionary:
		return false
	if not saved_mission.is_empty():
		if not valid_numbers([saved_mission.get("target"), saved_mission.get("arrival")], 2) or saved_mission.target >= countries.size() or saved_mission.arrival > data.elapsed + 6:
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
		if not valid_numbers(report.get("units"), 3) or not valid_numbers([report.get("time")], 1) or report.time > data.elapsed:
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
		if op.from >= countries.size() or op.target >= countries.size() or op.start > data.elapsed or op.arrival <= op.start or op.arrival > data.elapsed + 6:
			return false
		if op.kind != "nuke" and not op.get("overseas") is bool:
			return false
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
			if op.kind == "enemy" and not saved_warnings.any(func(w): return w.status == "launched" and w.attacker == op.from and w.deadline <= op.start and op.start - w.issued <= 300): return false
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
	warnings = saved_warnings
	notification_serial = int(saved_serial)
	notifications_seen = int(saved_seen)
	if data.get("military_balance", 0) == 0:
		var updated = migrate_legacy_armies()
		if updated > 0: log_event("Военный баланс GFP 2026: обновлено %d нетронутых чужих армий. Старые разведданные могут устареть." % updated)
	effects = []
	paused = false
	finished = owned_count() == countries.size() or owned_count() == 0
	cancel_protected_attacks()
	if announce_restore: log_event("Кампания восстановлена. Добро пожаловать, командующий.")
	return true
