## سوق الموارد العالمي: أسعار تتغير مع العرض والحرب والعقوبات والأحداث، واتفاقيات تجارية.
## الحاجة من كل مورد = نصيب الدولة من اقتصاد العالم × مجموع العرض الأصلي.
## ريع الموارد جزء من ناتج مناطقها (احتلال منطقة نفطية ينقل ريعها مع ناتجها)،
## والميزانية تتأثر بأثر الأسعار: الصادرات أغلى تربح، والواردات أغلى تكلف.
extends RefCounted

const Logistics := preload("res://sim/logistics.gd")
const Straits := preload("res://sim/straits.gd")
const HISTORY := 36    # أشهر من تاريخ الأسعار
## حدود أثر التجارة على الميزانية (نسبة من الناتج): تقييمات الموارد مؤشرات نسبية لا كميات حقيقية
const MAX_GAIN := 0.08
const MAX_LOSS := 0.15


static func cfg(sim) -> Dictionary:
	return sim.db.market


static func commodities(sim) -> Array:
	return cfg(sim)["commodities"].keys()


# ------------------------------------------------------------------ الإعداد

static func init_state(sim) -> void:
	var totals := {}
	var prices := {}
	var history := {}
	for k in commodities(sim):
		var t := 0.0
		for id in sim.state["order"]:
			t += float(sim.country(id)["resources"].get(k, 0.0))
		totals[k] = t
		prices[k] = 1.0
		history[k] = [1.0]
	sim.state["market"] = {"prices": prices, "history": history, "shocks": {}, "world_supply": totals}
	sim.state["trade_pacts"] = {}
	for pair in cfg(sim).get("initial_pacts", []):
		sim.state["trade_pacts"][sim.rel_key(pair[0], pair[1])] = true
	for id in sim.state["order"]:
		sim.country(id)["trade_income"] = 0.0
	# إعادة حساب الإمداد بعد إنشاء الاتفاقيات (تزيد قدرة الاستيراد)
	for id in sim.state["order"]:
		var c2: Dictionary = sim.country(id)
		c2["logistics"] = Logistics.compute(sim, c2)


static func world_gdp(sim) -> float:
	var t := 0.0
	for id in sim.alive_ids():
		t += float(sim.country(id)["gdp"])
	return maxf(1.0, t)


static func price(sim, k: String) -> float:
	return float(sim.state["market"]["prices"].get(k, 1.0))


## حاجة الدولة من المورد حسب حجم اقتصادها
static func need(sim, c: Dictionary, k: String, wgdp: float) -> float:
	return float(sim.state["market"]["world_supply"][k]) * float(c["gdp"]) / wgdp


## نسبة ما تستطيع الدولة تصديره: العقوبات والحصار تخفضه
static func export_factor(sim, c: Dictionary) -> float:
	var conf := cfg(sim)
	var f: float = 1.0 - float(conf["sanction_export_cut"]) * c.get("sanctions", []).size()
	if Logistics.blockaded(sim, c):
		f = minf(f, float(conf["blockade_export_factor"]))
	# مضيق مغلق أو مهدد يقطع حصة صادرات من تمر تجارتهم به
	f *= 1.0 - Straits.export_loss(sim, c["id"])
	return clampf(f, 0.05, 1.0)


## صافي التجارة لكل مورد: موجب = تصدير، سالب = استيراد (ما يمكن استيراده فعلاً)
static func net_flows(sim, c: Dictionary, wgdp: float) -> Dictionary:
	var out := {}
	var ef := export_factor(sim, c)
	var imp := Logistics.import_capacity(sim, c)
	for k in commodities(sim):
		var s := float(c["resources"].get(k, 0.0))
		var n := need(sim, c, k, wgdp)
		out[k] = (s - n) * ef if s >= n else -(n - s) * imp
	return out


## أثر الأسعار على الميزانية الشهرية بالمليار دولار: صافي التجارة × (السعر − 1) × قيمة المورد
static func price_effect(sim, flows: Dictionary, prices: Dictionary) -> float:
	var v := 0.0
	for k in flows:
		v += float(flows[k]) * (float(prices[k]) - 1.0) * float(cfg(sim)["commodities"][k]["value"])
	return v


## صادرات لم تُبع بسبب الحصار والعقوبات والمضائق (مليار دولار شهرياً)
static func lost_exports(sim, c: Dictionary, wgdp: float, prices: Dictionary) -> float:
	var ef := export_factor(sim, c)
	if ef >= 1.0:
		return 0.0
	var v := 0.0
	for k in commodities(sim):
		var surplus := float(c["resources"].get(k, 0.0)) - need(sim, c, k, wgdp)
		if surplus > 0.0:
			v += surplus * (1.0 - ef) * float(prices[k]) * float(cfg(sim)["commodities"][k]["value"])
	return v


# ------------------------------------------------------------------ الشهري

static func monthly(sim) -> void:
	var conf := cfg(sim)
	var m: Dictionary = sim.state["market"]
	var wgdp := world_gdp(sim)
	var ids: Array = sim.alive_ids()
	for k in commodities(sim):
		# العرض المتاح للعالم: كل دولة تستهلك حاجتها، وتصدّر الفائض بقدر ما تسمح العقوبات والحصار
		var avail := 0.0
		var demand := 0.0
		for id in ids:
			var c: Dictionary = sim.country(id)
			var s := float(c["resources"].get(k, 0.0))
			var n := need(sim, c, k, wgdp)
			demand += n
			avail += minf(s, n) + maxf(0.0, s - n) * export_factor(sim, c)
		var ratio := demand / maxf(0.01, avail)
		var shock := 1.0
		if m["shocks"].has(k):
			shock = float(m["shocks"][k]["mult"])
		var info: Dictionary = conf["commodities"][k]
		var target := clampf(pow(ratio, float(info["elasticity"])) * shock, float(conf["price_min"]), float(conf["price_max"]))
		var old := float(m["prices"][k])
		var p := old + (target - old) * float(conf["smoothing"])
		m["prices"][k] = p
		var hist: Array = m["history"][k]
		hist.append(p)
		if hist.size() > HISTORY:
			hist.pop_front()
		if old > 0.0 and absf(p / old - 1.0) >= 0.15:
			var up := p > old
			sim.add_news("%s أسعار %s %d%% هذا الشهر." % ["ترتفع" if up else "تنخفض", info["name_ar"], int(absf(p / old - 1.0) * 100.0)], "world")
	# انتهاء الصدمات
	for k in m["shocks"].keys():
		m["shocks"][k]["months"] = int(m["shocks"][k]["months"]) - 1
		if int(m["shocks"][k]["months"]) <= 0:
			m["shocks"].erase(k)
	sim.state["global"]["oil_price"] = price(sim, "oil")
	# أثر الأسعار على كل دولة حسب ما تصدّره وتستورده فعلاً، وخسارة ما منعه الحصار والعقوبات
	for id in ids:
		var c: Dictionary = sim.country(id)
		var flows := net_flows(sim, c, wgdp)
		c["trade_flows"] = flows
		var lost := lost_exports(sim, c, wgdp, m["prices"])
		c["trade_lost"] = lost
		var gdp_month := float(c["gdp"]) / 12.0
		c["trade_income"] = clampf(price_effect(sim, flows, m["prices"]) - lost, -MAX_LOSS * gdp_month, MAX_GAIN * gdp_month)


static func apply_shock(sim, shocks: Dictionary, months: int) -> void:
	var m: Dictionary = sim.state["market"]
	for k in shocks:
		m["shocks"][k] = {"mult": float(shocks[k]), "months": months}


## سعر قبل 12 شهراً (أو أقدم ما لدينا)
static func price_year_ago(sim, k: String) -> float:
	var hist: Array = sim.state["market"]["history"][k]
	return float(hist[maxi(0, hist.size() - 13)])


# ------------------------------------------------------------------ الاتفاقيات التجارية

static func has_pact(sim, a: String, b: String) -> bool:
	return sim.state.get("trade_pacts", {}).has(sim.rel_key(a, b))


static func pacts_of(sim, id: String) -> Array:
	var out: Array = []
	for oid in sim.state["order"]:
		if oid != id and has_pact(sim, id, oid):
			out.append(oid)
	return out


static func pact_growth(sim, id: String) -> float:
	var conf: Dictionary = cfg(sim)["trade_pact"]
	return minf(float(conf["growth_cap"]), float(conf["growth"]) * pacts_of(sim, id).size())


static func can_sign_pact(sim, a: String, b: String) -> String:
	if a == b:
		return "طلب غير صالح."
	if has_pact(sim, a, b):
		return "بينكما اتفاقية بالفعل."
	if not sim.war_between(a, b).is_empty():
		return "لا اتفاقيات أثناء الحرب."
	if a in sim.country(b).get("sanctions", []) or b in sim.country(a).get("sanctions", []):
		return "ارفع العقوبات أولاً."
	var need_rel := float(cfg(sim)["trade_pact"]["min_relation"])
	if sim.relation(a, b) < need_rel:
		return "%s ترفض: العلاقات يجب أن تكون %d على الأقل." % [sim.country(b)["name_ar"], int(need_rel)]
	return ""


static func sign_pact(sim, a: String, b: String) -> String:
	var why := can_sign_pact(sim, a, b)
	if why != "":
		return why
	sim.state["trade_pacts"][sim.rel_key(a, b)] = true
	sim.change_relation(a, b, 5.0)
	_refresh(sim, [a, b])
	sim.add_news("اتفاقية تجارية بين %s و%s." % [sim.country(a)["name_ar"], sim.country(b)["name_ar"]], "good")
	return ""


static func cancel_pact(sim, a: String, b: String, reason: String = "") -> void:
	if not has_pact(sim, a, b):
		return
	sim.state["trade_pacts"].erase(sim.rel_key(a, b))
	_refresh(sim, [a, b])
	var text := "إلغاء الاتفاقية التجارية بين %s و%s" % [sim.country(a)["name_ar"], sim.country(b)["name_ar"]]
	sim.add_news(text + ("، " + reason if reason != "" else "") + ".", "info")


static func _refresh(sim, ids: Array) -> void:
	for id in ids:
		var c: Dictionary = sim.country(id)
		c["logistics"] = Logistics.compute(sim, c)
