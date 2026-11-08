extends Control

const L = preload("res://src/i18n.gd")

const Simulation = preload("res://src/game.gd")
const WorldMap = preload("res://src/world_map.gd")
const SaveStore = preload("res://src/saves.gd")
const Sound = preload("res://src/sound.gd")
const NetworkSession = preload("res://src/network_session.gd")
const OnlineMenu = preload("res://src/online_menu.gd")
const ModMenu = preload("res://src/mod_menu.gd")
var mod_menu = ModMenu.new()
var mod_tools = preload("res://src/mod_tools.gd").new()
const Media = preload("res://src/mod_media.gd")
var INK = Media.color("ink", Color("f0f6ff"))
var MUTED = Media.color("muted", Color("a4bdd5"))
var MINT = Media.color("accent", Color("57edc3"))
const GOLD = Color("ffda80")
const RED = Color("ff938d")
const BUSINESS_NAMES = ["Торговый квартал", "Промышленный комплекс", "Транспортный узел", "Технологический парк", "Энергетическая компания"]
var game = Simulation.new()
var store = SaveStore.new()
var world: Control
var hud: Control
var balance: Label
var income_label: Label
var arsenal_button: Button
var notifications_button: Button
var threat_panel: PanelContainer
var threat_timer: Label
var threat_identity: Label
var toast: Label
var toast_panel: PanelContainer
var toast_tween: Tween
var last_event = ""
var overlay: Control
var menu_body: VBoxContainer
var card: PanelContainer
var card_body: VBoxContainer
var page = "menu"
var card_view = ""
var selected = -1
var save_origin = "menu"
var saves_list: Array = []
var actionable: Array = []
var country_picker: OptionButton
var color_picker: ColorPickerButton
var campaign_color = MINT
var new_country_ids: Array = []
var country_list: ItemList
var list_ids: Array = []
var search: LineEdit
var save_timer = 0
var ended_shown = false
var settings_path = "user://settings.cfg"
var settings_origin = "menu"
var fullscreen_toggle: CheckButton
var windowed_mode = Window.MODE_WINDOWED
var windowed_rect = Rect2i()
var sound: Node
var master_slider: HSlider
var effects_slider: HSlider
var network: Node
var online = OnlineMenu.new()
var force_mobile = false
var mobile = false
var treasury: PanelContainer
var toolbar: HBoxContainer
var pause_button: Button
var zoom_controls: VBoxContainer
var insets = Vector4.ZERO
var menu_shell: PanelContainer
var mobile_modal: Control
var show_fps = false
var fps_panel: PanelContainer
var fps_label: Label

func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		add_child(load("res://src/vps_server.gd").new())
		return
	mobile = force_mobile or OS.has_feature("android") or "--mobile-preview" in OS.get_cmdline_user_args()
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mod_menu.ui = self
	mod_tools.ui = self
	L.setup(settings_path)
	get_window().title = L.text("ATLAS — Мировое господство")
	online.nickname = L.text("Игрок")
	online.room_name = L.text("Моя партия")
	if mobile:
		Engine.max_fps = 60
		get_window().min_size = Vector2i.ZERO
		var logical_short = 440
		if OS.has_feature("android"):
			var dpi = DisplayServer.screen_get_dpi()
			if dpi >= 120: logical_short = clampi(roundi(mini(get_window().size.x, get_window().size.y) * 160.0 / dpi), 320, 720)
		get_window().content_scale_size = Vector2i(logical_short, logical_short)
	sound = Sound.new()
	sound.game = game
	add_child(sound)
	game.sound_requested.connect(sound.play)
	build_theme()
	world = WorldMap.new()
	world.setup(game)
	add_child(world)
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.country_selected.connect(select_country)
	build_hud()
	build_card()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	build_fps_panel()
	show_main_menu()
	var timer = Timer.new()
	timer.wait_time = 1
	timer.timeout.connect(on_second)
	add_child(timer)
	timer.start()
	get_tree().auto_accept_quit = false
	restore_display_settings()
	resized.connect(responsive_layout)
	responsive_layout()
	network = NetworkSession.new()
	add_child(network)
	online.ui = self
	online.net = network
	online.setup_mods()
	network.lobby_changed.connect(func():
		if network.stage == "lobby": online.show_lobby())
	network.view_received.connect(receive_network_view)
	network.discovery_changed.connect(online.refresh_rooms)
	network.directory_changed.connect(func():
		if network.stage == "directory":
			if page != "online":
				sound.stop_gameplay()
				game.reset()
				world.clear_motion()
				online.show_browser()
			else: online.refresh_rooms())
	network.notice.connect(func(text): message(L.text("Сетевая игра"), text))
	network.closed.connect(func(reason):
		sound.stop_gameplay()
		game.reset()
		world.clear_motion()
		show_main_menu()
		if not reason.is_empty(): message(L.text("Сетевая игра"), reason))
	if FileAccess.file_exists("user://mods_starting"): DirAccess.remove_absolute("user://mods_starting")

func style(bg: Color, border_color: Color = Color.TRANSPARENT, radius: int = 12) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border_color
	box.set_border_width_all(1 if border_color.a > 0 else 0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func build_fps_panel() -> void:
	fps_panel = PanelContainer.new()
	fps_panel.name = "FpsPanel"
	fps_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_panel.add_theme_stylebox_override("panel", style(Color("10243ddd"), Color("4b829f"), 8))
	add_child(fps_panel)
	fps_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	fps_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fps_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	fps_panel.offset_right = -12
	fps_panel.offset_bottom = -12
	fps_label = label("", 12, INK)
	fps_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_panel.add_child(fps_label)
	fps_panel.hide()

func update_performance_overlay() -> void:
	var public_lobby = page == "lobby" and is_instance_valid(network) and network.active and network.directory_client
	fps_panel.visible = show_fps and not public_lobby
	var frame_rate = int(Engine.get_frames_per_second())
	if fps_panel.visible: fps_label.text = "FPS %d" % frame_rate
	if public_lobby: online.update_telemetry(frame_rate if show_fps else -1)

func build_theme() -> void:
	var t = Theme.new()
	t.set_sound("pressed_sound", "BaseButton", sound.streams.click)
	t.set_sound("pressed_disabled_sound", "BaseButton", sound.streams.error)
	t.set_sound("focus_sound", "BaseButton", sound.streams.select)
	t.default_font_size = 17 if mobile else 14
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("71859e"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg = Color("22466b")
		if state == "hover": bg = Color("30618a")
		if state == "pressed": bg = Color("236f79")
		if state == "disabled": bg = Color("1a2c43")
		if state == "focus": bg = Color.TRANSPARENT
		t.set_stylebox(state, "Button", style(bg, MINT if state == "focus" else Color("43769c"), 8))
	for control in ["LineEdit", "ItemList", "OptionButton"]:
		t.set_color("font_color", control, INK)
		t.set_stylebox("normal" if control != "ItemList" else "panel", control, style(Color("142c49"), Color("3a6084"), 8))
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_stylebox("focus", "LineEdit", style(Color("142c49"), MINT, 8))
	t.set_stylebox("selected", "ItemList", style(Color("236b78")))
	t.set_stylebox("selected_focus", "ItemList", style(Color("236b78")))
	t.set_constant("v_separation", "ItemList", 28 if mobile else 12)
	t.set_color("font_color", "ItemList", INK)
	for entry in [["background", Color("284968")], ["fill", MINT]]:
		var thin = style(entry[1], Color.TRANSPARENT, 3)
		thin.set_content_margin_all(0)
		t.set_stylebox(entry[0], "ProgressBar", thin)
	theme = t

func label(text: String, font_size: int = 14, color: Color = INK) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", maxi(font_size, 15) if mobile else font_size)
	node.add_theme_color_override("font_color", color)
	if mobile:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func paragraph(text: String, color: Color = MUTED, font_size: int = 13) -> Label:
	var node = label(text, font_size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func button(text: String, action: Callable, accent: bool = false) -> Button:
	var node = Button.new()
	node.text = text
	node.custom_minimum_size.y = 42
	if mobile:
		node.custom_minimum_size.y = 56
		node.custom_minimum_size.x = 56
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.add_theme_font_size_override("font_size", 16)
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(action)
	if accent:
		node.add_theme_stylebox_override("normal", style(MINT, Color.TRANSPARENT, 8))
		node.add_theme_color_override("font_color", Color("0b2826"))
		node.add_theme_color_override("font_hover_color", MINT)
	return node

func clear_box(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func info(parent: Node, caption: String, value: String, color: Color = INK) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var name_label = label(caption, 13, MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mobile: name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)
	row.add_child(label(value, 14, color))

func box_panel(parent: Node) -> VBoxContainer:
	var shell = PanelContainer.new()
	shell.add_theme_stylebox_override("panel", StyleBoxEmpty.new() if mobile else style(Color("193b59"), Color("3c6c8f")))
	parent.add_child(shell)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	shell.add_child(box)
	return box

func build_hud() -> void:
	hud = Control.new()
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	treasury = PanelContainer.new()
	treasury.position = Vector2(24, 22)
	treasury.add_theme_stylebox_override("panel", style(Color("153452f5"), Color("4d8dac")))
	hud.add_child(treasury)
	var money_row = HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 10 if mobile else 22)
	treasury.add_child(money_row)
	balance = label("◈ 180", 20 if mobile else 23, GOLD)
	balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	money_row.add_child(balance)
	income_label = label(L.text("+0 / сек"), 15, MINT)
	income_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	money_row.add_child(income_label)
	pause_button = button("☰" if mobile else "☰  Esc", show_pause)
	hud.add_child(pause_button)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -118
	pause_button.offset_right = -24
	pause_button.offset_top = 22
	pause_button.offset_bottom = 66
	toolbar = HBoxContainer.new()
	hud.add_child(toolbar)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	toolbar.offset_left = 24
	toolbar.offset_top = -66
	toolbar.offset_bottom = -22
	toolbar.add_theme_constant_override("separation", 8)
	toolbar.add_child(button(L.text("⚑\nАрмия") if mobile else L.text("⚑  Армия"), func(): open_card("army")))
	toolbar.add_child(button(L.text("◎\nСтраны") if mobile else L.text("◎  Страны"), func(): open_card("countries")))
	arsenal_button = button(L.text("☢  Арсенал · 0"), func(): open_card("arsenal"))
	toolbar.add_child(arsenal_button)
	notifications_button = button(L.text("◉  Уведомления"), func(): open_card("notifications"))
	toolbar.add_child(notifications_button)
	threat_panel = PanelContainer.new()
	threat_panel.add_theme_stylebox_override("panel", style(Color("4c2e3af5"), Color("d79c58")))
	hud.add_child(threat_panel)
	threat_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	threat_panel.offset_left = -364
	threat_panel.offset_right = -24
	threat_panel.offset_top = 80
	threat_panel.offset_bottom = 158
	var threat_box = VBoxContainer.new()
	threat_box.add_theme_constant_override("separation", 5)
	threat_panel.add_child(threat_box)
	threat_timer = label("", 20, GOLD)
	threat_box.add_child(threat_timer)
	threat_identity = label("", 11, MUTED)
	threat_identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	threat_box.add_child(threat_identity)
	threat_panel.hide()
	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", style(Color("1b405ef5"), Color("62b9c9"), 10))
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toast_panel)
	toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_panel.offset_left = -345
	toast_panel.offset_right = 345
	toast_panel.offset_top = 22
	toast_panel.offset_bottom = 84
	toast = paragraph("", INK, 14)
	toast.custom_minimum_size.x = 654
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(toast)
	toast_panel.hide()
	if mobile:
		zoom_controls = VBoxContainer.new()
		hud.add_child(zoom_controls)
		zoom_controls.add_child(button("+", func(): world.set_zoom(world.zoom * 1.3)))
		zoom_controls.add_child(button("−", func(): world.set_zoom(world.zoom / 1.3)))
		zoom_controls.add_child(button("⌂", world.reset_view))

func build_card() -> void:
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", style(Color("172f4ff5"), Color("4b829f")))
	add_child(card)
	card.anchor_left = 1
	card.anchor_right = 1
	card.anchor_bottom = 1
	card.offset_left = -364
	card.offset_right = -24
	card.offset_top = 86
	card.offset_bottom = -90
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	card.add_child(scroll)
	card_body = VBoxContainer.new()
	card_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_body.add_theme_constant_override("separation", 13)
	scroll.add_child(card_body)
	card.hide()
	if mobile: card_body.add_theme_constant_override("separation", 14)

func menu_frame(title: String, subtitle: String, width: int = 500, height: int = 560) -> void:
	var changed_page = not overlay.visible or not is_instance_valid(menu_body) or menu_body.get_child(0).text != title
	clear_box(overlay)
	overlay.show()
	hud.hide()
	card.hide()
	var dim = ColorRect.new()
	dim.color = Color(0.035, 0.08, 0.16, 0.65)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell = PanelContainer.new()
	menu_shell = shell
	shell.add_theme_stylebox_override("panel", style(Color("172f4ff5"), Color("497b9c"), 18))
	overlay.add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	shell.offset_left = -width / 2.0
	shell.offset_right = width / 2.0
	shell.offset_top = -height / 2.0
	shell.offset_bottom = height / 2.0
	if mobile:
		shell.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shell.offset_left = insets.x
		shell.offset_top = insets.y
		shell.offset_right = -insets.z
		shell.offset_bottom = -insets.w
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	shell.add_child(margin)
	menu_body = VBoxContainer.new()
	menu_body.add_theme_constant_override("separation", 14)
	if mobile:
		var scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		margin.add_child(scroll)
		scroll.add_child(menu_body)
		menu_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else: margin.add_child(menu_body)
	var title_label = label(title, 26 if mobile else 32, MINT)
	if mobile:
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_body.add_child(title_label)
	menu_body.add_child(paragraph(subtitle))
	if mobile:
		call_deferred("adapt_inputs", menu_body)
		if changed_page: animate_page(shell)

func menu_scroll() -> void:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	menu_body.add_child(scroll)
	menu_body = VBoxContainer.new()
	menu_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_body.add_theme_constant_override("separation", 14)
	scroll.add_child(menu_body)

func animate_page(target: Control) -> void:
	if not mobile: return
	var previous: Tween = target.get_meta("page_tween") if target.has_meta("page_tween") else null
	if is_instance_valid(previous): previous.kill()
	target.modulate.a = 0.25
	target.scale = Vector2(0.985, 0.985)
	var tween = target.create_tween().set_parallel(true)
	target.set_meta("page_tween", tween)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "modulate:a", 1.0, 0.18)
	tween.tween_property(target, "scale", Vector2.ONE, 0.18)

func show_main_menu() -> void:
	game.paused = true
	page = "menu"
	menu_frame("◈  A T L A S", L.text("МИРОВОЕ ГОСПОДСТВО\nОдин мир. Ваша история."), 500, 620)
	var space = Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_body.add_child(space)
	saves_list = store.list_saves()
	var latest = saves_list.filter(func(entry): return entry.valid and not entry.defeated)
	var resume = button(L.text("Продолжить"), func():
		if game.home >= 0:
			enter_game()
		elif not latest.is_empty():
			load_campaign(latest[0].path), true)
	resume.disabled = game.home < 0 and latest.is_empty()
	menu_body.add_child(resume)
	menu_body.add_child(button(L.text("Новая игра"), show_new_game))
	menu_body.add_child(button(L.text("Сетевая игра · PvP + боты"), func():
		if not str(Engine.get_meta("atlas_mods", "")).is_empty() and not Engine.get_meta("atlas_network_mode", false):
			message(L.text("Моды"), L.text("Выключите моды и перезапустите игру для сетевой игры."))
		elif autosave(): online.show_browser()))
	menu_body.add_child(button(L.text("Сохранения · %d") % saves_list.size(), func(): show_saves("menu")))
	menu_body.add_child(button(L.text("Настройки"), func(): show_settings("menu")))
	menu_body.add_child(button(L.text("Моды"), mod_menu.show_menu))
	if Engine.has_meta("atlas_mod_error"):
		menu_body.add_child(paragraph(str(Engine.get_meta("atlas_mod_error")), RED, 12))
	menu_body.add_child(button(L.text("Выйти"), request_exit))
	menu_body.add_child(paragraph(L.text("Нативная 2D-стратегия · %s · v0.3.0") % ("Android" if mobile else "Windows"), MUTED, 11))
	if mobile:
		for action in menu_body.get_children():
			if action is Button:
				action.flat = true
				action.alignment = HORIZONTAL_ALIGNMENT_LEFT
				action.add_theme_color_override("font_color", MINT if action == resume else INK)

func show_settings(origin: String = "menu") -> void:
	settings_origin = origin
	page = "settings"
	game.paused = true
	menu_frame(L.text("Настройки"), L.text("Экран и звук"), 580, 600)
	menu_body.add_child(label(L.text("Язык / Language"), 16))
	var language_picker = OptionButton.new()
	language_picker.custom_minimum_size.y = 56 if mobile else 44
	language_picker.add_item("Русский")
	language_picker.add_item("English")
	language_picker.select(0 if L.language == "ru" else 1)
	language_picker.item_selected.connect(func(index): change_language("ru" if index == 0 else "en"))
	menu_body.add_child(language_picker)
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = L.text("Полноэкранный режим без рамок")
	fullscreen_toggle.custom_minimum_size.y = 52
	fullscreen_toggle.button_pressed = get_window().mode == Window.MODE_FULLSCREEN
	fullscreen_toggle.toggled.connect(set_fullscreen)
	menu_body.add_child(fullscreen_toggle)
	if not mobile:
		menu_body.add_child(paragraph(L.text("Игра занимает весь монитор без заголовка, рамок и панели задач. При выключении восстанавливается предыдущий оконный режим.")))
		menu_body.add_child(paragraph(L.text("Изменения применяются сразу и сохраняются между запусками. Карта заполняет окно при любом соотношении сторон.")))
	if mobile:
		fullscreen_toggle.hide()
		menu_body.add_child(paragraph(L.text("Касание выбирает страну. Перетаскивание двигает карту, два пальца меняют масштаб. Назад закрывает панель или открывает меню.")))
	var map_toggle = CheckButton.new()
	map_toggle.name = "MapViewToggle"
	map_toggle.text = L.text("Объёмная карта (2.5D)")
	map_toggle.custom_minimum_size.y = 52
	map_toggle.button_pressed = world.tilted
	map_toggle.toggled.connect(set_map_view)
	menu_body.add_child(map_toggle)
	var fps_toggle = CheckButton.new()
	fps_toggle.name = "FpsToggle"
	fps_toggle.text = L.text("Показывать FPS")
	fps_toggle.custom_minimum_size.y = 52
	fps_toggle.button_pressed = show_fps
	fps_toggle.toggled.connect(set_fps_counter)
	menu_body.add_child(fps_toggle)
	if not mobile:
		var quality_toggle = CheckButton.new()
		quality_toggle.name = "MapQualityToggle"
		quality_toggle.text = L.text("Высокое качество 2.5D")
		quality_toggle.custom_minimum_size.y = 52
		quality_toggle.button_pressed = world.detailed_map
		quality_toggle.toggled.connect(set_map_quality)
		menu_body.add_child(quality_toggle)
	master_slider = volume_control(L.text("Общая громкость"), sound.master_volume)
	effects_slider = volume_control(L.text("Громкость эффектов"), sound.effects_volume)
	master_slider.value_changed.connect(func(value): sound.set_mix(value / 100.0, sound.effects_volume); save_audio_settings())
	effects_slider.value_changed.connect(func(value): sound.set_mix(sound.master_volume, value / 100.0); save_audio_settings())
	menu_body.add_child(paragraph(L.text("Общая громкость управляет всеми звуками. Громкость эффектов — интерфейсом и игровыми событиями; музыкальные сигналы результата регулируются общей громкостью."), MUTED, 12))
	menu_body.add_child(button(L.text("Назад"), close_settings))

func volume_control(caption: String, value: float) -> HSlider:
	var row = HBoxContainer.new()
	menu_body.add_child(row)
	var text = label(caption, 14)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var percentage = label("%d%%" % roundi(value * 100), 13, GOLD)
	row.add_child(percentage)
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundi(value * 100)
	slider.custom_minimum_size.y = 28
	menu_body.add_child(slider)
	slider.value_changed.connect(func(number): percentage.text = "%d%%" % roundi(number))
	slider.drag_ended.connect(func(_changed): sound.play("confirm"))
	return slider

func save_audio_settings() -> void:
	var config = ConfigFile.new()
	config.load(settings_path)
	config.set_value("audio", "master", sound.master_volume)
	config.set_value("audio", "effects", sound.effects_volume)
	var error = config.save(settings_path)
	if error != OK:
		sound.play("error")
		message(L.text("Настройки"), L.text("Не удалось сохранить громкость: ") + error_string(error))

func close_settings() -> void:
	if settings_origin == "pause": show_pause()
	else: show_main_menu()

func change_language(language: String) -> void:
	L.set_language(language)
	get_window().title = L.text("ATLAS — Мировое господство")
	var config = ConfigFile.new()
	config.load(settings_path)
	config.set_value("interface", "language", language)
	var error = config.save(settings_path)
	if error != OK: message(L.text("Настройки"), L.text("Не удалось сохранить язык.") + " " + error_string(error))
	if is_instance_valid(toast_tween): toast_tween.kill()
	remove_child(hud)
	hud.queue_free()
	build_hud()
	move_child(hud, world.get_index() + 1)
	responsive_layout()
	show_settings(settings_origin)
	world.refresh_map()

func responsive_layout() -> void:
	if not mobile or not is_instance_valid(hud): return
	insets = Vector4.ZERO
	if OS.has_feature("android"):
		var safe = DisplayServer.get_display_safe_area()
		var window_size = Vector2(get_window().size)
		var scale = window_size.x / maxf(1, size.x)
		insets = Vector4(maxf(0, safe.position.x), maxf(0, safe.position.y), maxf(0, window_size.x - safe.end.x), maxf(0, window_size.y - safe.end.y)) / maxf(1, scale)
	treasury.position = Vector2(insets.x + 10, insets.y + 10)
	pause_button.offset_left = -insets.z - 68
	pause_button.offset_right = -insets.z - 10
	pause_button.offset_top = insets.y + 10
	pause_button.offset_bottom = insets.y + 66
	toolbar.anchor_right = 1
	toolbar.offset_left = insets.x + 8
	toolbar.offset_right = -insets.z - 8
	toolbar.offset_top = -insets.w - 76
	toolbar.offset_bottom = -insets.w - 10
	for child in toolbar.get_children():
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		child.custom_minimum_size = Vector2(0, 64)
		child.add_theme_font_size_override("font_size", 13)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var box = theme.get_stylebox(state, "Button").duplicate()
			box.content_margin_left = 4
			box.content_margin_right = 4
			child.add_theme_stylebox_override(state, box)
	threat_panel.offset_left = -minf(360, size.x - insets.x - insets.z - 20) - insets.z - 10
	threat_panel.offset_right = -insets.z - 10
	threat_panel.offset_top = insets.y + 76
	threat_panel.offset_bottom = insets.y + 154
	var toast_width = minf(650, size.x - insets.x - insets.z - 20)
	toast.custom_minimum_size.x = maxf(0, toast_width - 36)
	toast.size.x = toast.custom_minimum_size.x
	toast_panel.offset_left = -toast_width / 2
	toast_panel.offset_right = toast_width / 2
	toast_panel.size.x = toast_width
	if is_instance_valid(zoom_controls):
		zoom_controls.position = Vector2(insets.x + 10, size.y - insets.w - 260)
		zoom_controls.size.x = 56
		zoom_controls.visible = page == "game" and not card.visible
	fps_panel.offset_right = -insets.z - 10
	fps_panel.offset_bottom = -insets.w - 90
	apply_card_layout()
	if is_instance_valid(menu_shell) and overlay.visible:
		menu_shell.offset_left = insets.x
		menu_shell.offset_top = insets.y
		menu_shell.offset_right = -insets.z
		menu_shell.offset_bottom = -insets.w

func apply_card_layout() -> void:
	if not mobile: return
	card.anchor_left = 0
	card.anchor_right = 1
	card.offset_left = insets.x + 10 if size.x < size.y else maxf(insets.x + 10, size.x - 410)
	card.offset_right = -insets.z - 10
	card.offset_top = maxf(insets.y + (166 if threat_panel.visible else 76), size.y * 0.28) if size.x < size.y else insets.y + 76
	card.offset_bottom = -insets.w - 86

func toast_rest_y() -> float:
	return insets.y + (166 if threat_panel.visible else 76) if mobile else 22.0

func adapt_inputs(parent: Variant) -> void:
	if not is_instance_valid(parent): return
	for node in parent.find_children("*", "Control", true, false):
		if node is Button or node is LineEdit:
			node.custom_minimum_size.y = maxf(56, node.custom_minimum_size.y)
			if node is Button: node.custom_minimum_size.x = maxf(56, node.custom_minimum_size.x)
			if node is OptionButton:
				node.fit_to_longest_item = false
				node.clip_text = true
				node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				node.get_popup().add_theme_constant_override("v_separation", 24)
				node.get_popup().add_theme_font_size_override("font_size", 18)
		elif node is HSlider: node.custom_minimum_size.y = maxf(48, node.custom_minimum_size.y)
		elif node is ScrollContainer: node.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

func apply_fullscreen(enabled: bool) -> void:
	if mobile: return
	var window = get_window()
	if enabled == (window.mode == Window.MODE_FULLSCREEN): return
	if enabled:
		windowed_mode = window.mode
		windowed_rect = Rect2i(window.position, window.size)
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		if windowed_rect.has_area():
			window.size = windowed_rect.size
			window.position = windowed_rect.position
		window.mode = windowed_mode

func set_fullscreen(enabled: bool) -> void:
	apply_fullscreen(enabled)
	save_display_option("borderless_fullscreen", enabled)

func set_map_view(enabled: bool) -> void:
	world.set_tilted(enabled)
	save_display_option("tilted_map", enabled)

func set_map_quality(enabled: bool) -> void:
	world.set_detailed_map(enabled)
	save_display_option("detailed_map", enabled)

func set_fps_counter(enabled: bool) -> void:
	show_fps = enabled
	update_performance_overlay()
	save_display_option("show_fps", enabled)

func save_display_option(key: String, enabled: bool) -> void:
	var config = ConfigFile.new()
	config.load(settings_path)
	config.set_value("display", key, enabled)
	var error = config.save(settings_path)
	if error != OK: message(L.text("Настройки"), L.text("Не удалось сохранить режим экрана: ") + error_string(error))

func restore_display_settings() -> void:
	var config = ConfigFile.new()
	if config.load(settings_path) != OK: return
	var enabled = config.get_value("display", "borderless_fullscreen", false)
	if enabled is bool: apply_fullscreen(enabled)
	var tilted = config.get_value("display", "tilted_map", false)
	var detailed = config.get_value("display", "detailed_map", false)
	if not mobile and detailed is bool: world.set_detailed_map(detailed)
	if tilted is bool: world.set_tilted(tilted)
	show_fps = config.get_value("display", "show_fps", false) == true
	update_performance_overlay()
	var master = config.get_value("audio", "master", 0.8)
	var effects = config.get_value("audio", "effects", 0.75)
	if not (master is float or master is int) or not is_finite(float(master)) or master < 0 or master > 1: master = 0.8
	if not (effects is float or effects is int) or not is_finite(float(effects)) or effects < 0 or effects > 1: effects = 0.75
	sound.set_mix(master, effects)

func show_new_game() -> void:
	page = "new"
	menu_frame(L.text("Новая кампания"), L.text("Выберите стартовую страну и цвет своей державы."), 560, 680)
	menu_body.add_child(label(L.text("СТАРТОВАЯ СТРАНА"), 11, MUTED))
	var filter_input = LineEdit.new()
	filter_input.placeholder_text = L.text("Найти страну…")
	menu_body.add_child(filter_input)
	country_picker = OptionButton.new()
	country_picker.custom_minimum_size.y = 44
	country_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	country_picker.item_selected.connect(func(_index): sound.play("select"))
	menu_body.add_child(country_picker)
	filter_input.text_changed.connect(fill_new_countries)
	fill_new_countries("")
	menu_body.add_child(label(L.text("ЦВЕТ ВАШИХ ТЕРРИТОРИЙ"), 11, MUTED))
	var palette = HFlowContainer.new() if mobile else HBoxContainer.new()
	palette.add_theme_constant_override("separation", 10)
	menu_body.add_child(palette)
	for code in ["69dfbd", "73aeef", "edc16e", "b697ef", "f291a1", "ed876a"]:
		var swatch = button("", func(): campaign_color = Color(code); color_picker.color = campaign_color)
		swatch.custom_minimum_size = Vector2(44, 42)
		swatch.tooltip_text = L.text("Цвет #%s") % code
		swatch.add_theme_stylebox_override("normal", style(Color(code)))
		palette.add_child(swatch)
	color_picker = ColorPickerButton.new()
	color_picker.color = campaign_color
	color_picker.edit_alpha = false
	color_picker.custom_minimum_size = Vector2(72, 42)
	color_picker.tooltip_text = L.text("Свой цвет")
	color_picker.color_changed.connect(func(color): campaign_color = color)
	palette.add_child(color_picker)
	if not Engine.get_meta("atlas_mods", "").is_empty():
		menu_body.add_child(paragraph(L.text("Стартовые ресурсы, гарнизоны и условия победы задаются правилами текущего набора модов.")))
	else:
		menu_body.add_child(paragraph(L.text("Во всех стартовых странах одинаковые минимальные войска и 180 монет. В каждой стране 1–5 предприятий. Нейтральные армии основаны на рейтинге GFP 2026.")))
	menu_body.add_child(paragraph(L.text("Пока у вас одна страна, нападения запрещены. После расширения ожидайте предупреждения за 1–5 игровых минут до возможной атаки.")))
	var start = button(L.text("Начать кампанию  →"), begin_campaign, true)
	menu_body.add_child(start)
	filter_input.text_changed.connect(func(_text): start.disabled = new_country_ids.is_empty())
	menu_body.add_child(button(L.text("Назад"), show_main_menu))

func fill_new_countries(query: String) -> void:
	country_picker.clear()
	new_country_ids.clear()
	for c in matching_countries(query):
		if int(c.id) in Simulation.MICROSTATES: continue
		country_picker.add_item(L.country(c))
		new_country_ids.append(int(c.id))
		if query.strip_edges().is_empty() and (int(c.id) == int(Simulation.Runtime.content().get("scenario", {}).get("default_home", -1)) or (not Simulation.Runtime.content().get("scenario", {}).has("default_home") and c.english == "Russia")):
			country_picker.select(new_country_ids.size() - 1)

func matching_countries(query: String) -> Array:
	var countries = game.atlas.filter(func(c): return game.country_visible(int(c.id)))
	countries.sort_custom(func(a, b): return L.country(a).naturalnocasecmp_to(L.country(b)) < 0)
	query = query.strip_edges()
	if query.is_empty(): return countries
	var names = PackedStringArray()
	for country in countries: names.append(country.name + " " + country.english)
	var fuzzy = FuzzySearch.new()
	fuzzy.max_results = countries.size()
	var matches: Array = []
	for result in fuzzy.search_all(query, names): matches.append(countries[result.original_index])
	return matches

func begin_campaign() -> void:
	if new_country_ids.is_empty():
		return
	var id = int(new_country_ids[country_picker.selected])
	sound.stop_gameplay()
	game.reset()
	game.player_color = campaign_color
	game.start(id)
	selected = id
	world.selected = -1
	world.reset_view()
	world.clear_motion()
	save_timer = 0
	ended_shown = false
	enter_game()
	autosave()
	announce(L.text("Кампания началась. Коснитесь страны для действий. Кнопка ☰ открывает меню.") if mobile else L.text("Кампания началась. Нажмите на страну для действий. Esc — пауза и статистика."))

func enter_game() -> void:
	page = "game"
	game.paused = false
	overlay.hide()
	hud.show()
	animate_page(hud)
	card.hide()
	card_view = ""
	refresh_hud()
	world.refresh_map()
	responsive_layout()
	if game.finished:
		sound.play("campaign_win" if game.owned_count() > 0 else "campaign_lose")
		show_pause()

func show_saves(origin: String = "menu") -> void:
	save_origin = origin
	page = "saves"
	game.paused = true
	menu_frame(L.text("Сохранения"), L.text("Автосохранения и ручные снимки всех ваших кампаний."), 760, 660)
	saves_list = store.list_saves()
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_body.add_child(scroll)
	var rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	if saves_list.is_empty():
		rows.add_child(paragraph(L.text("Сохранений пока нет. Создайте новую кампанию — первое автосохранение появится сразу.")))
	for entry in saves_list:
		var box = box_panel(rows)
		var row = VBoxContainer.new() if mobile else HBoxContainer.new()
		box.add_child(row)
		var description = VBoxContainer.new()
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(description)
		description.add_child(label(("●  " if entry.valid else "!  ") + entry.name, 18, entry.color if entry.valid else RED))
		var timestamp = Time.get_datetime_string_from_unix_time(entry.modified + 10800).replace("T", " ")
		description.add_child(label((L.text("Автосохранение") if entry.auto else L.text("Ручное сохранение")) + "  ·  " + timestamp + L.text(" МСК"), 11, MUTED))
		var load_button = button(L.text("Загрузить"), func(): load_campaign(entry.path), true)
		load_button.disabled = not entry.valid
		row.add_child(load_button)
		if entry.valid:
			box.add_child(label(L.text("%d стран  ·  %d монет  ·  %s в игре%s") % [entry.owned, entry.coins, time_text(entry.elapsed), L.text("  ·  Поражение") if entry.defeated else ""], 12, MUTED))
		else:
			box.add_child(paragraph(L.text("Файл несовместим или повреждён. Текущая кампания не изменится."), RED, 12))
	menu_body.add_child(button(L.text("Назад"), func(): show_pause() if save_origin == "pause" else show_main_menu()))

func load_campaign(path: String) -> void:
	if not game.load_game(path):
		sound.play("error")
		message(L.text("Ошибка загрузки"), L.text("Сохранение повреждено или несовместимо. Текущая кампания не изменена."))
		return
	sound.stop_gameplay()
	selected = game.home
	world.selected = -1
	world.clear_motion()
	world.reset_view()
	save_timer = 0
	ended_shown = false
	enter_game()
	announce(L.text("Кампания восстановлена. Операции на карте продолжаются с сохранённого момента."))

func show_pause() -> void:
	if game.home < 0:
		return
	if network.active:
		show_network_pause()
		return
	game.paused = true
	page = "pause"
	sound.sync()
	var heading = L.text("Кампания на паузе")
	if game.finished:
		heading = L.text("Мир объединён") if game.owned_count() > 0 else L.text("Кампания проиграна")
	menu_frame(heading, L.text("Время, доход, разведка, марши и вторжения остановлены."), 540, 780)
	info(menu_body, L.text("Держава"), L.country(game.atlas[game.home]), game.player_color)
	info(menu_body, L.text("Территории"), "%d / %d" % [game.owned_count(), game.countries.size()])
	info(menu_body, L.text("Казна / доход"), L.text("%d  /  +%d в сек") % [game.coins, game.income()], GOLD)
	info(menu_body, L.text("Время кампании"), time_text(game.elapsed))
	info(menu_body, L.text("Победы / поражения"), "%d / %d" % [game.victories, game.defeats])
	info(menu_body, L.text("Первичные захваты / ядерные удары"), "%d / %d" % [game.conquests.size(), game.nukes])
	for i in Simulation.UNIT_COUNT:
		info(menu_body, L.text(Simulation.UNIT_NAMES[i]), L.text("%d ед.  ·  ур. %d") % [game.units[i], game.levels[i]])
	if not game.finished:
		menu_body.add_child(button(L.text("Продолжить") if mobile else L.text("Продолжить  ·  Esc"), enter_game, true))
	menu_body.add_child(button(L.text("Сохранить отдельным снимком"), manual_save))
	menu_body.add_child(button(L.text("Открыть сохранения"), func(): show_saves("pause")))
	menu_body.add_child(button(L.text("Журнал событий"), show_journal))
	menu_body.add_child(button(L.text("Настройки"), func(): show_settings("pause")))
	menu_body.add_child(button(L.text("Главное меню"), func():
		if autosave(): show_main_menu()))
	autosave()

func show_journal() -> void:
	page = "journal"
	menu_frame(L.text("Журнал кампании"), L.text("Последние 40 событий. Игра остаётся на паузе."), 760, 660)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_body.add_child(scroll)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 14)
	scroll.add_child(rows)
	build_battle_reports(rows)
	for entry in game.events:
		rows.add_child(paragraph("%s  ·  %s" % [time_text(entry.time), L.render(entry.text)], INK))
	menu_body.add_child(button(L.text("Назад к паузе"), show_pause))

func select_country(id: int) -> void:
	if page != "game":
		return
	sound.play("select")
	selected = id
	world.selected = id
	if mobile and size.x < size.y:
		world.focus_country(id)
		world.pan.y += insets.y + 180 - world.screen_point(id).y
		world.clamp_pan()
	world.refresh_map()
	open_card("country")

func open_card(view: String) -> void:
	sound.play("open")
	card_view = view
	if view == "notifications":
		game.notifications_seen = game.notification_serial
		if network.active: network.request("read")
	card.show()
	refresh_card()
	responsive_layout()
	animate_page(card)

func refresh_card() -> void:
	if not card.visible:
		return
	clear_box(card_body)
	actionable.clear()
	var row = HBoxContainer.new()
	card_body.add_child(row)
	var title = {"army": L.text("Главный штаб"), "countries": L.text("Страны мира"), "arsenal": L.text("Ядерный арсенал"), "economy": L.text("Экономика"), "notifications": L.text("Уведомления")}.get(card_view, L.country(game.atlas[selected]) if selected >= 0 else L.text("Страна"))
	var heading = label(title, 22)
	heading.resize_font_to_fit = true
	heading.minimum_font_size = 16
	heading.maximum_font_size = 22
	heading.custom_minimum_size.y = 32
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.tooltip_text = title
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(heading)
	var close = button("×", close_card)
	if mobile: close.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(close)
	match card_view:
		"country": build_country()
		"economy": build_economy()
		"army":
			build_army()
			build_mod_panels()
		"countries": build_countries()
		"arsenal": build_arsenal()
		"notifications": build_notifications()
	refresh_hud()
	if mobile: call_deferred("adapt_inputs", card_body)

func action_button(parent: Node, text: String, action: Callable, enabled: Callable, accent: bool = false) -> void:
	var node = button(text, action, accent)
	parent.add_child(node)
	actionable.append({"button": node, "enabled": enabled})

func build_country() -> void:
	var c = game.countries[selected]
	var country = game.atlas[selected]
	var flag = Media.flag(selected)
	if flag != null:
		var image = TextureRect.new()
		image.texture = flag
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(96, 56)
		card_body.add_child(image)
	var sovereign = int(country.sovereign)
	if selected in game.wars and not c.owned:
		card_body.add_child(paragraph(L.text("⚔  В состоянии войны"), RED, 13))
	if game.rebel_country(selected):
		card_body.add_child(paragraph(L.text("Повстанцы: снижают оборону на 1–10%. Проверка возврата прежнему владельцу — каждые 2–7 минут."), GOLD, 12))
	var status = L.text("●  ЗАВИСИМАЯ ТЕРРИТОРИЯ") if sovereign != selected else "●  " + L.text("НЕЗАВИСИМАЯ СТРАНА")
	if game.country_owners.has(str(selected)): status = "●  " + str(game.country_owners[str(selected)])
	card_body.add_child(paragraph(L.text("●  ВАША ТЕРРИТОРИЯ") if c.owned else status, game.player_color if c.owned else GOLD, 11))
	if sovereign != selected:
		card_body.add_child(paragraph(L.text("Главная страна") + ": " + L.country(game.atlas[sovereign]), MINT, 12))
	if not country.dependencies.is_empty():
		card_body.add_child(paragraph(L.text("Зависимые территории") + ": " + ", ".join(country.dependencies.map(func(id): return L.country(game.atlas[int(id)]))), MUTED, 12))
	if c.owned:
		var revenue = 0
		for level in c.businesses: revenue += int(level)
		for item in Simulation.Runtime.content().get("buildings", []): revenue += int(item.income) * int(c.get("structures", {}).get(item.id, 0))
		info(card_body, L.text("Бизнесы"), str(c.businesses.size()))
		info(card_body, L.text("Доход страны"), L.text("+%d / сек") % revenue, MINT)
		card_body.add_child(button(L.text("Управлять бизнесами  →"), func(): open_card("economy"), true))
		card_body.add_child(button(L.text("Нанять и улучшить войска"), func(): open_card("army")))
		card_body.add_child(paragraph(L.text("Единственная страна защищена от нападений.") if game.owned_count() == 1 and not network.active else L.text("Вся держава защищается общей армией. Слабая оборона может привести к потере этой территории.")))
	else:
		info(card_body, L.text("Операция"), L.text("По суше") if game.border(selected) else L.text("Морской десант"))
		info(card_body, L.text("Цена наступления"), L.text("%d монет") % game.attack_cost(selected), GOLD)
		var report = game.reports.get(str(selected), {})
		if report.is_empty():
			card_body.add_child(paragraph(L.text("Силы противника неизвестны. Разведайте страну перед наступлением.")))
		else:
			card_body.add_child(label(L.text("РАЗВЕДДАННЫЕ  ·  ") + time_text(report.time), 11, MINT))
			for i in Simulation.UNIT_COUNT: info(card_body, L.text(Simulation.UNIT_NAMES[i]), str(int(report.units[i])))
			info(card_body, L.text("Сила по разведке"), str(int(game.power(report.units))), GOLD)
			card_body.add_child(paragraph(L.text("Снимок на момент отчёта. Противник может усиливаться."), MUTED, 11))
		info(card_body, L.text("Сила вашей операции"), str(int(game.power(game.units, game.levels) * (1.0 if game.border(selected) else Simulation.B.naval_multiplier))), MINT)
		action_button(card_body, L.text("◎  Отправить шпиона · %d") % Simulation.B.spy_cost, send_spy, func(): return game.can_act() and game.coins >= Simulation.B.spy_cost and game.mission.is_empty())
		action_button(card_body, L.text("⚑  Начать наступление"), confirm_attack, func(): return game.attack_block(selected) == "", true)
		if game.attack_block(selected) != "": card_body.add_child(paragraph(L.render(game.attack_block(selected)), RED, 12))
		action_button(card_body, L.text("☢  Ядерный удар · %d доступно") % game.nukes, confirm_nuke, func(): return game.can_act() and game.nukes > 0 and not game.has_operation("nuke"))
	if not game.mission.is_empty():
		card_body.add_child(paragraph(L.text("Агент → %s\nОтчёт через %d сек.") % [L.country(game.atlas[int(game.mission.target)]), maxi(0, int(game.mission.arrival) - game.elapsed)], Color("7ac5ef")))
	for op in game.operations:
		if op.kind == "enemy" and op.get("surprise", false): continue
		card_body.add_child(paragraph(L.text("%s → %s\nПрибытие через %d сек.") % [{"attack": L.text("Ваши войска"), "enemy": L.text("ВТОРЖЕНИЕ"), "nuke": L.text("Ядерная ракета")}[op.kind], L.country(game.atlas[int(op.target)]), maxi(0, int(op.arrival) - game.elapsed)], RED if op.kind == "enemy" else GOLD, 12))

func build_economy() -> void:
	var c = game.countries[selected]
	if not c.owned:
		card_body.add_child(paragraph(L.text("Страна больше не под вашим контролем. Захватите её, чтобы управлять предприятиями."), RED))
		return
	card_body.add_child(paragraph(L.country(game.atlas[selected]), game.player_color, 17))
	card_body.add_child(paragraph(L.text("Улучшение предприятия даёт +1 монету в секунду.")))
	for i in c.businesses.size():
		var box = box_panel(card_body)
		box.add_child(label(L.text(BUSINESS_NAMES[i]), 13))
		info(box, L.text("Уровень %d") % c.businesses[i], L.text("+%d / сек") % c.businesses[i], MINT)
		var cost = game.business_cost(selected, i)
		action_button(box, L.text("Улучшить · %d монет") % cost, func():
			if perform("business", [selected, i]):
				world.pulses.append({"kind": "victory", "target": selected, "age": 0.0})
				refresh_card(), func(): return game.can_act() and game.coins >= cost)

	build_mod_buildings()

func build_army() -> void:
	info(card_body, L.text("Боевая сила"), str(int(game.power(game.units, game.levels))), MINT)
	card_body.add_child(paragraph(L.text("Армия общая: технологии усиливают наступление и оборону. +%d%% базовой силы за уровень.") % roundi(Simulation.B.technology_bonus * 100)))
	for i in Simulation.UNIT_COUNT:
		var box = box_panel(card_body)
		info(box, L.text(Simulation.UNIT_NAMES[i]), L.text("%d ед. · ур. %d") % [game.units[i], game.levels[i]])
		action_button(box, L.text("+%d ед. · %d монет") % [int(Simulation.B.recruit_units[i]), Simulation.UNIT_COST[i]], func():
			if perform("recruit", [i]): refresh_card(), func(): return game.can_act() and game.coins >= Simulation.UNIT_COST[i] and Simulation.Runtime.unit_available(game, i), true)
		var cost = game.upgrade_cost(i)
		action_button(box, L.text("Технология · %d монет") % cost, func():
			if perform("upgrade", [i]): refresh_card(), func(): return game.can_act() and game.coins >= cost and Simulation.Runtime.unit_available(game, i))
	build_mod_research()
	card_body.add_child(paragraph(L.text("Сила единицы: пехота %d, авиация %d, флот %d. Десант требует %d кораблей и имеет штраф силы %d%%.") % [Simulation.B.unit_weight[0], Simulation.B.unit_weight[1], Simulation.B.unit_weight[2], Simulation.B.naval_ships, roundi((1.0 - Simulation.B.naval_multiplier) * 100)], MUTED, 12))

func build_countries() -> void:
	search = LineEdit.new()
	search.placeholder_text = L.text("Найти страну…")
	card_body.add_child(search)
	country_list = ItemList.new()
	country_list.custom_minimum_size = Vector2(270, 430)
	card_body.add_child(country_list)
	search.text_changed.connect(refresh_country_list)
	country_list.item_selected.connect(func(index):
		var id = int(list_ids[index])
		world.focus_country(id)
		select_country(id))
	refresh_country_list("")

func refresh_country_list(query: String) -> void:
	country_list.clear()
	list_ids.clear()
	for c in matching_countries(query):
		list_ids.append(int(c.id))
		country_list.add_item(("●  " if game.countries[int(c.id)].owned else ("↳  " if int(c.sovereign) != int(c.id) else "    ")) + L.country(c))
		if int(c.sovereign) != int(c.id):
			country_list.set_item_tooltip(list_ids.size() - 1, L.text("Главная страна") + ": " + L.country(game.atlas[int(c.sovereign)]))
		if game.countries[int(c.id)].owned:
			country_list.set_item_custom_fg_color(list_ids.size() - 1, game.player_color)

func build_arsenal() -> void:
	info(card_body, L.text("Доступно ударов"), str(game.nukes), GOLD)
	info(card_body, L.text("Впервые захвачено стран"), str(game.conquests.size()))
	var remaining = Simulation.NUCLEAR_THRESHOLD - game.conquests.size() % Simulation.NUCLEAR_THRESHOLD
	card_body.add_child(paragraph(L.text("Следующий заряд через %d новых захватов. Один заряд за каждые %d впервые захваченных стран.") % [remaining, Simulation.NUCLEAR_THRESHOLD]))
	card_body.add_child(paragraph(L.text("Выберите чужую страну на карте и нажмите «Ядерный удар». Ракета летит %d секунд, затем сокращает каждый род войск на 50%%. Остаток округляется вниз.") % Simulation.B.nuke_seconds, INK))
	card_body.add_child(paragraph(L.text("Удар не захватывает территорию. Повторный захват уже завоёванной страны не даёт прогресса к следующему заряду.")))
	if selected >= 0 and not game.countries[selected].owned:
		card_body.add_child(paragraph(L.text("Текущая цель: ") + L.country(game.atlas[selected]), GOLD))
		action_button(card_body, L.text("☢  Нанести удар"), confirm_nuke, func(): return game.can_act() and game.nukes > 0 and not game.has_operation("nuke"), true)

func build_notifications() -> void:
	game.notifications_seen = game.notification_serial
	card_body.add_child(paragraph(L.text("Сведения о возможных атаках не подтверждены: вторжение может не состояться. Таймер показывает ожидаемый срок выступления.")))
	if game.owned_count() == 1 and not network.active:
		card_body.add_child(paragraph(L.text("Защита последней страны: никто не может на вас напасть."), MINT))
	for warning in game.warnings:
		var box = box_panel(card_body)
		box.add_child(paragraph(L.render(game.warning_description(warning)), GOLD))
		var state = {"pending": L.text("Возможная атака"), "cancelled": L.text("Угроза снята / слух не подтвердился"), "launched": L.text("Наступление началось")}[warning.status]
		box.add_child(paragraph(state, GOLD if warning.status == "pending" else MUTED, 12))
		info(box, L.text("Сообщение получено"), time_text(int(warning.issued)))
		if warning.status == "pending":
			info(box, L.text("Ожидаемый срок"), time_text(int(warning.deadline)), GOLD)
		box.add_child(paragraph(L.text("Оценка силы приблизительная. Разведка раскрывает название страны."), MUTED, 11))
	build_battle_reports(card_body)
	card_body.add_child(label(L.text("ПОСЛЕДНИЕ СОБЫТИЯ"), 11, MUTED))
	for entry in game.events:
		card_body.add_child(paragraph("%s · %s" % [time_text(entry.time), L.render(entry.text)], INK, 12))

func build_battle_reports(parent: VBoxContainer) -> void:
	for battle in game.battles:
		var box = box_panel(parent)
		box.add_child(paragraph(L.text("Бой за %s · %s") % [L.country(game.atlas[int(battle.target)]), time_text(int(battle.time))], GOLD))
		box.add_child(paragraph(L.text("Победа") if battle.won else L.text("Поражение"), MINT if battle.won else INK))
		box.add_child(paragraph(L.text("Вы наступали") if battle.attacking else L.text("Вы оборонялись")))
		info(box, L.text("Сила атаки / обороны"), "%.1f / %.1f" % [battle.effective, battle.defense])
		info(box, L.text("Сила без технологий"), "%.1f / %.1f" % [game.power(battle.attackers), game.power(battle.defenders)])
		info(box, L.text("Сила с технологиями"), "%.1f / %.1f" % [game.power(battle.attackers, battle.attack_levels), game.power(battle.defenders, battle.defense_levels)])
		info(box, L.text("Морской штраф"), "%d%%" % roundi((1.0 - Simulation.B.naval_multiplier) * 100) if battle.overseas else "0%")
		info(box, L.text("Помощь повстанцев: снижение обороны"), "%d%%" % battle.rebels)
		box.add_child(paragraph(L.text("Потери: пехота / авиация / флот")))
		info(box, L.text("Наступающие"), "%d / %d / %d" % battle.attack_losses)
		info(box, L.text("Обороняющиеся"), "%d / %d / %d" % battle.defense_losses)
		box.add_child(paragraph(L.text("Сравнивается итоговая сила на момент прибытия армии."), MUTED, 11))

func send_spy() -> void:
	if perform("spy", [selected]):
		autosave()
		refresh_card()
		announce(L.text("Агент на пути к цели. Следите за голубым маркером на карте."))

func confirm_attack() -> void:
	var id = selected
	confirm_action(L.text("Начать наступление?"), L.text("Цель: %s\nСтоимость: %d монет. Марш — %d секунд.\nАрмия понесёт потери даже при победе. Бой рассчитывается по силам на момент прибытия.") % [L.country(game.atlas[id]), game.attack_cost(id), Simulation.B.attack_seconds], func():
		if perform("attack", [id]):
			autosave()
			refresh_card()
			announce(L.text("Войска выдвинулись к %s.") % L.country(game.atlas[id])))

func confirm_nuke() -> void:
	var id = selected
	confirm_action(L.text("Нанести ядерный удар?"), L.text("Цель: %s\nБудет потрачен 1 ядерный удар. Через %d секунд каждый род войск цели потеряет 50%% состава. Территория не захватывается.") % [L.country(game.atlas[id]), Simulation.B.nuke_seconds], func():
		if perform("nuke", [id]):
			autosave()
			refresh_card()
			refresh_hud())

func confirm_action(title: String, text: String, action: Callable) -> void:
	if mobile:
		show_mobile_dialog(title, text, action, true)
		return
	var dialog = ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(480, 200)
	dialog.ok_button_text = L.text("Подтвердить")
	dialog.cancel_button_text = L.text("Отмена")
	add_child(dialog)
	dialog.confirmed.connect(action)
	dialog.confirmed.connect(func(): sound.play("confirm"))
	dialog.canceled.connect(func(): sound.play("cancel"))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func message(title: String, text: String) -> void:
	if mobile:
		show_mobile_dialog(title, L.render(text), func(): pass, false)
		return
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = L.render(text)
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(450, 160)
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func show_mobile_dialog(title: String, text: String, action: Callable, confirmation: bool) -> void:
	if is_instance_valid(mobile_modal): mobile_modal.queue_free()
	var layer = ColorRect.new()
	layer.color = Color(0, 0, 0, 0.75)
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mobile_modal = layer
	var center = CenterContainer.new()
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel = PanelContainer.new()
	panel.custom_minimum_size.x = minf(480, size.x - 32)
	panel.add_theme_stylebox_override("panel", style(Color("172f4f"), MINT, 12))
	center.add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(448, size.x - 64), minf(340, size.y - 96))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	center.resized.connect(func():
		panel.custom_minimum_size.x = minf(480, size.x - 32)
		scroll.custom_minimum_size = Vector2(minf(448, size.x - 64), minf(340, size.y - 96)))
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	body.add_child(paragraph(title, GOLD, 18))
	body.add_child(paragraph(text, INK, 14))
	body.add_child(button(L.text("Подтвердить") if confirmation else "OK", func():
		layer.queue_free()
		sound.play("confirm")
		action.call(), true))
	if confirmation: body.add_child(button(L.text("Отмена"), func(): layer.queue_free(); sound.play("cancel")))

func refresh_hud() -> void:
	balance.text = "◈ %s" % format_number(int(game.coins))
	income_label.text = L.text("+%s / сек") % format_number(game.income())
	arsenal_button.text = L.text("☢  Арсенал · %d") % game.nukes
	var unread = mini(40, game.notification_serial - game.notifications_seen)
	notifications_button.text = L.text("◉  Уведомления") + (" · %d" % unread if unread > 0 else "")
	if mobile:
		arsenal_button.text = L.text("☢\nУдары · %d") % game.nukes
		notifications_button.text = L.text("◉\nСобытия") + (" · %d" % mini(9, unread) if unread > 0 else "")
	var warning = game.pending_warning()
	threat_panel.visible = not warning.is_empty()
	if mobile: apply_card_layout()
	else: card.offset_top = 178 if threat_panel.visible else 86
	if not warning.is_empty():
		threat_timer.text = L.text("Возможная атака · ") + time_text(maxi(0, int(warning.deadline) - game.elapsed))
		threat_identity.text = L.render(game.warning_description(warning))
		threat_identity.tooltip_text = threat_identity.text
	for entry in actionable:
		if is_instance_valid(entry.button): entry.button.disabled = not entry.enabled.call()

func announce(text: String) -> void:
	if is_instance_valid(toast_tween): toast_tween.kill()
	toast.text = L.render(text)
	toast_panel.size.y = maxf(62, toast.get_combined_minimum_size().y + 24)
	toast_panel.modulate.a = 0
	var rest = toast_rest_y()
	toast_panel.position.y = rest - 16
	toast_panel.show()
	sound.play("notification")
	toast_tween = create_tween()
	toast_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.25)
	toast_tween.parallel().tween_property(toast_panel, "position:y", rest, 0.25)
	toast_tween.tween_interval(7.4)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.35)
	toast_tween.parallel().tween_property(toast_panel, "position:y", rest - 16, 0.35)
	toast_tween.tween_callback(func(): toast_panel.hide(); toast_tween = null)

func _process(_delta: float) -> void:
	if mobile and is_instance_valid(zoom_controls): zoom_controls.visible = page == "game" and not card.visible
	if mobile and is_instance_valid(toast_panel) and toast_panel.visible:
		toast_panel.size.y = maxf(62, toast.get_minimum_size().y + 24)
	if is_instance_valid(toast_tween) and toast_tween.is_valid():
		if page == "game" and not game.paused: toast_tween.play()
		else: toast_tween.pause()

func on_second() -> void:
	update_performance_overlay()
	if network.active: return
	var changed = game.tick()
	refresh_hud()
	if changed:
		world.sync_ownership()
		world.refresh_map()
		if card_view != "countries": refresh_card()
		if not game.events.is_empty() and game.events[0].text != last_event:
			last_event = game.events[0].text
			announce(last_event)
		autosave()
	if not game.mission.is_empty() or not game.operations.is_empty():
		if card_view == "country": refresh_card()
	if game.can_act():
		save_timer += 1
		if save_timer >= 15:
			autosave()
			save_timer = 0
	if game.finished and not ended_shown and page == "game":
		ended_shown = true
		show_pause()

func autosave() -> bool:
	if is_instance_valid(network) and network.active:
		if not network.hosting: return true
		var result = network.save_match()
		if result != OK: message(L.text("Ошибка сохранения сетевой партии"), error_string(result))
		return result == OK
	if game.home < 0: return true
	var error = store.autosave(game)
	if error != OK:
		sound.play("error")
		announce(L.text("Ошибка автосохранения: ") + error_string(error))
		if page != "game": message(L.text("Ошибка автосохранения"), error_string(error))
		return false
	return true

func manual_save() -> void:
	var error = store.manual_save(game)
	sound.play("save" if error == OK else "error")
	message(L.text("Сохранение"), L.text("Создан отдельный снимок кампании. Он доступен в списке сохранений.") if error == OK else L.text("Не удалось записать файл: ") + error_string(error))

func perform(action: String, args: Array) -> bool:
	if network.active: return network.request(action, args)
	match action:
		"construct": return Simulation.Runtime.construct(game, args[0], args[1])
		"research": return Simulation.Runtime.research(game, args[0])
		"recruit": return game.recruit(args[0])
		"upgrade": return game.upgrade_army(args[0])
		"business": return game.upgrade_business(args[0], args[1])
		"spy": return game.spy(args[0])
		"attack": return game.dispatch_attack(args[0])
		"nuke": return game.nuclear_strike(args[0])
	return false

func receive_network_view(data: Dictionary) -> void:
	if not network.active or network.stage != "game": return
	if not data.get("colors") is Dictionary or not data.get("names") is Dictionary or not data.get("remote") is Array or not data.get("sounds") is Array or not data.get("effects") is Array: return
	if data.colors.size() > Simulation.COUNTRY_COUNT or data.names.size() > Simulation.COUNTRY_COUNT or data.remote.size() > Simulation.COUNTRY_COUNT * 2 or data.sounds.size() > 40 or data.effects.size() > 40: return
	for key in data.colors:
		if not key is String or not key.is_valid_int() or int(key) < 0 or int(key) >= Simulation.COUNTRY_COUNT or not data.colors[key] in network.COLORS: return
	for key in data.names:
		if not key is String or not key.is_valid_int() or int(key) < 0 or int(key) >= Simulation.COUNTRY_COUNT or not data.names[key] is String or data.names[key].length() > 24: return
	for op in data.remote:
		if not op is Dictionary or not op.get("kind") in ["enemy", "nuke"] or not game.valid_numbers([op.get("from"), op.get("target"), op.get("start"), op.get("arrival")], 4): return
		if op.from >= Simulation.COUNTRY_COUNT or op.target >= Simulation.COUNTRY_COUNT or op.arrival <= op.start or not op.get("source_color") in network.COLORS or not op.get("overseas", false) is bool: return
	for effect in data.effects:
		if not effect is Dictionary or not effect.get("kind") in ["victory", "defeat", "nuke"] or not game.valid_numbers([effect.get("target")], 1) or effect.target >= Simulation.COUNTRY_COUNT: return
	if not game.restore_data(data.get("game"), false):
		network.shutdown(L.text("Получено несовместимое состояние партии."))
		return
	game.network_game = true
	game.country_colors = data.colors
	game.country_owners = data.names
	game.remote_operations = data.remote
	game.effects = data.effects
	if page in ["lobby", "online", "connecting"]:
		world.clear_motion()
		enter_game()
	world.sync_ownership()
	game.paused = page != "game"
	for cue in data.sounds:
		if cue is String and sound.streams.has(cue): sound.play(cue)
	world.refresh_map()
	refresh_hud()
	if card_view != "countries": refresh_card()
	if not game.events.is_empty() and game.events[0].text != last_event:
		last_event = game.events[0].text
		announce(last_event)

func show_network_pause() -> void:
	page = "pause"
	game.paused = true
	menu_frame(L.text("Сетевая партия"), L.text("Матч продолжается. Для общей паузы вернитесь в лобби."), 600, 680)
	info(menu_body, L.text("Игрок"), network.players[network.my_slot].name, game.player_color)
	info(menu_body, L.text("Территории"), str(game.owned_count()))
	info(menu_body, L.text("Казна / доход"), L.text("%d / +%d в сек") % [game.coins, game.income()], GOLD)
	info(menu_body, L.text("Время матча"), time_text(game.elapsed))
	for i in Simulation.UNIT_COUNT: info(menu_body, L.text(Simulation.UNIT_NAMES[i]), L.text("%d · ур. %d") % [game.units[i], game.levels[i]])
	menu_body.add_child(button(L.text("Вернуться к карте"), enter_game, true))
	menu_body.add_child(button(L.text("Вернуться всем в лобби · пауза"), func(): network.request("lobby")))
	if network.hosting:
		menu_body.add_child(button(L.text("Сохранить сетевую партию"), func():
			if autosave(): message(L.text("Сохранено"), L.text("Открывайте эту партию в разделе «Сетевая игра»; участники смогут вернуться."))))
	menu_body.add_child(button(L.text("Настройки"), func(): show_settings("pause")))
	menu_body.add_child(button(L.text("Покинуть матч"), leave_network))

func leave_network() -> void:
	confirm_action(L.text("Покинуть сетевую игру?"), L.text("Партия сохранится. Участники смогут продолжить после повторного подключения и готовности всех игроков."), func():
		if network.directory_client: network.directory_request("leave")
		elif autosave(): network.shutdown(""))

func request_exit() -> void:
	if not autosave():
		confirm_action(L.text("Не удалось сохранить"), L.text("Ошибка записи. Выйти без сохранения?"), func(): get_tree().quit())
		return
	get_tree().quit()

func find_country(english: String) -> int:
	for c in game.atlas:
		if c.english == english: return int(c.id)
	return 0

func time_text(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]

func format_number(value: int) -> String:
	if value >= 1000000: return "%.1fM" % (value / 1000000.0)
	if value >= 10000: return "%.1fK" % (value / 1000.0)
	return str(value)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE or (event.keycode == KEY_SPACE and page in ["game", "pause"] and not get_viewport().gui_get_focus_owner() is LineEdit):
		sound.play("open" if page == "game" else "cancel")
		match page:
			"game": show_pause()
			"pause":
				if not game.finished: enter_game()
			"journal": show_pause()
			"saves": show_pause() if save_origin == "pause" else show_main_menu()
			"new", "mods", "mod_tools": show_main_menu()
			"settings": close_settings()
			"mods_download": network.shutdown("")
			"online":
				if network.active: network.shutdown("")
				else:
					network.stop_scan()
					show_main_menu()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: request_exit()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and mobile: mobile_back()
	if what == NOTIFICATION_APPLICATION_PAUSED and mobile and is_instance_valid(sound):
		if is_instance_valid(network) and network.active: network.request("lobby")
		elif game.home >= 0:
			autosave()
			if page == "game": show_pause()
		game.paused = true
		sound.sync()

func mobile_back() -> void:
	if is_instance_valid(mobile_modal) and not mobile_modal.is_queued_for_deletion():
		mobile_modal.queue_free()
		sound.play("cancel")
		return
	if OS.has_feature("android") and DisplayServer.virtual_keyboard_get_height() > 0:
		DisplayServer.virtual_keyboard_hide()
		return
	for child in get_children():
		if child is AcceptDialog and child.visible:
			child.canceled.emit()
			child.hide()
			return
	if card.visible:
		close_card()
		return
	match page:
		"game": show_pause()
		"pause":
			if not game.finished: enter_game()
		"settings": close_settings()
		"journal": show_pause()
		"new", "mods", "mod_tools": show_main_menu()
		"saves": show_pause() if save_origin == "pause" else show_main_menu()
		"online", "connecting", "mods_download":
			if network.active: network.shutdown("")
			else: network.stop_scan(); show_main_menu()
		"lobby": leave_network()
		"menu": request_exit()

func close_card() -> void:
	card.hide()
	card_view = ""
	if mobile and selected >= 0: world.focus_country(selected)
	world.selected = -1
	world.refresh_map()

func build_mod_buildings() -> void:
	var definitions = Simulation.Runtime.content().get("buildings", [])
	for i in definitions.size():
		var item = definitions[i]
		var level = int(game.countries[selected].get("structures", {}).get(item.id, 0))
		var box = box_panel(card_body)
		info(box, L.render(item.name), "%d · +%d/s" % [level, level * int(item.income)])
		var cost = int(item.cost) * (level + 1)
		action_button(box, L.text("Построить · %d монет") % cost, func():
			if perform("construct", [selected, i]): refresh_card(), func(): return game.can_act() and game.coins >= cost and Simulation.Runtime.requirements(game, item.get("requires", [])))

func build_mod_research() -> void:
	var definitions = Simulation.Runtime.content().get("technologies", [])
	for i in definitions.size():
		var item = definitions[i]
		var box = box_panel(card_body)
		info(box, L.render(item.name), "✓" if item.id in game.mod_state.get("researches", []) else str(int(item.cost)))
		action_button(box, L.text("Исследовать · %d монет") % int(item.cost), func():
			if perform("research", [i]): refresh_card(), func(): return game.can_act() and game.coins >= item.cost and not item.id in game.mod_state.get("researches", []) and Simulation.Runtime.requirements(game, item.get("requires", [])))

func build_mod_panels() -> void:
	for panel in Simulation.Runtime.content().get("panels", []):
		var box = box_panel(card_body)
		box.add_child(label(L.render(panel.title), 16, MINT))
		box.add_child(paragraph(L.render(panel.get("text", ""))))
		var action = str(panel.get("action", ""))
		if not action.is_empty(): box.add_child(button(L.text("Открыть"), func(): open_card(action)))
