# مؤثرات المعركة: وميض، ودخان، ونار، وشرر، وتراب، وانفجار المحاكاة الفيزيائية، وآثار على الأرض
extends Node
class_name FX

static var root: Node3D
static var cam: Camera3D
static var smoke_tex: Texture2D = preload("res://fx/smoke.png")
static var fire_tex: Texture2D = preload("res://fx/fire.png")
static var glow_tex: Texture2D = preload("res://fx/glow.png")
static var scorch_tex: Texture2D = preload("res://fx/scorch.png")
static var track_tex: Texture2D = preload("res://fx/tracks.png")
static var blast_frames: Array[Texture2D] = []
static var blast_meta: Dictionary = {}
static var shake := 0.0
static var _mats := {}

static func setup(r: Node3D, c: Camera3D) -> void:
	root = r; cam = c
	blast_meta = JSON.parse_string(FileAccess.get_file_as_string("res://blast/blast.json"))
	for i in int(blast_meta.n):
		blast_frames.append(load("res://blast/b%02d.png" % i))

# مادة جسيمات بصورة 4×4 إطارات تواجه الكاميرا
static func _pmat(tex: Texture2D, additive: bool, lit: bool) -> StandardMaterial3D:
	var key := "%s%s%s" % [tex.resource_path, additive, lit]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = 4; m.particles_anim_v_frames = 4; m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if (additive or not lit) else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if additive: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points: c.add_point(Vector2(p[0], p[1]))
	return c

static func _grad(cols: Array) -> Gradient:
	var g := Gradient.new(); var o := PackedFloat32Array(); var c := PackedColorArray()
	for e in cols:
		o.append(e[0]); c.append(e[1])
	g.offsets = o; g.colors = c
	return g

# جسيمات لمرة واحدة تُحذف بعد انتهائها
static func burst(pos: Vector3, amount: int, life: float, tex: Texture2D, additive: bool, size: Vector2, vel: Vector2, spread: float, dir: Vector3, grav: Vector3, colors: Array, scale_curve: Array, damping := 0.0, lit := true, explosiveness := 1.0, emit_box := Vector3.ZERO) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount; p.lifetime = life; p.one_shot = true; p.explosiveness = explosiveness; p.randomness = .5
	var q := QuadMesh.new(); q.size = Vector2.ONE; q.material = _pmat(tex, additive, lit); p.mesh = q
	p.direction = dir; p.spread = spread; p.initial_velocity_min = vel.x; p.initial_velocity_max = vel.y
	p.gravity = grav; p.damping_min = damping; p.damping_max = damping
	p.scale_amount_min = size.x; p.scale_amount_max = size.y
	p.scale_amount_curve = _curve(scale_curve)
	p.color_ramp = _grad(colors)
	p.angle_min = 0; p.angle_max = 360; p.angular_velocity_min = -20; p.angular_velocity_max = 20
	# كل جسيم يأخذ شكل نفخة ثابتاً (الإطارات 16 نفخة مختلفة لا تسلسل زمني)
	p.anim_speed_min = 0; p.anim_speed_max = 0; p.anim_offset_max = 1.0
	# حلقة أرضية: انتشار مسطح بكل الاتجاهات الأفقية
	if spread >= 90 and abs(dir.y) < .2: p.direction = Vector3(1, 0, 0); p.spread = 180; p.flatness = 1.0
	if emit_box != Vector3.ZERO: p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = emit_box
	p.position = pos; p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p); p.emitting = true
	p.finished.connect(p.queue_free)
	return p

static func light(pos: Vector3, energy: float, rng: float, life: float, col := Color(1, .62, .3)) -> void:
	var l := OmniLight3D.new(); l.position = pos; l.light_energy = energy; l.omni_range = rng; l.light_color = col; l.shadow_enabled = false
	root.add_child(l)
	var tw := l.create_tween(); tw.tween_property(l, "light_energy", 0.0, life).set_ease(Tween.EASE_OUT); tw.tween_callback(l.queue_free)

static func flash(pos: Vector3, size: float, life: float) -> void:
	var s := Sprite3D.new(); s.texture = glow_tex; s.billboard = BaseMaterial3D.BILLBOARD_ENABLED; s.shaded = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; s.modulate = Color(1, .92, .7); s.pixel_size = size / glow_tex.get_width(); s.position = pos
	var m := StandardMaterial3D.new(); m.albedo_texture = glow_tex; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.vertex_color_use_as_albedo = true
	s.material_override = m
	root.add_child(s)
	var tw := s.create_tween(); tw.tween_property(s, "modulate:a", 0.0, life); tw.tween_callback(s.queue_free)

# أثر على الأرض (حرق، جنزير)
static func ground_mark(pos: Vector3, tex: Texture2D, size: Vector2, rot: float, alpha: float, life := -1.0) -> void:
	var mi := MeshInstance3D.new(); var q := PlaneMesh.new(); q.size = size; mi.mesh = q
	var m := StandardMaterial3D.new(); m.albedo_texture = tex; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, alpha); m.render_priority = -1
	mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, .035 + randf() * .01, 0); mi.rotation.y = rot
	root.add_child(mi)
	if life > 0:
		var tw := mi.create_tween(); tw.tween_interval(life * .7); tw.tween_property(m, "albedo_color:a", 0.0, life * .3); tw.tween_callback(mi.queue_free)

# ---------- انفجار قذيفة 155 ملم: تسلسل المحاكاة الفيزيائية + وميض + كتل تراب + دخان يبقى + حفرة
static func artillery(pos: Vector3, k := 1.0) -> void:
	light(pos + Vector3(0, 3, 0), 14.0 * k, 40.0, .35)
	flash(pos + Vector3(0, 1.5, 0), 14.0 * k, .12)
	# تسلسل المحاكاة: لوح يواجه الكاميرا، نقطة الأرض في الصورة على موضع الانفجار
	var s := Sprite3D.new(); var M := blast_meta
	s.pixel_size = float(M.mpp) * k; s.shaded = false; s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED; s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.centered = true; s.offset = Vector2(float(M.w) / 2.0 - float(M.gx), float(M.gy) - float(M.h) / 2.0)
	# اللوح يواجه الكاميرا المائلة، فجزؤه الأسفل ينغرز بالأرض؛ نقدّمه نحو الكاميرا بما يكفي ونصغّره بنفس النسبة ليبقى بنفس المكان والحجم على الشاشة
	var below := (float(M.h) - float(M.gy)) * float(M.mpp) * k
	var vz := cam.global_basis.z
	var adv := below * sqrt(1.0 - vz.y * vz.y) / maxf(.2, vz.y) * 1.15 + 1.0
	var D := cam.global_position.distance_to(pos)
	s.pixel_size *= (D - adv) / D
	s.texture = blast_frames[0]; s.position = pos + vz * adv
	root.add_child(s); s.global_basis = cam.global_basis
	s.set_meta("t", 0.0); s.set_meta("blast", true)
	BlastRunner.add(s)
	# كتل تراب تطير وتسقط (أجسام صغيرة مضاءة)
	var p := CPUParticles3D.new(); p.amount = 34; p.lifetime = 2.4; p.one_shot = true; p.explosiveness = .95
	var bm := BoxMesh.new(); bm.size = Vector3(.2, .14, .18)
	var mm := StandardMaterial3D.new(); mm.albedo_color = Color(.46, .38, .28); mm.roughness = 1; bm.material = mm; p.mesh = bm
	p.direction = Vector3.UP; p.spread = 50; p.initial_velocity_min = 9; p.initial_velocity_max = 26; p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = .4 * k; p.scale_amount_max = 1.4 * k; p.angular_velocity_min = -400; p.angular_velocity_max = 400
	p.particle_flag_rotate_y = true; p.position = pos + Vector3(0, .3, 0)
	root.add_child(p); p.emitting = true; p.finished.connect(p.queue_free)
	# حلقة غبار تزحف على الأرض
	burst(pos + Vector3(0, .6, 0), 26, 5.5, smoke_tex, false, Vector2(3, 5) * k, Vector2(7, 13), 90, Vector3(1, 0.05, 0), Vector3(0, .15, 0),
		[[0, Color(.62, .52, .4, .0)], [.08, Color(.62, .52, .4, .8)], [1, Color(.66, .58, .48, 0)]], [[0, .5], [1, 2.2]], 2.2, true, 1.0)
	# دخان يبقى وينجرف مع الريح بعد انتهاء التسلسل
	burst(pos + Vector3(0, 4, 0), 14, 16.0, smoke_tex, false, Vector2(6, 9) * k, Vector2(.5, 2.5), 40, Vector3.UP, Vector3(.35, .45, .2),
		[[0, Color(.55, .47, .38, 0)], [.15, Color(.55, .47, .38, .7)], [1, Color(.6, .55, .5, 0)]], [[0, .7], [1, 2.4]], .3, true, .6, Vector3(3, 2, 3))
	ground_mark(pos, scorch_tex, Vector2(9, 9) * k, randf() * TAU, .9)
	var d := cam.global_position.distance_to(pos)
	shake = max(shake, clamp(60.0 / d, .2, 1.2) * k)

# ---------- وميض فوهة الدبابة، ودخان، وحلقة غبار حولها
static func muzzle(pos: Vector3, fwd: Vector3, ground: Vector3) -> void:
	light(pos, 8.0, 22.0, .12, Color(1, .75, .4))
	flash(pos + fwd * 1.0, 6.0, .07)
	burst(pos + fwd * .8, 6, .18, fire_tex, true, Vector2(1.6, 2.6), Vector2(8, 16), 12, fwd, Vector3.ZERO,
		[[0, Color(1, .9, .6, 1)], [1, Color(1, .5, .2, 0)]], [[0, .6], [1, 1.4]], 6.0, false)
	burst(pos + fwd * 1.5, 10, 3.2, smoke_tex, false, Vector2(1.8, 3.2), Vector2(4, 12), 18, fwd, Vector3(.2, .5, .1),
		[[0, Color(.7, .68, .64, .85)], [1, Color(.75, .73, .7, 0)]], [[0, .5], [1, 2.6]], 5.0)
	burst(ground + Vector3(0, .5, 0), 18, 2.6, smoke_tex, false, Vector2(2.2, 3.5), Vector2(6, 11), 90, Vector3(1, .05, 0), Vector3(0, .2, 0),
		[[0, Color(.66, .56, .44, .7)], [1, Color(.7, .62, .52, 0)]], [[0, .5], [1, 1.8]], 4.0)
	shake = max(shake, .25)

# ---------- إصابة على الدرع: شرر ووهج ودخان أسود قليل
static func impact(pos: Vector3, back: Vector3) -> void:
	light(pos, 6.0, 16.0, .2, Color(1, .8, .5))
	flash(pos, 4.0, .08)
	burst(pos, 30, .7, glow_tex, true, Vector2(.12, .3), Vector2(10, 28), 70, back, Vector3(0, -9.8, 0),
		[[0, Color(1, .9, .6, 1)], [1, Color(1, .4, .1, 0)]], [[0, 1], [1, .4]], 0.0, false)
	burst(pos, 6, 2.5, smoke_tex, false, Vector2(1.5, 2.5), Vector2(1, 3), 60, Vector3.UP, Vector3(.2, .6, 0),
		[[0, Color(.2, .19, .18, .85)], [1, Color(.3, .3, .3, 0)]], [[0, .6], [1, 2.0]], 1.0)

# ---------- قذيفة تخطئ وتضرب الأرض
static func dirt_hit(pos: Vector3) -> void:
	flash(pos + Vector3(0, .5, 0), 3.0, .06)
	burst(pos + Vector3(0, .3, 0), 10, 2.2, smoke_tex, false, Vector2(1.5, 2.6), Vector2(2, 7), 35, Vector3.UP, Vector3(.2, -.4, 0),
		[[0, Color(.6, .5, .38, .85)], [1, Color(.66, .58, .48, 0)]], [[0, .6], [1, 1.8]], 1.5)
	ground_mark(pos, scorch_tex, Vector2(2.6, 2.6), randf() * TAU, .5)

# ---------- مركبة تحترق: كرة نار، ثم نار ودخان أسود يتصاعد باستمرار
static func vehicle_fire(node: Node3D) -> void:
	var pos := node.global_position
	if OS.get_environment("VF") == "L": return
	light(pos + Vector3(0, 3, 0), 16.0, 30.0, .8)
	if OS.get_environment("VF") == "B": return
	burst(pos + Vector3(0, 2, 0), 18, 1.3, fire_tex, true, Vector2(4, 7), Vector2(3, 9), 70, Vector3.UP, Vector3(0, 2, 0),
		[[0, Color(1, .95, .7, 1)], [.5, Color(1, .55, .2, .9)], [1, Color(.4, .2, .1, 0)]], [[0, .5], [1, 1.5]], 2.0, false)
	shake = max(shake, .8)
	var dbg := OS.get_environment("VF")
	if dbg == "0": return
	# نار مستمرة ودخان أسود (جسيمات مستمرة مربوطة بالمركبة)
	var f := CPUParticles3D.new(); f.amount = 16; f.lifetime = 1.0; f.preprocess = .5
	var q := QuadMesh.new(); q.material = _pmat(fire_tex, true, false); f.mesh = q
	f.direction = Vector3.UP; f.spread = 15; f.initial_velocity_min = 1.5; f.initial_velocity_max = 3.5; f.gravity = Vector3(0, 1.5, 0)
	f.scale_amount_min = 1.4; f.scale_amount_max = 2.6; f.scale_amount_curve = _curve([[0, .6], [.5, 1], [1, .3]])
	f.color_ramp = _grad([[0, Color(1, .9, .6, .9)], [1, Color(1, .4, .1, 0)]]); f.anim_speed_min = 0; f.anim_speed_max = 0; f.anim_offset_max = 1.0
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; f.emission_box_extents = Vector3(1.2, .3, 2)
	if dbg == "1": return
	f.position = Vector3(0, 2.0, .5); f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; node.add_child(f)
	var s := CPUParticles3D.new(); s.amount = 26; s.lifetime = 9.0; s.preprocess = 2.0
	var q2 := QuadMesh.new(); q2.material = _pmat(smoke_tex, false, true); s.mesh = q2
	s.direction = Vector3.UP; s.spread = 10; s.initial_velocity_min = 2.5; s.initial_velocity_max = 4.5; s.gravity = Vector3(.5, .4, .25); s.damping_min = .2; s.damping_max = .2
	s.scale_amount_min = 2.5; s.scale_amount_max = 4.0; s.scale_amount_curve = _curve([[0, .5], [1, 3.2]])
	s.color_ramp = _grad([[0, Color(.08, .075, .07, .0)], [.08, Color(.08, .075, .07, .9)], [1, Color(.25, .24, .23, 0)]])
	s.angle_max = 360; s.anim_offset_max = 1; s.position = Vector3(0, 3, 0); s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; node.add_child(s)
	var l := OmniLight3D.new(); l.light_color = Color(1, .55, .25); l.light_energy = 3.0; l.omni_range = 12; l.position = Vector3(0, 2.5, 0); node.add_child(l)
