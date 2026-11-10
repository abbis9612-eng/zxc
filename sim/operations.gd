## العمليات العسكرية: هدف واحد وحجم ودعم. التوقع بلا آثار جانبية (preview)، والإطلاق (launch)
## يأمر الفرق بالهجوم ويسجل العملية في الحرب ليركّز عليها القتال اليومي (sim/front.gd).
extends RefCounted

const Divisions := preload("res://sim/divisions.gd")
const Front := preload("res://sim/front.gd")
const Territory := preload("res://sim/territory.gd")


static func cfg(sim) -> Dictionary:
	return sim.db.military["operations"]


## العملية النشطة لطرف (دولة أو حليف لها) على هدف، أو {}
static func active_for(sim, w: Dictionary, side: Array) -> Dictionary:
	var day := int(sim.state["day"])
	for op in w.get("ops", []):
		if String(op["side"]) in side and int(op["until"]) >= day:
			return op
	return {}


## إزالة العمليات المنتهية أو التي سقط هدفها
static func cleanup(sim, w: Dictionary) -> void:
	if not w.has("ops"):
		return
	var day := int(sim.state["day"])
	w["ops"] = w["ops"].filter(func(op): return int(op["until"]) >= day and sim.state["regions"][op["target"]]["owner"] in sim.enemies_of(op["side"]))


## الفرق المتاحة للعملية: واقفة، بلا أمر هجوم، ولها طريق إلى منطقة تجاور الهدف. الأقرب أولاً
static func available(sim, pid: String, rid: String) -> Array:
	var cand: Array = []
	for d in Divisions.of(sim, pid):
		if int(d["eta"]) >= 0 or d.get("attack", "") != "":
			continue
		var pv: Dictionary = Divisions.attack_preview(sim, [int(d["id"])], rid)
		if pv["why"] == "":
			cand.append([int(pv["days"]), int(d["id"])])
	cand.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return cand


static func preview(sim, pid: String, rid: String, size: String, support: String) -> Dictionary:
	var conf := cfg(sim)
	var out := {"why": "", "ids": [], "move_days": 0, "days": -1, "chance": 0.0, "cost": 0.0, "support_why": "", "loss": 0.0, "available": 0}
	if not sim.state["regions"].has(rid):
		out["why"] = "منطقة غير معروفة."
		return out
	var owner: String = sim.state["regions"][rid]["owner"]
	var w: Dictionary = sim.war_between(pid, owner)
	if w.is_empty():
		out["why"] = "لست في حرب مع %s." % sim.country(owner)["name_ar"]
		return out
	var c: Dictionary = sim.country(pid)
	var cand := available(sim, pid, rid)
	out["available"] = cand.size()
	if cand.is_empty():
		out["why"] = "لا فرق متاحة تصل إلى %s. حرّك فرقاً نحو الجبهة أولاً." % sim.db.regions[rid]["name_ar"]
		return out
	var n := clampi(int(ceilf(float(cand.size()) * float(conf["sizes"][size]["share"]))), 1, cand.size())
	var ids: Array = []
	var move_days := 0
	for i in n:
		ids.append(cand[i][1])
		move_days = maxi(move_days, int(cand[i][0]))
	out["ids"] = ids
	out["move_days"] = move_days
	# الكلفة
	var sup: Dictionary = conf["supports"][support]
	var gdp := float(c["gdp"])
	out["cost"] = gdp * (float(conf["cost_per_div_gdp"]) * float(n) + float(sup["cost_gdp"]))
	if support == "air":
		if Front._nearest_base(sim, [pid], rid) == "":
			out["support_why"] = "لا قاعدة جوية عاملة في مدى مقاتلاتك من الهدف."
		elif float(c["military"].get("fighters", 0.0)) < 1.0:
			out["support_why"] = "لا مقاتلات لديك."
	elif support == "missiles" and float(c["military"].get("missiles", 0.0)) < 1.0:
		out["support_why"] = "لا صواريخ لديك."
	if float(c["treasury"]) < float(out["cost"]):
		out["why"] = "الخزينة لا تكفي: تحتاج %s مليار." % String.num(float(out["cost"]), 1)
	# التوقع: قوة الفرق المختارة (بعد وصولها) مقابل دفاع الهدف الآن
	var in_a: bool = pid in w["attackers"]
	var fc := Front.cfg(sim)
	var dconf: Dictionary = sim.db.military["divisions"]
	var exp_b := float(dconf["exp_bonus"])
	var n_divs := Divisions.of(sim, pid).size()
	var dp: float = Front._div_power(sim, w, pid, in_a, n_divs)
	var p := 0.0
	for did in ids:
		var d := Divisions.find(sim, int(did))
		p += dp * float(d["strength"]) * (1.0 + exp_b * float(d["exp"])) * (1.0 + float(dconf.get("attack_bonus", 0.0)))
	if out["support_why"] == "":
		p *= float(sup["pressure"])
	var held := 0.0
	var odp: float = Front._div_power(sim, w, owner, not in_a, Divisions.of(sim, owner).size())
	for d in sim.state["divisions"]:
		if d["owner"] == owner and d["region"] == rid and int(d["eta"]) < 0:
			held += odp * float(d["strength"]) * (1.0 + exp_b * float(d["exp"]))
	var defense: float = (odp * float(fc["garrison"]) + held) * float(fc["defender_bonus"])
	if sim.db.regions[rid]["capital"]:
		defense *= float(fc["capital_bonus"])
	var ratio := p / (p + defense + 0.001)
	out["ratio"] = ratio
	out["chance"] = clampf(0.5 + (ratio - 0.55) * 3.0, 0.05, 0.95)
	if sim.db.regions[rid]["capital"] and ratio < float(fc["capital_min_ratio"]):
		out["chance"] = minf(float(out["chance"]), 0.15)
	if ratio > 0.5:
		var per_day: float = float(fc["rate"]) * (ratio - 0.5) * 2.0 / Territory.capture_cost(sim, rid)
		out["days"] = move_days + int(ceilf(Front.control(sim, rid) / per_day))
	# الخسائر المتوقعة: من قوة الفرق المهاجمة طوال مدة القتال
	var fight_days := (int(out["days"]) - move_days) if int(out["days"]) > 0 else int(conf["days"])
	out["loss"] = clampf(float(fc["div_loss"]) * (1.0 - ratio) * 2.0 * float(fc["attack_loss"]) * float(fight_days), 0.0, 0.8)
	return out


static func launch(sim, pid: String, rid: String, size: String, support: String) -> String:
	var pv := preview(sim, pid, rid, size, support)
	if pv["why"] != "":
		return pv["why"]
	var err: String = Divisions.order_attack(sim, pv["ids"], rid)
	if err != "":
		return err
	var c: Dictionary = sim.country(pid)
	c["treasury"] = float(c["treasury"]) - float(pv["cost"])
	var w: Dictionary = sim.war_between(pid, sim.state["regions"][rid]["owner"])
	if not w.has("ops"):
		w["ops"] = []
	w["ops"] = w["ops"].filter(func(op): return op["side"] != pid)
	w["ops"].append({"side": pid, "target": rid, "size": size,
		"support": support if pv["support_why"] == "" else "none",
		"until": int(sim.state["day"]) + int(pv["move_days"]) + int(cfg(sim)["days"])})
	return ""
