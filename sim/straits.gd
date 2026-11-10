## المضائق والممرات: هرمز والسويس والبوسفور وغيرها.
## الإغلاق يقطع صادرات من تمر تجارتهم بالممر (إلا المسيطر الذي أغلقه)،
## ويرفع التوتر، ويقصّر وصول الأسطول لمن ليس مسيطراً ولا حليفاً لمسيطر.
## كل الأرقام في data/straits.json. الدولة غير الممثَّلة في المحاكاة تُتجاهل.
extends RefCounted


static func rules(sim) -> Dictionary:
	return sim.db.straits["rules"]


static func all(sim) -> Array:
	return sim.db.straits["straits"]


static func find(sim, sid: String) -> Dictionary:
	for s in all(sim):
		if s["id"] == sid:
			return s
	return {}


static func names(sim) -> Array:
	return sim.db.straits["state_names"]


static func init_state(sim) -> void:
	var st := {}
	for s in all(sim):
		st[s["id"]] = {"st": 0, "by": "", "since": 0}
	sim.state["straits"] = st
	sim.state["global"]["tension"] = 0.0


static func entry(sim, sid: String) -> Dictionary:
	return sim.state.get("straits", {}).get(sid, {})


static func state_of(sim, sid: String) -> int:
	return int(entry(sim, sid).get("st", 0))


## المسيطرون الأحياء فقط، بترتيب البيانات
static func owners(sim, s: Dictionary) -> Array:
	var out: Array = []
	for cid in s["controllers"]:
		var c: Dictionary = sim.country(cid)
		if c.is_empty() or c.get("annexed", false):
			continue
		if not (cid in out):
			out.append(cid)
	return out


static func player_controls(sim, sid: String) -> bool:
	var s := find(sim, sid)
	if s.is_empty():
		return false
	return sim.state["player"] in owners(sim, s)


# ------------------------------------------------------------------ الجغرافيا

static func _hav(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
	var r := PI / 180.0
	var dlat := (lat2 - lat1) * r
	var dlon := (lon2 - lon1) * r
	var a := sin(dlat * 0.5) * sin(dlat * 0.5) + cos(lat1 * r) * cos(lat2 * r) * sin(dlon * 0.5) * sin(dlon * 0.5)
	return 12742.0 * asin(sqrt(clampf(a, 0.0, 1.0)))


## هل يقع الممر على الطريق بين عاصمتي الدولتين؟ اختبار الانحراف، بلا حالة عشوائية.
static func on_route(sim, s: Dictionary, a: String, b: String) -> bool:
	var ca: Dictionary = sim.country(a)
	var cb: Dictionary = sim.country(b)
	if ca.is_empty() or cb.is_empty():
		return false
	var cfg: Dictionary = rules(sim)
	var d := _hav(float(ca["lon"]), float(ca["lat"]), float(cb["lon"]), float(cb["lat"]))
	if d < float(cfg["min_route_km"]):
		return false
	var via := _hav(float(ca["lon"]), float(ca["lat"]), float(s["lon"]), float(s["lat"]))
	via += _hav(float(s["lon"]), float(s["lat"]), float(cb["lon"]), float(cb["lat"]))
	return via < d * float(cfg["detour_factor"]) + float(cfg["detour_km"])


static func _exempt_naval(sim, actor: String, s: Dictionary) -> bool:
	for o in owners(sim, s):
		if o == actor or o in sim.allies(actor):
			return true
	return false


## مضاعف وصول البحر من a إلى b. 1 = بلا عائق.
static func reach(sim, a: String, b: String) -> float:
	if not sim.state.has("straits") or a == b:
		return 1.0
	var cfg: Dictionary = rules(sim)
	var m := 1.0
	for s in all(sim):
		var st := state_of(sim, s["id"])
		if st == 0 or _exempt_naval(sim, a, s) or not on_route(sim, s, a, b):
			continue
		m *= float(cfg["reach_closed"]) if st == 2 else float(cfg["reach_threatened"])
	return m


## أضيق ممر على طريق هذه الدولة نحو أي عدو في الجبهة.
static func reach_front(sim, id: String, enemies: Array) -> float:
	if enemies.is_empty():
		return 1.0
	var m := 1.0
	for e in enemies:
		m = minf(m, reach(sim, id, str(e)))
	return m


# ------------------------------------------------------------------ الاقتصاد

## حصة الصادرات المعطلة (0 إلى السقف). المسيطر الذي أغلق الممر لا يُقطع.
static func export_loss(sim, id: String) -> float:
	if not sim.state.has("straits"):
		return 0.0
	var cfg: Dictionary = rules(sim)
	var loss := 0.0
	for s in all(sim):
		var st := state_of(sim, s["id"])
		if st == 0:
			continue
		var share := float(s["users"].get(id, 0.0))
		if share <= 0.0:
			continue
		var e: Dictionary = entry(sim, s["id"])
		if id in owners(sim, s) and str(e.get("by", "")) == id:
			continue
		var w := 1.0 if st == 2 else float(cfg["threatened_export"])
		loss = 1.0 - (1.0 - loss) * (1.0 - share * w)
	return clampf(loss, 0.0, float(cfg["export_loss_cap"]))


## ضغط الممرات على نفط العالم: مغلق بحصته، ومهدد بجزء منها. للعرض والتوتر، والسعر يتحرك من قطع التصدير.
static func oil_disruption(sim) -> float:
	if not sim.state.has("straits"):
		return 0.0
	var w := float(rules(sim)["oil_threatened_weight"])
	var f := 0.0
	for s in all(sim):
		var st := state_of(sim, s["id"])
		if st == 2:
			f += float(s["oil_share"])
		elif st == 1:
			f += float(s["oil_share"]) * w
	return f


# ------------------------------------------------------------------ القرار

static func can_close(sim, actor: String, sid: String) -> String:
	var s := find(sim, sid)
	if s.is_empty():
		return "ممر غير معروف."
	if sim.country(actor).is_empty() or sim.country(actor).get("annexed", false):
		return "هذه الدولة لا تستطيع إغلاق ممر."
	if not (actor in owners(sim, s)):
		return "لا تسيطر على %s." % s["name_ar"]
	if state_of(sim, sid) == 2:
		return "%s مغلق بالفعل." % s["name_ar"]
	return ""


static func can_open(sim, actor: String, sid: String) -> String:
	var s := find(sim, sid)
	if s.is_empty():
		return "ممر غير معروف."
	if state_of(sim, sid) != 2:
		return "%s ليس مغلقاً." % s["name_ar"]
	if str(entry(sim, sid).get("by", "")) != actor:
		return "الذي أغلق %s هو من يعيد فتحه." % s["name_ar"]
	return ""


## أثر الإغلاق بلا تعديل على الحالة: من تتضرر تجارته، وكم تنخفض العلاقة، وكم يرتفع التوتر.
static func close_preview(sim, actor: String, sid: String) -> Dictionary:
	var s := find(sim, sid)
	var cfg: Dictionary = rules(sim)
	var hurt: Array = []
	for uid in s.get("users", {}):
		if sim.country(uid).is_empty() or sim.country(uid).get("annexed", false) or uid == actor:
			continue
		var share := float(s["users"][uid])
		if share <= 0.0:
			continue
		hurt.append({"id": uid, "share": share, "relation": -float(cfg["relation_per_share"]) * share})
	hurt.sort_custom(func(a, b): return float(a["share"]) > float(b["share"]))
	var powers: Array = []
	for gid in cfg["great_powers"]:
		if gid == actor or sim.country(gid).is_empty() or sim.country(gid).get("annexed", false):
			continue
		powers.append(gid)
	var tension := float(cfg["tension_close_high"]) if float(s.get("oil_share", 0.0)) > float(cfg["oil_close_tension_threshold"]) else float(cfg["tension_close_low"])
	return {"hurt": hurt, "powers": powers, "power_hit": -float(cfg["great_power_hit"]), "tension": tension, "reach": float(cfg["reach_closed"])}


static func close(sim, actor: String, sid: String) -> String:
	var why := can_close(sim, actor, sid)
	if why != "":
		return why
	var s := find(sim, sid)
	var e: Dictionary = entry(sim, sid)
	e["st"] = 2
	e["by"] = actor
	e["since"] = int(sim.state["day"])
	var preview: Dictionary = close_preview(sim, actor, sid)
	for h in preview["hurt"]:
		sim.change_relation(actor, h["id"], float(h["relation"]))
	for gid in preview["powers"]:
		sim.change_relation(actor, gid, float(preview["power_hit"]))
	var g: Dictionary = sim.state["global"]
	g["tension"] = clampf(float(g.get("tension", 0.0)) + float(preview["tension"]), 0.0, 100.0)
	sim.add_news("%s تغلق %s. الملاحة تتعطل وأسعار النفط مرشحة للارتفاع." % [sim.country(actor)["name_ar"], s["name_ar"]], "war")
	return ""


static func open(sim, actor: String, sid: String) -> String:
	var why := can_open(sim, actor, sid)
	if why != "":
		return why
	_force_open(sim, find(sim, sid), false)
	return ""


static func _force_open(sim, s: Dictionary, silent: bool) -> void:
	var e: Dictionary = entry(sim, s["id"])
	var was := int(e.get("st", 0))
	e["st"] = 0
	e["by"] = ""
	e["since"] = int(sim.state["day"])
	if was == 2 and not silent:
		sim.add_news("أُعيد فتح %s أمام الملاحة." % s["name_ar"], "world")


static func _pick(sim, opts: Array) -> String:
	var tot := 0.0
	for o in opts:
		tot += maxf(0.0, float(o[1]))
	if tot <= 0.0:
		return str(opts[0][0])
	var x: float = sim.rng.next_float() * tot
	for o in opts:
		x -= maxf(0.0, float(o[1]))
		if x <= 0.0:
			return str(o[0])
	return str(opts[opts.size() - 1][0])


static func _alive(sim, cid: String) -> bool:
	var c: Dictionary = sim.country(cid)
	return not c.is_empty() and not c.get("annexed", false)


# ------------------------------------------------------------------ الشهري

static func monthly(sim) -> void:
	if not sim.state.has("straits"):
		init_state(sim)
	var cfg: Dictionary = rules(sim)
	for s in all(sim):
		var e: Dictionary = entry(sim, s["id"])
		var ow: Array = owners(sim, s)
		if int(e["st"]) == 2:
			var by := str(e.get("by", ""))
			if not _alive(sim, by) or not (by in ow):
				_force_open(sim, s, false)
				continue
			if sim.is_player(by):
				continue
			var wars: int = sim.wars_of(by).size()
			var months := float(int(sim.state["day"]) - int(e["since"])) / 30.0
			var keep_w := float(cfg["ai_keep_at_war"]) if wars > 0 else float(cfg["ai_keep_peace"])
			var open_w := float(cfg["ai_open_war"]) if wars > 0 else float(cfg["ai_open_peace_base"])
			open_w += months * float(cfg["ai_open_per_month"])
			if _pick(sim, [["open", open_w], ["keep", keep_w]]) == "open":
				_force_open(sim, s, false)
			continue
		var risk := float(sim.state["global"].get("tension", 0.0)) / float(cfg["tension_div"])
		for o in ow:
			var enemies: Array = sim.enemies_of(o)
			if enemies.is_empty():
				continue
			risk += float(cfg["threat_war"])
			var sharp := false
			for x in enemies:
				if sim.country(x).is_empty():
					continue
				if float(s["users"].get(x, 0.0)) > 0.0 or float(sim.country(x)["military"].get("nukes", 0.0)) >= 1.0:
					sharp = true
					break
			if sharp:
				risk += float(cfg["threat_user_or_nuke"])
		e["st"] = 1 if risk > float(cfg["threat_level"]) else 0
		e["by"] = ""
		for o in ow:
			if sim.is_player(o) or sim.enemies_of(o).is_empty():
				continue
			var hit := 0.0
			for x in sim.enemies_of(o):
				if sim.country(x).is_empty():
					continue
				hit += float(s["users"].get(x, 0.0))
				if float(sim.country(x)["military"].get("nukes", 0.0)) >= 1.0:
					hit += float(cfg["nuclear_hit"])
			var close_w := hit * float(cfg["ai_close_per_hit"])
			if float(sim.state["global"].get("tension", 0.0)) > float(cfg["ai_tension_hot"]):
				close_w += float(cfg["ai_close_tension"])
			if _pick(sim, [["close", close_w], ["no", float(cfg["ai_close_no"])]]) == "close":
				close(sim, o, s["id"])
				break
	var wars_n: int = sim.state["wars"].size()
	var t := float(sim.state["global"].get("tension", 0.0))
	sim.state["global"]["tension"] = clampf(t * float(cfg["tension_decay"]) + wars_n * float(cfg["tension_per_war"]) + oil_disruption(sim) * float(cfg["tension_per_oil"]), 0.0, 100.0)
