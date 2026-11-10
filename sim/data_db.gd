## يقرأ ملفات البيانات من مجلد data. المنطق لا يحتوي أرقاماً عن الدول، كلها هنا.
extends RefCounted

const DATA_DIR := "res://data/"

var countries: Array = []        # قوالب الدول كما في الملف
var units: Dictionary = {}
var gen_mult: Array = []
var combat_mult: Array = []
var branches: Dictionary = {}
var governments: Dictionary = {}
var policies: Dictionary = {}
var alliances: Dictionary = {}
var relations: Array = []
var events: Array = []
var market: Dictionary = {}
var factions: Dictionary = {}
var intel: Dictionary = {}
var regions: Dictionary = {}          # id -> بيانات المنطقة الثابتة
var region_ids: Array = []            # ترتيب ثابت للمناطق (للحتمية)
var regions_by_country: Dictionary = {}
var capitals: Dictionary = {}         # دولة -> منطقة العاصمة


static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("تعذر فتح الملف: " + path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("ملف JSON غير صالح: " + path)
	return parsed


func load_all() -> bool:
	var c: Variant = read_json(DATA_DIR + "countries.json")
	var u: Variant = read_json(DATA_DIR + "units.json")
	var g: Variant = read_json(DATA_DIR + "governments.json")
	var a: Variant = read_json(DATA_DIR + "alliances.json")
	var e: Variant = read_json(DATA_DIR + "events.json")
	var r: Variant = read_json(DATA_DIR + "regions.json")
	var mk: Variant = read_json(DATA_DIR + "market.json")
	var fc: Variant = read_json(DATA_DIR + "factions.json")
	var it: Variant = read_json(DATA_DIR + "intel.json")
	if c == null or u == null or g == null or a == null or e == null or r == null or mk == null or fc == null or it == null:
		return false
	intel = it
	market = mk
	factions = fc
	countries = c["countries"]
	units = u["units"]
	gen_mult = u["generation_multiplier"]
	combat_mult = u.get("combat_multiplier", gen_mult)
	branches = u["branches"]
	governments = g["governments"]
	policies = g["policies"]
	alliances = a["alliances"]
	relations = a["relations"]
	events = e["events"]
	for reg in r["regions"]:
		var rid: String = reg["id"]
		regions[rid] = reg
		region_ids.append(rid)
		var cc: String = reg["country"]
		if not regions_by_country.has(cc):
			regions_by_country[cc] = []
		regions_by_country[cc].append(rid)
		if reg["capital"]:
			capitals[cc] = rid
	return true


func gen_multiplier(gen: int) -> float:
	return float(gen_mult[clampi(gen, 1, gen_mult.size() - 1)])


func combat_multiplier(gen: int) -> float:
	return float(combat_mult[clampi(gen, 1, combat_mult.size() - 1)])
