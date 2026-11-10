## الشاشة الرئيسية: خريطة القيادة مع الشريط العلوي واللوحة الجانبية والمستشار.
## على الكمبيوتر: لوحة جانبية ثابتة. على الموبايل: لوحة سفلية فوق الخريطة.
extends Control

const UI := preload("res://ui/ui_kit.gd")
const MapView := preload("res://world/map_view.gd")
const Economy := preload("res://sim/economy.gd")
const Combat := preload("res://sim/combat.gd")
const Simulation := preload("res://sim/simulation.gd")

enum Tab { STATE, ECONOMY, ARMY, RESEARCH, DIPLOMACY, NEWS }
const TAB_TITLES := ["الدولة", "الاقتصاد", "الجيش", "البحث", "الدبلوماسية", "الأخبار"]
const BRANCH_EXAMPLE := {"land": "armor", "air": "fighters", "sea": "ships", "missile": "missiles", "air_defense": "air_defense"}
const NEWS_COLORS := {"war": "#e05a55", "nuke": "#ff7b29", "peace": "#4cc38a", "good": "#4cc38a", "world": "#7fb8e6", "info": "#c9d4dc"}

var mobile := false
var map: MapView
var tabs: TabContainer
var tab_boxes: Array = []        # VBox لكل تبويب
var selected: String = ""

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
		side.custom_minimum_size = Vector2(420, 0)
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
	var names := ["سياسي", "القوة العسكرية", "الاقتصاد", "الاستقرار"]
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
	selected = id
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
		Tab.NEWS: _fill_news()
	map.queue_redraw()


func _update_top() -> void:
	if not Game.is_running():
		return
	var s = Game.sim
	var p: Dictionary = s.player()
	lbl_country.text = p["name_ar"]
	lbl_date.text = "📅 " + s.date_text()
	lbl_money.text = "💰 " + UI.money(float(p["treasury"]))
	var st := float(p["stability"])
	lbl_stab.text = "⚖ استقرار %d" % int(st)
	lbl_stab.add_theme_color_override("font_color", UI.C_GOOD if st >= 50.0 else (UI.C_ACCENT if st >= 30.0 else UI.C_BAD))
	btn_pause.text = "▶" if Game.paused else "⏸"
	for i in speed_btns.size():
		speed_btns[i].set_pressed_no_signal(i == Game.speed)


## المستشار: أهم 3 مشكلات أو فرص الآن، والضغط ينقلك للمكان الصحيح
func _update_advisor() -> void:
	UI.clear(advisor_box)
	advisor_box.add_child(UI.title("🎖 المستشار", 16))
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
	if float(p["treasury"]) > gdp * 0.03:
		items.append([40, "في الخزينة فائض %s: استثمر أو صنّع سلاحاً." % UI.money(float(p["treasury"])), Tab.ARMY, ""])
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
	box.add_child(UI.sep())

	box.add_child(UI.title("نظام الحكم", 18))
	var gov_opt := OptionButton.new()
	var gov_ids: Array = s.db.governments.keys()
	for i in gov_ids.size():
		var g: Dictionary = s.db.governments[gov_ids[i]]
		gov_opt.add_item("%s (نمو %s، استقرار %s)" % [g["name_ar"], UI.signed(float(g["growth"])), UI.signed(float(g["stability"]), 0)])
		if gov_ids[i] == p["government"]:
			gov_opt.select(i)
	box.add_child(gov_opt)
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
		for row in [["الرواتب والخدمات", "civil"], ["صيانة الجيش", "military"], ["الدعم", "subsidies"], ["البحث", "research"], ["فوائد الدين", "interest"], ["جزية للمتبوع", "tribute"]]:
			if float(b[row[1]]) > 0.0:
				eco_info.add_child(UI.kv(row[0], "−" + UI.money(float(b[row[1]])), UI.C_BAD))
		var bal := float(b["balance"])
		eco_info.add_child(UI.kv("الرصيد", UI.money(bal), UI.C_GOOD if bal >= 0.0 else UI.C_BAD))
	eco_info.add_child(UI.sep())
	eco_info.add_child(UI.title("الموارد", 18))
	var res_names := {"oil": "النفط", "gas": "الغاز", "steel": "الصلب", "rare_earth": "معادن نادرة", "uranium": "اليورانيوم", "food": "الغذاء"}
	for r in res_names:
		eco_info.add_child(UI.kv(res_names[r], str(int(p["resources"].get(r, 0)))))
		eco_info.add_child(UI.bar(float(p["resources"].get(r, 0)), 100.0, UI.C_LINE))
	var oil := float(s.state["global"]["oil_price"])
	eco_info.add_child(UI.kv("مؤشر سعر النفط العالمي", "%.2f" % oil, UI.C_ACCENT))


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
	box.add_child(UI.kv("نظام الحكم", s.db.governments[c["government"]]["name_ar"]))
	box.add_child(UI.kv("الناتج", UI.money(float(c["gdp"]))))
	box.add_child(UI.kv("القوة العسكرية", "%s (قوتك %s)" % [s.fmt_num(s.military_power(c)), s.fmt_num(s.military_power(s.player()))]))
	box.add_child(UI.kv("الاستقرار", str(int(c["stability"]))))
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
	box.add_child(UI.label("الأسلحة: جو الجيل %d، بر الجيل %d، دفاع جوي الجيل %d" % [int(c["tech"]["air"]), int(c["tech"]["land"]), int(c["tech"]["air_defense"])], UI.C_MUTED, 14))

	var at_war: bool = not s.war_between(pid, id).is_empty()
	var actions := GridContainer.new()
	actions.columns = 2
	box.add_child(actions)
	var act := func(text: String, cb: Callable) -> void:
		var b := UI.button(text, cb)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	if not at_war:
		act.call("تحسين العلاقات (%s)" % UI.money(maxf(0.2, float(s.player()["gdp"]) * 0.0005)), func(): _do(s.improve_relations(pid, id), "تحسنت العلاقات."))
		act.call("استثمار ونفوذ (%s)" % UI.money(maxf(0.5, float(c["gdp"]) * 0.01)), func(): _do(s.invest(pid, id), "تم الاستثمار وزاد نفوذك."))
		var do_sanction := func():
			s.toggle_sanction(pid, id)
			_dirty = true
		act.call("رفع العقوبات" if pid in c["sanctions"] else "فرض عقوبات", do_sanction)
		if not (id in s.allies(pid)):
			act.call("عرض تحالف", func(): _do(s.propose_alliance(pid, id), "تم التحالف!"))
		act.call("⚔ إعلان الحرب", func(): _confirm_war(id))
	else:
		act.call("☮ عرض السلام", func(): _do(s.propose_peace(pid, id), "قُبل السلام."))
		act.call("☢ ضربة نووية", func(): _confirm_nuke(id))


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
	var text := "سيدافع عنها: %s\n\nفرصتك المتوقعة في كل مرحلة:\n• الجو: %s\n• الضربات الصاروخية والمسيّرات: %s\n• البحر: %s\n• البر: %s\n\n" % [names, pct.call(f["air"]), pct.call(f["strike"]), pct.call(f["sea"]), pct.call(f["land"])]
	if int(f["weeks_to_win"]) > 0:
		text += "التقدير: نصر خلال %d أسبوعاً تقريباً." % int(f["weeks_to_win"])
	else:
		text += "التقدير: الحرب لن تكون في صالحك."
	text += "\nالحرب تخفض النمو والاستقرار، وتغضب حلفاء العدو."
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
