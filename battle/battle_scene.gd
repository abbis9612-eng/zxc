## مشهد المعركة يعرض تقرير المحاكاة كما هو: كل مرحلة، من تفوّق فيها، ثم النتيجة.
## النماذج مبسطة عمداً (صناديق على أرض داكنة) حتى يعمل على الموبايل بلا أصول خارجية.
extends Control

signal closed

const UI := preload("res://ui/ui_kit.gd")

var report: Dictionary = {}
var quality := 1
var _phases: Array = []
var _phase := 0
var _t := 0.0
var _speed := 1.0
var _done := false
var _vp: SubViewport
var _cam: Camera3D
var _units: Array = []
var _label: Label
var _bar: ProgressBar


static func plan(report: Dictionary) -> Array:
	var out: Array = []
	for ph in report.get("phases", []):
		var res := float(ph.get("result", 0.0))
		out.append({
			"id": str(ph.get("id", "")),
			"name_ar": str(ph.get("name_ar", "")),
			"result": res,
			"attacker_wins": res >= 0.0,
		})
	return out


func setup(battle: Dictionary, gfx: int) -> void:
	report = battle
	quality = clampi(gfx, 0, 2)
	_phases = plan(battle)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_hud()
	_begin_phase()


func _build_world() -> void:
	var box := SubViewportContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.stretch = true
	add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(1280, 720)
	if quality == 0:
		_vp.msaa_3d = Viewport.MSAA_DISABLED
	elif quality == 1:
		_vp.msaa_3d = Viewport.MSAA_2X
	else:
		_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.4, 0.48)
	e.ambient_light_energy = 0.55
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = quality >= 2
	_vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(48, 32)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.12, 0.14, 0.16)
	gmat.roughness = 1.0
	ground.material_override = gmat
	_vp.add_child(ground)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 9, 16)
	_cam.look_at(Vector3(0, 0.4, 0))
	_cam.current = true
	_vp.add_child(_cam)


func _build_hud() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 64
	top.add_theme_stylebox_override("panel", UI.float_box(0, 10))
	add_child(top)
	var v := UI.col()
	top.add_child(v)
	_label = UI.label("", UI.C_TEXT, 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_label)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	v.add_child(_bar)
	var row := UI.row()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_top = -72
	row.offset_bottom = -16
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	row.add_child(UI.button("سرعة", _cycle_speed))
	row.add_child(UI.button("تخطّي", _skip))
	row.add_child(UI.button("إغلاق", _close))


func _cycle_speed() -> void:
	_speed = 1.0 if _speed >= 4.0 else _speed * 2.0


func _close() -> void:
	closed.emit()


func _skip() -> void:
	_phase = _phases.size()
	_finish()


func _clear_units() -> void:
	for n in _units:
		(n as Node).queue_free()
	_units.clear()


func _spawn(kind: String, side: int, slot: int, count: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	match kind:
		"air":
			mesh.size = Vector3(0.9, 0.12, 1.4)
		"strike":
			mesh.size = Vector3(0.12, 0.12, 1.1)
		"sea":
			mesh.size = Vector3(1.3, 0.28, 0.55)
		_:
			mesh.size = Vector3(0.55, 0.32, 0.9)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.68, 0.28) if side == 0 else Color(0.75, 0.28, 0.24)
	mi.material_override = mat
	var span := 7.0
	var x0 := -9.0 if side == 0 else 9.0
	var z := (float(slot) - float(count - 1) * 0.5) * (span / maxf(1.0, float(count)))
	var y := 1.7 if kind == "air" or kind == "strike" else mesh.size.y * 0.5
	mi.position = Vector3(x0, y, z)
	mi.set_meta("side", side)
	mi.set_meta("z", z)
	mi.set_meta("y", y)
	_vp.add_child(mi)
	_units.append(mi)
	return mi


func _unit_count() -> int:
	if quality <= 0:
		return 3
	if quality == 1:
		return 7
	return 12


func _phase_seconds() -> float:
	if quality <= 0:
		return 1.35
	if quality == 1:
		return 2.2
	return 3.0


func _begin_phase() -> void:
	_clear_units()
	_t = 0.0
	if _phase >= _phases.size():
		_finish()
		return
	var ph: Dictionary = _phases[_phase]
	var n := _unit_count()
	var kind := str(ph["id"])
	if kind != "air" and kind != "strike" and kind != "sea":
		kind = "land"
	for side in 2:
		for i in n:
			_spawn(kind, side, i, n)
	var who := "المهاجم" if ph["attacker_wins"] else "المدافع"
	_label.text = "%s · تفوق %s" % [ph["name_ar"], who]


func _finish() -> void:
	if _done:
		return
	_done = true
	_clear_units()
	var ratio := float(report.get("ratio", 0.5))
	var who := "المهاجم" if ratio >= 0.5 else "المدافع"
	_label.text = "حسمت المحاكاة المعركة لصالح %s (%d%%)." % [who, int(ratio * 100.0)]
	_bar.value = 1.0
	var note := UI.label("ما رأيته هو تقرير المعركة نفسه: المراحل والخسائر حُسبت قبل المشهد.", UI.C_MUTED, 14)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.set_anchors_preset(Control.PRESET_CENTER)
	note.offset_top = 24
	note.offset_bottom = 72
	add_child(note)


func _process(delta: float) -> void:
	if _done or _phases.is_empty():
		return
	if _vp != null and size.x > 2.0:
		var s := Vector2i(maxi(2, int(size.x)), maxi(2, int(size.y)))
		if _vp.size != s:
			_vp.size = s
	_t += delta * _speed / _phase_seconds()
	var ph: Dictionary = _phases[_phase]
	var u := clampf(_t, 0.0, 1.0)
	var kind := str(ph["id"])
	for n in _units:
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var side := int(mi.get_meta("side"))
		var wins: bool = (side == 0) == bool(ph["attacker_wins"])
		var dir := 1.0 if side == 0 else -1.0
		var gain := u * (6.2 if wins else 1.6)
		var y := float(mi.get_meta("y"))
		if kind == "air" or kind == "strike":
			y += sin(u * TAU) * 0.35
		var x := (-9.0 if side == 0 else 9.0) + dir * gain
		mi.position = Vector3(x, y, float(mi.get_meta("z")))
	_bar.value = (float(_phase) + u) / maxf(1.0, float(_phases.size()))
	if _t >= 1.0:
		_phase += 1
		_begin_phase()
