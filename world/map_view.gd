## خريطة القيادة: خريطة مسطحة تملأ الشاشة، بحدود حقيقية وخطوط جبهة على الحد الفعلي بين المتحاربين،
## ورقائق وحدات واضحة تتحرك بسلاسة على طريقها. التحكم المباشر: المس قواتك ثم المس الوجهة.
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
## لمس رقاقة وحدات: المنطقة والمالك (وإن كانت متحركة: أرقام فرقها)
signal units_tapped(rid: String, owner: String, ids: Array)
## لمس خارج أي منطقة أو دولة
signal empty_tapped

const WORLD_FILE := "res://data/world_110m.json"
const REGIONS_FILE := "res://data/regions.json"
const REGIONS_GEO_FILE := "res://data/regions_geo.json"
const EDGES_FILE := "res://data/region_edges.json"
const MAP_W := 360.0
const MAP_H := 180.0
## مقاس الخط على الخريطة يكبر على الهاتف
static var text_scale := 1.0

enum Layer { POLITICAL, POWER, ECONOMY, STABILITY, RESOURCES, RANGE }

## ألوان الخريطة في الثيمين. المفتاح في الواجهة يقرأ من هنا أيضاً حتى يطابق الخريطة دائماً.
const MAP_PALETTES := {
	"dark": {
		"BG": "0a1018", "GRID": "40739914", "LAND_OFF": "18202a", "BORDER": "9fb6c8b3", "REGION_BORDER": "8cccf21f",
		"PLAYER": "d8ad4a", "ALLY": "3f86c9", "VASSAL": "6a6ff0", "ENEMY": "c9433f", "SELECT": "fffffff2",
		"REL_NEUTRAL": "2f3a46", "REL_GOOD": "36775a", "REL_BAD": "7a3a3a", "SCALE_LO": "2a3340",
		"POWER_HI": "c0392b", "ECON_HI": "27ae60", "STAB_LO": "c0392b", "STAB_HI": "27ae60",
		"RES_NONE": "1d2630", "RES_ENERGY": "d9822b", "RES_MINERAL": "6a7fd1",
		"RANGE_NONE": "1d2630", "RANGE_AIR": "2f5f8f", "RANGE_MIS": "6b3f8f", "RANGE_BOTH": "b0662e",
		"LABEL": "f2f6fa", "LABEL_SOFT": "c9d9e8cc", "OUTLINE": "05090ddd", "CHIP": "0b1118eb",
		"FRONT": "ff4d42", "REACH": "4fa3ff", "PATH": "ffffff",
		"U_MINE": "e3b443", "U_FRIEND": "3f8be0", "U_HOSTILE": "e0463e", "U_NEUTRAL": "5d7684",
		"U_MINE_TEXT": "1b1404", "U_TEXT": "ffffff",
	},
	"light": {
		"BG": "b9d2e6", "GRID": "4a6c8a1c", "LAND_OFF": "e7eaec", "BORDER": "33465acc", "REGION_BORDER": "5a6e8240",
		"PLAYER": "f0c35c", "ALLY": "86b6e6", "VASSAL": "a5a7f2", "ENEMY": "ec7f78", "SELECT": "0d1620f2",
		"REL_NEUTRAL": "e3e7ea", "REL_GOOD": "aed8bf", "REL_BAD": "efb9b5", "SCALE_LO": "e1e6ea",
		"POWER_HI": "d9534f", "ECON_HI": "3aa66b", "STAB_LO": "e0706b", "STAB_HI": "5bb585",
		"RES_NONE": "e6eaee", "RES_ENERGY": "ea9b4c", "RES_MINERAL": "8c9ee0",
		"RANGE_NONE": "e6eaee", "RANGE_AIR": "8fb8e0", "RANGE_MIS": "b49ad6", "RANGE_BOTH": "eba567",
		"LABEL": "111c26", "LABEL_SOFT": "26384acc", "OUTLINE": "ffffffe6", "CHIP": "ffffffee",
		"FRONT": "d7261c", "REACH": "1f6fd1", "PATH": "0d1620",
		"U_MINE": "c9921d", "U_FRIEND": "2369c4", "U_HOSTILE": "cf3027", "U_NEUTRAL": "62717d",
		"U_MINE_TEXT": "ffffff", "U_TEXT": "ffffff",
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

var sim = null:
	set(v):
		sim = v
		_last_sig = ""
		_world_dirty = true
var layer: int = Layer.POLITICAL
var selected: String = ""
var selected_region: String = "":
	set(v):
		selected_region = v
		if _fx != null:
			_redraw_light()
var selected_division: int = -1
## وضع التحريك: الفرق المختارة والمناطق التي تصلها (منطقة -> عدد القفزات)
var move_ids: Array = []
var move_from: String = ""
var move_reach: Dictionary = {}
var preview_target: String = ""

var _range_cache: Dictionary = {}     # منطقة -> 0 لا شيء، 1 طيران، 2 صواريخ، 3 كلاهما
var _range_day: int = -1
var _hover_rid := ""
var _anim_acc := 0.0
var _front_cache := {}     # حرب -> [مقاطع الجبهة الحقيقية]، تُحسب مرة كل يوم
var _front_day := -1
var _marker_cache := {}
var _marker_day := -1
var _hover_pos := Vector2.ZERO
var _path_cache := {}      # فرقة|وصول -> مسار المراكز
var _chip_hits: Array = [] # [Rect2, منطقة، مالك، أرقام الفرق]
var _labels: Array = []    # مستطيلات النصوص المرسومة في هذا الإطار (لمنع التراكب)
var _ping_pos := Vector2.ZERO
var _ping_t := -1.0

var _shapes: Array = []          # الدول غير المقسمة: {id, name_ar, rings, tris, rect}
var _by_id: Dictionary = {}
var _regions: Array = []         # المناطق: {id, country, name_ar, center, rings, tris, rect}
var _region_idx: Dictionary = {}
var _region_info: Dictionary = {}
var _playable: Dictionary = {}
var _edges: Array = []           # {a, b, lines:[PackedVector2Array], rect}
var _edges_of: Dictionary = {}   # منطقة -> [فهارس الحدود]
var _edge_key: Dictionary = {}   # "أ|ب" -> فهرس
var _zoom: float = 1.0
var _center := Vector2(MAP_W * 0.5 + 30.0, MAP_H * 0.5 - 50.0)
var _dragging := false
var _drag_moved := 0.0
var _touches: Dictionary = {}
var _time := 0.0
var _font: Font
var _font_bold: Font

## الأداء: الخريطة ثلاث طبقات. التحريك والتكبير لا يعيدان رسم الأرض، بل يحركانها فقط.
## _world: الأرض والحدود بإحداثيات الخريطة، تُرسم مرة وتُعاد فقط عند تغير الألوان أو تغير التكبير كثيراً.
## _fx: ما ينبض (الجبهات، الوجهات الممكنة، التحديد)، صغير وسريع.
## _over: النصوص والرقائق بإحداثيات الشاشة.
var _world: Node2D
var _grid_node: Node2D
var _chunks: Array = []
const CHUNK_DEG := 30.0
var _fx: Node2D
var _over: Control
var _cv: CanvasItem = self
var _world_dirty := true
var _last_sig := ""
var _world_scale := 0.0
var _world_internal := false
var _world_t := -10.0
var _by_area: Array = []        # المناطق مرتبة بالمساحة (للأسماء)
var _tw_cache := {}             # عرض النصوص المحسوب
var _aff_cache := {}
var _vis_cache := {}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	var fb := FontVariation.new()
	fb.base_font = _font
	fb.variation_embolden = 0.6
	_font_bold = fb
	_load_world()
	_load_regions()
	_load_edges()
	_by_area = _regions.duplicate()
	_by_area.sort_custom(func(a, b): return float(a["area"]) > float(b["area"]))
	_world = Node2D.new()
	add_child(_world)
	_grid_node = Node2D.new()
	_grid_node.draw.connect(_draw_grid_layer)
	_world.add_child(_grid_node)
	_build_chunks()
	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx_layer)
	add_child(_fx)
	_over = Control.new()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over_layer)
	add_child(_over)
	_zoom = 2.2
	resized.connect(func():
		_world_dirty = true
		_apply_view())


## مرّ يوم أو تغيّر شيء: تُعاد ألوان الأرض فقط إن تغيّر ما يؤثر فيها
## (انتقال منطقة، حرب أو سلام، تحالف، أو شهر جديد تتغير فيه العلاقات)
func refresh() -> void:
	var sig := _world_sig()
	if sig != _last_sig:
		_last_sig = sig
		_world_dirty = true
	_fx.queue_redraw()
	_over.queue_redraw()


func _world_sig() -> String:
	if sim == null or sim.state.is_empty():
		return ""
	var w := PackedStringArray()
	for war in sim.state["wars"]:
		w.append(str(int(war["id"])))
	var al := 0
	for aid in sim.state["alliances"]:
		al += sim.state["alliances"][aid]["members"].size() * 31 + aid.length()
	return "%d|%s|%d|%d|%d|%s" % [sim.map_version, ",".join(w), al, int(sim.state["date"]["m"]), layer, sim.state["player"]]


## تغيّر التحديد أو وضع التحريك: الطبقات الخفيفة فقط
func _redraw_light() -> void:
	_fx.queue_redraw()
	_over.queue_redraw()


## تحريك الخريطة أو تكبيرها: نحرك طبقة الأرض المرسومة مسبقاً بدل إعادة رسمها
func _apply_view() -> void:
	if _world == null:
		return
	var s := _scale()
	var offset := size * 0.5 - _center * s
	for n in [_world, _fx]:
		(n as Node2D).position = offset
		(n as Node2D).scale = Vector2(s, s)
	# سماكة الخطوط محسوبة لتكبير معين: إن ابتعدنا عنه كثيراً نعيد رسم الأرض
	if _world_scale <= 0.0 or s / _world_scale > 1.45 or s / _world_scale < 0.7 or (s >= 4.0) != _world_internal:
		_world_dirty = true
	_redraw_light()


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
		var area := 0.0
		for t in shape["rings"]:
			area += absf(_poly_area(t))
		shape["area"] = area
		_region_idx[rid] = _regions.size()
		_regions.append(shape)


## الحدود المشتركة بين المناطق (tools/build_regions.py): الحدود الدولية وخطوط الجبهة تُرسم منها
func _load_edges() -> void:
	var f := FileAccess.open(EDGES_FILE, FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for e in data["edges"]:
		var lines: Array = []
		var rect := Rect2()
		var first := true
		for flat in e[2]:
			var pts := PackedVector2Array()
			for i in range(0, flat.size(), 2):
				pts.append(to_map(float(flat[i]), float(flat[i + 1])))
			lines.append(pts)
			var r := _bounds(pts)
			rect = r if first else rect.merge(r)
			first = false
		var idx := _edges.size()
		_edges.append({"a": e[0], "b": e[1], "lines": lines, "rect": rect.grow(0.05)})
		_edge_key[e[0] + "|" + e[1]] = idx
		for rid in [e[0], e[1]]:
			if not _edges_of.has(rid):
				_edges_of[rid] = []
			_edges_of[rid].append(idx)


static func _poly_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


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


func region_screen(rid: String) -> Vector2:
	return map_to_screen(_region_info_center(rid))


func focus_country(id: String) -> void:
	if sim == null:
		return
	var c: Dictionary = sim.country(id)
	if c.is_empty():
		return
	_center = to_map(float(c["lon"]), float(c["lat"]))
	_zoom = maxf(_zoom, 3.0)
	_clamp_view()
	_apply_view()


func focus_point(lon: float, lat: float) -> void:
	_center = to_map(lon, lat)
	_zoom = maxf(_zoom, 6.0)
	_clamp_view()
	_apply_view()


func set_layer(l: int) -> void:
	layer = l
	_world_dirty = true
	_redraw_light()


## بدء وضع التحريك لفرق في منطقة: نظلل كل وجهة ممكنة
func set_move(ids: Array, from_rid: String) -> void:
	move_ids = ids.duplicate()
	move_from = from_rid
	preview_target = ""
	move_reach = {}
	if sim != null and not ids.is_empty():
		var d: Dictionary = Divisions.find(sim, int(ids[0]))
		if not d.is_empty():
			move_reach = Divisions.reachable(sim, d["owner"], from_rid)
	_redraw_light()


func clear_move() -> void:
	move_ids = []
	move_from = ""
	move_reach = {}
	preview_target = ""
	_redraw_light()


func _process(delta: float) -> void:
	_time += delta
	if sim == null:
		if _world_dirty:
			_rebake()
		return
	# إعادة الرسم للحركة فقط: الجبهات تنبض، والفرق تنزلق، ونبضة اللمس. حتى 30 مرة في الثانية.
	var anim: bool = not sim.state.get("wars", []).is_empty() or not move_ids.is_empty() or _ping_t >= 0.0
	if not anim and Game.is_running() and not Game.paused:
		for d in sim.state.get("divisions", []):
			if int(d["eta"]) >= 0:
				anim = true
				break
	if anim:
		_anim_acc += delta
		if _anim_acc >= 0.033:
			_anim_acc = 0.0
			_redraw_light()
	# الأرض: حين تتغير، وبحد أقصى 4 مرات في الثانية أثناء جريان الوقت
	if _world_dirty and _time - _world_t >= 0.25:
		_world_t = _time
		_rebake()


# ------------------------------------------------------------------ الرسم

func _draw() -> void:
	_cv = self
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)


## طبقة الأرض بإحداثيات الخريطة: كل العالم دفعة واحدة (بلا قص) حتى يُحرَّك بلا إعادة رسم
## إعادة رسم الأرض: كل مربع يرسم نفسه في الإطار التالي
func _rebake() -> void:
	_world_scale = _scale()
	_world_internal = _world_scale >= 4.0
	_world_dirty = false
	_apply_view()
	_grid_node.queue_redraw()
	for ch in _chunks:
		(ch["node"] as Node2D).queue_redraw()


func _draw_grid_layer() -> void:
	_cv = _grid_node
	_draw_grid()
	_cv = self


## مربع من الأرض (30×30 درجة): الدول والمناطق التي يقع مركزها فيه، دفعة واحدة.
## التقسيم يسمح للمحرك بتجاهل ما خارج الشاشة تلقائياً.
func _draw_chunk(i: int) -> void:
	var ch: Dictionary = _chunks[i]
	var node: Node2D = ch["node"]
	_cv = node
	var s := _world_scale
	var bp := PackedVector2Array()
	var bc := PackedColorArray()
	var bi := PackedInt32Array()
	for shape in ch["shapes"]:
		_batch_shape(bp, bc, bi, shape, _fill_color(shape["id"]))
	for shape in ch["regions"]:
		_batch_shape(bp, bc, bi, shape, _region_color(shape))
	if not bi.is_empty():
		RenderingServer.canvas_item_add_triangle_array(node.get_canvas_item(), bi, bp, bc)
	var outl := PackedVector2Array()
	for shape in ch["shapes"]:
		for pts in shape["rings"]:
			_add_segments(outl, pts, true)
	if outl.size() >= 2:
		_cv.draw_multiline(outl, C_BORDER, 1.0 / s)
	_draw_edges(s, ch["edges"])
	_cv = self


func _build_chunks() -> void:
	var cols := int(MAP_W / CHUNK_DEG)
	var rows := int(MAP_H / CHUNK_DEG)
	var idx_of := func(c: Vector2) -> int:
		return clampi(int(c.y / CHUNK_DEG), 0, rows - 1) * cols + clampi(int(c.x / CHUNK_DEG), 0, cols - 1)
	_chunks = []
	for i in cols * rows:
		var node := Node2D.new()
		node.draw.connect(_draw_chunk.bind(i))
		_world.add_child(node)
		_chunks.append({"node": node, "shapes": [], "regions": [], "edges": []})
	for shape in _shapes:
		if not _playable.has(shape["id"]):
			_chunks[idx_of.call((shape["rect"] as Rect2).get_center())]["shapes"].append(shape)
	for shape in _regions:
		_chunks[idx_of.call((shape["rect"] as Rect2).get_center())]["regions"].append(shape)
	for e in _edges:
		_chunks[idx_of.call((e["rect"] as Rect2).get_center())]["edges"].append(e)


func _batch_shape(bp: PackedVector2Array, bc: PackedColorArray, bi: PackedInt32Array, shape: Dictionary, col: Color) -> void:
	for i in shape["rings"].size():
		var pts: PackedVector2Array = shape["rings"][i]
		var tris: PackedInt32Array = shape["tris"][i]
		if tris.size() < 3:
			continue
		var base := bp.size()
		bp.append_array(pts)
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(col)
		bc.append_array(cols)
		for t in tris:
			bi.append(base + t)


## يحول خطاً متصلاً إلى أزواج نقاط حتى تُرسم كل الخطوط المتشابهة بأمر واحد
static func _add_segments(out: PackedVector2Array, pts: PackedVector2Array, closed: bool) -> void:
	var n := pts.size()
	for i in n - 1:
		out.append(pts[i])
		out.append(pts[i + 1])
	if closed and n > 2:
		out.append(pts[n - 1])
		out.append(pts[0])


## الطبقة النابضة بإحداثيات الخريطة: الوجهات الممكنة، وخطوط الجبهة، والتحديد
func _draw_fx_layer() -> void:
	_cv = _fx
	var s := _scale()
	var ci := _fx.get_canvas_item()
	if not move_reach.is_empty():
		var pulse := 0.30 + 0.10 * sin(_time * 5.0)
		for rid in move_reach:
			if rid == move_from:
				continue
			var shape: Dictionary = _regions[_region_idx[rid]]
			_fill_shape(ci, shape, Color(pal("REACH"), pulse))
			_outline(shape, Color(pal("REACH"), 0.8), 1.5 / s)
	_draw_fronts(s)
	if selected_region != "" and _region_idx.has(selected_region):
		var sh: Dictionary = _regions[_region_idx[selected_region]]
		_fill_shape(ci, sh, Color(1, 1, 1, 0.14))
		_outline(sh, pal("OUTLINE"), 5.0 / s)
		_outline(sh, C_SELECT, 2.5 / s)
	_cv = self


## طبقة النصوص والرقائق بإحداثيات الشاشة
func _draw_over_layer() -> void:
	_cv = _over
	if sim != null:
		_labels = []
		_chip_hits = []
		_aff_cache = {}
		_vis_cache = {}
		# الأهم يُرسم أولاً ويحجز مكانه: الوحدات، ثم العواصم، ثم المناطق
		_draw_wars_markers()
		_draw_move_preview()
		_draw_divisions()
		_draw_capitals()
		_draw_facilities()
		_draw_region_labels()
	_draw_ping()
	_draw_scale_bar()
	_cv = self


func _war_pairs() -> Dictionary:
	var at_war := {}
	if sim != null:
		for w in sim.state["wars"]:
			for a in w["attackers"]:
				for d in w["defenders"]:
					at_war[a + "|" + d] = true
					at_war[d + "|" + a] = true
	return at_war


func _draw_edges(s: float, edges: Array) -> void:
	var at_war := _war_pairs()
	var show_internal := s >= 4.0
	var intl_w := clampf(s * 0.09, 1.3, 2.4)
	var internal := PackedVector2Array()
	var former := PackedVector2Array()
	var intl := PackedVector2Array()
	for e in edges:
		var oa: String = _owner_rid(e["a"])
		var ob: String = _owner_rid(e["b"])
		if oa == ob:
			if not show_internal:
				continue
			# حد دولي سابق داخل أرض محتلة يبقى ظاهراً خفيفاً
			var same: bool = _region_info[e["a"]]["country"] == _region_info[e["b"]]["country"]
			for pts in e["lines"]:
				_add_segments(internal if same else former, pts, false)
		elif not at_war.has(oa + "|" + ob):
			for pts in e["lines"]:
				_add_segments(intl, pts, false)
	if internal.size() >= 2:
		_cv.draw_multiline(internal, C_REGION_BORDER, 1.0 / s)
	if former.size() >= 2:
		_cv.draw_multiline(former, Color(C_BORDER, 0.45), 1.0 / s)
	if intl.size() >= 2:
		_cv.draw_multiline(intl, C_BORDER, intl_w / s)


## خطوط الجبهة: الحدود بين متحاربين، تُحسب مرة كل يوم وتنبض بلا إعادة رسم الأرض
func _draw_fronts(s: float) -> void:
	if sim == null or sim.state["wars"].is_empty():
		return
	if _front_day != int(sim.state["day"]) or not _front_cache.has("edges"):
		_front_day = int(sim.state["day"])
		_front_cache = {}
		var at_war := _war_pairs()
		var fe: Array = []
		for e in _edges:
			var oa: String = _owner_rid(e["a"])
			var ob: String = _owner_rid(e["b"])
			if oa != ob and at_war.has(oa + "|" + ob):
				fe.append(e)
		_front_cache["edges"] = fe
	var pulse := 0.6 + 0.4 * sin(_time * 4.0)
	var intl_w := clampf(s * 0.09, 1.3, 2.4)
	for e in _front_cache["edges"]:
		for pts in e["lines"]:
			_cv.draw_polyline(pts, Color(pal("OUTLINE"), 0.9), (intl_w + 4.0) / s)
			_cv.draw_polyline(pts, Color(pal("FRONT"), 0.65 + 0.35 * pulse), (intl_w + 2.0) / s)


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
		_cv.draw_polyline(closed, col, width)


func _owner_of(shape: Dictionary) -> String:
	if sim == null:
		return shape["country"]
	return sim.state["regions"][shape["id"]]["owner"]


func _owner_rid(rid: String) -> String:
	if sim == null:
		return _region_info[rid]["country"]
	return sim.state["regions"][rid]["owner"]


func _region_color(shape: Dictionary) -> Color:
	var own := _owner_of(shape)
	if layer == Layer.RESOURCES:
		return _resource_color(shape)
	if layer == Layer.RANGE:
		return _range_color(shape)
	var col := _fill_color(own)
	if own != shape["country"]:
		# منطقة محتلة: لون المحتل ممزوج بلون صاحبها الأصلي
		col = col.lerp(_fill_color(shape["country"]), 0.3).darkened(0.08)
	return col


func _resource_color(shape: Dictionary) -> Color:
	var res: Dictionary = _region_info[shape["id"]].get("resources", {})
	var energy := float(res.get("oil", 0.0)) + float(res.get("gas", 0.0)) * 0.7
	var other := float(res.get("steel", 0.0)) + float(res.get("rare_earth", 0.0)) + float(res.get("uranium", 0.0))
	var col := pal("RES_NONE")
	col = col.lerp(pal("RES_ENERGY"), clampf(energy / 25.0, 0.0, 1.0))
	col = col.lerp(pal("RES_MINERAL"), clampf(other / 40.0, 0.0, 0.6))
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
		col = C_PLAYER.darkened(0.25)
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


# ------------------------------------------------------------------ النصوص بلا تراكب

func _fs(px: int) -> int:
	return int(round(px * text_scale))


## يحجز مكان نص؛ يرجع false إن كان سيغطي نصاً أهم رُسم قبله
func _claim(r: Rect2) -> bool:
	for o in _labels:
		if (o as Rect2).intersects(r):
			return false
	_labels.append(r)
	return true


## عرض نص بالبكسل، محفوظ حتى لا يُقاس الاسم نفسه كل إطار
func _tw(f: Font, txt: String, fs: int) -> float:
	var key := "%s|%d|%d" % [txt, fs, f.get_instance_id()]
	if not _tw_cache.has(key):
		_tw_cache[key] = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return _tw_cache[key]


func _text(pos_center: Vector2, txt: String, fs: int, col: Color, outline: int = 4, bold: bool = false) -> void:
	var f: Font = _font_bold if bold else _font
	var w := _tw(f, txt, fs)
	var p := pos_center + Vector2(-w * 0.5, fs * 0.35)
	_cv.draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, pal("OUTLINE"))
	_cv.draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# ------------------------------------------------------------------ الوحدات

func _aff(owner: String) -> String:
	if _aff_cache.has(owner):
		return _aff_cache[owner]
	var a := _aff_calc(owner)
	_aff_cache[owner] = a
	return a


func _aff_calc(owner: String) -> String:
	var pid: String = sim.state["player"]
	if owner == pid:
		return "mine"
	if owner in sim.allies(pid) or sim.country(owner).get("overlord", "") == pid:
		return "friend"
	if owner in sim.enemies_of(pid):
		return "hostile"
	return "neutral"


## رقاقة وحدات: لون الانتماء، رمز المشاة القياسي، العدد بخط كبير، وشريط الجاهزية في أسفلها
func _draw_chip(center: Vector2, aff: String, n: int, strength: float, sel: bool, moving: bool) -> Rect2:
	var fs := _fs(14)
	var txt := str(n)
	var tw := _tw(_font_bold, txt, fs)
	var icon_w := float(_fs(18))
	var h := float(_fs(24))
	var w := 8.0 + icon_w + 4.0 + tw + 8.0
	var r := Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h))
	var fill: Color = pal({"mine": "U_MINE", "friend": "U_FRIEND", "hostile": "U_HOSTILE"}.get(aff, "U_NEUTRAL"))
	var ink: Color = pal("U_MINE_TEXT") if aff == "mine" else pal("U_TEXT")
	# ظل وإطار حتى تبرز الرقاقة فوق أي لون للخريطة
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(h * 0.3))
	sb.border_color = pal("OUTLINE") if not sel else C_SELECT
	sb.set_border_width_all(2 if sel else 1)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	sb.anti_aliasing = true
	if moving:
		sb.bg_color = fill.lerp(Color.WHITE, 0.12)
	_cv.draw_style_box(sb, r)
	_cv.draw_texture_rect(Icons.tex("unit", ink, 48), Rect2(r.position + Vector2(8, (h - icon_w) * 0.5), Vector2(icon_w, icon_w)), false)
	_cv.draw_string(_font_bold, Vector2(r.position.x + 8 + icon_w + 4, r.position.y + h * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# الجاهزية: خط في قاعدة الرقاقة
	var bw := w - h * 0.6
	var bp := Vector2(r.position.x + h * 0.3, r.end.y - 3)
	_cv.draw_line(bp, bp + Vector2(bw, 0), Color(0, 0, 0, 0.35), 3.0)
	var sc: Color = UI.C_GOOD if strength >= 0.7 else (UI.C_WARN if strength >= 0.45 else UI.C_BAD)
	_cv.draw_line(bp, bp + Vector2(bw * clampf(strength, 0.0, 1.0), 0), sc.lightened(0.15), 3.0)
	if sel:
		var ring := 0.5 + 0.5 * sin(_time * 6.0)
		_cv.draw_style_box(_ring_box(h, ring), r.grow(3 + ring * 2))
	return r


func _ring_box(h: float, a: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Color(C_SELECT, 0.4 + 0.4 * a)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(h * 0.45))
	sb.anti_aliasing = true
	return sb


## موقع الفرقة المتحركة الآن: على طريقها بين المراكز، حسب الأيام المنقضية وجزء اليوم الحالي
func _moving_pos(d: Dictionary) -> Array:
	var key := "%d|%d" % [int(d["id"]), int(d["eta"])]
	if not _path_cache.has(key):
		var path: Array = Divisions.path(sim, d["owner"], d["region"], d["target"])
		if path.is_empty():
			path = [d["region"], d["target"]]   # نقل بحري: خط مستقيم
		var pts := PackedVector2Array()
		for rid in path:
			pts.append(_region_info_center(rid))
		_path_cache[key] = pts
		if _path_cache.size() > 400:
			_path_cache.clear()
			_path_cache[key] = pts
	var mp: PackedVector2Array = _path_cache[key]
	var eta := int(d["eta"])
	var dep := int(d.get("depart", -1))
	if dep < 0 or dep >= eta:
		dep = eta - maxi(1, mp.size() - 1)
	var t := clampf((float(sim.state["day"]) + Game.day_fraction() - float(dep)) / float(eta - dep), 0.0, 1.0)
	return [_along(mp, t), mp, t]


static func _along(pts: PackedVector2Array, t: float) -> Vector2:
	if pts.size() == 1:
		return pts[0]
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var want := total * t
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if want <= seg or i == pts.size() - 2:
			return pts[i].lerp(pts[i + 1], clampf(want / maxf(seg, 0.0001), 0.0, 1.0))
		want -= seg
	return pts[pts.size() - 1]


func _visible_owner(owner: String, rid: String, mine_regions: Dictionary) -> bool:
	var aff := _aff(owner)
	if aff == "mine" or aff == "friend":
		return true
	# ضباب الحرب: فرق الآخرين تظهر برؤية 40 أو إن كانت ملاصقة لقواتك
	if mine_regions.has(rid):
		return true
	for n in sim.db.regions[rid]["neighbors"]:
		if mine_regions.has(n):
			return true
	if not _vis_cache.has(owner):
		_vis_cache[owner] = Intel.visibility(sim, sim.state["player"], owner) >= 40.0
	return _vis_cache[owner]


func _draw_divisions() -> void:
	var pid: String = sim.state["player"]
	var screen := Rect2(Vector2(-40, -40), size + Vector2(80, 80))
	var mine_regions := {}
	for d in sim.state.get("divisions", []):
		if d["owner"] == pid:
			mine_regions[d["region"]] = true
	# تجميع: الفرق الثابتة رقاقة لكل مالك في كل منطقة، والمتحركة رقاقة لكل رحلة
	var groups := {}
	var order: Array = []
	for d in sim.state.get("divisions", []):
		var owner: String = d["owner"]
		var rid: String = d["region"]
		if not _visible_owner(owner, rid, mine_regions):
			continue
		var moving := int(d["eta"]) >= 0
		var key := ("m|%s|%s|%s|%d" % [owner, rid, d["target"], int(d["eta"])]) if moving else ("s|%s|%s" % [rid, owner])
		if not groups.has(key):
			groups[key] = {"rid": rid, "owner": owner, "n": 0, "str": 0.0, "sel": false, "ids": [], "d": d, "moving": moving}
			order.append(key)
		var g: Dictionary = groups[key]
		g["n"] += 1
		g["str"] += float(d["strength"])
		g["ids"].append(int(d["id"]))
		if int(d["id"]) == selected_division or int(d["id"]) in move_ids:
			g["sel"] = true
	var per_region := {}
	# المتحركة أولاً حتى تبقى ظاهرة فوق الطريق
	for key in order:
		var g: Dictionary = groups[key]
		var aff := _aff(g["owner"])
		var p: Vector2
		if g["moving"]:
			var mv: Array = _moving_pos(g["d"])
			p = map_to_screen(mv[0])
			if aff == "mine" or aff == "friend":
				_draw_route(mv[1], float(mv[2]), aff, int(g["d"]["eta"]) - int(sim.state["day"]))
		else:
			var rid: String = g["rid"]
			var k := int(per_region.get(rid, 0))
			per_region[rid] = k + 1
			# الرقائق في المنطقة نفسها تصطف عمودياً تحت مركزها
			p = region_screen(rid) + Vector2(0, -float(_fs(14)) + k * float(_fs(28)))
		if not screen.has_point(p):
			continue
		var n := int(g["n"])
		var r := _draw_chip(p, aff, n, float(g["str"]) / float(n), g["sel"], g["moving"])
		_labels.append(r.grow(2))
		_chip_hits.append([r.grow(6), g["rid"], g["owner"], g["ids"] if g["moving"] else []])


## طريق الفرقة المتحركة: الجزء المقطوع باهت، والباقي متقطع متحرك، والوجهة دائرة مع الأيام الباقية
func _draw_route(mp: PackedVector2Array, t: float, aff: String, days_left: int) -> void:
	var col: Color = pal("U_MINE") if aff == "mine" else pal("U_FRIEND")
	var pts := PackedVector2Array()
	for m in mp:
		pts.append(map_to_screen(m))
	var cur := map_to_screen(_along(mp, t))
	# الجزء الباقي من الطريق
	var rest := PackedVector2Array([cur])
	var total := 0.0
	for i in mp.size() - 1:
		total += mp[i].distance_to(mp[i + 1])
	var acc := 0.0
	for i in mp.size() - 1:
		acc += mp[i].distance_to(mp[i + 1])
		if acc / maxf(total, 0.0001) > t:
			rest.append(pts[i + 1])
	_dashed(rest, pal("OUTLINE"), 5.0, 10.0, 6.0)
	_dashed(rest, col, 3.0, 10.0, 6.0)
	var dest := pts[pts.size() - 1]
	_cv.draw_circle(dest, 9.0, pal("OUTLINE"))
	_cv.draw_circle(dest, 7.0, col)
	_cv.draw_circle(dest, 3.0, pal("OUTLINE"))
	if days_left >= 0:
		var lbl := "%d ي" % maxi(1, days_left)
		var fs := _fs(12)
		_text(dest + Vector2(0, -float(fs) - 6.0), lbl, fs, col.lightened(0.1) if not UI.light else col.darkened(0.2), 4, true)


## خط متقطع يتحرك باتجاه الوجهة
func _dashed(pts: PackedVector2Array, col: Color, w: float, dash: float, gap: float) -> void:
	var period := dash + gap
	var off := period - fmod(_time * 30.0, period)
	var base := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		if L < 0.5:
			continue
		var dir := (b - a) / L
		var x := 0.0
		while x < L:
			var ph := fmod(base + x + off, period)
			if ph < dash:
				var e := minf(L, x + dash - ph)
				_cv.draw_line(a + dir * x, a + dir * e, col, w, true)
				x = e + 0.01
			else:
				x += period - ph
		base += L


## معاينة الطريق قبل التحريك: من موقع الفرق إلى المنطقة تحت الإصبع أو المؤشر
func _draw_move_preview() -> void:
	if move_ids.is_empty() or move_from == "":
		return
	var p := region_screen(move_from)
	_cv.draw_arc(p, 22.0 + 4.0 * sin(_time * 6.0), 0.0, TAU, 36, pal("REACH"), 2.0, true)
	if preview_target == "" or preview_target == move_from or not move_reach.has(preview_target):
		return
	var d: Dictionary = Divisions.find(sim, int(move_ids[0]))
	if d.is_empty():
		return
	var path: Array = Divisions.path(sim, d["owner"], move_from, preview_target)
	var pts := PackedVector2Array()
	for rid in path:
		pts.append(region_screen(rid))
	if pts.size() < 2:
		return
	_dashed(pts, pal("OUTLINE"), 6.0, 12.0, 6.0)
	_dashed(pts, pal("REACH"), 3.5, 12.0, 6.0)
	var dest := pts[pts.size() - 1]
	var dir := (dest - pts[pts.size() - 2]).normalized()
	var head := PackedVector2Array([dest, dest - dir * 14.0 + dir.orthogonal() * 8.0, dest - dir * 14.0 - dir.orthogonal() * 8.0])
	_cv.draw_colored_polygon(head, pal("REACH"))
	var days := maxi(1, (path.size() - 1) * int(Divisions.cfg(sim)["days_per_hop"]))
	var fs := _fs(14)
	var lbl := "%s · %d يوماً" % [sim.db.regions[preview_target]["name_ar"], days]
	var w := _tw(_font_bold, lbl, fs)
	var box := Rect2(dest + Vector2(-w * 0.5 - 10, -fs - 34), Vector2(w + 20, fs + 14))
	var sb := StyleBoxFlat.new()
	sb.bg_color = pal("REACH")
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	_cv.draw_style_box(sb, box)
	_cv.draw_string(_font_bold, Vector2(box.position.x + 10, box.position.y + fs + 3), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	_labels.append(box)


# ------------------------------------------------------------------ المنشآت والأسماء

func _draw_facilities() -> void:
	var s := _scale()
	var show_all := s >= 70.0 or layer == Layer.RESOURCES
	if s < 9.0 and selected_region == "":
		return
	var screen := Rect2(Vector2(-20, -20), size + Vector2(40, 40))
	var px := float(_fs(18))
	for shape in _regions:
		var rid: String = shape["id"]
		# تفادياً للزحام: كل المنشآت عند الاقتراب الكبير، وإلا منشآت المنطقة المختارة فقط
		if not show_all and rid != selected_region:
			continue
		var fac: Dictionary = _region_info[rid].get("facilities", {})
		if fac.is_empty():
			continue
		var base := map_to_screen(shape["center"]) + Vector2(0, float(_fs(24)))
		if not screen.has_point(base):
			continue
		var dmg: Dictionary = sim.state["regions"][rid].get("damaged", {})
		var w := fac.size() * (px + 4.0)
		var row := Rect2(base - Vector2(w * 0.5, px * 0.5), Vector2(w, px))
		if not _claim(row.grow(1)):
			continue
		var x := row.position.x + px * 0.5 + 2.0
		for t in fac:
			var p := Vector2(x, base.y)
			var col: Color = UI.C_BAD if dmg.has(t) else UI.C_TEXT
			_cv.draw_circle(p, px * 0.5, pal("CHIP"))
			_cv.draw_arc(p, px * 0.5, 0.0, TAU, 20, Color(col, 0.6), 1.2, true)
			_cv.draw_texture_rect(Icons.tex(t, col, 32), Rect2(p - Vector2(px, px) * 0.33, Vector2(px, px) * 0.66), false)
			x += px + 4.0


func _draw_region_labels() -> void:
	var s := _scale()
	if s < 7.0:
		return
	var fs := _fs(12 if s < 20.0 else 14)
	var screen := Rect2(Vector2(-40, -20), size + Vector2(80, 40))
	# الأكبر مساحة أولاً
	var cand: Array = []
	for shape in _by_area:
		var p := map_to_screen(shape["center"])
		if not screen.has_point(p):
			continue
		if sim.db.capitals.get(shape["country"], "") == shape["id"]:
			continue   # العاصمة تُكتب باسم الدولة
		cand.append(shape)
	for shape in cand:
		var label: String = shape["name_ar"]
		var w := _tw(_font, label, fs)
		var rect: Rect2 = shape["rect"]
		# لا نكتب الاسم إن كانت المنطقة أصغر من النص على الشاشة (إلا المختارة)
		if shape["id"] != selected_region and rect.size.x * s < w * 0.8:
			continue
		var p := map_to_screen(shape["center"])
		var r := Rect2(p - Vector2(w * 0.5 + 2, fs * 0.6), Vector2(w + 4, fs * 1.2))
		if not _claim(r):
			continue
		_text(p, label, fs, pal("LABEL_SOFT"), 3)


## خطوط الطول والعرض بإحداثيات الخريطة (داخل طبقة الأرض)
func _draw_grid() -> void:
	for lon in range(-180, 181, 30):
		_cv.draw_line(to_map(lon, 90), to_map(lon, -90), C_GRID, -1.0)
	for lat in range(-90, 91, 30):
		_cv.draw_line(to_map(-180, lat), to_map(180, lat), C_GRID, -1.0)


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
				base = C_ENEMY
			elif id in sim.allies(pid):
				base = C_ALLY
			else:
				var r: float = sim.relation(pid, id)
				if r >= 0.0:
					base = pal("REL_NEUTRAL").lerp(pal("REL_GOOD"), r / 100.0)
				else:
					base = pal("REL_NEUTRAL").lerp(pal("REL_BAD"), -r / 100.0)
	return base


## أسماء الدول عند عواصمها مع العلم، وهي أهم نص على الخريطة بعد الوحدات
func _draw_capitals() -> void:
	var s := _scale()
	var pid: String = sim.state["player"]
	var screen := Rect2(Vector2(-60, -60), size + Vector2(120, 120))
	var ids: Array = sim.state["order"].duplicate()
	# دولتك والمختارة أولاً حتى لا يحجبهما غيرهما
	ids.sort_custom(func(a, b): return int(a == pid or a == selected) > int(b == pid or b == selected))
	for id in ids:
		var c: Dictionary = sim.country(id)
		if c.get("annexed", false):
			continue
		var p := map_to_screen(to_map(float(c["lon"]), float(c["lat"])))
		if not screen.has_point(p):
			continue
		var fallen: bool = c.get("capital_fallen", false)
		var col := pal("LABEL")
		var fs := _fs(13 if s < 6.0 else (15 if s < 14.0 else 17))
		var label: String = c["name_ar"]
		var w := _tw(_font_bold, label, fs)
		var fw := fs * 1.25
		var total := w + fw + 6.0
		var lp := p + Vector2(0, -float(fs) - 4.0)
		var r := Rect2(lp - Vector2(total * 0.5, fs * 0.7), Vector2(total, fs * 1.4))
		# النجمة دائماً، والاسم إن وجد مكاناً
		_cv.draw_circle(p, 5.5, pal("OUTLINE"))
		_cv.draw_texture_rect(Icons.tex("capital", C_ENEMY if fallen else (UI.C_ACCENT if id == pid else pal("LABEL")), 32), Rect2(p - Vector2(5, 5), Vector2(10, 10)), false)
		if not _claim(r):
			continue
		var ft: Texture2D = Flags.tex(c.get("flag", ""))
		var x0 := lp.x + total * 0.5
		if ft != null:
			var fr := Rect2(Vector2(x0 - fw, lp.y - fw * 0.375), Vector2(fw, fw * 0.75))
			_cv.draw_rect(fr.grow(1), pal("OUTLINE"))
			_cv.draw_texture_rect(ft, fr, false)
		_text(Vector2(x0 - fw - 6.0 - w * 0.5, lp.y), label, fs, col, 5, true)


## مقياس الرسم: طول مرجعي بالكيلومتر عند خط عرض وسط الشاشة
func _draw_scale_bar() -> void:
	var s := _scale()
	var lat := deg_to_rad(90.0 - _center.y)
	var px_per_km := s / (111.0 * maxf(0.2, cos(lat)))
	var km := 100.0
	for opt in [100.0, 250.0, 500.0, 1000.0, 2000.0, 5000.0]:
		km = opt
		if opt * px_per_km >= 60.0:
			break
	var w := km * px_per_km
	var o := Vector2(size.x - w - 18.0, size.y * 0.5)
	var fs := _fs(11)
	_cv.draw_line(o, o + Vector2(w, 0), pal("OUTLINE"), 4.0)
	_cv.draw_line(o, o + Vector2(w, 0), pal("LABEL"), 2.0)
	_cv.draw_line(o + Vector2(0, -4), o + Vector2(0, 4), pal("LABEL"), 2.0)
	_cv.draw_line(o + Vector2(w, -4), o + Vector2(w, 4), pal("LABEL"), 2.0)
	_text(o + Vector2(w * 0.5, -fs), "%d كم" % int(km), fs, pal("LABEL"), 3)


## علامة كل حرب عند منتصف جبهتها الحقيقية
func _draw_wars_markers() -> void:
	var pulse := 0.55 + 0.45 * sin(_time * 3.0)
	if _marker_day != int(sim.state["day"]):
		_marker_day = int(sim.state["day"])
		_marker_cache = {}
	for w in sim.state["wars"]:
		var A: Array = w["attackers"]
		var D: Array = w["defenders"]
		var wkey := int(w["id"])
		if not _marker_cache.has(wkey):
			var sum := Vector2.ZERO
			var n := 0
			for rid in Divisions.front_regions(sim, A, D):
				for nb in sim.db.regions[rid]["neighbors"]:
					if sim.state["regions"][nb]["owner"] in D:
						sum += (_region_info_center(rid) + _region_info_center(nb)) * 0.5
						n += 1
			if n > 0:
				_marker_cache[wkey] = sum / float(n)
			else:
				# بلا جبهة برية (حرب بحرية): بين العاصمتين
				var ca: Dictionary = sim.country(A[0])
				var cd: Dictionary = sim.country(D[0])
				_marker_cache[wkey] = to_map(float(ca["lon"]), float(ca["lat"])).lerp(to_map(float(cd["lon"]), float(cd["lat"])), 0.5)
		var marker := map_to_screen(_marker_cache[wkey])
		if Rect2(Vector2(-30, -30), size + Vector2(60, 60)).has_point(marker):
			var rr := float(_fs(14))
			_cv.draw_circle(marker, rr + 2.0, pal("OUTLINE"))
			_cv.draw_circle(marker, rr, pal("FRONT"))
			_cv.draw_arc(marker, rr + 4.0 + pulse * 4.0, 0.0, TAU, 32, Color(pal("FRONT"), 0.6 * (1.0 - pulse)), 2.0, true)
			_cv.draw_texture_rect(Icons.tex("war", Color.WHITE, 40), Rect2(marker - Vector2(rr, rr) * 0.65, Vector2(rr, rr) * 1.3), false)
			_labels.append(Rect2(marker - Vector2(rr, rr), Vector2(rr, rr) * 2.0))


## نبضة عند اللمس: تأكيد بصري فوري أن اللمسة وصلت
func _draw_ping() -> void:
	if _ping_t < 0.0:
		return
	var k := (_time - _ping_t) / 0.35
	if k >= 1.0:
		_ping_t = -1.0
		return
	_cv.draw_arc(_ping_pos, 8.0 + 22.0 * k, 0.0, TAU, 32, Color(C_SELECT, 0.6 * (1.0 - k)), 2.0, true)


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
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not move_ids.is_empty():
			# الزر الأيمن يلغي التحريك (عادة ألعاب الاستراتيجية على الكمبيوتر)
			empty_tapped.emit()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				_zoom_at(mb.position, 1.8)
				return
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				if _dragging and _drag_moved < 16.0:
					_click(mb.position)
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if _touches.size() >= 2:
			return
		_drag_moved += mm.relative.length()
		_center -= mm.relative / _scale()
		_clamp_view()
		_apply_view()
		if _hover_rid != "":
			_hover_rid = ""
			hovered.emit("", Vector2.ZERO)
	elif event is InputEventMouseMotion:
		var mv := event as InputEventMouseMotion
		if mv.position.distance_to(_hover_pos) >= 3.0:
			_hover_pos = mv.position
			var rid := region_at(mv.position)
			if not move_ids.is_empty() and rid != preview_target:
				preview_target = rid
				_redraw_light()
			_hover_rid = rid
			hovered.emit(rid, mv.position)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_center += pg.delta * 8.0 / _scale()
		_clamp_view()
		_apply_view()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() >= 2:
			_drag_moved = 999.0   # إصبعان: تكبير لا لمسة
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
			var mid_old := ((_touches[sd.index] as Vector2) + other) * 0.5
			var mid_new := (sd.position + other) * 0.5
			_center -= (mid_new - mid_old) / _scale()
			_clamp_view()
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
	_zoom = clampf(_zoom * factor, 1.0, 48.0)
	var after := screen_to_map(screen_pos)
	_center += before - after
	_clamp_view()
	_apply_view()


func zoom_by(factor: float) -> void:
	_zoom_at(size * 0.5, factor)


func _clamp_view() -> void:
	_center.x = clampf(_center.x, 0.0, MAP_W)
	_center.y = clampf(_center.y, 10.0, MAP_H - 30.0)


func _click(screen_pos: Vector2) -> void:
	_ping_pos = screen_pos
	_ping_t = _time
	_redraw_light()
	# الوحدات أولاً: هي أصغر هدف وأهمه
	if move_ids.is_empty():
		for i in range(_chip_hits.size() - 1, -1, -1):
			var h: Array = _chip_hits[i]
			if (h[0] as Rect2).has_point(screen_pos):
				units_tapped.emit(h[1], h[2], h[3])
				return
	var rid := region_at(screen_pos)
	if rid != "":
		selected_region = rid
		selected = _owner_rid(rid)
		region_selected.emit(rid)
		country_selected.emit(selected)
		return
	selected_region = ""
	var hit := ""
	var m := screen_to_map(screen_pos)
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
		hit = ""
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
	else:
		empty_tapped.emit()
