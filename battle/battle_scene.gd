## مشهد المعركة يعرض تقرير المحاكاة كما هو: كل مرحلة، من تفوّق فيها، ثم النتيجة.
## الأشكال طائرة وصاروخ وسفينة ودبابة وجندي نصنعها هنا، والحرائق تبقى على أهداف التقرير.
extends Control

signal closed

const UI := preload("res://ui/ui_kit.gd")
const Models := preload("res://battle/models.gd")
const Territory := preload("res://sim/territory.gd")

var report: Dictionary = {}
var quality := 1
var _phases: Array = []
var _phase := 0
var _t := 0.0
var _speed := 1.0
var _done := false
var _hits_shown := false
var _vp: SubViewport
var _cam: Camera3D
var _water: MeshInstance3D
var _units: Array = []
var _buildings: Array = []
var _label: Label
var _bar: ProgressBar


static func plan(battle: Dictionary) -> Array:
	var out: Array = []
	for ph in battle.get("phases", []):
		var res := float(ph.get("result", 0.0))
		out.append({
			"id": str(ph.get("id", "")),
			"name_ar": str(ph.get("name_ar", "")),
			"result": res,
			"attacker_wins": res >= 0.0,
		})
	return out


## سطور الختام من التقرير نفسه: الفائز، الخسائر، المنشآت المضروبة، المناطق المأخوذة.
static func summary_lines(battle: Dictionary, unit_names: Dictionary, region_names: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var ratio := float(battle.get("ratio", 0.5))
	var who := "المهاجم" if ratio >= 0.5 else "المدافع"
	lines.append("حسمت المحاكاة المعركة لصالح %s (%d%%)." % [who, int(ratio * 100.0)])
	lines.append("خسائر المهاجم: " + _loss_text(battle.get("losses_a", {}), unit_names))
	lines.append("خسائر المدافع: " + _loss_text(battle.get("losses_d", {}), unit_names))
	var strikes := _hit_text(battle.get("hits_a", []), "المهاجم", region_names)
	strikes.append_array(_hit_text(battle.get("hits_d", []), "المدافع", region_names))
	if strikes.is_empty():
		lines.append("لم تُدمَّر منشآت في العمق.")
	else:
		for line in strikes:
			lines.append(line)
	var taken: Array = battle.get("taken", [])
	if not taken.is_empty():
		var holder := "المهاجم" if bool(battle.get("taken_by_attacker", true)) else "المدافع"
		var names := PackedStringArray()
		for rid in taken:
			names.append(str(region_names.get(str(rid), rid)))
		lines.append("سيطر %s على: %s." % [holder, ", ".join(names)])
	return lines


static func _loss_text(losses: Dictionary, unit_names: Dictionary) -> String:
	if losses.is_empty():
		return "لا خسائر مادية"
	var parts := PackedStringArray()
	for k in losses:
		var name := str(unit_names.get(str(k), k))
		parts.append("%s ×%d" % [name, int(losses[k])])
	return "، ".join(parts)


static func _hit_text(hits: Array, side: String, region_names: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for hit in hits:
		if typeof(hit) != TYPE_DICTIONARY:
			continue
		var kind := str(Territory.FACILITY_NAMES.get(str(hit.get("type", "")), hit.get("type", "هدف")))
		var place := str(region_names.get(str(hit.get("region", "")), hit.get("region", "")))
		lines.append("دمّر %s %s في %s." % [side, kind, place])
	return lines


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
	e.background_color = Color(0.42, 0.58, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.7)
	e.ambient_light_energy = 0.65
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
	gmat.albedo_color = Color(0.32, 0.38, 0.24)
	gmat.roughness = 1.0
	ground.material_override = gmat
	_vp.add_child(ground)
	_water = MeshInstance3D.new()
	var water := PlaneMesh.new()
	water.size = Vector2(48, 32)
	_water.mesh = water
	_water.position.y = 0.03
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1, 0.28, 0.42)
	wmat.roughness = 0.18
	_water.material_override = wmat
	_water.visible = false
	_vp.add_child(_water)
	_place_buildings()
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 8, 15)
	_cam.current = true
	_vp.add_child(_cam)


func _place_buildings() -> void:
	for i in 5:
		var h := 0.7 + float(i % 3) * 0.4
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.7, h, 0.7)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = Vector3(12.2, h * 0.5, -5.0 + float(i) * 2.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.46, 0.42, 0.36)
		node.material_override = mat
		_vp.add_child(node)
		_buildings.append(node)


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
	_water.visible = kind == "sea"
	for b in _buildings:
		(b as Node3D).visible = kind != "sea"
	for side in 2:
		for i in n:
			_spawn(kind, side, i, n)
	if kind == "strike":
		_show_hit_fires()
	var who := "المهاجم" if ph["attacker_wins"] else "المدافع"
	_label.text = "%s · تفوق %s" % [ph["name_ar"], who]
	_aim(kind, 0.0, true)


func _spawn(kind: String, side: int, slot: int, count: int) -> void:
	var shape := kind
	if kind == "land" and slot % 3 == 2:
		shape = "soldier"
	var tint := Color(0.85, 0.68, 0.28) if side == 0 else Color(0.75, 0.28, 0.24)
	var unit := Models.make(shape, tint)
	var span := 18.0
	var x0 := -10.0 if side == 0 else 10.0
	var z := (float(slot) - float(count - 1) * 0.5) * (span / maxf(1.0, float(count)))
	unit.position = Vector3(x0, _altitude(kind), z)
	unit.scale = Vector3(1.25, 1.25, 1.25)
	if side == 1:
		unit.rotation.y = PI
	unit.set_meta("side", side)
	unit.set_meta("z", z)
	unit.set_meta("kind", kind)
	_vp.add_child(unit)
	_units.append(unit)


func _altitude(kind: String) -> float:
	if kind == "air":
		return 2.3
	if kind == "strike":
		return 3.4
	return 0.0


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
	if kind != "air" and kind != "strike" and kind != "sea":
		kind = "land"
	_aim(kind, u, false)
	for n in _units:
		var unit := n as Node3D
		if unit == null or not unit.visible:
			continue
		var side := int(unit.get_meta("side"))
		var wins: bool = (side == 0) == bool(ph["attacker_wins"])
		var dir := 1.0 if side == 0 else -1.0
		var gain := u * (7.2 if wins else 2.0)
		var y := _altitude(kind)
		if kind == "air" or kind == "strike":
			y += sin(u * TAU + float(unit.get_meta("z"))) * 0.28
		var x := (-10.0 if side == 0 else 10.0) + dir * gain
		unit.position = Vector3(x, y, float(unit.get_meta("z")))
		if not wins and u > 0.8 and not unit.has_meta("burst"):
			unit.set_meta("burst", true)
			_burst(unit.position + Vector3(0, 0.35, 0))
			unit.visible = false
	_bar.value = (float(_phase) + u) / maxf(1.0, float(_phases.size()))
	if _t >= 1.0:
		_phase += 1
		_begin_phase()


func _aim(kind: String, u: float, snap: bool) -> void:
	var eye := Vector3(0, 7, 14)
	var look := Vector3(0, 1.0, 0)
	if kind == "air":
		eye = Vector3(0, 14, 13)
		look = Vector3(0, 1.6, 0)
	elif kind == "strike":
		eye = Vector3(0, 11, 13)
		look = Vector3(0, 2.2, 0)
	elif kind == "sea":
		eye = Vector3(0, 8, 14)
		look = Vector3(0, 0.3, 0)
	else:
		eye = Vector3(0, 7.5, 12)
		look = Vector3(0, 0.35, 0)
	eye.x += (u - 0.5) * 2.0
	var pos := eye if snap else _cam.position.lerp(eye, 0.08)
	_cam.look_at_from_position(pos, look)


func _show_hit_fires() -> void:
	if _hits_shown or quality == 0:
		return
	_hits_shown = true
	var i := 0
	for _hit in report.get("hits_a", []):
		_flame(Vector3(12.2, 0.9, -5.0 + float(i) * 2.4), false)
		i += 1
	i = 0
	for _hit in report.get("hits_d", []):
		_flame(Vector3(-8.0, 0.6, -3.0 + float(i) * 1.5), false)
		i += 1


func _burst(at: Vector3) -> void:
	_flame(at, true)


func _flame(at: Vector3, brief: bool) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.26 if brief else 0.42
	mesh.height = mesh.radius * 2.0
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.42, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.32, 0.04)
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	_vp.add_child(node)
	if brief:
		var tween := create_tween()
		tween.tween_property(node, "scale", Vector3(2.6, 2.6, 2.6), 0.4)
		tween.tween_callback(node.queue_free)


func _finish() -> void:
	if _done:
		return
	_done = true
	_show_hit_fires()
	_clear_units()
	_bar.value = 1.0
	_label.text = "نتيجة المحاكاة"
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -90
	panel.offset_bottom = 150
	panel.add_theme_stylebox_override("panel", UI.float_box(12, 14))
	add_child(panel)
	var col := UI.col()
	panel.add_child(col)
	for line in summary_lines(report, _unit_names(), _region_names()):
		var text := UI.label(line, UI.C_TEXT, 16)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		col.add_child(text)


func _db() -> Object:
	var tree := get_tree()
	if tree == null:
		return null
	var node := tree.root.get_node_or_null("Game")
	if node == null:
		return null
	var data = node.get("db")
	return data as Object


func _unit_names() -> Dictionary:
	var names := {}
	var data := _db()
	if data == null:
		return names
	var units = data.get("units")
	if typeof(units) != TYPE_DICTIONARY:
		return names
	for k in units:
		var row = units[k]
		if typeof(row) == TYPE_DICTIONARY:
			names[str(k)] = str(row.get("name_ar", k))
	return names


func _region_names() -> Dictionary:
	var names := {}
	var data := _db()
	if data == null:
		return names
	var regions = data.get("regions")
	if typeof(regions) != TYPE_DICTIONARY:
		return names
	var want: Array = []
	for hit in report.get("hits_a", []) + report.get("hits_d", []):
		if typeof(hit) == TYPE_DICTIONARY:
			want.append(str(hit.get("region", "")))
	for rid in report.get("taken", []):
		want.append(str(rid))
	for rid in want:
		var region = regions.get(rid, {})
		if typeof(region) == TYPE_DICTIONARY and region.has("name_ar"):
			names[str(rid)] = str(region["name_ar"])
	return names
