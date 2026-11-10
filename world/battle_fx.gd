## المعركة على الخريطة: تعرض تقرير كل معركة أسبوعية كما حسبته المحاكاة، بلا حساب جديد.
## أسهم الهجوم البري بين المناطق المتواجهة، وطائرات تقلع من قواعد حقيقية إلى أهداف التقرير،
## وصواريخ بأقواس يُعترض بعضها بنسبة الاعتراض، وسفن في المعركة البحرية، وانفجارات،
## ووميض المنطقة التي سقطت بلون المنتصر. الحرائق على المنشآت المضروبة تبقى ما دامت معطلة.
extends RefCounted

const Icons := preload("res://ui/icons.gd")
const Territory := preload("res://sim/territory.gd")
const Divisions := preload("res://sim/divisions.gd")

## أقصى عدد للمؤثرات في وقت واحد (حتى لا يثقل الهاتف في السرعات العالية)
const MAX_FX := 90

var map = null
var fx: Array = []          # {kind, t0, dur, ...}
var _fires: Array = []       # [منطقة، نوع المنشأة]
var _fires_day := -1


func _init(m) -> void:
	map = m


func active() -> bool:
	return not fx.is_empty()


func has_fires() -> bool:
	return not _fires.is_empty()


func _now() -> float:
	return map._time


func _add(e: Dictionary) -> void:
	if fx.size() >= MAX_FX:
		return
	fx.append(e)
	var kind := String(e["kind"])
	# مؤثرات مرافقة: وميض الإطلاق، صاروخ الاعتراض الصاعد للقاء، والدخان الباقي بعد الانفجار
	if kind == "missile":
		fx.append({"kind": "launch", "t0": e["t0"], "dur": 0.6, "p": e["a"]})
		var cut := float(e.get("cut", 1.0))
		if cut < 1.0:
			var meet := _arc_point(e["a"], e["b"], cut, true)
			var idur := 0.45
			fx.append({"kind": "interceptor", "t0": float(e["t0"]) + float(e["dur"]) * cut - idur, "dur": idur, "a": (e["b"] as Vector2) + Vector2(0.15, 0.1), "b": meet})
	elif kind == "boom" and fx.size() < MAX_FX:
		fx.append({"kind": "smoke", "t0": float(e["t0"]) + 0.25, "dur": 2.2, "p": e["p"], "small": e.get("small", false)})


func _center(rid: String) -> Vector2:
	return map._region_info_center(rid)


## لون طرف بالنسبة للاعب: قواتك ذهبية، حلفاؤك زرق، أعداؤك حمر، والبقية رمادية
func _side_color(owner: String) -> Color:
	var aff: String = map._aff(owner)
	return map.pal({"mine": "U_MINE", "friend": "U_FRIEND", "hostile": "U_HOSTILE"}.get(aff, "U_NEUTRAL"))


# ------------------------------------------------------------------ تحويل التقرير إلى مؤثرات

func spawn(r: Dictionary) -> void:
	var sim = map.sim
	if sim == null:
		return
	var A: Array = r.get("attackers", [])
	var D: Array = r.get("defenders", [])
	if A.is_empty() or D.is_empty():
		return
	var t := _now()
	var a_wins: bool = r.get("taken_by_attacker", float(r.get("ratio", 0.5)) >= 0.5)
	var phases: Array = r.get("phases", [])
	var strike: Dictionary = {}
	var sea: Dictionary = {}
	for ph in phases:
		if ph.get("id", "") == "strike":
			strike = ph
		elif ph.get("id", "") == "sea":
			sea = ph
	# 1) الضربات في العمق: طائرة من أقرب قاعدة عاملة، وإلا صاروخ من أقرب أرض
	var k := 0
	for side in [[A, D, r.get("hits_a", [])], [D, A, r.get("hits_d", [])]]:
		for h in side[2]:
			_strike(side[0], String(h["region"]), t + 0.12 * k, k % 2 == 0, false)
			k += 1
	# 2) رشقات صاروخية يُعترض جزء منها بنسبة الاعتراض في التقرير
	if not strike.is_empty():
		var targets_d := _front_targets(D, A)
		var targets_a := _front_targets(A, D)
		var ia := float(strike.get("intercept_d", 0.3))
		var id_ := float(strike.get("intercept_a", 0.3))
		for i in 3:
			if not targets_d.is_empty():
				_strike(A, targets_d[i % targets_d.size()], t + 0.1 + 0.18 * i, false, float(i) / 3.0 < ia)
			if not targets_a.is_empty() and float(strike.get("d", 0.0)) > 0.0 and i < 2:
				_strike(D, targets_a[i % targets_a.size()], t + 0.2 + 0.2 * i, false, float(i) / 2.0 < id_)
	# 3) المعركة البحرية: سفن الطرفين تتقابل قرب ساحل المدافع
	if not sea.is_empty():
		_naval(A, D, float(sea.get("result", 0.0)), t + 0.2)
	# 4) الهجوم البري: أسهم من الرابح نحو الخاسر على الجبهة، والمأخوذ أولاً
	var winners: Array = A if a_wins else D
	var losers: Array = D if a_wins else A
	var pairs: Array = []
	for rid in r.get("taken", []):
		var from := _neighbor_of(String(rid), winners, String(rid))
		if from != "":
			pairs.append([from, String(rid), true])
	if pairs.size() < 3:
		for fr in Divisions.front_regions(sim, winners, losers):
			for nb in sim.db.regions[fr]["neighbors"]:
				if sim.state["regions"][nb]["owner"] in losers:
					pairs.append([String(fr), String(nb), false])
					break
			if pairs.size() >= 3:
				break
	var col := _side_color(winners[0])
	for i in pairs.size():
		var p: Array = pairs[i]
		_add({"kind": "assault", "t0": t + 0.35 + 0.15 * i, "dur": 1.7, "a": _center(p[0]), "b": _center(p[1]), "col": col})
		_add({"kind": "clash", "t0": t + 0.9 + 0.15 * i, "dur": 0.9, "p": _center(p[0]).lerp(_center(p[1]), 0.62)})
	# 5) سقوط المنطقة: وميض بلون المنتصر واسمها
	for rid in r.get("taken", []):
		_add({"kind": "capture", "t0": t + 1.0, "dur": 2.4, "rid": String(rid), "col": col, "name": String(sim.db.regions[rid]["name_ar"])})


## حدث قتال يومي من المحاكاة: طلعة جوية من قاعدة حقيقية، أو رشقة صواريخ يُعترض منها العدد المحسوب
func spawn_event(e: Dictionary) -> void:
	var sim = map.sim
	if sim == null or fx.size() > MAX_FX - 12:
		return
	var from := String(e.get("from", ""))
	var to := String(e.get("to", ""))
	if from == "" or to == "" or from == to or not sim.db.regions.has(from) or not sim.db.regions.has(to):
		return
	var a := _center(from)
	var b := _center(to)
	var col := _side_color(String(e.get("side", "")))
	var t := _now()
	var dur := clampf(a.distance_to(b) / 9.0, 0.8, 1.8)
	match String(e.get("kind", "")):
		"sortie":
			# تشكيل من طائرة إلى ثلاث بحسب عدد الطلعات، وتسقط واحدة إن أُسقط منها شيء
			var n := clampi(1 + int(e.get("n", 1)) / 10, 1, 3)
			var lost := int(e.get("lost", 0))
			for i in n:
				var off := Vector2(0, (float(i) - float(n - 1) * 0.5) * 0.25)
				var shot := i == n - 1 and lost > 0
				_add({"kind": "plane", "t0": t + 0.1 * i, "dur": dur, "a": a + off, "b": b + off, "col": col, "cut": 0.7 if shot else 1.0})
				if shot:
					_add({"kind": "flak", "t0": t + 0.1 * i + dur * 0.7, "dur": 0.5, "p": _arc_point(a + off, b + off, 0.7, false)})
				else:
					_add({"kind": "boom", "t0": t + 0.1 * i + dur, "dur": 0.7, "p": b + off * 0.5, "small": true})
		"salvo":
			# حتى ستة صواريخ مرئية بنسبة الاعتراض الفعلية
			var fired := int(e.get("fired", 1))
			var shown := clampi(fired, 1, 6)
			var icpt := int(roundf(float(shown) * float(e.get("intercepted", 0)) / maxf(1.0, float(fired))))
			for i in shown:
				var jitter := Vector2(sin(i * 2.3), cos(i * 1.7)) * 0.15
				var cut := i < icpt
				_add({"kind": "missile", "t0": t + 0.12 * i, "dur": dur, "a": a, "b": b + jitter, "col": col, "cut": 0.6 if cut else 1.0})
				if cut:
					_add({"kind": "flak", "t0": t + 0.12 * i + dur * 0.6, "dur": 0.5, "p": _arc_point(a, b + jitter, 0.6, true)})
				else:
					_add({"kind": "boom", "t0": t + 0.12 * i + dur, "dur": 0.8, "p": b + jitter})


## ضربة واحدة: طائرة من قاعدة عاملة، أو صاروخ بقوس من أرض المطلق. intercepted: تنفجر في الجو
func _strike(side: Array, target: String, t0: float, prefer_air: bool, intercepted: bool) -> void:
	var sim = map.sim
	var tp := _center(target)
	var origin := ""
	var kind := "missile"
	if prefer_air:
		origin = _nearest(Territory.working_facilities(sim, side, "airbase"), tp)
		if origin != "":
			kind = "plane"
	if origin == "":
		var land: Array = []
		for id in side:
			land += Territory.owned(sim, id)
		origin = _nearest(land, tp)
	if origin == "" or origin == target:
		return
	var a := _center(origin)
	var dur := clampf(a.distance_to(tp) / 9.0, 0.8, 1.8)
	_add({"kind": kind, "t0": t0, "dur": dur, "a": a, "b": tp, "col": _side_color(side[0]), "cut": 0.55 if intercepted else 1.0})
	if intercepted:
		_add({"kind": "flak", "t0": t0 + dur * 0.55, "dur": 0.5, "p": _arc_point(a, tp, 0.55, kind == "missile")})
	else:
		_add({"kind": "boom", "t0": t0 + dur, "dur": 0.8, "p": tp})


## أهداف الرشقات: مناطق الطرف الآخر على الجبهة، وإلا عاصمته
func _front_targets(side: Array, enemies: Array) -> Array:
	var sim = map.sim
	var out: Array = []
	for fr in Divisions.front_regions(sim, side, enemies):
		out.append(String(fr))
		if out.size() >= 3:
			break
	if out.is_empty():
		var cap: String = Territory.capital_region(sim, side[0])
		if sim.state["regions"].has(cap):
			out.append(cap)
	return out


func _naval(A: Array, D: Array, result: float, t0: float) -> void:
	var sim = map.sim
	var coast := ""
	var cap_a: Vector2 = _center(Territory.capital_region(sim, A[0]))
	var best := INF
	for id in D:
		for rid in Territory.owned(sim, id):
			if sim.db.regions[rid].get("coastal", false):
				var d := _center(rid).distance_to(cap_a)
				if d < best:
					best = d
					coast = rid
	if coast == "":
		return
	var c := _center(coast)
	# نحو البحر: من مركز أرض المدافع إلى ساحله ثم أبعد
	var land_c := Vector2.ZERO
	var n := 0
	for rid in Territory.owned(sim, D[0]):
		land_c += _center(rid)
		n += 1
	land_c /= maxf(1.0, float(n))
	var dir := (c - land_c).normalized()
	if dir == Vector2.ZERO:
		dir = (cap_a - c).normalized()
	var a_pos := c + dir * 3.0
	var d_pos := c + dir * 1.3
	var side_off := dir.orthogonal() * 0.7
	for i in 2:
		var off := side_off * (float(i) - 0.5)
		_add({"kind": "ship", "t0": t0 + 0.1 * i, "dur": 2.0, "a": a_pos + off, "b": a_pos.lerp(d_pos, 0.45) + off, "col": _side_color(A[0])})
		_add({"kind": "ship", "t0": t0 + 0.1 * i, "dur": 2.0, "a": d_pos + off, "b": d_pos.lerp(a_pos, 0.2) + off, "col": _side_color(D[0])})
	# الخاسر في البحر يتلقى الانفجارات
	var hit := d_pos if result >= 0.0 else a_pos
	for i in 3:
		_add({"kind": "boom", "t0": t0 + 0.7 + 0.3 * i, "dur": 0.6, "p": hit + side_off * (float(i) - 1.0) * 0.6, "small": true})


func _nearest(rids: Array, to: Vector2) -> String:
	var best := ""
	var bd := INF
	for rid in rids:
		var d := _center(String(rid)).distance_to(to)
		if d < bd:
			bd = d
			best = String(rid)
	return best


func _neighbor_of(rid: String, owners: Array, exclude: String) -> String:
	var sim = map.sim
	for nb in sim.db.regions[rid]["neighbors"]:
		if nb != exclude and sim.state["regions"][nb]["owner"] in owners:
			return String(nb)
	return ""


# ------------------------------------------------------------------ الرسم

## نقطة على مسار الضربة (بإحداثيات الخريطة): الصاروخ بقوس، والطائرة بخط شبه مستقيم
static func _arc_point(a: Vector2, b: Vector2, t: float, arc: bool) -> Vector2:
	var p := a.lerp(b, t)
	var h := a.distance_to(b) * (0.28 if arc else 0.06)
	return p + Vector2(0, -h * 4.0 * t * (1.0 - t))


func cleanup() -> void:
	var now := _now()
	var keep: Array = []
	for e in fx:
		if now < float(e["t0"]) + float(e["dur"]):
			keep.append(e)
	fx = keep


## تحت الرقائق: أسهم الهجوم
func draw_ground(cv: CanvasItem) -> void:
	var now := _now()
	var s: float = map._scale()
	for e in fx:
		if e["kind"] != "assault":
			continue
		var k := (now - float(e["t0"])) / float(e["dur"])
		if k < 0.0 or k > 1.0:
			continue
		var a0: Vector2 = map.map_to_screen(e["a"])
		var b0: Vector2 = map.map_to_screen(e["b"])
		# السهم يعبر الحد بين المنطقتين بطول ثابت يُرى مهما صغرت المحافظات
		var mid := a0.lerp(b0, 0.5)
		var d0 := (b0 - a0).normalized()
		if d0 == Vector2.ZERO:
			continue
		var L := maxf(a0.distance_to(b0) * 0.9, 74.0 * map.text_scale)
		var a := mid - d0 * L * 0.55
		var b := mid + d0 * L * 0.45
		var grow := clampf(k / 0.45, 0.0, 1.0)
		var fade := clampf((1.0 - k) / 0.25, 0.0, 1.0)
		var tip := a.lerp(b, 0.25 + 0.75 * grow)
		var base := a
		var col: Color = e["col"]
		var w := clampf(s * 0.35, 5.0, 11.0)
		var dir := (tip - base).normalized()
		if (tip - base).length() < 4.0:
			continue
		var head := w * 2.1
		var shaft_end := tip - dir * head * 0.8
		cv.draw_line(base, shaft_end, Color(map.pal("OUTLINE"), 0.85 * fade), w + 4.0, true)
		cv.draw_line(base, shaft_end, Color(col, 0.92 * fade), w, true)
		var n := dir.orthogonal()
		var tri := PackedVector2Array([tip + dir * 2.0, shaft_end + n * head * 0.75, shaft_end - n * head * 0.75])
		var tri_o := PackedVector2Array([tip + dir * 5.0, shaft_end + n * (head * 0.75 + 3.0) - dir * 2.0, shaft_end - n * (head * 0.75 + 3.0) - dir * 2.0])
		cv.draw_colored_polygon(tri_o, Color(map.pal("OUTLINE"), 0.85 * fade))
		cv.draw_colored_polygon(tri, Color(col, 0.95 * fade))


## فوق الرقائق: الطائرات والصواريخ والسفن والانفجارات
func draw_air(cv: CanvasItem) -> void:
	var now := _now()
	var s: float = map._scale()
	var ts: float = map.text_scale
	for e in fx:
		var k := (now - float(e["t0"])) / float(e["dur"])
		if k < 0.0 or k > 1.0:
			continue
		match String(e["kind"]):
			"plane", "missile":
				var cut := float(e.get("cut", 1.0))
				if k > cut:
					continue
				var arc: bool = e["kind"] == "missile"
				var p: Vector2 = map.map_to_screen(_arc_point(e["a"], e["b"], k, arc))
				var prev: Vector2 = map.map_to_screen(_arc_point(e["a"], e["b"], maxf(0.0, k - 0.03), arc))
				var dir := (p - prev).normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.RIGHT
				var zs := ts * clampf(s / 8.0, 0.75, 1.6)
				if arc:
					# دخان كثيف يتلاشى خلف الصاروخ
					for i in range(10, 0, -1):
						var tt := maxf(0.0, k - 0.02 * float(i))
						var sp: Vector2 = map.map_to_screen(_arc_point(e["a"], e["b"], tt, true))
						var fade := 1.0 - float(i) / 10.0
						cv.draw_circle(sp, (2.0 + float(i) * 0.7) * zs, Color(0.82, 0.82, 0.82, 0.35 * fade))
					_draw_missile(cv, p, dir, zs, e["col"], now)
				else:
					# خطا تكثف خلف المحركين
					var tr: Vector2 = map.map_to_screen(_arc_point(e["a"], e["b"], maxf(0.0, k - 0.12), false))
					var n := dir.orthogonal()
					for sgn in [-1.0, 1.0]:
						cv.draw_line(tr + n * 3.0 * zs * sgn, p - dir * 6.0 * zs + n * 3.0 * zs * sgn, Color(1, 1, 1, 0.45), 1.6 * zs, true)
					_draw_jet(cv, p, dir, zs, e["col"])
			"interceptor":
				var p6: Vector2 = map.map_to_screen((e["a"] as Vector2).lerp(e["b"], k))
				var pr6: Vector2 = map.map_to_screen((e["a"] as Vector2).lerp(e["b"], maxf(0.0, k - 0.15)))
				var d6 := (p6 - pr6).normalized()
				if d6 == Vector2.ZERO:
					d6 = Vector2.UP
				cv.draw_line(pr6, p6, Color(0.9, 0.95, 1.0, 0.7), 2.0 * ts, true)
				_draw_missile(cv, p6, d6, ts * 0.7, Color(0.75, 0.88, 1.0), now)
			"launch":
				var p7: Vector2 = map.map_to_screen(e["p"])
				var a7 := 1.0 - k
				cv.draw_circle(p7, (6.0 + 10.0 * k) * ts, Color(1.0, 0.85, 0.4, 0.55 * a7))
				cv.draw_arc(p7, (8.0 + 18.0 * k) * ts, 0.0, TAU, 24, Color(0.9, 0.9, 0.9, 0.5 * a7), 2.5 * ts, true)
			"smoke":
				var p8: Vector2 = map.map_to_screen(e["p"])
				var r8 := (8.0 if e.get("small", false) else 14.0) * ts
				for i in 4:
					var ang := float(i) * 1.7
					var off := Vector2(cos(ang), sin(ang)) * r8 * 0.5 * (0.5 + k) + Vector2(0, -r8 * 1.4 * k)
					cv.draw_circle(p8 + off, r8 * (0.6 + 0.6 * k), Color(0.35, 0.35, 0.35, 0.35 * (1.0 - k)))
			"ship":
				var p2: Vector2 = map.map_to_screen((e["a"] as Vector2).lerp(e["b"], k))
				var sz2 := 26.0 * ts
				# موجة خلف السفينة ثم السفينة بإطار داكن
				var bs: Vector2 = map.map_to_screen((e["a"] as Vector2).lerp(e["b"], maxf(0.0, k - 0.12)))
				cv.draw_line(bs, p2, Color(1, 1, 1, 0.5), 3.0 * ts, true)
				cv.draw_texture_rect(Icons.tex("ship", map.pal("OUTLINE"), 64), Rect2(p2 - Vector2(sz2, sz2) * 0.5 + Vector2(1.5, 1.5), Vector2(sz2, sz2)), false)
				cv.draw_texture_rect(Icons.tex("ship", e["col"], 64), Rect2(p2 - Vector2(sz2, sz2) * 0.5, Vector2(sz2, sz2)), false)
				# وميض المدافع
				if fmod(now * 3.0 + float(e["t0"]), 1.0) < 0.15:
					cv.draw_circle(p2 + Vector2(sz2 * 0.4, -sz2 * 0.3), 3.5 * ts, Color(1.0, 0.9, 0.4))
			"boom":
				_explosion(cv, map.map_to_screen(e["p"]), k, (12.0 if e.get("small", false) else 20.0) * ts)
			"clash":
				var p3: Vector2 = map.map_to_screen(e["p"])
				for i in 3:
					var kk := clampf(k * 1.4 - 0.2 * i, 0.0, 1.0)
					if kk > 0.0 and kk < 1.0:
						_explosion(cv, p3 + Vector2(cos(i * 2.1), sin(i * 2.1)) * 9.0 * ts, kk, 10.0 * ts)
			"flak":
				# اعتراض في الجو: وميض أبيض وشظايا وحلقة
				var p4: Vector2 = map.map_to_screen(e["p"])
				var a4 := 1.0 - k
				cv.draw_circle(p4, (5.0 + 8.0 * k) * ts, Color(1.0, 0.95, 0.75, 0.6 * a4))
				cv.draw_arc(p4, (4.0 + 16.0 * k) * ts, 0.0, TAU, 24, Color(0.75, 0.88, 1.0, a4), 2.0, true)
				for i in 8:
					var ang4 := float(i) * TAU / 8.0 + 0.3
					var d4 := Vector2(cos(ang4), sin(ang4))
					cv.draw_line(p4 + d4 * 6.0 * k * ts, p4 + d4 * (8.0 + 14.0 * k) * ts, Color(1.0, 0.8, 0.4, a4), 1.5, true)
			"capture":
				var p5: Vector2 = map.region_screen(e["rid"])
				var a := clampf(1.0 - k, 0.0, 1.0)
				var txt := "سقطت %s" % e["name"]
				var fs := int(15 * ts)
				var w: float = map._font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var y := -34.0 * ts - 16.0 * k
				var box := Rect2(p5 + Vector2(-w * 0.5 - 10, y - fs), Vector2(w + 20, fs + 12))
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(e["col"], 0.95 * a)
				sb.set_corner_radius_all(8)
				cv.draw_style_box(sb, box)
				cv.draw_string(map._font_bold, Vector2(box.position.x + 10, box.position.y + fs + 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))


## صاروخ: جسم ورأس وزعانف ولهب يرتجف
static func _draw_missile(cv: CanvasItem, p: Vector2, dir: Vector2, z: float, col: Color, now: float) -> void:
	var n := dir.orthogonal()
	var L := 11.0 * z
	var W := 2.2 * z
	var tail := p - dir * L
	var flick := 0.75 + 0.25 * sin(now * 40.0)
	cv.draw_colored_polygon(PackedVector2Array([tail - dir * 7.0 * z * flick, tail + n * W * 1.1, tail - n * W * 1.1]), Color(1.0, 0.55, 0.1, 0.9))
	cv.draw_colored_polygon(PackedVector2Array([tail - dir * 4.0 * z * flick, tail + n * W * 0.6, tail - n * W * 0.6]), Color(1.0, 0.95, 0.6))
	var body := PackedVector2Array([p + n * W, p - n * W, tail - n * W, tail + n * W])
	cv.draw_colored_polygon(body, Color(0.92, 0.92, 0.9))
	cv.draw_colored_polygon(PackedVector2Array([p + n * W, p + dir * 4.5 * z, p - n * W]), col)
	cv.draw_colored_polygon(PackedVector2Array([tail + n * W, tail + n * W * 2.6 - dir * 1.5 * z, tail + dir * 3.0 * z + n * W]), col.darkened(0.2))
	cv.draw_colored_polygon(PackedVector2Array([tail - n * W, tail - n * W * 2.6 - dir * 1.5 * z, tail + dir * 3.0 * z - n * W]), col.darkened(0.2))


## مقاتلة: جسم وجناحان مائلان وذيل، بلون صاحبها وظل تحتها
static func _draw_jet(cv: CanvasItem, p: Vector2, dir: Vector2, z: float, col: Color) -> void:
	var n := dir.orthogonal()
	var pts := PackedVector2Array([
		p + dir * 9.0 * z,
		p + dir * 2.0 * z + n * 1.4 * z,
		p - dir * 1.0 * z + n * 8.0 * z,
		p - dir * 3.0 * z + n * 8.0 * z,
		p - dir * 3.0 * z + n * 1.6 * z,
		p - dir * 7.0 * z + n * 4.0 * z,
		p - dir * 8.5 * z + n * 4.0 * z,
		p - dir * 8.0 * z,
		p - dir * 8.5 * z - n * 4.0 * z,
		p - dir * 7.0 * z - n * 4.0 * z,
		p - dir * 3.0 * z - n * 1.6 * z,
		p - dir * 3.0 * z - n * 8.0 * z,
		p - dir * 1.0 * z - n * 8.0 * z,
		p + dir * 2.0 * z - n * 1.4 * z,
	])
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(3.0, 5.0) * z)
	cv.draw_colored_polygon(shadow, Color(0, 0, 0, 0.25))
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	cv.draw_colored_polygon(pts, col)
	cv.draw_polyline(outline, Color(0.05, 0.05, 0.05, 0.8), 1.2, true)
	cv.draw_circle(p + dir * 4.0 * z, 1.3 * z, Color(0.7, 0.9, 1.0))


static func _explosion(cv: CanvasItem, p: Vector2, k: float, r: float) -> void:
	var a := 1.0 - k
	# موجة ضغط تتسع
	cv.draw_arc(p, r * (0.5 + 1.6 * k), 0.0, TAU, 28, Color(1.0, 0.9, 0.7, 0.55 * a), 2.0, true)
	cv.draw_circle(p, r * (0.4 + 0.9 * k), Color(1.0, 0.45, 0.1, 0.45 * a))
	cv.draw_circle(p, r * (0.3 + 0.5 * k), Color(1.0, 0.75, 0.2, 0.8 * a))
	cv.draw_circle(p, r * 0.25 * (1.0 - k), Color(1, 1, 0.9, a))
	for i in 6:
		var ang := float(i) * TAU / 6.0 + 0.4
		var d := Vector2(cos(ang), sin(ang))
		cv.draw_line(p + d * r * (0.3 + 0.6 * k), p + d * r * (0.5 + 0.9 * k), Color(1.0, 0.6, 0.2, a), 2.0, true)


## بإحداثيات الخريطة (طبقة النبض): وميض المنطقة التي سقطت بلون المنتصر
func draw_capture_fill(ci: RID) -> void:
	var now := _now()
	for e in fx:
		if e["kind"] != "capture":
			continue
		var k := (now - float(e["t0"])) / float(e["dur"])
		if k < 0.0 or k > 1.0 or not map._region_idx.has(e["rid"]):
			continue
		var pulse := 0.5 + 0.5 * sin(k * TAU * 2.0)
		map._fill_shape(ci, map._regions[map._region_idx[e["rid"]]], Color(e["col"], (0.25 + 0.35 * pulse) * (1.0 - k)))


# ------------------------------------------------------------------ الحرائق المستمرة

func _rebuild_fires() -> void:
	var sim = map.sim
	_fires_day = int(sim.state["day"])
	_fires = []
	for rid in sim.db.region_ids:
		var dmg: Dictionary = sim.state["regions"][rid].get("damaged", {})
		for t in dmg:
			_fires.append([rid, String(t)])
			break


## لهب صغير يرتجف فوق كل منطقة فيها منشأة معطلة بالضربات
func draw_fires(cv: CanvasItem) -> void:
	if map.sim == null:
		return
	if _fires_day != int(map.sim.state["day"]):
		_rebuild_fires()
	if _fires.is_empty():
		return
	var ts: float = map.text_scale
	var screen := Rect2(Vector2(-30, -30), map.size + Vector2(60, 60))
	var now := _now()
	for f in _fires:
		var p: Vector2 = map.region_screen(f[0]) + Vector2(14.0, 10.0) * ts
		if not screen.has_point(p):
			continue
		var ph := float(hash(f[0]) % 100) / 100.0 * TAU
		var fl := 0.8 + 0.2 * sin(now * 9.0 + ph)
		var h := 13.0 * ts * fl
		cv.draw_circle(p + Vector2(0, -h * 1.15), 3.5 * ts, Color(0.25, 0.25, 0.25, 0.35))
		var outer := PackedVector2Array([p + Vector2(-6, 0) * ts, p + Vector2(0, -h), p + Vector2(6, 0) * ts])
		var inner := PackedVector2Array([p + Vector2(-3, 0) * ts, p + Vector2(0, -h * 0.6), p + Vector2(3, 0) * ts])
		cv.draw_colored_polygon(outer, Color(0.95, 0.35, 0.1, 0.9))
		cv.draw_colored_polygon(inner, Color(1.0, 0.85, 0.25, 0.95))
