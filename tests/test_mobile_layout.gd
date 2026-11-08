extends SceneTree

var scene: Control
var failures = 0
var checks = 0

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(text)

func _initialize() -> void:
	call_deferred("run")

func check_page(name: String) -> void:
	for i in 4: await process_frame
	for control in scene.overlay.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree(): continue
		var rect = control.get_global_rect()
		if control is ScrollContainer and control.get_parent() is VBoxContainer:
			check(control.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Nested mobile lists use the page scroll")
		check(rect.position.x >= -1 and rect.end.x <= scene.size.x + 1,
			"%s / %s / %s exceeds width %d: %s" % [name, control.get_class(), control.get("text"), scene.size.x, rect])
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("res://build/fit-" + name + ".png")

func run() -> void:
	root.min_size = Vector2i.ZERO
	scene = load("res://main.tscn").instantiate()
	scene.force_mobile = true
	scene.settings_path = "user://test_mobile_layout_settings.cfg"
	scene.store = scene.SaveStore.new("user://test_mobile_layout_saves")
	root.add_child(scene)
	scene.game.start(3)
	check(scene.store.autosave(scene.game) == OK, "Create a real save for layout checks")
	for language in ["ru", "en"]:
		scene.L.set_language(language)
		for dimensions in [Vector2i(320, 640), Vector2i(360, 800), Vector2i(800, 360)]:
			root.content_scale_size = Vector2i(mini(dimensions.x, dimensions.y), mini(dimensions.x, dimensions.y))
			root.size = dimensions
			for i in 3: await process_frame
			scene.selected = 1
			scene.confirm_attack()
			for i in 4: await process_frame
			for control in scene.mobile_modal.find_children("*", "Control", true, false):
				if control is ScrollBar: continue
				var rect = control.get_global_rect()
				check(rect.position.x >= -1 and rect.end.x <= scene.size.x + 1, "Mobile confirmation fits screen")
			scene.mobile_back()
			await process_frame
			check(not is_instance_valid(scene.mobile_modal), "Back cancels mobile confirmation")
			scene.show_main_menu()
			await check_page("menu-%s-%d" % [language, dimensions.x])
			check(scene.menu_shell.get_theme_stylebox("panel") is StyleBoxEmpty, "Mobile menu has no enclosing card")
			for action in scene.menu_body.get_children():
				if action is Button: check(action.flat, "Main actions use a flat list")
			if dimensions.x > dimensions.y:
				var actions: ScrollContainer = scene.menu_body.get_parent()
				var exit_button: Button = scene.menu_body.get_child(-1)
				check(actions.get_v_scroll_bar().visible, "Short landscape menu has an action scrollbar")
				actions.ensure_control_visible(exit_button)
				await process_frame
				var viewport = actions.get_global_rect()
				var last = exit_button.get_global_rect()
				check(viewport.grow(1).encloses(last), "Scrolling reaches the exit button: %s in %s" % [last, viewport])
			scene.release = {"tag": "v10.0.0", "notes": "Release notes\n".repeat(100)}
			scene.release_notice_pending = true
			scene.show_release_update()
			for i in 4: await process_frame
			var update_actions = scene.mobile_modal.find_children("*", "Button", true, false)
			check(update_actions.size() == 2 and update_actions.all(func(action): return scene.get_global_rect().encloses(action.get_global_rect())),
				"Update actions remain visible when the notes overflow")
			scene.mobile_back()
			await process_frame
			scene.release.clear()
			scene.show_new_game()
			await check_page("new-%s-%d" % [language, dimensions.x])
			scene.show_settings()
			await check_page("settings-%s-%d" % [language, dimensions.x])
			scene.overlay.find_child("SettingsSection1", true, false).press()
			await check_page("settings-display-%s-%d" % [language, dimensions.x])
			scene.overlay.find_child("SettingsSection2", true, false).press()
			await check_page("settings-audio-%s-%d" % [language, dimensions.x])
			scene.show_saves()
			await check_page("saves-%s-%d" % [language, dimensions.x])
			scene.show_pause()
			await check_page("pause-%s-%d" % [language, dimensions.x])
			scene.online.show_browser()
			await check_page("online-%s-%d" % [language, dimensions.x])
			scene.online.show_lan_browser()
			await check_page("lan-%s-%d" % [language, dimensions.x])
			scene.network.stop_scan()
			scene.network.hosting = true
			scene.network.active = true
			scene.network.stage = "lobby"
			scene.network.my_slot = "host"
			scene.network.host_slot = "host"
			scene.network.lobby_name = "A".repeat(40)
			scene.network.players.host = scene.network.make_player("Player".repeat(4), "", 1, false)
			for i in 10:
				scene.network.players["bot_%d" % i] = scene.network.make_player("Bot %d" % i, "", 0, true)
			scene.online.show_lobby()
			await check_page("lobby-%s-%d" % [language, dimensions.x])
			scene.network.active = false
			scene.network.hosting = false
			scene.network.stage = "offline"
			scene.network.players.clear()
	scene.queue_free()
	await process_frame
	print("%s: %d mobile width checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(1 if failures else 0)
