## اختبارات المحرك الآلية، بلا رسوميات:
##   godot --headless --path . -s tests/run_tests.gd
## تخرج برمز 0 عند النجاح و1 عند الفشل.
extends SceneTree

const DataDB := preload("res://sim/data_db.gd")
const Simulation := preload("res://sim/simulation.gd")
const Economy := preload("res://sim/economy.gd")
const Combat := preload("res://sim/combat.gd")

var db: DataDB
var failures := 0
var passed := 0


func _init() -> void:
	db = DataDB.new()
	check(db.load_all(), "تحميل ملفات البيانات")
	if failures == 0:
		test_data_integrity()
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
		run_days(s, 365)
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
