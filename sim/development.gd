## اتجاه الدولة، استيراد السلاح، التكتيك، مسارات البحث، بناء منشأة في منطقة، نمو السكان، والاتحاد السلمي.
## الأرقام في data/development.json.
extends RefCounted

const Investment := preload("res://sim/investment.gd")
const Arsenal := preload("res://sim/arsenal.gd")
const Territory := preload("res://sim/territory.gd")


static func cfg(sim) -> Dictionary:
	return sim.db.development


static func doctrine(sim, c: Dictionary) -> Dictionary:
	var id: String = c.get("doctrine", "balanced")
	var all: Dictionary = cfg(sim)["doctrines"]
	return all.get(id, all["balanced"])


static func num(sim, c: Dictionary, key: String) -> float:
	return float(doctrine(sim, c).get(key, 0.0))


static func combat_mult(sim, c: Dictionary, utype: String) -> float:
	var m := 1.0
	if utype == "ew":
		m += num(sim, c, "ew_boost")
	if utype == "atgm" or utype == "ashm" or utype == "air_defense":
		m += num(sim, c, "def_boost")
	return m


static func track(sim, id: String) -> Dictionary:
	return cfg(sim)["tracks"].get(id, {})


static func tactic(sim, id: String) -> Dictionary:
	var all: Dictionary = cfg(sim)["tactics"]
	return all.get(id, all["balanced"])


static func gate_block(sim, c: Dictionary, branch: String, next_gen: int) -> String:
	for g in cfg(sim).get("gen_gates", []):
		if g["branch"] == branch and int(g["gen"]) == next_gen:
			if int(c["tech"].get(g["need_track"], 1)) < int(g["need_level"]):
				return g["text_ar"]
	return ""


# ------------------------------------------------------------------ الاتجاه

static func can_set_doctrine(sim, id: String, doc: String) -> String:
	if not cfg(sim)["doctrines"].has(doc):
		return "اتجاه غير معروف."
	var c: Dictionary = sim.country(id)
	if c.get("doctrine", "balanced") == doc:
		return "هذا اتجاهك الحالي."
	if int(sim.state["day"]) < int(c.get("doctrine_until", 0)):
		return "يمكن تغيير الاتجاه بعد %d يوماً." % (int(c["doctrine_until"]) - int(sim.state["day"]))
	return ""


static func set_doctrine(sim, id: String, doc: String) -> String:
	var why := can_set_doctrine(sim, id, doc)
	if why != "":
		return why
	var c: Dictionary = sim.country(id)
	c["doctrine"] = doc
	c["stability"] = maxf(0.0, float(c["stability"]) - float(cfg(sim)["doctrine_stability_cost"]))
	c["doctrine_until"] = int(sim.state["day"]) + int(cfg(sim)["doctrine_change_days"])
	sim.add_news("%s تتجه إلى: %s." % [c["name_ar"], cfg(sim)["doctrines"][doc]["name_ar"]], "info")
	return ""


static func monthly(sim) -> void:
	var rules: Dictionary = cfg(sim)
	var affinity: Array = rules["affinity"]
	for id in sim.alive_ids():
		var c: Dictionary = sim.country(id)
		if not doctrine(sim, c).get("unity", false):
			continue
		var step := float(doctrine(sim, c).get("relation_monthly", 0.0))
		for other in affinity:
			if other == id or sim.country(other).is_empty() or sim.country(other).get("annexed", false):
				continue
			if sim.war_between(id, other).is_empty():
				sim.change_relation(id, other, step)


# ------------------------------------------------------------------ الاستيراد

static func export_gen(sim, seller: String, buyer: String, utype: String) -> int:
	var branch: String = sim.db.units[utype]["branch"]
	var g := int(sim.country(seller)["tech"][branch])
	if seller in sim.allies(buyer) or buyer in sim.allies(seller):
		return g
	return maxi(1, g - int(cfg(sim)["import"]["gen_drop"]))


static func suppliers(sim, buyer: String, utype: String) -> Array:
	if not sim.db.units.has(utype) or utype == "nukes":
		return []
	var rules: Dictionary = cfg(sim)["import"]
	var branch: String = sim.db.units[utype]["branch"]
	var out: Array = []
	for id in sim.alive_ids():
		if id == buyer:
			continue
		var c: Dictionary = sim.country(id)
		if int(c["tech"][branch]) < int(rules["min_gen"]):
			continue
		if not sim.war_between(buyer, id).is_empty():
			continue
		if buyer in c.get("sanctions", []):
			continue
		var ally: bool = id in sim.allies(buyer)
		if not ally and sim.relation(buyer, id) < float(rules["min_relation"]):
			continue
		var blocked: bool = false
		for enemy in sim.enemies_of(buyer):
			if id in sim.allies(enemy):
				blocked = true
				break
		if blocked:
			continue
		var gen: int = export_gen(sim, id, buyer, utype)
		var markup: float = float(rules["ally_markup"]) if ally else float(rules["other_markup"])
		var cost: float = float(sim.unit_cost(c, utype)) * markup
		out.append({"id": id, "gen": gen, "cost": cost, "days": int(rules["days"]), "ally": ally})
	out.sort_custom(func(a, b): return int(a["gen"]) > int(b["gen"]) or (int(a["gen"]) == int(b["gen"]) and float(a["cost"]) < float(b["cost"])))
	return out


static func import_units(sim, buyer: String, seller: String, utype: String, count: float) -> String:
	if count <= 0.0:
		return "كمية غير صالحة."
	var offer: Dictionary = {}
	for s in suppliers(sim, buyer, utype):
		if s["id"] == seller:
			offer = s
			break
	if offer.is_empty():
		return "هذه الدولة لا تبيعك هذا السلاح."
	var c: Dictionary = sim.country(buyer)
	var total := float(offer["cost"]) * count
	if total > float(c["treasury"]):
		return "الخزينة لا تكفي. الكلفة %s مليار." % sim.fmt_num(total)
	c["treasury"] = float(c["treasury"]) - total
	var seller_c: Dictionary = sim.country(seller)
	seller_c["treasury"] = float(seller_c["treasury"]) + total * float(cfg(sim)["import"]["seller_share"])
	sim.change_relation(buyer, seller, float(cfg(sim)["import"]["relation_gain"]))
	c["imports"].append({"type": utype, "count": count, "gen": int(offer["gen"]), "from": seller, "days_left": float(offer["days"])})
	return ""


static func _tick_imports(sim, c: Dictionary) -> void:
	var queue: Array = c.get("imports", [])
	var i := queue.size() - 1
	while i >= 0:
		var o: Dictionary = queue[i]
		o["days_left"] = float(o["days_left"]) - 1.0
		if float(o["days_left"]) <= 0.0:
			queue.remove_at(i)
			Arsenal.add(c, o["type"], float(o["count"]), int(o["gen"]))
			if sim.is_player(c["id"]):
				sim.add_news("وصلت شحنة %s %s من %s، جيل %d." % [sim.fmt_num(o["count"]), sim.db.units[o["type"]]["name_ar"], sim.country(o["from"])["name_ar"], int(o["gen"])], "good")
		i -= 1


# ------------------------------------------------------------------ البناء في منطقة

static func can_build(sim, id: String, rid: String, ftype: String) -> String:
	var rules: Dictionary = cfg(sim)["projects"]
	if not rules.has(ftype):
		return "لا يُبنى هذا هنا."
	var r: Dictionary = Territory.region(sim, rid)
	if r.is_empty() or r["owner"] != id:
		return "المنطقة ليست تحت سيطرتك."
	var info: Dictionary = sim.db.regions[rid]
	if rules[ftype].get("coastal", false) and not info.get("coastal", false):
		return "الميناء يحتاج منطقة ساحلية."
	var c: Dictionary = sim.country(id)
	var cost := float(c["gdp"]) * float(rules[ftype]["cost_gdp"])
	if float(c["treasury"]) < cost:
		return "الخزينة لا تكفي (%s مليار)." % sim.fmt_num(cost)
	return ""


## أفضل محافظة لبناء منشأة: من مناطقك الأصلية الأقل منها ثم الأغنى (الميناء على الساحل فقط)
static func best_site(sim, id: String, ftype: String) -> String:
	var best := ""
	var best_score := -INF
	for rid in Territory.core_regions(id, sim.db):
		var r: Dictionary = sim.state["regions"][rid]
		if r["owner"] != id:
			continue
		if cfg(sim)["projects"][ftype].get("coastal", false) and not sim.db.regions[rid].get("coastal", false):
			continue
		var score := float(sim.db.regions[rid]["gdp_share"]) - float(Territory.facility_count(sim, rid, ftype)) * 0.5
		if score > best_score:
			best_score = score
			best = rid
	return best


## أيام البناء الفعلية بسرعة المصانع الحالية
static func project_days(sim, id: String, ftype: String) -> int:
	var c: Dictionary = sim.country(id)
	var speed := float(c.get("logistics", {}).get("production", 1.0)) * (1.0 + num(sim, c, "production"))
	return int(ceilf(float(cfg(sim)["projects"][ftype]["days"]) / maxf(0.05, speed)))


static func project_cost(sim, id: String, ftype: String) -> float:
	return float(sim.country(id)["gdp"]) * float(cfg(sim)["projects"][ftype]["cost_gdp"])


static func start_build(sim, id: String, rid: String, ftype: String) -> String:
	var why := can_build(sim, id, rid, ftype)
	if why != "":
		return why
	var c: Dictionary = sim.country(id)
	var cost := project_cost(sim, id, ftype)
	c["treasury"] = float(c["treasury"]) - cost
	var rules: Dictionary = cfg(sim)["projects"][ftype]
	c["projects"].append({"region": rid, "type": ftype, "days_left": float(rules["days"])})
	return ""


static func _tick_projects(sim, c: Dictionary) -> void:
	var queue: Array = c.get("projects", [])
	var speed := float(c.get("logistics", {}).get("production", 1.0)) * (1.0 + num(sim, c, "production"))
	var i := queue.size() - 1
	while i >= 0:
		var o: Dictionary = queue[i]
		o["days_left"] = float(o["days_left"]) - speed
		if float(o["days_left"]) <= 0.0:
			queue.remove_at(i)
			if Territory.region(sim, o["region"]).get("owner", "") == c["id"]:
				Territory.add_facility(sim, o["region"], o["type"])
				if sim.is_player(c["id"]):
					var nm: String = sim.db.regions[o["region"]]["name_ar"]
					sim.add_news("اكتمل بناء %s في %s." % [cfg(sim)["projects"][o["type"]]["name_ar"], nm], "good")
		i -= 1


static func daily(sim) -> void:
	for id in sim.alive_ids():
		var c: Dictionary = sim.country(id)
		_tick_imports(sim, c)
		_tick_projects(sim, c)
		Investment.daily(sim, c)


# ------------------------------------------------------------------ السكان

static func pop_rate(sim, c: Dictionary) -> float:
	var rules: Dictionary = cfg(sim)["population"]
	var food := float(c.get("logistics", {}).get("food", 35.0))
	var ratio := food / 35.0
	if ratio < float(rules["starve_line"]):
		return float(rules["starve_monthly"])
	var rate := float(rules["monthly"]) * minf(float(rules["food_cap"]), ratio)
	if not sim.wars_of(c["id"]).is_empty():
		rate *= float(rules["war_factor"])
	return rate


# ------------------------------------------------------------------ الاتحاد

static func can_union(sim, a: String, b: String) -> String:
	if a == b:
		return "لا اتحاد مع نفسك."
	var ca: Dictionary = sim.country(a)
	var cb: Dictionary = sim.country(b)
	if cb.is_empty() or cb.get("annexed", false) or ca.get("annexed", false):
		return "الدولة غير قائمة."
	if not sim.war_between(a, b).is_empty() or not sim.wars_of(b).is_empty():
		return "لا اتحاد ودولة في حرب."
	if float(cb["military"].get("nukes", 0.0)) >= 1.0:
		return "دولة نووية لا تتنازل عن سيادتها بالاتحاد."
	if cb.get("overlord", "") != "":
		return "هي تابعة لدولة أخرى."
	var rules: Dictionary = cfg(sim)["union"]
	var unity: bool = doctrine(sim, ca).get("unity", false)
	var need_inf := float(rules["influence_unity"]) if unity else float(rules["influence"])
	var need_rel := float(rules["relation_unity"]) if unity else float(rules["relation"])
	var inf := float(cb.get("influence", {}).get(a, 0.0))
	if inf < need_inf:
		return "تحتاج نفوذاً %d على الأقل (الآن %d)." % [int(need_inf), int(inf)]
	if sim.relation(a, b) < need_rel:
		return "تحتاج علاقة %d على الأقل." % int(need_rel)
	return ""


static func unite(sim, a: String, b: String) -> String:
	var why := can_union(sim, a, b)
	if why != "":
		return why
	var keep := float(cfg(sim)["union"]["army_keep"])
	var cb: Dictionary = sim.country(b)
	for k in sim.db.units:
		for batch in cb.get("stocks", {}).get(k, []):
			Arsenal.add(sim.country(a), k, float(batch["n"]) * keep, int(batch["gen"]))
	Territory.transfer_all(sim, b, a)
	for d in sim.state.get("divisions", []):
		if d["owner"] == b:
			d["owner"] = a
	sim.annex(b, a, true)
	return ""


# ------------------------------------------------------------------ التكتيك

static func pick_tactic(sim, c: Dictionary) -> String:
	var order := ["sead", "blitz", "strike", "naval", "ew", "attrition", "balanced"]
	var score: Dictionary = {
		"sead": sim.unit_power(c, "fighters"),
		"blitz": sim.unit_power(c, "armor"),
		"strike": sim.unit_power(c, "missiles") + sim.unit_power(c, "drones"),
		"naval": sim.unit_power(c, "ships") + sim.unit_power(c, "submarines"),
		"ew": sim.unit_power(c, "ew"),
		"attrition": sim.unit_power(c, "infantry") * 0.25,
		"balanced": sim.military_power(c) * 0.12,
	}
	var best := "balanced"
	var best_v := -1.0
	for k in order:
		var v := float(score[k])
		if v > best_v:
			best_v = v
			best = k
	return best


static func set_tactic(sim, id: String, war_id: int, tac: String) -> String:
	if not cfg(sim)["tactics"].has(tac):
		return "تكتيك غير معروف."
	for w in sim.state["wars"]:
		if int(w["id"]) != war_id:
			continue
		if not (id in w["attackers"] or id in w["defenders"]):
			return "لست طرفاً في هذه الحرب."
		if not w.has("tactics"):
			w["tactics"] = {}
		w["tactics"][id] = tac
		return ""
	return "الحرب غير قائمة."


static func tactic_of(sim, id: String, enemies: Array) -> String:
	for w in sim.wars_of(id):
		var other: Array = w["defenders"] if id in w["attackers"] else w["attackers"]
		for e in enemies:
			if e in other:
				return str(w.get("tactics", {}).get(id, "balanced"))
	return "balanced"
