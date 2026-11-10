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
const Icons := preload("res://ui/icons.gd")
const Flags := preload("res://ui/flags.gd")
const TouchScroll := preload("res://ui/touch_scroll.gd")

enum Tab { STATE, ECONOMY, ARMY, RESEARCH, DIPLOMACY, INTEL, NEWS }
const TAB_TITLES := ["الدولة", "الاقتصاد", "الجيش", "البحث", "الدبلوماسية", "الاستخبارات", "الأخبار"]
const TAB_ICONS := ["state", "economy", "army", "research", "diplomacy", "intel", "news"]
const LAYERS := [["سياسي", "layers"], ["القوة", "army"], ["الاقتصاد", "economy"], ["الاستقرار", "stability"], ["الموارد", "r_oil"], ["المدى", "range"]]
const BRANCH_EXAMPLE := {"land": "armor", "air": "fighters", "sea": "ships", "missile": "missiles", "air_defense": "air_defense"}
const NEWS_COLORS := {"war": "#e05a55", "nuke": "#ff7b29", "peace": "#4cc38a", "good": "#4cc38a", "world": "#7fb8e6", "info": "#c9d4dc"}

var mobile := false
var map: MapView
var hud: Control
var tabs: TabContainer
var tab_boxes: Array = []        # VBox لكل تبويب
var selected: String = ""
var selected_region: String = ""
var move_division: int = -1        # أول فرقة في وضع التحريك
var ctx: Dictionary = {}           # ما تعرضه بطاقة السياق: {kind: region|units|move, ...}

# مقاسات اللمس (تتضاعف دقتها على الهاتف عبر تكبير الواجهة كلها)
const EDGE := 10.0
const TOUCH := 44.0
const BIG := 56.0
const DOCK_W := 74.0
const CTX_W := 360.0
const DOCK_TABS := [Tab.ECONOMY, Tab.ARMY, Tab.DIPLOMACY, Tab.INTEL, Tab.RESEARCH]
const DOCK_TITLES := ["الدولة", "اقتصاد", "جيش", "بحث", "علاقات", "استخبارات", "الأخبار"]

# الشريط العلوي
var country_btn: Button
var country_flag: TextureRect
var lbl_country: Label
var ready_segs: Array = []
var lbl_ready: Label
var stat_money: Button
var stat_stab: Button
var stat_war: Button
var alerts_btn: Button
var alerts_pop: PanelContainer
# الوقت
var lbl_date: Label
var btn_pause: Button
var speed_btn: Button
var speed_pips: Array = []
# الرصيف واللوحة
var dock: PanelContainer
var dock_btns: Dictionary = {}
var sheet: PanelContainer
var panel_title: Label
var panel_icon: TextureRect
var _sheet_drag_y := -1.0
var _sheet_rest_y := 0.0
var _sheet_tw: Tween
# الخريطة
var layer_btn: Button
var layers_pop: PanelContainer
var legend_panel: PanelContainer
var legend_box: VBoxContainer
var hover_card: PanelContainer
var hover_label: Label
var ctx_card: PanelContainer
var ctx_box: VBoxContainer

# التنبيهات
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

var touch_scroll: Node
var _refresh_acc := 0.0
var _dirty := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.apply_palette(Game.light_theme)
	MapView.apply_palette(Game.light_theme)
	mobile = Game.mobile or get_viewport_rect().size.x < 900.0
	MapView.text_scale = 1.15 if mobile else 1.0
	theme = UI.make_theme(mobile)
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	touch_scroll = TouchScroll.new()
	add_child(touch_scroll)
	_build_layout()
	_build_start_screen()
	Game.day_passed.connect(_on_day)
	Game.month_passed.connect(func(): _dirty = true)
	Game.events_ready.connect(_on_events)
	Game.paused_changed.connect(func(_p): _update_top())
	Game.speed_changed.connect(func(_s): _update_top())
	Game.game_started.connect(_on_game_started)
	Game.theme_changed.connect(func(): get_tree().reload_current_scene())
	Game.day_passed.connect(func(): map.refresh())
	# بعد تبديل الثيم يُعاد بناء الشاشة واللعبة مستمرة
	if Game.is_running():
		_on_game_started.call_deferred()


# ================================================================== البناء

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = UI.C_INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# الخريطة تملأ الشاشة، وكل ما عداها يطفو فوقها
	map = MapView.new()
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	map.layout_direction = Control.LAYOUT_DIRECTION_LTR
	map.country_selected.connect(_on_country_selected)
	map.region_selected.connect(_on_region_clicked)
	map.units_tapped.connect(_on_units_tapped)
	map.empty_tapped.connect(_on_empty_tapped)
	map.hovered.connect(_on_map_hover)
	add_child(map)

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_child(hud)
	_build_top_bar()
	_build_time_controls()
	_build_dock()
	_build_map_tools()
	_build_context_card()
	_build_sheet()
	_build_alerts()

	hover_card = PanelContainer.new()
	hover_card.add_theme_stylebox_override("panel", UI.float_box(10, 10))
	hover_card.visible = false
	hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label = UI.label("", UI.C_TEXT, 14)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.layout_direction = Control.LAYOUT_DIRECTION_RTL
	hover_card.add_child(hover_label)
	hud.add_child(hover_card)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)


## مكان عنصر عائم: زاوية الشاشة والمسافة منها. طبقة العناصر العائمة يسار-يمين (LTR) حتى تبقى
## الزوايا كما نصفها، ومحتوى كل لوحة من اليمين لليسار.
func _pin(c: Control, corner: int, margin: Vector2) -> void:
	# المرساة تنعكس إن كان العنصر نفسه RTL، فنجعله LTR ومحتواه RTL
	c.layout_direction = Control.LAYOUT_DIRECTION_LTR
	for ch in c.get_children():
		if ch is Control and (ch as Control).layout_direction == Control.LAYOUT_DIRECTION_INHERITED:
			(ch as Control).layout_direction = Control.LAYOUT_DIRECTION_RTL
	var right := corner in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT]
	var bottom := corner in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	var middle := corner in [Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT]
	c.anchor_left = 1.0 if right else 0.0
	c.anchor_right = c.anchor_left
	c.anchor_top = 1.0 if bottom else (0.5 if middle else 0.0)
	c.anchor_bottom = c.anchor_top
	var x := -margin.x if right else margin.x
	var y := -margin.y if bottom else margin.y
	c.offset_left = x
	c.offset_right = x
	c.offset_top = y
	c.offset_bottom = y
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BOTH if middle else (Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END)


## زر شفاف داخل شريط عائم: أيقونة ونص قصير، يستجيب لكامل مساحته
func _pill_button(icon: String, text: String, cb: Callable, tip: String = "") -> Button:
	var b := UI.button(text, cb, icon, "FlatButton")
	b.tooltip_text = tip
	b.add_theme_constant_override("icon_max_width", 22 if not mobile else 24)
	b.add_theme_color_override("font_color", UI.C_TEXT)
	b.add_theme_color_override("font_hover_color", UI.C_TEXT)
	b.custom_minimum_size = Vector2(0, TOUCH)
	return b


## الشريط العلوي: حالة فقط. الدولة والاستعداد يميناً، ثم المال والاستقرار والحروب، والتنبيهات والقائمة يساراً
func _build_top_bar() -> void:
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UI.float_box(14, 4))
	var rh := UI.row()
	rh.add_theme_constant_override("separation", 2)
	right.add_child(rh)
	# الدولة: العلم والاسم ومؤشر الاستعداد، ولمسها يفتح ملف الدولة
	country_btn = Button.new()
	country_btn.theme_type_variation = "FlatButton"
	country_btn.custom_minimum_size = Vector2(0, TOUCH)
	country_btn.tooltip_text = "ملف دولتك: الحكم والفئات والسياسات"
	country_btn.pressed.connect(func(): _toggle_sheet(Tab.STATE))
	var ch := UI.row()
	ch.add_theme_constant_override("separation", 8)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ch.offset_left = 10
	ch.offset_right = -10
	country_flag = Flags.rect("", 30)
	country_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(country_flag)
	lbl_country = UI.title("—", 17)
	lbl_country.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(lbl_country)
	var ready_box := HBoxContainer.new()
	ready_box.add_theme_constant_override("separation", 2)
	ready_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 5:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(4, 12)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ready_segs.append(seg)
		ready_box.add_child(seg)
	ch.add_child(ready_box)
	lbl_ready = UI.label("", UI.C_TEXT, 13)
	lbl_ready.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_ready.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(lbl_ready)
	country_btn.add_child(ch)
	ch.resized.connect(func(): country_btn.custom_minimum_size.x = ch.get_combined_minimum_size().x + 20)
	rh.add_child(country_btn)
	var sep := ColorRect.new()
	sep.color = UI.C_LINE_2
	sep.custom_minimum_size = Vector2(1, 24)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(sep)
	stat_money = _pill_button("treasury", "", func(): _toggle_sheet(Tab.ECONOMY), "الخزينة، وصافي الشهر الماضي")
	stat_stab = _pill_button("stability", "", func(): _toggle_sheet(Tab.STATE), "الاستقرار الداخلي من 100")
	stat_war = _pill_button("war", "", func(): _toggle_sheet(Tab.DIPLOMACY), "الحروب الجارية")
	for b in [stat_money, stat_stab, stat_war]:
		rh.add_child(b)
	_pin(right, Control.PRESET_TOP_RIGHT, Vector2(EDGE, EDGE))
	hud.add_child(right)

	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UI.float_box(14, 4))
	var lh := UI.row()
	lh.add_theme_constant_override("separation", 2)
	left.add_child(lh)
	alerts_btn = _pill_button("bell", "", _toggle_alerts, "أمور تحتاج قرارك")
	lh.add_child(alerts_btn)
	var menu := _pill_button("menu", "", _show_menu, "القائمة: حفظ، تحميل، الوضع الداكن")
	lh.add_child(menu)
	_pin(left, Control.PRESET_TOP_LEFT, Vector2(EDGE, EDGE))
	hud.add_child(left)


## الوقت تحت إبهام اليد اليسرى: التاريخ، وزر كبير للتشغيل، وزر السرعة بخمس درجات
func _build_time_controls() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.float_box(18, 6))
	var v := UI.col()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	lbl_date = UI.label("", UI.C_TEXT, 14)
	lbl_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_date.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(lbl_date)
	var h := UI.row()
	h.add_theme_constant_override("separation", 6)
	h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	v.add_child(h)
	btn_pause = Button.new()
	btn_pause.theme_type_variation = "PrimaryButton"
	btn_pause.custom_minimum_size = Vector2(BIG, BIG)
	btn_pause.expand_icon = true
	btn_pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn_pause.tooltip_text = "تشغيل / إيقاف (مسافة)"
	btn_pause.pressed.connect(func(): Game.toggle_pause())
	var round_st := StyleBoxFlat.new()
	round_st.bg_color = UI.C_ACCENT
	round_st.set_corner_radius_all(int(BIG * 0.5))
	round_st.set_content_margin_all(14)
	round_st.anti_aliasing = true
	var round_h: StyleBoxFlat = round_st.duplicate()
	round_h.bg_color = UI.C_ACCENT.lightened(0.12)
	btn_pause.add_theme_stylebox_override("normal", round_st)
	btn_pause.add_theme_stylebox_override("hover", round_h)
	btn_pause.add_theme_stylebox_override("pressed", round_h)
	btn_pause.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	h.add_child(btn_pause)
	# السرعة: زر يدور بين الخمس، مع خمس نقاط تبين المستوى. على الكمبيوتر أيضاً المفاتيح 1-5
	speed_btn = Button.new()
	speed_btn.theme_type_variation = "FlatButton"
	speed_btn.custom_minimum_size = Vector2(BIG + 10, BIG)
	speed_btn.tooltip_text = "السرعة: المس للتبديل (المفاتيح 1-5)"
	speed_btn.pressed.connect(func(): _set_speed((Game.speed + 1) % Game.SPEEDS.size()))
	var sv := VBoxContainer.new()
	sv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_theme_constant_override("separation", 4)
	var fast := Icons.icon_rect("fast", UI.C_TEXT, 22)
	fast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sv.add_child(fast)
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 3)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in Game.SPEEDS.size():
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(6, 6 + i * 2)
		pip.size_flags_vertical = Control.SIZE_SHRINK_END
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		speed_pips.append(pip)
		pips.add_child(pip)
	sv.add_child(pips)
	speed_btn.add_child(sv)
	h.add_child(speed_btn)
	_pin(p, Control.PRESET_BOTTOM_LEFT, Vector2(EDGE, EDGE))
	hud.add_child(p)


## الرصيف السفلي: خمسة أزرار كبيرة تفتح اللوحات، تحت إبهام اليد اليمنى
func _build_dock() -> void:
	dock = PanelContainer.new()
	dock.add_theme_stylebox_override("panel", UI.float_box(18, 4))
	var h := UI.row()
	h.add_theme_constant_override("separation", 2)
	dock.add_child(h)
	for t in DOCK_TABS:
		var b := Button.new()
		b.theme_type_variation = "FlatButton"
		b.custom_minimum_size = Vector2(DOCK_W, BIG)
		b.tooltip_text = TAB_TITLES[t]
		b.toggle_mode = true
		b.pressed.connect(_toggle_sheet.bind(t))
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 1)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icons.icon_rect(TAB_ICONS[t], UI.C_MUTED, 24)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.name = "Icon"
		v.add_child(ic)
		var l := UI.label(DOCK_TITLES[t], UI.C_MUTED, 13)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.name = "Text"
		v.add_child(l)
		# شارة صغيرة للعدد (مثل حروب جارية أو بحث متاح)
		var badge := Label.new()
		badge.name = "Badge"
		badge.visible = false
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", Color.WHITE)
		var bs := StyleBoxFlat.new()
		bs.bg_color = UI.C_BAD
		bs.set_corner_radius_all(8)
		bs.content_margin_left = 5
		bs.content_margin_right = 5
		badge.add_theme_stylebox_override("normal", bs)
		badge.position = Vector2(DOCK_W * 0.5 + 6, 3)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		b.add_child(badge)
		dock_btns[t] = b
		h.add_child(b)
	_pin(dock, Control.PRESET_BOTTOM_RIGHT, Vector2(EDGE, EDGE))
	hud.add_child(dock)


## أدوات الخريطة على حافتها اليسرى: الطبقات، والتكبير والتصغير
func _build_map_tools() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.float_box(14, 4))
	var v := UI.col()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	layer_btn = _pill_button("layers", "", _toggle_layers, "طبقات الخريطة")
	layer_btn.custom_minimum_size = Vector2(TOUCH, TOUCH)
	v.add_child(layer_btn)
	var zin := _pill_button("", "+", func(): map.zoom_by(1.5), "تكبير")
	var zout := _pill_button("", "−", func(): map.zoom_by(1.0 / 1.5), "تصغير")
	for z in [zin, zout]:
		z.custom_minimum_size = Vector2(TOUCH, TOUCH)
		z.add_theme_font_size_override("font_size", 22)
		v.add_child(z)
	var home := _pill_button("capital", "", _go_home, "العودة إلى دولتك")
	home.custom_minimum_size = Vector2(TOUCH, TOUCH)
	v.add_child(home)
	_pin(p, Control.PRESET_CENTER_LEFT, Vector2(EDGE, 0))
	hud.add_child(p)

	# قائمة الطبقات: تظهر بجانب الزر
	layers_pop = PanelContainer.new()
	layers_pop.add_theme_stylebox_override("panel", UI.float_box(14, 8))
	layers_pop.visible = false
	var lv := UI.col()
	lv.add_theme_constant_override("separation", 2)
	layers_pop.add_child(lv)
	lv.add_child(UI.label("طبقة الخريطة", UI.C_MUTED, 13))
	var group := ButtonGroup.new()
	for i in LAYERS.size():
		var b := UI.button(LAYERS[i][0], _pick_layer.bind(i), LAYERS[i][1], "FlatButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.custom_minimum_size = Vector2(190, TOUCH - 4)
		lv.add_child(b)
	_pin(layers_pop, Control.PRESET_CENTER_LEFT, Vector2(EDGE + TOUCH + 18, 0))
	hud.add_child(layers_pop)

	# مفتاح الطبقة الحالية: يظهر فقط في الطبقات غير السياسية
	legend_panel = PanelContainer.new()
	legend_panel.add_theme_stylebox_override("panel", UI.float_box(12, 10))
	legend_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_panel.visible = false
	legend_box = UI.col()
	legend_box.add_theme_constant_override("separation", 4)
	legend_panel.add_child(legend_box)
	_pin(legend_panel, Control.PRESET_TOP_LEFT, Vector2(EDGE, EDGE + TOUCH + 22))
	hud.add_child(legend_panel)


func _go_home() -> void:
	if Game.is_running():
		map.focus_country(Game.sim.state["player"])


func _toggle_layers() -> void:
	layers_pop.visible = not layers_pop.visible
	if layers_pop.visible:
		alerts_pop.visible = false


func _pick_layer(i: int) -> void:
	map.set_layer(i)
	layers_pop.visible = false
	layer_btn.icon = Icons.tex(LAYERS[i][1], UI.C_ACCENT_TEXT if i != 0 else UI.C_TEXT, 48)
	_update_legend()


## بطاقة السياق: ما لمسته على الخريطة وأهم أفعاله، فوق الرصيف
func _build_context_card() -> void:
	ctx_card = PanelContainer.new()
	ctx_card.add_theme_stylebox_override("panel", UI.float_box(16, 12))
	ctx_card.visible = false
	ctx_card.custom_minimum_size = Vector2(CTX_W, 0)
	ctx_box = UI.col()
	ctx_box.add_theme_constant_override("separation", 8)
	ctx_card.add_child(ctx_box)
	_pin(ctx_card, Control.PRESET_BOTTOM_RIGHT, Vector2(EDGE, EDGE + BIG + 20))
	hud.add_child(ctx_card)


## اللوحة: ترتفع من الرصيف وتغطي جانب الشاشة فقط، فتبقى الخريطة ظاهرة للمس الدول
func _build_sheet() -> void:
	sheet = PanelContainer.new()
	var st := UI.float_box(18, 0, UI.C_SIDE)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 6
	st.content_margin_bottom = 10
	sheet.add_theme_stylebox_override("panel", st)
	sheet.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	sheet.add_child(v)
	# مقبض السحب: اسحب للأسفل للإغلاق
	var grip := Control.new()
	grip.custom_minimum_size = Vector2(0, 14)
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.draw.connect(func():
		var w := 44.0
		grip.draw_rect(Rect2((grip.size.x - w) * 0.5, 5, w, 4), UI.C_LINE_2))
	grip.gui_input.connect(_on_sheet_drag)
	v.add_child(grip)
	var head := UI.row()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.gui_input.connect(_on_sheet_drag)
	panel_icon = TextureRect.new()
	panel_icon.custom_minimum_size = Vector2(26, 26)
	panel_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(panel_icon)
	panel_title = UI.title("", 20)
	panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(panel_title)
	var close := _pill_button("close", "", _close_sheet, "إغلاق")
	close.custom_minimum_size = Vector2(TOUCH, TOUCH)
	head.add_child(close)
	v.add_child(head)
	var line := ColorRect.new()
	line.color = UI.C_LINE_2
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)

	tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	for i in TAB_TITLES.size():
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box := UI.col()
		box.add_theme_constant_override("separation", 10)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(box)
		tabs.add_child(scroll)
		touch_scroll.add(scroll)
		tab_boxes.append(box)
	tabs.tab_changed.connect(_on_tab_changed)

	eco_controls = UI.col()
	eco_info = UI.col()
	tab_boxes[Tab.ECONOMY].add_child(eco_controls)
	tab_boxes[Tab.ECONOMY].add_child(eco_info)
	_build_economy_controls()

	army_controls = UI.col()
	army_info = UI.col()
	tab_boxes[Tab.ARMY].add_child(army_info)
	tab_boxes[Tab.ARMY].add_child(army_controls)
	_build_army_controls()
	v.layout_direction = Control.LAYOUT_DIRECTION_RTL
	hud.add_child(sheet)
	_layout_sheet()
	resized.connect(_layout_sheet)
	_on_tab_changed(0)


## حجم اللوحة: من تحت الشريط العلوي إلى فوق الرصيف، بعرض نصف الشاشة تقريباً على جهة البداية
func _layout_sheet() -> void:
	if sheet == null:
		return
	var vp := get_viewport_rect().size
	var w := clampf(vp.x * 0.46, minf(420.0, vp.x - 24.0), 660.0)
	sheet.anchor_left = 1.0
	sheet.anchor_right = 1.0
	sheet.anchor_top = 0.0
	sheet.anchor_bottom = 1.0
	sheet.offset_right = -EDGE
	sheet.offset_left = -EDGE - w
	sheet.offset_top = EDGE + TOUCH + 16
	sheet.offset_bottom = -(EDGE + BIG + 20)


func _on_sheet_drag(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_sheet_drag_y = mb.global_position.y
			elif _sheet_drag_y >= 0.0:
				var dy := mb.global_position.y - _sheet_drag_y
				_sheet_drag_y = -1.0
				if dy > 50.0:
					_close_sheet()
				else:
					_slide_sheet(0.0)
	elif ev is InputEventMouseMotion and _sheet_drag_y >= 0.0:
		var dy := maxf(0.0, (ev as InputEventMouseMotion).global_position.y - _sheet_drag_y)
		sheet.position.y = _sheet_rest_y + dy


func _slide_sheet(from_dy: float) -> void:
	_layout_sheet()
	_sheet_rest_y = sheet.position.y
	if _sheet_tw != null:
		_sheet_tw.kill()
	sheet.position.y = _sheet_rest_y + from_dy
	_sheet_tw = create_tween()
	_sheet_tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sheet_tw.tween_property(sheet, "position:y", _sheet_rest_y, 0.16)


## الضغط على زر اللوحة المفتوحة يغلقها، وعلى غيرها يفتحها عليه
func _toggle_sheet(t: int) -> void:
	if sheet.visible and tabs.current_tab == t:
		_close_sheet()
		return
	_open_tab(t)


func _open_tab(i: int) -> void:
	var was_open := sheet.visible
	sheet.visible = true
	ctx_card.visible = false
	alerts_pop.visible = false
	layers_pop.visible = false
	if tabs.current_tab != i:
		tabs.current_tab = i
	else:
		_on_tab_changed(i)
	if not was_open:
		_slide_sheet(sheet.size.y * 0.35)


func _close_sheet() -> void:
	if not sheet.visible:
		return
	_sheet_drag_y = -1.0
	if _sheet_tw != null:
		_sheet_tw.kill()
	_sheet_tw = create_tween()
	_sheet_tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_sheet_tw.tween_property(sheet, "modulate:a", 0.0, 0.12)
	_sheet_tw.tween_callback(func():
		sheet.visible = false
		sheet.modulate.a = 1.0
		_layout_sheet()
		_sync_dock())
	if not ctx.is_empty():
		_show_context()


func _on_tab_changed(t: int) -> void:
	_dirty = true
	if panel_title != null:
		panel_title.text = TAB_TITLES[t]
		panel_icon.texture = Icons.tex(TAB_ICONS[t], UI.C_ACCENT_TEXT, 48)
	_sync_dock()


func _sync_dock() -> void:
	for t in dock_btns:
		var b: Button = dock_btns[t]
		var on: bool = sheet != null and sheet.visible and tabs.current_tab == t
		b.set_pressed_no_signal(on)
		var col: Color = UI.C_ACCENT_TEXT if on else UI.C_MUTED
		var v: Control = b.get_child(0)
		(v.get_node("Icon") as TextureRect).texture = Icons.tex(TAB_ICONS[t], col, 48)
		(v.get_node("Text") as Label).add_theme_color_override("font_color", col)


## التنبيهات: قائمة منسدلة من الجرس بأهم ما يحتاج قرارك
func _build_alerts() -> void:
	alerts_pop = PanelContainer.new()
	alerts_pop.add_theme_stylebox_override("panel", UI.float_box(14, 10))
	alerts_pop.visible = false
	alerts_pop.custom_minimum_size = Vector2(CTX_W + 20, 0)
	advisor_box = UI.col()
	advisor_box.add_theme_constant_override("separation", 6)
	alerts_pop.add_child(advisor_box)
	_pin(alerts_pop, Control.PRESET_TOP_LEFT, Vector2(EDGE, EDGE + TOUCH + 18))
	hud.add_child(alerts_pop)


func _toggle_alerts() -> void:
	alerts_pop.visible = not alerts_pop.visible
	layers_pop.visible = false
	if alerts_pop.visible:
		_update_advisor()


## مفتاح ألوان الطبقة الحالية
func _update_legend() -> void:
	if legend_box == null:
		return
	UI.clear(legend_box)
	var rows: Array = []
	match map.layer:
		1:
			rows = [[MapView.pal("SCALE_LO"), "قوة ضعيفة"], [MapView.pal("POWER_HI"), "قوة كبيرة (تقدير)"]]
		2:
			rows = [[MapView.pal("SCALE_LO"), "اقتصاد صغير"], [MapView.pal("ECON_HI"), "اقتصاد كبير"]]
		3:
			rows = [[MapView.pal("STAB_LO"), "غير مستقرة"], [MapView.pal("STAB_HI"), "مستقرة"], [MapView.pal("SCALE_LO"), "غير معروفة"]]
		4:
			rows = [[MapView.pal("RES_ENERGY"), "نفط وغاز"], [MapView.pal("RES_MINERAL"), "معادن ويورانيوم"], [MapView.pal("RES_NONE"), "فقيرة بالموارد"]]
		5:
			rows = [[MapView.pal("RANGE_BOTH"), "طيرانك وصواريخك"], [MapView.pal("RANGE_AIR"), "طيرانك فقط"], [MapView.pal("RANGE_MIS"), "صواريخك فقط"]]
	legend_panel.visible = not rows.is_empty()
	if rows.is_empty():
		return
	legend_box.add_child(UI.label("طبقة " + LAYERS[map.layer][0], UI.C_TEXT, 14))
	for r in rows:
		var h := UI.row()
		h.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = r[0]
		sw.custom_minimum_size = Vector2(16, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		var ll := UI.label(r[1], UI.C_MUTED, 13)
		ll.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(ll)
		legend_box.add_child(h)


## عند التمرير بالمؤشر (الكمبيوتر فقط): بطاقة صغيرة باسم المنطقة ومالكها
func _on_map_hover(rid: String, pos: Vector2) -> void:
	if rid == "" or not Game.is_running() or mobile or not map.move_ids.is_empty():
		hover_card.visible = false
		return
	var s = Game.sim
	var info: Dictionary = s.db.regions[rid]
	var r: Dictionary = s.state["regions"][rid]
	var t: String = info["name_ar"] + ("  ★" if info["capital"] else "")
	var owner: String = r["owner"]
	if owner != r["core"]:
		t += "\n%s · تحتلها %s" % [s.country(r["core"])["name_ar"], s.country(owner)["name_ar"]]
	else:
		t += "\n" + String(s.country(owner)["name_ar"])
	hover_label.text = t
	hover_card.visible = true
	hover_card.reset_size()
	var p := pos + Vector2(18, 18)
	if p.x + hover_card.size.x > size.x:
		p.x = pos.x - hover_card.size.x - 12
	if p.y + hover_card.size.y > size.y:
		p.y = pos.y - hover_card.size.y - 12
	hover_card.position = p


## عنوان دولة: علمها واسمها
func _country_title(c: Dictionary) -> HBoxContainer:
	var h := UI.row()
	h.add_theme_constant_override("separation", 10)
	h.add_child(Flags.rect(c.get("flag", ""), 40))
	h.add_child(UI.title(c["name_ar"], 22))
	return h


# ================================================================== بطاقة السياق

## لمس قرب عاصمة في البحر: نعامله كلمس منطقة العاصمة
func _on_country_selected(id: String) -> void:
	if map.selected_region == "" and Game.is_running():
		var cap: String = Territory.capital_region(Game.sim, id)
		if Game.sim.state["regions"].has(cap):
			_on_region_clicked(cap)


## تحريك فرقة من قائمة الجيش: تُغلق اللوحة وتظهر الوجهات على الخريطة
func _move_from_list(did: int) -> void:
	var d: Dictionary = Divisions.find(Game.sim, did)
	if d.is_empty() or int(d["eta"]) >= 0:
		_toast("الفرقة في طريقها الآن.")
		return
	_close_sheet()
	var info: Dictionary = Game.sim.db.regions[d["region"]]
	map.focus_point(float(info["lon"]), float(info["lat"]))
	selected_region = d["region"]
	map.selected_region = d["region"]
	_start_move([did], d["region"])


func _on_region_clicked(rid: String) -> void:
	var s = Game.sim
	hover_card.visible = false
	alerts_pop.visible = false
	layers_pop.visible = false
	# وضع التحريك: لمس وجهة مظللة يحرك القوات فوراً
	if not map.move_ids.is_empty():
		_move_to(rid)
		return
	selected_region = rid
	selected = s.state["regions"][rid]["owner"]
	map.selected = selected
	map.selected_region = rid
	# لوحة العلاقات أو الاستخبارات مفتوحة: تتبدل للدولة الملموسة بدل إغلاقها
	if sheet.visible and tabs.current_tab in [Tab.DIPLOMACY, Tab.INTEL] and selected != s.state["player"]:
		_dirty = true
		return
	if sheet.visible:
		_close_sheet()
	ctx = {"kind": "region", "rid": rid}
	_show_context()


func _on_units_tapped(rid: String, owner: String, ids: Array) -> void:
	var s = Game.sim
	alerts_pop.visible = false
	if sheet.visible:
		_close_sheet()
	selected_region = rid
	map.selected_region = rid
	if owner == s.state["player"] and ids.is_empty():
		# قواتك الثابتة: ندخل وضع التحريك مباشرة (لمسة واحدة ثم لمسة الوجهة)
		var mine: Array = []
		for d in Divisions.of(s, owner):
			if d["region"] == rid and int(d["eta"]) < 0:
				mine.append(int(d["id"]))
		if not mine.is_empty():
			_start_move(mine, rid)
			return
	ctx = {"kind": "units", "rid": rid, "owner": owner, "ids": ids}
	_show_context()


func _on_empty_tapped() -> void:
	if not map.move_ids.is_empty():
		_cancel_move()
		return
	alerts_pop.visible = false
	layers_pop.visible = false
	if sheet.visible:
		_close_sheet()
	ctx = {}
	selected_region = ""
	map.selected_region = ""
	ctx_card.visible = false


func _start_move(ids: Array, from_rid: String) -> void:
	move_division = int(ids[0])
	map.set_move(ids, from_rid)
	ctx = {"kind": "move", "rid": from_rid, "ids": ids}
	_show_context()


func _cancel_move() -> void:
	move_division = -1
	map.clear_move()
	ctx = {"kind": "region", "rid": selected_region} if selected_region != "" else {}
	_show_context()


func _move_to(rid: String) -> void:
	var s = Game.sim
	var ids: Array = map.move_ids.duplicate()
	if rid == map.move_from:
		_cancel_move()
		return
	if not map.move_reach.has(rid):
		var d0: Dictionary = Divisions.find(s, int(ids[0]))
		var why: String = Divisions.can_move(s, d0, rid) if not d0.is_empty() else "فرقة غير موجودة."
		if why != "":
			_toast(why)
			return
	var moved := 0
	var err := ""
	for did in ids:
		var e: String = Divisions.move(s, int(did), rid)
		if e == "":
			moved += 1
		else:
			err = e
	map.clear_move()
	move_division = -1
	if moved > 0:
		var d: Dictionary = Divisions.find(s, int(ids[0]))
		_toast("تتحرك %s إلى %s · %d يوماً" % ["فرقة" if moved == 1 else "%d فرق" % moved, s.db.regions[rid]["name_ar"], int(d["eta"]) - int(s.state["day"])])
		if Game.paused:
			Game.set_paused(false)
	else:
		_toast(err)
	ctx = {}
	ctx_card.visible = false
	_dirty = true


func _show_context() -> void:
	UI.clear(ctx_box)
	if ctx.is_empty() or not Game.is_running():
		ctx_card.visible = false
		return
	match String(ctx["kind"]):
		"region": _ctx_region(ctx["rid"])
		"units": _ctx_units(ctx["rid"], ctx["owner"], ctx["ids"])
		"move": _ctx_move(ctx["rid"], ctx["ids"])
	ctx_card.visible = ctx_box.get_child_count() > 0 and not sheet.visible
	ctx_card.reset_size()


## رأس البطاقة: العلم والاسم، وسطر فرعي، وزر إغلاق
func _ctx_head(c: Dictionary, sub: String) -> void:
	var h := UI.row()
	h.add_theme_constant_override("separation", 10)
	h.add_child(Flags.rect(c.get("flag", ""), 34))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.title(c["name_ar"], 18)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	tv.add_child(t)
	if sub != "":
		var sl := UI.label(sub, UI.C_MUTED, 13)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tv.add_child(sl)
	h.add_child(tv)
	var x := _pill_button("close", "", _on_empty_tapped, "إغلاق")
	x.custom_minimum_size = Vector2(TOUCH - 6, TOUCH - 6)
	h.add_child(x)
	ctx_box.add_child(h)


## سطر أرقام قصير: [أيقونة، قيمة، لون، تلميح]
func _ctx_stats(items: Array) -> void:
	var h := UI.row()
	h.add_theme_constant_override("separation", 14)
	for it in items:
		var cell := UI.row()
		cell.add_theme_constant_override("separation", 4)
		cell.tooltip_text = it[3] if it.size() > 3 else ""
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(Icons.icon_rect(it[0], it[2], 16))
		var l := UI.label(it[1], it[2], 14)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		cell.add_child(l)
		h.add_child(cell)
	ctx_box.add_child(h)


## أزرار البطاقة: [نص، دالة، أيقونة، نوع]. الأول هو الفعل الرئيسي
func _ctx_actions(items: Array) -> void:
	var g := GridContainer.new()
	g.columns = 2 if items.size() > 1 else 1
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for it in items:
		var b := UI.button(it[0], it[1], it[2] if it.size() > 2 else "", it[3] if it.size() > 3 else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, TOUCH)
		b.add_theme_constant_override("icon_max_width", 20)
		b.clip_text = true
		g.add_child(b)
	ctx_box.add_child(g)


func _ctx_region(rid: String) -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	var info: Dictionary = s.db.regions[rid]
	var r: Dictionary = s.state["regions"][rid]
	var owner: String = r["owner"]
	var c: Dictionary = s.country(owner)
	var sub: String = info["name_ar"] + ("  ★ العاصمة" if info["capital"] else "")
	if owner != r["core"]:
		sub += " · محتلة من %s" % s.country(r["core"])["name_ar"]
	_ctx_head(c, sub)
	var my_here: Array = []
	for d in Divisions.of(s, pid):
		if d["region"] == rid and int(d["eta"]) < 0:
			my_here.append(int(d["id"]))
	var fac: Dictionary = info.get("facilities", {})
	if owner == pid:
		_ctx_stats([["people", "%s م" % String.num(float(r["pop"]), 1), UI.C_TEXT, "السكان بالمليون"],
			["economy", UI.money_short(float(r["gdp"]) * Territory.efficiency(r)), UI.C_TEXT, "ناتج المنطقة السنوي"],
			["army", "%d فرق" % my_here.size(), UI.C_FRIENDLY if not my_here.is_empty() else UI.C_MUTED, "فرقك المتمركزة هنا"]])
		_ctx_facilities(rid, fac, r, false)
		var acts: Array = []
		if not my_here.is_empty():
			acts.append(["حرّك القوات", _start_move.bind(my_here, rid), "move", "PrimaryButton"])
		acts.append(["ملف الدولة", func(): _open_tab(Tab.STATE), "details"])
		_ctx_actions(acts)
		return
	var rel: float = s.relation(pid, owner)
	var at_war: bool = not s.war_between(pid, owner).is_empty()
	var est: Dictionary = Intel.estimate(s, pid, owner, s.military_power(c), "power")
	var mine: float = s.military_power(s.player())
	var ratio := float(est["value"]) / maxf(1.0, mine)
	var ratio_txt := ("أقوى ×%s" % String.num(ratio, 1)) if ratio >= 1.15 else (("أضعف ×%s" % String.num(1.0 / maxf(ratio, 0.01), 1)) if ratio <= 0.87 else "متكافئة")
	if not est["exact"]:
		ratio_txt = "≈ " + ratio_txt
	var stats: Array = [["diplomacy", "%d" % int(rel), UI.C_GOOD if rel >= 0.0 else UI.C_BAD, "العلاقة معك من −100 إلى 100"],
		["army", ratio_txt, UI.C_BAD if ratio >= 1.15 else (UI.C_GOOD if ratio <= 0.87 else UI.C_TEXT), "قوتها العسكرية مقارنة بقوتك (تقدير حسب رؤيتك)"]]
	if at_war:
		stats.append(["war", "حرب", UI.C_BAD, "أنتما في حرب"])
	elif owner in s.allies(pid):
		stats.append(["alliance", "حليف", UI.C_FRIENDLY, "حليفك"])
	_ctx_stats(stats)
	_ctx_facilities(rid, fac, r, at_war)
	var acts2: Array = []
	if at_war:
		acts2.append(["عرض السلام", func(): _do(s.propose_peace(pid, owner), "قُبل السلام."), "peace", "PrimaryButton"])
	else:
		acts2.append(["تحسين العلاقات", func(): _do(s.improve_relations(pid, owner), "تحسنت العلاقات."), "handshake", "PrimaryButton"])
		if not Market.has_pact(s, pid, owner):
			acts2.append(["اتفاقية تجارية", func(): _do(Market.sign_pact(s, pid, owner), "وُقعت الاتفاقية التجارية."), "trade"])
		if not (owner in s.allies(pid)):
			acts2.append(["إعلان الحرب", func(): _confirm_war(owner), "war", "DangerButton"])
	acts2.append(["كل الخيارات", func(): _open_tab(Tab.DIPLOMACY), "details"])
	_ctx_actions(acts2)


## منشآت المنطقة كأيقونات؛ في الحرب تصبح أزرار ضرب مع فرصة النجاح
func _ctx_facilities(rid: String, fac: Dictionary, r: Dictionary, can_strike: bool) -> void:
	if fac.is_empty():
		return
	var s = Game.sim
	var pid: String = s.state["player"]
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	for t in Territory.FACILITY_TYPES:
		if int(fac.get(t, 0)) <= 0:
			continue
		var dmg := int(r.get("damaged", {}).get(t, 0))
		var col: Color = UI.C_BAD if dmg > 0 else UI.C_TEXT
		if can_strike and dmg == 0:
			var pct := int(s.strike_chance(pid, rid) * 100.0)
			var b := UI.button("اضرب %s %d%%" % [Territory.FACILITY_NAMES[t], pct], _strike.bind(rid, t), t, "DangerButton")
			b.add_theme_constant_override("icon_max_width", 18)
			b.custom_minimum_size = Vector2(0, TOUCH - 4)
			b.tooltip_text = "ضربة بـ %d صاروخاً" % int(Simulation.STRIKE_MISSILES)
			h.add_child(b)
		else:
			# منشأة غير قابلة للضرب: أيقونة صغيرة فقط، واسمها في التلميح
			var ic := Icons.icon_rect(t, col, 20)
			ic.tooltip_text = Territory.FACILITY_NAMES[t] + (" · معطلة %d أشهر" % dmg if dmg > 0 else "")
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			var cell := PanelContainer.new()
			var cs := StyleBoxFlat.new()
			cs.bg_color = Color(col, 0.10)
			cs.set_corner_radius_all(8)
			cs.set_content_margin_all(5)
			cell.add_theme_stylebox_override("panel", cs)
			cell.tooltip_text = ic.tooltip_text
			cell.add_child(ic)
			h.add_child(cell)
	ctx_box.add_child(h)


func _ctx_units(rid: String, owner: String, ids: Array) -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	var c: Dictionary = s.country(owner)
	var divs: Array = []
	for d in s.state["divisions"]:
		if d["owner"] == owner and ((ids.is_empty() and d["region"] == rid and int(d["eta"]) < 0) or int(d["id"]) in ids):
			divs.append(d)
	if divs.is_empty():
		ctx = {}
		return
	var str_sum := 0.0
	for d in divs:
		str_sum += float(d["strength"])
	var avg := str_sum / float(divs.size())
	var d0: Dictionary = divs[0]
	var sub := "%d فرق في %s" % [divs.size(), s.db.regions[rid]["name_ar"]]
	if int(d0["eta"]) >= 0:
		sub = "%d فرق تتحرك إلى %s" % [divs.size(), s.db.regions[d0["target"]]["name_ar"]]
	_ctx_head(c, sub)
	var stats: Array = [["army", "جاهزية %d%%" % int(avg * 100.0), UI.C_GOOD if avg >= 0.7 else (UI.C_WARN if avg >= 0.45 else UI.C_BAD), "متوسط جاهزية الفرق"]]
	if int(d0["eta"]) >= 0:
		stats.append(["calendar", "تصل بعد %d يوماً" % maxi(1, int(d0["eta"]) - int(s.state["day"])), UI.C_TEXT])
	_ctx_stats(stats)
	var acts: Array = []
	if owner == pid and int(d0["eta"]) < 0:
		var all_ids: Array = divs.map(func(d): return int(d["id"]))
		acts.append(["حرّك الكل", _start_move.bind(all_ids, rid), "move", "PrimaryButton"])
		if divs.size() > 1:
			acts.append(["فرقة واحدة", _start_move.bind([all_ids[0]], rid), "unit"])
	acts.append(["الجيش" if owner == pid else "العلاقات", func(): _open_tab(Tab.ARMY if owner == pid else Tab.DIPLOMACY), "details"])
	_ctx_actions(acts)


func _ctx_move(rid: String, ids: Array) -> void:
	var s = Game.sim
	var h := UI.row()
	h.add_theme_constant_override("separation", 10)
	h.add_child(Icons.icon_rect("move", UI.C_FRIENDLY, 28))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.title("حرّك %s من %s" % ["فرقة" if ids.size() == 1 else "%d فرق" % ids.size(), s.db.regions[rid]["name_ar"]], 17))
	var hint := UI.label("المس منطقة مظللة بالأزرق لتتحرك إليها.", UI.C_MUTED, 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	tv.add_child(hint)
	h.add_child(tv)
	ctx_box.add_child(h)
	_ctx_actions([["إلغاء", _cancel_move, "close"]])


func _build_start_screen() -> void:
	start_screen = Control.new()
	start_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(start_screen)
	# الخريطة تظهر خافتة خلف الشاشة الأولى
	var shade := ColorRect.new()
	shade.color = Color(UI.C_INK, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_screen.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_screen.add_child(center)
	var v := UI.col()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(minf(1040.0, get_viewport_rect().size.x - 32.0), 0)
	center.add_child(v)
	var eyebrow := UI.label("غرفة العمليات المشتركة · تشرين الأول 2026", UI.C_ACCENT, 15)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(eyebrow)
	var t := UI.title("الحرب العالمية الثالثة", 34 if mobile else 46)
	t.add_theme_color_override("font_color", UI.C_TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UI.label("العالم على حافة الحرب. اختر الدولة التي ستقودها: اقتصادها وجيشها وتحالفاتها وعداواتها كما هي اليوم تقريباً.", UI.C_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	# الصعوبة: أزرار متجاورة، ومتابعة آخر لعبة
	var top := UI.row()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	var dl := UI.label("الصعوبة", UI.C_MUTED)
	dl.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(dl)
	var diff_group := ButtonGroup.new()
	var diffs := ["سهل", "عادي", "صعب"]
	var diff_tips := ["الذكاء الاصطناعي أقل جرأة وتسليحاً", "التجربة المقصودة", "الدول تستهدفك أسرع وتتسلح أكثر"]
	var diff_btns: Array = []
	for i in 3:
		var b := UI.button(diffs[i], func(): pass)
		b.toggle_mode = true
		b.button_group = diff_group
		b.button_pressed = i == 1
		b.tooltip_text = diff_tips[i]
		b.custom_minimum_size = Vector2(80, 0)
		diff_btns.append(b)
		top.add_child(b)
	var diff_value := func() -> int:
		for i in diff_btns.size():
			if diff_btns[i].button_pressed:
				return i
		return 1
	if Game.has_save() or Game.has_save(Game.AUTOSAVE_PATH):
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(24, 0)
		top.add_child(gap)
		top.add_child(UI.button("متابعة آخر لعبة", func():
			if not Game.load_game():
				Game.load_game(Game.AUTOSAVE_PATH), "save", "PrimaryButton"))
	v.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(520.0, get_viewport_rect().size.y - 280.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	touch_scroll.add(scroll)
	var grid := GridContainer.new()
	grid.columns = 2 if mobile else 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var list: Array = Game.db.countries.duplicate()
	list.sort_custom(func(a, b): return float(a["gdp"]) > float(b["gdp"]))
	for c in list:
		var cid: String = c["id"]
		grid.add_child(_country_card(c, func(): Game.start_new(cid, diff_value.call())))
	var note := UI.label("الأرقام تقديرات خاصة باللعبة من مصادر مفتوحة. سيناريو خيالي، والحدود حسب السيطرة الفعلية.", UI.C_MUTED, 13)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)


## بطاقة دولة في الشاشة الأولى: الاسم والرمز والاقتصاد والحكم وأبرز ما يميزها
func _country_card(c: Dictionary, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 112)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var head := UI.row()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UI.title(c["name_ar"], 18)
	nm.add_theme_color_override("font_color", UI.C_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	head.add_child(Flags.rect(c.get("flag", ""), 40))
	v.add_child(head)
	v.add_child(UI.label("%s · %s" % [UI.money(float(c["gdp"])), Game.db.governments[c["government"]]["name_ar"]], UI.C_MUTED, 13))
	var tags := PackedStringArray()
	if float(c["military"].get("nukes", 0)) > 0.0:
		tags.append("☢ نووية")
	if float(c["resources"].get("oil", 0)) >= 70.0:
		tags.append("نفطية")
	var allies: Array = []
	for aid in Game.db.alliances:
		if c["id"] in Game.db.alliances[aid]["members"]:
			allies.append(Game.db.alliances[aid]["name_ar"])
	if not allies.is_empty():
		tags.append(allies[0])
	if not tags.is_empty():
		v.add_child(UI.label(" · ".join(tags), UI.C_ACCENT, 13))
	for ch in v.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## مؤشر الاستعداد: 5 سلم، 4 توتر، 3 تهديد، 2 حرب، 1 خطر وجودي
func _readiness() -> Array:
	var s = Game.sim
	var pid: String = s.state["player"]
	var p: Dictionary = s.player()
	var wars: Array = s.wars_of(pid)
	if not wars.is_empty():
		var worst := 100.0
		for w in wars:
			worst = minf(worst, float(w["score"]) if pid in w["attackers"] else -float(w["score"]))
		if p.get("capital_fallen", false) or worst < -40.0 or int(s.state["global"]["nuclear_strikes"]) > 0:
			return [1, "خطر وجودي", Color("ff3b30")]
		return [2, "حرب", UI.C_BAD]
	var mine: float = s.bloc_power(pid)
	for oid in s.alive_ids():
		if oid == pid:
			continue
		var c: Dictionary = s.country(oid)
		if c.get("rival", "") == pid and Intel.visibility(s, pid, oid) >= 50.0:
			return [3, "تهديد", UI.C_WARN]
		if oid in p["neighbors"] and s.relation(pid, oid) < -50.0 and s.bloc_power(oid) > mine * 1.2:
			return [3, "تهديد", UI.C_WARN]
	for oid in p["neighbors"]:
		if not s.country(oid).is_empty() and s.relation(pid, oid) < -40.0:
			return [4, "توتر", UI.C_UNKNOWN]
	return [5, "سلم", UI.C_GOOD]


func _update_top() -> void:
	if not Game.is_running():
		return
	var s = Game.sim
	var p: Dictionary = s.player()
	lbl_country.text = p["name_ar"]
	country_flag.texture = Flags.tex(p.get("flag", ""))
	var rd: Array = _readiness()
	for i in ready_segs.size():
		# الدرجة 1 تملأ الخمس، والدرجة 5 تملأ واحدة
		ready_segs[i].color = rd[2] if i < 6 - int(rd[0]) else UI.C_SUNKEN
	lbl_ready.text = rd[1]
	lbl_ready.add_theme_color_override("font_color", rd[2])
	country_btn.tooltip_text = "ملف دولتك · الاستعداد %d من 5: %s" % [int(rd[0]), rd[1]]
	lbl_date.text = s.date_text()
	var b: Dictionary = p.get("last_budget", {})
	var bal := float(b.get("balance", 0.0))
	_set_stat(stat_money, "%s  %s%s" % [UI.money_short(float(p["treasury"])), "▲" if bal >= 0.0 else "▼", UI.money_short(absf(bal))], UI.C_GOOD if bal >= 0.0 else UI.C_BAD, "treasury")
	var st := float(p["stability"])
	_set_stat(stat_stab, "%d" % int(st), UI.C_GOOD if st >= 50.0 else (UI.C_WARN if st >= 30.0 else UI.C_BAD), "stability")
	var wn: int = s.wars_of(p["id"]).size()
	stat_war.visible = wn > 0
	_set_stat(stat_war, "%d %s" % [wn, "حرب" if wn == 1 else "حروب"], UI.C_BAD, "war")
	btn_pause.icon = Icons.tex("play" if Game.paused else "pause", UI.C_ON_ACCENT, 48)
	btn_pause.tooltip_text = ("تشغيل" if Game.paused else "إيقاف") + " (مسافة)"
	for i in speed_pips.size():
		speed_pips[i].color = UI.C_ACCENT if i <= Game.speed else UI.C_LINE_2
	speed_btn.tooltip_text = "السرعة %d من 5: %s (المس للتبديل، أو المفاتيح 1-5)" % [Game.speed + 1, _speed_text(Game.speed)]


func _set_stat(b: Button, text: String, color: Color, icon: String) -> void:
	b.text = text
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color)
	b.icon = Icons.tex(icon, color, 48)

func _build_economy_controls() -> void:
	eco_controls.add_child(UI.section("الضرائب والبحث", "invest"))
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
	army_controls.add_child(UI.section("التصنيع والشراء", "factory"))
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


func _on_game_started() -> void:
	start_screen.visible = false
	map.sim = Game.sim
	selected = Game.sim.state["player"]
	map.selected = selected
	map.focus_country(selected)
	_rebuild_buy_types()
	_sync_economy_controls()
	_update_legend()
	_dirty = true
	_refresh()
	if int(Game.sim.state["day"]) == 0 and not Game.welcomed:
		Game.welcomed = true
		var p: Dictionary = Game.sim.player()
		_show_dialog("مرحباً بك في غرفة العمليات",
			"أنت تقود %s. الوقت متوقف حتى تبدأ.\n\n• الزر الذهبي أسفل اليسار يشغّل الوقت، وبجانبه السرعة.\n• المس رقاقة قواتك الذهبية، ثم المس منطقة مظللة لتحريكها.\n• المس أي دولة لترى علاقتك وقوتها وأهم أفعالك معها.\n• الأزرار أسفل اليمين تفتح الاقتصاد والجيش والعلاقات والاستخبارات والبحث.\n• الجرس أعلى اليسار يجمع ما يحتاج قرارك." % p["name_ar"],
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
	elif key.keycode == KEY_ESCAPE:
		if not map.move_ids.is_empty():
			_cancel_move()
		elif sheet.visible:
			_close_sheet()
		else:
			_on_empty_tapped()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_5:
		_set_speed(int(key.keycode) - int(KEY_1))


func _speed_text(i: int) -> String:
	var spd: float = Game.SPEEDS[i]
	return "يوم في الثانية" if spd >= 1.0 else "%d يوماً في الثانية" % roundi(1.0 / spd)


func _set_speed(i: int) -> void:
	Game.set_speed(i)
	Game.set_paused(false)


func _step_one_day() -> void:
	if Game.is_running():
		Game.step_day()


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
	if ctx_card.visible and String(ctx.get("kind", "")) != "move":
		_show_context()
	if sheet.visible:
		_fill_current_tab()
	map.refresh()


func _fill_current_tab() -> void:
	match tabs.current_tab:
		Tab.STATE: _fill_state()
		Tab.ECONOMY: _fill_economy()
		Tab.ARMY: _fill_army()
		Tab.RESEARCH: _fill_research()
		Tab.DIPLOMACY: _fill_diplomacy()
		Tab.INTEL: _fill_intel()
		Tab.NEWS: _fill_news()
	map.refresh()


func _update_advisor() -> void:
	UI.clear(advisor_box)
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
	# الجرس: عدد الأمور العاجلة بلون أخطرها
	var urgent := 0
	for it in items:
		if int(it[0]) >= 60:
			urgent += 1
	var top_prio := int(items[0][0])
	var head_col: Color = UI.C_BAD if top_prio >= 85 else (UI.C_WARN if top_prio >= 60 else UI.C_MUTED)
	alerts_btn.text = str(urgent) if urgent > 0 else ""
	alerts_btn.icon = Icons.tex("bell", head_col, 48)
	alerts_btn.add_theme_color_override("font_color", head_col)
	alerts_btn.add_theme_color_override("font_hover_color", head_col)
	if not alerts_pop.visible:
		return
	var head := UI.row()
	var ht := UI.title("أمور تحتاجك", 17)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ht)
	head.add_child(UI.button("الأخبار", func(): _open_tab(Tab.NEWS), "news", "FlatButton"))
	advisor_box.add_child(head)
	for it in items.slice(0, 6):
		var tab_i: int = it[2]
		var target: String = it[3]
		var prio := int(it[0])
		var sev: Color = UI.C_BAD if prio >= 85 else (UI.C_WARN if prio >= 60 else (UI.C_FRIENDLY if prio > 0 else UI.C_GOOD))
		var icon: String = "warning" if prio >= 85 else TAB_ICONS[tab_i]
		if "الحرب" in String(it[1]):
			icon = "war"
		var btn := UI.button(it[1], _go_alert.bind(tab_i, target))
		btn.icon = Icons.tex(icon, sev, 36)
		btn.add_theme_constant_override("icon_max_width", 18)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(0, TOUCH)
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(sev, 0.08)
		cs.border_color = sev
		cs.border_width_right = 3
		cs.set_corner_radius_all(6)
		cs.content_margin_left = 8
		cs.content_margin_right = 10
		cs.content_margin_top = 6
		cs.content_margin_bottom = 6
		var ch: StyleBoxFlat = cs.duplicate()
		ch.bg_color = Color(sev, 0.16)
		btn.add_theme_stylebox_override("normal", cs)
		btn.add_theme_stylebox_override("hover", ch)
		btn.add_theme_stylebox_override("pressed", ch)
		advisor_box.add_child(btn)


func _go_alert(tab_i: int, target: String) -> void:
	alerts_pop.visible = false
	if target != "":
		selected = target
		map.selected = target
		map.focus_country(target)
	_open_tab(tab_i)
	_dirty = true


# ------------------------------------------------------------------ تبويب الدولة

func _fill_state() -> void:
	var box: VBoxContainer = tab_boxes[Tab.STATE]
	UI.clear(box)
	var s = Game.sim
	var pid: String = s.state["player"]
	var p: Dictionary = s.player()
	box.add_child(_country_title(p))
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

	box.add_child(UI.section("نظام الحكم", "state"))
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

	box.add_child(UI.section("السياسات", "check"))
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
	eco_info.add_child(UI.section("الاقتصاد", "economy"))
	eco_info.add_child(UI.kv("الناتج المحلي", UI.money(float(p["gdp"]))))
	eco_info.add_child(UI.kv("نصيب الفرد", "%s $" % s.fmt_num(Economy.gdp_per_capita(p))))
	eco_info.add_child(UI.kv("النمو السنوي", "%s%%" % UI.signed(Economy.growth_rate(s, p), 2)))
	eco_info.add_child(UI.kv("الخزينة", UI.money(float(p["treasury"]))))
	eco_info.add_child(UI.kv("الدين", "%s (%d%% من الناتج)" % [UI.money(float(p["debt"])), int(100.0 * float(p["debt"]) / float(p["gdp"]))]))
	eco_info.add_child(UI.kv("التضخم", "%.1f%%" % float(p["inflation"]), UI.C_BAD if float(p["inflation"]) > 8.0 else UI.C_TEXT))
	var b: Dictionary = p.get("last_budget", {})
	if not b.is_empty():
		eco_info.add_child(UI.sep())
		eco_info.add_child(UI.section("ميزانية الشهر الماضي", "treasury"))
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
	eco_info.add_child(UI.section("الموارد (من مناطقك)", "r_oil"))
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
	army_info.add_child(UI.section("القوات المسلحة", "army"))
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
		army_info.add_child(UI.section("خطوط الإنتاج", "factory"))
		for o in q:
			army_info.add_child(UI.kv("%s × %s" % [s.db.units[o["type"]]["name_ar"], s.fmt_num(o["count"])], "%d يوماً" % int(ceilf(float(o["days_left"]))), UI.C_MUTED))


# ------------------------------------------------------------------ تبويب البحث

func _fill_research() -> void:
	var box: VBoxContainer = tab_boxes[Tab.RESEARCH]
	UI.clear(box)
	var s = Game.sim
	var pid: String = s.state["player"]
	var p: Dictionary = s.player()
	box.add_child(UI.section("أجيال الأسلحة", "research"))
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
	box.add_child(UI.section("حروبك", "war"))
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
	box.add_child(UI.section("كل الحروب في العالم", "war"))
	if s.state["wars"].is_empty():
		box.add_child(UI.label("العالم في سلام هش.", UI.C_MUTED))
	for w in s.state["wars"]:
		var wr := UI.row()
		var ca: Dictionary = s.country(w["attackers"][0])
		var cd: Dictionary = s.country(w["defenders"][0])
		wr.add_child(Flags.rect(ca.get("flag", ""), 24))
		var al := UI.label(ca["name_ar"], UI.C_TEXT, 14)
		al.autowrap_mode = TextServer.AUTOWRAP_OFF
		wr.add_child(al)
		wr.add_child(Icons.icon_rect("war", UI.C_BAD, 16))
		wr.add_child(Flags.rect(cd.get("flag", ""), 24))
		var dl := UI.label(cd["name_ar"], UI.C_TEXT, 14)
		dl.autowrap_mode = TextServer.AUTOWRAP_OFF
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wr.add_child(dl)
		var sl := UI.label("%d" % int(w["score"]), UI.C_MUTED, 14)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		wr.add_child(sl)
		box.add_child(wr)


func _fill_selected(box: VBoxContainer, id: String) -> void:
	var s = Game.sim
	var pid: String = s.state["player"]
	var c: Dictionary = s.country(id)
	var rel: float = s.relation(pid, id)
	box.add_child(_country_title(c))
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
	v.add_child(UI.section(title, "region"))
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
	box.add_child(UI.section("الفئات الداخلية", "people"))
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
	box.add_child(UI.section("السوق العالمي", "market"))
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
	box.add_child(UI.section("الإمداد", "trade"))
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
	box.add_child(UI.section("مناطق %s (%d)" % [s.country(id)["name_ar"], core.size()], "region"))
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
	box.add_child(UI.section("الاستخبارات في %s" % c["name_ar"], "intel"))
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
	box.add_child(UI.section("مكافحة التجسس", "radar"))
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
	box.add_child(UI.section("شبكات التجسس", "network"))
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
	box.add_child(UI.section("ما نعرفه عن الأخطار", "warning"))
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
	box.add_child(UI.section("الفرق", "move"))
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
		var col := UI.C_MUTED
		if int(d["eta"]) >= 0:
			status = "تتحرك ← %s · %d يوماً" % [s.db.regions[d["target"]]["name_ar"], int(d["eta"]) - int(s.state["day"])]
			col = UI.C_WARN
		elif d["region"] in front:
			status = "على الجبهة"
			col = UI.C_BAD
		var c := UI.card(col)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		c.add_child(cv)
		var head := UI.row()
		head.add_child(Icons.icon_rect("army", UI.C_FRIENDLY, 18))
		var nm := UI.label("الفرقة %d" % int(d["id"]), UI.C_TEXT)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(nm)
		head.add_child(Icons.icon_rect("region", UI.C_MUTED, 14))
		var wl := UI.label(where, UI.C_MUTED, 14)
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(wl)
		var st := UI.label(status, col, 13)
		st.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(st)
		cv.add_child(head)
		var strength := float(d["strength"])
		cv.add_child(UI.label("الجاهزية %d%% · الخبرة %d%%" % [int(strength * 100.0), int(float(d["exp"]) * 100.0)], UI.C_MUTED, 13))
		cv.add_child(UI.bar(strength * 100.0, 100.0, UI.C_GOOD if strength >= 0.7 else (UI.C_WARN if strength >= 0.45 else UI.C_BAD)))
		var row := UI.row()
		var did := int(d["id"])
		var mv := UI.button("تحريك", _move_from_list.bind(did), "move")
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(mv)
		var show_on_map := func():
			var info: Dictionary = s.db.regions[Divisions.find(s, did)["region"]]
			map.selected_division = did
			map.focus_point(float(info["lon"]), float(info["lat"]))
		var where_btn := UI.button("على الخريطة", show_on_map, "region")
		row.add_child(where_btn)
		cv.add_child(row)
		box.add_child(c)
	if p.get("auto_deploy", true):
		box.add_child(UI.label("التحريك اليدوي يعمل مع التوزيع التلقائي، لكن التوزيع قد يعيد ترتيب الفرق. أوقفه لقيادة كاملة.", UI.C_MUTED, 13))


func _select_country(id: String) -> void:
	selected = id
	selected_region = ""
	map.selected = id
	map.selected_region = ""
	map.focus_country(id)
	_open_tab(Tab.DIPLOMACY)
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
	# ضباب الحرب: كلما قلت رؤيتك للعدو اتسع هامش الخطأ في التوقع
	var vis := Intel.visibility(s, pid, id)
	var band := maxf(0.0, (1.0 - vis / 60.0) * 0.25)
	var v := UI.col()
	v.add_child(UI.kv("سيدافع عنها", names, UI.C_BAD, "alliance"))
	v.add_child(UI.label("فرصتك المتوقعة في كل مرحلة من المعركة:", UI.C_MUTED, 14))
	for ph in [["الجو", "airbase", "air"], ["الصواريخ والمسيّرات والمدفعية", "target", "strike"], ["البحر", "port", "sea"], ["البر", "army", "land"]]:
		var val := float(f[ph[2]])
		var row := UI.row()
		row.add_child(Icons.icon_rect(ph[1], UI.C_MUTED, 18))
		var nm := UI.label(ph[0], UI.C_TEXT, 14)
		nm.custom_minimum_size = Vector2(190, 0)
		row.add_child(nm)
		if val < 0.0:
			row.add_child(UI.label("لا قوات بحرية", UI.C_MUTED, 14))
		else:
			var col: Color = UI.C_GOOD if val >= 0.6 else (UI.C_WARN if val >= 0.45 else UI.C_BAD)
			var b := UI.bar(val * 100.0, 100.0, col)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(b)
			var txt := "%d%%" % int(val * 100.0)
			if band > 0.0:
				txt = "%d–%d%%" % [int(clampf(val - band, 0.0, 1.0) * 100.0), int(clampf(val + band, 0.0, 1.0) * 100.0)]
			var pl := UI.label(txt, col, 14)
			pl.custom_minimum_size = Vector2(70, 0)
			row.add_child(pl)
		v.add_child(row)
	if band > 0.0:
		v.add_child(UI.label("رؤيتك لهذا العدو %d فقط، فالأرقام تقديرية. ابنِ شبكة تجسس لتوقع أدق." % int(vis), UI.C_WARN, 13))
	v.add_child(UI.sep())
	if int(f["weeks_to_win"]) > 0:
		v.add_child(UI.kv("التقدير", "نصر خلال %d أسبوعاً تقريباً" % int(f["weeks_to_win"]), UI.C_GOOD, "check"))
	else:
		v.add_child(UI.kv("التقدير", "الحرب لن تكون في صالحك", UI.C_BAD, "warning"))
	var mth: Dictionary = f.get("theater", {}).get(pid, {})
	if not mth.is_empty():
		v.add_child(UI.kv("فرقك على الجبهة", "%d من %d" % [int(mth["front_divisions"]), int(mth["divisions"])], UI.C_TEXT if int(mth["front_divisions"]) > 0 else UI.C_BAD, "army"))
		v.add_child(UI.kv("قواعدك الجوية في المدى", "%d%%" % int(float(mth["air"]) * 100.0), UI.C_TEXT, "range"))
		v.add_child(UI.kv("صواريخك", "في المدى" if float(mth["missiles"]) >= 1.0 else "خارج المدى", UI.C_TEXT if float(mth["missiles"]) >= 1.0 else UI.C_BAD, "target"))
		if int(mth["front_divisions"]) == 0:
			v.add_child(UI.label("لا فرق لك على الجبهة بعد: حرّكها أولاً أو فعّل التوزيع التلقائي.", UI.C_WARN, 13))
	if not f.get("land_front", true):
		v.add_child(UI.label("لا جبهة برية: التقدم يحتاج تفوقاً بحرياً للإنزال، والإمداد أضعف.", UI.C_WARN, 13))
	v.add_child(UI.label("الحرب تُخاض منطقة بمنطقة، وتخفض النمو والاستقرار، وتغضب حلفاء العدو.", UI.C_MUTED, 13))
	var do_war := func():
		s.declare_war(pid, id)
		_dirty = true
	_show_dialog("إعلان الحرب على %s؟" % s.country(id)["name_ar"], "", [
		{"text": "أعلن الحرب", "cb": do_war},
		{"text": "تراجع"},
	], v)


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
## نافذة عامة: buttons = [{text, cb?}]. الأيقونة تُستنتج من العنوان إن لم تُحدد.
func _show_dialog(title: String, text: String, buttons: Array, content: Control = null, icon: String = "") -> void:
	dialog_queue.append({"title": title, "text": text, "buttons": buttons, "content": content, "icon": icon})
	if not dialog_open:
		_next_dialog()


func _dialog_icon(title: String) -> Array:
	for pair in [["نووي", "nuke", UI.C_BAD], ["☢", "nuke", UI.C_BAD], ["إعلان الحرب", "war", UI.C_BAD], ["حرب", "war", UI.C_BAD], ["معركة", "war", UI.C_WARN],
			["سقوط", "warning", UI.C_BAD], ["انقلاب", "warning", UI.C_BAD], ["ثورة", "warning", UI.C_BAD], ["خطر", "warning", UI.C_BAD], ["غاضب", "warning", UI.C_WARN], ["يغلي", "warning", UI.C_WARN],
			["سلام", "peace", UI.C_GOOD], ["انتصار", "check", UI.C_GOOD], ["فوز", "check", UI.C_GOOD], ["تبعية", "check", UI.C_GOOD], ["ضم", "check", UI.C_GOOD],
			["هزيمة", "warning", UI.C_BAD], ["الاستسلام", "warning", UI.C_BAD], ["خسارة", "warning", UI.C_BAD],
			["ضربة", "target", UI.C_WARN], ["شبكة", "network", UI.C_FRIENDLY], ["عملية", "intel", UI.C_FRIENDLY], ["غامض", "intel", UI.C_WARN], ["نجحت", "intel", UI.C_GOOD], ["فشلت", "intel", UI.C_BAD],
			["أزمة", "market", UI.C_WARN], ["جفاف", "r_food", UI.C_WARN], ["ركود", "decline", UI.C_WARN], ["وباء", "warning", UI.C_WARN], ["زلزال", "warning", UI.C_WARN], ["اكتشاف", "r_oil", UI.C_GOOD],
			["حادث", "warning", UI.C_WARN], ["مرحباً", "advisor", UI.C_ACCENT], ["القائمة", "menu", UI.C_ACCENT], ["تقرير", "war", UI.C_ACCENT]]:
		if pair[0] in title:
			return [pair[1], pair[2]]
	return ["info", UI.C_ACCENT]


func _next_dialog() -> void:
	if dialog_queue.is_empty():
		dialog_open = false
		return
	dialog_open = true
	var d: Dictionary = dialog_queue.pop_front()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.06, 0.45 if UI.light else 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var ic: Array = _dialog_icon(d["title"])
	if d.get("icon", "") != "":
		ic[0] = d["icon"]
	var accent: Color = ic[1]
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = UI.C_DIALOG
	ps.border_color = Color(accent, 0.8)
	ps.set_border_width_all(1)
	ps.border_width_top = 4
	ps.set_corner_radius_all(8)
	ps.content_margin_left = 22
	ps.content_margin_right = 22
	ps.content_margin_top = 18
	ps.content_margin_bottom = 18
	ps.shadow_color = UI.C_SHADOW
	ps.shadow_size = 18
	panel.add_theme_stylebox_override("panel", ps)
	panel.custom_minimum_size = Vector2(minf(580.0, get_viewport_rect().size.x - 32.0), 0)
	center.add_child(panel)
	var v := UI.col()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := UI.row()
	head.add_theme_constant_override("separation", 12)
	head.add_child(Icons.icon_rect(ic[0], accent, 30))
	var t := UI.title(d["title"], 22)
	t.add_theme_color_override("font_color", UI.C_TEXT)
	head.add_child(t)
	v.add_child(head)
	var line := ColorRect.new()
	line.color = Color(accent, 0.3)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	if d["text"] != "":
		v.add_child(UI.label(d["text"]))
	if d["content"] != null:
		v.add_child(d["content"])
	var h := UI.row()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var first := true
	for b in d["buttons"]:
		var cb: Callable = b.get("cb", Callable())
		var label: String = b["text"]
		var variation := ""
		if label in ["أعلن الحرب", "أطلق"]:
			variation = "DangerButton"
		elif first and not (label in ["تراجع", "رفض", "إغلاق", "متابعة"]):
			variation = "PrimaryButton"
		first = false
		var btn := UI.button(label, func():
			dim.queue_free()
			if cb.is_valid():
				cb.call()
			_next_dialog(), "", variation)
		btn.custom_minimum_size = Vector2(110, 0)
		h.add_child(btn)


func _toast(text: String) -> void:
	var good := text.begins_with("تم") or text.contains("ارتفع") or text.contains("وُقعت") or text.contains("تتحرك") or text.contains("تحسنت") or text.contains("توسعت")
	var col: Color = UI.C_GOOD if good else UI.C_WARN
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UI.C_DIALOG
	st.border_color = col
	st.border_width_right = 3
	st.set_corner_radius_all(6)
	st.set_content_margin_all(10)
	st.shadow_color = UI.C_SHADOW
	st.shadow_size = 8
	p.add_theme_stylebox_override("panel", st)
	var h := UI.row()
	h.add_child(Icons.icon_rect("check" if good else "info", col, 18))
	var l := UI.label(text, UI.C_TEXT)
	l.custom_minimum_size = Vector2(340, 0)
	h.add_child(l)
	p.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(p)
	p.reset_size()
	var vp := get_viewport_rect().size
	p.position = Vector2((vp.x - p.size.x) * 0.5, EDGE + TOUCH + 18.0)
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
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
		{"text": "الوضع الفاتح" if not Game.light_theme else "الوضع الداكن", "cb": func(): Game.set_light_theme(not Game.light_theme)},
		{"text": "القائمة الرئيسية", "cb": _back_to_menu},
		{"text": "متابعة"},
	])


func _back_to_menu() -> void:
	Game.set_paused(true)
	start_screen.queue_free()
	_build_start_screen()
