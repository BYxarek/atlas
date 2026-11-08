extends RefCounted

const L = preload("res://src/i18n.gd")
const Mods = preload("res://src/mods.gd")
var ui: Control
var manager = Mods.new()

func show_menu() -> void:
	manager.scan()
	DirAccess.make_dir_recursive_absolute(Mods.network_directory())
	ui.page = "mods"
	ui.game.paused = true
	ui.menu_frame(L.text("Моды"), L.text("Изменения применятся после перезапуска игры."), 780, 790)
	ui.menu_body.add_child(ui.paragraph(L.text("Одиночные моды могут выполнять код. Сетевые моды используют общие правила для LAN, VPS и PHP.")))
	ui.menu_body.add_child(ui.paragraph(ProjectSettings.globalize_path(manager.directory), ui.MUTED, 12))
	if Engine.has_meta("atlas_mod_error"):
		ui.menu_body.add_child(ui.paragraph(str(Engine.get_meta("atlas_mod_error")), ui.RED))
	for problem in manager.errors:
		ui.menu_body.add_child(ui.paragraph(problem, ui.RED))
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 200
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.menu_body.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var order = manager.selected.duplicate()
	for mod in manager.installed:
		if not mod.id in order: order.append(mod.id)
	for id in order:
		var mod = manager.find_mod(str(id))
		var enabled = id in manager.selected
		var box = ui.box_panel(list)
		box.add_child(ui.paragraph((mod.get("name", str(id))) + " · " + mod.get("version", "?"), ui.INK))
		if not mod.get("description", "").is_empty(): box.add_child(ui.paragraph(mod.description))
		if not mod.get("requires", []).is_empty(): box.add_child(ui.paragraph("Requires: " + ", ".join(mod.requires)))
		var active = id in Engine.get_meta("atlas_mod_list", [])
		box.add_child(ui.label(L.text("Активен в этой сессии") if active else L.text("Не активен в этой сессии"), 12, ui.MINT if active else ui.MUTED))
		box.add_child(ui.button(L.text("Выключить") if enabled else L.text("Включить"), func():
			var next = manager.selected.duplicate()
			if enabled:
				next.erase(id)
				commit(next)
			else:
				next.append(id)
				ui.confirm_action(L.text("Включить мод"), L.text("Этот мод получает права игры на выполнение кода и доступ к файлам. Вы доверяете его автору?"), func(): commit(next))))
		if enabled:
			var index = manager.selected.find(id)
			for delta in [-1, 1]:
				var move = ui.button(L.text("Выше") if delta < 0 else L.text("Ниже"), func():
					var next = manager.selected.duplicate()
					next[index] = next[index + delta]
					next[index + delta] = id
					commit(next))
				move.disabled = index + delta < 0 or index + delta >= manager.selected.size()
				box.add_child(move)
	if order.is_empty(): list.add_child(ui.paragraph(L.text("Моды пока не установлены. Выберите файл .atlasmod.")))
	ui.menu_body.add_child(ui.button(L.text("Установить мод…"), install_dialog.bind(false)))
	ui.menu_body.add_child(ui.paragraph(L.text("Папка сетевых модов: ") + ProjectSettings.globalize_path(Mods.network_directory()), ui.MUTED, 12))
	ui.menu_body.add_child(ui.button(L.text("Установить сетевой мод…"), install_dialog.bind(true)))
	ui.menu_body.add_child(ui.button(L.text("Установить сборку модов…"), install_set_dialog))
	ui.menu_body.add_child(ui.button(L.text("Запустить с сетевыми модами"), start_network))
	if FileAccess.file_exists(Mods.NETWORK_BOOT):
		ui.menu_body.add_child(ui.button(L.text("Вернуться к одиночным модам"), func():
			if not ui.autosave(): return
			DirAccess.remove_absolute(Mods.NETWORK_BOOT)
			ui.online.restart_for_mods()))
	ui.menu_body.add_child(ui.button(L.text("Инструменты модов"), ui.mod_tools.show_tools))
	ui.menu_body.add_child(ui.button(L.text("Обновить список"), show_menu))
	ui.menu_body.add_child(ui.button(L.text("Выключить все моды"), func(): commit([])))
	ui.menu_body.add_child(ui.button(L.text("Назад"), ui.show_main_menu))

func commit(order: Array) -> void:
	var problem = manager.save_selection(order)
	if not problem.is_empty(): ui.message(L.text("Моды"), problem)
	else: show_menu()

func install_dialog(network: bool = false) -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.atlasmod ; ATLAS mod"])
	dialog.use_native_dialog = true
	ui.add_child(dialog)
	dialog.file_selected.connect(func(path):
		var problem = Mods.install_network(path) if network else manager.install(path)
		dialog.queue_free()
		show_menu()
		if not problem.is_empty(): ui.message(L.text("Моды"), problem))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.8)

func start_network() -> void:
	var catalog = Mods.network_catalog()
	var profile = []
	for data in catalog:
		if data.has("error"):
			ui.message(L.text("Моды"), data.error)
			return
		if not Mods.Package.portable(data):
			ui.message(L.text("Моды"), "Mod has no compatible shared network rules: " + data.id)
			return
		profile.append(Mods.Package.descriptor(data))
	var composed = Mods.Package.Rules.compose(catalog, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))
	if not composed.error.is_empty():
		ui.message(L.text("Моды"), composed.error)
		return
	if not ui.autosave(): return
	var error = Mods.write_network_boot(profile)
	if error != OK: ui.message(L.text("Моды"), error_string(error))
	else: ui.online.restart_for_mods()

func install_set_dialog() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.atlaspack ; ATLAS mod set"])
	dialog.use_native_dialog = true
	ui.add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(func(path):
		dialog.queue_free()
		if not ui.autosave(): return
		var problem = Mods.install_network_set(path)
		if not problem.is_empty(): ui.message(L.text("Моды"), problem)
		else: ui.online.restart_for_mods())
	dialog.popup_centered_ratio(0.8)
