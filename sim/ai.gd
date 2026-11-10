## الذكاء الاصطناعي للدول: يخطط شهرياً على مستويات: اقتصاد، تسليح، بحث، دبلوماسية، ثم حرب.
## الشخصيات: cautious حذرة، ambitious طموحة، opportunist انتهازية.
extends RefCounted

const Economy := preload("res://sim/economy.gd")

## عتبة العلاقات وتفوق القوة المطلوب لإعلان الحرب، واحتمالها الشهري
const WAR_RULES := {
	"cautious": {"relation": -95.0, "ratio": 3.0, "chance": 0.02},
	"ambitious": {"relation": -55.0, "ratio": 1.8, "chance": 0.06},
	"opportunist": {"relation": -65.0, "ratio": 2.2, "chance": 0.08},
}

## ميزان التسليح المرغوب: حصة كل صنف من ميزانية الشراء
const BUY_WEIGHTS := {
	"armor": 0.18, "artillery": 0.10, "fighters": 0.22, "drones": 0.10,
	"air_defense": 0.15, "missiles": 0.10, "ships": 0.08, "infantry": 0.07,
}


static func monthly(sim, c: Dictionary) -> void:
	var difficulty: int = int(sim.state.get("difficulty", 1))
	_economy(sim, c)
	_research(sim, c)
	_armament(sim, c, difficulty)
	_diplomacy(sim, c)
	_war(sim, c, difficulty)


static func _economy(sim, c: Dictionary) -> void:
	var b: Dictionary = c.get("last_budget", {})
	if b.is_empty():
		return
	var tol: float = Economy.tax_tolerance(sim, c) + 0.03
	var gdp := float(c["gdp"])
	if float(b["balance"]) < 0.0 and float(c["treasury"]) < gdp * 0.01:
		if float(c["tax_rate"]) < tol - 0.01:
			sim.set_tax(c["id"], float(c["tax_rate"]) + 0.01)
	elif float(c["treasury"]) > gdp * 0.08 and float(c["tax_rate"]) > 0.12:
		sim.set_tax(c["id"], float(c["tax_rate"]) - 0.01)
	# سياسات بسيطة
	var at_war: bool = not sim.wars_of(c["id"]).is_empty()
	if at_war and not ("war_economy" in c["policies"]) and float(c["stability"]) > 35.0:
		sim.toggle_policy(c["id"], "war_economy")
	elif not at_war and "war_economy" in c["policies"]:
		sim.toggle_policy(c["id"], "war_economy")
	if float(c["stability"]) < 30.0 and not ("subsidies" in c["policies"]) and float(c["treasury"]) > gdp * 0.02:
		sim.toggle_policy(c["id"], "subsidies")


static func _research(sim, c: Dictionary) -> void:
	# التركيز على أضعف فرع
	var best := ""
	var low := 99
	for br in sim.db.branches:
		var g := int(c["tech"][br])
		if g < low:
			low = g
			best = br
	if best != "" and best != c["research_focus"] and float(c["research_progress"]) < 1.0:
		sim.set_research(c["id"], float(c["research_ratio"]), best)


static func _armament(sim, c: Dictionary, difficulty: int) -> void:
	var gdp := float(c["gdp"])
	var reserve := gdp * 0.02
	var at_war: bool = not sim.wars_of(c["id"]).is_empty()
	var spend_share := 0.5 if at_war else 0.25
	spend_share *= 0.7 + 0.3 * difficulty
	var budget := (float(c["treasury"]) - reserve) * spend_share
	if budget <= 0.05:
		return
	for u in BUY_WEIGHTS:
		var unit_c: float = sim.unit_cost(c, u)
		var count := floorf(budget * float(BUY_WEIGHTS[u]) / unit_c)
		if (u == "ships" or u == "submarines") and float(c["military"]["ships"]) < 1.0:
			continue
		if count >= 1.0:
			sim.order_units(c["id"], u, count)


static func _diplomacy(sim, c: Dictionary) -> void:
	var id: String = c["id"]
	if not sim.wars_of(id).is_empty():
		return
	# تحسين العلاقات مع أقرب دولة صديقة غير حليفة
	if sim.rng.chance(0.15):
		for n in c["neighbors"]:
			if sim.country(n).is_empty():
				continue
			var r: float = sim.relation(id, n)
			if r > 20.0 and r < 70.0:
				sim.improve_relations(id, n)
				break


static func _war(sim, c: Dictionary, difficulty: int) -> void:
	var id: String = c["id"]
	if c.get("overlord", "") != "":
		return
	var my_wars: Array = sim.wars_of(id)
	# طلب السلام عند الخسارة
	for w in my_wars:
		var my_score := float(w["score"]) if id in w["attackers"] else -float(w["score"])
		var lead: String = w["defenders"][0] if id in w["attackers"] else w["attackers"][0]
		if id != w["attackers"][0] and id != w["defenders"][0]:
			continue
		var days := int(sim.state["day"]) - int(w["start_day"])
		var stalemate := days > 365 and absf(my_score) < 10.0
		if my_score < -30.0 or (float(c["stability"]) < 20.0 and my_score < 10.0) or stalemate:
			if sim.is_player(lead):
				if not w.get("offer_sent", false):
					w["offer_sent"] = true
					sim.push_event("peace_offer", "عرض سلام", "%s تعرض عليك السلام. هل تقبل؟" % c["name_ar"], true, ["قبول", "رفض"], {"war_id": w["id"]})
			else:
				sim.propose_peace(id, lead)
	if not my_wars.is_empty():
		return
	var rules: Dictionary = WAR_RULES.get(c.get("personality", "cautious"), WAR_RULES["cautious"])
	if float(c["stability"]) < 35.0:
		return
	var my_power: float = sim.bloc_power(id)
	for n in c["neighbors"]:
		var target: Dictionary = sim.country(n)
		if target.is_empty() or target.get("overlord", "") != "":
			continue
		if sim.relation(id, n) > float(rules["relation"]):
			continue
		if sim.can_declare_war(id, n) != "":
			continue
		var their: float = sim.bloc_power(n)
		# الصعوبة الأعلى تجعل الذكاء أكثر جرأة مع اللاعب
		var ratio_need := float(rules["ratio"])
		if sim.is_player(n):
			ratio_need -= 0.2 * difficulty
		if my_power < their * ratio_need:
			continue
		if sim.rng.chance(float(rules["chance"])):
			sim.declare_war(id, n)
			return
