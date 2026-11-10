## حساب المعارك على مراحل: الجو، ثم الضربات، ثم البحر، ثم البر.
## النتيجة تُحسب هنا أولاً، ومشهد المعركة ثلاثي الأبعاد (لاحقاً) يعرض هذا التقرير بأمانة.
extends RefCounted

const FRONT_SHARE := 0.35      # نسبة الجيش المشاركة في جبهة واحدة
const DEFENDER_BONUS := 1.25
const FAR_SUPPLY := 0.6        # قوات بلا جبهة برية مع العدو تضعف بالإمداد
const MAX_GAINS := 2           # أقصى عدد مناطق تسقط في معركة أسبوعية
const GAIN_RATE := 2.0         # تقدم أسبوعي لكل وحدة تفوق (منطقة صغيرة تحتاج 0.7)
const AIR_LAND_BASE := 0.5     # التفوق الجوي يضاعف أثر القوات البرية
const AIR_LAND_WEIGHT := 1.0
const STRIKE_MONTHS := 4       # مدة تعطل المنشأة بعد ضربة في معركة
const STRIKE_REF := 150.0      # قوة الضربات التي تكفي لضربة استراتيجية أسبوعية تقريباً
const STRIKE_PRIORITY := ["airbase", "refinery", "factory", "power_plant", "port"]

const Territory := preload("res://sim/territory.gd")
const Logistics := preload("res://sim/logistics.gd")
const Divisions := preload("res://sim/divisions.gd")

const PHASE_UNITS := {
	"air": ["fighters"],
	"strike": ["missiles", "drones", "artillery", "bombers"],
	"sea": ["ships", "submarines"],
	"land": ["infantry", "armor", "helicopters"],
}


static func _share(sim, id: String) -> float:
	return FRONT_SHARE / maxf(1.0, float(sim.wars_of(id).size()))


## الإمداد: جبهة برية مباشرة مع مناطق العدو، أو عبر أرض حليف أو تابع
static func _supply(sim, id: String, enemies: Array) -> float:
	if Territory.has_land_front(sim, [id], enemies):
		return 1.0
	if Territory.has_land_front(sim, sim.allies(id) + sim.vassals(id), enemies):
		return 0.85
	return FAR_SUPPLY


## مضاعف وصول الصنف إلى هذه الجبهة: البر من انتشار الفرق، والجو من مدى القواعد، والصواريخ من مداها
static func _factor(id: String, u: String, th: Dictionary, share: float) -> float:
	if not th.has(id):
		return share
	var t: Dictionary = th[id]
	match u:
		"infantry", "armor", "helicopters", "artillery":
			return float(t["land"])
		"fighters":
			return share * float(t["air"])
		"bombers":
			return share * float(t["bombers"])
		"missiles":
			return share * float(t["missiles"])
		"drones":
			return share * float(t["drones"])
		"ships", "submarines":
			return share * float(t.get("sea", 1.0))
	return share


static func _side_power(sim, side: Array, utypes: Array, th: Dictionary = {}) -> float:
	var total := 0.0
	for id in side:
		var c: Dictionary = sim.country(id)
		var f := _share(sim, id)
		for u in utypes:
			total += sim.unit_power(c, u) * _factor(id, u, th, f)
	return total


## عوامل المسرح لكل دولة في الطرفين
static func _theaters(sim, A: Array, D: Array) -> Dictionary:
	var th := {}
	for id in A:
		th[id] = Divisions.theater(sim, id, A, D)
	for id in D:
		th[id] = Divisions.theater(sim, id, D, A)
	return th


static func _apply_losses(sim, side: Array, utypes: Array, pct: float, record: Dictionary) -> void:
	for id in side:
		var c: Dictionary = sim.country(id)
		var f := _share(sim, id)
		for u in utypes:
			var n := float(c["military"][u])
			var lost := n * clampf(pct * f, 0.0, 0.5)
			c["military"][u] = n - lost
			record[u] = float(record.get(u, 0.0)) + lost


static func _morale(sim, side: Array) -> float:
	var s := 0.0
	for id in side:
		s += float(sim.country(id)["stability"])
	return 0.6 + (s / maxf(1.0, side.size())) / 250.0


static func weekly_battle(sim, w: Dictionary) -> Dictionary:
	var A: Array = w["attackers"].filter(func(x): return sim.country(x).get("overlord", "") == "" or sim.country(x)["overlord"] in w["attackers"])
	var D: Array = w["defenders"].filter(func(x): return sim.country(x).get("overlord", "") == "" or sim.country(x)["overlord"] in w["defenders"])
	if A.is_empty() or D.is_empty():
		sim.make_peace(w)
		return {}
	var rng = sim.rng
	var th := _theaters(sim, A, D)
	var loss_a := {}
	var loss_d := {}
	var phases: Array = []

	# 1) الجو
	var air_a := _side_power(sim, A, PHASE_UNITS["air"], th)
	var air_d := _side_power(sim, D, PHASE_UNITS["air"], th)
	var ad_a := _side_power(sim, A, ["air_defense"], th)
	var ad_d := _side_power(sim, D, ["air_defense"], th)
	var sup_a := air_a / (air_a + air_d + 0.5 * ad_d + 0.001)
	var sup_d := air_d / (air_d + air_a + 0.5 * ad_a + 0.001)
	_apply_losses(sim, A, ["fighters"], 0.04 * (1.0 - sup_a) * rng.range_f(0.7, 1.3), loss_a)
	_apply_losses(sim, D, ["fighters"], 0.04 * (1.0 - sup_d) * rng.range_f(0.7, 1.3), loss_d)
	phases.append({"id": "air", "name_ar": "المعركة الجوية", "a": air_a, "d": air_d + 0.5 * ad_d, "result": sup_a - sup_d})

	# 2) الضربات: صواريخ ومسيّرات ومدفعية وقاذفات، ضد الدفاع الجوي
	var strike_a := _side_power(sim, A, ["missiles", "drones", "artillery"], th) + _side_power(sim, A, ["bombers"], th) * sup_a
	var strike_d := _side_power(sim, D, ["missiles", "drones", "artillery"], th) + _side_power(sim, D, ["bombers"], th) * sup_d
	var intercept_d := clampf(ad_d / (ad_d + strike_a + 0.001), 0.05, 0.85)
	var intercept_a := clampf(ad_a / (ad_a + strike_d + 0.001), 0.05, 0.85)
	var eff_a: float = strike_a * (1.0 - intercept_d) * rng.range_f(0.85, 1.15)
	var eff_d: float = strike_d * (1.0 - intercept_a) * rng.range_f(0.85, 1.15)
	_apply_losses(sim, A, ["missiles"], 0.05, loss_a)
	_apply_losses(sim, A, ["drones"], 0.08, loss_a)
	_apply_losses(sim, D, ["missiles"], 0.05, loss_d)
	_apply_losses(sim, D, ["drones"], 0.08, loss_d)
	_apply_losses(sim, D, ["air_defense"], 0.03 * eff_a / (eff_a + ad_d + 0.001), loss_d)
	_apply_losses(sim, A, ["air_defense"], 0.03 * eff_d / (eff_d + ad_a + 0.001), loss_a)
	# ضرب الأهداف الاستراتيجية في العمق: قواعد ومصافٍ ومصانع ومحطات وموانئ
	# عدد الضربات حسب اختراق الدفاع الجوي وحجم القوة الضاربة الفعلي
	var hits_a := _strategic_strikes(sim, A, D, eff_a / (eff_a + ad_d + 0.001) * eff_a / (eff_a + STRIKE_REF))
	var hits_d := _strategic_strikes(sim, D, A, eff_d / (eff_d + ad_a + 0.001) * eff_d / (eff_d + STRIKE_REF))
	phases.append({"id": "strike", "name_ar": "الضربات الصاروخية والمسيّرات والمدفعية", "a": eff_a, "d": eff_d, "result": (eff_a - eff_d) / (eff_a + eff_d + 0.001), "intercept_a": intercept_a, "intercept_d": intercept_d})

	# 3) البحر
	var sea_a := _side_power(sim, A, PHASE_UNITS["sea"], th)
	var sea_d := _side_power(sim, D, PHASE_UNITS["sea"], th)
	var naval_a := 0.5
	if sea_a + sea_d > 0.001:
		naval_a = sea_a / (sea_a + sea_d) * rng.range_f(0.9, 1.1)
		naval_a = clampf(naval_a, 0.0, 1.0)
		_apply_losses(sim, A, PHASE_UNITS["sea"], 0.03 * (1.0 - naval_a), loss_a)
		_apply_losses(sim, D, PHASE_UNITS["sea"], 0.03 * naval_a, loss_d)
		phases.append({"id": "sea", "name_ar": "المعركة البحرية", "a": sea_a, "d": sea_d, "result": naval_a * 2.0 - 1.0})
		# الحصار البحري: الطرف المهزوم بحرياً يفقد معظم وارداته
		var until := int(sim.state["day"]) + Logistics.BLOCKADE_DAYS
		if naval_a > 0.7:
			for id in D:
				sim.country(id)["blockade_until"] = until
		elif naval_a < 0.3:
			for id in A:
				sim.country(id)["blockade_until"] = until

	# 4) البر
	var land_a := 0.0
	for id in A:
		land_a += _side_power(sim, [id], PHASE_UNITS["land"], th) * _supply(sim, id, D)
	var land_d := _side_power(sim, D, PHASE_UNITS["land"], th)
	var total_a: float = land_a * (AIR_LAND_BASE + AIR_LAND_WEIGHT * sup_a) * _morale(sim, A) + eff_a * 0.5
	var total_d: float = land_d * (AIR_LAND_BASE + AIR_LAND_WEIGHT * sup_d) * _morale(sim, D) * DEFENDER_BONUS + eff_d * 0.5
	total_a *= 1.0 + (naval_a - 0.5) * 0.2
	total_d *= 1.0 + (0.5 - naval_a) * 0.2
	total_a *= rng.range_f(0.85, 1.15)
	total_d *= rng.range_f(0.85, 1.15)
	var ratio: float = total_a / (total_a + total_d + 0.001)
	_apply_losses(sim, A, PHASE_UNITS["land"], 0.03 * (1.0 - ratio) + 0.005, loss_a)
	_apply_losses(sim, D, PHASE_UNITS["land"], 0.03 * ratio + 0.005, loss_d)
	_apply_losses(sim, D, ["artillery"], 0.02 * ratio, loss_d)
	_apply_losses(sim, A, ["artillery"], 0.02 * (1.0 - ratio), loss_a)
	phases.append({"id": "land", "name_ar": "المعركة البرية", "a": total_a, "d": total_d, "result": ratio * 2.0 - 1.0})

	# التقدم على الجبهة: منطقة أو أكثر حسب تفوق الرابح
	var old_score := float(w["score"])
	var a_wins := ratio >= 0.5
	# التقدم يتراكم أسبوعاً بعد أسبوع، والمناطق الكبرى تحتاج تقدماً أكبر
	var push: float = absf(ratio - 0.5) * GAIN_RATE * rng.range_f(0.8, 1.2)
	var pkey := "progress_a" if a_wins else "progress_d"
	w[pkey] = float(w.get(pkey, 0.0)) + push
	var winners: Array = A if a_wins else D
	var losers: Array = D if a_wins else A
	var naval_w := naval_a if a_wins else 1.0 - naval_a
	var dominance := absf(ratio - 0.5) * 2.0
	var taken: Array = Territory.advance(sim, w, winners, losers, MAX_GAINS, naval_w, dominance, pkey)
	w["score"] = Territory.war_score(sim, w)
	var delta: float = float(w["score"]) - old_score
	w["battles"] = int(w["battles"]) + 1
	Divisions.after_battle(sim, A, D)
	Divisions.after_battle(sim, D, A)

	# إرهاق الحرب
	for id in A + D:
		var c: Dictionary = sim.country(id)
		c["stability"] = maxf(0.0, float(c["stability"]) - 0.3)

	var report := {
		"war_id": w["id"], "date": sim.date_text(), "attackers": A, "defenders": D,
		"phases": phases, "ratio": ratio, "delta": delta, "score": w["score"],
		"losses_a": loss_a, "losses_d": loss_d,
		"taken": taken, "taken_by_attacker": a_wins,
		"hits_a": hits_a, "hits_d": hits_d,
		"front_a": _count_front(th, A), "front_d": _count_front(th, D),
	}
	var pid: String = sim.state["player"]
	if pid in A or pid in D:
		sim.state["last_battle"] = report

	_check_outcome(sim, w, A, D)
	return report


## الاستسلام عند انهيار الدولة: سقوط العاصمة مع خسارة أرض كبيرة، أو خسارة معظم الأرض
static func _check_outcome(sim, w: Dictionary, A: Array, D: Array) -> void:
	if not w.get("active", true):
		return
	var pid: String = sim.state["player"]
	if Territory.collapsed(sim, D[0], A):
		sim.capitulate(w, D[0], A[0])
	elif Territory.collapsed(sim, A[0], D):
		sim.capitulate(w, A[0], D[0])
	elif float(w["score"]) <= 0.0 and int(w["battles"]) >= 26 and not Territory.has_land_front(sim, A, D):
		# مهاجم بعيد بلا جبهة برية لم يحقق شيئاً خلال نصف سنة: ينسحب
		var a_lead: Dictionary = sim.country(A[0])
		a_lead["stability"] = maxf(0.0, float(a_lead["stability"]) - 10.0)
		sim.make_peace(w, "%s تنسحب مهزومة من الحرب على %s." % [a_lead["name_ar"], sim.country(D[0])["name_ar"]])
		if pid == A[0]:
			sim.push_event("defeat", "هزيمة", "قواتك هُزمت واضطرت للانسحاب.", true)


## توقع قبل الهجوم: نسب القوة في كل مرحلة بلا عشوائية وبلا تعديل على الحالة
static func forecast(sim, attacker: String, defender: String) -> Dictionary:
	var A: Array = [attacker] + sim.vassals(attacker)
	var D: Array = [defender]
	for al in sim.allies(defender):
		if al != attacker and not (al in sim.allies(attacker)) and sim.relation(al, attacker) < 50.0:
			D.append(al)
	D += sim.vassals(defender)
	var share := FRONT_SHARE
	var th := _theaters(sim, A, D)
	var p := func(side: Array, utypes: Array) -> float:
		var t := 0.0
		for id in side:
			for u in utypes:
				t += sim.unit_power(sim.country(id), u) * _factor(id, u, th, share)
		return t
	var air_a: float = p.call(A, ["fighters"])
	var air_d: float = p.call(D, ["fighters"])
	var ad_a: float = p.call(A, ["air_defense"])
	var ad_d: float = p.call(D, ["air_defense"])
	var sup_a := air_a / (air_a + air_d + 0.5 * ad_d + 0.001)
	var sup_d := air_d / (air_d + air_a + 0.5 * ad_a + 0.001)
	var strike_a: float = p.call(A, ["missiles", "drones", "artillery"])
	var strike_d: float = p.call(D, ["missiles", "drones", "artillery"])
	var eff_a: float = strike_a * (1.0 - clampf(ad_d / (ad_d + strike_a + 0.001), 0.05, 0.85))
	var eff_d: float = strike_d * (1.0 - clampf(ad_a / (ad_a + strike_d + 0.001), 0.05, 0.85))
	var sea_a: float = p.call(A, ["ships", "submarines"])
	var sea_d: float = p.call(D, ["ships", "submarines"])
	var land_a := 0.0
	for id in A:
		land_a += float(p.call([id], PHASE_UNITS["land"])) * _supply(sim, id, D)
	var land_d: float = p.call(D, PHASE_UNITS["land"])
	var total_a: float = land_a * (AIR_LAND_BASE + AIR_LAND_WEIGHT * sup_a) * _morale(sim, A) + eff_a * 0.5
	var total_d: float = land_d * (AIR_LAND_BASE + AIR_LAND_WEIGHT * sup_d) * _morale(sim, D) * DEFENDER_BONUS + eff_d * 0.5
	var ratio: float = total_a / (total_a + total_d + 0.001)
	return {
		"defenders": D,
		"air": sup_a / maxf(0.001, sup_a + sup_d),
		"strike": eff_a / maxf(0.001, eff_a + eff_d),
		"sea": sea_a / maxf(0.001, sea_a + sea_d) if sea_a + sea_d > 0.001 else -1.0,
		"land": ratio,
		"weeks_to_win": _weeks_to_win(sim, defender, ratio),
		"theater": th,
		"land_front": Territory.has_land_front(sim, A, D),
	}


## تقدير زمن النصر: نحتاج احتلال نحو نصف أرض العدو مع عاصمته
static func _weeks_to_win(sim, defender: String, ratio: float) -> int:
	if ratio <= 0.55:
		return -1
	var regions: int = Territory.core_regions(defender, sim.db).size()
	var per_week := (ratio - 0.5) * GAIN_RATE
	# نحتاج نحو نصف أرض العدو: كلفة كل منطقة 0.7 + 3 × حصتها من الاقتصاد
	var cost := regions * 0.5 * 0.7 + 0.5 * 3.0 * 1.0
	return ceili(cost / maxf(0.05, per_week))


## ضربات في العمق: عدد الأهداف حسب نسبة الضربات التي تتجاوز الدفاع الجوي
static func _strategic_strikes(sim, side: Array, enemies: Array, penetration: float) -> Array:
	var hits: Array = []
	var n := floori(clampf(penetration, 0.0, 1.0) * 1.6 + sim.rng.next_float() * 0.6)
	var my_cap := Territory.capital_region(sim, side[0])
	for i in n:
		for ftype in STRIKE_PRIORITY:
			var targets: Array = Territory.working_facilities(sim, enemies, ftype, my_cap)
			if not targets.is_empty():
				var rid: String = targets[0]
				Territory.damage_facility(sim, rid, ftype, STRIKE_MONTHS)
				hits.append({"region": rid, "type": ftype})
				break
	return hits


static func _count_front(th: Dictionary, side: Array) -> int:
	var n := 0
	for id in side:
		n += int(th.get(id, {}).get("front_divisions", 0))
	return n
