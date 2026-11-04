extends SceneTree

var scene: Control
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		push_error("FAIL: " + text)
		quit(1)

func until(condition: Callable, text: String) -> void:
	var deadline = Time.get_ticks_msec() + 12000
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			push_error("TIMEOUT UI: " + text)
			quit(1)
			return
		await process_frame

func press(text: String) -> void:
	text = scene.L.text(text)
	var controls = scene.overlay.find_children("*", "Button", true, false).filter(func(b): return b.text == text)
	check(controls.size() == 1 and not controls[0].disabled, "Enabled button: " + text)
	controls[0].pressed.emit()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	if OS.get_environment("ATLAS_PHP_TEST") == "1": name = name.replace("vps-", "php-")
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://build/" + name + ".png")

func run() -> void:
	scene = load("res://main.tscn").instantiate()
	scene.settings_path = "user://test_vps_ui_settings.cfg"
	if OS.get_environment("ATLAS_MOBILE_UI") == "1":
		root.min_size = Vector2i.ZERO
		root.size = Vector2i(440, 900)
		scene.force_mobile = true
	var language = OS.get_environment("ATLAS_TEST_LANGUAGE")
	if language in ["ru", "en"]:
		var config = ConfigFile.new()
		config.set_value("interface", "language", language)
		config.save(scene.settings_path)
	root.add_child(scene)
	scene.network.identity_token = "7".repeat(48)
	scene.online.php_mode = OS.get_environment("ATLAS_PHP_TEST") == "1"
	scene.online.server_address = "http://127.0.0.1:30761" if scene.online.php_mode else "ws://127.0.0.1:30760"
	scene.online.room_name = "Комната на PHP-хостинге" if scene.online.php_mode else "Комната на VPS"
	scene.online.show_browser()
	await capture("vps-connect-preview")
	press("Подключиться к серверу")
	check(scene.page == "connecting", "Connection screen")
	await until(func(): return scene.network.stage == "directory" and scene.page == "online", "Server browser")
	check(scene.online.rooms.get_child_count() > 0 and scene.game.home == -1, "Browser does not run a local campaign")
	press("Создать комнату на сервере")
	await until(func(): return scene.page == "lobby", "Remote lobby")
	check(scene.network.is_admin() and not scene.network.hosting, "Remote administrator controls are available")
	for input in scene.overlay.find_children("*", "LineEdit", true, false):
		if input.accessibility_name == scene.L.text("Количество ботов"): input.text = "10"
	press("Добавить ботов")
	await until(func(): return scene.network.players.size() == 11, "Custom bot count refresh beyond the old eight-player limit")
	await capture("vps-lobby-preview")
	if DisplayServer.get_name() != "headless":
		press("Скопировать приглашение")
		check(DisplayServer.clipboard_get().contains(scene.network.room_id), "Invitation includes room code")
	var ready = scene.overlay.find_children("*", "CheckButton", true, false)[0]
	ready.set_pressed(true)
	await until(func(): return scene.network.players[scene.network.my_slot].ready, "Ready state")
	press("Начать матч")
	await until(func(): return scene.page == "game" and scene.game.network_game, "Authoritative view reaches map")
	check(scene.game.units == [35, 8, 4] and scene.game.coins == 180, "Starting view belongs to remote player")
	scene.show_pause()
	check(scene.page == "pause" and scene.network.stage == "game", "Personal menu does not pause server")
	press("Вернуться всем в лобби · пауза")
	await until(func(): return scene.page == "lobby", "Shared lobby pause")
	scene.network.directory_request("leave")
	await until(func(): return scene.page == "online" and scene.network.stage == "directory", "Return to server browser")
	check(scene.game.home == -1 and scene.game.paused, "Remote proxy cleared on leave")
	await capture("vps-rooms-preview")
	press("Удалить комнату")
	var dialog = scene.find_children("*", "ConfirmationDialog", true, false)[0]
	dialog.confirmed.emit()
	await until(func(): return scene.network.directory_rooms.is_empty(), "Delete room from UI")
	scene.network.shutdown("")
	check(scene.page == "menu", "Disconnect returns to main menu")
	if OS.get_environment("ATLAS_PHP_TEST") == "1": await create_timer(0.3).timeout
	scene.online.show_browser()
	press("Подключиться к серверу")
	await until(func(): return scene.page == "online" and scene.network.stage == "directory", "Reconnect server browser")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	scene._input(escape)
	check(scene.page == "menu" and not scene.network.active, "Escape disconnects server and allows offline simulation")
	scene.online.show_lan_browser()
	check(scene.online.rooms.get_child(0).text == scene.L.text("ЛОКАЛЬНЫЕ ЛОББИ"), "LAN browser still works after a VPS connection")
	scene.network.stop_scan()
	scene.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("PASS: VPS UI %d checks" % checks)
	quit()
