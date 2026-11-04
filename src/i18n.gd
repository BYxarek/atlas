extends RefCounted

static var language = "ru"
static var catalog: Dictionary = {}
static var countries: Dictionary = {}
static var patterns: Array = []
static var loaded = false

static func load_catalog() -> void:
	if loaded: return
	loaded = true
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/i18n/en.json"))
	var translation = Translation.new()
	translation.locale = "en"
	var russian = Translation.new()
	russian.locale = "ru"
	for key in catalog:
		translation.add_message(key, catalog[key])
		russian.add_message(key, key)
		if not "%" in key or (key.length() < 12 and not key.begins_with("Бот ")): continue
		var regex = RegEx.new()
		var placeholders = RegEx.new()
		placeholders.compile("%(?:0?[0-9]+)?[dsf]|%%")
		var expression = "^"
		var previous = 0
		var fields = 0
		for item in placeholders.search_all(key):
			expression += escape_regex(key.substr(previous, item.get_start() - previous))
			if item.get_string() == "%%": expression += "%"
			else:
				expression += "([\\s\\S]+?)" if item.get_string().ends_with("s") else "([0-9]+(?:\\.[0-9]+)?)"
				fields += 1
			previous = item.get_end()
		expression += escape_regex(key.substr(previous)) + "$"
		if fields > 0 and regex.compile(expression) == OK: patterns.append({"regex": regex, "key": key})
	patterns.sort_custom(func(a, b): return a.key.length() > b.key.length())
	TranslationServer.add_translation(translation)
	TranslationServer.add_translation(russian)
	var atlas = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world.json"))
	for c in atlas: countries[c.name] = c.english

static func escape_regex(value: String) -> String:
	var result = ""
	for character in value:
		if character in "\\.^$|?*+()[]{}": result += "\\"
		result += character
	return result

static func setup(path: String) -> void:
	var config = ConfigFile.new()
	config.load(path)
	var preferred = config.get_value("interface", "language", OS.get_locale_language())
	set_language("ru" if str(preferred).begins_with("ru") else "en")

static func set_language(value: String) -> void:
	load_catalog()
	language = value if value in ["ru", "en"] else "en"
	TranslationServer.set_locale(language)

static func text(value: String) -> String:
	if language != "en": return value
	load_catalog()
	return str(TranslationServer.translate(value))

static func country(value: Dictionary) -> String:
	return str(value.english if language == "en" else value.name)

static func render(value: String, depth: int = 0) -> String:
	if language != "en": return value
	load_catalog()
	if catalog.has(value): return catalog[value]
	if countries.has(value): return countries[value]
	if depth > 3: return value
	for key in catalog:
		if key.ends_with(": ") and value.begins_with(key): return catalog[key] + render(value.substr(key.length()), depth + 1)
	for entry in patterns:
		var match_text = entry.regex.search(value)
		if match_text == null: continue
		var template = str(catalog[entry.key])
		var fields = RegEx.new()
		fields.compile("%(?:0?[0-9]+)?[dsf]|%%")
		var result = ""
		var previous = 0
		var index = 1
		for field in fields.search_all(template):
			result += template.substr(previous, field.get_start() - previous)
			if field.get_string() == "%%": result += "%"
			else:
				result += render(match_text.get_string(index), depth + 1)
				index += 1
			previous = field.get_end()
		return result + template.substr(previous)
	return value
