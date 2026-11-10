## القتال اليومي على الجبهة: كل منطقة على خط التماس لها «سيطرة» من 100.
## فرق كل طرف تضغط على مناطق العدو المجاورة لها، والمدافع يصمد بحامية المنطقة وفرقه فيها ودعم جواره.
## السيطرة تنزل يوماً بعد يوم بفرق القوة حتى تسقط المنطقة، وتعود إن رجح المدافع (هجوم مضاد).
## الطلعات الجوية تقلع من قواعد حقيقية في المدى، ورشقات الصواريخ يُعترض بعضها، والخسائر تقع على فرق بعينها.
extends RefCounted

const Territory := preload("res://sim/territory.gd")
const Divisions := preload("res://sim/divisions.gd")
const Arsenal := preload("res://sim/arsenal.gd")
const Combat := preload("res://sim/combat.gd")
const Development := preload("res://sim/development.gd")

const LAND_UNITS := ["infantry", "armor", "helicopters"]


static func cfg(sim) -> Dictionary:
	return sim.db.military["front"]


static func control(sim, rid: String) -> float:
	return float(sim.state["regions"][rid].get("control", 100.0))


static func daily(sim) -> void:
	for w in sim.state["wars"].duplicate():
		if w.get("active", true):
			_war_day(sim, w)


static func sides(sim, w: Dictionary) -> Array:
	var A: Array = w["attackers"].filter(func(x): return sim.country(x).get("overlord", "") == "" or sim.country(x)["overlord"] in w["attackers"])
	var D: Array = w["defenders"].filter(func(x): return sim.country(x).get("overlord", "") == "" or sim.country(x)["overlord"] in w["defenders"])
	return [A, D]


## قوة فرقة واحدة كاملة لكل دولة اليوم، مع التفوق الجوي والمعنويات والتكتيك
static func _div_power(sim, w: Dictionary, id: String, in_a: bool, n_divs: int) -> float:
	var c: Dictionary = sim.country(id)
	var conf := cfg(sim)
	var p := 0.0
	for u in LAND_UNITS:
		p += sim.unit_power(c, u)
	p += sim.unit_power(c, "artillery") * float(conf["artillery_weight"])
	p /= maxf(1.0, float(n_divs))
	var sup := float(w.get("sup_a" if in_a else "sup_d", 0.5))
	var lead: String = w["attackers"][0] if in_a else w["defenders"][0]
	var tac := str(w.get("tactics", {}).get(lead, "balanced"))
	return p * (Combat.AIR_LAND_BASE + Combat.AIR_LAND_WEIGHT * sup) * Combat._morale(sim, [id]) * Combat._tac(sim, tac, "land")


static func _war_day(sim, w: Dictionary) -> void:
	var sd := sides(sim, w)
	var A: Array = sd[0]
	var D: Array = sd[1]
	if A.is_empty() or D.is_empty():
		return
	if not w.has("sup_a"):
		Combat.store_components(sim, w, A, D)
	var conf := cfg(sim)
	var regs: Dictionary = sim.state["regions"]
	var side_of := {}
	for id in A:
		side_of[id] = 0
	for id in D:
		side_of[id] = 1
	# قوة الفرقة لكل دولة
	var divs_by: Dictionary = {}
	for d in sim.state["divisions"]:
		if side_of.has(d["owner"]):
			if not divs_by.has(d["owner"]):
				divs_by[d["owner"]] = 0
			divs_by[d["owner"]] = int(divs_by[d["owner"]]) + 1
	var dpow := {}
	for id in A + D:
		dpow[id] = _div_power(sim, w, id, side_of[id] == 0, int(divs_by.get(id, 1)))
	var exp_b := float(sim.db.military["divisions"]["exp_bonus"])
	var atk_b := float(sim.db.military["divisions"].get("attack_bonus", 0.0))
	# العمليات النشطة: الهدف يأخذ دعمها (جو أو صواريخ) فيزيد ضغط فرق طرفها عليه
	var ops := _active_ops(sim, w)
	var op_bonus := {}    # "طرف|هدف" -> مضاعف الضغط
	for op in ops:
		var sup: Dictionary = sim.db.military["operations"]["supports"].get(String(op["support"]), {})
		if side_of.has(op["side"]):
			op_bonus["%d|%s" % [int(side_of[op["side"]]), op["target"]]] = float(sup.get("pressure", 1.0))

	# الضغط على كل منطقة معادية، والمدافعون داخل كل منطقة
	var pressure := {}       # منطقة -> مجموع الضغط
	var press_by := {}       # منطقة -> {دولة: ضغط}
	var attackers := {}      # منطقة -> [[فرقة، حصة]]
	var defenders := {}      # منطقة -> [فرق]
	var held := {}           # منطقة -> قوة الفرق فيها
	var front_order: Array = []
	for d in sim.state["divisions"]:
		var owner: String = d["owner"]
		if not side_of.has(owner) or int(d["eta"]) >= 0:
			continue
		var rid: String = d["region"]
		var eff: float = float(dpow[owner]) * float(d["strength"]) * (1.0 + exp_b * float(d["exp"]))
		if not defenders.has(rid):
			defenders[rid] = []
		defenders[rid].append(d)
		held[rid] = float(held.get(rid, 0.0)) + eff
		var my_side: int = side_of[owner]
		var targets: Array = []
		for n in sim.db.regions[rid]["neighbors"]:
			var o: String = regs[n]["owner"]
			if side_of.has(o) and int(side_of[o]) != my_side:
				targets.append(n)
		if targets.is_empty():
			continue
		var shares := _allocate(sim, d, targets, A if my_side == 1 else D)
		for i in targets.size():
			var t: String = targets[i]
			var sh: float = shares[i]
			if sh <= 0.0:
				continue
			var p: float = eff * sh * ((1.0 + atk_b) if d.get("attack", "") == t else 1.0)
			p *= float(op_bonus.get("%d|%s" % [my_side, t], 1.0))
			if not pressure.has(t):
				pressure[t] = 0.0
				press_by[t] = {}
				attackers[t] = []
				front_order.append(t)
			pressure[t] = float(pressure[t]) + p
			press_by[t][owner] = float(press_by[t].get(owner, 0.0)) + p
			attackers[t].append([d, sh])

	var taken_a: Array = []
	var taken_d: Array = []
	var hot := ""
	var hot_p := 0.0
	for rid in front_order:
		var owner: String = regs[rid]["owner"]
		var my_side: int = side_of[owner]
		# الدفاع: حامية المنطقة + الفرق فيها + دعم الفرق في المناطق الصديقة المجاورة
		var defense: float = float(dpow[owner]) * float(conf["garrison"]) + float(held.get(rid, 0.0))
		for n in sim.db.regions[rid]["neighbors"]:
			var o: String = regs[n]["owner"]
			if side_of.has(o) and int(side_of[o]) == my_side:
				defense += float(held.get(n, 0.0)) * float(conf["neighbor_support"])
		defense *= float(conf["defender_bonus"])
		var info: Dictionary = sim.db.regions[rid]
		if info["capital"]:
			defense *= float(conf["capital_bonus"])
		var p: float = float(pressure[rid]) * sim.rng.range_f(1.0 - float(conf["noise"]), 1.0 + float(conf["noise"]))
		if p > hot_p:
			hot_p = p
			hot = rid
		var ratio: float = p / (p + defense + 0.001)
		var r: Dictionary = regs[rid]
		var ctl := float(r.get("control", 100.0))
		var cost: float = Territory.capture_cost(sim, rid)
		if ratio > 0.5:
			ctl -= float(conf["rate"]) * (ratio - 0.5) * 2.0 / cost
		else:
			ctl += float(conf["recover"]) * (0.5 - ratio) * 2.0
		# العاصمة لا تسقط إلا بتفوق واضح
		if info["capital"] and ratio < float(conf["capital_min_ratio"]):
			ctl = maxf(ctl, 1.0)
		# الخسائر على فرق بعينها
		var loss := float(conf["div_loss"])
		var lose_def: float = loss * ratio * 2.0
		var lose_atk: float = loss * (1.0 - ratio) * 2.0 * float(conf["attack_loss"])
		for d in defenders.get(rid, []):
			_hurt(sim, w, d, lose_def)
		for pair in attackers[rid]:
			_hurt(sim, w, pair[0], lose_atk * float(pair[1]))
		if ctl <= 0.0:
			# تسقط المنطقة: لصاحبها الأصلي إن كان مع المنتصر، وإلا لأكثر دولة ضغطت عليها
			var winners: Array = D if my_side == 0 else A
			var new_owner: String = r["core"]
			if not (new_owner in winners):
				new_owner = _top(press_by[rid], winners)
			Territory.capture(sim, rid, new_owner)
			r["control"] = float(conf["captured_control"])
			if my_side == 1:
				taken_a.append(rid)
			else:
				taken_d.append(rid)
		else:
			r["control"] = clampf(ctl, 0.0, 100.0)
	# المناطق التي لا يضغط عليها أحد تستعيد سيطرتها
	for id in A + D:
		for rid in sim.border_info()[0].get(id, []):
			if not pressure.has(rid) and float(regs[rid].get("control", 100.0)) < 100.0:
				regs[rid]["control"] = minf(100.0, float(regs[rid]["control"]) + float(conf["recover"]))

	_air_and_missiles(sim, w, A, D, hot, ops)
	if w.has("ops"):
		w["ops"] = ops.filter(func(op): return regs[op["target"]]["owner"] in sim.enemies_of(op["side"]))
	_flush_losses(sim, w)
	if not taken_a.is_empty():
		_report(sim, w, A, D, taken_a, true)
	if not taken_d.is_empty():
		_report(sim, w, A, D, taken_d, false)


## توزيع ضغط الفرقة على مناطق العدو المجاورة: أمر الهجوم يأخذ كل القوة،
## وإلا فالهدف الأهم (تحرير الأرض ثم الأقرب لعاصمة العدو) يأخذ الحصة الأكبر
static func _allocate(sim, d: Dictionary, targets: Array, enemies: Array) -> Array:
	var shares: Array = []
	shares.resize(targets.size())
	shares.fill(0.0)
	var atk: String = d.get("attack", "")
	var i_atk := targets.find(atk)
	if i_atk >= 0:
		shares[i_atk] = 1.0
		return shares
	if targets.size() == 1:
		shares[0] = 1.0
		return shares
	var owner: String = d["owner"]
	var best := Territory._pick_target(sim, targets, [owner] + sim.allies(owner), enemies[0])
	var push := float(cfg(sim)["push_share"])
	var rest := (1.0 - push) / float(targets.size() - 1)
	for i in targets.size():
		shares[i] = push if targets[i] == best else rest
	return shares


static func _top(by: Dictionary, winners: Array) -> String:
	var best: String = winners[0]
	var bp := -1.0
	for id in winners:
		if float(by.get(id, 0.0)) > bp:
			bp = float(by.get(id, 0.0))
			best = id
	return best


## خسارة فرقة: تنقص قوتها، وتُسجل لتخصم من مخزون دولتها في نهاية اليوم
static func _hurt(sim, w: Dictionary, d: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	var floor_s := float(cfg(sim)["min_strength"])
	var before := float(d["strength"])
	d["strength"] = maxf(floor_s, before - amount)
	var lost := before - float(d["strength"])
	if lost <= 0.0:
		return
	var key := "_hurt"
	if not w.has(key):
		w[key] = {}
	w[key][d["owner"]] = float(w[key].get(d["owner"], 0.0)) + lost
	d["hurt_day"] = int(sim.state["day"])


## نقص قوة الفرق يصير خسارة حقيقية في المخزون: مشاة ودروع ومروحيات
static func _flush_losses(sim, w: Dictionary) -> void:
	var hurt: Dictionary = w.get("_hurt", {})
	if hurt.is_empty():
		return
	var conf := cfg(sim)
	for id in hurt:
		var c: Dictionary = sim.country(id)
		var n := maxf(1.0, float(Divisions.of(sim, id).size()))
		var frac: float = float(hurt[id]) / n * float(conf["stock_loss"])
		var rec_key := "day_loss_a" if id in w["attackers"] else "day_loss_d"
		if not w.has(rec_key):
			w[rec_key] = {}
		for u in LAND_UNITS:
			var lost := Arsenal.lose_fraction(c, u, frac)
			w[rec_key][u] = float(w[rec_key].get(u, 0.0)) + lost
	w["_hurt"] = {}


# ------------------------------------------------------------------ الجو والصواريخ

## طلعات جوية من أقرب قاعدة عاملة في المدى، ورشقة صواريخ على أكثر منطقة ساخنة
static func _active_ops(sim, w: Dictionary) -> Array:
	var day := int(sim.state["day"])
	return w.get("ops", []).filter(func(op): return int(op["until"]) >= day)


static func _air_and_missiles(sim, w: Dictionary, A: Array, D: Array, hot: String, ops: Array = []) -> void:
	if hot == "" and ops.is_empty():
		return
	var conf := cfg(sim)
	var day := int(sim.state["day"])
	for s in 2:
		var mine: Array = A if s == 0 else D
		var them: Array = D if s == 0 else A
		var lead: Dictionary = sim.country(mine[0])
		var sup := float(w.get("sup_a" if s == 0 else "sup_d", 0.5))
		var target := hot
		var op_sup: Dictionary = {}
		for op in ops:
			if String(op["side"]) in mine and sim.state["regions"][op["target"]]["owner"] in them:
				target = op["target"]
				op_sup = sim.db.military["operations"]["supports"].get(String(op["support"]), {})
				break
		if target == "":
			continue
		if not (sim.state["regions"][target]["owner"] in them):
			target = _their_hot(sim, target, them)
		if target == "":
			continue
		# الطلعات الجوية: من أقرب قاعدة يصلها مدى المقاتلات
		var fighters := float(lead["military"].get("fighters", 0.0))
		if fighters >= 1.0:
			var base := _nearest_base(sim, mine, target)
			if base != "":
				var n := maxi(1, int(roundf(fighters * float(conf["sortie_rate"]) * sup)))
				var shot := 0
				var ad_frac := 1.0 - sup
				for i in mini(n, 40):
					if sim.rng.chance(float(conf["sortie_loss"]) * ad_frac):
						shot += 1
				if shot > 0:
					Arsenal.remove(lead, "fighters", float(shot))
				# الدعم الجوي القريب يضرب الفرق في المنطقة
				_damage_region(sim, w, target, them, float(conf["air_cas"]) * float(op_sup.get("cas_mult", 1.0)) * sup * float(conf["hit_damage"]) * float(mini(n, 40)))
				_event(sim, {"kind": "sortie", "war_id": w["id"], "side": mine[0], "from": base, "to": target, "n": n, "lost": shot, "day": day})
		# رشقة صواريخ
		var missiles := float(lead["military"].get("missiles", 0.0))
		var salvo_mult := float(op_sup.get("salvo_mult", 0.0))
		if missiles >= 1.0 and (salvo_mult > 0.0 or sim.rng.chance(float(conf["salvo_chance"]))):
			var fired := clampi(int(roundf(missiles * float(conf["salvo_share"]) * maxf(1.0, salvo_mult))), 1, int(conf["salvo_max"]))
			var p_int := float(w.get("int_d" if s == 0 else "int_a", 0.3))
			var intercepted := 0
			for i in fired:
				if sim.rng.chance(p_int):
					intercepted += 1
			Arsenal.remove(lead, "missiles", float(fired))
			var hits := fired - intercepted
			_damage_region(sim, w, target, them, float(hits) * float(conf["hit_damage"]))
			var from := _launch_site(sim, mine, target)
			_event(sim, {"kind": "salvo", "war_id": w["id"], "side": mine[0], "from": from, "to": target, "fired": fired, "intercepted": intercepted, "day": day})


static func _their_hot(sim, near: String, them: Array) -> String:
	for n in sim.db.regions[near]["neighbors"]:
		if sim.state["regions"][n]["owner"] in them:
			return n
	return ""


static func _nearest_base(sim, side: Array, target: String) -> String:
	var lead: Dictionary = sim.country(side[0])
	var rng_km: float = Divisions.range_km(sim, "fighters", int(lead["tech"]["air"]))
	var best := ""
	var bd := INF
	for rid in Territory.working_facilities(sim, side, "airbase"):
		var dd: float = Divisions.dist_km(sim, rid, target)
		if dd <= rng_km and dd < bd:
			bd = dd
			best = rid
	return best


static func _launch_site(sim, side: Array, target: String) -> String:
	var best := ""
	var bd := INF
	for rid in sim.border_info()[0].get(side[0], []):
		var dd: float = Divisions.dist_km(sim, rid, target)
		if dd < bd:
			bd = dd
			best = rid
	return best


## الضربات تصيب الفرق داخل المنطقة المستهدفة (بالتساوي)
static func _damage_region(sim, w: Dictionary, rid: String, them: Array, total: float) -> void:
	if total <= 0.0:
		return
	var inside: Array = []
	for d in sim.state["divisions"]:
		if d["region"] == rid and d["owner"] in them and int(d["eta"]) < 0:
			inside.append(d)
	if inside.is_empty():
		var r: Dictionary = sim.state["regions"][rid]
		r["control"] = maxf(1.0, float(r.get("control", 100.0)) - total * 20.0)
		return
	for d in inside:
		_hurt(sim, w, d, total / float(inside.size()))


# ------------------------------------------------------------------ التقارير

## أحداث القتال اليومية للعرض (لا تُحفظ): طلعات ورشقات
static func _event(sim, e: Dictionary) -> void:
	sim.combat_feed.append(e)
	if sim.combat_feed.size() > sim.BATTLE_FEED_MAX:
		sim.combat_feed.pop_front()


## سقوط مناطق اليوم: تقرير بنفس شكل تقرير المعركة حتى تعرضه الخريطة فوراً
static func _report(sim, w: Dictionary, A: Array, D: Array, taken: Array, by_attacker: bool) -> void:
	var report := {
		"war_id": w["id"], "date": sim.date_text(), "attackers": A, "defenders": D,
		"phases": [], "ratio": 0.5, "delta": 0.0, "score": w["score"],
		"losses_a": {}, "losses_d": {}, "taken": taken, "taken_by_attacker": by_attacker,
		"hits_a": [], "hits_d": [], "front_a": 0, "front_d": 0, "daily": true,
	}
	w["score"] = Territory.war_score(sim, w)
	report["score"] = w["score"]
	sim.battle_feed.append(report)
	if sim.battle_feed.size() > sim.BATTLE_FEED_MAX:
		sim.battle_feed.pop_front()


## توقع بلا آثار جانبية: كم يوماً تقريباً حتى تسقط منطقة معادية بالقوات المجاورة لها الآن
static func days_to_take(sim, rid: String, side: Array) -> int:
	var regs: Dictionary = sim.state["regions"]
	var owner: String = regs[rid]["owner"]
	var w: Dictionary = sim.war_between(side[0], owner)
	if w.is_empty():
		return -1
	var in_a: bool = side[0] in w["attackers"]
	var conf := cfg(sim)
	var exp_b := float(sim.db.military["divisions"]["exp_bonus"])
	var p := 0.0
	var held := 0.0
	var their := {}
	for d in sim.state["divisions"]:
		if int(d["eta"]) >= 0:
			continue
		var o: String = d["owner"]
		if o in side and rid in sim.db.regions[d["region"]]["neighbors"]:
			p += _div_power(sim, w, o, in_a, Divisions.of(sim, o).size()) * float(d["strength"]) * (1.0 + exp_b * float(d["exp"]))
		elif o == owner and d["region"] == rid:
			held += _div_power(sim, w, o, not in_a, Divisions.of(sim, o).size()) * float(d["strength"]) * (1.0 + exp_b * float(d["exp"]))
	var defense: float = (_div_power(sim, w, owner, not in_a, Divisions.of(sim, owner).size()) * float(conf["garrison"]) + held) * float(conf["defender_bonus"])
	if sim.db.regions[rid]["capital"]:
		defense *= float(conf["capital_bonus"])
	var ratio := p / (p + defense + 0.001)
	if ratio <= 0.5:
		return -1
	var per_day: float = float(conf["rate"]) * (ratio - 0.5) * 2.0 / Territory.capture_cost(sim, rid)
	return int(ceilf(float(regs[rid].get("control", 100.0)) / per_day))
