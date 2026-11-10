## مدير اللعبة (Autoload باسم Game): الوقت والسرعات والحفظ، ويربط المحاكاة بالواجهة.
extends Node

const Simulation := preload("res://sim/simulation.gd")
const DataDB := preload("res://sim/data_db.gd")

## ثواني حقيقية لكل يوم في اللعبة، لكل سرعة من الخمس (من يوم في الثانية إلى 25 يوماً في الثانية)
const SPEEDS := [1.0, 0.5, 0.25, 0.1, 0.04]
const SETTINGS_PATH := "user://settings.cfg"
## العرض المنطقي للواجهة على الهاتف (الشاشة بالطول): كلما قل كبرت العناصر
const MOBILE_LOGICAL_WIDTH := 430
const SAVE_PATH := "user://savegame.json"
const AUTOSAVE_PATH := "user://autosave.json"

signal day_passed
signal month_passed
signal events_ready(events: Array)
signal paused_changed(paused: bool)
signal speed_changed(speed: int)
signal game_started
signal theme_changed

var light_theme := true
var mobile := false
var welcomed := false

var db: DataDB
var sim: Simulation
var paused: bool = true
var speed: int = 2           # 0..4
var _acc: float = 0.0
## «الشهر التالي»: تجري الأيام بسرعة حتى أول الشهر القادم ثم يتوقف الوقت
var rushing := false
var _rush_month := -1
const RUSH_STEP := 0.02
## أقصى وقت للمحاكاة في الإطار الواحد (ميكروثانية): يترك وقتاً للرسم حتى 60 إطاراً في الثانية
const SIM_BUDGET_US := 8000


func _ready() -> void:
	db = DataDB.new()
	if not db.load_all():
		push_error("فشل تحميل بيانات اللعبة")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	mobile = OS.has_feature("mobile") or "--mobile-preview" in OS.get_cmdline_user_args()
	if mobile:
		_apply_mobile_scale()
		get_window().size_changed.connect(_apply_mobile_scale)


## على الهاتف: نكبّر الواجهة حسب حجم الشاشة الفعلي بدل تصغير تصميم الكمبيوتر
func _apply_mobile_scale() -> void:
	var px := DisplayServer.window_get_size()
	if px.x <= 0 or px.y <= 0:
		return
	var short_side := float(mini(px.x, px.y))
	var k := short_side / float(MOBILE_LOGICAL_WIDTH)
	get_tree().root.content_scale_size = Vector2i(roundi(px.x / k), roundi(px.y / k))


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		light_theme = bool(cf.get_value("display", "light_theme", true))


func set_light_theme(v: bool) -> void:
	light_theme = v
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("display", "light_theme", v)
	cf.save(SETTINGS_PATH)
	theme_changed.emit()


func start_new(player_id: String, difficulty: int = 1, seed_value: int = -1) -> void:
	welcomed = false
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	sim = Simulation.new(db)
	sim.new_game(player_id, seed_value, difficulty)
	# اللاعب يبحث في كل الفروع معاً من البداية (يستطيع إيقافه من تبويب البحث)
	sim.set_research_parallel(player_id, true)
	set_paused(true)
	game_started.emit()


func is_running() -> bool:
	return sim != null and not sim.state.is_empty()


## يجري الوقت بسرعة حتى أول الشهر القادم ويتوقف هناك، أو عند أي حدث يحتاج قرارك
func rush_month() -> void:
	if not is_running():
		return
	rushing = true
	_rush_month = int(sim.state["date"]["m"])
	paused = false
	_acc = 0.0
	paused_changed.emit(paused)


func set_paused(p: bool) -> void:
	if p:
		rushing = false
	paused = p
	_acc = 0.0
	paused_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


func set_speed(s: int) -> void:
	speed = clampi(s, 0, SPEEDS.size() - 1)
	speed_changed.emit(speed)


var _autosave_pending := false


func _process(delta: float) -> void:
	if _autosave_pending and is_running():
		_autosave_pending = false
		save_game(AUTOSAVE_PATH)
		return
	if paused or not is_running() or sim.state["game_over"] != "":
		return
	_acc += delta
	var step: float = RUSH_STEP if rushing else float(SPEEDS[speed])
	# ميزانية وقت للمحاكاة في كل إطار: على الجهاز الضعيف يتباطأ الزمن قليلاً بدل أن تنهار الإطارات
	var t0 := Time.get_ticks_usec()
	var guard := 0
	while _acc >= step and guard < 10:
		_acc -= step
		guard += 1
		step_day()
		if paused or Time.get_ticks_usec() - t0 > SIM_BUDGET_US:
			break
	# لا نراكم ديناً من الأيام: ما لم يُحسب في هذا الإطار يُترك
	_acc = minf(_acc, step * 2.0)


## الجزء المنقضي من اليوم الحالي (0..1): للعرض فقط، حتى تتحرك الفرق بسلاسة بين الأيام
func day_fraction() -> float:
	if paused or not is_running():
		return 0.0
	return clampf(_acc / float(SPEEDS[speed]), 0.0, 1.0)


## يتقدم يوماً واحداً ويرسل الإشارات. تستخدمه الواجهة وزر "يوم واحد".
func step_day() -> void:
	var month_before := int(sim.state["date"]["m"])
	sim.advance_day()
	day_passed.emit()
	if int(sim.state["date"]["m"]) != month_before:
		month_passed.emit()
		if rushing:
			set_paused(true)
		_autosave_pending = true  # حفظ تلقائي كل شهر، في الإطار التالي حتى لا يجتمع مع حساب الشهر
	if not sim.pending.is_empty():
		var evs: Array = sim.pending.duplicate()
		sim.pending.clear()
		for e in evs:
			if e.get("pause", false):
				set_paused(true)
				break
		events_ready.emit(evs)


func save_game(path: String = SAVE_PATH) -> bool:
	if not is_running():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(sim.to_save())
	return true


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var s := Simulation.new(db)
	if not s.load_save(f.get_as_text()):
		return false
	sim = s
	set_paused(true)
	game_started.emit()
	return true
