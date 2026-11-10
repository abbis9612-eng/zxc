## حساب المعارك على مراحل: الجو، ثم الضربات، ثم البحر، ثم البر.
## النتيجة تُحسب هنا أولاً، ومشهد المعركة ثلاثي الأبعاد (لاحقاً) يعرض هذا التقرير بأمانة.
extends RefCounted

const FRONT_SHARE := 0.35      # نسبة الجيش المشاركة في جبهة واحدة
const DEFENDER_BONUS := 1.25
const FAR_SUPPLY := 0.6        # قوات بلا جبهة برية مع العدو تضعف بالإمداد
const MAX_GAINS := 2           # أقصى عدد مناطق تسقط في معركة أسبوعية
const GAIN_RATE := 3.0         # مناطق إضافية لكل وحدة تفوق

const Territory := preload("res://sim/territory.gd")

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


static func _side_power(sim, side: Array, utypes: Array) -> float:
	var total := 0.0
	for id in side:
		var c: Dictionary = sim.country(id)
		var f := _share(sim, id)
		for u in utypes:
			total += sim.unit_power(c, u) * f
	return total


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
	var loss_a := {}
	var loss_d := {}
	var phases: Array = []

	# 1) الجو
	var air_a := _side_power(sim, A, PHASE_UNITS["air"])
	var air_d := _side_power(sim, D, PHASE_UNITS["air"])
	var ad_a := _side_power(sim, A, ["air_defense"])
	var ad_d := _side_power(sim, D, ["air_defense"])
	var sup_a := air_a / (air_a + air_d + 0.5 * ad_d + 0.001)
	var sup_d := air_d / (air_d + air_a + 0.5 * ad_a + 0.001)
	_apply_losses(sim, A, ["fighters"], 0.04 * (1.0 - sup_a) * rng.range_f(0.7, 1.3), loss_a)
	_apply_losses(sim, D, ["fighters"], 0.04 * (1.0 - sup_d) * rng.range_f(0.7, 1.3), loss_d)
	phases.append({"id": "air", "name_ar": "المعركة الجوية", "a": air_a, "d": air_d + 0.5 * ad_d, "result": sup_a - sup_d})

	# 2) الضربات: صواريخ ومسيّرات ومدفعية وقاذفات، ضد الدفاع الجوي
	var strike_a := _side_power(sim, A, ["missiles", "drones", "artillery"]) + _side_power(sim, A, ["bombers"]) * sup_a
	var strike_d := _side_power(sim, D, ["missiles", "drones", "artillery"]) + _side_power(sim, D, ["bombers"]) * sup_d
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
	phases.append({"id": "strike", "name_ar": "الضربات الصاروخية والمسيّرات والمدفعية", "a": eff_a, "d": eff_d, "result": (eff_a - eff_d) / (eff_a + eff_d + 0.001), "intercept_a": intercept_a, "intercept_d": intercept_d})

	# 3) البحر
	var sea_a := _side_power(sim, A, PHASE_UNITS["sea"])
	var sea_d := _side_power(sim, D, PHASE_UNITS["sea"])
	var naval_a := 0.5
	if sea_a + sea_d > 0.001:
		naval_a = sea_a / (sea_a + sea_d) * rng.range_f(0.9, 1.1)
		naval_a = clampf(naval_a, 0.0, 1.0)
		_apply_losses(sim, A, PHASE_UNITS["sea"], 0.03 * (1.0 - naval_a), loss_a)
		_apply_losses(sim, D, PHASE_UNITS["sea"], 0.03 * naval_a, loss_d)
		phases.append({"id": "sea", "name_ar": "المعركة البحرية", "a": sea_a, "d": sea_d, "result": naval_a * 2.0 - 1.0})

	# 4) البر
	var land_a := 0.0
	for id in A:
		land_a += _side_power(sim, [id], PHASE_UNITS["land"]) * _supply(sim, id, D)
	var land_d := _side_power(sim, D, PHASE_UNITS["land"])
	var total_a: float = land_a * (0.7 + 0.6 * sup_a) * _morale(sim, A) + eff_a * 0.5
	var total_d: float = land_d * (0.7 + 0.6 * sup_d) * _morale(sim, D) * DEFENDER_BONUS + eff_d * 0.5
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
	var gains := mini(MAX_GAINS, floori(absf(ratio - 0.5) * GAIN_RATE + rng.next_float()))
	var winners: Array = A if a_wins else D
	var losers: Array = D if a_wins else A
	var naval_w := naval_a if a_wins else 1.0 - naval_a
	var dominance := absf(ratio - 0.5) * 2.0
	var taken: Array = Territory.advance(sim, w, winners, losers, gains, naval_w, dominance)
	w["score"] = Territory.war_score(sim, w)
	var delta: float = float(w["score"]) - old_score
	w["battles"] = int(w["battles"]) + 1

	# إرهاق الحرب
	for id in A + D:
		var c: Dictionary = sim.country(id)
		c["stability"] = maxf(0.0, float(c["stability"]) - 0.3)

	var report := {
		"war_id": w["id"], "date": sim.date_text(), "attackers": A, "defenders": D,
		"phases": phases, "ratio": ratio, "delta": delta, "score": w["score"],
		"losses_a": loss_a, "losses_d": loss_d,
		"taken": taken, "taken_by_attacker": a_wins,
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
	var p := func(side: Array, utypes: Array) -> float:
		var t := 0.0
		for id in side:
			for u in utypes:
				t += sim.unit_power(sim.country(id), u) * share
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
	var total_a: float = land_a * (0.7 + 0.6 * sup_a) * _morale(sim, A) + eff_a * 0.5
	var total_d: float = land_d * (0.7 + 0.6 * sup_d) * _morale(sim, D) * DEFENDER_BONUS + eff_d * 0.5
	var ratio: float = total_a / (total_a + total_d + 0.001)
	return {
		"defenders": D,
		"air": sup_a / maxf(0.001, sup_a + sup_d),
		"strike": eff_a / maxf(0.001, eff_a + eff_d),
		"sea": sea_a / maxf(0.001, sea_a + sea_d) if sea_a + sea_d > 0.001 else -1.0,
		"land": ratio,
		"weeks_to_win": _weeks_to_win(sim, defender, ratio),
		"land_front": Territory.has_land_front(sim, A, D),
	}


## تقدير زمن النصر: نحتاج احتلال نحو نصف أرض العدو مع عاصمته
static func _weeks_to_win(sim, defender: String, ratio: float) -> int:
	if ratio <= 0.55:
		return -1
	var regions: int = Territory.core_regions(defender, sim.db).size()
	var per_week := minf(float(MAX_GAINS), (ratio - 0.5) * GAIN_RATE + 0.5)
	return ceili(maxf(1.0, regions * 0.45) / maxf(0.2, per_week))
