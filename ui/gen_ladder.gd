## سلّم الأجيال الخمسة لفرع بحث: أين وصلت، وما قيد البحث، وأين عدوك.
## يُرسم من اليمين لليسار (الجيل 1 يميناً) كما تُقرأ العربية.
extends Control

const UI := preload("res://ui/ui_kit.gd")

var gen := 1                 # الجيل الذي وصلت إليه
var researching := false     # هل الجيل التالي قيد البحث
var progress := 0.0          # تقدم البحث نحو الجيل التالي (0..1)
var rival_gen := -1          # جيل العدو، -1 غير معروف
var rival_flag: Texture2D = null
var names: Array = []        # أسماء أسلحة الأجيال الخمسة
var _font: Font
var _bold: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 54)
	_font = get_theme_default_font()
	var fb := FontVariation.new()
	fb.base_font = _font
	fb.variation_embolden = 0.6
	_bold = fb
	resized.connect(queue_redraw)


## مركز الدرجة i (0..4) على الشاشة: الأولى يميناً
func _node_x(i: int) -> float:
	var step := size.x / 5.0
	return size.x - step * (i + 0.5)


func _draw() -> void:
	var cy := 22.0
	var r := 12.0
	var ink := UI.C_TEXT
	var empty := UI.C_LINE_2
	var gold := UI.C_ACCENT
	# الخط الواصل: ممتلئ حتى جيلك، ثم جزء ذهبي بقدر التقدم
	draw_line(Vector2(_node_x(0), cy), Vector2(_node_x(4), cy), empty, 3.0)
	if gen > 1:
		draw_line(Vector2(_node_x(0), cy), Vector2(_node_x(gen - 1), cy), ink, 3.0)
	if researching and gen < 5:
		var a := _node_x(gen - 1)
		var b := _node_x(gen)
		draw_line(Vector2(a, cy), Vector2(lerpf(a, b, clampf(progress, 0.0, 1.0)), cy), gold, 3.0)
	for i in 5:
		var p := Vector2(_node_x(i), cy)
		var n := i + 1
		var txt := str(n)
		var col_txt: Color
		if n <= gen:
			draw_circle(p, r, ink)
			col_txt = Color.WHITE if UI.light else Color("0b1118")
		elif n == gen + 1 and researching:
			draw_circle(p, r, UI.C_PANEL_2)
			draw_arc(p, r - 1.5, 0.0, TAU, 32, gold, 3.0, true)
			col_txt = UI.C_ACCENT_TEXT
		else:
			draw_circle(p, r, UI.C_PANEL_2)
			draw_arc(p, r - 1.0, 0.0, TAU, 32, empty, 2.0, true)
			col_txt = UI.C_MUTED
		var fs := 14
		var w := _bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_bold, p + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_txt)
		# اسم السلاح تحت جيلك فقط (الجيل القادم يُكتب في رأس الشاشة)
		if n == gen and n - 1 < names.size():
			var label := _short(String(names[n - 1]))
			var lfs := 12
			var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
			var lc: Color = UI.C_TEXT
			var maxw := size.x / 5.0 * 1.9
			if lw > maxw:
				lw = maxw
			draw_string(_font, Vector2(p.x - lw * 0.5, cy + r + 15), label, HORIZONTAL_ALIGNMENT_CENTER, lw, lfs, lc)
	# العدو: علمه فوق الجيل الذي وصل إليه
	if rival_gen >= 1:
		var p := Vector2(_node_x(rival_gen - 1), cy)
		var fr := Rect2(p + Vector2(-11, -r - 14), Vector2(22, 15))
		draw_rect(fr.grow(1.5), UI.C_BAD)
		if rival_flag != null:
			draw_texture_rect(rival_flag, fr, false)


## اسم السلاح بلا «فئة»: الدرجة تقول إنها فئة
static func _short(s: String) -> String:
	return s.trim_prefix("فئة ")
