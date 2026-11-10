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
const Market := preload("res://sim/market.gd")
const Factions := preload("res://sim/factions.gd")
const Intel := preload("res://sim/intel.gd")
const Divisions := preload("res://sim/divisions.gd")
const Straits := preload("res://sim/straits.gd")

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
		test_market()
		test_trade_pacts()
		test_straits()
		test_factions()
		test_intel()
		test_divisions()
		test_determinism()
		test_save_load()
		test_forecast_is_pure()
		test_research_forecast()
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


## توقع مدة البحث يطابق ما يحدث فعلاً، ولا يغيّر العالم
func test_research_forecast() -> void:
	print("توقع البحث")
	var s := new_sim("SAU", 11)
	var p: Dictionary = s.player()
	s.set_research("SAU", 0.02, "air_defense")
	var gen0 := int(p["tech"]["air_defense"])
	var before := s.checksum()
	var months := Economy.research_months(s, p, "air_defense", 0.02)
	var doubled := Economy.research_months(s, p, "air_defense", 0.04)
	check(s.checksum() == before, "توقع البحث بلا آثار جانبية")
	check(months > 0 and doubled <= ceili(months / 2.0) + 1, "مضاعفة الميزانية تختصر المدة للنصف تقريباً (%d ← %d شهراً)" % [months, doubled])
	# نشغّل الأشهر المتوقعة (أياماً) ونتأكد أن الجيل التالي وصل في الوقت المتوقع تقريباً
	var hit := -1
	for m in months + 3:
		run_days(s, 30)
		if int(p["tech"]["air_defense"]) > gen0:
			hit = m + 1
			break
	check(hit > 0 and absi(hit - months) <= 2, "الجيل التالي وصل بعد %d شهراً، والتوقع %d" % [hit, months])
	p["tech"]["land"] = 5
	check(Economy.research_months(s, p, "land", 0.02) == -1, "الفرع في أعلى جيل")


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
	# ضرب كل القواعد الجوية يضعف سلاح الجو (كندا: بعيدة عن حروب الذكاء الاصطناعي)
	var air_before: float = s.unit_power(s.country("CAN"), "fighters")
	for rid in Territory.working_facilities(s, ["CAN"], "airbase"):
		Territory.damage_facility(s, rid, "airbase", 2)
	var air_after: float = s.unit_power(s.country("CAN"), "fighters")
	check(air_after < air_before * 0.5, "تعطيل القواعد الجوية يضعف المقاتلات (%.0f ← %.0f)" % [air_before, air_after])
	check(float(s.country("CAN")["logistics"]["air"]) < 0.4, "كفاءة القواعد تنخفض")
	run_days(s, 70)
	check(float(s.country("CAN")["logistics"]["air"]) > 0.99, "القواعد تُصلح بعد شهرين")
	# الضربة الصاروخية على منشأة (عالم جديد بلا معارك بعد)
	s = new_sim("JOR", 9)
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


func test_market() -> void:
	print("السوق العالمي")
	var s := new_sim("JOR", 12)
	var ok := true
	Market.monthly(s)
	for k in Market.commodities(s):
		if absf(Market.price(s, k) - 1.0) > 0.03:
			ok = false
			print("    سعر غير متوازن في البداية: %s %.2f" % [k, Market.price(s, k)])
	check(ok, "الأسعار متوازنة في البداية")
	var inc_ok := true
	for id in s.state["order"]:
		if absf(float(s.country(id)["trade_income"])) > float(s.country(id)["gdp"]) * 0.002:
			inc_ok = false
	check(inc_ok, "لا أثر للتجارة على الميزانية في عالم بلا اضطرابات")
	# حصار وعقوبات على السعودية: النفط يرتفع، المصدرون يربحون، المستوردون يدفعون
	var sau := s.country("SAU")
	for i in 6:
		sau["blockade_until"] = int(s.state["day"]) + 30
		Market.monthly(s)
	check(Market.price(s, "oil") > 1.15, "حصار السعودية يرفع سعر النفط (%.2f)" % Market.price(s, "oil"))
	check(float(s.country("IRQ")["trade_income"]) > 0.0, "العراق المصدّر يربح من ارتفاع النفط (%.2f)" % float(s.country("IRQ")["trade_income"]))
	check(float(s.country("JPN")["trade_income"]) < 0.0, "اليابان المستوردة تدفع أكثر (%.2f)" % float(s.country("JPN")["trade_income"]))
	check(float(sau["trade_income"]) < 0.0, "السعودية المحاصرة تخسر صادراتها")
	# فقدان البصرة يُفقد العراق ريع نفطها مع ناتجها
	var s2 := new_sim("JOR", 12)
	var gdp0 := float(s2.country("IRQ")["gdp"])
	Territory.capture(s2, _region_by_name("IRQ", "Al-Basrah"), "IRN")
	check(float(s2.country("IRQ")["gdp"]) < gdp0 * 0.75, "فقدان البصرة يُفقد العراق أكثر من ربع ناتجه (%.0f ← %.0f)" % [gdp0, float(s2.country("IRQ")["gdp"])])
	# بعد خسارة البصرة لم يعد العراق يربح من ارتفاع النفط بنفس القدر
	Market.apply_shock(s, {"oil": 1.0}, 1)
	var flows: Dictionary = Market.net_flows(s2, s2.country("IRQ"), Market.world_gdp(s2))
	check(float(flows["oil"]) < 50.0, "صادرات العراق النفطية تنخفض بعد خسارة البصرة (%.0f)" % float(flows["oil"]))
	# صدمة سعرية من حدث عالمي
	var s3 := new_sim("JOR", 12)
	Market.apply_shock(s3, {"food": 1.5}, 6)
	for i in 4:
		Market.monthly(s3)
	check(Market.price(s3, "food") > 1.3, "صدمة الجفاف ترفع الغذاء (%.2f)" % Market.price(s3, "food"))


func test_trade_pacts() -> void:
	print("الاتفاقيات التجارية")
	var s := new_sim("IRQ", 13)
	check(Market.has_pact(s, "FRA", "DEU"), "اتفاقيات البداية قائمة (الاتحاد الأوروبي)")
	var g0 := Economy.growth_rate(s, s.country("IRQ"))
	var imp0 := Logistics.import_capacity(s, s.country("IRQ"))
	check(Market.sign_pact(s, "IRQ", "JOR") == "", "توقيع اتفاقية مع الأردن")
	check(Economy.growth_rate(s, s.country("IRQ")) > g0, "الاتفاقية ترفع النمو")
	check(Logistics.import_capacity(s, s.country("IRQ")) > imp0, "الاتفاقية ترفع قدرة الاستيراد")
	check(Market.sign_pact(s, "IRQ", "IRN") == "" or s.relation("IRQ", "IRN") >= 25.0, "الشروط تُحترم")
	check(Market.sign_pact(s, "IRQ", "ISR") != "", "لا اتفاقية مع دولة معادية")
	s.declare_war("IRQ", "JOR")
	check(not Market.has_pact(s, "IRQ", "JOR"), "الحرب تلغي الاتفاقية")


func test_straits() -> void:
	print("المضائق")
	var s := new_sim("IRN", 21)
	check(s.db.straits["straits"].size() == 8, "ثمانية ممرات في البيانات")
	check(Straits.export_loss(s, "IRQ") == 0.0, "الممرات مفتوحة في البداية")
	check(Straits.can_close(s, "IRQ", "hormuz") != "", "العراق لا يغلق هرمز")
	check(Straits.can_close(s, "EGY", "mandeb") != "", "باب المندب بلا مسيطر ممثَّل")
	var before := s.checksum()
	var preview: Dictionary = Straits.close_preview(s, "IRN", "hormuz")
	check(s.checksum() == before, "توقع الإغلاق بلا آثار جانبية")
	check(not preview["hurt"].is_empty() and float(preview["hurt"][0]["share"]) >= 0.9, "العراق أكثر المتضررين من هرمز")
	var rel0: float = s.relation("IRN", "IRQ")
	var imp0 := Logistics.import_capacity(s, s.country("IRQ"))
	var sea_open: float = Divisions.theater(s, "USA", ["USA"], ["IRN"])["sea"]
	check(s.close_strait("IRN", "hormuz") == "", "إيران تغلق هرمز")
	check(Straits.state_of(s, "hormuz") == 2, "هرمز مغلق")
	check(Straits.export_loss(s, "IRN") == 0.0, "المسيطر الذي أغلق الممر لا تُقطع تجارته")
	check(Straits.export_loss(s, "IRQ") >= 0.9, "تجارة العراق عبر هرمز تُقطع (%.2f)" % Straits.export_loss(s, "IRQ"))
	check(Logistics.import_capacity(s, s.country("IRQ")) < imp0 * 0.75, "استيراد العراق يضعف")
	check(s.relation("IRN", "IRQ") < rel0 - 10.0, "علاقة العراق بإيران تنخفض")
	check(float(s.state["global"]["tension"]) >= 10.0, "التوتر العالمي يرتفع")
	var sea_shut: float = Divisions.theater(s, "USA", ["USA"], ["IRN"])["sea"]
	var sea_owner: float = Divisions.theater(s, "IRN", ["IRN"], ["USA"])["sea"]
	check(sea_open > 0.99 and sea_shut < 0.5, "أسطول أمريكا نحو إيران يُقصَّر (%.2f ← %.2f)" % [sea_open, sea_shut])
	check(sea_owner > 0.99, "أسطول المسيطر لا يتأثر بممره")
	check(Combat.forecast(s, "USA", "IRN")["theater"]["USA"]["sea"] < 0.5, "التوقع يُظهر قصر الوصول البحري")
	for i in 6:
		Market.monthly(s)
	check(Market.price(s, "oil") > 1.1, "إغلاق هرمز يرفع سعر النفط (%.2f)" % Market.price(s, "oil"))
	check(s.open_strait("IRN", "hormuz") == "", "إيران تعيد فتح هرمز")
	check(Straits.export_loss(s, "IRQ") == 0.0, "الفتح يعيد التجارة")
	check(s.open_strait("USA", "hormuz") != "", "من لم يغلق الممر لا يفتحه")
	# إغلاق الذكاء الاصطناعي أثناء الحرب يبقى حتمياً
	var a := new_sim("IRQ", 21)
	var b := new_sim("IRQ", 21)
	a.declare_war("IRN", "IRQ")
	b.declare_war("IRN", "IRQ")
	for i in 8:
		Straits.monthly(a)
		Straits.monthly(b)
	check(a.checksum() == b.checksum(), "قرار الممر عند الذكاء الاصطناعي حتمي")


func _target(s: Simulation, c: Dictionary, f: String) -> float:
	return float(Factions.compute_targets(s, c)[f]["target"])


func test_factions() -> void:
	print("الفئات الداخلية")
	var s := new_sim("IRQ", 15)
	var c := s.player()
	var ok := true
	for f in ["military", "business", "street", "clergy"]:
		var v := float(c["factions"][f]["sat"])
		if v < 0.0 or v > 100.0:
			ok = false
	check(ok and c["factions"].size() == 4, "أربع فئات برضا بين 0 و100")
	var street0 := _target(s, c, "street")
	var mil0 := _target(s, c, "military")
	s.toggle_policy("IRQ", "subsidies")
	check(_target(s, c, "street") > street0 + 8.0, "دعم السلع يرضي الشارع")
	s.toggle_policy("IRQ", "subsidies")
	s.toggle_policy("IRQ", "conscription")
	check(_target(s, c, "military") > mil0 and _target(s, c, "street") < street0, "التجنيد الإجباري يرضي الجيش ويغضب الشارع")
	s.toggle_policy("IRQ", "conscription")
	var bus0 := _target(s, c, "business")
	s.set_tax("IRQ", float(c["tax_rate"]) + 0.08)
	check(_target(s, c, "business") < bus0 - 10.0, "رفع الضرائب يغضب رجال الأعمال")
	s.set_tax("IRQ", float(c["tax_rate"]) - 0.08)
	# تغيير نظام الحكم يحتاج دعم الفئات
	var sup_mil: float = Factions.support(s, c, "military")["total"]
	var sup_pres: float = Factions.support(s, c, "presidential")["total"]
	check(sup_mil < 0.5 and s.can_change_government("IRQ", "military") != "", "الفئات ترفض حكماً عسكرياً في العراق (%d%%)" % int(sup_mil * 100.0))
	check(sup_pres > sup_mil, "النظام الرئاسي يحظى بدعم أكبر (%d%%)" % int(sup_pres * 100.0))
	# الاسترضاء
	c["treasury"] = 50.0
	var before := float(c["factions"]["military"]["sat"])
	check(Factions.appease(s, c, "military") == "", "استرضاء الجيش")
	check(float(c["factions"]["military"]["sat"]) > before + 10.0 and float(c["treasury"]) < 50.0, "الاسترضاء يرفع الرضا ويكلف المال")
	check(Factions.can_appease(s, c, "military") != "", "لا استرضاء متكرر قبل ثلاثة أشهر")
	# انقلاب عسكري في دولة يديرها الذكاء الاصطناعي
	var syr := s.country("SYR")
	var couped := false
	for m in 24:
		syr["factions"]["military"]["sat"] = 5.0
		Factions._check_coup(s, syr)
		if syr["government"] == "military":
			couped = true
			break
	check(couped, "الجيش الغاضب ينقلب في سوريا")
	check(Factions._immune(s, syr), "فترة هدوء بعد الانقلاب")
	# انقلاب على اللاعب = نهاية اللعبة
	for m in 24:
		c["factions"]["military"]["sat"] = 5.0
		Factions._check_coup(s, c)
		s.pending.clear()
		if s.state["game_over"] != "":
			break
	check(s.state["game_over"] == "coup", "الانقلاب على اللاعب ينهي اللعبة")


func test_intel() -> void:
	print("الاستخبارات وضباب الحرب")
	var s := new_sim("IRQ", 17)
	check(Intel.visibility(s, "IRQ", "IRQ") == 100.0, "الدولة ترى نفسها كاملة")
	check(Intel.visibility(s, "IRQ", "SYR") == 30.0, "الجار يُرى جزئياً (30)")
	check(Intel.visibility(s, "IRQ", "JPN") == 15.0, "الدولة البعيدة شبه مجهولة (15)")
	check(Intel.visibility(s, "FRA", "DEU") >= 80.0, "الحليف مكشوف (الناتو)")
	# التقدير: نطاق يحوي القيمة غالباً، ودقيق مع شبكة قوية، وثابت خلال الشهر
	var real: float = s.military_power(s.country("JPN"))
	var e1 := Intel.estimate(s, "IRQ", "JPN", real, "power")
	var e2 := Intel.estimate(s, "IRQ", "JPN", real, "power")
	check(not e1["exact"] and float(e1["value"]) == float(e2["value"]), "التقدير غير دقيق وثابت خلال الشهر")
	check(float(e1["hi"]) > float(e1["lo"]), "التقدير له نطاق خطأ")
	# بناء شبكة
	var p := s.player()
	p["treasury"] = 100.0
	check(Intel.build(s, "IRQ", "JPN") == "", "بناء شبكة تجسس في اليابان")
	check(Intel.network(s, "IRQ", "JPN") > 5.0 and float(p["treasury"]) < 100.0, "الشبكة تكبر وتكلف المال")
	check(Intel.can_build(s, "IRQ", "JPN") != "", "التوسيع مرة في الشهر")
	p["intel"]["JPN"] = 70.0
	var e3 := Intel.estimate(s, "IRQ", "JPN", real, "power")
	check(e3["exact"], "شبكة 70 تكشف الأرقام الحقيقية")
	# العمليات تحتاج شبكة كافية
	check(Intel.can_run(s, "IRQ", "SYR", "sabotage") != "", "لا تخريب بلا شبكة")
	p["intel"]["SYR"] = 100.0
	s.country("SYR")["counter_intel"] = 0
	var done := {"sabotage": false, "opposition": false, "cyber": false}
	for i in 30:
		for op in done:
			if done[op]:
				continue
			p["treasury"] = 100.0
			p["intel"]["SYR"] = 100.0
			var street0 := float(s.country("SYR")["factions"]["street"]["sat"])
			var gdp0 := float(s.country("SYR")["gdp"])
			var broken0 := 0
			for t in s.country("SYR")["facilities"]:
				broken0 += int(s.country("SYR")["facilities"][t]["total"]) - int(s.country("SYR")["facilities"][t]["working"])
			var r: Dictionary = Intel.run(s, "IRQ", "SYR", op)
			if r["success"]:
				var broken1 := 0
				for t in s.country("SYR")["facilities"]:
					broken1 += int(s.country("SYR")["facilities"][t]["total"]) - int(s.country("SYR")["facilities"][t]["working"])
				match op:
					"sabotage": done[op] = broken1 > broken0
					"opposition": done[op] = float(s.country("SYR")["factions"]["street"]["sat"]) < street0
					"cyber": done[op] = float(s.country("SYR")["gdp"]) < gdp0
	check(done["sabotage"], "التخريب يعطل منشأة")
	check(done["opposition"], "دعم المعارضة يغضب الشارع")
	check(done["cyber"], "الهجوم السيبراني يضرب الاقتصاد")
	# سرقة التقنية من دولة أحدث
	p["intel"]["ISR"] = 100.0
	var stole := false
	for i in 30:
		p["treasury"] = 100.0
		p["intel"]["ISR"] = 100.0
		var prog0 := float(p["research_progress"])
		var r2: Dictionary = Intel.run(s, "IRQ", "ISR", "steal_tech")
		if r2["success"] and float(p["research_progress"]) > prog0:
			stole = true
			break
	check(stole, "سرقة تقنية من إسرائيل تقدم البحث")
	# الكشف يضر العلاقات
	var exposed := false
	for i in 40:
		p["treasury"] = 100.0
		p["intel"]["JPN"] = 100.0
		var rel0: float = s.relation("IRQ", "JPN")
		var r3: Dictionary = Intel.run(s, "IRQ", "JPN", "cyber")
		if r3["exposed"]:
			exposed = s.relation("IRQ", "JPN") < rel0
			break
	check(exposed, "انكشاف العملية يخفض العلاقات")
	# مكافحة التجسس تكلف وتخفض فرص الأعداء
	var ch0 := Intel.op_chance(s, "SYR", "IRQ", "cyber")
	Intel.set_counter(s, "IRQ", 3)
	check(Intel.op_chance(s, "SYR", "IRQ", "cyber") < ch0, "مكافحة التجسس المشددة تخفض فرص العدو")


func test_divisions() -> void:
	print("الفرق العسكرية والمدى")
	var s := new_sim("IRQ", 19)
	var ok := true
	for c in db.countries:
		var divs := Divisions.of(s, c["id"])
		if divs.size() < 2:
			ok = false
		for d in divs:
			if Territory.region(s, d["region"])["owner"] != c["id"]:
				ok = false
	check(ok, "لكل دولة فرقتان على الأقل في أرضها")
	var my := Divisions.of(s, "IRQ")
	var d0: Dictionary = my[0]
	var basra := _region_by_name("IRQ", "Al-Basrah")
	var dohuk := _region_by_name("IRQ", "Dihok")
	s.player()["auto_deploy"] = false
	d0["region"] = dohuk
	check(Divisions.move(s, int(d0["id"]), basra) == "", "تحريك فرقة من دهوك إلى البصرة")
	var days := int(d0["eta"]) - int(s.state["day"])
	check(days >= 8, "الحركة تأخذ أياماً حسب المسافة (%d يوماً)" % days)
	run_days(s, days + 1)
	check(d0["region"] == basra, "الفرقة وصلت البصرة")
	check(Divisions.move(s, int(d0["id"]), db.capitals["IRN"]) != "", "لا تحرك إلى أرض العدو بلا معركة")
	# الانتشار على الجبهة يرفع القوة البرية
	s.declare_war("IRQ", "SYR")
	for d in my:
		d["region"] = db.capitals["IRQ"]
		d["eta"] = -1
	var reserve: float = Divisions.theater(s, "IRQ", ["IRQ"], ["SYR"])["land"]
	var front: Array = Divisions.front_regions(s, ["IRQ"], ["SYR"])
	check(not front.is_empty(), "للعراق جبهة مع سوريا (%d مناطق)" % front.size())
	for d in my:
		d["region"] = front[0]
	var deployed: float = Divisions.theater(s, "IRQ", ["IRQ"], ["SYR"])["land"]
	check(deployed > reserve * 4.0, "الفرق على الجبهة أقوى كثيراً من الاحتياط (%.2f مقابل %.2f)" % [deployed, reserve])
	# المدى: القواعد البعيدة لا تصل
	var near: Dictionary = Divisions.theater(s, "IRQ", ["IRQ"], ["SYR"])
	check(float(near["air"]) > 0.5, "الطيران العراقي يصل جبهة سوريا")
	var far_th: Dictionary = Divisions.theater(s, "SYR", ["SYR"], ["JPN"])
	check(float(far_th["missiles"]) < 0.5, "صواريخ سوريا لا تصل اليابان")
	# سقوط منطقة: الفرقة المدافعة تنسحب
	var syr_div: Dictionary = Divisions.of(s, "SYR")[0]
	var spot: String = syr_div["region"]
	Territory.capture(s, spot, "IRQ")
	check(syr_div["region"] != spot and Territory.region(s, syr_div["region"])["owner"] == "SYR", "الفرقة السورية تنسحب من المنطقة الساقطة")
	# التوزيع التلقائي في الحرب
	var s2 := new_sim("JOR", 19)
	s2.declare_war("TUR", "SYR")
	run_days(s2, 35)
	var tur_front: Array = Divisions.front_regions(s2, ["TUR"], ["SYR"])
	var at_front := 0
	for d in Divisions.of(s2, "TUR"):
		if d["region"] in tur_front:
			at_front += 1
	check(at_front >= 3, "الذكاء الاصطناعي ينشر فرقه على الجبهة (%d)" % at_front)
