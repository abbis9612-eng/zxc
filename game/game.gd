## مدير اللعبة (Autoload باسم Game): الوقت والسرعات والحفظ، ويربط المحاكاة بالواجهة.
extends Node

const Simulation := preload("res://sim/simulation.gd")
const DataDB := preload("res://sim/data_db.gd")

## ثواني حقيقية لكل يوم في اللعبة، لكل سرعة من الخمس (من يوم في الثانية إلى 25 يوماً في الثانية)
const SPEEDS := [1.0, 0.5, 0.25, 0.1, 0.04]
const SETTINGS_PATH := "user://settings.cfg"
## الارتفاع المنطقي للواجهة على الهاتف: كلما قل كبرت العناصر
const MOBILE_LOGICAL_HEIGHT := 520
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
## 0 خفيف، 1 متوسط، 2 عالٍ. يغيّر نعومة الكرة وطول مشهد المعركة وظلاله.
const QUALITY_NAMES := ["خفيف", "متوسط", "عالٍ"]
var quality := 1
var _quality_saved := false
var mobile := false
var welcomed := false

var db: DataDB
var sim: Simulation
var paused: bool = true
var speed: int = 2           # 0..4
var _acc: float = 0.0


func _ready() -> void:
	db = DataDB.new()
	if not db.load_all():
		push_error("فشل تحميل بيانات اللعبة")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	mobile = OS.has_feature("mobile") or "--mobile-preview" in OS.get_cmdline_user_args()
	if mobile and not _quality_saved:
		quality = 0
	if mobile:
		_apply_mobile_scale()
		get_window().size_changed.connect(_apply_mobile_scale)


## على الهاتف: نكبّر الواجهة حسب حجم الشاشة الفعلي بدل تصغير تصميم الكمبيوتر
func _apply_mobile_scale() -> void:
	var px := DisplayServer.window_get_size()
	if px.x <= 0 or px.y <= 0:
		return
	var short_side := float(mini(px.x, px.y))
	var k := short_side / float(MOBILE_LOGICAL_HEIGHT)
	get_tree().root.content_scale_size = Vector2i(roundi(px.x / k), roundi(px.y / k))


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		light_theme = bool(cf.get_value("display", "light_theme", true))
		if cf.has_section_key("display", "quality"):
			quality = clampi(int(cf.get_value("display", "quality", 1)), 0, 2)
			_quality_saved = true


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("display", "quality", quality)
	cf.save(SETTINGS_PATH)


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
	set_paused(true)
	game_started.emit()


func is_running() -> bool:
	return sim != null and not sim.state.is_empty()


func set_paused(p: bool) -> void:
	paused = p
	_acc = 0.0
	paused_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


func set_speed(s: int) -> void:
	speed = clampi(s, 0, SPEEDS.size() - 1)
	speed_changed.emit(speed)


func _process(delta: float) -> void:
	if paused or not is_running() or sim.state["game_over"] != "":
		return
	_acc += delta
	var step: float = SPEEDS[speed]
	# حد أقصى لعدد الأيام في الإطار الواحد حتى لا يتجمد الجهاز الضعيف
	var guard := 0
	while _acc >= step and guard < 10:
		_acc -= step
		guard += 1
		step_day()
		if paused:
			break


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
		save_game(AUTOSAVE_PATH)  # حفظ تلقائي كل شهر
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
