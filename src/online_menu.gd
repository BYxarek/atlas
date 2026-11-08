extends RefCounted

const L = preload("res://src/i18n.gd")

var ui: Control
var net: Node
var nickname = L.text("Игрок")
var room_name = L.text("Моя партия")
var address = "127.0.0.1"
var port = 24760
var rooms: VBoxContainer
var server_address = ""
var code = ""
var server_status: Label
var php_mode = false
const Mods = preload("res://src/mods.gd")
var mod_progress: Label
var lobby_telemetry: Label
var lobby_ping_rows: Dictionary = {}

func setup_mods() -> void:
	net.mods.required.connect(show_required_mods)
	net.mods.progress.connect(func(done, total):
		if is_instance_valid(mod_progress): mod_progress.text = "%d / %d KB" % [done / 1024, total / 1024])
	net.mods.failed.connect(func(problem):
		ui.message(L.text("Моды"), problem)
		show_required_mods(net.mods.offered))
	net.mods.downloaded.connect(func():
		ui.page = "mods_download"
		ui.menu_frame(L.text("Моды установлены"), L.text("Перезапустите игру, чтобы применить моды и вернуться в комнату."), 650, 350)
		ui.menu_body.add_child(ui.button(L.text("Перезапустить и подключиться"), restart_for_mods)))
	if FileAccess.file_exists(Mods.NETWORK_BOOT) and Engine.get_meta("atlas_network_mode", false):
		var boot = JSON.parse_string(FileAccess.get_file_as_string(Mods.NETWORK_BOOT))
		if boot is Dictionary and boot.get("target", {}) is Dictionary and not boot.get("target", {}).is_empty():
			var target = boot.target
			Mods.write_network_boot(Engine.get_meta("atlas_network_profile", []))
			resume_connection.call_deferred(target)

func show_required_mods(profile: Array) -> void:
	ui.page = "mods_download"
	ui.game.paused = true
	ui.menu_frame(L.text("Нужны моды комнаты"), L.text("Установить точные версии модов и подключиться после перезапуска?"), 700, 650)
	ui.menu_scroll()
	for item in profile:
		ui.menu_body.add_child(ui.paragraph("%s · %s · %d KB" % [item.name, item.version, int(item.size) / 1024]))
	if profile.is_empty(): ui.menu_body.add_child(ui.paragraph(L.text("Эта комната работает без модов. Текущие сетевые моды будут отключены.")))
	ui.menu_body.add_child(ui.paragraph(L.text("Сетевые пакеты устанавливаются отдельно от одиночных модов. Игра проверит размер, версии и SHA-256 перед применением.")))
	ui.menu_body.add_child(ui.button(L.text("Установить все нужные моды"), func():
		if not ui.autosave(): return
		ui.clear_box(ui.menu_body)
		mod_progress = ui.paragraph(L.text("Загрузка модов…"))
		ui.menu_body.add_child(mod_progress)
		ui.menu_body.add_child(ui.button(L.text("Отмена"), func(): net.shutdown("")))
		net.mods.begin(), true))
	ui.menu_body.add_child(ui.button(L.text("Отмена"), func(): net.shutdown("")))

func restart_for_mods() -> void:
	if not ui.autosave(): return
	if OS.has_feature("android") or Engine.is_embedded_in_editor():
		ui.message(L.text("Моды"), L.text("Закройте и снова откройте игру. Нужный профиль и подключение уже сохранены."))
		return
	var args = PackedStringArray()
	if OS.has_feature("editor"): args = PackedStringArray(["--path", ProjectSettings.globalize_path("res://")])
	OS.set_restart_on_exit(true, args)
	ui.get_tree().quit()

func resume_connection(target: Dictionary) -> void:
	if not target.get("kind") in ["lan", "vps", "php"] or not target.get("address") is String or not target.get("name") is String: return
	nickname = target.name
	var error: Error
	if target.kind == "lan":
		error = net.join_room(target.address, nickname, int(target.get("port", 24760)))
	else:
		net.mods.resume = {"action": target.get("action", "list"), "args": target.get("args", [])}
		error = net.join_php(target.address, nickname, str(target.get("nonce", ""))) if target.kind == "php" else net.join_directory(target.address, nickname)
	if error != OK: ui.message(L.text("Подключение"), error_string(error))
	else: show_connecting()

func show_browser() -> void:
	ui.page = "online"
	ui.game.paused = true
	ui.menu_frame(L.text("Серверы ATLAS"), L.text("Свои комнаты на VPS или обычном PHP-хостинге."), 800, 790)
	if net.active and net.directory_client:
		ui.menu_body.add_child(ui.paragraph(net.server_url, ui.MINT))
		field(L.text("Название комнаты"), room_name, func(value): room_name = value, 40)
		ui.menu_body.add_child(ui.button(L.text("Создать комнату на сервере"), func(): net.directory_request("create", [room_name]), true))
		field(L.text("Код комнаты"), code, func(value): code = value, 16)
		ui.menu_body.add_child(ui.button(L.text("Подключиться по коду"), func(): net.directory_request("join", [code.strip_edges()])))
	else:
		var config = ConfigFile.new()
		if config.load(ui.settings_path) == OK and server_address.is_empty():
			server_address = str(config.get_value("network", "server", "")).substr(0, 255)
			nickname = str(config.get_value("network", "name", nickname)).substr(0, 24)
			php_mode = config.get_value("network", "php", false) == true
		field(L.text("Ваше имя"), nickname, func(value): nickname = value, 24)
		var mode = OptionButton.new()
		mode.add_item("VPS · WebSocket (wss://)")
		mode.add_item(L.text("PHP-хостинг · HTTPS (https://)"))
		mode.select(1 if php_mode else 0)
		mode.item_selected.connect(func(index): php_mode = index == 1)
		ui.menu_body.add_child(mode)
		field(L.text("Адрес сервера"), server_address, func(value): server_address = value, 255)
		ui.menu_body.add_child(ui.button(L.text("Подключиться к серверу"), connect_server, true))
		ui.menu_body.add_child(ui.paragraph(L.text("VPS: wss://atlas.example.com. PHP: https://example.com/atlas. На PHP-хостинге обновления приходят примерно раз в секунду. Открывать порты на компьютере игрока не нужно."), ui.MUTED, 13))
	server_status = ui.paragraph("", ui.GOLD, 12)
	ui.menu_body.add_child(server_status)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 230
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.menu_body.add_child(scroll)
	rooms = VBoxContainer.new()
	rooms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms.add_theme_constant_override("separation", 8)
	scroll.add_child(rooms)
	refresh_rooms()
	ui.menu_body.add_child(ui.button(L.text("Отключиться от сервера") if net.active else L.text("Назад"), func():
		if net.active: net.shutdown("")
		else: ui.show_main_menu()))
	if not net.active: ui.menu_body.add_child(ui.button(L.text("Локальная сеть · прежний режим"), show_lan_browser))

func connect_server() -> void:
	var error = net.join_php(server_address.strip_edges(), nickname) if php_mode else net.join_directory(server_address.strip_edges(), nickname)
	if error != OK:
		ui.message(L.text("Подключение"), L.text("Проверьте адрес и выбранный тип сервера. ") + error_string(error))
		return
	var config = ConfigFile.new()
	config.load(ui.settings_path)
	config.set_value("network", "server", server_address.strip_edges())
	config.set_value("network", "name", nickname)
	config.set_value("network", "php", php_mode)
	config.save(ui.settings_path)
	show_connecting()

func show_lan_browser() -> void:
	server_status = null
	ui.page = "online"
	ui.game.paused = true
	ui.menu_frame(L.text("Сетевая игра"), L.text("PvP и боты · до 8 участников · LAN или прямой адрес"), 740, 790)
	field(L.text("Ваше имя"), nickname, func(value): nickname = value, 24)
	field(L.text("Название нового лобби"), room_name, func(value): room_name = value, 40)
	var row = HBoxContainer.new()
	ui.menu_body.add_child(row)
	var ip = LineEdit.new()
	ip.text = address
	ip.placeholder_text = L.text("IP или имя хоста")
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip.max_length = 255
	ip.text_changed.connect(func(value): address = value)
	row.add_child(ip)
	var number = SpinBox.new()
	number.min_value = 1024
	number.max_value = 65535
	number.value = port
	number.value_changed.connect(func(value): port = int(value))
	row.add_child(number)
	row = VBoxContainer.new() if ui.mobile else HBoxContainer.new()
	ui.menu_body.add_child(row)
	row.add_child(ui.button(L.text("Создать лобби"), func(): open_host(""), true))
	row.add_child(ui.button(L.text("Подключиться"), func():
		var error = net.join_room(address, nickname, port)
		if error != OK: ui.message(L.text("Подключение"), error_string(error))
		else: show_connecting()))
	row.add_child(ui.button(L.text("Обновить LAN"), func(): net.scan_lan()))
	ui.menu_body.add_child(ui.paragraph(L.text("Поиск в локальной сети выполняется автоматически. Для интернета нужен доступный UDP-порт хоста (по умолчанию 24760); при подключении через роутер — проброс порта."), ui.MUTED, 12))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 260
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.menu_body.add_child(scroll)
	rooms = VBoxContainer.new()
	rooms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rooms)
	refresh_rooms()
	ui.menu_body.add_child(ui.button(L.text("Назад"), func(): net.stop_scan(); ui.show_main_menu()))
	net.scan_lan()

func field(caption: String, value: String, changed: Callable, limit: int) -> void:
	var row = VBoxContainer.new() if ui.mobile else HBoxContainer.new()
	ui.menu_body.add_child(row)
	row.add_child(ui.label(caption))
	var input = LineEdit.new()
	input.text = value
	input.max_length = limit
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_changed.connect(changed)
	row.add_child(input)

func refresh_rooms() -> void:
	if ui.page != "online" or not is_instance_valid(rooms): return
	if net.directory_client or is_instance_valid(server_status):
		refresh_server_rooms()
		return
	refresh_lan_rooms()

func refresh_server_rooms() -> void:
	ui.clear_box(rooms)
	if is_instance_valid(server_status): server_status.text = L.render(net.directory_status) if net.active else L.text("Сервер не подключён")
	if not net.active:
		rooms.add_child(ui.paragraph(L.text("Адреса серверов можно распространять вместе с приглашением. Общая регистрация не требуется.")))
		return
	if net.directory_rooms.is_empty(): rooms.add_child(ui.paragraph(L.text("Комнат пока нет. Создайте первую партию.")))
	for entry in net.directory_rooms:
		var box = ui.box_panel(rooms)
		box.add_child(ui.paragraph(entry.name + (L.text(" · ваша партия") if entry.member else ""), ui.MINT if entry.member else ui.INK, 16))
		box.add_child(ui.paragraph(L.text("%d/%d · %s · %s · код %s") % [entry.players, net.MAX_PLAYERS, L.text("идёт матч") if entry.stage == "game" else L.text("лобби"), ui.time_text(entry.elapsed), entry.id], ui.MUTED, 11))
		var row = HBoxContainer.new()
		box.add_child(row)
		var join = ui.button(L.text("Вернуться") if entry.member else L.text("Войти"), func(): net.directory_request("join", [entry.id]), true)
		join.disabled = entry.players >= net.MAX_PLAYERS and not entry.member
		row.add_child(join)
		if entry.admin:
			row.add_child(ui.button(L.text("Удалить комнату"), func(): ui.confirm_action(L.text("Удалить комнату?"), L.text("Сервер удалит партию и её сохранение. Все игроки должны предварительно выйти."), func(): net.directory_request("delete", [entry.id]))))

func refresh_lan_rooms() -> void:
	ui.clear_box(rooms)
	rooms.add_child(ui.label(L.text("ЛОКАЛЬНЫЕ ЛОББИ"), 12, ui.MINT))
	if net.found.is_empty(): rooms.add_child(ui.paragraph(L.text("Пока не найдены. Хост и игроки должны находиться в одной сети.")))
	for entry in net.found:
		rooms.add_child(ui.button("%s · %d/%d · %s:%d · %s" % [entry.name, entry.players, net.MAX_PLAYERS, entry.address, entry.port, L.text("в игре") if entry.stage == "game" else L.text("лобби")], func():
			var error = net.join_room(entry.address, nickname, int(entry.port))
			if error != OK: ui.message(L.text("Подключение"), error_string(error))
			else: show_connecting()))
	rooms.add_child(ui.label(L.text("ПРОДОЛЖИТЬ СЕТЕВУЮ ПАРТИЮ (ХОСТ)"), 12, ui.GOLD))
	for entry in net.saved_matches():
		rooms.add_child(ui.button(entry.name + " · " + ui.time_text(entry.elapsed), func(): open_host(entry.path)))

func open_host(path: String) -> void:
	var error = net.host_room(room_name, nickname, port, path)
	if error != OK: ui.message(L.text("Создание лобби"), L.text("Не удалось открыть порт или сохранение: ") + error_string(error))
	else: net.stop_scan()

func show_connecting() -> void:
	net.stop_scan()
	ui.page = "connecting"
	ui.menu_frame(L.text("Подключение…"), L.text("Ожидаем ответ хоста."), 540, 300)
	ui.menu_body.add_child(ui.button(L.text("Отмена"), func(): net.shutdown("")))

func show_lobby() -> void:
	ui.page = "lobby"
	ui.game.paused = true
	ui.sound.sync()
	ui.menu_frame(net.lobby_name, L.text("Лобби · %d/%d%s") % [net.players.size(), net.MAX_PLAYERS, L.text(" · вы администратор") if net.is_admin() else ""], 820, 800)
	if net.directory_client:
		ui.menu_body.add_child(ui.button(L.text("Скопировать приглашение"), func(): DisplayServer.clipboard_set(net.server_url + " · " + net.room_id)))
	ui.menu_body.add_child(ui.paragraph(L.render(net.status), ui.GOLD, 12))
	lobby_ping_rows.clear()
	if net.directory_client:
		lobby_telemetry = ui.paragraph("", ui.INK, 12)
		lobby_telemetry.name = "LobbyTelemetry"
		ui.menu_body.add_child(lobby_telemetry)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 240
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.menu_body.add_child(scroll)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for slot in net.players:
		var p = net.players[slot]
		var row = HBoxContainer.new()
		rows.add_child(row)
		var text = "%s%s · %s · %s" % [L.render(p.name) if p.bot else p.name, L.text(" (вы)") if slot == net.my_slot else "", L.country(ui.game.atlas[int(p.home)]), L.text("бот ✓") if p.bot else (L.text("отключён") if not p.connected else (L.text("готов ✓") if p.ready else L.text("не готов")))]
		var description = ui.paragraph(text, Color(p.color), 14)
		row.add_child(description)
		if net.directory_client and not p.bot and p.connected:
			lobby_ping_rows[slot] = {"label": description, "base": text}
		if net.is_admin() and slot != net.host_slot:
			row.add_child(ui.button(L.text("Удалить"), func(): ui.confirm_action(L.text("Удалить участника?"), L.text("Его территории станут нейтральными. Место освободится для нового игрока."), func(): net.request("kick", [slot]))))
	var me = net.players[net.my_slot]
	var picker = OptionButton.new()
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var ids = []
	var sorted = ui.game.atlas.duplicate()
	sorted.sort_custom(func(a, b): return L.country(a).naturalnocasecmp_to(L.country(b)) < 0)
	for c in sorted:
		if not net.country_available(net.my_slot, int(c.id)) and int(c.id) != int(me.home): continue
		ids.append(int(c.id))
		picker.add_item(L.country(c))
		if int(c.id) == int(me.home): picker.select(ids.size() - 1)
	picker.disabled = net.locked(net.my_slot)
	picker.item_selected.connect(func(index): net.request("choose", [ids[index]]))
	ui.menu_body.add_child(picker)
	var palette = HFlowContainer.new() if ui.mobile else HBoxContainer.new()
	ui.menu_body.add_child(palette)
	for code in net.COLORS:
		var swatch = ui.button("✓" if me.color == code else "", func(): net.request("color", [code]))
		swatch.custom_minimum_size.x = 52
		swatch.add_theme_stylebox_override("normal", ui.style(Color(code).darkened(0.35)))
		swatch.disabled = net.players.keys().any(func(id): return id != net.my_slot and net.players[id].color == code)
		palette.add_child(swatch)
	ui.menu_body.add_child(ui.paragraph(L.text("Все игроки и боты начинают с одинаковой минимальной армией и 180 монетами. При продолжении сохраняется прежний прогресс. В PvP последняя страна тоже может быть захвачена."), ui.MUTED, 12))
	var ready = CheckButton.new()
	ready.text = L.text("Я готов")
	ready.button_pressed = me.ready
	ready.toggled.connect(func(value): net.request("ready", [value]))
	ui.menu_body.add_child(ready)
	if net.is_admin():
		var row = VBoxContainer.new() if ui.mobile else HBoxContainer.new()
		ui.menu_body.add_child(row)
		var count = LineEdit.new()
		count.text = "1"
		count.placeholder_text = "1–%d" % (net.MAX_PLAYERS - net.players.size())
		count.accessibility_name = L.text("Количество ботов")
		count.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		count.custom_minimum_size.x = 100
		row.add_child(count)
		var bot = ui.button(L.text("Добавить ботов"), func():
			if not count.text.is_valid_int() or int(count.text) < 1 or int(count.text) + net.players.size() > net.MAX_PLAYERS:
				ui.message(L.text("Количество ботов"), L.text("Игроков и ботов не может быть больше, чем стран: %d.") % net.MAX_PLAYERS)
				return
			net.request("bot", [int(count.text)]))
		bot.disabled = net.players.size() >= net.MAX_PLAYERS
		row.add_child(bot)
		var start = ui.button(L.text("Продолжить матч") if net.world != null or net.resuming else L.text("Начать матч"), func(): net.request("start"), true)
		start.disabled = not net.start_error().is_empty()
		row.add_child(start)
		ui.menu_body.add_child(ui.paragraph(L.render(net.start_error()), ui.GOLD, 12))
	ui.menu_body.add_child(ui.button(L.text("Покинуть лобби"), ui.leave_network))
	ui.update_performance_overlay()

func update_telemetry(frame_rate: int) -> void:
	if not is_instance_valid(lobby_telemetry): return
	var failures = net.quality.failure_percent()
	var percent = "%d%%" % failures if failures >= 0 else "—"
	var failure_text = L.text("Сбои запросов %s" if net.php != null else "Тайм-ауты проб %s") % percent
	var text = "%s · %s · %s" % [ping_text(net.my_slot), L.text("Потери пакетов —"), failure_text]
	lobby_telemetry.text = "FPS %d · %s" % [frame_rate, text] if frame_rate >= 0 else text
	for slot in lobby_ping_rows:
		var entry = lobby_ping_rows[slot]
		entry.label.text = entry.base + " · " + ping_text(slot)

func ping_text(slot: String) -> String:
	var ping = net.player_ping_ms(slot)
	return L.text("Пинг %s") % (L.text("%d мс") % ping if ping >= 0 else "—")
