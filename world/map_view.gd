## خريطة القيادة (المرحلة الحالية: خريطة مسطحة ثنائية الأبعاد بطابع غرفة عمليات).
## الكرة الأرضية ثلاثية الأبعاد تأتي في مرحلة لاحقة وتستبدل هذا الملف فقط.
extends Control

const Intel := preload("res://sim/intel.gd")
const Divisions := preload("res://sim/divisions.gd")
const Territory := preload("res://sim/territory.gd")
const Icons := preload("res://ui/icons.gd")
const UI := preload("res://ui/ui_kit.gd")
const Flags := preload("res://ui/flags.gd")

signal country_selected(id: String)
signal region_selected(rid: String)
signal hovered(rid: String, pos: Vector2)

const WORLD_FILE := "res://data/world_110m.json"
const REGIONS_FILE := "res://data/regions.json"
const REGIONS_GEO_FILE := "res://data/regions_geo.json"
const C_OCCUPIED_LINE := Color(0, 0, 0, 0.35)
const MAP_W := 360.0
const MAP_H := 180.0

enum Layer { POLITICAL, POWER, ECONOMY, STABILITY, RESOURCES, RANGE }

## رموز المنشآت على الخريطة: حرف عربي داخل دائرة ملونة (يعمل مع أي خط)
const FACILITY_MARKS := {
	"airbase": ["ج", Color("3d8fd6")], "port": ["م", Color("21a3ad")], "factory": ["ص", Color("b8902f")],
	"refinery": ["ف", Color("d9692b")], "power_plant": ["ك", Color("c9a812")], "nuclear": ["ن", Color("9b4fd6")],
}

## ألوان الخريطة في الثيمين. المفتاح في الواجهة يقرأ من هنا أيضاً حتى يطابق الخريطة دائماً.
const MAP_PALETTES := {
	"dark": {
		"BG": "0a1018", "GRID": "40739919", "LAND_OFF": "1a222c", "BORDER": "59bff259", "REGION_BORDER": "8cccf229",
		"PLAYER": "e0b84a", "ALLY": "3f8fd8", "VASSAL": "6a6ff0", "ENEMY": "d8423f", "SELECT": "fffffff2",
		"REL_NEUTRAL": "34404c", "REL_GOOD": "3d8a5a", "REL_BAD": "8a3d3d", "SCALE_LO": "2a3340",
		"POWER_HI": "c0392b", "ECON_HI": "27ae60", "STAB_LO": "c0392b", "STAB_HI": "27ae60",
		"RES_NONE": "1d2630", "RES_ENERGY": "d9822b", "RES_MINERAL": "6a7fd1",
		"RANGE_NONE": "1d2630", "RANGE_AIR": "2f5f8f", "RANGE_MIS": "6b3f8f", "RANGE_BOTH": "b0662e",
		"LABEL": "ffffff", "LABEL_SOFT": "d9ebffd9", "OUTLINE": "000000d0", "CHIP": "0b1118e6",
		"UNIT_FRIEND": "1d3f63", "UNIT_HOSTILE": "5a1f1c", "UNIT_NEUTRAL": "1f4a32", "SELF_OUTLINE": "ffffff59",
	},
	"light": {
		"BG": "bcd3e4", "GRID": "4a6c8a22", "LAND_OFF": "e4e8eb", "BORDER": "6f8599b3", "REGION_BORDER": "7d91a466",
		"PLAYER": "e8b54e", "ALLY": "78acdf", "VASSAL": "9d9ff0", "ENEMY": "e2716b", "SELECT": "16212bf2",
		"REL_NEUTRAL": "dfe4e8", "REL_GOOD": "9ccfb0", "REL_BAD": "e8aaa6", "SCALE_LO": "e1e6ea",
		"POWER_HI": "d9534f", "ECON_HI": "3aa66b", "STAB_LO": "e0706b", "STAB_HI": "5bb585",
		"RES_NONE": "e6eaee", "RES_ENERGY": "ea9b4c", "RES_MINERAL": "8c9ee0",
		"RANGE_NONE": "e6eaee", "RANGE_AIR": "8fb8e0", "RANGE_MIS": "b49ad6", "RANGE_BOTH": "eba567",
		"LABEL": "16212b", "LABEL_SOFT": "2b3a48d9", "OUTLINE": "ffffffe6", "CHIP": "ffffffeb",
		"UNIT_FRIEND": "d6e7fa", "UNIT_HOSTILE": "f8d7d5", "UNIT_NEUTRAL": "d4efdf", "SELF_OUTLINE": "16212b59",
	},
}
static var P := {}
static var C_BG: Color
static var C_GRID: Color
static var C_LAND_OFF: Color
static var C_BORDER: Color
static var C_PLAYER: Color
static var C_ALLY: Color
static var C_VASSAL: Color
static var C_ENEMY: Color
static var C_SELECT: Color
static var C_REGION_BORDER: Color


static func apply_palette(light: bool) -> void:
	P = {}
	var src: Dictionary = MAP_PALETTES["light" if light else "dark"]
	for k in src:
		P[k] = Color(src[k])
	C_BG = P["BG"]; C_GRID = P["GRID"]; C_LAND_OFF = P["LAND_OFF"]; C_BORDER = P["BORDER"]; C_PLAYER = P["PLAYER"]
	C_ALLY = P["ALLY"]; C_VASSAL = P["VASSAL"]; C_ENEMY = P["ENEMY"]; C_SELECT = P["SELECT"]; C_REGION_BORDER = P["REGION_BORDER"]


static func pal(k: String) -> Color:
	if P.is_empty():
		apply_palette(true)
	return P[k]

var sim = null
var layer: int = Layer.POLITICAL
var selected: String = ""
var selected_region: String = ""
var selected_division: int = -1
var _range_cache: Dictionary = {}     # منطقة -> 0 لا شيء، 1 طيران، 2 صواريخ، 3 كلاهما
var _range_day: int = -1
var _hover_rid := ""
var _anim_acc := 0.0
var _front_cache := {}     # حرب -> مناطق الجبهة، تُحسب مرة كل يوم
var _front_day := -1
var _hover_pos := Vector2.ZERO

var _shapes: Array = []          # [{id, name_ar, rings:[PackedVector2Array], tris:[PackedInt32Array], rect:Rect2}]
var _by_id: Dictionary = {}       # id -> index في _shapes
var _regions: Array = []         # أشكال المناطق: {id, country, name_ar, center, rings, tris, rect}
var _region_info: Dictionary = {}
var _playable: Dictionary = {}    # الدول المقسمة إلى مناطق
var _zoom: float = 1.0
var _center := Vector2(MAP_W * 0.5 + 30.0, MAP_H * 0.5 - 50.0)   # نبدأ فوق الشرق الأوسط وأوروبا
var _dragging := false
var _drag_moved := 0.0
var _touches: Dictionary = {}
var _time := 0.0
var _font: Font


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	_load_world()
	_load_regions()
	_zoom = 2.2
	resized.connect(queue_redraw)


func _load_world() -> void:
	var f := FileAccess.open(WORLD_FILE, FileAccess.READ)
	if f == null:
		push_error("تعذر فتح ملف الخريطة")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for c in data["countries"]:
		var shape := _make_shape(c["polys"])
		shape["id"] = c["id"]
		shape["name_ar"] = c["name_ar"]
		_by_id[c["id"]] = _shapes.size()
		_shapes.append(shape)


func _load_regions() -> void:
	var fi := FileAccess.open(REGIONS_FILE, FileAccess.READ)
	var fg := FileAccess.open(REGIONS_GEO_FILE, FileAccess.READ)
	if fi == null or fg == null:
		push_error("تعذر فتح ملفات المناطق")
		return
	var info: Dictionary = JSON.parse_string(fi.get_as_text())
	var geo: Dictionary = JSON.parse_string(fg.get_as_text())["shapes"]
	for r in info["regions"]:
		var rid: String = r["id"]
		_region_info[rid] = r
		_playable[r["country"]] = true
		var shape := _make_shape(geo.get(rid, []))
		shape["id"] = rid
		shape["country"] = r["country"]
		shape["name_ar"] = r["name_ar"]
		shape["center"] = to_map(float(r["lon"]), float(r["lat"]))
		_regions.append(shape)


func _make_shape(polys: Array) -> Dictionary:
	var shape := {"rings": [], "tris": [], "rect": Rect2()}
	var first := true
	for flat in polys:
		var pts := PackedVector2Array()
		for i in range(0, flat.size(), 2):
			pts.append(to_map(float(flat[i]), float(flat[i + 1])))
		if pts.size() < 3:
			continue
		shape["rings"].append(pts)
		shape["tris"].append(Geometry2D.triangulate_polygon(pts))
		var r := _bounds(pts)
		shape["rect"] = r if first else (shape["rect"] as Rect2).merge(r)
		first = false
	return shape


static func to_map(lon: float, lat: float) -> Vector2:
	return Vector2(lon + 180.0, 90.0 - lat)


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


func _scale() -> float:
	# عدد البكسلات لكل درجة
	return size.x / MAP_W * _zoom


func map_to_screen(m: Vector2) -> Vector2:
	return (m - _center) * _scale() + size * 0.5


func screen_to_map(s: Vector2) -> Vector2:
	return (s - size * 0.5) / _scale() + _center


func focus_country(id: String) -> void:
	if sim == null:
		return
	var c: Dictionary = sim.country(id)
	if c.is_empty():
		return
	_center = to_map(float(c["lon"]), float(c["lat"]))
	_zoom = maxf(_zoom, 3.0)
	_clamp_view()
	queue_redraw()


func focus_point(lon: float, lat: float) -> void:
	_center = to_map(lon, lat)
	_zoom = maxf(_zoom, 6.0)
	_clamp_view()
	queue_redraw()


func set_layer(l: int) -> void:
	layer = l
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	# نبضة الجبهات: إعادة رسم 10 مرات في الثانية تكفي، بدل كل إطار (أخف على الهاتف)
	if sim != null and not sim.state.get("wars", []).is_empty():
		_anim_acc += delta
		if _anim_acc >= 0.1:
			_anim_acc = 0.0
			queue_redraw()


# ------------------------------------------------------------------ الرسم

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	_draw_grid()
	var s := _scale()
	var offset := size * 0.5 - _center * s
	draw_set_transform(offset, 0.0, Vector2(s, s))
	var view := Rect2(screen_to_map(Vector2.ZERO), size / s)
	var ci := get_canvas_item()
	# 1) الدول غير المقسمة بعد
	for shape in _shapes:
		if _playable.has(shape["id"]) or not view.intersects(shape["rect"]):
			continue
		_fill_shape(ci, shape, _fill_color(shape["id"]))
	# 2) المناطق بلون من يسيطر عليها
	for shape in _regions:
		if not view.intersects(shape["rect"]):
			continue
		_fill_shape(ci, shape, _region_color(shape))
	# 3) الحدود
	for shape in _shapes:
		if not view.intersects(shape["rect"]):
			continue
		if _playable.has(shape["id"]):
			continue
		_outline(shape, C_BORDER, -1.0)
	for shape in _regions:
		if not view.intersects(shape["rect"]):
			continue
		var own := _owner_of(shape)
		var border := C_REGION_BORDER
		if own != shape["country"]:
			border = Color(C_ENEMY, 0.55)
		_outline(shape, border, -1.0)
	# حدود الدول المقسمة (تقريبية) عند الابتعاد فقط
	if s < 14.0:
		for shape in _shapes:
			if _playable.has(shape["id"]) and view.intersects(shape["rect"]):
				_outline(shape, C_BORDER, -1.0)
	# 4) التحديد
	for shape in _regions:
		if shape["id"] == selected_region:
			_outline(shape, C_SELECT, 2.5 / s)
		elif _owner_of(shape) == selected and view.intersects(shape["rect"]):
			_outline(shape, pal("SELF_OUTLINE"), 1.2 / s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if sim != null:
		_draw_region_labels()
		_draw_facilities()
		_draw_wars()
		_draw_capitals()
		_draw_divisions()
	_draw_scale_bar()


func _fill_shape(ci: RID, shape: Dictionary, col: Color) -> void:
	for i in shape["rings"].size():
		var pts: PackedVector2Array = shape["rings"][i]
		var tris: PackedInt32Array = shape["tris"][i]
		if tris.size() >= 3:
			var cols := PackedColorArray()
			cols.resize(pts.size())
			cols.fill(col)
			RenderingServer.canvas_item_add_triangle_array(ci, tris, pts, cols)


func _outline(shape: Dictionary, col: Color, width: float) -> void:
	for pts in shape["rings"]:
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col, width)


func _owner_of(shape: Dictionary) -> String:
	if sim == null:
		return shape["country"]
	return sim.state["regions"][shape["id"]]["owner"]


func _region_color(shape: Dictionary) -> Color:
	var own := _owner_of(shape)
	if layer == Layer.RESOURCES:
		return _resource_color(shape)
	if layer == Layer.RANGE:
		return _range_color(shape)
	var col := _fill_color(own)
	if own != shape["country"]:
		# منطقة محتلة: لون المحتل ممزوج بلون صاحبها الأصلي
		col = col.lerp(_fill_color(shape["country"]), 0.35).darkened(0.15)
	if shape["id"] == selected_region:
		col = col.lightened(0.2)
	return col


func _resource_color(shape: Dictionary) -> Color:
	var res: Dictionary = _region_info[shape["id"]].get("resources", {})
	var energy := float(res.get("oil", 0.0)) + float(res.get("gas", 0.0)) * 0.7
	var other := float(res.get("steel", 0.0)) + float(res.get("rare_earth", 0.0)) + float(res.get("uranium", 0.0))
	var col := pal("RES_NONE")
	col = col.lerp(pal("RES_ENERGY"), clampf(energy / 25.0, 0.0, 1.0))
	col = col.lerp(pal("RES_MINERAL"), clampf(other / 40.0, 0.0, 0.6))
	if shape["id"] == selected_region:
		col = col.lightened(0.25)
	return col


## طبقة المدى: أين تصل مقاتلاتك من قواعدها العاملة، وصواريخك من أرضك
func _range_color(shape: Dictionary) -> Color:
	if sim == null:
		return C_LAND_OFF
	if _range_day != int(sim.state["day"]) / 7:
		_rebuild_range()
	var code := int(_range_cache.get(shape["id"], 0))
	var col: Color = [pal("RANGE_NONE"), pal("RANGE_AIR"), pal("RANGE_MIS"), pal("RANGE_BOTH")][code]
	if _owner_of(shape) == sim.state["player"]:
		col = C_PLAYER.darkened(0.35)
	return col


func _rebuild_range() -> void:
	_range_day = int(sim.state["day"]) / 7
	_range_cache = {}
	var pid: String = sim.state["player"]
	var c: Dictionary = sim.player()
	var fr: float = Divisions.range_km(sim, "fighters", int(c["tech"]["air"]))
	var mr: float = Divisions.range_km(sim, "missiles", int(c["tech"]["missile"]))
	var bases: Array = Territory.working_facilities(sim, [pid], "airbase")
	var mine: Array = Territory.owned(sim, pid)
	for shape in _regions:
		var rid: String = shape["id"]
		var code := 0
		for b in bases:
			if Divisions.dist_km(sim, b, rid) <= fr:
				code |= 1
				break
		for m in mine:
			if Divisions.dist_km(sim, m, rid) <= mr:
				code |= 2
				break
		_range_cache[rid] = code


## رمز فرقة بمعيار APP-6: الإطار حسب الانتماء، وداخله علامة المشاة الآلية (× مع شكل بيضاوي)،
## وفوقه علامة مستوى الفرقة XX، وتحته شريط الجاهزية
func _draw_unit_symbol(p: Vector2, aff: String, mine: bool, strength: float) -> void:
	var fill: Color
	var line: Color
	match aff:
		"friend":
			fill = pal("UNIT_FRIEND")
			line = UI.C_FRIENDLY
		"hostile":
			fill = pal("UNIT_HOSTILE")
			line = UI.C_HOSTILE
		_:
			fill = pal("UNIT_NEUTRAL")
			line = UI.C_NEUTRAL
	if mine:
		line = UI.C_ACCENT_TEXT if UI.light else C_PLAYER
	var inner: PackedVector2Array
	if aff == "hostile":
		var pts := PackedVector2Array([p + Vector2(0, -11), p + Vector2(11, 0), p + Vector2(0, 11), p + Vector2(-11, 0)])
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, line, 1.6, true)
		inner = PackedVector2Array([p + Vector2(-5.5, -5.5), p + Vector2(5.5, 5.5), p + Vector2(-5.5, 5.5), p + Vector2(5.5, -5.5)])
	else:
		var half := Vector2(11, 7.5) if aff == "friend" else Vector2(8.5, 8.5)
		var r := Rect2(p - half, half * 2.0)
		draw_rect(r, fill)
		draw_rect(r, line, false, 1.6)
		inner = PackedVector2Array([r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)])
	draw_line(inner[0], inner[1], line, 1.2, true)
	draw_line(inner[2], inner[3], line, 1.2, true)
	draw_arc(p, 3.0, 0.0, TAU, 14, line, 1.2, true)
	# مستوى الفرقة: XX
	var ech := "XX"
	var ew := _font.get_string_size(ech, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string_outline(_font, p + Vector2(-ew * 0.5, -13), ech, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, pal("OUTLINE"))
	draw_string(_font, p + Vector2(-ew * 0.5, -13), ech, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, line)
	# شريط الجاهزية
	var bw := 20.0
	draw_rect(Rect2(p + Vector2(-bw * 0.5, 12), Vector2(bw, 3)), Color(0, 0, 0, 0.7))
	var sc: Color = UI.C_GOOD if strength >= 0.7 else (UI.C_WARN if strength >= 0.45 else UI.C_BAD)
	draw_rect(Rect2(p + Vector2(-bw * 0.5, 12), Vector2(bw * clampf(strength, 0.0, 1.0), 3)), sc)


## رموز الفرق مع ضباب الحرب وأسهم الحركة
func _draw_divisions() -> void:
	var pid: String = sim.state["player"]
	var screen := Rect2(Vector2(-30, -30), size + Vector2(60, 60))
	var mine_regions: Array = []
	for d in sim.state.get("divisions", []):
		if d["owner"] == pid:
			mine_regions.append(d["region"])
	# تجميع الفرق: رمز واحد لكل دولة في كل منطقة، مع عددها ومتوسط جاهزيتها
	var groups := {}
	var order: Array = []
	for d in sim.state.get("divisions", []):
		var owner: String = d["owner"]
		var rid: String = d["region"]
		# ضباب الحرب: فرق الآخرين تظهر برؤية 40 أو إن كانت ملاصقة لقواتك
		if owner != pid and not (owner in sim.allies(pid)):
			var near := false
			for m in mine_regions:
				if rid == m or rid in sim.db.regions[m]["neighbors"]:
					near = true
					break
			if not near and Intel.visibility(sim, pid, owner) < 40.0:
				continue
		var key := rid + "|" + owner
		if not groups.has(key):
			groups[key] = {"rid": rid, "owner": owner, "n": 0, "str": 0.0, "sel": false, "moving": []}
			order.append(key)
		var g: Dictionary = groups[key]
		g["n"] += 1
		g["str"] += float(d["strength"])
		if int(d["id"]) == selected_division:
			g["sel"] = true
		if int(d["eta"]) >= 0 and owner == pid:
			g["moving"].append(d["target"])
	var per_region := {}
	for key in order:
		var g: Dictionary = groups[key]
		var rid: String = g["rid"]
		var owner: String = g["owner"]
		var info: Dictionary = sim.db.regions[rid]
		var base := map_to_screen(to_map(float(info["lon"]), float(info["lat"])))
		var k := int(per_region.get(rid, 0))
		per_region[rid] = k + 1
		var p := base + Vector2(16 + k * 26, -16)
		if not screen.has_point(p):
			continue
		# رموز APP-6: صديق مستطيل أزرق، معادٍ معيّن أحمر، محايد مربع أخضر
		var aff := "neutral"
		if owner == pid or owner in sim.allies(pid) or sim.country(owner).get("overlord", "") == pid:
			aff = "friend"
		elif owner in sim.enemies_of(pid):
			aff = "hostile"
		var n := int(g["n"])
		_draw_unit_symbol(p, aff, owner == pid, float(g["str"]) / float(n))
		if n > 1:
			var txt := "×%d" % n
			var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var bp := p + Vector2(10, 2)
			draw_rect(Rect2(bp - Vector2(1, 10), Vector2(tw + 4, 13)), pal("CHIP"))
			draw_string(_font, bp + Vector2(1, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pal("LABEL"))
		if g["sel"]:
			draw_arc(p, 17.0, 0.0, TAU, 32, Color.WHITE, 1.5)
		var col: Color = UI.C_FRIENDLY if aff == "friend" else (UI.C_HOSTILE if aff == "hostile" else UI.C_NEUTRAL)
		# أسهم الحركة لفرقك
		for target in g["moving"]:
			var t: Dictionary = sim.db.regions[target]
			var tp := map_to_screen(to_map(float(t["lon"]), float(t["lat"])))
			draw_dashed_line(p, tp, col, 1.5, 5.0)
			var dir := (tp - p).normalized()
			draw_line(tp, tp - dir * 8.0 + dir.orthogonal() * 4.0, col, 1.5)
			draw_line(tp, tp - dir * 8.0 - dir.orthogonal() * 4.0, col, 1.5)


func _draw_facilities() -> void:
	var s := _scale()
	if s < 10.0:
		return
	var screen := Rect2(Vector2(-20, -20), size + Vector2(40, 40))
	for shape in _regions:
		var fac: Dictionary = _region_info[shape["id"]].get("facilities", {})
		if fac.is_empty():
			continue
		# عند الاقتراب المتوسط: منشآت الدولة المختارة فقط
		if s < 24.0 and _owner_of(shape) != selected and shape["country"] != selected:
			continue
		var base := map_to_screen(shape["center"])
		if not screen.has_point(base):
			continue
		var dmg: Dictionary = {}
		if sim != null:
			dmg = sim.state["regions"][shape["id"]].get("damaged", {})
		var x := -float(fac.size() - 1) * 10.0
		for t in fac:
			var mark: Array = FACILITY_MARKS.get(t, ["?", Color.WHITE])
			var p := base + Vector2(x, 18)
			var col: Color = UI.C_BAD if dmg.has(t) else mark[1]
			# أيقونة المنشأة داخل دائرة داكنة بحافة ملونة؛ المعطلة حمراء
			draw_circle(p, 9.0, pal("CHIP"))
			draw_arc(p, 9.0, 0.0, TAU, 20, col, 1.4, true)
			draw_texture_rect(Icons.tex(t, col, 32), Rect2(p - Vector2(6, 6), Vector2(12, 12)), false)
			x += 20.0


func _draw_region_labels() -> void:
	var s := _scale()
	if s < 8.0:
		return
	var fs := 11 if s < 20.0 else 13
	var screen := Rect2(Vector2(-40, -20), size + Vector2(80, 40))
	for shape in _regions:
		var own := _owner_of(shape)
		# عند الاقتراب المتوسط: مناطق الدولة المختارة فقط، وعند الاقتراب الكبير: كل المناطق
		if s < 22.0 and own != selected and shape["country"] != selected:
			continue
		var p := map_to_screen(shape["center"])
		if not screen.has_point(p):
			continue
		var label: String = shape["name_ar"]
		if sim != null and sim.db.capitals.get(shape["country"], "") == shape["id"]:
			continue   # العاصمة تُكتب باسم الدولة
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# لا نكتب الاسم إن كانت المنطقة أصغر من النص على الشاشة (إلا المختارة)
		var rect: Rect2 = shape["rect"]
		if shape["id"] != selected_region and rect.size.x * s < w * 0.9:
			continue
		var pos := p + Vector2(-w * 0.5, 4)
		draw_string_outline(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, pal("OUTLINE"))
		draw_string(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pal("LABEL_SOFT"))


func _draw_grid() -> void:
	for lon in range(-180, 181, 30):
		var a := map_to_screen(to_map(lon, 90))
		var b := map_to_screen(to_map(lon, -90))
		draw_line(a, b, C_GRID, 1.0)
	for lat in range(-90, 91, 30):
		var a := map_to_screen(to_map(-180, lat))
		var b := map_to_screen(to_map(180, lat))
		draw_line(a, b, C_GRID, 1.0)


func _fill_color(id: String) -> Color:
	if sim == null:
		return C_LAND_OFF
	var c: Dictionary = sim.country(id)
	if c.is_empty():
		return C_LAND_OFF
	var pid: String = sim.state["player"]
	var base: Color
	match layer:
		Layer.POWER:
			# ضباب الحرب: القوة المعروضة تقدير حسب رؤيتك للدولة
			var p: float = float(Intel.estimate(sim, pid, id, sim.military_power(c), "power")["value"])
			base = pal("SCALE_LO").lerp(pal("POWER_HI"), clampf(log(1.0 + p) / log(1.0 + 60000.0), 0.0, 1.0))
		Layer.ECONOMY:
			base = pal("SCALE_LO").lerp(pal("ECON_HI"), clampf(log(1.0 + float(c["gdp"])) / log(30000.0), 0.0, 1.0))
		Layer.STABILITY:
			if Intel.visibility(sim, pid, id) < 40.0:
				base = pal("SCALE_LO")   # غير معروف
			else:
				base = pal("STAB_LO").lerp(pal("STAB_HI"), float(c["stability"]) / 100.0)
		_:
			if id == pid:
				base = C_PLAYER
			elif c.get("overlord", "") == pid:
				base = C_VASSAL
			elif id in sim.enemies_of(pid):
				base = C_ENEMY.lerp(Color.WHITE, 0.15 * (0.5 + 0.5 * sin(_time * 4.0)))
			elif id in sim.allies(pid):
				base = C_ALLY
			else:
				var r: float = sim.relation(pid, id)
				if r >= 0.0:
					base = pal("REL_NEUTRAL").lerp(pal("REL_GOOD"), r / 100.0)
				else:
					base = pal("REL_NEUTRAL").lerp(pal("REL_BAD"), -r / 100.0)
	if id == selected:
		base = base.lightened(0.25)
	return base


func _draw_capitals() -> void:
	var s := _scale()
	var pid: String = sim.state["player"]
	for id in sim.state["order"]:
		var c: Dictionary = sim.country(id)
		if c.get("annexed", false):
			continue
		var p := map_to_screen(to_map(float(c["lon"]), float(c["lat"])))
		if not Rect2(Vector2(-50, -50), size + Vector2(100, 100)).has_point(p):
			continue
		var col := UI.C_ACCENT_TEXT if id == pid else pal("LABEL")
		if c.get("capital_fallen", false):
			col = C_ENEMY
		# العاصمة نجمة بإطار داكن
		draw_circle(p, 7.5, pal("CHIP"))
		draw_texture_rect(Icons.tex("capital", col, 32), Rect2(p - Vector2(7, 7), Vector2(14, 14)), false)
		if s >= 6.0 or id == pid or id == selected:
			var label: String = c["name_ar"]
			var fs := 14 if s < 10.0 else 16
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			# علم صغير بجانب اسم الدولة
			var ft: Texture2D = Flags.tex(c.get("flag", ""))
			if ft != null:
				var fr := Rect2(p + Vector2(w * 0.5 + 4, -12 - fs + 3), Vector2(fs * 1.2, fs * 0.9))
				draw_rect(fr.grow(1), pal("OUTLINE"))
				draw_texture_rect(ft, fr, false)
			draw_string_outline(_font, p + Vector2(-w * 0.5, -12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, pal("OUTLINE"))
			draw_string(_font, p + Vector2(-w * 0.5, -12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pal("LABEL") if id != pid else UI.C_ACCENT_TEXT)


## مقياس الرسم: طول مرجعي بالكيلومتر عند خط عرض وسط الشاشة
func _draw_scale_bar() -> void:
	var s := _scale()
	var lat := deg_to_rad(90.0 - _center.y)
	var px_per_km := s / (111.0 * maxf(0.2, cos(lat)))
	var km := 100.0
	for opt in [100.0, 250.0, 500.0, 1000.0, 2000.0, 5000.0]:
		km = opt
		if opt * px_per_km >= 70.0:
			break
	var w := km * px_per_km
	var o := Vector2(16, 22)
	draw_rect(Rect2(o - Vector2(6, 16), Vector2(w + 12, 26)), pal("CHIP"))
	draw_line(o, o + Vector2(w, 0), pal("LABEL"), 2.0)
	draw_line(o + Vector2(0, -4), o + Vector2(0, 4), pal("LABEL"), 2.0)
	draw_line(o + Vector2(w, -4), o + Vector2(w, 4), pal("LABEL"), 2.0)
	var label := "%d كم" % int(km)
	draw_string(_font, o + Vector2(w * 0.5 - _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, -4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, pal("LABEL"))


## خط الجبهة الحقيقي: مقاطع بين المناطق المتواجهة، وعلامة سيفين عند مركز الجبهة
func _draw_wars() -> void:
	var pulse := 0.55 + 0.45 * sin(_time * 3.0)
	for w in sim.state["wars"]:
		var A: Array = w["attackers"]
		var D: Array = w["defenders"]
		if _front_day != int(sim.state["day"]):
			_front_day = int(sim.state["day"])
			_front_cache = {}
		var wkey := int(w["id"])
		if not _front_cache.has(wkey):
			_front_cache[wkey] = Divisions.front_regions(sim, A, D)
		var front: Array = _front_cache[wkey]
		var sum := Vector2.ZERO
		var n := 0
		var segs := 0
		for rid in front:
			var pa := map_to_screen(_region_info_center(rid))
			for nb in sim.db.regions[rid]["neighbors"]:
				if not (sim.state["regions"][nb]["owner"] in D):
					continue
				var pb := map_to_screen(_region_info_center(nb))
				var mid := pa.lerp(pb, 0.5)
				# المقطع عمودي على خط الاتصال بين المنطقتين، كحد الجبهة
				var dir := (pb - pa).normalized().orthogonal() * clampf(pa.distance_to(pb) * 0.35, 6.0, 26.0)
				draw_line(mid - dir, mid + dir, Color(C_ENEMY, 0.35 + 0.4 * pulse), 4.0)
				draw_line(mid - dir, mid + dir, pal("OUTLINE"), 1.0)
				sum += mid
				n += 1
				segs += 1
				if segs > 80:
					break
		var marker: Vector2
		if n > 0:
			marker = sum / float(n)
		else:
			# بلا جبهة برية (حرب بحرية): بين العاصمتين
			var ca: Dictionary = sim.country(A[0])
			var cd: Dictionary = sim.country(D[0])
			marker = map_to_screen(to_map(float(ca["lon"]), float(ca["lat"]))).lerp(map_to_screen(to_map(float(cd["lon"]), float(cd["lat"]))), 0.5)
		if Rect2(Vector2(-30, -30), size + Vector2(60, 60)).has_point(marker):
			draw_circle(marker, 13.0, pal("CHIP"))
			draw_arc(marker, 13.0, 0.0, TAU, 28, Color(C_ENEMY, 0.6 + 0.4 * pulse), 2.0)
			draw_texture_rect(Icons.tex("war", C_ENEMY.lightened(0.2), 40), Rect2(marker - Vector2(9, 9), Vector2(18, 18)), false)


func _region_info_center(rid: String) -> Vector2:
	var r: Dictionary = _region_info[rid]
	return to_map(float(r["lon"]), float(r["lat"]))


# ------------------------------------------------------------------ الإدخال: فأرة ولمس

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				if _dragging and _drag_moved < 8.0:
					_click(mb.position)
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		_center -= mm.relative / _scale()
		_clamp_view()
		queue_redraw()
		if _hover_rid != "":
			_hover_rid = ""
			hovered.emit("", Vector2.ZERO)
	elif event is InputEventMouseMotion:
		var mv := event as InputEventMouseMotion
		if mv.position.distance_to(_hover_pos) >= 3.0:
			_hover_pos = mv.position
			var rid := region_at(mv.position)
			_hover_rid = rid
			hovered.emit(rid, mv.position)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_center += pg.delta * 8.0 / _scale()
		_clamp_view()
		queue_redraw()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.size() >= 2 and _touches.has(sd.index):
			# تكبير بإصبعين
			var other := Vector2.ZERO
			for k in _touches:
				if k != sd.index:
					other = _touches[k]
					break
			var old_d := (_touches[sd.index] as Vector2).distance_to(other)
			var new_d := sd.position.distance_to(other)
			if old_d > 1.0:
				_zoom_at((sd.position + other) * 0.5, new_d / old_d)
		_touches[sd.index] = sd.position


func region_at(screen_pos: Vector2) -> String:
	var m := screen_to_map(screen_pos)
	for shape in _regions:
		if not (shape["rect"] as Rect2).has_point(m):
			continue
		for pts in shape["rings"]:
			if Geometry2D.is_point_in_polygon(m, pts):
				return shape["id"]
	return ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_rid != "":
		_hover_rid = ""
		hovered.emit("", Vector2.ZERO)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_map(screen_pos)
	_zoom = clampf(_zoom * factor, 1.0, 40.0)
	var after := screen_to_map(screen_pos)
	_center += before - after
	_clamp_view()
	queue_redraw()


func _clamp_view() -> void:
	_center.x = clampf(_center.x, 0.0, MAP_W)
	_center.y = clampf(_center.y, 0.0, MAP_H)


func _click(screen_pos: Vector2) -> void:
	var m := screen_to_map(screen_pos)
	for shape in _regions:
		if not (shape["rect"] as Rect2).has_point(m):
			continue
		for pts in shape["rings"]:
			if Geometry2D.is_point_in_polygon(m, pts):
				selected_region = shape["id"]
				selected = _owner_of(shape)
				region_selected.emit(selected_region)
				country_selected.emit(selected)
				queue_redraw()
				return
	selected_region = ""
	var hit := ""
	for shape in _shapes:
		if not (shape["rect"] as Rect2).has_point(m):
			continue
		for pts in shape["rings"]:
			if Geometry2D.is_point_in_polygon(m, pts):
				hit = shape["id"]
				break
		if hit != "":
			break
	# إن لم نصب دولة، نختار أقرب عاصمة قريبة
	if (hit == "" or (sim != null and sim.country(hit).is_empty())) and sim != null:
		var best := 30.0
		for id in sim.state["order"]:
			var c: Dictionary = sim.country(id)
			var p := map_to_screen(to_map(float(c["lon"]), float(c["lat"])))
			var d := p.distance_to(screen_pos)
			if d < best:
				best = d
				hit = id
	if hit != "" and sim != null and not sim.country(hit).is_empty():
		selected = hit
		country_selected.emit(hit)
		queue_redraw()
