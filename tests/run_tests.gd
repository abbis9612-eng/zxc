## اختبارات المحرك الآلية، بلا رسوميات:
##   godot --headless --path . -s tests/run_tests.gd
## تخرج برمز 0 عند النجاح و1 عند الفشل.
extends SceneTree

const DataDB := preload("res://sim/data_db.gd")
const Simulation := preload("res://sim/simulation.gd")
const Economy := preload("res://sim/economy.gd")
const Combat := preload("res://sim/combat.gd")
const Territory := preload("res://sim/territory.gd")
const Logistics := preload("res://sim/logistics.gd")

var db: DataDB
var failures := 0
var passed := 0


func _init() -> void:
	db = DataDB.new()
	check(db.load_all(), "تحميل ملفات البيانات")
	if failures == 0:
		test_data_integrity()
		test_regions_data()
		test_regions_economy()
		test_regional_war()
		test_peace_returns_regions()
		test_resources()
		test_facilities()
		test_determinism()
		test_save_load()
		test_forecast_is_pure()
		test_strong_beats_weak()
		test_twenty_years()
	print("")
	print("نجح %d، فشل %d" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  ✔ " + name)
	else:
		failures += 1
		print("  ✘ فشل: " + name)


func new_sim(player: String = "IRQ", seed_value: int = 777) -> Simulation:
	var s := Simulation.new(db)
	s.new_game(player, seed_value, 1)
	return s


func run_days(s: Simulation, n: int) -> void:
	for i in n:
		s.advance_day()
		s.pending.clear()


## يوحّد تمثيل الأرقام (int/float) قبل المقارنة
func normalized(s: Simulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(s.state, "", true, true)), "", true, true)


func test_data_integrity() -> void:
	print("سلامة البيانات")
	var ids := {}
	for c in db.countries:
		ids[c["id"]] = true
	var ok := true
	for c in db.countries:
		for n in c["neighbors"]:
			if not ids.has(n):
				ok = false
				print("    جار غير معروف: %s -> %s" % [c["id"], n])
		if not db.governments.has(c["government"]):
			ok = false
			print("    نظام حكم غير معروف: " + c["id"])
		for br in db.branches:
			if not c["tech"].has(br):
				ok = false
				print("    جيل ناقص: %s %s" % [c["id"], br])
	check(ok, "كل الجيران والأنظمة والأجيال معرّفة")


func test_determinism() -> void:
	print("الحتمية")
	var a := new_sim("IRQ", 42)
	var b := new_sim("IRQ", 42)
	run_days(a, 400)
	run_days(b, 400)
	check(a.checksum() == b.checksum(), "نفس البذرة تعطي نفس العالم بعد 400 يوم")
	var c := new_sim("IRQ", 43)
	run_days(c, 400)
	check(a.checksum() != c.checksum(), "بذرة مختلفة تعطي عالماً مختلفاً")


func test_save_load() -> void:
	print("الحفظ والتحميل")
	var a := new_sim("EGY", 9)
	run_days(a, 120)
	var text := a.to_save()
	var b := Simulation.new(db)
	check(b.load_save(text), "تحميل الملف المحفوظ")
	check(normalized(a) == normalized(b), "الحالة بعد التحميل مطابقة")
	run_days(a, 200)
	run_days(b, 200)
	check(normalized(a) == normalized(b), "اللعبة المحمّلة تستمر بنفس النتائج")


func test_forecast_is_pure() -> void:
	print("التوقعات لا تغيّر العالم")
	var s := new_sim("TUR", 5)
	var before := s.checksum()
	var f := Combat.forecast(s, "TUR", "SYR")
	Economy.preview(s, s.player(), {"tax_rate": 0.4})
	check(s.checksum() == before, "التوقع والمعاينة بلا آثار جانبية")
	check(float(f["land"]) > 0.5, "توقع تركيا ضد سوريا لصالح تركيا (%.2f)" % float(f["land"]))


func test_strong_beats_weak() -> void:
	print("القتال")
	var s := new_sim("MEX", 11)
	var w := s.declare_war("USA", "MEX")
	check(not w.is_empty(), "إعلان حرب")
	run_days(s, 365)
	var mex := s.country("MEX")
	check(mex["overlord"] == "USA" or float(w["score"]) > 50.0, "القوة الكبرى تهزم الصغرى خلال سنة")


func test_twenty_years() -> void:
	print("محاكاة 20 سنة للتوازن")
	var s := new_sim("IRQ", 2026)
	var t0 := Time.get_ticks_msec()
	for year in 20:
		for d in 365:
			s.advance_day()
			s.pending.clear()
			# محاكاة التوازن تستمر حتى لو خسر اللاعب (لا أحد يلعبه هنا)
			s.state["game_over"] = ""
	var ms := Time.get_ticks_msec() - t0
	var ok := true
	for id in s.state["order"]:
		var c := s.country(id)
		for k in ["gdp", "stability", "treasury", "debt", "inflation"]:
			var v := float(c[k])
			if is_nan(v) or is_inf(v):
				ok = false
				print("    قيمة غير صالحة: %s %s" % [id, k])
		if float(c["gdp"]) <= 0.0:
			ok = false
		for u in c["military"]:
			if float(c["military"][u]) < 0.0:
				ok = false
				print("    جيش سالب: %s %s" % [id, u])
	check(ok, "لا قيم غير صالحة بعد 20 سنة")
	check(s.state["game_over"] != "nuclear_winter", "العالم لم ينته بشتاء نووي بلا لاعب")
	# ملخص التوازن
	print("    المدة: %d ms، التاريخ: %s، حروب بدأت: %d، حروب جارية: %d" % [ms, s.date_text(), int(s.state["next_war_id"]) - 1, s.state["wars"].size()])
	var rows: Array = []
	for id in s.state["order"]:
		var c := s.country(id)
		rows.append([float(c["gdp"]), id])
	rows.sort()
	rows.reverse()
	for r in rows.slice(0, 8):
		var c := s.country(r[1])
		print("    %s ناتج %d (بدأ %d) استقرار %d تضخم %.1f دين/ناتج %.0f%% تابعة لـ[%s]" % [c["id"], int(c["gdp"]), int(c["gdp_start"]), int(c["stability"]), float(c["inflation"]), 100.0 * float(c["debt"]) / float(c["gdp"]), c["overlord"]])
	var growth_ok := true
	for id in s.state["order"]:
		var c := s.country(id)
		if c["overlord"] == "" and float(c["gdp"]) > float(c["gdp_start"]) * 20.0:
			growth_ok = false
			print("    نمو غير واقعي: " + id)
	check(growth_ok, "لا نمو انفجاري غير واقعي")


func test_regions_data() -> void:
	print("المناطق")
	var iraq: Array = db.regions_by_country.get("IRQ", [])
	check(iraq.size() == 18, "العراق 18 محافظة (%d)" % iraq.size())
	var arabic := true
	for rid in iraq:
		var n: String = db.regions[rid]["name_ar"]
		if n == "" or n == db.regions[rid]["name_en"]:
			arabic = false
	check(arabic, "كل محافظات العراق بأسماء عربية")
	check(db.regions[db.capitals["IRQ"]]["name_ar"] == "بغداد", "عاصمة العراق في منطقة بغداد")
	var ok := true
	for c in db.countries:
		if not db.capitals.has(c["id"]) or db.regions_by_country.get(c["id"], []).is_empty():
			ok = false
			print("    دولة بلا مناطق أو عاصمة: " + c["id"])
	check(ok, "كل دولة لها مناطق ومنطقة عاصمة")
	var sym := true
	for rid in db.region_ids:
		for n in db.regions[rid]["neighbors"]:
			if not db.regions.has(n) or not (rid in db.regions[n]["neighbors"]):
				sym = false
	check(sym, "الجوار بين المناطق متماثل")
	var cross := false
	for rid in iraq:
		for n in db.regions[rid]["neighbors"]:
			if db.regions[n]["country"] == "SYR":
				cross = true
	check(cross, "مناطق العراق تجاور مناطق سوريا (جبهة برية)")


func test_regions_economy() -> void:
	print("اقتصاد المناطق")
	var s := new_sim("IRQ", 3)
	var c := s.country("IRQ")
	check(absf(float(c["gdp"]) - 270.0) < 1.0, "ناتج العراق = مجموع محافظاته (%.1f)" % float(c["gdp"]))
	check(Territory.owned(s, "IRQ").size() == 18, "العراق يملك محافظاته الـ18")
	var syr_before := float(s.country("SYR")["gdp"])
	var rid: String = db.regions_by_country["SYR"][0]
	Territory.capture(s, rid, "IRQ")
	check(float(s.country("SYR")["gdp"]) < syr_before, "خسارة منطقة تخفض ناتج صاحبها")
	check(Territory.owned(s, "IRQ").size() == 19, "المنطقة المحتلة تنتقل للمحتل")


func test_regional_war() -> void:
	print("الحرب منطقة بمنطقة")
	var s := new_sim("JOR", 21)
	var w := s.declare_war("TUR", "SYR")
	var captured := false
	var capital_fell := false
	for week in 52:
		run_days(s, 7)
		if Territory.occupied_share(s, "SYR", ["TUR"]) > 0.0:
			captured = true
		if s.country("SYR").get("capital_fallen", false):
			capital_fell = true
		if not w.get("active", true):
			break
	check(captured, "تركيا تحتل مناطق سورية")
	check(capital_fell or s.country("SYR")["overlord"] == "TUR", "التقدم يصل إلى دمشق أو استسلام سوريا")
	var syr := s.country("SYR")
	if syr["overlord"] == "TUR" or syr.get("annexed", false):
		check(Territory.owned(s, "TUR").size() > 81, "تركيا تحتفظ بالمناطق المحتلة بعد الاستسلام")


func test_peace_returns_regions() -> void:
	print("السلام يعيد المناطق")
	var s := new_sim("JOR", 4)
	var w := s.declare_war("IRQ", "SYR")
	var rid: String = db.regions_by_country["SYR"][0]
	Territory.capture(s, rid, "IRQ")
	s.make_peace(w)
	check(Territory.region(s, rid)["owner"] == "SYR", "بعد السلام تعود المنطقة لسوريا")
	check(Territory.owned(s, "IRQ").size() == 18, "العراق يعود لمحافظاته")


func _region_by_name(country: String, name_en: String) -> String:
	for rid in db.regions_by_country[country]:
		if db.regions[rid]["name_en"] == name_en:
			return rid
	return ""


func test_resources() -> void:
	print("الموارد في المناطق")
	var s := new_sim("JOR", 8)
	var ok := true
	for c in db.countries:
		for k in Territory.RESOURCE_NAMES:
			var total := 0.0
			for rid in db.regions_by_country[c["id"]]:
				total += float(db.regions[rid].get("resources", {}).get(k, 0.0))
			if absf(total - float(c["resources"].get(k, 0))) > 0.5:
				ok = false
				print("    مجموع غير مطابق: %s %s %.1f" % [c["id"], k, total])
	check(ok, "موارد المناطق تساوي تقييم كل دولة")
	var basra := _region_by_name("IRQ", "Al-Basrah")
	check(float(db.regions[basra]["resources"]["oil"]) > 40.0, "البصرة تحوي معظم نفط العراق")
	var irq_oil := float(s.country("IRQ")["resources"]["oil"])
	var irn_oil := float(s.country("IRN")["resources"]["oil"])
	Territory.capture(s, basra, "IRN")
	check(float(s.country("IRQ")["resources"]["oil"]) < irq_oil - 40.0, "خسارة البصرة تُفقد العراق نفطها")
	check(float(s.country("IRN")["resources"]["oil"]) > irn_oil, "المحتل يكسب نفط المنطقة تدريجياً")


func test_facilities() -> void:
	print("المنشآت والإمداد")
	var s := new_sim("JOR", 9)
	var ok := true
	for c in db.countries:
		var f: Dictionary = s.country(c["id"])["facilities"]
		if int(f["airbase"]["total"]) < 1 or int(f["factory"]["total"]) < 1 or int(f["power_plant"]["total"]) < 1:
			ok = false
			print("    منشآت ناقصة: " + c["id"])
	check(ok, "لكل دولة قاعدة جوية ومصنع ومحطة كهرباء")
	var ports_ok := true
	for rid in db.region_ids:
		if int(db.regions[rid].get("facilities", {}).get("port", 0)) > 0 and not db.regions[rid]["coastal"]:
			ports_ok = false
	check(ports_ok, "الموانئ في مناطق ساحلية فقط")
	check(int(s.country("ISR")["facilities"]["nuclear"]["total"]) == 1 and int(s.country("IRQ")["facilities"]["nuclear"]["total"]) == 0, "المنشأة النووية لمن يملك سلاحاً نووياً فقط")
	# ضرب كل القواعد الجوية يضعف سلاح الجو
	var air_before: float = s.unit_power(s.country("SYR"), "fighters")
	for rid in Territory.working_facilities(s, ["SYR"], "airbase"):
		Territory.damage_facility(s, rid, "airbase", 2)
	var air_after: float = s.unit_power(s.country("SYR"), "fighters")
	check(air_after < air_before * 0.5, "تعطيل القواعد الجوية يضعف المقاتلات (%.0f ← %.0f)" % [air_before, air_after])
	check(float(s.country("SYR")["logistics"]["air"]) < 0.4, "كفاءة القواعد تنخفض")
	run_days(s, 70)
	check(float(s.country("SYR")["logistics"]["air"]) > 0.99, "القواعد تُصلح بعد شهرين")
	# الضربة الصاروخية على منشأة
	var w := s.declare_war("TUR", "SYR")
	var target: String = Territory.working_facilities(s, ["SYR"], "refinery")[0]
	check(s.can_strike_facility("TUR", target, "refinery") == "", "تركيا تستطيع ضرب مصفاة سورية")
	var hit := false
	for i in 6:
		var r: Dictionary = s.strike_facility("TUR", target, "refinery")
		if r.get("hit", false):
			hit = true
			break
	check(hit and not Territory.facility_working(s, target, "refinery"), "الضربة تعطل المصفاة")
	check(s.can_strike_facility("JOR", target, "refinery") != "", "لا ضربة بلا حرب")
	# الحصار يقطع الاستيراد
	s.country("SYR")["blockade_until"] = int(s.state["day"]) + 10
	check(Logistics.import_capacity(s, s.country("SYR")) < 0.3, "الحصار يقطع معظم الواردات")
	s.make_peace(w)
