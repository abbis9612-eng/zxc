## الاستخبارات والعمليات السرية وضباب الحرب.
## كل دولة تبني شبكات تجسس في دول أخرى (0-100)، والرؤية = أعلى من الشبكة والعلاقة.
## ما لا تراه بوضوح يظهر تقديراً بهامش خطأ. العمليات السرية تحتاج شبكة كافية وقد تُكشف.
extends RefCounted

const Territory := preload("res://sim/territory.gd")
const Factions := preload("res://sim/factions.gd")
const Economy := preload("res://sim/economy.gd")
const Market := preload("res://sim/market.gd")


static func cfg(sim) -> Dictionary:
	return sim.db.intel


static func init_country(c: Dictionary) -> void:
	c["intel"] = {}
	c["counter_intel"] = 1
	c["intel_build_day"] = {}


static func network(sim, a: String, b: String) -> float:
	return float(sim.country(a).get("intel", {}).get(b, 0.0))


static func counter(sim, id: String) -> Dictionary:
	var lv := clampi(int(sim.country(id).get("counter_intel", 0)), 0, 3)
	return cfg(sim)["counter_levels"][lv]


# ------------------------------------------------------------------ الرؤية وضباب الحرب

static func base_visibility(sim, viewer: String, target: String) -> float:
	var v: Dictionary = cfg(sim)["visibility"]
	if viewer == target:
		return float(v["self"])
	var t: Dictionary = sim.country(target)
	if t.get("overlord", "") == viewer:
		return float(v["vassal"])
	if target in sim.allies(viewer):
		return float(v["ally"])
	var best := float(v["other"])
	if Market.has_pact(sim, viewer, target):
		best = maxf(best, float(v["pact"]))
	if target in sim.country(viewer)["neighbors"]:
		best = maxf(best, float(v["neighbor"]))
	return best


static func visibility(sim, viewer: String, target: String) -> float:
	return maxf(base_visibility(sim, viewer, target), network(sim, viewer, target))


## تقدير قيمة حسب الرؤية: دقيق عند 60 فأكثر، وإلا بانحراف ثابت خلال الشهر ونطاق للخطأ.
## دالة عرض فقط: لا تستخدم rng المحاكاة ولا تغيّر الحالة.
static func estimate(sim, viewer: String, target: String, value: float, key: String) -> Dictionary:
	var vis := visibility(sim, viewer, target)
	if vis >= float(cfg(sim)["exact_at"]):
		return {"value": value, "lo": value, "hi": value, "exact": true, "vis": vis}
	var unc := (1.0 - vis / float(cfg(sim)["exact_at"])) * 0.6
	var month := int(sim.state["day"]) / 30
	var h := hash("%s|%s|%s|%d|%d" % [viewer, target, key, month, int(sim.state.get("seed", 0))])
	var noise := float(absi(h) % 2001) / 1000.0 - 1.0        # بين -1 و1
	var est := maxf(0.0, value * (1.0 + noise * unc))
	return {"value": est, "lo": est * (1.0 - unc), "hi": est * (1.0 + unc), "exact": false, "vis": vis}


static func can_see(sim, viewer: String, target: String, needed: float) -> bool:
	return visibility(sim, viewer, target) >= needed


# ------------------------------------------------------------------ الشبكات

static func network_cost(sim, a: String) -> float:
	return maxf(float(cfg(sim)["network_cost_min"]), float(sim.country(a)["gdp"]) * float(cfg(sim)["network_cost_gdp"]))


static func can_build(sim, a: String, b: String) -> String:
	if a == b or sim.country(b).is_empty():
		return "هدف غير صالح."
	var ca: Dictionary = sim.country(a)
	if int(ca.get("intel_build_day", {}).get(b, -100000)) + 30 > int(sim.state["day"]):
		return "توسيع الشبكة متاح مرة في الشهر."
	if network(sim, a, b) >= 100.0:
		return "الشبكة في أقصى مستوى."
	if float(ca["treasury"]) < network_cost(sim, a):
		return "الخزينة لا تكفي."
	return ""


static func build(sim, a: String, b: String) -> String:
	var why := can_build(sim, a, b)
	if why != "":
		return why
	var ca: Dictionary = sim.country(a)
	ca["treasury"] = float(ca["treasury"]) - network_cost(sim, a)
	var step := float(cfg(sim)["network_step"]) * (1.0 - float(counter(sim, b)["block"]))
	ca["intel"][b] = minf(100.0, network(sim, a, b) + step)
	ca["intel_build_day"][b] = int(sim.state["day"])
	return ""


static func set_counter(sim, id: String, level: int) -> void:
	sim.country(id)["counter_intel"] = clampi(level, 0, 3)


## كلفة مكافحة التجسس الشهرية (مليار): cost_gdp نسبة سنوية من الناتج
static func monthly_cost(sim, c: Dictionary) -> float:
	var lv := clampi(int(c.get("counter_intel", 0)), 0, 3)
	return float(c["gdp"]) * float(cfg(sim)["counter_levels"][lv]["cost_gdp"]) / 12.0


## شهرياً: الشبكات تضعف، ومكافحة التجسس قد تكشف بعضها
static func monthly(sim) -> void:
	var decay := float(cfg(sim)["network_decay"])
	for a in sim.alive_ids():
		var ca: Dictionary = sim.country(a)
		var nets: Dictionary = ca.get("intel", {})
		for b in nets.keys():
			var tb: Dictionary = sim.country(b)
			if tb.is_empty() or tb.get("annexed", false):
				nets.erase(b)
				continue
			var lv := float(nets[b]) - decay
			if lv > 20.0 and sim.rng.chance(float(counter(sim, b)["detect"])):
				lv -= float(cfg(sim)["exposure_network_loss"])
				sim.change_relation(a, b, -10.0)
				if sim.is_player(a) or sim.is_player(b):
					var text := "%s تفكك شبكة تجسس تابعة لـ%s." % [tb["name_ar"], ca["name_ar"]]
					sim.add_news(text, "info")
					sim.push_event("intel", "كشف شبكة تجسس", text, false)
			if lv <= 0.0:
				nets.erase(b)
			else:
				nets[b] = lv


# ------------------------------------------------------------------ العمليات السرية

static func op_cost(sim, a: String, op: String) -> float:
	return maxf(0.2, float(sim.country(a)["gdp"]) * float(cfg(sim)["operations"][op]["cost_gdp"]))


static func op_chance(sim, a: String, b: String, op: String) -> float:
	var o: Dictionary = cfg(sim)["operations"][op]
	var net := network(sim, a, b)
	var p := float(o["base_success"]) + (net - float(o["min_network"])) / 200.0 - float(counter(sim, b)["block"]) * 0.5
	return clampf(p, 0.1, 0.9)


static func can_run(sim, a: String, b: String, op: String) -> String:
	if not cfg(sim)["operations"].has(op):
		return "عملية غير معروفة."
	if a == b:
		return "هدف غير صالح."
	var o: Dictionary = cfg(sim)["operations"][op]
	if network(sim, a, b) < float(o["min_network"]):
		return "تحتاج شبكة تجسس %d على الأقل في %s (لديك %d)." % [int(o["min_network"]), sim.country(b)["name_ar"], int(network(sim, a, b))]
	if float(sim.country(a)["treasury"]) < op_cost(sim, a, op):
		return "الخزينة لا تكفي."
	if op == "sabotage" and _sabotage_target(sim, b).is_empty():
		return "لا منشآت عاملة للتخريب."
	if op == "steal_tech" and _tech_gap(sim, a, b).is_empty():
		return "لا تملك %s تقنية أحدث منك." % sim.country(b)["name_ar"]
	return ""


static func _sabotage_target(sim, b: String) -> Array:
	for ftype in ["refinery", "factory", "airbase", "power_plant", "port"]:
		var list: Array = Territory.working_facilities(sim, [b], ftype)
		if not list.is_empty():
			return [list[0], ftype]
	return []


static func _tech_gap(sim, a: String, b: String) -> String:
	var ta: Dictionary = sim.country(a)["tech"]
	var tb: Dictionary = sim.country(b)["tech"]
	var best := ""
	var gap := 0
	for br in sim.db.branches:
		var g := int(tb[br]) - int(ta[br])
		if g > gap:
			gap = g
			best = br
	return best


## تنفيذ عملية: يعيد {success, exposed, text}
static func run(sim, a: String, b: String, op: String) -> Dictionary:
	var why := can_run(sim, a, b, op)
	if why != "":
		return {"success": false, "exposed": false, "text": why, "error": true}
	var conf := cfg(sim)
	var ca: Dictionary = sim.country(a)
	var cb: Dictionary = sim.country(b)
	ca["treasury"] = float(ca["treasury"]) - op_cost(sim, a, op)
	var success: bool = sim.rng.chance(op_chance(sim, a, b, op))
	var text := ""
	var hidden_text := ""   # ما يراه الضحية إن لم تُكشف الجهة
	if success:
		match op:
			"cyber":
				Territory.scale_gdp(sim, b, 0.995)
				cb["treasury"] = maxf(0.0, float(cb["treasury"]) - float(cb["gdp"]) * 0.002)
				cb["stability"] = maxf(0.0, float(cb["stability"]) - 2.0)
				text = "الهجوم السيبراني عطّل أنظمة %s المالية والخدمية." % cb["name_ar"]
				hidden_text = "هجوم سيبراني مجهول يعطل أنظمة %s." % cb["name_ar"]
			"sabotage":
				var t: Array = _sabotage_target(sim, b)
				Territory.damage_facility(sim, t[0], t[1], 4)
				var fname: String = Territory.FACILITY_NAMES[t[1]]
				var place: String = sim.db.regions[t[0]]["name_ar"]
				text = "عملاؤنا عطلوا %s في %s لأربعة أشهر." % [fname, place]
				hidden_text = "انفجار غامض يعطل %s في %s." % [fname, place]
			"opposition":
				if cb.has("factions"):
					cb["factions"]["street"]["sat"] = maxf(0.0, float(cb["factions"]["street"]["sat"]) - 12.0)
				cb["stability"] = maxf(0.0, float(cb["stability"]) - 4.0)
				text = "المعارضة في %s تتحرك بتمويلنا: الشارع غاضب." % cb["name_ar"]
				hidden_text = "احتجاجات منظمة تجتاح %s." % cb["name_ar"]
			"steal_tech":
				var br := _tech_gap(sim, a, b)
				var gen := int(ca["tech"][br])
				if ca["research_focus"] != br:
					ca["research_focus"] = br
					ca["research_progress"] = 0.0
				ca["research_progress"] = float(ca["research_progress"]) + Economy.research_cost(gen + 1) * 0.5
				text = "سرقنا أسراراً من %s في %s: نصف الطريق إلى الجيل التالي." % [cb["name_ar"], sim.db.branches[br]]
				hidden_text = "تسريب أسرار عسكرية من %s." % cb["name_ar"]
			"incite":
				if cb.has("factions"):
					cb["factions"]["military"]["sat"] = maxf(0.0, float(cb["factions"]["military"]["sat"]) - 15.0)
				text = "قادة في جيش %s بدأوا يتململون من حكومتهم." % cb["name_ar"]
				hidden_text = "توتر بين الحكومة وقادة الجيش في %s." % cb["name_ar"]
	else:
		text = "فشلت عملية «%s» في %s." % [conf["operations"][op]["name_ar"], cb["name_ar"]]
	var p_exp := float(conf["exposure_on_success"]) if success else float(conf["exposure_on_failure"])
	p_exp += float(counter(sim, b)["detect"]) * 3.0
	var exposed: bool = sim.rng.chance(clampf(p_exp, 0.0, 0.95))
	if exposed:
		sim.change_relation(a, b, float(conf["exposure_relation"]))
		ca["intel"][b] = maxf(0.0, network(sim, a, b) - float(conf["exposure_network_loss"]))
		var news := "%s تتهم %s بعملية «%s»." % [cb["name_ar"], ca["name_ar"], conf["operations"][op]["name_ar"]]
		sim.add_news(news, "war")
		text += " وانكشف أمرنا: العلاقات تتدهور."
		if sim.is_player(b):
			sim.push_event("intel", "عملية معادية مكشوفة", news + (" " + hidden_text if success else ""), true)
	elif success and (sim.is_player(a) or sim.is_player(b)):
		sim.add_news(text if sim.is_player(a) else hidden_text, "good" if sim.is_player(a) else "world")
		if sim.is_player(b):
			sim.push_event("intel", "حادث غامض", hidden_text, true)
	return {"success": success, "exposed": exposed, "text": text}
