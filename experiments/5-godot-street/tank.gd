# دبابة: بدن يتحرك بتسارع ودوران حقيقيين، وبرج يدور وحده نحو الهدف، ورمي بارتداد ووميض
extends Node3D
class_name Tank

var side := "iq"
var kind := "m1a1"
var hull: Node3D
var turret: Node3D
var muzzle_local := Vector3(0, .4, -6)
var hp := 100.0
var dead := false
var goal = null
var speed := 0.0
var max_speed := 7.0          # م/ث على الطريق (نحو 25 كم/س في الشارع)
var turn_rate := .55          # راد/ث للبدن
var turret_rate := .7         # راد/ث للبرج (نحو 40°/ث)
var reload := 7.5
var cd := 3.0
var recoil := 0.0
var accel_prev := 0.0
var track_acc := 0.0
var dust: CPUParticles3D
var armor_front := 1.0
var accuracy := .7
var damage := 100.0
static var all: Array[Tank] = []
static var shots_fired := 0

func setup(k: String, s: String) -> void:
	kind = k; side = s
	var sc: Node3D = load("res://models/%s.glb" % k).instantiate()
	add_child(sc)
	hull = sc.find_child("Hull", true, false)
	turret = sc.find_child("Turret", true, false)
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_find_muzzle()
	if k == "t72":
		accuracy = .5; damage = 34.0; reload = 8.0; turret_rate = .4
	else:
		accuracy = .75; damage = 100.0; reload = 7.0
	# غبار خلف الجنازير
	dust = CPUParticles3D.new(); dust.amount = 30; dust.lifetime = 2.6; dust.emitting = false
	var q := QuadMesh.new(); q.material = FX._pmat(FX.smoke_tex, false, true); dust.mesh = q
	dust.direction = Vector3(0, .4, 1); dust.spread = 30; dust.initial_velocity_min = .5; dust.initial_velocity_max = 2
	dust.gravity = Vector3(.3, .3, .1); dust.scale_amount_min = 1.4; dust.scale_amount_max = 2.4
	dust.scale_amount_curve = FX._curve([[0, .5], [1, 2.4]])
	dust.color_ramp = FX._grad([[0, Color(.7, .6, .48, .0)], [.1, Color(.7, .6, .48, .5)], [1, Color(.72, .64, .54, 0)]])
	dust.angle_max = 360; dust.anim_offset_max = 1; dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; dust.emission_box_extents = Vector3(1.8, .2, .4)
	dust.position = Vector3(0, .4, 4.5); dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hull.add_child(dust)
	all.append(self)

# فوهة المدفع: أبعد نقاط البرج للأمام (‎-Z)، بارتفاع متوسطها
func _find_muzzle() -> void:
	var zmin := 1e9; var pts: Array[Vector3] = []
	var meshes: Array = turret.find_children("*", "MeshInstance3D", true, false)
	if turret is MeshInstance3D: meshes.append(turret)     # البرج نفسه قد يكون هو الشبكة
	for mi in meshes:
		var m := mi as MeshInstance3D
		var xf := turret.global_transform.affine_inverse() * m.global_transform
		for v in m.mesh.get_faces():
			var p: Vector3 = xf * v
			pts.append(p); zmin = min(zmin, p.z)
	var ys := 0.0; var n := 0
	for p in pts:
		if p.z < zmin + .25: ys += p.y; n += 1
	if n == 0: push_error("لم أجد فوهة المدفع في " + kind); return
	muzzle_local = Vector3(0, ys / max(1, n), zmin)

func fwd() -> Vector3: return -global_basis.z
func turret_fwd() -> Vector3: return -turret.global_basis.z

func _physics_process(dt: float) -> void:
	if dead: return
	# ---- الحركة: يدور البدن ثم يتقدم، أبطأ في المنعطف، بتسارع وكبح
	var target_speed := 0.0
	if goal != null:
		var to: Vector3 = goal - global_position; to.y = 0
		var dist := to.length()
		if dist < 2.0:
			goal = null
		else:
			var want := atan2(-to.x, -to.z)
			var diff := wrapf(want - rotation.y, -PI, PI)
			rotation.y += clamp(diff, -turn_rate * dt, turn_rate * dt)
			target_speed = max_speed * clamp(cos(diff), 0.0, 1.0)
			if abs(diff) > .7: target_speed = 1.2      # دوران محوري بطيء
			target_speed = min(target_speed, dist * .9)
	var acc := 2.2 if target_speed > speed else 4.5
	var prev := speed
	speed = move_toward(speed, target_speed, acc * dt)
	global_position += fwd() * speed * dt
	var a := (speed - prev) / maxf(dt, 1e-4)
	accel_prev = lerp(accel_prev, a, min(1.0, dt * 6))
	# ميلان البدن مع التسارع، واهتزاز خفيف أثناء السير
	hull.rotation.x = lerp(hull.rotation.x, clamp(accel_prev * .012, -.05, .05) + sin(Time.get_ticks_msec() * .02) * .002 * speed, min(1.0, dt * 8))
	dust.emitting = speed > 1.5 and OS.get_environment("NODUST") != "1"
	# آثار الجنازير
	track_acc += speed * dt
	if track_acc > 1.6:
		track_acc = 0
		var trk := OS.get_environment("TRK")
		if trk != "off": FX.ground_mark(global_position, FX.track_tex, Vector2(3.8, 1.8), rotation.y, .35, -1.0 if trk == "keep" else 40.0)
	# ---- البرج نحو أقرب عدو
	var tgt: Tank = null; var bd := 1e9
	for t in all:
		if t.side != side and not t.dead:
			var d := t.global_position.distance_to(global_position)
			if d < bd: bd = d; tgt = t
	var want_t := 0.0
	if tgt and bd < 240:
		var to2 := tgt.global_position - turret.global_position
		want_t = wrapf(atan2(-to2.x, -to2.z) - rotation.y, -PI, PI)
	var dt_ := wrapf(want_t - turret.rotation.y, -PI, PI)
	turret.rotation.y += clamp(dt_, -turret_rate * dt, turret_rate * dt)
	# ارتداد المدفع ورجوعه
	recoil = move_toward(recoil, 0.0, dt * 1.6)
	turret.position.z = turret.get_meta("z0", turret.position.z) + recoil * .45
	if not turret.has_meta("z0"): turret.set_meta("z0", turret.position.z)
	cd -= dt
	if tgt and bd < 240 and abs(dt_) < .03 and cd <= 0:
		fire(tgt); cd = reload * randf_range(.92, 1.08)

func fire(tgt: Tank) -> void:
	var mz: Vector3 = turret.global_transform * muzzle_local
	var f := turret_fwd(); f.y = 0; f = f.normalized()
	FX.muzzle(mz, f, global_position); shots_fired += 1
	if OS.get_cmdline_user_args().has("autotest"): print("FIRE ", kind, " pos=", global_position, " mz=", mz, " tgt=", tgt.global_position, " hp=", tgt.hp)
	recoil = 1.0
	hull.rotation.x += .03                      # البدن يرتد للخلف لحظة
	var hit := randf() < accuracy
	var aim := tgt.global_position + Vector3(0, 1.4, 0)
	if not hit: aim += Vector3(randf_range(-6, 6), -1.4, randf_range(-6, 6))
	Shot.spawn(get_parent(), mz, aim, tgt if hit else null, damage)

func take_hit(dmg: float, from: Vector3) -> void:
	if dead: return
	# الدرع الأمامي أقوى: إذا جاءت القذيفة من الأمام تقل الإصابة
	var dirv := (from - global_position); dirv.y = 0
	var frontal := fwd().dot(dirv.normalized()) > .5
	hp -= dmg * (.6 if frontal else 1.0)
	FX.impact(global_position + Vector3(0, 1.6, 0) + dirv.normalized() * 2.0, dirv.normalized())
	if OS.get_cmdline_user_args().has("autotest"): print("HIT ", kind, " hp=", hp)
	if hp <= 0: die()

func die() -> void:
	dead = true; speed = 0; dust.emitting = false
	FX.vehicle_fire(self)
	# تسويد المركبة المحترقة
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(.04, .035, .03, .72); dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if OS.get_environment("DK") != "0":
		for mi in find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).material_overlay = dark
	# البرج ينقلع ويميل
	if OS.get_environment("TW") == "0": return
	var tw := turret.create_tween()
	tw.tween_property(turret, "position:y", turret.position.y + .5, .25).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(turret, "rotation:z", .18, .25)
	tw.tween_property(turret, "position:y", turret.position.y + .25, .4).set_ease(Tween.EASE_IN)
