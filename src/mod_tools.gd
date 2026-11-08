extends RefCounted

const L = preload("res://src/i18n.gd")
const Package = preload("res://src/mod_package.gd")
var ui: Control

func show_tools() -> void:
	ui.page = "mod_tools"
	ui.game.paused = true
	ui.menu_frame(L.text("Инструменты модов"), L.text("Итоговые правила, конфликты, проверка пакетов и тест сценария."), 850, 790)
	ui.menu_body.add_child(ui.button(L.text("Открыть редактор модов"), func(): OS.shell_open("https://byxarek.github.io/atlas/mod-studio.ru.html" if L.language == "ru" else "https://byxarek.github.io/atlas/mod-studio.html")))
	ui.menu_body.add_child(ui.button(L.text("Проверить пакет…"), inspect_file.bind(false)))
	ui.menu_body.add_child(ui.button(L.text("Проверить сохранение…"), inspect_file.bind(true)))
	ui.menu_body.add_child(ui.button(L.text("Тестовая кампания текущего профиля"), test_campaign))
	var sources = Engine.get_meta("atlas_rule_sources", {})
	for item in Engine.get_meta("atlas_rule_conflicts", []):
		ui.menu_body.add_child(ui.paragraph("%s: %s → %s" % [item.field, item.previous, item.winner], ui.GOLD))
	for key in ui.Simulation.B:
		ui.info(ui.menu_body, str(key), JSON.stringify(ui.Simulation.B[key]) + " · " + str(sources.get(key, "base")))
	var content = ui.Simulation.Runtime.content()
	for key in ["units", "buildings", "technologies", "events", "panels", "assets"]:
		ui.info(ui.menu_body, key, str(content.get(key, []).size()))
	ui.menu_body.add_child(ui.paragraph(JSON.stringify(content.get("victory", {}))))
	ui.menu_body.add_child(ui.button(L.text("Назад"), ui.mod_menu.show_menu))

func inspect_file(save: bool) -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Campaign"]) if save else PackedStringArray(["*.atlasmod ; ATLAS mod"])
	dialog.use_native_dialog = true
	ui.add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(func(path):
		var problem = ""
		if save:
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			var validator = ui.Simulation.new()
			if not validator.restore_data(data, false): problem = L.text("Сохранение несовместимо с текущим профилем или повреждено.")
		else:
			var data = Package.read(path)
			if data.is_empty(): problem = "Invalid .atlasmod"
			else:
				var documents = Engine.get_meta("atlas_rule_documents", []).filter(func(doc): return doc.id != data.id)
				documents.append(data)
				var seen = []
				for doc in documents:
					if doc.game_version != ProjectSettings.get_setting("application/config/version") or not doc.get("requires", []).all(func(id): return id in seen): problem = "Incompatible version or missing earlier dependency"
					seen.append(doc.id)
				for doc in documents:
					if doc.get("conflicts", []).any(func(id): return id in seen): problem = "Conflicting mods"
				if problem.is_empty():
					var compiled = Package.Rules.compose(documents, Engine.get_meta("atlas_base_balance"))
					problem = compiled.error
		ui.message(L.text("Проверка"), L.text("Проверка пройдена. Файлы и текущая кампания не изменены.") if problem.is_empty() else problem)
		dialog.queue_free())
	dialog.popup_centered_ratio(0.8)

func test_campaign() -> void:
	if ui.network.active:
		ui.message(L.text("Моды"), L.text("Сначала покиньте сетевую комнату."))
		return
	if not ui.autosave(): return
	ui.show_new_game()
	var home = int(ui.Simulation.Runtime.content().get("scenario", {}).get("default_home", 0))
	var index = ui.new_country_ids.find(home)
	if index >= 0: ui.country_picker.select(index)
	ui.begin_campaign()
