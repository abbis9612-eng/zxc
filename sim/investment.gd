## الاستثمار الداخلي: حقول النفط والغاز، الصلب، التنقيب، اليورانيوم، الزراعة، البنية التحتية، الجامعات.
## الكلفة من الخزينة فوراً، والأثر عند الاكتمال. المنشآت في المحافظات (مصنع حربي، مصفاة...) في development.gd.
extends RefCounted

const Territory := preload("res://sim/territory.gd")


static func cfg(sim) -> Dictionary:
	return sim.db.development["domestic"]


static func ids(sim) -> Array:
	return cfg(sim).keys().filter(func(k): return not String(k).begins_with("_"))


static func level(c: Dictionary, kind: String) -> int:
	return int(c.get("dom_levels", {}).get(kind, 0))


static func cost(sim, c: Dictionary, kind: String) -> float:
	return float(c["gdp"]) * float(cfg(sim)[kind]["cost_gdp"])


static func days(sim, c: Dictionary, kind: String) -> int:
	return int(cfg(sim)[kind]["days"])


static func in_progress(c: Dictionary, kind: String) -> Dictionary:
	for o in c.get("dom_projects", []):
		if o["type"] == kind:
			return o
	return {}


## لماذا لا يجوز (فارغ = يجوز)
static func can_start(sim, id: String, kind: String) -> String:
	var c: Dictionary = sim.country(id)
	var p: Dictionary = cfg(sim).get(kind, {})
	if p.is_empty():
		return "مشروع غير معروف."
	if not in_progress(c, kind).is_empty():
		return "قيد التنفيذ."
	if p.has("max") and level(c, kind) >= int(p["max"]):
		return "وصلت لأعلى مستوى."
	if p.has("res") and float(c["resources"].get(p["res"], 0.0)) >= 100.0:
		return "المورد في أعلى مستوى."
	if p.get("needs_res", false) and float(c["resources"].get(p["res"], 0.0)) <= 0.0:
		return "لا مكامن معروفة في أرضك."
	if p.has("needs_track"):
		var tr: Array = p["needs_track"]
		if int(c["tech"].get(tr[0], 1)) < int(tr[1]):
			return "يحتاج البرنامج النووي مستوى %d." % int(tr[1])
	if float(c["treasury"]) < cost(sim, c, kind):
		return "الخزينة لا تكفي (%s مليار)." % sim.fmt_num(cost(sim, c, kind))
	return ""


static func start(sim, id: String, kind: String) -> String:
	var why := can_start(sim, id, kind)
	if why != "":
		return why
	var c: Dictionary = sim.country(id)
	c["treasury"] = float(c["treasury"]) - cost(sim, c, kind)
	if not c.has("dom_projects"):
		c["dom_projects"] = []
	var d := float(days(sim, c, kind))
	c["dom_projects"].append({"type": kind, "days_left": d, "total": d})
	return ""


static func daily(sim, c: Dictionary) -> void:
	var q: Array = c.get("dom_projects", [])
	if q.is_empty():
		return
	var i := q.size() - 1
	while i >= 0:
		var o: Dictionary = q[i]
		o["days_left"] = float(o["days_left"]) - 1.0
		if float(o["days_left"]) <= 0.0:
			q.remove_at(i)
			_complete(sim, c, String(o["type"]))
		i -= 1


static func _complete(sim, c: Dictionary, kind: String) -> void:
	var p: Dictionary = cfg(sim)[kind]
	if not c.has("dom_levels"):
		c["dom_levels"] = {}
	c["dom_levels"][kind] = level(c, kind) + 1
	var text := "اكتمل مشروع %s." % p["name_ar"]
	if p.has("res"):
		var ok := true
		if p.has("chance"):
			ok = sim.rng.chance(float(p["chance"]))
		if ok:
			if not c.has("res_bonus"):
				c["res_bonus"] = {}
			c["res_bonus"][p["res"]] = float(c["res_bonus"].get(p["res"], 0.0)) + float(p["amount"])
			Territory.recompute(sim, c["id"])
		else:
			text = "التنقيب عن %s لم يجد مكمناً هذه المرة." % p["name_ar"].trim_prefix("التنقيب عن ")
	if p.has("gdp"):
		Territory.scale_gdp(sim, c["id"], 1.0 + float(p["gdp"]))
	if p.has("growth"):
		c["growth_bonus"] = float(c.get("growth_bonus", 0.0)) + float(p["growth"])
	if sim.is_player(c["id"]):
		sim.add_news(text, "good")
