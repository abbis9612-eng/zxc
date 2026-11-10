## نظام التصميم: توكنز الألوان والخطوط، والثيم، ومكونات جاهزة بطابع غرفة عمليات مشتركة.
## الألوان الدلالية للقوات تتبع رموز الخرائط العسكرية القياسية (APP-6):
## صديق أزرق، معادٍ أحمر، محايد أخضر، مجهول أصفر. ولون الدولة نحاسي كشارات الرتب.
extends RefCounted

const Icons := preload("res://ui/icons.gd")

const FONT_BODY := "res://assets/fonts/Cairo.ttf"
const FONT_TITLE := "res://assets/fonts/NotoKufiArabic.ttf"

# ---------------------------------------------------------------- التوكنز
# الألوان متغيرات لا ثوابت: تتبدل بين الثيم الفاتح والداكن (apply_palette)
static var light := true
static var _applied := false
static var C_INK: Color          # الخلفية العامة
static var C_BAR: Color          # الشريط العلوي
static var C_SIDE: Color         # اللوحة الجانبية
static var C_RAIL: Color         # القائمة بالأيقونات
static var C_PANEL: Color        # اللوحات العائمة
static var C_PANEL_2: Color      # البطاقات والأزرار
static var C_PANEL_3: Color      # التحويم
static var C_SUNKEN: Color       # خلفيات الأشرطة والشرائح
static var C_DIALOG: Color
static var C_LINE: Color
static var C_LINE_2: Color
static var C_TEXT: Color
static var C_MUTED: Color
static var C_DISABLED: Color
static var C_ACCENT: Color       # النحاسي: دولتك والأفعال الرئيسية
static var C_ACCENT_TEXT: Color  # نص نحاسي مقروء على الخلفية
static var C_ON_ACCENT: Color    # نص فوق زر نحاسي
static var C_GOOD: Color
static var C_BAD: Color
static var C_WARN: Color
static var C_FRIENDLY: Color     # APP-6 صديق
static var C_HOSTILE: Color      # APP-6 معادٍ
static var C_NEUTRAL: Color      # APP-6 محايد
static var C_UNKNOWN: Color      # APP-6 مجهول
static var C_SHADOW: Color

const PALETTES := {
	"dark": {
		"INK": "0b1118", "BAR": "0d151d", "SIDE": "0f171f", "RAIL": "0b1218", "PANEL": "111a23f5", "PANEL_2": "172330",
		"PANEL_3": "1e2d3b", "SUNKEN": "0e151c", "DIALOG": "101922", "LINE": "26364480", "LINE_2": "33495c",
		"TEXT": "e6edf3", "MUTED": "8fa3b3", "DISABLED": "5d6b77", "ACCENT": "d4a84b", "ACCENT_TEXT": "d4a84b", "ON_ACCENT": "1a1406",
		"GOOD": "4cc38a", "BAD": "e5534b", "WARN": "e8a33d", "FRIENDLY": "4c9be8", "HOSTILE": "e5534b", "NEUTRAL": "4fb477",
		"UNKNOWN": "e8c547", "SHADOW": "00000080",
	},
	"light": {
		"INK": "e9eef2", "BAR": "ffffff", "SIDE": "f7f9fb", "RAIL": "eef2f6", "PANEL": "fffffff2", "PANEL_2": "ffffff",
		"PANEL_3": "eaf0f5", "SUNKEN": "e3e9ef", "DIALOG": "ffffff", "LINE": "c9d3dc99", "LINE_2": "c3ced8",
		"TEXT": "16212b", "MUTED": "5b6b78", "DISABLED": "a3afb9", "ACCENT": "c9972f", "ACCENT_TEXT": "9a6d12", "ON_ACCENT": "1a1406",
		"GOOD": "1e8c5a", "BAD": "c93b33", "WARN": "b86e0a", "FRIENDLY": "1f6fc2", "HOSTILE": "c93b33", "NEUTRAL": "2e8b57",
		"UNKNOWN": "a88514", "SHADOW": "1b2a3a33",
	},
}


static func apply_palette(use_light: bool) -> void:
	light = use_light
	_applied = true
	var p: Dictionary = PALETTES["light" if use_light else "dark"]
	C_INK = Color(p["INK"]); C_BAR = Color(p["BAR"]); C_SIDE = Color(p["SIDE"]); C_RAIL = Color(p["RAIL"])
	C_PANEL = Color(p["PANEL"]); C_PANEL_2 = Color(p["PANEL_2"]); C_PANEL_3 = Color(p["PANEL_3"])
	C_SUNKEN = Color(p["SUNKEN"]); C_DIALOG = Color(p["DIALOG"]); C_LINE = Color(p["LINE"]); C_LINE_2 = Color(p["LINE_2"])
	C_TEXT = Color(p["TEXT"]); C_MUTED = Color(p["MUTED"]); C_DISABLED = Color(p["DISABLED"])
	C_ACCENT = Color(p["ACCENT"]); C_ACCENT_TEXT = Color(p["ACCENT_TEXT"]); C_ON_ACCENT = Color(p["ON_ACCENT"])
	C_GOOD = Color(p["GOOD"]); C_BAD = Color(p["BAD"]); C_WARN = Color(p["WARN"])
	C_FRIENDLY = Color(p["FRIENDLY"]); C_HOSTILE = Color(p["HOSTILE"]); C_NEUTRAL = Color(p["NEUTRAL"]); C_UNKNOWN = Color(p["UNKNOWN"])
	C_SHADOW = Color(p["SHADOW"])


static func load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f: Variant = load(path)
		if f is Font:
			return f
	return null


static func _box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 6, bw: int = 1, margin: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func make_theme(mobile: bool) -> Theme:
	if not _applied:
		apply_palette(light)
	var t := Theme.new()
	var body := load_font(FONT_BODY)
	if body != null:
		t.default_font = body
	var fs := 18 if mobile else 16
	t.default_font_size = fs
	# العربي يحتاج سطراً أعلى من اللاتيني (~1.6 من المقاس)
	t.set_constant("line_spacing", "Label", int(fs * 0.45))
	t.set_constant("line_separation", "RichTextLabel", int(fs * 0.45))

	var panel := _box(C_PANEL, C_LINE_2, 8, 1, 12)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	# بطاقة داخل اللوحات
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _box(C_PANEL_2, C_LINE, 6, 1, 10))

	var pad_v := 10 if mobile else 7
	var btn := _box(C_PANEL_2, C_LINE_2, 6, 1, 12)
	btn.content_margin_top = pad_v
	btn.content_margin_bottom = pad_v
	var btn_h: StyleBoxFlat = btn.duplicate()
	btn_h.bg_color = C_PANEL_3
	btn_h.border_color = C_ACCENT if light else Color("4a6680")
	var btn_p: StyleBoxFlat = btn.duplicate()
	btn_p.bg_color = Color(C_ACCENT, 0.16)
	btn_p.border_color = C_ACCENT
	var btn_d: StyleBoxFlat = btn.duplicate()
	btn_d.bg_color = C_SUNKEN
	btn_d.border_color = C_LINE
	for cls in ["Button", "OptionButton", "CheckButton", "MenuButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, btn_h)
		t.set_stylebox("pressed", cls, btn_p)
		t.set_stylebox("hover_pressed", cls, btn_p)
		t.set_stylebox("disabled", cls, btn_d)
		t.set_stylebox("focus", cls, _box(Color.TRANSPARENT, Color(C_ACCENT, 0.7), 6, 1, 0))
		t.set_color("font_color", cls, C_TEXT)
		t.set_color("font_hover_color", cls, C_TEXT)
		t.set_color("font_pressed_color", cls, C_ACCENT_TEXT)
		t.set_color("font_hover_pressed_color", cls, C_ACCENT_TEXT)
		t.set_color("font_disabled_color", cls, C_DISABLED)
		t.set_color("icon_normal_color", cls, C_TEXT)
		t.set_color("icon_pressed_color", cls, C_ACCENT_TEXT)
		t.set_color("icon_hover_color", cls, C_TEXT)
		t.set_color("icon_disabled_color", cls, C_DISABLED)
		t.set_constant("h_separation", cls, 8)
	# زر رئيسي نحاسي، وزر خطر أحمر
	t.set_type_variation("PrimaryButton", "Button")
	var prim := _box(C_ACCENT, Color.TRANSPARENT, 6, 0, 14)
	prim.content_margin_top = pad_v
	prim.content_margin_bottom = pad_v
	var prim_h: StyleBoxFlat = prim.duplicate()
	prim_h.bg_color = C_ACCENT.lightened(0.12)
	t.set_stylebox("normal", "PrimaryButton", prim)
	t.set_stylebox("hover", "PrimaryButton", prim_h)
	t.set_stylebox("pressed", "PrimaryButton", prim_h)
	t.set_color("font_color", "PrimaryButton", C_ON_ACCENT)
	t.set_color("font_hover_color", "PrimaryButton", C_ON_ACCENT)
	t.set_color("font_pressed_color", "PrimaryButton", C_ON_ACCENT)
	t.set_color("icon_normal_color", "PrimaryButton", C_ON_ACCENT)
	t.set_color("icon_hover_color", "PrimaryButton", C_ON_ACCENT)
	t.set_type_variation("DangerButton", "Button")
	var dang := _box(Color(C_BAD, 0.14), C_BAD, 6, 1, 14)
	dang.content_margin_top = pad_v
	dang.content_margin_bottom = pad_v
	var dang_h: StyleBoxFlat = dang.duplicate()
	dang_h.bg_color = Color(C_BAD, 0.32)
	t.set_stylebox("normal", "DangerButton", dang)
	t.set_stylebox("hover", "DangerButton", dang_h)
	t.set_stylebox("pressed", "DangerButton", dang_h)
	t.set_color("font_color", "DangerButton", C_BAD if light else Color("ffd9d6"))
	t.set_color("font_hover_color", "DangerButton", C_BAD if light else Color.WHITE)
	# زر شفاف للقوائم والقائمة الجانبية
	t.set_type_variation("FlatButton", "Button")
	var flat := _box(Color.TRANSPARENT, Color.TRANSPARENT, 6, 0, 8)
	var flat_h := _box(C_PANEL_3, Color.TRANSPARENT, 6, 0, 8)
	var flat_p := _box(Color(C_ACCENT, 0.14), Color.TRANSPARENT, 6, 0, 8)
	t.set_stylebox("normal", "FlatButton", flat)
	t.set_stylebox("hover", "FlatButton", flat_h)
	t.set_stylebox("pressed", "FlatButton", flat_p)
	t.set_stylebox("hover_pressed", "FlatButton", flat_p)
	t.set_color("font_color", "FlatButton", C_MUTED)
	t.set_color("font_pressed_color", "FlatButton", C_ACCENT_TEXT)
	t.set_color("icon_normal_color", "FlatButton", C_MUTED)
	t.set_color("icon_pressed_color", "FlatButton", C_ACCENT_TEXT)

	t.set_color("font_color", "Label", C_TEXT)

	# التبويبات مخفية: التنقل من القائمة الجانبية بالأيقونات
	t.set_stylebox("panel", "TabContainer", _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0))

	t.set_stylebox("background", "ProgressBar", _box(C_SUNKEN, Color.TRANSPARENT, 3, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(C_ACCENT, Color.TRANSPARENT, 3, 0, 0))

	# أشرطة التمرير رفيعة
	var grab := _box(C_LINE_2, Color.TRANSPARENT, 3, 0, 0)
	var grab_h := _box(C_MUTED, Color.TRANSPARENT, 3, 0, 0)
	var track := _box(Color.TRANSPARENT, Color.TRANSPARENT, 3, 0, 0)
	track.content_margin_left = 3
	track.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_h)

	t.set_stylebox("panel", "TooltipPanel", _box(C_DIALOG, C_LINE_2, 6, 1, 8))
	t.set_color("font_color", "TooltipLabel", C_TEXT)

	var slider := _box(C_SUNKEN, Color.TRANSPARENT, 3, 0, 0)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", _box(Color(C_ACCENT, 0.7), Color.TRANSPARENT, 3, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(C_ACCENT, Color.TRANSPARENT, 3, 0, 0))

	t.set_stylebox("normal", "LineEdit", btn)
	t.set_stylebox("focus", "LineEdit", btn_p)
	return t


# ---------------------------------------------------------------- مكونات

static func title(text: String, size: int = 20) -> Label:
	var l := Label.new()
	l.text = text
	var f := load_font(FONT_TITLE)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", C_ACCENT_TEXT)
	return l


## رأس قسم: أيقونة + عنوان + خط نحاسي رفيع يمتد
static func section(text: String, icon: String = "", size: int = 17) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if icon != "":
		h.add_child(Icons.icon_rect(icon, C_ACCENT_TEXT, size + 3))
	var t := title(text, size)
	h.add_child(t)
	v.add_child(h)
	var line := ColorRect.new()
	line.color = Color(C_ACCENT, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	var top := MarginContainer.new()
	top.add_theme_constant_override("margin_top", 6)
	top.add_child(v)
	var wrap := VBoxContainer.new()
	wrap.add_child(top)
	return wrap


static func label(text: String, color: Color = C_TEXT, size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


static func button(text: String, cb: Callable, icon: String = "", variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	if icon != "":
		var col := C_ON_ACCENT if variation == "PrimaryButton" else C_TEXT
		b.icon = Icons.tex(icon, col, 36)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 18)
	if variation != "":
		b.theme_type_variation = variation
	return b


static func row(children: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for c in children:
		# تسمية قصيرة داخل صف لا تلتف، وإلا انكسرت حرفاً حرفاً
		if c is Label and not c.size_flags_horizontal & Control.SIZE_EXPAND:
			(c as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(c)
	return h


static func col() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	return v


static func card(severity: Color = Color.TRANSPARENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Card"
	if severity.a > 0.0:
		var s := _box(C_PANEL_2, C_LINE, 6, 1, 10)
		# شريط اللون على بداية السطر (اليمين في العربي)
		s.border_width_right = 4
		s.border_color = severity
		s.border_width_left = 0
		s.border_width_top = 0
		s.border_width_bottom = 0
		p.add_theme_stylebox_override("panel", s)
	return p


static func sep() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = C_LINE
	s.add_theme_stylebox_override("separator", line)
	return s


static func bar(value: float, max_value: float = 100.0, color: Color = C_ACCENT) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = max_value
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 8)
	var fill := _box(color, Color.TRANSPARENT, 3, 0, 0)
	p.add_theme_stylebox_override("fill", fill)
	return p


## مفتاح: قيمة في سطر واحد، مع أيقونة اختيارية قبل المفتاح
static func kv(key: String, value: String, value_color: Color = C_TEXT, icon: String = "") -> HBoxContainer:
	# الطرفان يلتفان حتى لا توسّع القيم الطويلة اللوحة الجانبية
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if icon != "":
		h.add_child(Icons.icon_rect(icon, C_MUTED, 18))
	var k := label(key, C_MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	var v := label(value, value_color)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = 1.3
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


## شريحة صغيرة: أيقونة + قيمة، للشريط العلوي والملخصات
static func chip(icon: String, text: String, color: Color = C_TEXT, tip: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var s := _box(C_SUNKEN if light else Color("0f171f"), C_LINE_2, 14, 1, 0)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", s)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(Icons.icon_rect(icon, color, 18))
	var l := label(text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.name = "Value"
	h.add_child(l)
	p.add_child(h)
	p.tooltip_text = tip
	p.set_meta("icon", icon)
	return p


static func money(billions: float) -> String:
	var x := billions
	if absf(x) >= 1000.0:
		return "%s ترليون $" % _num(x / 1000.0, 2)
	if absf(x) >= 1.0:
		return "%s مليار $" % _num(x, 1)
	return "%s مليون $" % _num(x * 1000.0, 0)


static func _num(x: float, decimals: int) -> String:
	if decimals <= 0:
		return str(int(roundf(x)))
	return String.num(x, decimals)


static func signed(x: float, decimals: int = 1) -> String:
	var s := String.num(x, decimals)
	return ("+" + s) if x > 0.0 else s


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()
