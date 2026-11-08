extends SceneTree

const TEMP = "user://test_export_smoke"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP)
	var args = OS.get_cmdline_user_args()
	var portable = not args.is_empty()
	if portable:
		var Mods = load("res://src/mods.gd")
		Mods.network_boot_path = TEMP + "/boot.json"
		OS.set_environment("ATLAS_MODS_DIR", ProjectSettings.globalize_path(TEMP + "/mods"))
		DirAccess.make_dir_recursive_absolute(TEMP + "/mods")
		assert(DirAccess.copy_absolute(args[0], TEMP + "/mods/frontier.atlasmod") == OK)
		assert(Mods.new().activate_network())
	var scene = load("res://main.tscn").instantiate()
	scene.settings_path = TEMP + "/settings.cfg"
	scene.store = scene.SaveStore.new(TEMP + "/saves")
	root.add_child(scene)
	await process_frame
	assert(scene.page == "menu" and scene.sound.streams.size() == scene.sound.CUES.size())
	scene.game.start(0)
	scene.enter_game()
	scene.selected = 0
	assert(scene.game.countries.size() == (3 if portable else 244))
	if portable:
		assert(scene.game.units.size() == 4 and scene.game.coins == 600)
		assert(scene.Simulation.Runtime.research(scene.game, 0) and scene.Simulation.Runtime.research(scene.game, 1))
		assert(scene.Simulation.Runtime.construct(scene.game, 0, 0) and scene.game.recruit(3))
	else: assert(scene.game.recruit(0))
	scene.open_card("army")
	assert(scene.card.visible)
	scene.open_card("economy")
	assert(scene.store.autosave(scene.game) == OK)
	var loaded = scene.Simulation.new()
	assert(loaded.load_game(scene.store.list_saves()[0].path))
	assert(loaded.units == scene.game.units)
	for player in scene.sound.players + scene.sound.loops.values(): player.stop()
	await create_timer(0.2).timeout
	scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("PASS: exported scenes, audio, %s rules, commands, UI and save/load" % ("portable" if portable else "vanilla"))
	quit()
