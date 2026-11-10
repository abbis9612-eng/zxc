## أعلام الدول (مكتبة flag-icons، ترخيص MIT). الرمز من حقل flag في data/countries.json.
extends RefCounted

static var _cache := {}


static func tex(code: String) -> Texture2D:
	if code == "":
		return null
	if _cache.has(code):
		return _cache[code]
	var path := "res://assets/flags/%s.svg" % code
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if t != null:
		# إطار رفيع حول العلم حتى لا تذوب الأعلام البيضاء (مثل اليابان) في الخلفية الفاتحة
		var img := t.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var w := img.get_width()
			var h := img.get_height()
			var edge := Color(0.1, 0.15, 0.2, 0.35)
			for x in w:
				img.set_pixel(x, 0, edge)
				img.set_pixel(x, h - 1, edge)
			for y in h:
				img.set_pixel(0, y, edge)
				img.set_pixel(w - 1, y, edge)
			t = ImageTexture.create_from_image(img)
	_cache[code] = t
	return t


## صورة علم بإطار رفيع، بعرض معيّن ونسبة 4:3
static func rect(code: String, width: int = 28) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(code)
	r.custom_minimum_size = Vector2(width, roundf(width * 0.75))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r
