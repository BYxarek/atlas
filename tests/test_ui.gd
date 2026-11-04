extends SceneTree

var failures = 0
var checks = 0
const DIRECTORY = "user://test_ui_saves"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func escape() -> void:
	var key = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	scene.settings_path = "user://test_ui_settings.cfg"
	if FileAccess.file_exists(scene.settings_path): DirAccess.remove_absolute(scene.settings_path)
	scene.store = scene.SaveStore.new(DIRECTORY)
	clear_store()
	root.add_child(scene)
	await process_frame
	await process_frame
	check(scene.page == "menu" and scene.overlay.visible and not scene.hud.visible, "Boot opens main menu")
	check(scene.game.paused and not scene.card.visible, "Main menu blocks simulation and panels")
	check(scene.matching_countries("").size() == scene.game.atlas.size(), "Empty fuzzy query keeps all countries")
	check(scene.matching_countries("Jpan")[0].english == "Japan", "Godot 4.8 fuzzy search tolerates a missing letter")
	check(scene.matching_countries("  Япония  ")[0].english == "Japan", "Fuzzy search supports Russian and trims spaces")
	check(scene.matching_countries("zzzzzzzzzzzzzzzz").is_empty(), "Unmatched query has no countries")
	var native_button = scene.button("test", func(): pass)
	scene.add_child(native_button)
	check(native_button.get_theme_sound("pressed_sound") == scene.sound.streams.click, "Native button audio inherits the shared theme")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Interface")) == "Effects", "Native UI audio uses the effects volume")
	var clicks = [0]
	native_button.pressed.connect(func(): clicks[0] += 1)
	native_button.press()
	check(clicks[0] == 1, "Godot 4.8 native press invokes the action once")
	if DisplayServer.get_name() != "headless":
		await process_frame
		var touch = InputEventScreenTouch.new()
		touch.position = native_button.get_global_rect().get_center()
		touch.pressed = true
		Input.parse_input_event(touch)
		await process_frame
		touch = touch.duplicate()
		touch.pressed = false
		Input.parse_input_event(touch)
		await process_frame
		check(clicks[0] == 2, "Touch press activates the native button exactly once")
		var ui_bus = AudioServer.get_bus_index("Interface")
		var capture_audio = AudioEffectCapture.new()
		AudioServer.add_bus_effect(ui_bus, capture_audio)
		native_button.press()
		await create_timer(0.15).timeout
		var samples = capture_audio.get_buffer(capture_audio.get_frames_available())
		var audible = false
		for sample in samples:
			if sample.length_squared() > 0.000000001: audible = true
		check(audible, "Native theme button produces audio on the interface bus")
		AudioServer.remove_bus_effect(ui_bus, AudioServer.get_bus_effect_count(ui_bus) - 1)
	native_button.queue_free()
	scene.show_settings("menu")
	check(scene.page == "settings" and scene.game.paused, "Settings are available from the main menu")
	scene.master_slider.value = 65
	scene.effects_slider.value = 40
	check(is_equal_approx(scene.sound.master_volume, 0.65) and is_equal_approx(scene.sound.effects_volume, 0.4), "Volume sliders immediately update mix")
	await capture("settings-preview")
	scene.fullscreen_toggle.set_pressed(true)
	await process_frame
	await process_frame
	var config = ConfigFile.new()
	check(config.load(scene.settings_path) == OK and config.get_value("display", "borderless_fullscreen") == true, "Fullscreen choice persists")
	check(is_equal_approx(config.get_value("audio", "master"), 0.65) and is_equal_approx(config.get_value("audio", "effects"), 0.4), "Changing fullscreen preserves volume preferences")
	if DisplayServer.get_name() != "headless":
		check(root.mode == Window.MODE_FULLSCREEN, "Toggle enables native borderless fullscreen")
		check(root.size == DisplayServer.screen_get_size(root.current_screen), "Fullscreen covers the monitor")
		await capture("fullscreen-preview")
	scene.apply_fullscreen(false)
	scene.restore_display_settings()
	check(is_equal_approx(scene.sound.master_volume, 0.65) and is_equal_approx(scene.sound.effects_volume, 0.4), "Volume preferences restore together with fullscreen")
	await process_frame
	if DisplayServer.get_name() != "headless": check(root.mode == Window.MODE_FULLSCREEN, "Saved fullscreen restores")
	scene.fullscreen_toggle.set_pressed(false)
	await process_frame
	check(config.load(scene.settings_path) == OK and config.get_value("display", "borderless_fullscreen") == false, "Windowed choice persists")
	if DisplayServer.get_name() != "headless": check(root.mode == Window.MODE_WINDOWED, "Toggle restores decorated window")
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_MAXIMIZED
		await process_frame
		await process_frame
		check(absf(root.get_visible_rect().size.aspect() - Vector2(root.size).aspect()) < 0.005, "Maximized window has no letterboxing")
		scene.set_fullscreen(true)
		await process_frame
		await process_frame
		scene.set_fullscreen(false)
		await process_frame
		await process_frame
		check(root.mode == Window.MODE_MAXIMIZED, "Exiting fullscreen restores previous maximized mode")
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1440, 900)
	escape()
	await process_frame
	check(scene.page == "menu", "Esc returns from settings to main menu")
	scene.show_new_game()
	check(scene.new_country_ids.size() == 176, "New game offers all countries")
	await capture("new-game-preview")
	scene.fill_new_countries("Japan")
	check(scene.new_country_ids.size() == 1, "New game country search works")
	scene.color_picker.color = Color("b697ef")
	scene.color_picker.color_changed.emit(scene.color_picker.color)
	scene.begin_campaign()
	check(scene.game.home == scene.find_country("Japan"), "New game starts as chosen country")
	check(scene.game.player_color == Color("b697ef"), "Chosen territory color reaches simulation")
	check(scene.game.units == scene.Simulation.START_UNITS and scene.game.coins == 180, "New campaign uses equal minimal starting resources")
	scene.announce("Проверка нового уведомления")
	check(scene.toast_panel.visible and scene.toast_panel.modulate.a == 0 and scene.toast_panel.position.y == 6, "Notification starts transparent and above its resting position")
	check(scene.sound.players[(scene.sound.next_player - 1 + 12) % 12].stream == scene.sound.streams.notification, "Notification appearance has a dedicated sound")
	scene.toast_tween.custom_step(0.1)
	check(scene.toast_panel.modulate.a > 0 and scene.toast_panel.modulate.a < 1 and scene.toast_panel.position.y > 6, "Notification animates in gradually")
	scene.toast_tween.custom_step(0.2)
	check(is_equal_approx(scene.toast_panel.modulate.a, 1) and is_equal_approx(scene.toast_panel.position.y, 22), "Notification settles fully visible on its background")
	scene.toast_tween.custom_step(7.5)
	check(scene.toast_panel.visible and scene.toast_panel.modulate.a > 0 and scene.toast_panel.modulate.a < 1, "Notification fades out gradually")
	scene.toast_tween.custom_step(1)
	check(not scene.toast_panel.visible, "Completed notification disappears")
	scene.announce("Старое сообщение")
	scene.announce("Новое сообщение")
	scene.toast_tween.custom_step(0.3)
	check(scene.toast.text == "Новое сообщение" and scene.toast_panel.visible, "Replacing a notification cancels the previous animation")
	await capture("toast-preview")
	check(scene.toast_panel.size.y < 120, "Notification background stays compact after long and short messages")
	check(scene.page == "game" and scene.hud.visible and not scene.overlay.visible and not scene.card.visible, "Gameplay opens an unobstructed full-window map")
	check(scene.store.list_saves().size() == 1, "Starting a campaign immediately autosaves")
	var id = scene.find_country("Brazil")
	var point = scene.world.screen_point(id)
	check(scene.world.pick(point) == id, "Map hit testing selects country")
	scene.world.set_zoom(2, point)
	check(scene.world.pick(point) == id, "Zoom preserves country under cursor")
	scene.world.reset_view()
	scene.open_card("army")
	scene.game.coins = 0
	scene.refresh_hud()
	check(scene.actionable.size() == 6 and scene.actionable.all(func(item): return item.button.disabled), "Army has six actions and blocks unaffordable spending")
	scene.game.coins = 2000
	scene.refresh_hud()
	check(scene.actionable.all(func(item): return not item.button.disabled), "Income enables actions without rebuilding controls")
	for i in 3:
		var before = scene.game.units[i]
		scene.actionable[i * 2].button.pressed.emit()
		check(scene.game.units[i] > before, "Recruitment controls target correct branch")
	scene.select_country(scene.game.home)
	scene.open_card("economy")
	var before = scene.game.income()
	scene.actionable[0].button.pressed.emit()
	check(scene.game.income() == before + 1, "Business upgrade preserves +1 per second rule")
	var foreign = scene.find_country("Finland")
	scene.select_country(foreign)
	scene.send_spy()
	for i in 2: scene.on_second()
	scene.world._process(0.25)
	escape()
	await process_frame
	check(scene.page == "pause" and scene.game.paused, "Esc opens pause menu and stops game")
	scene.show_settings("pause")
	check(scene.game.paused and scene.page == "settings", "Settings preserve paused campaign")
	escape()
	await process_frame
	check(scene.page == "pause" and scene.game.paused, "Esc returns from settings to pause")
	var visual_time = scene.world.visual_time
	var elapsed = scene.game.elapsed
	var coins = scene.game.coins
	scene.on_second()
	scene.world._process(1)
	check(scene.game.elapsed == elapsed and scene.game.coins == coins and scene.world.visual_time == visual_time, "Pause freezes economy, mission and animation")
	check(scene.menu_body.get_child_count() >= 15, "Pause menu contains statistics and save controls")
	await capture("pause-preview")
	scene.manual_save()
	for child in scene.get_children():
		if child is AcceptDialog: child.confirmed.emit()
	await process_frame
	scene.show_saves("pause")
	check(scene.saves_list.size() == 2, "Save browser lists auto and manual snapshots")
	await capture("saves-preview")
	scene.load_campaign(scene.saves_list[0].path)
	check(scene.page == "game" and not scene.game.paused and not scene.game.mission.is_empty(), "Loading resumes campaign and in-flight spy")
	for i in 4: scene.on_second()
	check(scene.game.reports.has(str(foreign)), "Spy completes after remaining active seconds")
	scene.select_country(foreign)
	scene.game.countries[foreign].units = [1, 0, 0]
	scene.confirm_attack()
	await process_frame
	var dialogs = scene.get_children().filter(func(n): return n is ConfirmationDialog)
	check(dialogs.size() == 1, "Attack requires confirmation")
	if not dialogs.is_empty(): dialogs[0].confirmed.emit()
	check(scene.game.has_operation("attack") and not scene.game.countries[foreign].owned, "Confirm dispatches an animated march")
	scene.world.visual_time = scene.game.elapsed + 1.8
	await capture("operations-preview")
	for i in 4: scene.on_second()
	check(scene.game.countries[foreign].owned, "Battle result applies after arrival")
	check(scene.notifications_button.text.contains(scene.L.text("Уведомления")), "Toolbar includes notifications")
	scene.notifications_button.pressed.emit()
	check(scene.card_view == "notifications" and scene.game.notifications_seen == scene.game.notification_serial, "Opening notifications marks existing messages read")
	scene.game.rng.seed = 7
	check(scene.game.schedule_warning(), "Expanded empire receives a possible-attack warning")
	var warning = scene.game.pending_warning()
	scene.refresh_hud()
	check(scene.threat_panel.visible and scene.threat_timer.text.contains(scene.time_text(int(warning.deadline) - scene.game.elapsed)), "Corner timer displays remaining warning time")
	check(scene.notifications_button.text.contains("1"), "New warning increments unread counter")
	check(scene.threat_identity.text.begins_with(scene.L.text("Неизвестная страна")), "Corner timer masks unexplored attacker")
	scene.open_card("notifications")
	check(scene.card.offset_top >= scene.threat_panel.get_rect().end.y, "Notification panel does not overlap threat timer")
	await capture("notifications-preview")
	var attacker = int(warning.attacker)
	scene.game.reports[str(attacker)] = {"units": scene.game.countries[attacker].units.duplicate(), "time": scene.game.elapsed}
	scene.refresh_hud()
	scene.refresh_card()
	check(scene.threat_identity.text.begins_with(scene.L.country(scene.game.atlas[attacker])), "Reconnaissance reveals attacker in current corner timer")
	escape()
	await process_frame
	var remaining = int(warning.deadline) - scene.game.elapsed
	scene.on_second()
	check(int(warning.deadline) - scene.game.elapsed == remaining, "Pause freezes possible-attack countdown")
	scene.enter_game()
	scene.open_card("countries")
	scene.search.text = "Япония"
	scene.refresh_country_list(scene.search.text)
	check(scene.country_list.item_count == 1, "Country panel supports Russian search")
	scene.open_card("arsenal")
	check(scene.card.visible and scene.card_body.get_child_count() > 4, "Arsenal panel explains nuclear progress")
	escape()
	await process_frame
	scene.show_journal()
	check(scene.page == "journal" and scene.game.paused, "Journal keeps game paused")
	scene.show_main_menu()
	check(scene.page == "menu" and scene.game.paused, "Returning to main menu pauses campaign")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/menu-preview.png")
	scene.enter_game()
	scene.card.hide()
	scene.game.reports[str(scene.find_country("China"))] = {"units": [10, 10, 10], "time": scene.game.elapsed}
	scene.game.reports[str(scene.find_country("Russia"))] = {"units": [10, 10, 10], "time": scene.game.elapsed}
	scene.world.queue_redraw()
	for dimensions in [Vector2i(1120, 720), Vector2i(1440, 900), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1120, 1000)]:
		root.size = dimensions
		await process_frame
		await process_frame
		check(scene.world.position == Vector2.ZERO and scene.world.size == root.get_visible_rect().size, "Map occupies complete window at every tested size")
		check(absf(root.get_visible_rect().size.aspect() - Vector2(root.size).aspect()) < 0.005, "Visible viewport matches window aspect without black bars")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440, 900)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/preview.png")
	clear_store()
	DirAccess.remove_absolute(scene.settings_path)
	scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("%s: %d UI checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func clear_store() -> void:
	var dir = DirAccess.open(DIRECTORY)
	if dir:
		for file in dir.get_files(): DirAccess.remove_absolute(DIRECTORY.path_join(file))
		DirAccess.remove_absolute(DIRECTORY)

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + filename + ".png")
