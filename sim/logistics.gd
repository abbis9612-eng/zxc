## الإمداد: الموارد والمنشآت تتحول إلى عوامل تؤثر في القتال والإنتاج والاقتصاد.
## نقص المورد يُعوَّض بالاستيراد، إلا تحت العقوبات أو الحصار البحري أو مضيق يمر به تجارتك.
extends RefCounted

const Straits := preload("res://sim/straits.gd")

const NEED := 40.0           # حاجة الدولة من المورد (بمقياس التقييم 0-100)
const FOOD_NEED := 35.0
const BASE_IMPORT := 0.9
const MAX_IMPORT := 1.0
const BLOCKADE_DAYS := 14


## نسبة المنشآت العاملة من نوع ما (0 إن لم يكن لديها أي منها)
static func ratio(c: Dictionary, ftype: String) -> float:
	var f: Dictionary = c.get("facilities", {}).get(ftype, {"total": 0, "working": 0})
	if int(f["total"]) <= 0:
		return 0.0
	return float(f["working"]) / float(f["total"])


static func blockaded(sim, c: Dictionary) -> bool:
	return int(c.get("blockade_until", -1)) >= int(sim.state["day"])


## قدرة الاستيراد: العقوبات والحصار يقطعانها
static func import_capacity(sim, c: Dictionary) -> float:
	var cap: float = BASE_IMPORT - 0.12 * c.get("sanctions", []).size()
	# الاتفاقيات التجارية تفتح الأسواق
	cap += _pact_count(sim, c["id"]) * float(sim.db.market.get("trade_pact", {}).get("import_bonus", 0.0))
	if blockaded(sim, c):
		cap *= 0.3
	var strait_loss := Straits.export_loss(sim, c["id"])
	if strait_loss > 0.0:
		cap *= 1.0 - strait_loss * float(Straits.rules(sim)["import_cut"])
	if ratio(c, "port") <= 0.0 and c.get("facilities", {}).get("port", {}).get("total", 0) > 0:
		cap *= 0.6   # فقدت كل موانئها
	return clampf(cap, 0.05, MAX_IMPORT)


static func _effective(supply: float, need: float, imp: float) -> float:
	return supply + imp * maxf(0.0, need - supply)


## كل العوامل في قاموس واحد يُخزن في الدولة ويقرؤه القتال والإنتاج والواجهة
static func compute(sim, c: Dictionary) -> Dictionary:
	var res: Dictionary = c.get("resources", {})
	var imp := import_capacity(sim, c)
	var refinery := ratio(c, "refinery")
	var fuel_supply := float(res.get("oil", 0.0)) * maxf(0.2, refinery)
	var fuel := clampf(_effective(fuel_supply, NEED, imp) / NEED, 0.5, 1.0)
	var steel := clampf(_effective(float(res.get("steel", 0.0)), NEED, imp) / NEED, 0.5, 1.0)
	var food := _effective(float(res.get("food", 0.0)), FOOD_NEED, imp)
	return {
		"import": imp,
		"fuel": fuel,
		"air": 0.3 + 0.7 * ratio(c, "airbase"),
		"sea": 0.3 + 0.7 * ratio(c, "port"),
		"production": steel * (0.4 + 0.6 * ratio(c, "factory")),
		"power": ratio(c, "power_plant"),
		"food": food,
		"food_penalty": maxf(0.0, FOOD_NEED - food) * 0.5,
		"growth_penalty": (1.0 - ratio(c, "power_plant")) * 3.0,
	}


static func get_factors(c: Dictionary) -> Dictionary:
	return c.get("logistics", {})


## مضاعف القتال لكل صنف حسب الإمداد والقواعد
static func unit_factor(c: Dictionary, utype: String) -> float:
	var l: Dictionary = c.get("logistics", {})
	if l.is_empty():
		return 1.0
	match utype:
		"fighters", "bombers", "helicopters":
			return float(l["air"]) * float(l["fuel"])
		"ships", "submarines":
			return float(l["sea"]) * float(l["fuel"])
		"infantry", "armor":
			return float(l["fuel"])
	return 1.0


static func _pact_count(sim, id: String) -> int:
	var n := 0
	for k in sim.state.get("trade_pacts", {}):
		var parts: PackedStringArray = String(k).split("|")
		if parts[0] == id or parts[1] == id:
			n += 1
	return n
