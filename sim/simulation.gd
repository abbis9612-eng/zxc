## محرك المحاكاة: يحسب العالم كله بلا رسوميات.
## كل الحالة في القاموس state، فالحفظ والتحميل مجرد كتابته وقراءته.
## حتمي: نفس البذرة ونفس أوامر اللاعب تعطي نفس النتيجة.
extends RefCounted

const DataDB := preload("res://sim/data_db.gd")
const SimRng := preload("res://sim/rng.gd")
const Economy := preload("res://sim/economy.gd")
const Combat := preload("res://sim/combat.gd")
const AI := preload("res://sim/ai.gd")
const Territory := preload("res://sim/territory.gd")
const Logistics := preload("res://sim/logistics.gd")
const Market := preload("res://sim/market.gd")
const Factions := preload("res://sim/factions.gd")

const SAVE_VERSION := 1
const START_YEAR := 2026
const START_MONTH := 10
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const MONTH_NAMES_AR := ["كانون الثاني", "شباط", "آذار", "نيسان", "أيار", "حزيران", "تموز", "آب", "أيلول", "تشرين الأول", "تشرين الثاني", "كانون الأول"]
const NUCLEAR_WINTER_STRIKES := 12
const MAX_NEWS := 300
const STRIKE_MISSILES := 10.0
const TRUCE_DAYS := 730
const BORDER_INCIDENT_CHANCE := 0.02

var db: DataDB
var rng: SimRng
var state: Dictionary = {}
## أحداث تنتظر أن تعرضها الواجهة: {kind, title, text, pause, choices, data}
var pending: Array = []


func _init(database: DataDB = null) -> void:
	db = database
	if db == null:
		db = DataDB.new()
		db.load_all()


# ------------------------------------------------------------------ بداية اللعبة

## difficulty: 0 سهل، 1 عادي، 2 صعب
func new_game(player_id: String, seed_value: int = 12345, difficulty: int = 1) -> void:
	rng = SimRng.new(seed_value)
	pending.clear()
	state = {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"rng": rng.state,
		"day": 0,
		"date": {"y": START_YEAR, "m": START_MONTH, "d": 1},
		"player": player_id,
		"difficulty": difficulty,
		"order": [],
		"countries": {},
		"relations": {},
		"alliances": db.alliances.duplicate(true),
		"wars": [],
		"next_war_id": 1,
		"global": {"oil_price": 1.0, "growth_mod": 0.0, "stability_mod": 0.0, "mod_months": 0, "nuclear_strikes": 0},
		"news": [],
		"game_over": "",
		"victories": [],
		"last_battle": {},
	}
	for t in db.countries:
		var c: Dictionary = t.duplicate(true)
		c["gdp_start"] = c["gdp"]
		c["treasury"] = c["gdp"] * 0.05
		c["debt"] = c["gdp"] * 0.4
		c["inflation"] = 3.0
		c["research_ratio"] = 0.01
		c["research_focus"] = "land"
		c["research_progress"] = 0.0
		c["policies"] = []
		c["overlord"] = ""
		c["influence"] = {}
		c["sanctions"] = []
		c["low_stab_months"] = 0
		c["capital_fallen"] = false
		c["production"] = []
		c["last_budget"] = {}
		for k in db.units:
			c["military"][k] = float(c["military"].get(k, 0))
		state["countries"][c["id"]] = c
		state["order"].append(c["id"])
	Territory.init_state(self)
	Market.init_state(self)
	state["truces"] = {}
	for r in db.relations:
		set_relation(r[0], r[1], float(r[2]))
	for aid in state["alliances"]:
		var m: Array = state["alliances"][aid]["members"]
		for i in m.size():
			for j in range(i + 1, m.size()):
				set_relation(m[i], m[j], maxf(relation(m[i], m[j]), 60.0))
	state["relation_base"] = state["relations"].duplicate()
	for id in state["order"]:
		Economy.init_civil_spending(self, country(id))
	for id in state["order"]:
		Factions.init_country(self, country(id))
	add_news("بدأت اللعبة. أنت تقود %s." % country(player_id)["name_ar"], "info")


# ------------------------------------------------------------------ أدوات عامة

func country(id: String) -> Dictionary:
	return state["countries"].get(id, {})


func player() -> Dictionary:
	return country(state["player"])


func is_player(id: String) -> bool:
	return id == state["player"]


func alive_ids() -> Array:
	var out: Array = []
	for id in state["order"]:
		if not country(id).get("annexed", false):
			out.append(id)
	return out


static func rel_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func relation(a: String, b: String) -> float:
	if a == b:
		return 100.0
	return float(state["relations"].get(rel_key(a, b), 0.0))


func set_relation(a: String, b: String, v: float) -> void:
	if a == b:
		return
	state["relations"][rel_key(a, b)] = clampf(v, -100.0, 100.0)


func change_relation(a: String, b: String, dv: float) -> void:
	set_relation(a, b, relation(a, b) + dv)


func alliance_of(id: String) -> Array:
	var out: Array = []
	for aid in state["alliances"]:
		if id in state["alliances"][aid]["members"]:
			out.append(aid)
	return out


func allies(id: String) -> Array:
	var out: Array = []
	for aid in alliance_of(id):
		for m in state["alliances"][aid]["members"]:
			if m != id and not (m in out):
				out.append(m)
	return out


func vassals(id: String) -> Array:
	var out: Array = []
	for oid in state["order"]:
		if country(oid).get("overlord", "") == id:
			out.append(oid)
	return out


func date_text() -> String:
	var d: Dictionary = state["date"]
	return "%d %s %d" % [int(d["d"]), MONTH_NAMES_AR[int(d["m"]) - 1], int(d["y"])]


func add_news(text: String, kind: String = "info") -> void:
	var news: Array = state["news"]
	news.append({"day": state["day"], "date": date_text(), "text": text, "kind": kind})
	if news.size() > MAX_NEWS:
		news.pop_front()


func push_event(kind: String, title: String, text: String, pause: bool, choices: Array = [], data: Dictionary = {}) -> void:
	pending.append({"kind": kind, "title": title, "text": text, "pause": pause, "choices": choices, "data": data})


# ------------------------------------------------------------------ الوقت

func advance_day() -> void:
	if state["game_over"] != "":
		return
	state["day"] = int(state["day"]) + 1
	var d: Dictionary = state["date"]
	var day := int(d["d"]) + 1
	var month := int(d["m"])
	var year := int(d["y"])
	var new_month := false
	if day > days_in_month(month, year):
		day = 1
		month += 1
		new_month = true
		if month > 12:
			month = 1
			year += 1
	state["date"] = {"y": year, "m": month, "d": day}

	_daily_production()
	if int(state["day"]) % 7 == 0:
		for w in state["wars"].duplicate():
			if w.get("active", true):
				Combat.weekly_battle(self, w)
		_cleanup_wars()
	if new_month:
		_monthly()
	state["rng"] = rng.state


static func days_in_month(m: int, y: int) -> int:
	if m == 2 and ((y % 4 == 0 and y % 100 != 0) or y % 400 == 0):
		return 29
	return MONTH_DAYS[m - 1]


func _monthly() -> void:
	_global_modifiers_tick()
	# النمو أولاً لكل الدول في مرور واحد على المناطق، ثم الميزانيات
	var growths := {}
	for id in alive_ids():
		var c := country(id)
		var g := Economy.growth_rate(self, c)
		c["growth_now"] = g
		growths[id] = g
	Territory.monthly(self)          # الاندماج والإصلاح والمقاومة (بلا إعادة حساب)
	Territory.grow_all(self, growths)  # النمو ثم إعادة حساب كل الدول مرة واحدة
	Market.monthly(self)               # الأسعار ودخل التجارة قبل الميزانيات
	for id in alive_ids():
		Economy.monthly(self, country(id))
	for id in alive_ids():
		Factions.monthly(self, country(id))
	for id in alive_ids():
		if not is_player(id):
			AI.monthly(self, country(id))
	_relations_drift()
	_border_incidents()
	_random_events()
	_check_end_conditions()


func _daily_production() -> void:
	for id in state["order"]:
		var c := country(id)
		var queue: Array = c["production"]
		if queue.is_empty() or c.get("annexed", false):
			continue
		var speed := float(c.get("logistics", {}).get("production", 1.0))
		if "war_economy" in c["policies"]:
			speed *= float(db.policies["war_economy"].get("production_speed", 1.0))
		var i := queue.size() - 1
		while i >= 0:
			var o: Dictionary = queue[i]
			o["days_left"] = float(o["days_left"]) - speed
			if float(o["days_left"]) <= 0.0:
				queue.remove_at(i)
				c["military"][o["type"]] = float(c["military"][o["type"]]) + float(o["count"])
				if is_player(id):
					add_news("اكتمل تصنيع %s %s." % [fmt_num(o["count"]), db.units[o["type"]]["name_ar"]], "good")
			i -= 1


func _global_modifiers_tick() -> void:
	var g: Dictionary = state["global"]
	if int(g["mod_months"]) > 0:
		g["mod_months"] = int(g["mod_months"]) - 1
		if int(g["mod_months"]) == 0:
			g["growth_mod"] = 0.0
			g["stability_mod"] = 0.0


func _relations_drift() -> void:
	# العلاقات تعود ببطء نحو مستواها التاريخي (العداوات القديمة لا تختفي)، والحرب تبقيها منخفضة
	var base: Dictionary = state.get("relation_base", {})
	for k in state["relations"].keys():
		var v: float = state["relations"][k]
		var target: float = base.get(k, 0.0)
		state["relations"][k] = v + clampf(target - v, -0.4, 0.4)
	for w in state["wars"]:
		for a in w["attackers"]:
			for b in w["defenders"]:
				change_relation(a, b, -3.0)


## حوادث حدودية بين الجيران المتوترين ترفع احتمال الحرب
func _border_incidents() -> void:
	var ids := alive_ids()
	for i in ids.size():
		var a: String = ids[i]
		for b in country(a)["neighbors"]:
			if b <= a or country(b).is_empty() or country(b).get("annexed", false):
				continue
			if relation(a, b) < -20.0 and war_between(a, b).is_empty() and rng.chance(BORDER_INCIDENT_CHANCE):
				change_relation(a, b, -12.0)
				var text := "حادث حدودي بين %s و%s يرفع التوتر." % [country(a)["name_ar"], country(b)["name_ar"]]
				add_news(text, "war")
				if is_player(a) or is_player(b):
					push_event("incident", "حادث حدودي", text, false)


func _random_events() -> void:
	for e in db.events:
		if e.get("global", false):
			if rng.chance(float(e["chance"])):
				_apply_event(e, "")
		else:
			for id in alive_ids():
				var p := float(e["chance"])
				if e.get("min_instability", false) and float(country(id)["stability"]) > 45.0:
					continue
				if rng.chance(p):
					_apply_event(e, id)


func _apply_event(e: Dictionary, target: String) -> void:
	var g: Dictionary = state["global"]
	if target == "":
		if e.has("growth"):
			g["growth_mod"] = float(e["growth"])
			g["mod_months"] = int(e.get("months", 6))
		if e.has("stability"):
			g["stability_mod"] = float(e["stability"])
			g["mod_months"] = int(e.get("months", 6))
		if e.has("price_shock"):
			Market.apply_shock(self, e["price_shock"], int(e.get("months", 6)))
		if e.has("relations"):
			for k in state["relations"].keys():
				var v: float = state["relations"][k]
				if v < 0.0:
					state["relations"][k] = minf(0.0, v + float(e["relations"]))
		add_news("%s: %s" % [e["title_ar"], e["text_ar"]], "world")
		push_event("world", e["title_ar"], e["text_ar"], true)
	else:
		var c := country(target)
		if e.has("gdp"):
			Territory.scale_gdp(self, target, 1.0 + float(e["gdp"]))
		if e.has("stability"):
			c["stability"] = clampf(float(c["stability"]) + float(e["stability"]), 0.0, 100.0)
		if e.has("oil"):
			c["resources"]["oil"] = minf(100.0, float(c["resources"]["oil"]) + float(e["oil"]))
		add_news("%s في %s." % [e["title_ar"], c["name_ar"]], "good" if e.has("oil") else "world")
		if is_player(target):
			push_event("local", e["title_ar"], e["text_ar"], true)


# ------------------------------------------------------------------ القوة العسكرية

func unit_power(c: Dictionary, utype: String) -> float:
	var u: Dictionary = db.units[utype]
	return float(c["military"].get(utype, 0.0)) * float(u["power"]) * db.combat_multiplier(int(c["tech"][u["branch"]])) * Logistics.unit_factor(c, utype) * float(c.get("quality", 1.0))


func military_power(c: Dictionary) -> float:
	var total := 0.0
	for k in db.units:
		total += unit_power(c, k)
	return total


## قوة الدولة مع حلفائها المستعدين للدفاع عنها
func bloc_power(id: String) -> float:
	var total := military_power(country(id))
	for a in allies(id):
		total += military_power(country(a)) * 0.35
	return total


# ------------------------------------------------------------------ الحرب

func war_between(a: String, b: String) -> Dictionary:
	for w in state["wars"]:
		if (a in w["attackers"] and b in w["defenders"]) or (b in w["attackers"] and a in w["defenders"]):
			return w
	return {}


func wars_of(id: String) -> Array:
	return state["wars"].filter(func(w): return id in w["attackers"] or id in w["defenders"])


func enemies_of(id: String) -> Array:
	var out: Array = []
	for w in wars_of(id):
		var other: Array = w["defenders"] if id in w["attackers"] else w["attackers"]
		for o in other:
			if not (o in out):
				out.append(o)
	return out


func can_declare_war(a: String, b: String) -> String:
	if a == b:
		return "لا يمكن إعلان الحرب على نفسك."
	if country(a).get("annexed", false) or country(b).get("annexed", false):
		return "هذه الدولة لم تعد قائمة."
	if not war_between(a, b).is_empty():
		return "أنتما في حرب بالفعل."
	if int(state.get("truces", {}).get(rel_key(a, b), -1)) > int(state["day"]):
		return "بينكما هدنة حتى %d يوماً أخرى." % (int(state["truces"][rel_key(a, b)]) - int(state["day"]))
	if b in allies(a):
		return "لا يمكن إعلان الحرب على حليف. اخرج من التحالف أولاً."
	if country(a).get("overlord", "") == b or country(b).get("overlord", "") == a:
		return "لا يمكن إعلان الحرب بين دولة تابعة ومتبوعها."
	return ""


func declare_war(a: String, b: String) -> Dictionary:
	if can_declare_war(a, b) != "":
		return {}
	var defenders: Array = [b]
	for al in allies(b):
		if al != a and not (al in allies(a)) and relation(al, a) < 50.0:
			defenders.append(al)
	for v in vassals(b):
		if not (v in defenders) and v != a:
			defenders.append(v)
	var attackers: Array = [a]
	for v in vassals(a):
		if not (v in defenders):
			attackers.append(v)
	var w := {"id": state["next_war_id"], "attackers": attackers, "defenders": defenders, "score": 0.0, "start_day": state["day"], "battles": 0, "active": true}
	state["next_war_id"] = int(state["next_war_id"]) + 1
	state["wars"].append(w)
	set_relation(a, b, minf(relation(a, b), -80.0) - 10.0)
	for x in attackers:
		for y in defenders:
			Market.cancel_pact(self, x, y, "بسبب الحرب")
	for id in alive_ids():
		if id != a and id != b and b in allies(id):
			change_relation(id, a, -30.0)
	var names := "، ".join(PackedStringArray(defenders.map(func(x): return country(x)["name_ar"])))
	add_news("%s تعلن الحرب على %s." % [country(a)["name_ar"], names], "war")
	if state["player"] in defenders:
		push_event("war", "إعلان حرب!", "%s أعلنت الحرب عليك. الدول المشاركة في الدفاع: %s." % [country(a)["name_ar"], names], true)
	return w


## السلام يعيد المناطق المحتلة لأصحابها، إلا أرض keep_loser التي يحتلها keep_side (عند الاستسلام)
func make_peace(w: Dictionary, text: String = "", keep_loser: String = "", keep_side: Array = []) -> void:
	if not w.get("active", true):
		return
	Territory.revert_war_regions(self, w, keep_loser, keep_side)
	w["active"] = false
	# هدنة سنتين بين أطراف الحرب
	for a in w["attackers"]:
		for b in w["defenders"]:
			state["truces"][rel_key(a, b)] = int(state["day"]) + TRUCE_DAYS
	var msg := text
	if msg == "":
		msg = "توقيع السلام بين %s و%s." % [country(w["attackers"][0])["name_ar"], country(w["defenders"][0])["name_ar"]]
	add_news(msg, "peace")
	_cleanup_wars()


func capitulate(w: Dictionary, loser: String, winner: String) -> void:
	var l := country(loser)
	l["overlord"] = winner
	l["stability"] = maxf(10.0, float(l["stability"]) - 10.0)
	for k in l["military"]:
		l["military"][k] = float(l["military"][k]) * 0.6
	# الدول التابعة للخاسر تتحرر
	for v in vassals(loser):
		country(v)["overlord"] = ""
	# الخروج من التحالفات
	for aid in alliance_of(loser):
		state["alliances"][aid]["members"].erase(loser)
	var winner_side: Array = w["attackers"] if winner in w["attackers"] else w["defenders"]
	var text := "%s تستسلم وتصبح تابعة لـ%s، وتبقى المناطق المحتلة بيد المنتصر." % [l["name_ar"], country(winner)["name_ar"]]
	make_peace(w, text, loser, winner_side)
	if Territory.owned(self, loser).is_empty():
		annex(loser, winner)
		return
	if is_player(loser):
		push_event("defeat", "الاستسلام", text, true)
	elif is_player(winner):
		push_event("victory", "انتصار!", text, true)


## ضم دولة لم يبق لها أي منطقة
func annex(id: String, by: String) -> void:
	var c := country(id)
	c["annexed"] = true
	c["overlord"] = ""
	for v in vassals(id):
		country(v)["overlord"] = ""
	for aid in alliance_of(id):
		state["alliances"][aid]["members"].erase(id)
	for w in state["wars"]:
		w["attackers"].erase(id)
		w["defenders"].erase(id)
		if w["attackers"].is_empty() or w["defenders"].is_empty():
			w["active"] = false
	_cleanup_wars()
	var text := "%s تُضم بالكامل إلى %s." % [c["name_ar"], country(by)["name_ar"]]
	add_news(text, "war")
	if is_player(id):
		state["game_over"] = "occupied"
		push_event("game_over", "خسارة بالاحتلال", text, true)
	elif is_player(by):
		push_event("victory", "ضم كامل", text, true)


func _cleanup_wars() -> void:
	state["wars"] = state["wars"].filter(func(w): return w.get("active", true))


# ------------------------------------------------------------------ النووي

func can_nuke(a: String, b: String) -> String:
	var c := country(a)
	if float(c["military"]["nukes"]) < 1.0:
		return "لا تملك رؤوساً نووية."
	if float(c["military"]["missiles"]) < 1.0 and float(c["military"]["bombers"]) < 1.0 and float(c["military"]["submarines"]) < 1.0:
		return "لا تملك وسيلة إيصال (صواريخ أو قاذفات أو غواصات)."
	if war_between(a, b).is_empty():
		return "الضربة النووية ممكنة فقط على دولة في حرب معك."
	return ""


func nuclear_strike(a: String, b: String) -> Dictionary:
	if can_nuke(a, b) != "":
		return {}
	var ca := country(a)
	var cb := country(b)
	ca["military"]["nukes"] = float(ca["military"]["nukes"]) - 1.0
	state["global"]["nuclear_strikes"] = int(state["global"]["nuclear_strikes"]) + 1
	var ad_gen := int(cb["tech"]["air_defense"])
	var intercept := clampf(0.05 * ad_gen * minf(1.0, float(cb["military"]["air_defense"]) / 20.0), 0.0, 0.3)
	var hit := not rng.chance(intercept)
	var result := {"hit": hit}
	if hit:
		Territory.scale_gdp(self, b, 0.88)
		Territory.scale_pop(self, b, 0.97)
		cb["stability"] = maxf(0.0, float(cb["stability"]) - 20.0)
		for k in ["infantry", "armor", "artillery"]:
			cb["military"][k] = float(cb["military"][k]) * 0.85
		var w := war_between(a, b)
		if not w.is_empty():
			var dir := 1.0 if a in w["attackers"] else -1.0
			w["score"] = clampf(float(w["score"]) + 25.0 * dir, -100.0, 100.0)
		add_news("☢ ضربة نووية من %s على %s!" % [ca["name_ar"], cb["name_ar"]], "nuke")
	else:
		add_news("☢ %s تعترض صاروخاً نووياً أطلقته %s." % [cb["name_ar"], ca["name_ar"]], "nuke")
	for id in alive_ids():
		if id != a:
			change_relation(id, a, -40.0)
	ca["stability"] = maxf(0.0, float(ca["stability"]) - 8.0)
	if is_player(b) or is_player(a):
		push_event("nuke", "ضربة نووية", "ضربة نووية من %s على %s. %s" % [ca["name_ar"], cb["name_ar"], "أصابت هدفها." if hit else "تم اعتراضها."], true)
	# الرد النووي من الذكاء الاصطناعي
	if not is_player(b) and can_nuke(b, a) == "" and rng.chance(0.85):
		nuclear_strike(b, a)
	if int(state["global"]["nuclear_strikes"]) >= NUCLEAR_WINTER_STRIKES:
		state["game_over"] = "nuclear_winter"
		push_event("game_over", "شتاء نووي", "عدد الضربات النووية تجاوز ما يحتمله الكوكب. انتهت الحضارة كما نعرفها.", true)
	return result


# ------------------------------------------------------------------ أوامر اللاعب (وأيضاً يستخدمها الذكاء الاصطناعي)

func set_tax(id: String, rate: float) -> void:
	country(id)["tax_rate"] = clampf(rate, 0.05, 0.60)


func set_research(id: String, ratio: float, focus: String) -> void:
	var c := country(id)
	c["research_ratio"] = clampf(ratio, 0.0, 0.05)
	if db.branches.has(focus):
		if focus != c["research_focus"]:
			c["research_progress"] = float(c["research_progress"]) * 0.5
		c["research_focus"] = focus


func toggle_policy(id: String, policy: String) -> void:
	var c := country(id)
	if policy in c["policies"]:
		c["policies"].erase(policy)
	else:
		c["policies"].append(policy)
		c["stability"] = maxf(0.0, float(c["stability"]) - 2.0)


func can_change_government(id: String, gov: String) -> String:
	var c := country(id)
	if c["government"] == gov:
		return "هذا هو نظام الحكم الحالي."
	if float(c["stability"]) < 40.0:
		return "تغيير نظام الحكم يحتاج استقراراً 40 على الأقل."
	if not wars_of(id).is_empty():
		return "لا يمكن تغيير نظام الحكم أثناء الحرب."
	var sup: float = Factions.support(self, c, gov)["total"]
	var need := float(db.factions["support_needed"])
	if sup < need:
		return "دعم الفئات للنظام الجديد %d%% فقط، والمطلوب %d%%." % [int(sup * 100.0), int(need * 100.0)]
	return ""


func change_government(id: String, gov: String) -> bool:
	if can_change_government(id, gov) != "":
		return false
	var c := country(id)
	var old_gov: String = c["government"]
	c["government"] = gov
	c["stability"] = float(c["stability"]) - 20.0
	Factions.shift_for_government(self, c, old_gov, gov)
	add_news("%s تتحول إلى %s." % [c["name_ar"], db.governments[gov]["name_ar"]], "info")
	return true


func unit_cost(c: Dictionary, utype: String) -> float:
	## الكلفة بالمليار دولار للوحدة الواحدة
	var u: Dictionary = db.units[utype]
	var cost := float(u["cost"]) / 1000.0 * db.gen_multiplier(int(c["tech"][u["branch"]]))
	if "war_economy" in c["policies"]:
		cost *= 0.9
	return cost


func order_units(id: String, utype: String, count: float) -> String:
	var c := country(id)
	if not db.units.has(utype) or count <= 0.0:
		return "طلب غير صالح."
	if utype == "nukes":
		if Territory.working_facilities(self, [id], "nuclear").is_empty():
			return "تحتاج منشأة نووية عاملة."
		if float(c["resources"].get("uranium", 0.0)) < 5.0:
			return "تحتاج يورانيوم (5 على الأقل)."
	var total := unit_cost(c, utype) * count
	if total > float(c["treasury"]):
		return "الخزينة لا تكفي. الكلفة %s مليار." % fmt_num(total)
	c["treasury"] = float(c["treasury"]) - total
	c["production"].append({"type": utype, "count": count, "days_left": float(db.units[utype]["build_days"])})
	return ""


func improve_relations(a: String, b: String) -> String:
	var c := country(a)
	var cost := maxf(0.2, float(c["gdp"]) * 0.0005)
	if float(c["treasury"]) < cost:
		return "الخزينة لا تكفي (%s مليار)." % fmt_num(cost)
	if not war_between(a, b).is_empty():
		return "لا يمكن تحسين العلاقات أثناء الحرب."
	c["treasury"] = float(c["treasury"]) - cost
	change_relation(a, b, 8.0)
	return ""


func invest(a: String, b: String) -> String:
	var ca := country(a)
	var cb := country(b)
	var cost := maxf(0.5, float(cb["gdp"]) * 0.01)
	if float(ca["treasury"]) < cost:
		return "الخزينة لا تكفي (%s مليار)." % fmt_num(cost)
	if not war_between(a, b).is_empty():
		return "لا يمكن الاستثمار في دولة عدوة."
	ca["treasury"] = float(ca["treasury"]) - cost
	Territory.add_gdp(self, b, cost * 0.5)
	var inf: Dictionary = cb["influence"]
	var ratio := float(ca["gdp"]) / maxf(1.0, float(cb["gdp"]))
	inf[a] = minf(100.0, float(inf.get(a, 0.0)) + clampf(ratio, 2.0, 12.0))
	change_relation(a, b, 3.0)
	if float(inf[a]) >= 100.0 and relation(a, b) >= 50.0 and cb.get("overlord", "") == "" and ratio >= 3.0 and wars_of(b).is_empty():
		cb["overlord"] = a
		for aid in alliance_of(b):
			state["alliances"][aid]["members"].erase(b)
		add_news("%s تصبح دولة تابعة لـ%s عبر النفوذ الاقتصادي." % [cb["name_ar"], ca["name_ar"]], "good")
		if is_player(a):
			push_event("victory", "تبعية سلمية", "%s أصبحت تابعة لك بفضل استثماراتك ونفوذك." % cb["name_ar"], true)
	return ""


func toggle_sanction(a: String, b: String) -> void:
	var cb := country(b)
	if a in cb["sanctions"]:
		cb["sanctions"].erase(a)
		add_news("%s ترفع العقوبات عن %s." % [country(a)["name_ar"], cb["name_ar"]], "info")
	else:
		cb["sanctions"].append(a)
		change_relation(a, b, -25.0)
		Market.cancel_pact(self, a, b, "بسبب العقوبات")
		add_news("%s تفرض عقوبات على %s." % [country(a)["name_ar"], cb["name_ar"]], "info")


## العرض: هل تقبل الدولة b تحالفاً مع a؟
func propose_alliance(a: String, b: String) -> String:
	if relation(a, b) < 60.0:
		return "%s ترفض: العلاقات يجب أن تكون 60 على الأقل." % country(b)["name_ar"]
	if not war_between(a, b).is_empty():
		return "أنتما في حرب."
	var key := "pact_" + rel_key(a, b)
	if not state["alliances"].has(key):
		state["alliances"][key] = {"name_ar": "تحالف %s و%s" % [country(a)["name_ar"], country(b)["name_ar"]], "members": [a, b]}
	add_news("تحالف عسكري جديد بين %s و%s." % [country(a)["name_ar"], country(b)["name_ar"]], "good")
	return ""


func propose_peace(a: String, b: String) -> String:
	var w := war_between(a, b)
	if w.is_empty():
		return "لا توجد حرب بينكما."
	var b_side_score := float(w["score"]) if b in w["attackers"] else -float(w["score"])
	var days := int(state["day"]) - int(w["start_day"])
	if is_player(b) or b_side_score < 15.0 or (days > 180 and b_side_score < 35.0):
		make_peace(w)
		return ""
	return "%s ترفض السلام لأنها تتقدم في الحرب." % country(b)["name_ar"]


## ضربة صاروخية على منشأة في منطقة يملكها عدو: تعطلها أشهراً إن نجحت
func can_strike_facility(a: String, rid: String, ftype: String) -> String:
	var r: Dictionary = Territory.region(self, rid)
	if r.is_empty() or Territory.facility_count(self, rid, ftype) <= 0:
		return "لا توجد هذه المنشأة هنا."
	if war_between(a, r["owner"]).is_empty():
		return "الضربة ممكنة فقط على منشآت دولة في حرب معك."
	if not Territory.facility_working(self, rid, ftype):
		return "المنشأة معطلة أصلاً."
	if float(country(a)["military"]["missiles"]) < STRIKE_MISSILES:
		return "تحتاج %d صاروخاً على الأقل." % int(STRIKE_MISSILES)
	return ""


func strike_chance(a: String, rid: String) -> float:
	var ca := country(a)
	var cd := country(Territory.region(self, rid)["owner"])
	var ad := float(cd["military"]["air_defense"])
	var p := 0.7 + 0.07 * (int(ca["tech"]["missile"]) - int(cd["tech"]["air_defense"])) - 0.3 * ad / (ad + 40.0)
	return clampf(p, 0.15, 0.9)


func strike_facility(a: String, rid: String, ftype: String) -> Dictionary:
	if can_strike_facility(a, rid, ftype) != "":
		return {}
	var ca := country(a)
	ca["military"]["missiles"] = float(ca["military"]["missiles"]) - STRIKE_MISSILES
	var owner: String = Territory.region(self, rid)["owner"]
	var hit := rng.chance(strike_chance(a, rid))
	var place: String = db.regions[rid]["name_ar"]
	var fname: String = Territory.FACILITY_NAMES[ftype]
	if hit:
		Territory.damage_facility(self, rid, ftype, 6)
		add_news("صواريخ %s تدمر %s في %s." % [ca["name_ar"], fname, place], "war")
	else:
		add_news("%s تعترض صواريخ %s فوق %s." % [country(owner)["name_ar"], ca["name_ar"], place], "war")
	return {"hit": hit, "text": ("أصابت الضربة %s في %s، وستبقى معطلة 6 أشهر." % [fname, place]) if hit else ("اعتُرضت الصواريخ فوق %s." % place)}


## رد اللاعب على حدث فيه خيارات
func resolve_choice(ev: Dictionary, choice: int) -> void:
	if ev.get("kind", "") == "peace_offer" and choice == 0:
		for w in state["wars"]:
			if int(w["id"]) == int(ev["data"]["war_id"]):
				make_peace(w)
				break


# ------------------------------------------------------------------ النهاية

func _check_end_conditions() -> void:
	var pid: String = state["player"]
	var p := player()
	# خسارة داخلية
	if float(p["stability"]) < 10.0:
		p["low_stab_months"] = int(p["low_stab_months"]) + 1
		if int(p["low_stab_months"]) == 1:
			push_event("warning", "خطر انقلاب", "الاستقرار انهار تحت 10. إن بقي كذلك ثلاثة أشهر سيحدث انقلاب.", true)
		if int(p["low_stab_months"]) >= 3:
			state["game_over"] = "coup"
			push_event("game_over", "انقلاب", "الجيش والشارع أطاحوا بحكومتك بعد انهيار الاستقرار.", true)
			return
	else:
		p["low_stab_months"] = 0
	if p.get("overlord", "") != "":
		if state["game_over"] == "":
			state["game_over"] = "occupied"
			push_event("game_over", "خسارة", "دولتك استسلمت وأصبحت تابعة لـ%s." % country(p["overlord"])["name_ar"], true)
		return
	# الفوز (اختياري: يمكن الاستمرار بعده)
	var world_gdp := 0.0
	var my_gdp := 0.0
	var bloc := [pid] + vassals(pid)
	for id in alive_ids():
		world_gdp += float(country(id)["gdp"])
	for id in bloc:
		my_gdp += float(country(id)["gdp"])
	if my_gdp / maxf(1.0, world_gdp) >= 0.40 and not ("economic" in state["victories"]):
		state["victories"].append("economic")
		push_event("victory", "فوز اقتصادي", "أكثر من 40% من اقتصاد العالم تحت سيطرتك. يمكنك الاستمرار في اللعب.", true)
	if vassals(pid).size() * 2 >= alive_ids().size() - 1 and not ("hegemony" in state["victories"]):
		state["victories"].append("hegemony")
		push_event("victory", "فوز بالهيمنة", "نصف دول العالم أصبحت تابعة لك. يمكنك الاستمرار في اللعب.", true)


# ------------------------------------------------------------------ الحفظ

func to_save() -> String:
	state["rng"] = rng.state
	# صيغة ثنائية دقيقة: نص JSON يفقد آخر رقم عشري فتنحرف المحاكاة بعد التحميل
	return Marshalls.raw_to_base64(var_to_bytes(state))


func load_save(text: String) -> bool:
	var parsed: Variant = bytes_to_var(Marshalls.base64_to_raw(text.strip_edges()))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != SAVE_VERSION:
		return false
	state = parsed
	rng = SimRng.new(1)
	rng.state = int(state["rng"])
	pending.clear()
	return true


## بصمة رقمية للحالة لاختبار الحتمية
func checksum() -> int:
	return hash(JSON.stringify(state))


static func fmt_num(v: Variant) -> String:
	var x := float(v)
	if absf(x) >= 1000.0:
		return "%s ألف" % str(snappedf(x / 1000.0, 0.1))
	if absf(x) >= 10.0 or is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return str(snappedf(x, 0.1))
