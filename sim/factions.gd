## الفئات الداخلية: الجيش، رجال الأعمال، الشارع، رجال الدين.
## لكل فئة رضا يتجه شهرياً نحو هدف تحدده قرارات الدولة، ووزن يحدده نظام الحكم.
## الرضا الموزون يدخل في الاستقرار، والجيش الغاضب ينقلب، والشارع الغاضب يثور،
## وتغيير نظام الحكم يحتاج دعمها.
extends RefCounted

const Economy := preload("res://sim/economy.gd")
const Logistics := preload("res://sim/logistics.gd")
const Market := preload("res://sim/market.gd")

const COUP_THRESHOLD := 20.0
const REVOLUTION_THRESHOLD := 15.0
const REVOLUTION_STABILITY := 25.0


static func cfg(sim) -> Dictionary:
	return sim.db.factions


static func ids(sim) -> Array:
	return cfg(sim)["factions"].keys()


static func weight(sim, gov: String, f: String) -> float:
	return float(cfg(sim)["weights"][gov][f])


static func preference(sim, f: String, gov: String) -> float:
	return float(cfg(sim)["preferences"][f].get(gov, 0.0))


# ------------------------------------------------------------------ الإعداد

static func init_country(sim, c: Dictionary) -> void:
	c["mil_ratio_base"] = Economy.military_upkeep(sim, c) / maxf(1.0, float(c["gdp"]))
	c["appease_until"] = {}
	c["coup_months"] = 0
	c["revolution_months"] = 0
	var targets := compute_targets(sim, c)
	var fac := {}
	for f in ids(sim):
		fac[f] = {"sat": float(targets[f]["target"]), "target": float(targets[f]["target"]), "reasons": targets[f]["reasons"]}
	c["factions"] = fac
	c["wsat_base"] = weighted(sim, c)
	c["faction_delta"] = 0.0


## الرضا الموزون حسب نظام الحكم الحالي
static func weighted(sim, c: Dictionary) -> float:
	var t := 0.0
	for f in ids(sim):
		t += weight(sim, c["government"], f) * float(c["factions"][f]["sat"])
	return t


# ------------------------------------------------------------------ الأهداف وأسبابها

## يحسب هدف رضا كل فئة مع أسبابه: {فئة: {target, reasons: [[نص، قيمة]...]}}
static func compute_targets(sim, c: Dictionary) -> Dictionary:
	var out := {}
	var gov: String = c["government"]
	var gdp := maxf(1.0, float(c["gdp"]))
	var b: Dictionary = c.get("last_budget", {})
	var growth := float(b.get("growth", c.get("growth", 2.0)))
	var tax_up := float(c["tax_rate"]) - float(c.get("tax_base", c["tax_rate"]))
	var infl := float(c.get("inflation", 3.0))
	var wars: Array = sim.wars_of(c["id"])
	var war_score := 0.0
	for w in wars:
		war_score += float(w["score"]) if c["id"] in w["attackers"] else -float(w["score"])
	var lost := 0.0
	if sim.state.has("regions"):
		for rid in sim.db.regions_by_country.get(c["id"], []):
			if sim.state["regions"][rid]["owner"] != c["id"]:
				lost += float(sim.db.regions[rid]["gdp_share"])
	var capital_lost: bool = c.get("capital_fallen", false)
	for f in ids(sim):
		var r: Array = []
		var pref := preference(sim, f, gov)
		if absf(pref) > 0.01:
			r.append(["نظام الحكم", pref * 12.0])
		for p in c["policies"]:
			var eff: Dictionary = cfg(sim)["policy_effects"].get(p, {})
			if eff.has(f):
				r.append([sim.db.policies[p]["name_ar"], float(eff[f])])
		# الهزيمة تؤلم أكثر أثناء الحرب، ثم تخف بعدها
		var at_war := not wars.is_empty()
		if capital_lost:
			r.append(["سقوط العاصمة", -20.0 if at_war else -6.0])
		if lost > 0.01:
			r.append(["أرض محتلة", -minf(20.0 if at_war else 6.0, lost * 60.0)])
		match f:
			"military":
				var ratio := Economy.military_upkeep(sim, c) / gdp
				var base := maxf(0.0001, float(c.get("mil_ratio_base", ratio)))
				r.append(["ميزانية الجيش", clampf((ratio / base - 1.0) * 30.0, -15.0, 15.0)])
				if not wars.is_empty():
					r.append(["سير الحرب", clampf(war_score * 0.2, -15.0, 10.0)])
			"business":
				r.append(["النمو", clampf((growth - 2.0) * 4.0, -15.0, 12.0)])
				r.append(["الضرائب", clampf(-tax_up * 200.0, -20.0, 10.0)])
				if infl > 3.0:
					r.append(["التضخم", -minf(15.0, (infl - 3.0) * 1.5)])
				if not c.get("sanctions", []).is_empty():
					r.append(["العقوبات", -6.0 * c["sanctions"].size()])
				var pacts: int = Market.pacts_of(sim, c["id"]).size() if sim.state.has("trade_pacts") else 0
				if pacts > 0:
					r.append(["الاتفاقيات التجارية", minf(8.0, pacts * 2.0)])
				if not wars.is_empty():
					r.append(["الحرب", -5.0])
			"street":
				r.append(["النمو", clampf((growth - 2.0) * 2.0, -10.0, 8.0)])
				r.append(["الضرائب", clampf(-tax_up * 250.0, -25.0, 10.0)])
				if infl > 3.0:
					r.append(["التضخم", -minf(20.0, (infl - 3.0) * 2.0)])
				if not wars.is_empty():
					r.append(["الحرب", -6.0 * wars.size()])
				var food := float(c.get("logistics", {}).get("food_penalty", 0.0))
				if food > 0.0:
					r.append(["نقص الغذاء", -food * 1.5])
			"clergy":
				pass
		var t := 50.0
		for x in r:
			t += float(x[1])
		out[f] = {"target": clampf(t, 0.0, 100.0), "reasons": r}
	return out


# ------------------------------------------------------------------ الشهري

static func monthly(sim, c: Dictionary) -> void:
	var targets := compute_targets(sim, c)
	var drift := float(cfg(sim)["drift"])
	for f in ids(sim):
		var e: Dictionary = c["factions"][f]
		e["target"] = targets[f]["target"]
		e["reasons"] = targets[f]["reasons"]
		e["sat"] = clampf(float(e["sat"]) + (float(e["target"]) - float(e["sat"])) * drift, 0.0, 100.0)
	c["faction_delta"] = weighted(sim, c) - float(c.get("wsat_base", 50.0))
	_check_coup(sim, c)
	_check_revolution(sim, c)


## بعد انقلاب أو ثورة: فترة هدوء قبل أي تغيير جديد
static func _immune(sim, c: Dictionary) -> bool:
	return int(c.get("regime_change_day", -100000)) + int(cfg(sim)["regime_immunity_days"]) > int(sim.state["day"])


static func _check_coup(sim, c: Dictionary) -> void:
	if _immune(sim, c):
		c["coup_months"] = 0
		return
	var mil := float(c["factions"]["military"]["sat"])
	if mil >= COUP_THRESHOLD:
		c["coup_months"] = 0
		return
	c["coup_months"] = int(c.get("coup_months", 0)) + 1
	var name: String = c["name_ar"]
	if sim.is_player(c["id"]) and int(c["coup_months"]) == 1:
		sim.push_event("warning", "الجيش غاضب", "رضا الجيش انهار إلى %d. إن استمر سيحدث انقلاب. ارفع ميزانية الجيش أو استرضِ القادة." % int(mil), true)
		return
	if int(c["coup_months"]) < 2:
		return
	var p := 0.2 + weight(sim, c["government"], "military") * 0.5
	if not sim.rng.chance(p):
		return
	if sim.is_player(c["id"]):
		sim.state["game_over"] = "coup"
		sim.push_event("game_over", "انقلاب عسكري", "قادة الجيش أطاحوا بحكومتك بعد أشهر من الغضب.", true)
		return
	_set_government(sim, c, "military", "انقلاب عسكري في %s: الجيش يستولي على السلطة." % name)
	c["factions"]["military"]["sat"] = 70.0
	c["coup_months"] = 0


static func _check_revolution(sim, c: Dictionary) -> void:
	if _immune(sim, c):
		c["revolution_months"] = 0
		return
	var street := float(c["factions"]["street"]["sat"])
	if street >= REVOLUTION_THRESHOLD or float(c["stability"]) >= REVOLUTION_STABILITY:
		c["revolution_months"] = 0
		return
	c["revolution_months"] = int(c.get("revolution_months", 0)) + 1
	if sim.is_player(c["id"]) and int(c["revolution_months"]) == 1:
		sim.push_event("warning", "الشارع يغلي", "رضا الشارع %d والاستقرار %d. احتجاجات واسعة قد تتحول إلى ثورة." % [int(street), int(c["stability"])], true)
		return
	if int(c["revolution_months"]) < 2 or not sim.rng.chance(0.3):
		return
	if sim.is_player(c["id"]):
		sim.state["game_over"] = "revolution"
		sim.push_event("game_over", "ثورة شعبية", "الشارع أسقط حكومتك.", true)
		return
	# النظام الجديد: إسلامي إن كان رجال الدين أقوى من رجال الأعمال، وإلا برلماني
	var clergy := float(c["factions"]["clergy"]["sat"])
	var business := float(c["factions"]["business"]["sat"])
	var islamic_ok: bool = c["id"] in cfg(sim).get("islamic_possible", [])
	var gov := "islamic" if islamic_ok and clergy > business + 10.0 else "parliamentary"
	if gov == c["government"]:
		gov = "presidential"
	_set_government(sim, c, gov, "ثورة شعبية في %s تُسقط الحكومة وتقيم %s." % [c["name_ar"], sim.db.governments[gov]["name_ar"]])
	c["factions"]["street"]["sat"] = 60.0
	c["revolution_months"] = 0


static func _set_government(sim, c: Dictionary, gov: String, news: String) -> void:
	var old_gov: String = c["government"]
	c["government"] = gov
	c["policies"] = c["policies"].filter(func(p): return p == "conscription" and gov == "military")
	c["stability"] = maxf(5.0, float(c["stability"]) - 10.0)
	c["regime_change_day"] = int(sim.state["day"])
	shift_for_government(sim, c, old_gov, gov)
	sim.add_news(news, "war")


## الفئات ترحب بالنظام الذي تفضله وتستاء من غيره
static func shift_for_government(sim, c: Dictionary, old_gov: String, new_gov: String) -> void:
	for f in ids(sim):
		var d := (preference(sim, f, new_gov) - preference(sim, f, old_gov)) * 15.0
		c["factions"][f]["sat"] = clampf(float(c["factions"][f]["sat"]) + d, 0.0, 100.0)


# ------------------------------------------------------------------ تغيير الحكم والاسترضاء

## دعم الفئات لنظام جديد: كل فئة تدعم حسب ميلها له ورضاها ووزنها الحالي (0 إلى 1)
static func support(sim, c: Dictionary, new_gov: String) -> Dictionary:
	var gov: String = c["government"]
	var total := 0.0
	var parts := {}
	for f in ids(sim):
		var pref := (preference(sim, f, new_gov) + 1.0) / 2.0
		var sat := float(c["factions"][f]["sat"]) / 100.0
		var s := clampf(pref * (0.5 + sat), 0.0, 1.0)
		parts[f] = s
		total += weight(sim, gov, f) * s
	return {"total": total, "parts": parts}


static func appease_cost(sim, c: Dictionary) -> float:
	return float(c["gdp"]) * float(cfg(sim)["appease_cost_gdp"])


static func can_appease(sim, c: Dictionary, f: String) -> String:
	if not cfg(sim)["factions"].has(f):
		return "فئة غير معروفة."
	if int(c.get("appease_until", {}).get(f, -1)) > int(sim.state["day"]):
		return "استرضيتهم مؤخراً. انتظر %d يوماً." % (int(c["appease_until"][f]) - int(sim.state["day"]))
	if float(c["treasury"]) < appease_cost(sim, c):
		return "الخزينة لا تكفي."
	return ""


static func appease(sim, c: Dictionary, f: String) -> String:
	var why := can_appease(sim, c, f)
	if why != "":
		return why
	c["treasury"] = float(c["treasury"]) - appease_cost(sim, c)
	var e: Dictionary = c["factions"][f]
	e["sat"] = minf(100.0, float(e["sat"]) + float(cfg(sim)["appease_gain"]))
	if not c.has("appease_until"):
		c["appease_until"] = {}
	c["appease_until"][f] = int(sim.state["day"]) + int(cfg(sim)["appease_cooldown_days"])
	c["faction_delta"] = weighted(sim, c) - float(c.get("wsat_base", 50.0))
	return ""


## توقع أثر سياسة على كل فئة قبل تفعيلها أو إلغائها
static func policy_preview(sim, c: Dictionary, policy: String) -> Dictionary:
	var eff: Dictionary = cfg(sim)["policy_effects"].get(policy, {})
	var dir := -1.0 if policy in c["policies"] else 1.0
	var out := {}
	for f in eff:
		out[f] = float(eff[f]) * dir
	return out
