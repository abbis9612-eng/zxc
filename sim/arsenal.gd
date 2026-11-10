## مخزون السلاح بدفعات، لكل دفعة جيلها. التصنيع يضيف جيل الدولة، والاستيراد قد يأتي بجيل مختلف.
## military يبقى مجموع الدفعات حتى تقرأه الواجهة والشروط.
extends RefCounted

const Logistics := preload("res://sim/logistics.gd")


static func init_country(sim, c: Dictionary) -> void:
	var stocks := {}
	for k in sim.db.units:
		var n := float(c["military"].get(k, 0.0))
		c["military"][k] = n
		var gen := int(c["tech"][sim.db.units[k]["branch"]])
		stocks[k] = [{"n": n, "gen": gen}] if n > 0.0 else []
	c["stocks"] = stocks


static func sync(c: Dictionary, utype: String) -> void:
	var total := 0.0
	var kept: Array = []
	for b in c["stocks"][utype]:
		var n := float(b["n"])
		if n <= 0.05:
			continue
		b["n"] = n
		kept.append(b)
		total += n
	c["stocks"][utype] = kept
	c["military"][utype] = total


static func add(c: Dictionary, utype: String, count: float, gen: int) -> void:
	if count <= 0.0 or not c.has("stocks"):
		return
	var g := clampi(gen, 1, 5)
	var batches: Array = c["stocks"][utype]
	for b in batches:
		if int(b["gen"]) == g:
			b["n"] = float(b["n"]) + count
			sync(c, utype)
			return
	batches.append({"n": count, "gen": g})
	sync(c, utype)


static func remove(c: Dictionary, utype: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if not c.has("stocks"):
		c["military"][utype] = maxf(0.0, float(c["military"].get(utype, 0.0)) - amount)
		return
	var total := float(c["military"].get(utype, 0.0))
	if total <= amount:
		c["stocks"][utype] = []
		c["military"][utype] = 0.0
		return
	var keep := 1.0 - amount / total
	for b in c["stocks"][utype]:
		b["n"] = float(b["n"]) * keep
	sync(c, utype)


static func lose_fraction(c: Dictionary, utype: String, frac: float) -> float:
	var f := clampf(frac, 0.0, 0.5)
	var before := float(c["military"].get(utype, 0.0))
	if f <= 0.0 or before <= 0.0:
		return 0.0
	if not c.has("stocks"):
		var lost: float = before * f
		c["military"][utype] = before - lost
		return lost
	for b in c["stocks"][utype]:
		b["n"] = float(b["n"]) * (1.0 - f)
	sync(c, utype)
	return before - float(c["military"][utype])


static func scale_types(c: Dictionary, types: Array, factor: float) -> void:
	for k in types:
		if not c.has("stocks"):
			c["military"][k] = float(c["military"].get(k, 0.0)) * factor
			continue
		for b in c["stocks"][k]:
			b["n"] = float(b["n"]) * factor
		sync(c, k)


static func scale(c: Dictionary, factor: float) -> void:
	if not c.has("stocks"):
		for k in c["military"]:
			c["military"][k] = float(c["military"][k]) * factor
		return
	for k in c["stocks"]:
		for b in c["stocks"][k]:
			b["n"] = float(b["n"]) * factor
		sync(c, k)


static func power(sim, c: Dictionary, utype: String) -> float:
	var u: Dictionary = sim.db.units[utype]
	var q := float(c.get("quality", 1.0))
	var lf: float = Logistics.unit_factor(c, utype)
	var base := float(u["power"]) * lf * q
	if c.has("stocks"):
		var total := 0.0
		for b in c["stocks"].get(utype, []):
			total += float(b["n"]) * base * sim.db.combat_multiplier(int(b["gen"]))
		return total
	return float(c["military"].get(utype, 0.0)) * base * sim.db.combat_multiplier(int(c["tech"][u["branch"]]))
