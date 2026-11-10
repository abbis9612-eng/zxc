## نظام التصميم: توكنز الألوان والخطوط، والثيم، ومكونات جاهزة بطابع غرفة عمليات مشتركة.
## الألوان الدلالية للقوات تتبع رموز الخرائط العسكرية القياسية (APP-6):
## صديق أزرق، معادٍ أحمر، محايد أخضر، مجهول أصفر. ولون الدولة نحاسي كشارات الرتب.
extends RefCounted

const Icons := preload("res://ui/icons.gd")

const FONT_BODY := "res://assets/fonts/Cairo.ttf"
const FONT_TITLE := "res://assets/fonts/NotoKufiArabic.ttf"

# ---------------------------------------------------------------- التوكنز
const C_INK := Color("0b1118")          # البحر والخلفية
const C_PANEL := Color("111a23f5")      # اللوحات
const C_PANEL_2 := Color("172330")      # البطاقات والأزرار
const C_PANEL_3 := Color("1e2d3b")      # التحويم
const C_LINE := Color("26364480")       # فواصل هادئة
const C_LINE_2 := Color("33495c")       # حدود العناصر
const C_TEXT := Color("e6edf3")
const C_MUTED := Color("8fa3b3")
const C_ACCENT := Color("d4a84b")       # النحاسي: دولتك والأفعال الرئيسية
const C_GOOD := Color("4cc38a")
const C_BAD := Color("e5534b")
const C_WARN := Color("e8a33d")
const C_FRIENDLY := Color("4c9be8")     # APP-6 صديق
const C_HOSTILE := Color("e5534b")      # APP-6 معادٍ
const C_NEUTRAL := Color("4fb477")      # APP-6 محايد
const C_UNKNOWN := Color("e8c547")      # APP-6 مجهول


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
	btn_h.border_color = Color("4a6680")
	var btn_p: StyleBoxFlat = btn.duplicate()
	btn_p.bg_color = Color(C_ACCENT, 0.16)
	btn_p.border_color = C_ACCENT
	var btn_d: StyleBoxFlat = btn.duplicate()
	btn_d.bg_color = Color("121a22")
	btn_d.border_color = Color("26364466")
	for cls in ["Button", "OptionButton", "CheckButton", "MenuButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, btn_h)
		t.set_stylebox("pressed", cls, btn_p)
		t.set_stylebox("hover_pressed", cls, btn_p)
		t.set_stylebox("disabled", cls, btn_d)
		t.set_stylebox("focus", cls, _box(Color.TRANSPARENT, Color(C_ACCENT, 0.7), 6, 1, 0))
		t.set_color("font_color", cls, C_TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, C_ACCENT)
		t.set_color("font_hover_pressed_color", cls, C_ACCENT)
		t.set_color("font_disabled_color", cls, Color("5d6b77"))
		t.set_color("icon_normal_color", cls, C_TEXT)
		t.set_color("icon_pressed_color", cls, C_ACCENT)
		t.set_color("icon_hover_color", cls, Color.WHITE)
		t.set_color("icon_disabled_color", cls, Color("5d6b77"))
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
	t.set_color("font_color", "PrimaryButton", Color("1a1406"))
	t.set_color("font_hover_color", "PrimaryButton", Color("1a1406"))
	t.set_color("font_pressed_color", "PrimaryButton", Color("1a1406"))
	t.set_color("icon_normal_color", "PrimaryButton", Color("1a1406"))
	t.set_color("icon_hover_color", "PrimaryButton", Color("1a1406"))
	t.set_type_variation("DangerButton", "Button")
	var dang := _box(Color(C_BAD, 0.18), C_BAD, 6, 1, 14)
	dang.content_margin_top = pad_v
	dang.content_margin_bottom = pad_v
	var dang_h: StyleBoxFlat = dang.duplicate()
	dang_h.bg_color = Color(C_BAD, 0.32)
	t.set_stylebox("normal", "DangerButton", dang)
	t.set_stylebox("hover", "DangerButton", dang_h)
	t.set_stylebox("pressed", "DangerButton", dang_h)
	t.set_color("font_color", "DangerButton", Color("ffd9d6"))
	t.set_color("font_hover_color", "DangerButton", Color.WHITE)
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
	t.set_color("font_pressed_color", "FlatButton", C_ACCENT)
	t.set_color("icon_normal_color", "FlatButton", C_MUTED)
	t.set_color("icon_pressed_color", "FlatButton", C_ACCENT)

	t.set_color("font_color", "Label", C_TEXT)

	# التبويبات مخفية: التنقل من القائمة الجانبية بالأيقونات
	t.set_stylebox("panel", "TabContainer", _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0))

	t.set_stylebox("background", "ProgressBar", _box(Color("0e151c"), Color.TRANSPARENT, 3, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(C_ACCENT, Color.TRANSPARENT, 3, 0, 0))

	# أشرطة التمرير رفيعة
	var grab := _box(Color("33495c"), Color.TRANSPARENT, 3, 0, 0)
	var grab_h := _box(Color("4a6680"), Color.TRANSPARENT, 3, 0, 0)
	var track := _box(Color.TRANSPARENT, Color.TRANSPARENT, 3, 0, 0)
	track.content_margin_left = 3
	track.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_h)

	t.set_stylebox("panel", "TooltipPanel", _box(Color("0d151d"), C_LINE_2, 6, 1, 8))
	t.set_color("font_color", "TooltipLabel", C_TEXT)

	var slider := _box(Color("0e151c"), Color.TRANSPARENT, 3, 0, 0)
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
	l.add_theme_color_override("font_color", C_ACCENT)
	return l


## رأس قسم: أيقونة + عنوان + خط نحاسي رفيع يمتد
static func section(text: String, icon: String = "", size: int = 17) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if icon != "":
		h.add_child(Icons.icon_rect(icon, C_ACCENT, size + 3))
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
		var col := Color("1a1406") if variation == "PrimaryButton" else C_TEXT
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
	var s := _box(Color("0f171f"), C_LINE_2, 14, 1, 0)
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
