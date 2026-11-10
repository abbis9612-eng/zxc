## خريطة القيادة (المرحلة الحالية: خريطة مسطحة ثنائية الأبعاد بطابع غرفة عمليات).
## الكرة الأرضية ثلاثية الأبعاد تأتي في مرحلة لاحقة وتستبدل هذا الملف فقط.
extends Control

const Intel := preload("res://sim/intel.gd")
const Divisions := preload("res://sim/divisions.gd")
const Territory := preload("res://sim/territory.gd")

signal country_selected(id: String)
signal region_selected(rid: String)

const WORLD_FILE := "res://data/world_110m.json"
const REGIONS_FILE := "res://data/regions.json"
const REGIONS_GEO_FILE := "res://data/regions_geo.json"
const C_REGION_BORDER := Color(0.55, 0.8, 0.95, 0.16)
const C_OCCUPIED_LINE := Color(0, 0, 0, 0.35)
const MAP_W := 360.0
const MAP_H := 180.0

enum Layer { POLITICAL, POWER, ECONOMY, STABILITY, RESOURCES, RANGE }

## رموز المنشآت على الخريطة: حرف عربي داخل دائرة ملونة (يعمل مع أي خط)
const FACILITY_MARKS := {
	"airbase": ["ج", Color("5fa8e8")], "port": ["م", Color("3fc1c9")], "factory": ["ص", Color("c9a03f")],
	"refinery": ["ف", Color("e07b39")], "power_plant": ["ك", Color("e8d85f")], "nuclear": ["ن", Color("b05fe8")],
}

const C_BG := Color("0a1018")
const C_GRID := Color(0.25, 0.45, 0.6, 0.10)
const C_LAND_OFF := Color("1a222c")
const C_BORDER := Color(0.35, 0.75, 0.95, 0.35)
const C_PLAYER := Color("e0b84a")
const C_ALLY := Color("3f8fd8")
const C_VASSAL := Color("6a6ff0")
const C_ENEMY := Color("d8423f")
const C_SELECT := Color(1, 1, 1, 0.95)

var sim = null
var layer: int = Layer.POLITICAL
var selected: String = ""
var selected_region: String = ""
var selected_division: int = -1
var _range_cache: Dictionary = {}     # منطقة -> 0 لا شيء، 1 طيران، 2 صواريخ، 3 كلاهما
var _range_day: int = -1

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
	if sim != null and not sim.state.get("wars", []).is_empty():
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
			_outline(shape, Color(1, 1, 1, 0.35), 1.2 / s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if sim != null:
		_draw_region_labels()
		_draw_facilities()
		_draw_wars()
		_draw_divisions()
		_draw_capitals()


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
	var col := Color("1d2630")
	col = col.lerp(Color("d9822b"), clampf(energy / 25.0, 0.0, 1.0))
	col = col.lerp(Color("6a7fd1"), clampf(other / 40.0, 0.0, 0.6))
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
	var col: Color = [Color("1d2630"), Color("2f5f8f"), Color("6b3f8f"), Color("b0662e")][code]
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


## رموز الفرق: مربع عسكري فيه علامة ×، بلون صاحبه، مع سهم الحركة
func _draw_divisions() -> void:
	var pid: String = sim.state["player"]
	var screen := Rect2(Vector2(-30, -30), size + Vector2(60, 60))
	var stack := {}
	var mine_regions: Array = []
	for d in sim.state.get("divisions", []):
		if d["owner"] == pid:
			mine_regions.append(d["region"])
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
		var info: Dictionary = sim.db.regions[rid]
		var base := map_to_screen(to_map(float(info["lon"]), float(info["lat"])))
		var k := int(stack.get(rid, 0))
		stack[rid] = k + 1
		var p := base + Vector2(14 + k * 6, -14 - k * 6)
		if not screen.has_point(p):
			continue
		var col := Color(0.8, 0.8, 0.8)
		if owner == pid:
			col = C_PLAYER
		elif owner in sim.allies(pid) or sim.country(owner).get("overlord", "") == pid:
			col = C_ALLY
		elif owner in sim.enemies_of(pid):
			col = C_ENEMY
		var r := Rect2(p - Vector2(9, 6), Vector2(18, 12))
		draw_rect(r, Color(0, 0, 0, 0.75))
		draw_rect(r, col, false, 1.5)
		draw_line(r.position, r.end, col, 1.2)
		draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), col, 1.2)
		if int(d["id"]) == selected_division:
			draw_rect(r.grow(3), Color.WHITE, false, 1.5)
		# سهم الحركة
		if int(d["eta"]) >= 0 and owner == pid:
			var t: Dictionary = sim.db.regions[d["target"]]
			var tp := map_to_screen(to_map(float(t["lon"]), float(t["lat"])))
			draw_dashed_line(p, tp, col, 1.5, 5.0)
			draw_circle(tp, 3.0, col)


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
		var x := -float(fac.size() - 1) * 9.0
		for t in fac:
			var mark: Array = FACILITY_MARKS.get(t, ["?", Color.WHITE])
			var p := base + Vector2(x, 16)
			var col: Color = Color("e05a55") if dmg.has(t) else mark[1]
			draw_circle(p, 8.0, Color(0, 0, 0, 0.7))
			draw_circle(p, 7.0, col)
			var w := _font.get_string_size(mark[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(_font, p + Vector2(-w * 0.5, 4), mark[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
			x += 18.0


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
		draw_string_outline(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.75))
		draw_string(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.92, 1.0, 0.85))


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
			base = Color("2a3340").lerp(Color("c0392b"), clampf(log(1.0 + p) / log(1.0 + 60000.0), 0.0, 1.0))
		Layer.ECONOMY:
			base = Color("2a3340").lerp(Color("27ae60"), clampf(log(1.0 + float(c["gdp"])) / log(30000.0), 0.0, 1.0))
		Layer.STABILITY:
			if Intel.visibility(sim, pid, id) < 40.0:
				base = Color("2a3340")   # غير معروف
			else:
				base = Color("c0392b").lerp(Color("27ae60"), float(c["stability"]) / 100.0)
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
					base = Color("34404c").lerp(Color("3d8a5a"), r / 100.0)
				else:
					base = Color("34404c").lerp(Color("8a3d3d"), -r / 100.0)
	if id == selected:
		base = base.lightened(0.25)
	return base


func _draw_capitals() -> void:
	var s := _scale()
	var pid: String = sim.state["player"]
	for id in sim.state["order"]:
		var c: Dictionary = sim.country(id)
		var p := map_to_screen(to_map(float(c["lon"]), float(c["lat"])))
		if not Rect2(Vector2(-50, -50), size + Vector2(100, 100)).has_point(p):
			continue
		var col := C_PLAYER if id == pid else Color(0.85, 0.95, 1.0, 0.9)
		if c.get("capital_fallen", false):
			col = C_ENEMY
		draw_circle(p, 3.0, col)
		draw_arc(p, 6.0, 0.0, TAU, 20, Color(col, 0.4), 1.0)
		if s >= 6.0 or id == pid or id == selected:
			var label: String = c["name_ar"]
			var fs := 14 if s < 10.0 else 16
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(_font, p + Vector2(-w * 0.5, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(_font, p + Vector2(-w * 0.5, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))


func _draw_wars() -> void:
	for w in sim.state["wars"]:
		var a: Dictionary = sim.country(w["attackers"][0])
		var d: Dictionary = sim.country(w["defenders"][0])
		var pa := map_to_screen(to_map(float(a["lon"]), float(a["lat"])))
		var pd := map_to_screen(to_map(float(d["lon"]), float(d["lat"])))
		draw_line(pa, pd, Color(C_ENEMY, 0.35), 4.0)
		# نبضة تتحرك من المهاجم إلى المدافع
		var t := fmod(_time * 0.5, 1.0)
		draw_circle(pa.lerp(pd, t), 4.0, C_ENEMY)
		var mid := pa.lerp(pd, 0.5)
		draw_string_outline(_font, mid + Vector2(-8, -6), "⚔", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
		draw_string(_font, mid + Vector2(-8, -6), "⚔", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_ENEMY)


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
