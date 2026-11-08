extends RefCounted

static var textures: Dictionary = {}

static func color(key: String, fallback: Color) -> Color:
	return Color(Engine.get_meta("atlas_content", {}).get("theme", {}).get(key, fallback.to_html()))

static func flag(country: int) -> Texture2D:
	if textures.has(country): return textures[country]
	var item = Engine.get_meta("atlas_content", {}).get("assets", {}).get("flag:" + str(country), {})
	if item.is_empty(): return null
	var image = Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(item.data)) != OK: return null
	if image.get_width() > 1024 or image.get_height() > 1024: return null
	textures[country] = ImageTexture.create_from_image(image)
	return textures[country]

static func sound(cue: String) -> AudioStream:
	var item = Engine.get_meta("atlas_content", {}).get("assets", {}).get("sound:" + cue, {})
	return null if item.is_empty() else AudioStreamWAV.load_from_buffer(Marshalls.base64_to_raw(item.data))
