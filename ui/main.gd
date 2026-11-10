## الشاشة الرئيسية: خريطة القيادة مع الشريط العلوي واللوحة الجانبية والمستشار.
## على الكمبيوتر: لوحة جانبية ثابتة. على الموبايل: لوحة سفلية فوق الخريطة.
extends Control

const UI := preload("res://ui/ui_kit.gd")
const MapView := preload("res://world/map_view.gd")
const Economy := preload("res://sim/economy.gd")
const Combat := preload("res://sim/combat.gd")
const Simulation := preload("res://sim/simulation.gd")
const Territory := preload("res://sim/territory.gd")
const Logistics := preload("res://sim/logistics.gd")
const Market := preload("res://sim/market.gd")
const Sparkline := preload("res://ui/sparkline.gd")
const Factions := preload("res://sim/factions.gd")
const Intel := preload("res://sim/intel.gd")
const Divisions := preload("res://sim/divisions.gd")

enum Tab { STATE, ECONOMY, ARMY, RESEARCH, DIPLOMACY, INTEL, NEWS }
const TAB_TITLES := ["الدولة", "الاقتصاد", "الجيش", "البحث", "الدبلوماسية", "الاستخبارات", "الأخبار"]
const BRANCH_EXAMPLE := {"land": "armor", "air": "fighters", "sea": "ships", "missile": "missiles", "air_defense": "air_defense"}
const NEWS_COLORS := {"war": "#e05a55", "nuke": "#ff7b29", "peace": "#4cc38a", "good": "#4cc38a", "world": "#7fb8e6", "info": "#c9d4dc"}

var mobile := false
var map: MapView
var tabs: TabContainer
var tab_boxes: Array = []        # VBox لكل تبويب
var selected: String = ""
var selected_region: String = ""
var move_division: int = -1        # فرقة تنتظر اختيار وجهتها على الخريطة
var _keep_tab := false

# الشريط العلوي
var lbl_country: Label
var lbl_date: Label
var lbl_money: Label
var lbl_stab: Label
var btn_pause: Button
var speed_btns: Array = []

# المستشار
var advisor_box: VBoxContainer

# الاقتصاد (تُبنى مرة واحدة حتى لا تضيع حركة المنزلقات)
var eco_controls: VBoxContainer
var eco_info: VBoxContainer
var tax_slider: HSlider
var tax_label: Label
var tax_preview: Label
var res_slider: HSlider
var res_label: Label

# الجيش
var army_controls: VBoxContainer
var army_info: VBoxContainer
var buy_type: OptionButton
var buy_count: SpinBox
var buy_cost: Label
var buy_types: Array = []

# النوافذ المنبثقة
var overlay: Control
var dialog_queue: Array = []
var dialog_open := false
var start_screen: Control

var _refresh_acc := 0.0
var _dirty := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mobile = OS.has_feature("mobile") or get_viewport_rect().size.x < 900.0
	theme = UI.make_theme(mobile)
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	_build_layout()
	_build_start_screen()
	Game.day_passed.connect(_on_day)
	Game.month_passed.connect(func(): _dirty = true)
	Game.events_ready.connect(_on_events)
	Game.paused_changed.connect(func(_p): _update_top())
	Game.speed_changed.connect(func(_s): _update_top())
	Game.game_started.connect(_on_game_started)


# ================================================================== البناء

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("070b10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_top_bar())

	var body: BoxContainer = VBoxContainer.new() if mobile else HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	var side := _build_side_panel()
	var map_area := _build_map_area()
	if mobile:
		body.add_child(map_area)
		side.custom_minimum_size = Vector2(0, get_viewport_rect().size.y * 0.45)
		body.add_child(side)
	else:
		# في الاتجاه من اليمين لليسار يظهر العنصر الأول على اليمين
		side.custom_minimum_size = Vector2(450, 0)
		body.add_child(side)
		body.add_child(map_area)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)


func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	var h := UI.row()
	panel.add_child(h)
	lbl_country = UI.title("—", 20)
	h.add_child(lbl_country)
	lbl_date = UI.label("", UI.C_TEXT)
	lbl_date.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(lbl_date)
	lbl_money = UI.label("", UI.C_GOOD)
	lbl_money.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(lbl_money)
	lbl_stab = UI.label("", UI.C_TEXT)
	lbl_stab.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(lbl_stab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	btn_pause = UI.button("▶", func(): Game.toggle_pause())
	btn_pause.tooltip_text = "إيقاف / تشغيل (مسافة)"
	btn_pause.custom_minimum_size = Vector2(48, 0)
	h.add_child(btn_pause)
	for i in Game.SPEEDS.size():
		var b := UI.button(str(i + 1), func(): _set_speed(i))
		b.toggle_mode = true
		b.tooltip_text = "السرعة %d" % (i + 1)
		speed_btns.append(b)
		h.add_child(b)
	h.add_child(UI.button("+يوم", _step_one_day))
	h.add_child(UI.button("حفظ", _on_save))
	h.add_child(UI.button("القائمة", _show_menu))
	return panel


func _build_side_panel() -> Control:
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in TAB_TITLES.size():
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var v := UI.col()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(v)
		tabs.add_child(scroll)
		tabs.set_tab_title(i, TAB_TITLES[i])
		tab_boxes.append(v)
	tabs.tab_changed.connect(func(_t): _dirty = true)

	# الاقتصاد: عناصر تحكم ثابتة + معلومات تتحدث
	eco_controls = UI.col()
	eco_info = UI.col()
	tab_boxes[Tab.ECONOMY].add_child(eco_controls)
	tab_boxes[Tab.ECONOMY].add_child(UI.sep())
	tab_boxes[Tab.ECONOMY].add_child(eco_info)
	_build_economy_controls()

	army_controls = UI.col()
	army_info = UI.col()
	tab_boxes[Tab.ARMY].add_child(army_info)
	tab_boxes[Tab.ARMY].add_child(UI.sep())
	tab_boxes[Tab.ARMY].add_child(army_controls)
	_build_army_controls()
	return tabs


func _build_map_area() -> Control:
	var area := Control.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map = MapView.new()
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	map.layout_direction = Control.LAYOUT_DIRECTION_LTR
	map.country_selected.connect(_on_country_selected)
	map.region_selected.connect(_on_region_clicked)
	area.add_child(map)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	area.add_child(margin)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)

	# المستشار
	var adv_panel := PanelContainer.new()
	adv_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	adv_panel.custom_minimum_size = Vector2(320 if not mobile else 260, 0)
	advisor_box = UI.col()
	adv_panel.add_child(advisor_box)
	v.add_child(adv_panel)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)

	# طبقات الخريطة
	var layers := UI.row()
	layers.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var names := ["سياسي", "القوة العسكرية", "الاقتصاد", "الاستقرار", "الموارد", "المدى"]
	var group := ButtonGroup.new()
	for i in names.size():
		var b := UI.button(names[i], func(): map.set_layer(i))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		layers.add_child(b)
	v.add_child(layers)
	return area


func _build_economy_controls() -> void:
	eco_controls.add_child(UI.title("الضرائب والبحث", 18))
	tax_label = UI.label("")
	eco_controls.add_child(tax_label)
	tax_slider = HSlider.new()
	tax_slider.min_value = 5
	tax_slider.max_value = 60
	tax_slider.step = 1
	tax_slider.value_changed.connect(func(_v): _update_tax_preview())
	eco_controls.add_child(tax_slider)
	res_label = UI.label("")
	eco_controls.add_child(res_label)
	res_slider = HSlider.new()
	res_slider.min_value = 0
	res_slider.max_value = 5
	res_slider.step = 0.25
	res_slider.value_changed.connect(func(_v): _update_tax_preview())
	eco_controls.add_child(res_slider)
	tax_preview = UI.label("", UI.C_MUTED)
	eco_controls.add_child(tax_preview)
	eco_controls.add_child(UI.button("تطبيق الضرائب والبحث", _apply_tax))


func _build_army_controls() -> void:
	army_controls.add_child(UI.title("التصنيع والشراء", 18))
	buy_type = OptionButton.new()
	buy_type.item_selected.connect(func(_i): _update_buy_cost())
	army_controls.add_child(buy_type)
	buy_count = SpinBox.new()
	buy_count.min_value = 1
	buy_count.max_value = 10000
	buy_count.value = 10
	buy_count.value_changed.connect(func(_v): _update_buy_cost())
	army_controls.add_child(UI.row([UI.label("العدد:"), buy_count]))
	buy_cost = UI.label("", UI.C_MUTED)
	army_controls.add_child(buy_cost)
	army_controls.add_child(UI.button("طلب التصنيع", _on_buy))


func _build_start_screen() -> void:
	start_screen = ColorRect.new()
	(start_screen as ColorRect).color = Color(0.02, 0.03, 0.05, 0.97)
	start_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(start_screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_screen.add_child(center)
	var v := UI.col()
	v.custom_minimum_size = Vector2(minf(900.0, get_viewport_rect().size.x - 32.0), 0)
	center.add_child(v)
	var t := UI.title("الحرب العالمية الثالثة", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UI.label("تشرين الأول 2026. العالم على حافة الحرب. اختر الدولة التي ستقودها.", UI.C_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UI.sep())

	var diff := OptionButton.new()
	diff.add_item("سهل")
	diff.add_item("عادي")
	diff.add_item("صعب")
	diff.select(1)
	var top := UI.row([UI.label("الصعوبة:"), diff])
	if Game.has_save() or Game.has_save(Game.AUTOSAVE_PATH):
		top.add_child(UI.button("متابعة آخر لعبة", func():
			if not Game.load_game():
				Game.load_game(Game.AUTOSAVE_PATH)))
	v.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(520.0, get_viewport_rect().size.y - 260.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2 if mobile else 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var list: Array = Game.db.countries.duplicate()
	list.sort_custom(func(a, b): return float(a["gdp"]) > float(b["gdp"]))
	for c in list:
		var b := Button.new()
		b.text = "%s\n%s" % [c["name_ar"], UI.money(float(c["gdp"]))]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cid: String = c["id"]
		b.pressed.connect(func(): Game.start_new(cid, diff.selected))
		grid.add_child(b)
	var note := UI.label("الأرقام تقديرات خاصة باللعبة من مصادر مفتوحة. سيناريو خيالي، والحدود حسب السيطرة الفعلية.", UI.C_MUTED, 13)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)


# ================================================================== الأحداث العامة

func _on_game_started() -> void:
	start_screen.visible = false
	map.sim = Game.sim
	selected = Game.sim.state["player"]
	map.selected = selected
	map.focus_country(selected)
	_rebuild_buy_types()
	_sync_economy_controls()
	_dirty = true
	_refresh()
	if int(Game.sim.state["day"]) == 0:
		var p: Dictionary = Game.sim.player()
		_show_dialog("مرحباً بك في غرفة العمليات",
			"أنت تقود %s.\n\n• الوقت متوقف الآن. اضغط ▶ أو المسافة للتشغيل، والأرقام 1 إلى 5 للسرعة.\n• المستشار في أعلى الخريطة يعرض أهم ما يحتاج انتباهك.\n• اضغط على أي دولة في الخريطة لترى علاقاتك بها وخياراتك.\n• كل قرار يُعرض أثره المتوقع قبل تنفيذه." % p["name_ar"],
			[{"text": "لنبدأ"}])


func _on_day() -> void:
	_update_top()


func _process(delta: float) -> void:
	if not Game.is_running():
		return
	_refresh_acc += delta
	if _dirty and _refresh_acc > 0.25:
		_refresh_acc = 0.0
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not Game.is_running() or start_screen.visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		Game.toggle_pause()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_5:
		_set_speed(int(key.keycode) - int(KEY_1))


func _set_speed(i: int) -> void:
	Game.set_speed(i)
	Game.set_paused(false)


func _step_one_day() -> void:
	if Game.is_running():
		Game.step_day()


func _on_country_selected(id: String) -> void:
	if map.selected_region == "":
		selected_region = ""
	selected = id
	if _keep_tab:
		_keep_tab = false
		return
	tabs.current_tab = Tab.STATE if id == Game.sim.state["player"] else Tab.DIPLOMACY
	_dirty = true


func _on_events(evs: Array) -> void:
	for e in evs:
		var buttons: Array = []
		if e.get("kind", "") == "game_over":
			buttons = [{"text": "العودة للقائمة", "cb": _back_to_menu}]
		elif not e.get("choices", []).is_empty():
			var idx := 0
			for ch in e["choices"]:
				var i := idx
				var ev: Dictionary = e
				var on_choice := func():
					Game.sim.resolve_choice(ev, i)
					_dirty = true
				buttons.append({"text": ch, "cb": on_choice})
				idx += 1
		else:
			buttons = [{"text": "حسناً"}]
		if e.get("kind", "") in ["war", "capital"] and not Game.sim.state["last_battle"].is_empty():
			buttons.append({"text": "تقرير آخر معركة", "cb": _show_battle_report})
		_show_dialog(e["title"], e["text"], buttons)
	_dirty = true


# ================================================================== التحديث

func _refresh() -> void:
	_dirty = false
	if not Game.is_running():
		return
	_update_top()
	_update_advisor()
	match tabs.current_tab:
		Tab.STATE: _fill_state()
		Tab.ECONOMY: _fill_economy()
		Tab.ARMY: _fill_army()
		Tab.RESEARCH: _fill_research()
		Tab.DIPLOMACY: _fill_diplomacy()
		Tab.INTEL: _fill_intel()
		Tab.NEWS: _fill_news()
	map.queue_redraw()


func _update_top() -> void:
	if not Game.is_running():
		return
	var s = Game.sim
	var p: Dictionary = s.player()
	lbl_country.text = p["name_ar"]
	lbl_date.text = s.date_text()
	lbl_money.text = "الخزينة " + UI.money(float(p["treasury"]))
	var st := float(p["stability"])
	lbl_stab.text = "استقرار %d" % int(st)
	lbl_stab.add_theme_color_override("font_color", UI.C_GOOD if st >= 50.0 else (UI.C_ACCENT if st >= 30.0 else UI.C_BAD))
	btn_pause.text = "▶" if Game.paused else "⏸"
	for i in speed_btns.size():
		speed_btns[i].set_pressed_no_signal(i == Game.speed)


## المستشار: أهم 3 مشكلات أو فرص الآن، والضغط ينقلك للمكان الصحيح
func _update_advisor() -> void:
	UI.clear(advisor_box)
	advisor_box.add_child(UI.title("المستشار", 16))
	var s = Game.sim
	var pid: String = s.state["player"]
	var p: Dictionary = s.player()
	var b: Dictionary = p.get("last_budget", {})
	var items: Array = []   # [أولوية, نص, تبويب, دولة]
	var gdp := float(p["gdp"])
	for w in s.wars_of(pid):
		var my := float(w["score"]) if pid in w["attackers"] else -float(w["score"])
		var enemy: String = w["defenders"][0] if pid in w["attackers"] else w["attackers"][0]
		if my < -20.0:
			items.append([100, "الحرب مع %s تسير ضدك (%d). فكّر في السلام أو التعزيز." % [s.country(enemy)["name_ar"], int(my)], Tab.DIPLOMACY, enemy])
		else:
			items.append([60, "الحرب مع %s: النتيجة %d." % [s.country(enemy)["name_ar"], int(my)], Tab.DIPLOMACY, enemy])
	if float(p["stability"]) < 35.0:
		items.append([95, "الاستقرار منخفض (%d). خفّض الضرائب أو فعّل دعم السلع." % int(p["stability"]), Tab.STATE, ""])
	if not b.is_empty() and float(b["balance"]) < -gdp * 0.002:
		items.append([80, "عجز شهري %s. الدين يكبر." % UI.money(-float(b["balance"])), Tab.ECONOMY, ""])
	if float(p["inflation"]) > 8.0:
		items.append([75, "التضخم مرتفع (%.1f%%)." % float(p["inflation"]), Tab.ECONOMY, ""])
	var my_power: float = s.bloc_power(pid)
	for n in p["neighbors"]:
		var c: Dictionary = s.country(n)
		if c.is_empty() or not s.war_between(pid, n).is_empty():
			continue
		if s.relation(pid, n) < -50.0 and s.bloc_power(n) > my_power * 1.3:
			items.append([85, "%s معادية وأقوى منك. عزّز دفاعك أو حسّن العلاقات." % c["name_ar"], Tab.DIPLOMACY, n])
	var lg: Dictionary = p.get("logistics", {})
	if Logistics.blockaded(s, p):
		items.append([90, "أنت تحت حصار بحري: الواردات شبه مقطوعة.", Tab.ECONOMY, ""])
	if not lg.is_empty() and float(lg["fuel"]) < 0.85:
		items.append([70, "نقص الوقود يضعف جيشك (%d%%). احمِ المصافي ومناطق النفط." % int(float(lg["fuel"]) * 100.0), Tab.ECONOMY, ""])
	var broken := 0
	for t in p.get("facilities", {}):
		broken += int(p["facilities"][t]["total"]) - int(p["facilities"][t]["working"])
	if broken > 0:
		items.append([65, "%d من منشآتك معطلة بالضربات." % broken, Tab.ARMY, ""])
	if float(p["treasury"]) > gdp * 0.03:
		items.append([40, "في الخزينة فائض %s: استثمر أو صنّع سلاحاً." % UI.money(float(p["treasury"])), Tab.ARMY, ""])
	var gm := float(p["gdp"]) / 12.0
	var tinc := float(p.get("trade_income", 0.0))
	if tinc < -gm * 0.004:
		items.append([72, "أسعار الموارد تكلفك %s شهرياً. ابحث عن موارد أو اتفاقيات." % UI.money(-tinc), Tab.ECONOMY, ""])
	elif tinc > gm * 0.004:
		items.append([35, "ارتفاع أسعار صادراتك يربحك %s شهرياً." % UI.money(tinc), Tab.ECONOMY, ""])
	if float(p.get("trade_lost", 0.0)) > gm * 0.003:
		items.append([78, "الحصار والعقوبات يمنعان صادرات بقيمة %s شهرياً." % UI.money(float(p["trade_lost"])), Tab.ECONOMY, ""])
	if Market.pacts_of(s, pid).size() < 3:
		for oid in s.alive_ids():
			if oid != pid and Market.can_sign_pact(s, pid, oid) == "":
				items.append([30, "يمكنك توقيع اتفاقية تجارية مع %s." % s.country(oid)["name_ar"], Tab.DIPLOMACY, oid])
				break
	for oid in s.alive_ids():
		if oid != pid and s.country(oid).get("rival", "") == pid and Intel.visibility(s, pid, oid) >= 50.0:
			items.append([88, "استخباراتنا: %s تتهيأ ضدك." % s.country(oid)["name_ar"], Tab.INTEL, oid])
	if not s.wars_of(pid).is_empty() and int(p.get("counter_intel", 0)) < 2:
		items.append([62, "أنت في حرب ومكافحة التجسس ضعيفة: العدو قد يخرب منشآتك.", Tab.INTEL, ""])
	if p.has("factions"):
		for f in Factions.ids(s):
			var sat := float(p["factions"][f]["sat"])
			var fname: String = s.db.factions["factions"][f]["name_ar"]
			if f == "military" and sat < 25.0:
				items.append([98, "الجيش غاضب (%d): خطر انقلاب! ارفع ميزانيته أو استرضِه." % int(sat), Tab.STATE, ""])
			elif f == "street" and sat < 20.0:
				items.append([96, "الشارع يغلي (%d): خطر ثورة إن انهار الاستقرار." % int(sat), Tab.STATE, ""])
			elif sat < 30.0:
				items.append([68, "%s غير راضين (%d)." % [fname, int(sat)], Tab.STATE, ""])
	if items.is_empty():
		items.append([0, "الوضع مستقر. راقب جيرانك وطوّر اقتصادك.", Tab.ECONOMY, ""])
	items.sort_custom(func(a, c): return a[0] > c[0])
	for it in items.slice(0, 3):
		var tab_i: int = it[2]
		var target: String = it[3]
		var btn := UI.button("• " + it[1], func():
			tabs.current_tab = tab_i
			if target != "":
				selected = target
				map.selected = target
				map.focus_country(target)
			_dirty = true)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		advisor_box.add_child(btn)


# ------------------------------------------------------------------ تبويب الدولة

func _fill_state() -> void:
	var box: VBoxContainer = tab_boxes[Tab.STATE]
	UI.clear(box)
	var s = Game.sim
	var pid: String = s.state["player"]
	var p: Dictionary = s.player()
	box.add_child(UI.title(p["name_ar"]))
	_region_card(box, pid)
	box.add_child(UI.kv("العاصمة", p["capital_ar"]))
	box.add_child(UI.kv("نظام الحكم", s.db.governments[p["government"]]["name_ar"]))
	box.add_child(UI.kv("السكان", "%s مليون" % s.fmt_num(p["population"])))
	box.add_child(UI.kv("الاستقرار", str(int(p["stability"]))))
	box.add_child(UI.bar(float(p["stability"]), 100.0, UI.C_GOOD if float(p["stability"]) >= 50.0 else UI.C_BAD))
	var b: Dictionary = p.get("last_budget", {})
	if not b.is_empty():
		box.add_child(UI.kv("الاستقرار المتوقع", str(int(b["stability_target"])), UI.C_MUTED))
	var vs: Array = s.vassals(pid)
	if not vs.is_empty():
		box.add_child(UI.kv("الدول التابعة", "، ".join(PackedStringArray(vs.map(func(x): return s.country(x)["name_ar"])))))
	_factions_section(box, p)
	_regions_section(box, pid)
	box.add_child(UI.sep())

	box.add_child(UI.title("نظام الحكم", 18))
	box.add_child(UI.label("التغيير يحتاج دعم %d%% من الفئات (حسب أوزانها)، واستقراراً 40، وألا تكون في حرب." % int(float(s.db.factions["support_needed"]) * 100.0), UI.C_MUTED, 13))
	var gov_opt := OptionButton.new()
	var gov_ids: Array = s.db.governments.keys()
	for i in gov_ids.size():
		var g: Dictionary = s.db.governments[gov_ids[i]]
		var sup: float = Factions.support(s, p, gov_ids[i])["total"]
		var mark := "" if gov_ids[i] == p["government"] else "، دعم %d%%" % int(sup * 100.0)
		gov_opt.add_item("%s (نمو %s، استقرار %s%s)" % [g["name_ar"], UI.signed(float(g["growth"])), UI.signed(float(g["stability"]), 0), mark])
		if gov_ids[i] == p["government"]:
			gov_opt.select(i)
	box.add_child(gov_opt)
	var sup_label := UI.label("", UI.C_MUTED, 14)
	var show_support := func(idx: int) -> void:
		var gid: String = gov_ids[idx]
		if gid == p["government"]:
			sup_label.text = "هذا نظامك الحالي."
			return
		var sp: Dictionary = Factions.support(s, p, gid)
		var parts := PackedStringArray()
		for f in Factions.ids(s):
			parts.append("%s %d%%" % [s.db.factions["factions"][f]["name_ar"], int(float(sp["parts"][f]) * 100.0)])
		sup_label.text = "دعم الفئات: " + "، ".join(parts) + " ← المجموع %d%%" % int(float(sp["total"]) * 100.0)
	gov_opt.item_selected.connect(show_support)
	show_support.call(gov_opt.selected)
	box.add_child(sup_label)
	box.add_child(UI.button("تغيير نظام الحكم (−20 استقرار)", func():
		var gid: String = gov_ids[gov_opt.selected]
		var why: String = s.can_change_government(pid, gid)
		if why != "":
			_toast(why)
		else:
			s.change_government(pid, gid)
		_dirty = true))
	box.add_child(UI.sep())

	box.add_child(UI.title("السياسات", 18))
	var base: Dictionary = Economy.preview(s, p, {})
	for pol in s.db.policies:
		var info: Dictionary = s.db.policies[pol]
		var on: bool = pol in p["policies"]
		var toggled: Array = p["policies"].duplicate()
		if on:
			toggled.erase(pol)
		else:
			toggled.append(pol)
		var pv: Dictionary = Economy.preview(s, p, {"policies": toggled})
		var cb := CheckButton.new()
		cb.text = info["name_ar"]
		cb.button_pressed = on
		var pol_id: String = pol
		cb.toggled.connect(func(_v):
			s.toggle_policy(pid, pol_id)
			_dirty = true)
		box.add_child(cb)
		box.add_child(UI.label(info["desc_ar"], UI.C_MUTED, 14))
		var d_bal := float(pv["balance"]) - float(base["balance"])
		var d_stab := float(pv["stability_target"]) - float(base["stability_target"])
		var d_gr := float(pv["growth"]) - float(base["growth"])
		var verb := "إلغاؤها" if on else "تفعيلها"
		var fx: Dictionary = Factions.policy_preview(s, p, pol)
		if not fx.is_empty():
			var fparts := PackedStringArray()
			for f in fx:
				fparts.append("%s %s" % [s.db.factions["factions"][f]["name_ar"], UI.signed(float(fx[f]), 0)])
			box.add_child(UI.label("الفئات: " + "، ".join(fparts), UI.C_ACCENT, 14))
		box.add_child(UI.label("أثر %s: الميزانية %s شهرياً، النمو %s%%، الاستقرار %s" % [verb, UI.money(d_bal), UI.signed(d_gr, 2), UI.signed(d_stab, 0)], UI.C_ACCENT, 14))


# ------------------------------------------------------------------ تبويب الاقتصاد

func _sync_economy_controls() -> void:
	var p: Dictionary = Game.sim.player()
	tax_slider.set_value_no_signal(roundf(float(p["tax_rate"]) * 100.0))
	res_slider.set_value_no_signal(float(p["research_ratio"]) * 100.0)
	_update_tax_preview()


func _update_tax_preview() -> void:
	if not Game.is_running():
		return
	var s = Game.sim
	var p: Dictionary = s.player()
	tax_label.text = "الضرائب: %d%% من الناتج" % int(tax_slider.value)
	res_label.text = "البحث والتطوير: %.2f%% من الناتج" % res_slider.value
	var now: Dictionary = Economy.preview(s, p, {})
	var pv: Dictionary = Economy.preview(s, p, {"tax_rate": tax_slider.value / 100.0, "research_ratio": res_slider.value / 100.0})
	tax_preview.text = "التوقع للشهر القادم:\nالرصيد %s (الآن %s)\nالنمو السنوي %s%% (الآن %s%%)\nالاستقرار يتجه إلى %d (الآن %d)" % [
		UI.money(float(pv["balance"])), UI.money(float(now["balance"])),
		UI.signed(float(pv["growth"]), 2), UI.signed(float(now["growth"]), 2),
		int(pv["stability_target"]), int(now["stability_target"])]


func _apply_tax() -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	s.set_tax(pid, tax_slider.value / 100.0)
	s.set_research(pid, res_slider.value / 100.0, s.player()["research_focus"])
	_toast("تم تطبيق الضرائب والبحث.")
	_dirty = true


func _fill_economy() -> void:
	_update_tax_preview()
	UI.clear(eco_info)
	var s = Game.sim
	var p: Dictionary = s.player()
	eco_info.add_child(UI.title("الاقتصاد", 18))
	eco_info.add_child(UI.kv("الناتج المحلي", UI.money(float(p["gdp"]))))
	eco_info.add_child(UI.kv("نصيب الفرد", "%s $" % s.fmt_num(Economy.gdp_per_capita(p))))
	eco_info.add_child(UI.kv("النمو السنوي", "%s%%" % UI.signed(Economy.growth_rate(s, p), 2)))
	eco_info.add_child(UI.kv("الخزينة", UI.money(float(p["treasury"]))))
	eco_info.add_child(UI.kv("الدين", "%s (%d%% من الناتج)" % [UI.money(float(p["debt"])), int(100.0 * float(p["debt"]) / float(p["gdp"]))]))
	eco_info.add_child(UI.kv("التضخم", "%.1f%%" % float(p["inflation"]), UI.C_BAD if float(p["inflation"]) > 8.0 else UI.C_TEXT))
	var b: Dictionary = p.get("last_budget", {})
	if not b.is_empty():
		eco_info.add_child(UI.sep())
		eco_info.add_child(UI.title("ميزانية الشهر الماضي", 18))
		eco_info.add_child(UI.kv("الإيرادات", UI.money(float(b["revenue"])), UI.C_GOOD))
		var tr := float(b.get("trade", 0.0))
		if absf(tr) >= 0.001:
			eco_info.add_child(UI.kv("أثر أسعار الموارد والتجارة", ("+" if tr > 0.0 else "−") + UI.money(absf(tr)), UI.C_GOOD if tr > 0.0 else UI.C_BAD))
		for row in [["الرواتب والخدمات", "civil"], ["صيانة الجيش", "military"], ["الدعم", "subsidies"], ["البحث", "research"], ["فوائد الدين", "interest"], ["مكافحة التجسس", "intel"], ["جزية للمتبوع", "tribute"]]:
			if float(b.get(row[1], 0.0)) > 0.0:
				eco_info.add_child(UI.kv(row[0], "−" + UI.money(float(b[row[1]])), UI.C_BAD))
		var bal := float(b["balance"])
		eco_info.add_child(UI.kv("الرصيد", UI.money(bal), UI.C_GOOD if bal >= 0.0 else UI.C_BAD))
	_market_section(eco_info, p)
	eco_info.add_child(UI.sep())
	eco_info.add_child(UI.title("الموارد (من مناطقك)", 18))
	eco_info.add_child(UI.label("كل مورد يأتي من مناطق محددة: خسارة منطقة نفطية تُفقدك نفطها، واحتلال منطقة يمنحك مواردها تدريجياً.", UI.C_MUTED, 13))
	for r in Territory.RESOURCE_NAMES:
		var v := float(p["resources"].get(r, 0.0))
		var base := float(_core_resource(p["id"], r))
		var txt := str(int(roundf(v)))
		if absf(v - base) >= 1.0:
			txt += " (الأصل %d)" % int(roundf(base))
		eco_info.add_child(UI.kv(Territory.RESOURCE_NAMES[r], txt, UI.C_TEXT if v + 0.5 >= base else UI.C_BAD))
		eco_info.add_child(UI.bar(v, 100.0, UI.C_LINE))
	_logistics_section(eco_info, p)


# ------------------------------------------------------------------ تبويب الجيش

func _rebuild_buy_types() -> void:
	buy_type.clear()
	buy_types.clear()
	for u in Game.db.units:
		if u == "nukes":
			continue
		buy_types.append(u)
		buy_type.add_item(Game.db.units[u]["name_ar"])
	_update_buy_cost()


func _update_buy_cost() -> void:
	if not Game.is_running() or buy_types.is_empty():
		return
	var s = Game.sim
	var p: Dictionary = s.player()
	var u: String = buy_types[buy_type.selected]
	var info: Dictionary = s.db.units[u]
	var gen := int(p["tech"][info["branch"]])
	var cost: float = s.unit_cost(p, u) * buy_count.value
	var days := int(info["build_days"])
	buy_cost.text = "الجيل %d (%s)\nالكلفة %s، المدة %d يوماً\nفي الخزينة %s" % [gen, info["gens"][gen - 1], UI.money(cost), days, UI.money(float(p["treasury"]))]
	buy_cost.add_theme_color_override("font_color", UI.C_TEXT if cost <= float(p["treasury"]) else UI.C_BAD)


func _on_buy() -> void:
	var s = Game.sim
	var u: String = buy_types[buy_type.selected]
	var err: String = s.order_units(s.state["player"], u, buy_count.value)
	_toast(err if err != "" else "تم طلب التصنيع.")
	_dirty = true


func _fill_army() -> void:
	_update_buy_cost()
	UI.clear(army_info)
	var s = Game.sim
	var p: Dictionary = s.player()
	army_info.add_child(UI.title("القوات المسلحة", 18))
	army_info.add_child(UI.kv("القوة الكلية", s.fmt_num(s.military_power(p)), UI.C_ACCENT))
	_divisions_section(army_info, p)
	var fac: Dictionary = p.get("facilities", {})
	for t in Territory.FACILITY_TYPES:
		var f: Dictionary = fac.get(t, {"total": 0, "working": 0})
		if int(f["total"]) > 0:
			var bad := int(f["working"]) < int(f["total"])
			army_info.add_child(UI.kv(Territory.FACILITY_NAMES[t], "%d عاملة من %d" % [int(f["working"]), int(f["total"])], UI.C_BAD if bad else UI.C_TEXT))
	army_info.add_child(UI.kv("الصيانة السنوية", UI.money(Economy.military_upkeep(s, p))))
	for u in s.db.units:
		var info: Dictionary = s.db.units[u]
		var gen := int(p["tech"][info["branch"]])
		var n := float(p["military"][u])
		var line := UI.kv("%s" % info["name_ar"], "%s  ·  %s" % [s.fmt_num(n), info["gens"][gen - 1]])
		army_info.add_child(line)
	var q: Array = p["production"]
	if not q.is_empty():
		army_info.add_child(UI.sep())
		army_info.add_child(UI.title("خطوط الإنتاج", 16))
		for o in q:
			army_info.add_child(UI.kv("%s × %s" % [s.db.units[o["type"]]["name_ar"], s.fmt_num(o["count"])], "%d يوماً" % int(ceilf(float(o["days_left"]))), UI.C_MUTED))


# ------------------------------------------------------------------ تبويب البحث

func _fill_research() -> void:
	var box: VBoxContainer = tab_boxes[Tab.RESEARCH]
	UI.clear(box)
	var s = Game.sim
	var pid: String = s.state["player"]
	var p: Dictionary = s.player()
	box.add_child(UI.title("أجيال الأسلحة", 18))
	box.add_child(UI.label("خمسة أجيال لكل فرع. الجيل الخامس يحتاج اقتصاداً بحجم 500 مليار على الأقل. نسبة الإنفاق على البحث تُضبط من تبويب الاقتصاد.", UI.C_MUTED, 14))
	var research_month := float(p["gdp"]) * float(p["research_ratio"]) / 12.0
	for br in s.db.branches:
		box.add_child(UI.sep())
		var gen := int(p["tech"][br])
		var ex: Dictionary = s.db.units[BRANCH_EXAMPLE[br]]
		var focus: bool = p["research_focus"] == br
		box.add_child(UI.kv(s.db.branches[br], "الجيل %d · %s" % [gen, ex["gens"][gen - 1]], UI.C_ACCENT if focus else UI.C_TEXT))
		if gen < 5:
			var need := Economy.research_cost(gen + 1)
			var prog := float(p["research_progress"]) if focus else 0.0
			box.add_child(UI.bar(prog, need))
			if focus:
				var months := ceili((need - prog) / maxf(0.001, research_month))
				box.add_child(UI.label("قيد البحث: الجيل %d (%s) خلال %d شهراً تقريباً" % [gen + 1, ex["gens"][gen], months], UI.C_ACCENT, 14))
			else:
				var branch := String(br)
				box.add_child(UI.button("ركّز البحث هنا (التقدم الحالي يقل للنصف)", func():
					s.set_research(pid, float(p["research_ratio"]), branch)
					_dirty = true))
		else:
			box.add_child(UI.label("وصلت لأعلى جيل.", UI.C_GOOD, 14))


# ------------------------------------------------------------------ تبويب الدبلوماسية

func _fill_diplomacy() -> void:
	var box: VBoxContainer = tab_boxes[Tab.DIPLOMACY]
	UI.clear(box)
	var s = Game.sim
	var pid: String = s.state["player"]
	if selected == "" or selected == pid:
		box.add_child(UI.label("اضغط على دولة في الخريطة لترى علاقاتك بها وخياراتك.", UI.C_MUTED))
	else:
		_fill_selected(box, selected)
	box.add_child(UI.sep())
	box.add_child(UI.title("حروبك", 18))
	var my_wars: Array = s.wars_of(pid)
	if my_wars.is_empty():
		box.add_child(UI.label("لا حروب الآن.", UI.C_MUTED))
	for w in my_wars:
		var my := float(w["score"]) if pid in w["attackers"] else -float(w["score"])
		var enemy: String = w["defenders"][0] if pid in w["attackers"] else w["attackers"][0]
		box.add_child(UI.kv("ضد %s" % s.country(enemy)["name_ar"], "النتيجة %d" % int(my), UI.C_GOOD if my >= 0.0 else UI.C_BAD))
		box.add_child(UI.bar(my + 100.0, 200.0, UI.C_GOOD if my >= 0.0 else UI.C_BAD))
	if not s.state["last_battle"].is_empty():
		box.add_child(UI.button("تقرير آخر معركة", _show_battle_report))
	box.add_child(UI.sep())
	box.add_child(UI.title("كل الحروب في العالم", 16))
	if s.state["wars"].is_empty():
		box.add_child(UI.label("العالم في سلام هش.", UI.C_MUTED))
	for w in s.state["wars"]:
		box.add_child(UI.label("%s ⚔ %s (%d)" % [s.country(w["attackers"][0])["name_ar"], s.country(w["defenders"][0])["name_ar"], int(w["score"])], UI.C_MUTED, 14))


func _fill_selected(box: VBoxContainer, id: String) -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	var c: Dictionary = s.country(id)
	var rel: float = s.relation(pid, id)
	box.add_child(UI.title(c["name_ar"]))
	_region_card(box, id)
	box.add_child(UI.kv("نظام الحكم", s.db.governments[c["government"]]["name_ar"]))
	box.add_child(UI.kv("الناتج", UI.money(float(c["gdp"]))))
	var vis := Intel.visibility(s, pid, id)
	box.add_child(UI.kv("رؤيتك الاستخباراتية", "%d / 100%s" % [int(vis), "" if vis >= 60.0 else " (أرقام تقديرية)"], UI.C_GOOD if vis >= 60.0 else UI.C_ACCENT))
	box.add_child(UI.kv("القوة العسكرية", "%s (قوتك %s)" % [_fmt_est(Intel.estimate(s, pid, id, s.military_power(c), "power")), s.fmt_num(s.military_power(s.player()))]))
	box.add_child(UI.kv("الاستقرار", str(int(c["stability"])) if vis >= 40.0 else "غير معروف"))
	box.add_child(UI.kv("العلاقة معك", "%d" % int(rel), UI.C_GOOD if rel >= 0.0 else UI.C_BAD))
	box.add_child(UI.bar(rel + 100.0, 200.0, UI.C_GOOD if rel >= 0.0 else UI.C_BAD))
	var al: Array = s.alliance_of(id)
	if not al.is_empty():
		box.add_child(UI.kv("التحالفات", "، ".join(PackedStringArray(al.map(func(a): return s.state["alliances"][a]["name_ar"])))))
	if c.get("overlord", "") != "":
		box.add_child(UI.kv("تابعة لـ", s.country(c["overlord"])["name_ar"], UI.C_ACCENT))
	var inf := float(c["influence"].get(pid, 0.0))
	if inf > 0.0:
		box.add_child(UI.kv("نفوذك فيها", "%d / 100" % int(inf), UI.C_ACCENT))
	if vis >= 40.0:
		box.add_child(UI.label("الأسلحة: جو الجيل %d، بر الجيل %d، دفاع جوي الجيل %d" % [int(c["tech"]["air"]), int(c["tech"]["land"]), int(c["tech"]["air_defense"])], UI.C_MUTED, 14))
	else:
		box.add_child(UI.label("أجيال أسلحتها غير معروفة: تحتاج رؤية 40 على الأقل.", UI.C_MUTED, 14))
	if vis >= 50.0 and c.get("rival", "") == pid:
		box.add_child(UI.label("استخباراتنا: %s تعتبرك خصماً وعلاقتها بك تتدهور عمداً." % c["name_ar"], UI.C_BAD, 14))
	_regions_section(box, id)

	var at_war: bool = not s.war_between(pid, id).is_empty()
	var actions := GridContainer.new()
	actions.columns = 2
	box.add_child(actions)
	var act := func(text: String, cb: Callable) -> void:
		var b := UI.button(text, cb)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		actions.add_child(b)
	if not at_war:
		act.call("تحسين العلاقات (%s)" % UI.money(maxf(0.2, float(s.player()["gdp"]) * 0.0005)), func(): _do(s.improve_relations(pid, id), "تحسنت العلاقات."))
		act.call("استثمار ونفوذ (%s)" % UI.money(maxf(0.5, float(c["gdp"]) * 0.01)), func(): _do(s.invest(pid, id), "تم الاستثمار وزاد نفوذك."))
		var do_sanction := func():
			s.toggle_sanction(pid, id)
			_dirty = true
		act.call("رفع العقوبات" if pid in c["sanctions"] else "فرض عقوبات (−15% من صادراتها)", do_sanction)
		if Market.has_pact(s, pid, id):
			act.call("إلغاء الاتفاقية التجارية", func():
				Market.cancel_pact(s, pid, id, "بقرار منك")
				_dirty = true)
		else:
			var tp: Dictionary = s.db.market["trade_pact"]
			act.call("اتفاقية تجارية (+%.2f%% نمو، +%d%% استيراد)" % [float(tp["growth"]), int(float(tp["import_bonus"]) * 100.0)], func(): _do(Market.sign_pact(s, pid, id), "وُقعت الاتفاقية التجارية."))
		if not (id in s.allies(pid)):
			act.call("عرض تحالف", func(): _do(s.propose_alliance(pid, id), "تم التحالف!"))
		act.call("⚔ إعلان الحرب", func(): _confirm_war(id))
	else:
		act.call("☮ عرض السلام", func(): _do(s.propose_peace(pid, id), "قُبل السلام."))
		act.call("☢ ضربة نووية", func(): _confirm_nuke(id))
	_covert_section(box, id)


## بطاقة المنطقة المختارة على الخريطة (إن كانت تخص هذه الدولة)
func _region_card(box: VBoxContainer, id: String) -> void:
	var s = Game.sim
	if selected_region == "" or not s.state["regions"].has(selected_region):
		return
	var r: Dictionary = s.state["regions"][selected_region]
	if r["owner"] != id and r["core"] != id:
		return
	var info: Dictionary = s.db.regions[selected_region]
	var panel := PanelContainer.new()
	var v := UI.col()
	panel.add_child(v)
	var title: String = info["name_ar"]
	if info["capital"]:
		title += " (العاصمة)"
	v.add_child(UI.title(title, 18))
	if r["owner"] != r["core"]:
		v.add_child(UI.kv("الحالة", "تحتلها %s" % s.country(r["owner"])["name_ar"], UI.C_BAD))
		v.add_child(UI.kv("الولاء للمحتل", "%d" % int(r["loyalty"])))
		v.add_child(UI.kv("الاندماج", "%d%%" % int(Territory.efficiency(r) * 100.0)))
	v.add_child(UI.kv("السكان", "%s مليون" % String.num(float(r["pop"]), 2)))
	v.add_child(UI.kv("الناتج", UI.money(float(r["gdp"]) * Territory.efficiency(r))))
	var nb := PackedStringArray()
	for n in info["neighbors"]:
		var ninfo: Dictionary = s.db.regions[n]
		var nm: String = ninfo["name_ar"]
		if ninfo["country"] != info["country"]:
			nm += " (%s)" % s.country(ninfo["country"])["name_ar"]
		nb.append(nm)
	v.add_child(UI.label("تجاورها: " + ("، ".join(nb) if not nb.is_empty() else "لا جيران برّيين (جزيرة)"), UI.C_MUTED, 14))
	if info.get("coastal", false):
		v.add_child(UI.label("منطقة ساحلية", UI.C_MUTED, 13))
	var here := PackedStringArray()
	for d in s.state.get("divisions", []):
		if d["region"] == selected_region and (d["owner"] == s.state["player"] or Intel.visibility(s, s.state["player"], d["owner"]) >= 40.0):
			here.append("الفرقة %d (%s، جاهزية %d%%)" % [int(d["id"]), s.country(d["owner"])["name_ar"], int(float(d["strength"]) * 100.0)])
	if not here.is_empty():
		v.add_child(UI.label("فرق هنا: " + "، ".join(here), UI.C_ACCENT, 14))
	var res: Dictionary = info.get("resources", {})
	var rp := PackedStringArray()
	for k in Territory.RESOURCE_NAMES:
		if float(res.get(k, 0.0)) >= 0.5:
			rp.append("%s %s" % [Territory.RESOURCE_NAMES[k], String.num(float(res[k]), 1)])
	if not rp.is_empty():
		v.add_child(UI.label("الموارد: " + "، ".join(rp), UI.C_TEXT, 14))
	var fac: Dictionary = info.get("facilities", {})
	var pid: String = s.state["player"]
	var enemy: bool = r["owner"] != pid and not s.war_between(pid, r["owner"]).is_empty()
	for t in Territory.FACILITY_TYPES:
		if int(fac.get(t, 0)) <= 0:
			continue
		var dmg := int(r.get("damaged", {}).get(t, 0))
		var status := "معطلة %d أشهر" % dmg if dmg > 0 else "عاملة"
		var line := UI.kv("%s × %d" % [Territory.FACILITY_NAMES[t], int(fac[t])], status, UI.C_BAD if dmg > 0 else UI.C_GOOD)
		v.add_child(line)
		if enemy and dmg == 0:
			var pct := int(s.strike_chance(pid, selected_region) * 100.0)
			var b := UI.button("اضرب %s (%d صاروخاً، فرصة %d%%)" % [Territory.FACILITY_NAMES[t], int(Simulation.STRIKE_MISSILES), pct], _strike.bind(selected_region, t))
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(b)
	box.add_child(panel)


func _strike(rid: String, ftype: String) -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	var why: String = s.can_strike_facility(pid, rid, ftype)
	if why != "":
		_toast(why)
		return
	var res: Dictionary = s.strike_facility(pid, rid, ftype)
	_show_dialog("ضربة صاروخية", res.get("text", ""), [{"text": "حسناً"}])
	_dirty = true


func _core_resource(id: String, k: String) -> float:
	var t := 0.0
	for rid in Game.sim.db.regions_by_country.get(id, []):
		t += float(Game.sim.db.regions[rid].get("resources", {}).get(k, 0.0))
	return t


## الفئات الداخلية: رضا كل فئة وأسبابه ووزنها، وزر الاسترضاء
func _factions_section(box: VBoxContainer, p: Dictionary) -> void:
	var s = Game.sim
	if not p.has("factions"):
		return
	box.add_child(UI.sep())
	box.add_child(UI.title("الفئات الداخلية", 18))
	box.add_child(UI.label("رضاها الموزون يرفع الاستقرار أو يخفضه. الجيش الغاضب ينقلب، والشارع الغاضب يثور.", UI.C_MUTED, 13))
	for f in Factions.ids(s):
		var e: Dictionary = p["factions"][f]
		var info: Dictionary = s.db.factions["factions"][f]
		var sat := float(e["sat"])
		var w := Factions.weight(s, p["government"], f)
		var col := UI.C_GOOD if sat >= 55.0 else (UI.C_ACCENT if sat >= 30.0 else UI.C_BAD)
		var trend := ""
		if float(e["target"]) > sat + 2.0:
			trend = " ▲"
		elif float(e["target"]) < sat - 2.0:
			trend = " ▼"
		box.add_child(UI.kv("%s (وزنها %d%%)" % [info["name_ar"], int(w * 100.0)], "%d%s" % [int(sat), trend], col))
		box.add_child(UI.bar(sat, 100.0, col))
		var reasons: Array = e.get("reasons", []).duplicate()
		reasons.sort_custom(func(a, b): return absf(float(a[1])) > absf(float(b[1])))
		var rp := PackedStringArray()
		for r in reasons.slice(0, 3):
			if absf(float(r[1])) >= 1.0:
				rp.append("%s %s" % [r[0], UI.signed(float(r[1]), 0)])
		if not rp.is_empty():
			box.add_child(UI.label("الأسباب: " + "، ".join(rp), UI.C_MUTED, 13))
		var fid: String = f
		var b := UI.button("استرضاء: %s (%s)" % [info["appease_ar"], UI.money(Factions.appease_cost(s, p))], func():
			_do(Factions.appease(s, p, fid), "ارتفع رضا %s." % info["name_ar"]))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = Factions.can_appease(s, p, f) != ""
		box.add_child(b)


## السوق العالمي: الأسعار وتاريخها، ومركزك تصديراً واستيراداً، واتفاقياتك
func _market_section(box: VBoxContainer, p: Dictionary) -> void:
	var s = Game.sim
	box.add_child(UI.sep())
	box.add_child(UI.title("السوق العالمي", 18))
	box.add_child(UI.label("الأسعار تتغير مع العرض والحروب والعقوبات والأحداث. المصدّر يربح من ارتفاعها والمستورد يدفع.", UI.C_MUTED, 13))
	var flows: Dictionary = p.get("trade_flows", {})
	for k in Market.commodities(s):
		var pr := Market.price(s, k)
		var ago := Market.price_year_ago(s, k)
		var ch := (pr / maxf(0.01, ago) - 1.0) * 100.0
		var arrow := "▲" if ch > 1.0 else ("▼" if ch < -1.0 else "•")
		var cname: String = s.db.market["commodities"][k]["name_ar"]
		var net := float(flows.get(k, 0.0))
		var pos := "مصدّر %d" % int(roundf(net)) if net > 0.5 else ("مستورد %d" % int(roundf(-net)) if net < -0.5 else "مكتفٍ")
		var row := UI.row()
		var lbl := UI.label("%s  %.2f %s%d%%" % [cname, pr, arrow, int(roundf(absf(ch)))], UI.C_BAD if pr > 1.15 else (UI.C_GOOD if pr < 0.9 else UI.C_TEXT))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var sl := Sparkline.new()
		sl.values = s.state["market"]["history"][k]
		sl.color = UI.C_ACCENT
		row.add_child(sl)
		var lp := UI.label(pos, UI.C_GOOD if net > 0.5 else (UI.C_MUTED if net > -0.5 else UI.C_ACCENT), 14)
		lp.custom_minimum_size = Vector2(90, 0)
		row.add_child(lp)
		box.add_child(row)
	var pacts: Array = Market.pacts_of(s, p["id"])
	var names := PackedStringArray(pacts.map(func(x): return s.country(x)["name_ar"]))
	box.add_child(UI.kv("الاتفاقيات التجارية", ("، ".join(names) if not names.is_empty() else "لا يوجد"), UI.C_TEXT))
	if not pacts.is_empty():
		box.add_child(UI.label("تمنحك +%.2f%% نمواً سنوياً، وقدرة استيراد أعلى." % Market.pact_growth(s, p["id"]), UI.C_GOOD, 13))
	if float(p.get("trade_lost", 0.0)) > 0.0:
		box.add_child(UI.kv("صادرات منعها الحصار والعقوبات", UI.money(float(p["trade_lost"])) + " شهرياً", UI.C_BAD))


## الإمداد: كيف تؤثر الموارد والمنشآت في الجيش والاقتصاد
func _logistics_section(box: VBoxContainer, p: Dictionary) -> void:
	var lg: Dictionary = p.get("logistics", {})
	if lg.is_empty():
		return
	var s = Game.sim
	box.add_child(UI.sep())
	box.add_child(UI.title("الإمداد", 18))
	if Logistics.blockaded(s, p):
		box.add_child(UI.label("تحت حصار بحري: الواردات شبه مقطوعة.", UI.C_BAD))
	var pct := func(x: float) -> String:
		return "%d%%" % int(roundf(x * 100.0))
	var col := func(x: float) -> Color:
		return UI.C_GOOD if x >= 0.95 else (UI.C_ACCENT if x >= 0.75 else UI.C_BAD)
	box.add_child(UI.kv("قدرة الاستيراد", pct.call(float(lg["import"])), col.call(float(lg["import"]) / Logistics.BASE_IMPORT)))
	box.add_child(UI.kv("الوقود للجيش", pct.call(float(lg["fuel"])), col.call(float(lg["fuel"]))))
	box.add_child(UI.kv("كفاءة القواعد الجوية", pct.call(float(lg["air"])), col.call(float(lg["air"]))))
	box.add_child(UI.kv("كفاءة الموانئ والأسطول", pct.call(float(lg["sea"])), col.call(float(lg["sea"]))))
	box.add_child(UI.kv("سرعة التصنيع", pct.call(float(lg["production"])), col.call(float(lg["production"]))))
	box.add_child(UI.kv("الكهرباء", pct.call(float(lg["power"])), col.call(float(lg["power"]))))
	if float(lg["food_penalty"]) > 0.0:
		box.add_child(UI.kv("نقص الغذاء", "−%d استقرار" % int(float(lg["food_penalty"])), UI.C_BAD))


## قائمة مناطق الدولة بأسمائها، مع العاصمة والمناطق المحتلة
func _regions_section(box: VBoxContainer, id: String) -> void:
	var s = Game.sim
	var core: Array = s.db.regions_by_country.get(id, [])
	box.add_child(UI.sep())
	box.add_child(UI.title("مناطق %s (%d)" % [s.country(id)["name_ar"], core.size()], 18))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for rid in core:
		var r: Dictionary = s.state["regions"][rid]
		var info: Dictionary = s.db.regions[rid]
		var text: String = info["name_ar"]
		if info["capital"]:
			text = "★ " + text
		var col := UI.C_TEXT
		if r["owner"] != id:
			text += " (محتلة)"
			col = UI.C_BAD
		var b := UI.button(text, _select_region.bind(rid))
		b.add_theme_color_override("font_color", col)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(b)
	var occ := PackedStringArray()
	for rid in Territory.owned(s, id):
		if s.state["regions"][rid]["core"] != id:
			occ.append("%s (%s)" % [s.db.regions[rid]["name_ar"], s.country(s.state["regions"][rid]["core"])["name_ar"]])
	if not occ.is_empty():
		box.add_child(UI.label("مناطق تحتلها: " + "، ".join(occ), UI.C_ACCENT, 14))


func _select_region(rid: String) -> void:
	selected_region = rid
	map.selected_region = rid
	var info: Dictionary = Game.sim.db.regions[rid]
	map.focus_point(float(info["lon"]), float(info["lat"]))
	_dirty = true


## نص تقدير: دقيق أو بنطاق خطأ
func _fmt_est(e: Dictionary) -> String:
	var s = Game.sim
	if e["exact"]:
		return s.fmt_num(e["value"])
	return "≈ %s (%s–%s)" % [s.fmt_num(e["value"]), s.fmt_num(e["lo"]), s.fmt_num(e["hi"])]


## شبكة التجسس والعمليات السرية في الدولة المختارة
func _covert_section(box: VBoxContainer, id: String) -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	var c: Dictionary = s.country(id)
	box.add_child(UI.sep())
	box.add_child(UI.title("الاستخبارات في %s" % c["name_ar"], 16))
	var net := Intel.network(s, pid, id)
	box.add_child(UI.kv("شبكة التجسس", "%d / 100" % int(net), UI.C_ACCENT))
	box.add_child(UI.bar(net, 100.0, UI.C_ACCENT))
	var bb := UI.button("توسيع الشبكة (%s)" % UI.money(Intel.network_cost(s, pid)), func():
		_do(Intel.build(s, pid, id), "توسعت شبكة التجسس."))
	bb.disabled = Intel.can_build(s, pid, id) != ""
	bb.tooltip_text = Intel.can_build(s, pid, id)
	box.add_child(bb)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for op in s.db.intel["operations"]:
		var o: Dictionary = s.db.intel["operations"][op]
		var why: String = Intel.can_run(s, pid, id, op)
		var label := "%s (شبكة %d)" % [o["name_ar"], int(o["min_network"])]
		if why == "":
			label = "%s: فرصة %d%%، %s" % [o["name_ar"], int(Intel.op_chance(s, pid, id, op) * 100.0), UI.money(Intel.op_cost(s, pid, op))]
		var opid: String = op
		var b := UI.button(label, func(): _run_op(id, opid))
		b.disabled = why != ""
		b.tooltip_text = (why if why != "" else o["desc_ar"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(b)
	box.add_child(UI.label("كل عملية قد تنكشف فتتدهور العلاقات وتخسر جزءاً من الشبكة.", UI.C_MUTED, 13))


func _run_op(id: String, op: String) -> void:
	var s = Game.sim
	var r: Dictionary = Intel.run(s, s.state["player"], id, op)
	var title: String = s.db.intel["operations"][op]["name_ar"]
	if r.get("error", false):
		_toast(r["text"])
	else:
		_show_dialog(("نجحت: " if r["success"] else "فشلت: ") + title, r["text"], [{"text": "حسناً"}])
	_dirty = true


## تبويب الاستخبارات: مكافحة التجسس وشبكاتك والتهديدات
func _fill_intel() -> void:
	var box: VBoxContainer = tab_boxes[Tab.INTEL]
	UI.clear(box)
	var s = Game.sim
	var pid: String = s.state["player"]
	var p: Dictionary = s.player()
	box.add_child(UI.title("مكافحة التجسس", 18))
	box.add_child(UI.label("تحمي من العمليات المعادية وتكشف شبكات الأعداء، بكلفة سنوية من الناتج.", UI.C_MUTED, 13))
	var row := UI.row()
	var levels: Array = s.db.intel["counter_levels"]
	for i in levels.size():
		var lv: Dictionary = levels[i]
		var b := UI.button("%s (%s سنوياً)" % [lv["name_ar"], UI.money(float(p["gdp"]) * float(lv["cost_gdp"]))], func():
			Intel.set_counter(s, pid, i)
			_dirty = true)
		b.toggle_mode = true
		b.button_pressed = int(p.get("counter_intel", 0)) == i
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	box.add_child(row)
	var cur: Dictionary = levels[clampi(int(p.get("counter_intel", 0)), 0, 3)]
	box.add_child(UI.label("الآن: تخفض نجاح عمليات الأعداء %d%%، وتكشف شبكاتهم بنسبة %.1f%% شهرياً." % [int(float(cur["block"]) * 50.0), float(cur["detect"]) * 100.0], UI.C_TEXT, 14))
	box.add_child(UI.sep())
	box.add_child(UI.title("شبكات التجسس", 18))
	var nets: Dictionary = p.get("intel", {})
	if nets.is_empty():
		box.add_child(UI.label("لا شبكات بعد. اختر دولة على الخريطة ووسّع شبكتك فيها من تبويب الدبلوماسية.", UI.C_MUTED))
	for t in nets:
		var nm: String = s.country(t)["name_ar"]
		var b := UI.button("%s: %d" % [nm, int(nets[t])], _select_country.bind(t))
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(b)
		box.add_child(UI.bar(float(nets[t]), 100.0, UI.C_ACCENT))
	box.add_child(UI.sep())
	box.add_child(UI.title("ما نعرفه عن الأخطار", 18))
	var any := false
	for oid in s.alive_ids():
		if oid == pid:
			continue
		var c: Dictionary = s.country(oid)
		var vis := Intel.visibility(s, pid, oid)
		if c.get("rival", "") == pid and vis >= 50.0:
			box.add_child(UI.label("• %s تعتبرك خصماً وتدفع العلاقات نحو الحرب." % c["name_ar"], UI.C_BAD, 14))
			any = true
		elif s.relation(pid, oid) < -40.0:
			box.add_child(UI.label("• %s معادية (%d). رؤيتك لها %d%s." % [c["name_ar"], int(s.relation(pid, oid)), int(vis), "" if vis >= 50.0 else ": نواياها غير واضحة"], UI.C_ACCENT, 14))
			any = true
	if not any:
		box.add_child(UI.label("لا أخطار ظاهرة الآن.", UI.C_MUTED))


## الفرق: موقعها وحالتها، وتحريكها بالضغط على منطقة في الخريطة
func _divisions_section(box: VBoxContainer, p: Dictionary) -> void:
	var s = Game.sim
	var pid: String = p["id"]
	box.add_child(UI.sep())
	box.add_child(UI.title("الفرق", 16))
	var auto := CheckButton.new()
	auto.text = "توزيع تلقائي على الجبهات والحدود"
	auto.button_pressed = p.get("auto_deploy", true)
	auto.toggled.connect(func(v):
		p["auto_deploy"] = v
		_dirty = true)
	box.add_child(auto)
	var air_r: float = Divisions.range_km(s, "fighters", int(p["tech"]["air"]))
	var mis_r: float = Divisions.range_km(s, "missiles", int(p["tech"]["missile"]))
	box.add_child(UI.label("مدى مقاتلاتك %d كم من قواعدها، وصواريخك %d كم من أرضك. طبقة «المدى» على الخريطة تعرضه." % [int(air_r), int(mis_r)], UI.C_MUTED, 13))
	var enemies: Array = s.enemies_of(pid)
	var front: Array = Divisions.front_regions(s, [pid], enemies)
	for d in Divisions.of(s, pid):
		var where: String = s.db.regions[d["region"]]["name_ar"]
		var status := "احتياط"
		var col := UI.C_TEXT
		if int(d["eta"]) >= 0:
			status = "تتحرك إلى %s (%d يوماً)" % [s.db.regions[d["target"]]["name_ar"], int(d["eta"]) - int(s.state["day"])]
			col = UI.C_ACCENT
		elif d["region"] in front:
			status = "على الجبهة"
			col = UI.C_BAD
		box.add_child(UI.kv("الفرقة %d · %s" % [int(d["id"]), where], "%s · جاهزية %d%% · خبرة %d%%" % [status, int(float(d["strength"]) * 100.0), int(float(d["exp"]) * 100.0)], col))
		var row := UI.row()
		var did := int(d["id"])
		var mv := UI.button("تحريك" if move_division != did else "اختر الوجهة على الخريطة…", func():
			move_division = did
			map.selected_division = did
			_toast("اضغط على المنطقة التي تريد نقل الفرقة إليها.")
			_dirty = true)
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(mv)
		var where_btn := UI.button("أين؟", func():
			var info: Dictionary = s.db.regions[Divisions.find(s, did)["region"]]
			map.selected_division = did
			map.focus_point(float(info["lon"]), float(info["lat"])))
		row.add_child(where_btn)
		box.add_child(row)
	if p.get("auto_deploy", true):
		box.add_child(UI.label("التحريك اليدوي يعمل مع التوزيع التلقائي، لكن التوزيع قد يعيد ترتيب الفرق. أوقفه لقيادة كاملة.", UI.C_MUTED, 13))


func _on_region_clicked(rid: String) -> void:
	selected_region = rid
	if move_division >= 0:
		var s = Game.sim
		var err: String = Divisions.move(s, move_division, rid)
		if err == "":
			var d: Dictionary = Divisions.find(s, move_division)
			_toast("الفرقة %d تتحرك إلى %s (%d يوماً)." % [move_division, s.db.regions[rid]["name_ar"], int(d["eta"]) - int(s.state["day"])])
		else:
			_toast(err)
		move_division = -1
		map.selected_division = -1
		_keep_tab = true
		tabs.current_tab = Tab.ARMY
		_dirty = true


func _select_country(id: String) -> void:
	selected = id
	selected_region = ""
	map.selected = id
	map.selected_region = ""
	map.focus_country(id)
	tabs.current_tab = Tab.DIPLOMACY
	_dirty = true


func _do(err: String, ok_text: String) -> void:
	_toast(err if err != "" else ok_text)
	_dirty = true


## توقع واضح قبل كل حرب: فرصتك في كل مرحلة
func _confirm_war(id: String) -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	var why: String = s.can_declare_war(pid, id)
	if why != "":
		_toast(why)
		return
	var f: Dictionary = Combat.forecast(s, pid, id)
	var names := "، ".join(PackedStringArray(f["defenders"].map(func(x): return s.country(x)["name_ar"])))
	var pct := func(v: float) -> String:
		return "لا يوجد" if v < 0.0 else "%d%%" % int(v * 100.0)
	# ضباب الحرب: كلما قلت رؤيتك للعدو اتسع هامش الخطأ في التوقع
	var vis := Intel.visibility(s, pid, id)
	var band := maxf(0.0, (1.0 - vis / 60.0) * 0.25)
	if band > 0.0:
		pct = func(v: float) -> String:
			if v < 0.0:
				return "لا يوجد"
			return "%d%%–%d%%" % [int(clampf(v - band, 0.0, 1.0) * 100.0), int(clampf(v + band, 0.0, 1.0) * 100.0)]
	var text := "سيدافع عنها: %s\n\nفرصتك المتوقعة في كل مرحلة:\n• الجو: %s\n• الضربات الصاروخية والمسيّرات: %s\n• البحر: %s\n• البر: %s\n\n" % [names, pct.call(f["air"]), pct.call(f["strike"]), pct.call(f["sea"]), pct.call(f["land"])]
	if band > 0.0:
		text += "رؤيتك لهذا العدو %d فقط: الأرقام تقديرية. ابنِ شبكة تجسس لتوقع أدق.\n" % int(vis)
	if int(f["weeks_to_win"]) > 0:
		text += "التقدير: نصر خلال %d أسبوعاً تقريباً." % int(f["weeks_to_win"])
	var mth: Dictionary = f.get("theater", {}).get(pid, {})
	if not mth.is_empty():
		text += "\nفرقك على الجبهة: %d من %d. قواعدك الجوية التي تصل الجبهة: %d%%. صواريخك: %s." % [int(mth["front_divisions"]), int(mth["divisions"]), int(float(mth["air"]) * 100.0), "في المدى" if float(mth["missiles"]) >= 1.0 else "خارج المدى"]
		if int(mth["front_divisions"]) == 0:
			text += "\nتحذير: لا فرق لك على الجبهة بعد. حرّكها أولاً أو فعّل التوزيع التلقائي."
	else:
		text += "التقدير: الحرب لن تكون في صالحك."
	if not f.get("land_front", true):
		text += "\nلا توجد جبهة برية: التقدم يحتاج تفوقاً بحرياً للإنزال، والإمداد أضعف."
	text += "\nالحرب تُخاض منطقة بمنطقة، وتخفض النمو والاستقرار، وتغضب حلفاء العدو."
	var do_war := func():
		s.declare_war(pid, id)
		_dirty = true
	_show_dialog("إعلان الحرب على %s؟" % s.country(id)["name_ar"], text, [
		{"text": "أعلن الحرب", "cb": do_war},
		{"text": "تراجع"},
	])


func _confirm_nuke(id: String) -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	var why: String = s.can_nuke(pid, id)
	if why != "":
		_toast(why)
		return
	var do_nuke := func():
		s.nuclear_strike(pid, id)
		_dirty = true
	_show_dialog("☢ ضربة نووية على %s؟" % s.country(id)["name_ar"],
		"ستدمر جزءاً كبيراً من اقتصادها وجيشها، لكن كل دول العالم ستعاديك، والرد النووي متوقع.\nالضربات النووية في العالم حتى الآن: %d من %d قبل الشتاء النووي." % [int(s.state["global"]["nuclear_strikes"]), Simulation.NUCLEAR_WINTER_STRIKES],
		[{"text": "أطلق", "cb": do_nuke}, {"text": "تراجع"}])


func _show_battle_report() -> void:
	var s = Game.sim
	var r: Dictionary = s.state["last_battle"]
	if r.is_empty():
		return
	var v := UI.col()
	var a_names := "، ".join(PackedStringArray(r["attackers"].map(func(x): return s.country(x)["name_ar"])))
	var d_names := "، ".join(PackedStringArray(r["defenders"].map(func(x): return s.country(x)["name_ar"])))
	v.add_child(UI.label("%s\nالمهاجم: %s\nالمدافع: %s" % [r["date"], a_names, d_names]))
	for ph in r["phases"]:
		var res := float(ph["result"])
		var winner := "تعادل"
		if res > 0.1:
			winner = "تفوق المهاجم"
		elif res < -0.1:
			winner = "تفوق المدافع"
		v.add_child(UI.kv(ph["name_ar"], winner, UI.C_ACCENT))
		v.add_child(UI.bar(res + 1.0, 2.0, UI.C_GOOD if res >= 0.0 else UI.C_BAD))
	v.add_child(UI.sep())
	var loss_text := func(d: Dictionary) -> String:
		var parts := PackedStringArray()
		for u in d:
			if float(d[u]) >= 0.5:
				parts.append("%s %s" % [s.fmt_num(d[u]), s.db.units[u]["name_ar"]])
		return "، ".join(parts) if not parts.is_empty() else "خسائر طفيفة"
	v.add_child(UI.label("خسائر المهاجم: " + loss_text.call(r["losses_a"]), UI.C_MUTED, 14))
	v.add_child(UI.label("خسائر المدافع: " + loss_text.call(r["losses_d"]), UI.C_MUTED, 14))
	var hits_text := func(hits: Array) -> String:
		var parts := PackedStringArray()
		for h in hits:
			parts.append("%s في %s" % [Territory.FACILITY_NAMES[h["type"]], s.db.regions[h["region"]]["name_ar"]])
		return "، ".join(parts)
	if not r.get("hits_a", []).is_empty():
		v.add_child(UI.label("ضربات المهاجم في العمق: " + hits_text.call(r["hits_a"]), UI.C_ACCENT, 14))
	if not r.get("hits_d", []).is_empty():
		v.add_child(UI.label("ضربات المدافع في العمق: " + hits_text.call(r["hits_d"]), UI.C_ACCENT, 14))
	var taken: Array = r.get("taken", [])
	if not taken.is_empty():
		var who: String = "المهاجم" if r.get("taken_by_attacker", true) else "المدافع"
		var names := PackedStringArray(taken.map(func(x): return s.db.regions[x]["name_ar"]))
		v.add_child(UI.label("سيطر %s على: %s" % [who, "، ".join(names)], UI.C_ACCENT))
	else:
		v.add_child(UI.label("الجبهة لم تتحرك هذا الأسبوع.", UI.C_MUTED, 14))
	if r.has("front_a"):
		v.add_child(UI.kv("الفرق على الجبهة", "المهاجم %d، المدافع %d" % [int(r["front_a"]), int(r["front_d"])], UI.C_TEXT))
	v.add_child(UI.kv("تغير نتيجة الحرب", UI.signed(float(r["delta"]), 1), UI.C_ACCENT))
	v.add_child(UI.label("مشهد المعركة ثلاثي الأبعاد يأتي في مرحلة لاحقة، وسيعرض هذا التقرير نفسه.", UI.C_MUTED, 13))
	_show_dialog("تقرير المعركة", "", [{"text": "إغلاق"}], v)


# ------------------------------------------------------------------ تبويب الأخبار

func _fill_news() -> void:
	var box: VBoxContainer = tab_boxes[Tab.NEWS]
	UI.clear(box)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var news: Array = Game.sim.state["news"]
	var text := ""
	for i in range(news.size() - 1, maxi(-1, news.size() - 81), -1):
		var n: Dictionary = news[i]
		var col: String = NEWS_COLORS.get(n["kind"], "#c9d4dc")
		text += "[color=#7a8a96]%s[/color]\n[color=%s]%s[/color]\n\n" % [n["date"], col, n["text"]]
	rt.text = text
	box.add_child(rt)


# ================================================================== نوافذ ورسائل

## نافذة عامة: buttons = [{text, cb?}]
func _show_dialog(title: String, text: String, buttons: Array, content: Control = null) -> void:
	dialog_queue.append({"title": title, "text": text, "buttons": buttons, "content": content})
	if not dialog_open:
		_next_dialog()


func _next_dialog() -> void:
	if dialog_queue.is_empty():
		dialog_open = false
		return
	dialog_open = true
	var d: Dictionary = dialog_queue.pop_front()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(560.0, get_viewport_rect().size.x - 32.0), 0)
	center.add_child(panel)
	var v := UI.col()
	panel.add_child(v)
	v.add_child(UI.title(d["title"], 22))
	if d["text"] != "":
		v.add_child(UI.label(d["text"]))
	if d["content"] != null:
		v.add_child(d["content"])
	var h := UI.row()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	for b in d["buttons"]:
		var cb: Callable = b.get("cb", Callable())
		h.add_child(UI.button(b["text"], func():
			dim.queue_free()
			if cb.is_valid():
				cb.call()
			_next_dialog()))


func _toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_child(UI.label(text, UI.C_ACCENT))
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.position = Vector2(get_viewport_rect().size.x * 0.5 - 200.0, get_viewport_rect().size.y - 120.0)
	p.custom_minimum_size = Vector2(400, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(p)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _on_save() -> void:
	_toast("تم حفظ اللعبة." if Game.save_game() else "تعذر الحفظ.")


func _on_load() -> void:
	if not Game.load_game():
		_toast("لا يوجد حفظ.")


func _show_menu() -> void:
	Game.set_paused(true)
	_show_dialog("القائمة", "", [
		{"text": "حفظ", "cb": _on_save},
		{"text": "تحميل", "cb": _on_load},
		{"text": "القائمة الرئيسية", "cb": _back_to_menu},
		{"text": "متابعة"},
	])


func _back_to_menu() -> void:
	Game.set_paused(true)
	start_screen.queue_free()
	_build_start_screen()
