## الاقتصاد الشهري: الناتج والميزانية والديون والتضخم والبحث والاستقرار.
## كل الدوال ثابتة وتأخذ المحاكاة sim والدولة c.
extends RefCounted

const Territory := preload("res://sim/territory.gd")
const Market := preload("res://sim/market.gd")
const Development := preload("res://sim/development.gd")

const RESEARCH_BASE_COST := 4.0   # مليار × (الجيل التالي)²
const EQUIPMENT_FACTOR := 3.0


static func gdp_per_capita(c: Dictionary) -> float:
	return float(c["gdp"]) * 1000.0 / maxf(0.1, float(c["population"]))


## صيانة الجيش السنوية بالمليار دولار
static func military_upkeep(sim, c: Dictionary) -> float:
	var gdp_pc := gdp_per_capita(c)
	var price := clampf(gdp_pc / 40000.0, 0.2, 1.5)
	var total := 0.0
	for k in sim.db.units:
		var u: Dictionary = sim.db.units[k]
		var n := float(c["military"].get(k, 0.0))
		if k == "infantry":
			total += n * float(u["upkeep"]) * (gdp_pc / 10000.0) / 1000.0
		else:
			total += n * float(u["upkeep"]) * sim.db.gen_multiplier(int(c["tech"][u["branch"]])) * EQUIPMENT_FACTOR * price / 1000.0
	var mod := 1.0
	for p in c["policies"]:
		mod += float(sim.db.policies[p].get("military_cost", 0.0))
	return total * maxf(0.5, mod)


## الإنفاق المدني يُضبط في البداية بحيث تبدأ الميزانية متوازنة تقريباً
static func init_civil_spending(sim, c: Dictionary) -> void:
	var gdp := float(c["gdp"])
	var mil := military_upkeep(sim, c) / gdp
	var interest := float(c["debt"]) / gdp * 0.04
	c["civil_ratio"] = maxf(0.04, float(c["tax_rate"]) - mil - float(c["research_ratio"]) - interest - 0.005)
	# الشعب معتاد على مستوى الضرائب الذي بدأ به
	c["tax_base"] = float(c["tax_rate"])


static func policy_sum(sim, c: Dictionary, field: String) -> float:
	var s := 0.0
	for p in c["policies"]:
		s += float(sim.db.policies[p].get(field, 0.0))
	return s


## أعلى ضريبة يتقبلها الشعب بلا غضب
static func tax_tolerance(sim, c: Dictionary) -> float:
	var gov: Dictionary = sim.db.governments[c["government"]]
	return maxf(0.30, float(c.get("tax_base", 0.30))) + float(gov["tax_tolerance"])


static func research_cost(next_gen: int) -> float:
	return RESEARCH_BASE_COST * next_gen * next_gen


## توقع البحث بلا آثار جانبية: الأشهر الباقية حتى الجيل التالي في فرع، بنسبة إنفاق معينة.
## يحسب نصف التقدم إن كان الفرع غير المركّز عليه (لأن تغيير التركيز يضيّع النصف).
## يرجع -1 إن كان الفرع في أعلى جيل، و-2 إن احتاج الجيل الخامس اقتصاداً بحجم 500 مليار.
static func research_months(sim, c: Dictionary, branch: String, ratio: float) -> int:
	var gen := int(c["tech"][branch])
	if gen >= 5:
		return -1
	if gen + 1 >= 5 and float(c["gdp"]) < 500.0:
		return -2
	var gov: Dictionary = sim.db.governments[c["government"]]
	var mult := maxf(0.2, 1.0 + float(gov["research"]) + policy_sum(sim, c, "research") + Development.num(sim, c, "research"))
	var per_month := float(c["gdp"]) * ratio / 12.0 * mult
	var prog := float(c["research_progress"])
	if branch != c["research_focus"]:
		prog *= 0.5
	var left := maxf(0.0, research_cost(gen + 1) - prog)
	if per_month <= 0.0:
		return 9999
	# الاقتصاد ينمو فيزيد مال البحث كل شهر: نحسب شهراً بشهر بالنمو الحالي
	var monthly_growth := pow(1.0 + clampf(growth_rate(sim, c), -20.0, 20.0) / 100.0, 1.0 / 12.0)
	var months := 0
	while left > 0.0 and months < 1200:
		left -= per_month
		per_month *= monthly_growth
		months += 1
	return months


static func growth_rate(sim, c: Dictionary) -> float:
	var gov: Dictionary = sim.db.governments[c["government"]]
	var g: Dictionary = sim.state["global"]
	var growth := float(c["growth"]) + float(gov["growth"]) + policy_sum(sim, c, "growth")
	growth += float(g["growth_mod"])
	growth += (float(c["stability"]) - 50.0) * 0.03
	growth -= maxf(0.0, float(c["inflation"]) - 5.0) * 0.15
	growth -= (float(c["tax_rate"]) - 0.25) * 4.0
	growth -= sim.wars_of(c["id"]).size() * 1.0
	if c.get("capital_fallen", false):
		growth -= 3.0
	var sanction_mult := 1.0
	if "open_economy" in c["policies"]:
		sanction_mult = float(sim.db.policies["open_economy"].get("sanction_effect", 1.0))
	growth -= c["sanctions"].size() * 0.7 * sanction_mult
	if float(c["debt"]) > float(c["gdp"]) * 1.2:
		growth -= 1.0
	# محطات الكهرباء المعطلة تبطئ الاقتصاد
	growth -= float(c.get("logistics", {}).get("growth_penalty", 0.0))
	# الاتفاقيات التجارية تنشط الاقتصاد
	growth += Market.pact_growth(sim, c["id"])
	growth += float(c["resources"].get("oil", 0.0)) / 100.0 * (float(g["oil_price"]) - 1.0) * 6.0
	growth += Development.num(sim, c, "growth")
	return growth


## dry = true: حساب فقط بلا آثار جانبية على دول أخرى أو الأخبار (للتوقعات)
static func monthly(sim, c: Dictionary, dry: bool = false) -> void:
	var gov: Dictionary = sim.db.governments[c["government"]]
	var gdp := float(c["gdp"])

	# النمو: في المحاكاة الفعلية طُبق مسبقاً على كل المناطق (Territory.grow_all)
	var growth: float
	if dry or not c.has("growth_now"):
		growth = growth_rate(sim, c)
		gdp = maxf(1.0, gdp * (1.0 + growth / 1200.0))
		c["gdp"] = gdp
	else:
		growth = float(c["growth_now"])

	# الميزانية الشهرية بالمليار
	var revenue := gdp * float(c["tax_rate"]) / 12.0
	var tribute := 0.0
	if c.get("overlord", "") != "":
		tribute = revenue * 0.08
		var o: Dictionary = sim.country(c["overlord"])
		if not o.is_empty() and not dry:
			o["treasury"] = float(o["treasury"]) + tribute
	var military := military_upkeep(sim, c) / 12.0
	var civil := gdp * float(c["civil_ratio"]) / 12.0
	var subsidies := gdp * policy_sum(sim, c, "budget_gdp") / 12.0
	var research := gdp * float(c["research_ratio"]) / 12.0
	var interest := float(c["debt"]) * 0.04 / 12.0
	# التجارة: أثر أسعار الموارد وفقدانها أو كسبها (الفرق عن وضع البداية)
	var trade := float(c.get("trade_income", 0.0))
	# مكافحة التجسس (نسبة سنوية من الناتج حسب المستوى)
	var intel := 0.0
	var levels: Array = sim.db.intel.get("counter_levels", [])
	if not levels.is_empty():
		intel = gdp * float(levels[clampi(int(c.get("counter_intel", 0)), 0, levels.size() - 1)]["cost_gdp"]) / 12.0
	var balance := revenue + trade - tribute - military - civil - subsidies - research - interest - intel
	c["treasury"] = float(c["treasury"]) + balance
	if float(c["treasury"]) < 0.0:
		c["debt"] = float(c["debt"]) - float(c["treasury"])
		c["treasury"] = 0.0
	elif float(c["treasury"]) > gdp * 0.10 and float(c["debt"]) > 0.0:
		var pay := minf(float(c["debt"]), float(c["treasury"]) - gdp * 0.10)
		c["debt"] = float(c["debt"]) - pay
		c["treasury"] = float(c["treasury"]) - pay

	# التضخم
	var deficit_pct := -balance * 12.0 / gdp * 100.0
	var inflation := float(c["inflation"])
	if deficit_pct > 3.0:
		inflation += (deficit_pct - 3.0) * 0.15
	inflation += (2.5 - inflation) * 0.08
	c["inflation"] = clampf(inflation, -2.0, 200.0)

	# البحث
	var focus: String = c["research_focus"]
	var track_name: String = sim.db.branches.get(focus, Development.track(sim, focus).get("name_ar", ""))
	if track_name != "" and int(c["tech"].get(focus, 1)) < 5 and not dry:
		var gen := int(c["tech"][focus])
		var mult := 1.0 + float(gov["research"]) + policy_sum(sim, c, "research") + Development.num(sim, c, "research")
		c["research_progress"] = float(c["research_progress"]) + research * maxf(0.2, mult)
		var need := research_cost(gen + 1)
		var industry_ok := gen + 1 < 5 or gdp >= 500.0
		var blocked := Development.gate_block(sim, c, focus, gen + 1)
		if float(c["research_progress"]) >= need and industry_ok and blocked == "":
			c["tech"][focus] = gen + 1
			c["research_progress"] = 0.0
			sim.add_news("%s تصل إلى الجيل %d في %s." % [c["name_ar"], gen + 1, track_name], "good" if sim.is_player(c["id"]) else "info")
		elif blocked != "" and float(c["research_progress"]) >= need and sim.is_player(c["id"]) and not c.get("gate_told", false):
			c["gate_told"] = true
			sim.add_news(blocked, "info")

	# الاستقرار
	var tol := tax_tolerance(sim, c)
	var target := 50.0 + float(gov["stability"]) + policy_sum(sim, c, "stability")
	target += float(sim.state["global"]["stability_mod"])
	target += (growth - 2.0) * 2.0
	target -= maxf(0.0, float(c["tax_rate"]) - tol) * 150.0
	target -= maxf(0.0, float(c["inflation"]) - 4.0) * 1.2
	target -= sim.wars_of(c["id"]).size() * 5.0
	if c.get("capital_fallen", false):
		target -= 15.0
	if float(c["debt"]) > gdp * 1.2:
		target -= 5.0
	if c.get("overlord", "") != "":
		target -= 5.0
	# المناطق المحتلة تحتاج قوات وتثير الاحتجاج
	target -= minf(10.0, Territory.occupied_count(sim, c["id"]) * 0.4)
	# نقص الغذاء (خاصة تحت الحصار) يغضب الشارع
	target -= float(c.get("logistics", {}).get("food_penalty", 0.0))
	# رضا الفئات الداخلية الموزون حسب نظام الحكم
	target += float(c.get("faction_delta", 0.0)) * float(sim.db.factions.get("stability_weight", 0.0))
	target += Development.num(sim, c, "stability")
	target = clampf(target, 0.0, 100.0)
	c["stability"] = clampf(float(c["stability"]) + (target - float(c["stability"])) * 0.12, 0.0, 100.0)

	c["last_budget"] = {
		"revenue": revenue, "trade": trade, "intel": intel, "tribute": tribute, "military": military, "civil": civil,
		"subsidies": subsidies, "research": research, "interest": interest,
		"balance": balance, "growth": growth, "stability_target": target,
	}


## توقع أثر قرار قبل تنفيذه: يحسب الشهر القادم على نسخة من الدولة
static func preview(sim, c: Dictionary, changes: Dictionary) -> Dictionary:
	var copy: Dictionary = c.duplicate(true)
	for k in changes:
		copy[k] = changes[k]
	var before_stab := float(copy["stability"])
	monthly(sim, copy, true)
	var b: Dictionary = copy["last_budget"]
	return {"balance": b["balance"], "growth": b["growth"], "stability_target": b["stability_target"], "stability_change": float(copy["stability"]) - before_stab}
