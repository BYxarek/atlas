extends SceneTree

const L = preload("res://src/i18n.gd")
var failures = 0
var checks = 0
var scene: Control

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("res://build/" + name + ".png")

func run() -> void:
	L.set_language("en")
	check(L.text("Пехота") == "Infantry" and L.text("Настройки") == "Settings", "English catalog")
	check(L.render("Победа! Япония под вашим контролем. Трофеи: 30 монет.") == "Victory! You now control Japan. Spoils: 30 coins.", "Old and server event translation includes country name")
	check(L.render("Неизвестная страна · сила примерно 10–20") == "Unknown country · estimated strength 10–20", "Formatted reconnaissance")
	var percent = RegEx.new()
	percent.compile("%(?:0?[0-9]+)?[dsf]|%%")
	for key in L.catalog:
		check(percent.search_all(key).size() == percent.search_all(L.catalog[key]).size(), "Translation preserves format placeholders: " + key)
	var config = ConfigFile.new()
	config.set_value("interface", "language", "en")
	config.save("user://test_mobile_settings.cfg")
	root.min_size = Vector2i.ZERO
	root.size = Vector2i(440, 900)
	scene = load("res://main.tscn").instantiate()
	scene.force_mobile = true
	scene.settings_path = "user://test_mobile_settings.cfg"
	scene.store = scene.SaveStore.new("user://test_mobile_saves")
	root.add_child(scene)
	await capture("mobile-menu-en")
	check(scene.mobile and scene.size.x <= 450, "Phone layout uses a touch-sized logical viewport")
	check(scene.menu_shell.position.x >= 0 and scene.menu_shell.get_rect().end.x <= scene.size.x + 1, "Menu fits phone width")
	scene.show_new_game()
	check(scene.menu_shell.modulate.a < 1.0, "Mobile page starts fading in")
	var replaced_shell = scene.menu_shell
	scene.show_settings()
	await create_timer(0.25).timeout
	check(not is_instance_valid(replaced_shell), "Rapid navigation frees the previous animated page")
	check(is_equal_approx(scene.menu_shell.modulate.a, 1.0) and scene.menu_shell.scale == Vector2.ONE, "Page transition restores opacity and scale")
	scene.show_settings()
	check(is_equal_approx(scene.menu_shell.modulate.a, 1.0), "Refreshing the same page does not replay its transition")
	scene.show_new_game()
	scene.fill_new_countries("Japan")
	check(scene.country_picker.get_item_text(0) == "Japan", "Country names are localized")
	await capture("mobile-new-en")
	scene.begin_campaign()
	check(scene.game.units == [35, 8, 4], "Mobile preserves campaign simulation")
	check(scene.game.events[0].text.contains("Поднят ваш флаг"), "Saved events remain canonical across language switches")
	check(L.render(scene.game.events[0].text).contains("Japan"), "Campaign event displays in English")
	check(scene.toolbar.get_child_count() == 4, "All core actions remain accessible on mobile")
	scene.select_country(scene.game.home)
	await capture("mobile-country-en")
	check(scene.balance.get_line_count() == 1 and scene.income_label.get_line_count() == 1, "Godot 4.8 keeps treasury values on one line")
	check(scene.treasury.get_rect().end.x < scene.pause_button.position.x, "Treasury leaves room for the pause button")
	if "--layout-debug" in OS.get_cmdline_user_args(): print("CARD ", scene.card.get_rect(), " TOAST ", scene.toast_panel.get_rect(), " LABEL ", scene.toast.get_rect())
	check(scene.card.offset_left >= 0 and scene.card.offset_right < 0 and scene.card.get_rect().end.y < scene.size.y, "Country sheet stays within phone viewport")
	for b in scene.card_body.find_children("*", "Button", true, false): check(b.custom_minimum_size.y >= 56, "Touch action height")
	scene.mobile_back()
	check(not scene.card.visible and scene.page == "game", "Android Back closes detail sheet first")
	scene.mobile_back()
	check(scene.page == "pause" and scene.game.paused, "Android Back pauses offline game")
	scene.show_settings("pause")
	await capture("mobile-settings-en")
	scene.change_language("ru")
	check(L.language == "ru" and config.load(scene.settings_path) == OK and config.get_value("interface", "language") == "ru", "Language persists on both platforms")
	check(L.render(scene.game.events[0].text).contains("Япония"), "Switching to Russian restores original country and event text")
	await capture("mobile-settings-ru")
	scene.enter_game()
	scene.world.set_zoom(3)
	var start_pan = scene.world.pan
	var touch = InputEventScreenTouch.new()
	touch.index = 0; touch.pressed = true; touch.position = Vector2(100, 200)
	scene.world._gui_input(touch)
	var drag = InputEventScreenDrag.new()
	drag.index = 0; drag.position = Vector2(145, 230)
	scene.world._gui_input(drag)
	check(scene.world.pan != start_pan, "Touch drag moves map")
	var second = InputEventScreenTouch.new()
	second.index = 1; second.pressed = true; second.position = Vector2(230, 230)
	scene.world._gui_input(second)
	var old_zoom = scene.world.zoom
	drag.index = 1; drag.position = Vector2(300, 230)
	scene.world._gui_input(drag)
	check(scene.world.zoom > old_zoom, "Two-finger pinch zooms map")
	root.size = Vector2i(900, 440)
	await capture("mobile-landscape-ru")
	if "--layout-debug" in OS.get_cmdline_user_args(): print("LOCALE ", L.language, " ", TranslationServer.get_locale(), " INCOME ", scene.income_label.text, " TR ", scene.income_label.tr(scene.income_label.text))
	check(scene.game.home >= 0 and scene.page == "game", "Rotation retains current campaign")
	scene.open_card("army")
	var replaced_tween = scene.card.get_meta("page_tween")
	scene.open_card("economy")
	check(not replaced_tween.is_valid(), "Repeated card navigation cancels the previous tween")
	await create_timer(0.25).timeout
	check(is_equal_approx(scene.card.modulate.a, 1.0) and scene.card.scale == Vector2.ONE, "Card transition completes")
	scene.open_card("army")
	await capture("mobile-army-landscape-ru")
	check(scene.card.get_rect().end.x <= scene.size.x + 1 and scene.card.get_rect().end.y <= scene.size.y, "Landscape detail panel fits")
	scene._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	check(scene.game.paused, "Backgrounding pauses and saves offline play")
	scene.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	root.content_scale_size = Vector2i(1440, 900)
	L.set_language("ru")
	print("PASS: %d mobile/localization checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
