## المناطق والاحتلال: كل دولة مقسمة إلى مناطقها الإدارية الحقيقية.
## الناتج والسكان يُحسبان من مجموع المناطق التي تسيطر عليها الدولة،
## والحرب تتقدم منطقة بمنطقة على الجبهات بين المناطق المتجاورة.
extends RefCounted

const INTEGRATION_MONTHS := 12.0     # أشهر حتى تنتج المنطقة المحتلة بكامل طاقتها لمحتلها
const OCCUPIED_START_EFF := 0.3
const CAPTURE_LOYALTY := 10.0
const CAPITAL_MIN_DOMINANCE := 0.3   # اقتحام العاصمة يحتاج تفوقاً واضحاً في المعركة
const CAPITAL_CAPTURE_CHANCE := 0.35


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
		}
	sim.state["regions"] = regions
	for id in sim.state["order"]:
		recompute(sim, id)


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
	var n := 0
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		if r["owner"] == id and r["core"] != id:
			n += 1
	return n


## إنتاجية المنطقة لمالكها: المحتلة حديثاً تنتج أقل حتى تندمج
static func efficiency(r: Dictionary) -> float:
	if r["owner"] == r["core"]:
		return 1.0
	return OCCUPIED_START_EFF + (1.0 - OCCUPIED_START_EFF) * minf(1.0, float(r["occupied_months"]) / INTEGRATION_MONTHS)


static func recompute(sim, id: String) -> void:
	var c: Dictionary = sim.country(id)
	if c.is_empty():
		return
	var gdp := 0.0
	var pop := 0.0
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		if r["owner"] == id:
			gdp += float(r["gdp"]) * efficiency(r)
			pop += float(r["pop"])
	c["gdp"] = maxf(0.5, gdp)
	c["population"] = maxf(0.05, pop)


static func grow(sim, id: String, growth_annual_pct: float) -> void:
	var f := 1.0 + growth_annual_pct / 1200.0
	for rid in owned(sim, id):
		var r: Dictionary = sim.state["regions"][rid]
		r["gdp"] = maxf(0.001, float(r["gdp"]) * f)
	recompute(sim, id)


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


# ------------------------------------------------------------------ التقدم على الجبهة

## مناطق الخاسر الملاصقة لمناطق الرابح
static func _front_candidates(sim, winners: Array, losers: Array) -> Array:
	var out: Array = []
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		if not (r["owner"] in losers):
			continue
		for n in sim.db.regions[rid]["neighbors"]:
			if sim.state["regions"].has(n) and sim.state["regions"][n]["owner"] in winners:
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
static func advance(sim, w: Dictionary, winners: Array, losers: Array, gains: int, naval_superiority: float, dominance: float = 1.0) -> Array:
	var taken: Array = []
	var loser_lead: String = losers[0]
	for i in gains:
		var cands := _front_candidates(sim, winners, losers)
		# العاصمة محصنة: لا تسقط إلا بتفوق واضح وبعد حصار
		var cap := capital_region(sim, loser_lead)
		if cap in cands and cands.size() > 1:
			if dominance < CAPITAL_MIN_DOMINANCE or not sim.rng.chance(CAPITAL_CAPTURE_CHANCE):
				cands.erase(cap)
		elif cap in cands and dominance < CAPITAL_MIN_DOMINANCE:
			cands.erase(cap)
		var rid := ""
		if not cands.is_empty():
			rid = _pick_target(sim, cands, winners, loser_lead)
		elif naval_superiority > 0.6 and taken.is_empty():
			# إنزال بحري: أقرب منطقة للعدو إلى عاصمة الرابح
			var my_cap := capital_region(sim, winners[0])
			var best := INF
			for r2 in sim.db.region_ids:
				if sim.state["regions"][r2]["owner"] in losers and my_cap != "":
					var d := _dist2(sim, r2, my_cap)
					if d < best:
						best = d
						rid = r2
		if rid == "":
			break
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


## هل انهارت الدولة؟ سقوط العاصمة مع خسارة أرض كبيرة، أو خسارة معظم الأرض
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


# ------------------------------------------------------------------ الشهري: الاندماج والمقاومة

static func monthly(sim) -> void:
	var touched := {}
	for rid in sim.db.region_ids:
		var r: Dictionary = sim.state["regions"][rid]
		if r["owner"] == r["core"]:
			continue
		r["occupied_months"] = int(r["occupied_months"]) + 1
		r["loyalty"] = minf(100.0, float(r["loyalty"]) + 2.5)
		touched[r["owner"]] = true
		# المقاومة: المناطق المحتلة قد تثور وتعود لدولتها إن كانت لا تزال قائمة
		var core: Dictionary = sim.country(r["core"])
		if core.get("annexed", false) or float(r["loyalty"]) >= 35.0:
			continue
		var p := 0.01 + (35.0 - float(r["loyalty"])) / 1500.0
		if sim.rng.chance(p):
			var old_owner: String = r["owner"]
			capture(sim, rid, r["core"])
			touched[old_owner] = true
			sim.add_news("ثورة في %s تطرد قوات %s." % [sim.db.regions[rid]["name_ar"], sim.country(old_owner)["name_ar"]], "war")
	for id in touched:
		recompute(sim, id)
