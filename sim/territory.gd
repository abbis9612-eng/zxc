## المناطق والاحتلال والمنشآت: كل دولة مقسمة إلى مناطقها الإدارية الحقيقية.
## الناتج والسكان والموارد والمنشآت تُحسب من مجموع المناطق التي تسيطر عليها الدولة،
## والحرب تتقدم منطقة بمنطقة على الجبهات بين المناطق المتجاورة.
extends RefCounted

const INTEGRATION_MONTHS := 12.0     # أشهر حتى تنتج المنطقة المحتلة بكامل طاقتها لمحتلها
const OCCUPIED_START_EFF := 0.3
const CAPTURE_LOYALTY := 10.0
const CAPITAL_MIN_DOMINANCE := 0.3   # اقتحام العاصمة يحتاج تفوقاً واضحاً في المعركة
const CAPITAL_CAPTURE_CHANCE := 0.35
const FACILITY_TYPES := ["airbase", "port", "factory", "refinery", "power_plant", "nuclear"]
const FACILITY_NAMES := {
	"airbase": "قاعدة جوية", "port": "ميناء", "factory": "مصنع حربي",
	"refinery": "مصفاة", "power_plant": "محطة كهرباء", "nuclear": "منشأة نووية",
}
const RESOURCE_NAMES := {"oil": "النفط", "gas": "الغاز", "steel": "الصلب", "rare_earth": "معادن نادرة", "uranium": "اليورانيوم", "food": "الغذاء"}

const Logistics := preload("res://sim/logistics.gd")


# ------------------------------------------------------------------ الإعداد

static func init_state(sim) -> void:
	var regions := {}
	for rid in sim.db.region_ids:
		var info: Dictionary = sim.db.regions[rid]
		var c: Dictionary = sim.country(info["country"])
		regions[rid] = {
			"owner": info["country"], "core": info["country"],
			"gdp": float(c["gdp"]) * float(info["gdp_share"]),
			"pop": float(c["population"]) * float(info["pop_share"]),
			"loyalty": 100.0, "occupied_months": 0,
			"damaged": {},     # نوع المنشأة -> أشهر متبقية للإصلاح
		}
	sim.state["regions"] = regions
	recompute_all(sim)


# ------------------------------------------------------------------ أدوات

static func region(sim, rid: String) -> Dictionary:
	return sim.state["regions"].get(rid, {})


static func owned(sim, id: String) -> Array:
	var out: Array = []
	for rid in sim.db.region_ids:
		if sim.state["regions"][rid]["owner"] == id:
			out.append(rid)
	return out


static func core_regions(id: String, db) -> Array:
	return db.regions_by_country.get(id, [])


static func occupied_count(sim, id: String) -> int:
	return int(sim.country(id).get("occupied_regions", 0))


## إنتاجية المنطقة لمالكها: المحتلة حديثاً تنتج أقل حتى تندمج
static func efficiency(r: Dictionary) -> float:
	if r["owner"] == r["core"]:
		return 1.0
	return OCCUPIED_START_EFF + (1.0 - OCCUPIED_START_EFF) * minf(1.0, float(r["occupied_months"]) / INTEGRATION_MONTHS)


## عدد منشآت نوع معين في منطقة، والعامل منها
static func facility_count(sim, rid: String, ftype: String) -> int:
	var base := int(sim.db.regions[rid].get("facilities", {}).get(ftype, 0))
	return base + int(sim.state["regions"][rid].get("built", {}).get(ftype, 0))


static func add_facility(sim, rid: String, ftype: String) -> void:
	var r: Dictionary = sim.state["regions"][rid]
	if not r.has("built"):
		r["built"] = {}
	r["built"][ftype] = int(r["built"].get(ftype, 0)) + 1
	sim._fac_cache = {}
	recompute(sim, r["owner"])


## نقل كل أرض دولة إلى أخرى بلا تخريب حرب: الاتحاد السلمي
static func transfer_all(sim, from_id: String, to_id: String) -> void:
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		if r["owner"] != from_id:
			continue
		r["owner"] = to_id
		r["occupied_months"] = 0
		r["loyalty"] = 80.0
	recompute(sim, from_id)
	recompute(sim, to_id)
	sim.mark_borders_dirty()


static func facility_working(sim, rid: String, ftype: String) -> bool:
	return not sim.state["regions"][rid].get("damaged", {}).has(ftype)


## يعيد حساب كل الدول في مرور واحد على المناطق (سريع)
static func recompute_all(sim) -> void:
	var acc := {}
	for id in sim.state["order"]:
		acc[id] = _empty_acc()
	_accumulate(sim, acc)
	for id in acc:
		_apply_acc(sim, id, acc[id])


static func recompute(sim, id: String) -> void:
	if sim.country(id).is_empty():
		return
	var acc := {id: _empty_acc()}
	_accumulate(sim, acc)
	_apply_acc(sim, id, acc[id])


static func _empty_acc() -> Dictionary:
	var fac := {}
	for t in FACILITY_TYPES:
		fac[t] = {"total": 0, "working": 0}
	return {"gdp": 0.0, "pop": 0.0, "occ": 0, "res": {"oil": 0.0, "gas": 0.0, "steel": 0.0, "rare_earth": 0.0, "uranium": 0.0, "food": 0.0}, "fac": fac}


static func _accumulate(sim, acc: Dictionary) -> void:
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		var own: String = r["owner"]
		if not acc.has(own):
			continue
		var a: Dictionary = acc[own]
		var eff := efficiency(r)
		a["gdp"] += float(r["gdp"]) * eff
		a["pop"] += float(r["pop"])
		if own != r["core"]:
			a["occ"] += 1
		var info: Dictionary = sim.db.regions[rid]
		var res: Dictionary = info.get("resources", {})
		for k in res:
			a["res"][k] += float(res[k]) * eff
		var fac: Dictionary = info.get("facilities", {})
		var dmg: Dictionary = r.get("damaged", {})
		if not fac.is_empty():
			for t in fac:
				var n := int(fac[t])
				a["fac"][t]["total"] += n
				if not dmg.has(t):
					a["fac"][t]["working"] += n
		var built: Dictionary = r.get("built", {})
		for t in built:
			var extra := int(built[t])
			if extra <= 0 or not a["fac"].has(t):
				continue
			a["fac"][t]["total"] += extra
			if not dmg.has(t):
				a["fac"][t]["working"] += extra


static func _apply_acc(sim, id: String, a: Dictionary) -> void:
	var c: Dictionary = sim.country(id)
	c["gdp"] = maxf(0.5, float(a["gdp"]))
	c["population"] = maxf(0.05, float(a["pop"]))
	c["occupied_regions"] = a["occ"]
	for k in a["res"]:
		a["res"][k] = snappedf(float(a["res"][k]), 0.01)
	c["resources"] = a["res"]
	c["facilities"] = a["fac"]
	c["logistics"] = Logistics.compute(sim, c)


## النمو الشهري لكل الدول في مرور واحد
static func grow_all(sim, growth_by_id: Dictionary, pop_by_id: Dictionary = {}) -> void:
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		var own: String = r["owner"]
		var g: float = growth_by_id.get(own, 0.0)
		r["gdp"] = maxf(0.001, float(r["gdp"]) * (1.0 + g / 1200.0))
		var pg: float = pop_by_id.get(own, 0.0)
		r["pop"] = maxf(0.001, float(r["pop"]) * (1.0 + pg))
	recompute_all(sim)


static func scale_gdp(sim, id: String, factor: float) -> void:
	for rid in owned(sim, id):
		var r: Dictionary = sim.state["regions"][rid]
		r["gdp"] = float(r["gdp"]) * factor
	recompute(sim, id)


static func add_gdp(sim, id: String, amount: float) -> void:
	var c: Dictionary = sim.country(id)
	if float(c["gdp"]) > 0.0:
		scale_gdp(sim, id, 1.0 + amount / float(c["gdp"]))


static func scale_pop(sim, id: String, factor: float) -> void:
	for rid in owned(sim, id):
		var r: Dictionary = sim.state["regions"][rid]
		r["pop"] = float(r["pop"]) * factor
	recompute(sim, id)


static func capital_region(sim, id: String) -> String:
	return sim.db.capitals.get(id, "")


## هل للدولة (أو حلفائها في الحرب) جبهة برية مع العدو؟
static func has_land_front(sim, side: Array, enemies: Array) -> bool:
	return not _front_candidates(sim, side, enemies).is_empty()


# ------------------------------------------------------------------ المنشآت

## تعطيل منشأة بضربة: تبقى معطلة عدة أشهر
static func damage_facility(sim, rid: String, ftype: String, months: int) -> void:
	var r: Dictionary = sim.state["regions"][rid]
	if not r.has("damaged"):
		r["damaged"] = {}
	r["damaged"][ftype] = maxi(months, int(r["damaged"].get(ftype, 0)))
	recompute(sim, r["owner"])


## منشآت عاملة لدى طرف ما، مرتبة: الأقرب إلى نقطة مرجعية أولاً
## المناطق التي فيها منشأة من نوع معين (بترتيب المناطق)، محفوظة حتى تُبنى منشأة جديدة
static func facility_regions(sim, ftype: String) -> Array:
	if sim._fac_cache.has(ftype):
		return sim._fac_cache[ftype]
	var out: Array = []
	for rid in sim.db.region_ids:
		if facility_count(sim, rid, ftype) > 0:
			out.append(rid)
	sim._fac_cache[ftype] = out
	return out


static func working_facilities(sim, side: Array, ftype: String, near_rid: String = "") -> Array:
	var out: Array = []
	for rid in facility_regions(sim, ftype):
		if not (sim.state["regions"][rid]["owner"] in side):
			continue
		if facility_count(sim, rid, ftype) > 0 and facility_working(sim, rid, ftype):
			out.append(rid)
	if near_rid != "" and out.size() > 1:
		out.sort_custom(func(a, b): return _dist2(sim, a, near_rid) < _dist2(sim, b, near_rid))
	return out


# ------------------------------------------------------------------ التقدم على الجبهة

## مناطق الخاسر الملاصقة لمناطق الرابح
static func _front_candidates(sim, winners: Array, losers: Array) -> Array:
	var out: Array = []
	var info: Array = sim.border_info()
	var owned: Dictionary = info[0]
	var borders: Dictionary = info[1]
	for l in losers:
		for rid in owned.get(l, []):
			for o in borders[rid]:
				if o in winners:
					out.append(rid)
					break
	return out


static func _dist2(sim, a: String, b: String) -> float:
	var ra: Dictionary = sim.db.regions[a]
	var rb: Dictionary = sim.db.regions[b]
	var dx := float(ra["lon"]) - float(rb["lon"])
	var dy := float(ra["lat"]) - float(rb["lat"])
	return dx * dx + dy * dy


## يختار المنطقة التالية: تحرير الأرض أولاً، ثم التقدم نحو عاصمة العدو
static func _pick_target(sim, cands: Array, winners: Array, loser_lead: String) -> String:
	var cap := capital_region(sim, loser_lead)
	var best := ""
	var best_score := INF
	for rid in cands:
		var r: Dictionary = sim.state["regions"][rid]
		var s := 0.0
		if r["core"] in winners:
			s -= 10000.0       # تحرير أرض الرابح المحتلة له الأولوية
		if cap != "":
			s += _dist2(sim, rid, cap)
		if s < best_score:
			best_score = s
			best = rid
	return best


## يتقدم الرابح gains مناطق. naval_superiority يسمح بإنزال بحري حين لا توجد جبهة برية.
## كلفة احتلال منطقة من رصيد التقدم: المناطق الأغنى والأكثر سكاناً أصعب
static func capture_cost(sim, rid: String) -> float:
	var info: Dictionary = sim.db.regions[rid]
	var c := 0.7 + 3.0 * float(info["gdp_share"])
	if info["capital"]:
		c *= 1.5
	return minf(c, 3.0)


static func advance(sim, w: Dictionary, winners: Array, losers: Array, max_gains: int, naval_superiority: float, dominance: float = 1.0, progress_key: String = "", focus: Array = []) -> Array:
	var taken: Array = []
	var loser_lead: String = losers[0]
	for i in max_gains:
		var cands := _front_candidates(sim, winners, losers)
		# العاصمة محصنة: لا تسقط إلا بتفوق واضح وبعد حصار
		var cap := capital_region(sim, loser_lead)
		if cap in cands and cands.size() > 1:
			if dominance < CAPITAL_MIN_DOMINANCE or not sim.rng.chance(CAPITAL_CAPTURE_CHANCE):
				cands.erase(cap)
		elif cap in cands and dominance < CAPITAL_MIN_DOMINANCE:
			cands.erase(cap)
		var rid := ""
		# أوامر الهجوم أولاً: الهدف الذي تقف عنده فرق الرابح
		for f in focus:
			if f in cands and not (f in taken):
				rid = f
				break
		if rid != "":
			pass
		elif not cands.is_empty():
			rid = _pick_target(sim, cands, winners, loser_lead)
		elif naval_superiority > 0.6 and taken.is_empty() and not working_facilities(sim, winners, "port").is_empty():
			# إنزال بحري يحتاج ميناءً عاملاً: أقرب منطقة ساحلية للعدو إلى عاصمة الرابح
			var my_cap := capital_region(sim, winners[0])
			var best := INF
			for r2 in sim.db.region_ids:
				if sim.state["regions"][r2]["owner"] in losers and sim.db.regions[r2].get("coastal", true) and my_cap != "":
					var d := _dist2(sim, r2, my_cap)
					if d < best:
						best = d
						rid = r2
		if rid == "":
			break
		if progress_key != "":
			var cost := capture_cost(sim, rid)
			if float(w.get(progress_key, 0.0)) < cost:
				break
			w[progress_key] = float(w[progress_key]) - cost
		# من يأخذ المنطقة: صاحبها الأصلي إن كان من الرابحين، وإلا قائد الرابحين
		var r: Dictionary = sim.state["regions"][rid]
		var new_owner: String = r["core"] if r["core"] in winners else winners[0]
		capture(sim, rid, new_owner)
		taken.append(rid)
	return taken


static func capture(sim, rid: String, new_owner: String) -> void:
	var r: Dictionary = sim.state["regions"][rid]
	var old_owner: String = r["owner"]
	if old_owner == new_owner:
		return
	r["owner"] = new_owner
	r["occupied_months"] = 0
	r["loyalty"] = 100.0 if new_owner == r["core"] else CAPTURE_LOYALTY
	# أضرار الحرب في المنطقة
	r["gdp"] = float(r["gdp"]) * 0.97
	recompute(sim, old_owner)
	recompute(sim, new_owner)
	sim.on_region_captured(rid, new_owner)
	var info: Dictionary = sim.db.regions[rid]
	var core: String = r["core"]
	var core_c: Dictionary = sim.country(core)
	if info["capital"]:
		if new_owner != core and not core_c.get("capital_fallen", false):
			core_c["capital_fallen"] = true
			core_c["stability"] = maxf(0.0, float(core_c["stability"]) - 15.0)
			var text := "سقوط %s! قوات %s تدخل عاصمة %s." % [core_c["capital_ar"], sim.country(new_owner)["name_ar"], core_c["name_ar"]]
			sim.add_news(text, "war")
			if sim.is_player(core) or sim.is_player(new_owner):
				sim.push_event("capital", "سقوط عاصمة", text, true)
		elif new_owner == core:
			core_c["capital_fallen"] = false
			sim.add_news("تحرير %s." % core_c["capital_ar"], "good")
	if sim.is_player(old_owner) or sim.is_player(new_owner):
		var verb := "تحرر" if new_owner == core else "تسيطر على"
		sim.add_news("%s %s %s." % [sim.country(new_owner)["name_ar"], verb, info["name_ar"]], "good" if sim.is_player(new_owner) else "war")


## نسبة أرض الدولة الأصلية (بوزن الاقتصاد) التي يحتلها طرف معين
static func occupied_share(sim, core_id: String, by_side: Array) -> float:
	var s := 0.0
	for rid in core_regions(core_id, sim.db):
		if sim.state["regions"][rid]["owner"] in by_side:
			s += float(sim.db.regions[rid]["gdp_share"])
	return s


## نتيجة الحرب من الأرض: موجبة لصالح المهاجمين
static func war_score(sim, w: Dictionary) -> float:
	var A: Array = w["attackers"]
	var D: Array = w["defenders"]
	var d_lead: String = D[0]
	var a_lead: String = A[0]
	var s := (occupied_share(sim, d_lead, A) - occupied_share(sim, a_lead, D)) * 140.0
	if sim.country(d_lead).get("capital_fallen", false) and sim.state["regions"][capital_region(sim, d_lead)]["owner"] in A:
		s += 25.0
	if sim.country(a_lead).get("capital_fallen", false) and sim.state["regions"][capital_region(sim, a_lead)]["owner"] in D:
		s -= 25.0
	return clampf(s, -100.0, 100.0)


## هل انهارت الدولة؟ سقوط العاصمة مع خسارة نصف الأرض، أو خسارة معظمها
static func collapsed(sim, id: String, enemies: Array) -> bool:
	var c: Dictionary = sim.country(id)
	var occ := occupied_share(sim, id, enemies)
	if occ >= 0.75:
		return true
	return c.get("capital_fallen", false) and (occ >= 0.5 or float(c["stability"]) < 10.0)


## عند السلام: تعود المناطق المحتلة بين الطرفين لأصحابها،
## إلا أرض keep_loser التي يحتلها keep_side (استسلام)
static func revert_war_regions(sim, w: Dictionary, keep_loser: String = "", keep_side: Array = []) -> void:
	var A: Array = w["attackers"]
	var D: Array = w["defenders"]
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		var owner: String = r["owner"]
		var core: String = r["core"]
		if owner == core:
			continue
		var crossed: bool = (owner in A and core in D) or (owner in D and core in A)
		if not crossed:
			continue
		if keep_loser != "" and core == keep_loser and owner in keep_side:
			continue
		capture(sim, rid, core)


# ------------------------------------------------------------------ الشهري: الاندماج والإصلاح والمقاومة

static func monthly(sim) -> void:
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		# إصلاح المنشآت المعطلة
		var dmg: Dictionary = r.get("damaged", {})
		if not dmg.is_empty():
			for t in dmg.keys():
				dmg[t] = int(dmg[t]) - 1
				if int(dmg[t]) <= 0:
					dmg.erase(t)
		if r["owner"] == r["core"]:
			continue
		r["occupied_months"] = int(r["occupied_months"]) + 1
		r["loyalty"] = minf(100.0, float(r["loyalty"]) + 2.5)
		# المقاومة: المناطق المحتلة قد تثور وتعود لدولتها إن كانت لا تزال قائمة
		var core: Dictionary = sim.country(r["core"])
		if core.get("annexed", false) or float(r["loyalty"]) >= 35.0:
			continue
		var p := 0.01 + (35.0 - float(r["loyalty"])) / 1500.0
		if sim.rng.chance(p):
			var old_owner: String = r["owner"]
			capture(sim, rid, r["core"])
			sim.add_news("ثورة في %s تطرد قوات %s." % [sim.db.regions[rid]["name_ar"], sim.country(old_owner)["name_ar"]], "war")
	# إعادة الحساب تتم بعدها في grow_all
