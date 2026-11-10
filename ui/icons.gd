## مكتبة أيقونات متجهة خاصة باللعبة: رسوم SVG بسيطة (شبكة 24×24، خط 2) تتحول إلى صور
## حادة بأي مقاس وبأي لون. كل الأيقونات مرسومة لهذا المشروع، لا مأخوذة من مكتبات أخرى.
extends RefCounted

const S := 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'

const PATHS := {
	# التبويبات
	"state": '<path d="M3 21h18M5 21v-9M9.5 21v-9M14.5 21v-9M19 21v-9M2.5 10 12 4l9.5 6z"/>',
	"economy": '<path d="M3 20h18M5 16l4.5-5 4 3L19 7"/><path d="M15 7h4v4"/>',
	"army": '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M8 10l4 3 4-3M8 14l4 3 4-3"/>',
	"research": '<path d="M9 3h6M10 3v6l-5 9a2 2 0 0 0 1.8 3h10.4a2 2 0 0 0 1.8-3l-5-9V3M7.3 15h9.4"/>',
	"diplomacy": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3.2 3 3.2 15 0 18M12 3c-3.2 3-3.2 15 0 18"/>',
	"intel": '<path d="M2 12s3.8-7 10-7 10 7 10 7-3.8 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
	"news": '<path d="M4 5h12v14H6a2 2 0 0 1-2-2zM16 9h3a1 1 0 0 1 1 1v7a2 2 0 0 1-2 2h-2M7 9h6M7 12.5h6M7 16h4"/>',
	# الشريط العلوي والعناصر العامة
	"calendar": '<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
	"treasury": '<ellipse cx="12" cy="6.5" rx="7" ry="2.5"/><path d="M5 6.5v5c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5v-5M5 11.5v5c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5v-5"/>',
	"stability": '<path d="M12 4v16M7 20h10M5 8h14M5 8l-2.5 6a2.5 2.5 0 0 0 5 0zM19 8l-2.5 6a2.5 2.5 0 0 0 5 0z"/>',
	"growth": '<path d="M3 17l6-6 4 4 8-8M15 7h6v6"/>',
	"decline": '<path d="M3 7l6 6 4-4 8 8M15 17h6v-6"/>',
	"war": '<path d="M4 4l11 11M4 4h4M4 4v4M20 4L9 15M20 4h-4M20 4v4M13 17l4 4M11 17l-4 4M7.5 13.5 10.5 16.5M16.5 13.5l-3 3"/>',
	"peace": '<path d="M7 11V6.5a1.5 1.5 0 0 1 3 0V11M10 10V5a1.5 1.5 0 0 1 3 0v5M13 10V6a1.5 1.5 0 0 1 3 0v6M16 9.5a1.5 1.5 0 0 1 3 0V14a7 7 0 0 1-7 7h-.5a6.5 6.5 0 0 1-5.5-3L4 14.5a1.5 1.5 0 0 1 2.4-1.8L7 13.5V11"/>',
	"nuke": '<circle cx="12" cy="12" r="2" fill="currentColor" stroke="none"/><path fill="currentColor" stroke="none" d="M12 12 7.6 4.4A9 9 0 0 1 16.4 4.4zM12 12l8.8 0a9 9 0 0 1-4.4 7.6zM12 12l-4.4 7.6A9 9 0 0 1 3.2 12z"/>',
	"warning": '<path d="M12 3 2 20h20zM12 9v5M12 17h.01"/>',
	"info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5h.01"/>',
	"check": '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
	"play": '<path fill="currentColor" d="M7 4.5v15l12-7.5z"/>',
	"pause": '<path d="M8.5 5v14M15.5 5v14" stroke-width="3"/>',
	"step": '<path fill="currentColor" d="M5 5v14l9-7z"/><path d="M18 5v14" stroke-width="3"/>',
	"save": '<path d="M5 3h11l4 4v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a1 1 0 0 1 1-1z"/><path d="M8 3v5h7V3M8 21v-6h8v6"/>',
	"sun": '<circle cx="12" cy="12" r="4.5"/><path d="M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.9 4.9l1.8 1.8M17.3 17.3l1.8 1.8M4.9 19.1l1.8-1.8M17.3 6.7l1.8-1.8"/>',
	"moon": '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z"/>',
	"chevron": '<path d="M9 6l6 6-6 6"/>',
	"legend": '<rect x="4" y="5" width="4" height="4" rx="1"/><rect x="4" y="15" width="4" height="4" rx="1"/><path d="M11 7h9M11 17h9"/>',
	"menu": '<path d="M4 7h16M4 12h16M4 17h16"/>',
	"close": '<path d="M6 6l12 12M18 6L6 18"/>',
	"target": '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 1v5M12 18v5M1 12h5M18 12h5"/>',
	"radar": '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><path d="M12 12l6.4-6.4"/><circle cx="16" cy="9" r="1" fill="currentColor"/>',
	"advisor": '<path d="M4 9l8-5 8 5-8 5z"/><path d="M7 11v5c0 1.5 2.2 3 5 3s5-1.5 5-3v-5M20 9v6"/>',
	"region": '<path d="M12 21s-7-6.2-7-11.5a7 7 0 0 1 14 0C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
	"capital": '<path fill="currentColor" stroke="none" d="M12 2.5l2.7 6.1 6.6.6-5 4.4 1.5 6.5L12 16.7l-5.8 3.4 1.5-6.5-5-4.4 6.6-.6z"/>',
	"unit": '<rect x="2.5" y="14" width="19" height="6" rx="3"/><path d="M5.5 14l1.5-4h9l1.5 4"/><path d="M14 11.5l7.5-2.5"/>',
	"bell": '<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 20a2 2 0 0 0 4 0"/>',
	"fast": '<path d="M4 6l7 6-7 6M13 6l7 6-7 6"/>',
	"details": '<path d="M15 6l-6 6 6 6"/>',
	"ship": '<path d="M2.5 15.5h19l-2.5 4.5H5z"/><path d="M6 15.5v-4h11v4M10 11.5V7h4v4.5M12 7V4"/>',
	"up": '<path d="M6 15l6-6 6 6"/>',
	"down": '<path d="M6 9l6 6 6-6"/>',
	"move": '<path d="M4 12h15M14 6l6 6-6 6"/>',
	"layers": '<path d="M12 3 2 8l10 5 10-5zM2 13l10 5 10-5M2 17.5l10 5 10-5"/>',
	"range": '<circle cx="12" cy="12" r="9" stroke-dasharray="3 3"/><circle cx="12" cy="12" r="4"/><circle cx="12" cy="12" r="1" fill="currentColor"/>',
	"people": '<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.6 2.7-6 6-6s6 2.4 6 6"/><circle cx="17" cy="9" r="2.5"/><path d="M16.5 14.2c2.6.3 4.5 2.4 4.5 5.8"/>',
	"trade": '<path d="M4 8h13l-3-3M20 16H7l3 3"/>',
	"market": '<path d="M4 20V10M9 20V4M14 20v-7M19 20V8"/>',
	"alliance": '<path d="M12 3l7 3v5c0 4.5-3 7.6-7 9-4-1.4-7-4.5-7-9V6z"/><path d="M9 12l2 2 4-4"/>',
	"sanction": '<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/>',
	"invest": '<path d="M12 3v18M16.5 7.5c0-1.7-2-3-4.5-3s-4.5 1.3-4.5 3 2 2.6 4.5 3.2 4.5 1.6 4.5 3.3-2 3-4.5 3-4.5-1.3-4.5-3"/>',
	"handshake": '<path d="M3 12l4-4 4 2 3-2 7 4M14 8l-4 4 2 2 3-2 2 2 3-2M7 14l3 3M3 12l5 5"/>',
	# الفئات
	"f_military": '<path d="M12 3l2.4 4.9 5.4.8-3.9 3.8.9 5.4L12 15.3l-4.8 2.6.9-5.4L4.2 8.7l5.4-.8z"/><path d="M8 21h8"/>',
	"f_business": '<rect x="3" y="7.5" width="18" height="12" rx="2"/><path d="M9 7.5V5.5a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 5.5v2M3 13h18"/>',
	"f_street": '<circle cx="12" cy="7" r="3"/><path d="M6 21v-2a6 6 0 0 1 12 0v2M2.5 21v-1.5a4 4 0 0 1 3.2-3.9M21.5 21v-1.5a4 4 0 0 0-3.2-3.9"/>',
	"f_clergy": '<path d="M4 5.5C6.5 4.2 9.5 4.2 12 5.8c2.5-1.6 5.5-1.6 8-.3V19c-2.5-1.3-5.5-1.3-8 .3-2.5-1.6-5.5-1.6-8-.3zM12 5.8v13.5"/>',
	# الموارد
	"r_oil": '<path d="M12 3s6 7 6 11a6 6 0 0 1-12 0c0-4 6-11 6-11z"/>',
	"r_gas": '<path d="M12 21a6 6 0 0 0 6-6c0-3.5-2.5-5.5-3.5-9-1.5 2-2 3.5-2 5.5-1-1-1.8-2.3-2-3.8C8.5 9.6 6 12 6 15a6 6 0 0 0 6 6z"/>',
	"r_steel": '<path d="M5 4h14M5 20h14M12 4v16M8 4v2M16 4v2M8 18v2M16 18v2"/>',
	"r_rare_earth": '<path d="M6 3h12l3 6-9 12L3 9z"/><path d="M3 9h18M9.5 3 8 9l4 12 4-12-1.5-6"/>',
	"r_uranium": '<circle cx="12" cy="12" r="2"/><ellipse cx="12" cy="12" rx="10" ry="4"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(60 12 12)"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(120 12 12)"/>',
	"r_food": '<path d="M12 21V8M12 8c-2.5 0-4-2-4-4 2.5 0 4 2 4 4zm0 0c2.5 0 4-2 4-4-2.5 0-4 2-4 4zM12 13c-2.5 0-4-2-4-4 2.5 0 4 2 4 4zm0 0c2.5 0 4-2 4-4-2.5 0-4 2-4 4zM12 18c-2.5 0-4-2-4-4 2.5 0 4 2 4 4zm0 0c2.5 0 4-2 4-4-2.5 0-4 2-4 4z"/>',
	# المنشآت
	"airbase": '<path d="M12 2.5c1 0 1.5 1 1.5 2.5v5l7.5 4.5v2l-7.5-2v4l2.5 2v1.5L12 21l-4 1v-1.5l2.5-2v-4L3 16.5v-2L10.5 10V5c0-1.5.5-2.5 1.5-2.5z"/>',
	"port": '<circle cx="12" cy="5" r="2"/><path d="M12 7v14M7 11h10M4 14c0 4 3.6 7 8 7s8-3 8-7M4 14l-1.5 1.5M20 14l1.5 1.5"/>',
	"factory": '<path d="M3 21V10l5 3V10l5 3V10l5 3V4h3v17zM7 17h2M12 17h2M17 17h1"/>',
	"refinery": '<path d="M6 21V8l3-5 3 5v13M6 12h6M6 16h6M15 21V11h5v10M3 21h18"/>',
	"power_plant": '<path fill="currentColor" d="M13 2 4.5 13.5H11L10 22l9.5-12.5H13z"/>',
	"nuclear": '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><path fill="currentColor" stroke="none" d="M12 12 8.4 5.8a7.2 7.2 0 0 1 7.2 0zM12 12h7.2a7.2 7.2 0 0 1-3.6 6.2zM12 12l-3.6 6.2A7.2 7.2 0 0 1 4.8 12z"/>',
	# الاستخبارات والعمليات
	"network": '<circle cx="5" cy="6" r="2"/><circle cx="19" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><circle cx="12" cy="10" r="2"/><path d="M6.7 7l3.6 2M17.3 7l-3.6 2M12 12v4"/>',
	"op_cyber": '<rect x="6" y="6" width="12" height="12" rx="1.5"/><rect x="9.5" y="9.5" width="5" height="5"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
	"op_sabotage": '<circle cx="10" cy="14" r="7"/><path d="M15 9l3-3M17 4l1.5 1.5M20 3l.5 2.5M21 7l-2 .5"/>',
	"op_opposition": '<path d="M3 10v4h3l7 5V5L6 10zM16 9a4 4 0 0 1 0 6M18.5 6.5a7.5 7.5 0 0 1 0 11"/>',
	"op_steal_tech": '<circle cx="8" cy="15" r="4.5"/><path d="M11.2 11.8 20 3M16.5 6.5l2.5 2.5M14 9l2 2"/>',
	"op_incite": '<path d="M5 13l7-6 7 6M5 18l7-6 7 6"/>',
}


static var _cache := {}


## صورة الأيقونة بلون ومقاس محددين (تُخزن مؤقتاً)
static func tex(icon: String, color: Color = Color.WHITE, px: int = 20) -> Texture2D:
	var key := "%s|%s|%d" % [icon, color.to_html(), px]
	if _cache.has(key):
		return _cache[key]
	var body: String = PATHS.get(icon, PATHS["info"])
	var hex := "#" + color.to_html(false)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" %s color="%s">%s</svg>' % [S, hex, body]
	svg = svg.replace("currentColor", hex)
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(px) / 24.0)
	if err != OK:
		push_warning("تعذر رسم الأيقونة: " + icon)
		img = Image.create(px, px, false, Image.FORMAT_RGBA8)
	if color.a < 1.0:
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				c.a *= color.a
				img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func icon_rect(icon: String, color: Color, px: int = 18) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(icon, color, px * 2)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
