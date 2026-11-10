## يقرأ ملفات البيانات من مجلد data. المنطق لا يحتوي أرقاماً عن الدول، كلها هنا.
extends RefCounted

const DATA_DIR := "res://data/"

var countries: Array = []        # قوالب الدول كما في الملف
var units: Dictionary = {}
var gen_mult: Array = []
var branches: Dictionary = {}
var governments: Dictionary = {}
var policies: Dictionary = {}
var alliances: Dictionary = {}
var relations: Array = []
var events: Array = []


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
	if c == null or u == null or g == null or a == null or e == null:
		return false
	countries = c["countries"]
	units = u["units"]
	gen_mult = u["generation_multiplier"]
	branches = u["branches"]
	governments = g["governments"]
	policies = g["policies"]
	alliances = a["alliances"]
	relations = a["relations"]
	events = e["events"]
	return true


func gen_multiplier(gen: int) -> float:
	return float(gen_mult[clampi(gen, 1, gen_mult.size() - 1)])
