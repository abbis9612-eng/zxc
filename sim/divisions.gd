## الفرق العسكرية: القوات البرية مقسمة إلى فرق متمركزة في مناطق حقيقية تتحرك بينها.
## الفرق على الجبهة تقاتل بكامل قوتها والاحتياط بجزء صغير. الطيران يعمل ضمن مدى قواعده،
## والصواريخ ضمن مداها من أرض الدولة.
extends RefCounted

const Territory := preload("res://sim/territory.gd")

const LAND := ["infantry", "armor", "helicopters"]
const KM_PER_DEG := 111.0


static func cfg(sim) -> Dictionary:
	return sim.db.military["divisions"]


# ------------------------------------------------------------------ الإعداد

static func init_state(sim) -> void:
	sim.state["divisions"] = []
	sim.state["next_division_id"] = 1
	for id in sim.state["order"]:
		var c: Dictionary = sim.country(id)
		c["auto_deploy"] = true
		var n := clampi(int(roundf(float(c["military"]["infantry"]) / float(cfg(sim)["infantry_per_division"]))), int(cfg(sim)["min"]), int(cfg(sim)["max"]))
		var spots := _default_spots(sim, id, n)
		for i in n:
			_create(sim, id, spots[i % spots.size()])


static func _create(sim, owner: String, rid: String) -> Dictionary:
	var d := {"id": int(sim.state["next_division_id"]), "owner": owner, "region": rid, "strength": 1.0, "exp": 0.0, "target": "", "eta": -1, "depart": -1}
	sim.state["next_division_id"] = int(sim.state["next_division_id"]) + 1
	sim.state["divisions"].append(d)
	return d


## مواقع البداية: العاصمة، ثم المناطق الحدودية مع الجيران المعادين، ثم الأكبر سكاناً
static func _default_spots(sim, id: String, n: int) -> Array:
	var cap: String = Territory.capital_region(sim, id)
	var spots: Array = [cap]
	var hostile: Array = []
	for nb in sim.country(id)["neighbors"]:
		if not sim.country(nb).is_empty() and sim.relation(id, nb) < -30.0:
			hostile.append(nb)
	for rid in front_regions(sim, [id], hostile):
		if not (rid in spots):
			spots.append(rid)
	var core: Array = Territory.core_regions(id, sim.db).duplicate()
	core.sort_custom(func(a, b): return float(sim.db.regions[a]["pop_share"]) > float(sim.db.regions[b]["pop_share"]))
	for rid in core:
		if spots.size() >= n:
			break
		if not (rid in spots):
			spots.append(rid)
	return spots


# ------------------------------------------------------------------ أدوات

static func of(sim, id: String) -> Array:
	return sim.state.get("divisions", []).filter(func(d): return d["owner"] == id)


static func find(sim, div_id: int) -> Dictionary:
	for d in sim.state.get("divisions", []):
		if int(d["id"]) == div_id:
			return d
	return {}


static func dist_km(sim, a: String, b: String) -> float:
	var ra: Dictionary = sim.db.regions[a]
	var rb: Dictionary = sim.db.regions[b]
	var lat := deg_to_rad((float(ra["lat"]) + float(rb["lat"])) * 0.5)
	var dx := (float(ra["lon"]) - float(rb["lon"])) * cos(lat) * KM_PER_DEG
	var dy := (float(ra["lat"]) - float(rb["lat"])) * KM_PER_DEG
	return sqrt(dx * dx + dy * dy)


static func range_km(sim, utype: String, gen: int) -> float:
	var arr: Array = sim.db.military["range_km"].get(utype, [])
	if arr.is_empty():
		return 0.0
	return float(arr[clampi(gen, 1, arr.size() - 1)])


## مناطق الطرف side الملاصقة لمناطق يملكها enemies (خط الجبهة من جهة side)
static func front_regions(sim, side: Array, enemies: Array) -> Array:
	var out: Array = []
	if enemies.is_empty():
		return out
	var info: Array = sim.border_info()
	var owned: Dictionary = info[0]
	var borders: Dictionary = info[1]
	for id in side:
		for rid in owned.get(id, []):
			for o in borders[rid]:
				if o in enemies:
					out.append(rid)
					break
	return out


## المناطق المتنازع عليها: مناطق العدو على الجبهة (أهداف الطيران والصواريخ)
static func contested(sim, side: Array, enemies: Array) -> Array:
	var out: Array = front_regions(sim, enemies, side)
	if out.is_empty():
		# بلا جبهة برية: أقرب مناطق العدو الساحلية هي ساحة المعركة
		var owned: Dictionary = sim.border_info()[0]
		for e in enemies:
			for rid in owned.get(e, []):
				if sim.db.regions[rid].get("coastal", false):
					out.append(rid)
	return out


static func _min_dist(sim, from: Array, to: Array) -> float:
	var best := INF
	for a in from:
		for b in to:
			best = minf(best, dist_km(sim, a, b))
	return best


# ------------------------------------------------------------------ عوامل المسرح للقتال

## لكل دولة في حرب: كم من قواتها يصل فعلاً إلى هذه الجبهة
static func theater(sim, id: String, allies_side: Array, enemies: Array) -> Dictionary:
	var c: Dictionary = sim.country(id)
	var conf := cfg(sim)
	var front: Array = front_regions(sim, allies_side, enemies)
	var targets: Array = contested(sim, allies_side, enemies)
	# البر: الفرق على الجبهة بكامل قوتها، والبقية احتياط
	var divs := of(sim, id)
	var land := 0.0
	var front_n := 0
	for d in divs:
		var f := float(conf["reserve_factor"])
		if d["region"] in front and int(d["eta"]) < 0:
			f = 1.0
			front_n += 1
		land += f * float(d["strength"]) * (1.0 + float(conf["exp_bonus"]) * float(d["exp"]))
	land = land / maxf(1.0, float(divs.size())) * float(conf["deploy_scale"])
	var oor := float(sim.db.military["out_of_range_factor"])
	# الجو: نسبة القواعد العاملة التي تصل الجبهة بمدى المقاتلات
	var fgen := int(c["tech"]["air"])
	var bases: Array = Territory.working_facilities(sim, [id], "airbase")
	var air := oor
	var bomb := oor
	if not targets.is_empty() and not bases.is_empty():
		var in_r := 0
		var in_b := 0
		for rid in bases:
			var dd := _min_dist(sim, [rid], targets)
			if dd <= range_km(sim, "fighters", fgen):
				in_r += 1
			if dd <= range_km(sim, "bombers", fgen):
				in_b += 1
		air = maxf(oor, float(in_r) / float(bases.size()))
		bomb = maxf(oor, float(in_b) / float(bases.size()))
	# الصواريخ والمسيّرات: من أقرب منطقة تملكها الدولة
	var mine: Array = front if not front.is_empty() else Territory.owned(sim, id)
	var dist := _min_dist(sim, mine, targets) if not targets.is_empty() else INF
	var mgen := int(c["tech"]["missile"])
	return {
		"land": land,
		"front_divisions": front_n,
		"divisions": divs.size(),
		"air": air,
		"bombers": bomb,
		"missiles": 1.0 if dist <= range_km(sim, "missiles", mgen) else oor,
		"drones": 1.0 if dist <= range_km(sim, "drones", mgen) else oor,
	}


# ------------------------------------------------------------------ الحركة

## المسار عبر مناطق تملكها الدولة أو حلفاؤها أو تابعوها (بحث بالعرض)
static func path(sim, owner: String, from: String, to: String) -> Array:
	if from == to:
		return [from]
	var ok_owners: Array = [owner] + sim.allies(owner) + sim.vassals(owner)
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n in sim.db.regions[cur]["neighbors"]:
			if prev.has(n) or not (sim.state["regions"][n]["owner"] in ok_owners):
				continue
			prev[n] = cur
			if n == to:
				var out: Array = [to]
				var p: String = cur
				while p != "":
					out.push_front(p)
					p = prev[p]
				return out
			queue.append(n)
	return []


## كل المناطق التي تصلها الفرقة براً وعدد القفزات إليها (للعرض: تظليل الوجهات الممكنة)
static func reachable(sim, owner: String, from: String) -> Dictionary:
	var ok_owners: Array = [owner] + sim.allies(owner) + sim.vassals(owner)
	var hops := {from: 0}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n in sim.db.regions[cur]["neighbors"]:
			if hops.has(n) or not (sim.state["regions"][n]["owner"] in ok_owners):
				continue
			hops[n] = int(hops[cur]) + 1
			queue.append(n)
	return hops


static func can_move(sim, d: Dictionary, to: String) -> String:
	if not sim.state["regions"].has(to):
		return "منطقة غير معروفة."
	var owner: String = d["owner"]
	var ok_owners: Array = [owner] + sim.allies(owner) + sim.vassals(owner)
	if not (sim.state["regions"][to]["owner"] in ok_owners):
		return "لا يمكن التحرك إلى منطقة لا تسيطر عليها أنت أو حلفاؤك. الهجوم يتم بالمعارك."
	if d["region"] == to:
		return "الفرقة هناك بالفعل."
	if path(sim, owner, d["region"], to).is_empty() and not _sea_ok(sim, d, to):
		return "لا طريق بري، والنقل البحري يحتاج منطقتين ساحليتين وميناء عاملاً."
	return ""


static func _sea_ok(sim, d: Dictionary, to: String) -> bool:
	return sim.db.regions[d["region"]].get("coastal", false) and sim.db.regions[to].get("coastal", false) \
		and not Territory.working_facilities(sim, [d["owner"]], "port").is_empty()


## مدة الحركة بالأيام
static func travel_days(sim, d: Dictionary, to: String) -> int:
	var p := path(sim, d["owner"], d["region"], to)
	if not p.is_empty():
		return maxi(1, (p.size() - 1) * int(cfg(sim)["days_per_hop"]))
	return int(cfg(sim)["sea_days_base"]) + int(dist_km(sim, d["region"], to) / float(cfg(sim)["sea_km_per_day"]))


static func move(sim, div_id: int, to: String) -> String:
	var d := find(sim, div_id)
	if d.is_empty():
		return "فرقة غير موجودة."
	var why := can_move(sim, d, to)
	if why != "":
		return why
	d["target"] = to
	d["depart"] = int(sim.state["day"])
	d["eta"] = int(sim.state["day"]) + travel_days(sim, d, to)
	return ""


static func daily(sim) -> void:
	var day := int(sim.state["day"])
	var rec := float(cfg(sim)["recovery_per_day"])
	for d in sim.state["divisions"]:
		if int(d["eta"]) >= 0 and day >= int(d["eta"]):
			# إن سقطت الوجهة أثناء الحركة تعود الفرقة لمكانها
			var to: String = d["target"]
			var owner: String = d["owner"]
			if sim.state["regions"][to]["owner"] in [owner] + sim.allies(owner) + sim.vassals(owner):
				d["region"] = to
			d["target"] = ""
			d["eta"] = -1
		d["strength"] = minf(1.0, float(d["strength"]) + rec)


## بعد معركة: إرهاق للمشاركين وخبرة
static func after_battle(sim, side: Array, enemies: Array) -> void:
	var front := front_regions(sim, side, enemies)
	var conf := cfg(sim)
	for d in sim.state["divisions"]:
		if d["owner"] in side and d["region"] in front:
			d["strength"] = maxf(0.3, float(d["strength"]) - float(conf["fatigue_per_battle"]))
			d["exp"] = minf(1.0, float(d["exp"]) + float(conf["exp_per_battle"]))


## عند سقوط منطقة: فرق الخاسر تنسحب لأقرب منطقة لها، وفرقة من الرابح تتقدم إليها
static func on_capture(sim, rid: String, new_owner: String) -> void:
	var ok_new: Array = [new_owner] + sim.allies(new_owner) + sim.vassals(new_owner)
	var advanced := false
	for d in sim.state.get("divisions", []):
		var owner: String = d["owner"]
		if d["region"] == rid and not (owner in ok_new):
			var dest := _retreat_spot(sim, d)
			if dest == "":
				d["strength"] = 0.3
				var cap: String = Territory.capital_region(sim, owner)
				dest = cap if sim.state["regions"].has(cap) and sim.state["regions"][cap]["owner"] == owner else ""
			if dest != "":
				d["region"] = dest
			d["strength"] = maxf(0.3, float(d["strength"]) - float(cfg(sim)["retreat_loss"]))
			d["target"] = ""
			d["eta"] = -1
		elif not advanced and owner == new_owner and int(d["eta"]) < 0 and rid in sim.db.regions[d["region"]]["neighbors"]:
			d["region"] = rid
			advanced = true


static func _retreat_spot(sim, d: Dictionary) -> String:
	var owner: String = d["owner"]
	var ok: Array = [owner] + sim.allies(owner) + sim.vassals(owner)
	for n in sim.db.regions[d["region"]]["neighbors"]:
		if sim.state["regions"][n]["owner"] in ok:
			return n
	return ""


## الدول المضمومة تفقد فرقها، والفرق في مناطق لم تعد لها أو لحلفائها تُعاد للعاصمة
static func cleanup(sim) -> void:
	sim.state["divisions"] = sim.state["divisions"].filter(func(d): return not sim.country(d["owner"]).get("annexed", false))


# ------------------------------------------------------------------ التوزيع التلقائي (الذكاء الاصطناعي واللاعب إن اختار)

static func auto_deploy(sim, id: String) -> void:
	var divs := of(sim, id)
	if divs.is_empty():
		return
	var enemies: Array = sim.enemies_of(id)
	var targets: Array = []
	if not enemies.is_empty():
		# الحرب: كل الجبهات، والأكثر أهمية أولاً (الأقرب للعاصمة)
		var side: Array = [id] + sim.allies(id) + sim.vassals(id)
		targets = front_regions(sim, [id], enemies)
		if targets.is_empty():
			targets = front_regions(sim, side, enemies)
	else:
		var hostile: Array = []
		for oid in sim.alive_ids():
			if oid != id and sim.relation(id, oid) < -30.0:
				hostile.append(oid)
		targets = front_regions(sim, [id], hostile)
	var cap: String = Territory.capital_region(sim, id)
	if sim.state["regions"].has(cap) and sim.state["regions"][cap]["owner"] == id and not (cap in targets):
		targets.push_front(cap)   # فرقة واحدة على الأقل تحمي العاصمة
	if targets.is_empty():
		return
	# فرقة لكل هدف بالدور، ولا نحرك فرقة في هدف أو في طريقها
	var per := ceili(float(divs.size()) / float(targets.size()))
	var covered := {}
	var idle: Array = []
	for d in divs:
		var at: String = d["target"] if int(d["eta"]) >= 0 else d["region"]
		# الفرقة الزائدة عن حصة موقعها تصبح متاحة للتحريك (مثل تكدس الفرق في العاصمة)
		if at in targets and int(covered.get(at, 0)) < per:
			covered[at] = int(covered.get(at, 0)) + 1
		elif int(d["eta"]) < 0:
			idle.append(d)
	for t in targets:
		while int(covered.get(t, 0)) < per and not idle.is_empty():
			var d: Dictionary = idle.pop_front()
			if move(sim, int(d["id"]), t) == "":
				covered[t] = int(covered.get(t, 0)) + 1
		if idle.is_empty():
			break
