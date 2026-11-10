## أدوات بناء الواجهة: الثيم والخطوط وعناصر جاهزة بطابع غرفة العمليات.
extends RefCounted

const FONT_BODY := "res://assets/fonts/Cairo.ttf"
const FONT_TITLE := "res://assets/fonts/NotoKufiArabic.ttf"

const C_PANEL := Color(0.05, 0.08, 0.11, 0.94)
const C_PANEL_2 := Color(0.08, 0.12, 0.16, 1.0)
const C_LINE := Color(0.3, 0.7, 0.9, 0.45)
const C_TEXT := Color(0.88, 0.93, 0.97)
const C_MUTED := Color(0.55, 0.65, 0.72)
const C_ACCENT := Color("e0b84a")
const C_GOOD := Color("4cc38a")
const C_BAD := Color("e05a55")


static func load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f: Variant = load(path)
		if f is Font:
			return f
	return null


static func make_theme(mobile: bool) -> Theme:
	var t := Theme.new()
	var body := load_font(FONT_BODY)
	if body != null:
		t.default_font = body
	t.default_font_size = 19 if mobile else 16

	var panel := StyleBoxFlat.new()
	panel.bg_color = C_PANEL
	panel.border_color = C_LINE
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var btn := StyleBoxFlat.new()
	btn.bg_color = C_PANEL_2
	btn.border_color = C_LINE
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(4)
	btn.content_margin_left = 12
	btn.content_margin_right = 12
	btn.content_margin_top = 6 if not mobile else 10
	btn.content_margin_bottom = 6 if not mobile else 10
	var btn_h: StyleBoxFlat = btn.duplicate()
	btn_h.bg_color = Color(0.12, 0.2, 0.27)
	var btn_p: StyleBoxFlat = btn.duplicate()
	btn_p.bg_color = Color(0.2, 0.17, 0.08)
	btn_p.border_color = C_ACCENT
	var btn_d: StyleBoxFlat = btn.duplicate()
	btn_d.bg_color = Color(0.06, 0.08, 0.1)
	btn_d.border_color = Color(0.3, 0.3, 0.3, 0.4)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, btn_h)
		t.set_stylebox("pressed", cls, btn_p)
		t.set_stylebox("hover_pressed", cls, btn_p)
		t.set_stylebox("disabled", cls, btn_d)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, C_TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, C_ACCENT)
		t.set_color("font_disabled_color", cls, Color(0.5, 0.5, 0.5))
	t.set_color("font_color", "Label", C_TEXT)

	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = C_PANEL_2
	tab_sel.border_color = C_ACCENT
	tab_sel.border_width_bottom = 2
	tab_sel.set_content_margin_all(8)
	var tab_un: StyleBoxFlat = tab_sel.duplicate()
	tab_un.bg_color = Color(0.04, 0.06, 0.08)
	tab_un.border_width_bottom = 0
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_un)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_color("font_selected_color", "TabContainer", C_ACCENT)
	t.set_color("font_unselected_color", "TabContainer", C_MUTED)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.13, 0.16)
	bar_bg.set_corner_radius_all(3)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = C_ACCENT
	bar_fill.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	return t


static func title(text: String, size: int = 20) -> Label:
	var l := Label.new()
	l.text = text
	var f := load_font(FONT_TITLE)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", C_ACCENT)
	return l


static func label(text: String, color: Color = C_TEXT, size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


static func row(children: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for c in children:
		h.add_child(c)
	return h


static func col() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	return v


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
	p.custom_minimum_size = Vector2(0, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	p.add_theme_stylebox_override("fill", fill)
	return p


## مفتاح: قيمة في سطر واحد
static func kv(key: String, value: String, value_color: Color = C_TEXT) -> HBoxContainer:
	var k := label(key, C_MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	var v := label(value, value_color)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	return row([k, v])


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
