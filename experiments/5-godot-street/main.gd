# تجربة: شارع من بلدة عراقية بثلاثي أبعاد حقيقي، كاميرا مائلة، أبرامز ضد T-72، ومدفعية
extends Node3D

var cam: Camera3D
var player: Tank
var cam_target := Vector3(0, 0, 20)
var cam_dist := 95.0
const EL := 40.0
const AZ := 35.0
var touches := {}
var tap_start := {}
var pinch0 := 0.0
var follow := true
var art_t := 6.0
var hud: Label
var fps_acc := 0.0
var fps_n := 0
var autotest := false
var rings: Array = []

func _ready() -> void:
	autotest = "autotest" in OS.get_cmdline_user_args()
	_env()
	cam = Camera3D.new(); cam.fov = 22.0; cam.keep_aspect = Camera3D.KEEP_WIDTH; cam.near = 5; cam.far = 1500
	add_child(cam)
	FX.setup(self, cam)
	add_child(BlastRunner.new())
	_ground()
	var st: Node3D = load("res://models/street.glb").instantiate(); add_child(st)
	for mi in st.find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# الدبابات (إحداثيات بلندر (x,y) ← Godot (x, 0, -y))
	player = _tank("m1a1", "iq", Vector3(1.6, 0, 34), 0.0)
	_tank("t72", "tr", Vector3(-1.8, 0, -28), PI)
	_tank("t72", "tr", Vector3(2.2, 0, -40), PI)
	for p in [Vector3(-3, 0, -14), Vector3(9, 0, 24), Vector3(-12, 0, 22)]: FX.ground_mark(p, FX.scorch_tex, Vector2(6, 6), randf() * TAU, .8)
	_ui()
	_update_cam(0.0)
	if autotest: _run_autotest()

func _tank(k: String, s: String, pos: Vector3, yaw: float) -> Tank:
	var t := Tank.new(); add_child(t); t.global_position = pos; t.rotation.y = yaw; t.setup(k, s); return t

func _env() -> void:
	var we := WorldEnvironment.new(); var e := Environment.new()
	var sky := Sky.new(); var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(.36, .52, .74); sm.sky_horizon_color = Color(.78, .76, .7); sm.ground_horizon_color = Color(.72, .66, .56); sm.ground_bottom_color = Color(.5, .45, .38)
	sm.sun_angle_max = 20; sky.sky_material = sm
	e.background_mode = Environment.BG_SKY; e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.ambient_light_energy = .75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; e.tonemap_exposure = 1.0; e.tonemap_white = 6.0
	e.glow_enabled = OS.get_environment("GLOW") != "0"; e.glow_intensity = .55; e.glow_bloom = .05; e.glow_hdr_threshold = 1.1
	e.fog_enabled = true; e.fog_light_color = Color(.8, .76, .68); e.fog_density = .00035; e.fog_sky_affect = .2
	e.adjustment_enabled = true; e.adjustment_saturation = .92; e.adjustment_contrast = 1.06
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); add_child(sun)
	sun.light_energy = 2.0; sun.light_color = Color(1, .93, .82); sun.shadow_enabled = OS.get_environment("NOSH") != "1"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS; sun.directional_shadow_max_distance = 260
	sun.shadow_blur = 1.2; sun.shadow_bias = .04; sun.shadow_normal_bias = 1.2
	sun.look_at(sun.global_position + Vector3(.452, -.616, -.645), Vector3.UP)

func _tex_mat(path: String, meters: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_texture = load(path); m.albedo_color = tint
	m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3.ONE / meters
	m.roughness = 1.0; m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _plane(size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var p := PlaneMesh.new(); p.size = size; mi.mesh = p; mi.material_override = mat; mi.position = pos; add_child(mi); return mi

func _ground() -> void:
	_plane(Vector2(2400, 2400), Vector3.ZERO, _tex_mat("res://fx/dry_ground_rocks.jpg", 4.5, Color(.92, .84, .7)))
	# بقع أرض بلون مختلف لكسر التكرار
	var big := _tex_mat("res://fx/aerial_ground_rock.jpg", 22.0, Color(1, .93, .8, .55)); big.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; big.render_priority = -2
	_plane(Vector2(2400, 2400), Vector3(0, .01, 0), big)
	_plane(Vector2(4, 2400), Vector3(-6.2, .015, 0), _tex_mat("res://fx/dry_ground_01.jpg", 4.0, Color(.95, .88, .76)))
	_plane(Vector2(4, 2400), Vector3(6.2, .015, 0), _tex_mat("res://fx/dry_ground_01.jpg", 4.0, Color(.95, .88, .76)))
	_plane(Vector2(8, 2400), Vector3(0, .02, 0), _tex_mat("res://fx/aerial_asphalt_01.jpg", 14.0, Color(.82, .8, .78)))
	var curb := StandardMaterial3D.new(); curb.albedo_color = Color(.66, .64, .6); curb.roughness = .9
	for x in [-4.1, 4.1]:
		var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(.25, .15, 2400); mi.mesh = bm; mi.material_override = curb; mi.position = Vector3(x, .07, 0); add_child(mi)
	var line := StandardMaterial3D.new(); line.albedo_color = Color(.9, .88, .82); line.roughness = .8
	for x in [-3.7, 3.7]: _plane(Vector2(.15, 2400), Vector3(x, .025, 0), line)

func _ui() -> void:
	var cl := CanvasLayer.new(); add_child(cl)
	var font: FontFile = load("res://fonts/Cairo.ttf")
	hud = Label.new(); hud.position = Vector2(16, 40); hud.add_theme_font_override("font", font); hud.add_theme_font_size_override("font_size", 26)
	hud.add_theme_color_override("font_color", Color(.96, .93, .86)); hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, .8)); hud.add_theme_constant_override("outline_size", 6)
	cl.add_child(hud)
	var tip := Label.new(); tip.text = "اضغط على الأرض لتحريك دبابتك (أبرامز) · اسحب لتحريك الكاميرا · إصبعان للتقريب"
	tip.add_theme_font_override("font", font); tip.add_theme_font_size_override("font_size", 22); tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85)); tip.add_theme_constant_override("outline_size", 6)
	tip.anchor_left = 0; tip.anchor_right = 1; tip.anchor_top = 1; tip.anchor_bottom = 1; tip.offset_left = 20; tip.offset_right = -20; tip.offset_top = -140; tip.offset_bottom = -50
	cl.add_child(tip)

func _update_cam(dt: float) -> void:
	if follow and player and not player.dead:
		var want := player.global_position + Vector3(0, 0, -10)
		cam_target = cam_target.lerp(want, min(1.0, dt * 1.6)) if dt > 0 else want
	var el := deg_to_rad(EL); var az := deg_to_rad(AZ)
	var d := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	var sh := FX.shake
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * sh * .35
	cam.global_position = cam_target + d * cam_dist + jitter
	cam.look_at(cam_target + jitter, Vector3.UP)
	FX.shake = max(0.0, FX.shake - dt * 2.5)

func _ground_at(sp: Vector2) -> Variant:
	var o := cam.project_ray_origin(sp); var n := cam.project_ray_normal(sp)
	if abs(n.y) < 1e-4: return null
	var t := -o.y / n.y
	return o + n * t if t > 0 else null

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			touches[ev.index] = ev.position; tap_start[ev.index] = [ev.position, Time.get_ticks_msec()]
			if touches.size() == 2:
				var v := touches.values(); pinch0 = (v[0] as Vector2).distance_to(v[1])
		else:
			if tap_start.has(ev.index) and touches.size() == 1:
				var s: Array = tap_start[ev.index]
				if (s[0] as Vector2).distance_to(ev.position) < 18 and Time.get_ticks_msec() - int(s[1]) < 450:
					_tap(ev.position)
			touches.erase(ev.index); tap_start.erase(ev.index)
	elif ev is InputEventScreenDrag:
		if touches.size() == 2 and touches.has(ev.index):
			touches[ev.index] = ev.position
			var v := touches.values(); var d := (v[0] as Vector2).distance_to(v[1])
			if pinch0 > 0: cam_dist = clamp(cam_dist * pinch0 / d, 40.0, 230.0)
			pinch0 = d
		elif touches.size() == 1:
			var a = _ground_at(ev.position - ev.relative); var b = _ground_at(ev.position)
			if a != null and b != null: cam_target += (a - b); follow = false
			touches[ev.index] = ev.position
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: cam_dist = clamp(cam_dist / 1.12, 40.0, 230.0)
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam_dist = clamp(cam_dist * 1.12, 40.0, 230.0)

func _tap(sp: Vector2) -> void:
	var g = _ground_at(sp)
	if g == null or player.dead: return
	player.goal = g; follow = true
	_ring(g)

func _ring(p: Vector3) -> void:
	var mi := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 1.6; tm.outer_radius = 2.0; mi.mesh = tm
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = Color(1, .85, .4, .9); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m; mi.position = p + Vector3(0, .1, 0); mi.scale = Vector3(1, .05, 1); add_child(mi)
	var tw := mi.create_tween(); tw.tween_property(mi, "scale", Vector3(2.2, .05, 2.2), .7); tw.parallel().tween_property(m, "albedo_color:a", 0.0, .7); tw.tween_callback(mi.queue_free)

func _process(dt: float) -> void:
	_update_cam(dt)
	# مدفعية العدو: قذيفة 155 كل 9-16 ثانية، نصفها قرب دبابتك
	art_t -= dt
	if art_t <= 0 and not autotest:
		art_t = randf_range(9, 16)
		var near := randf() < .45 and not player.dead
		var c := player.global_position if near else Vector3(randf_range(-14, 14), 0, randf_range(-30, 30))
		var a := randf() * TAU; var r := randf_range(14, 30) if near else randf_range(0, 6)
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		FX.artillery(p, randf_range(.85, 1.1))
		for t in Tank.all:
			var d := t.global_position.distance_to(p)
			if d < 9: t.take_hit(80 * (1 - d / 9.0), p)
	fps_acc += dt; fps_n += 1
	if fps_acc >= .5:
		var alive := 0
		for t in Tank.all: if t.side == "tr" and not t.dead: alive += 1
		hud.text = "%d إطار/ث · دبابتك %d%% · دبابات العدو %d" % [roundi(fps_n / fps_acc), max(0, roundi(player.hp)), alive]
		fps_acc = 0; fps_n = 0

# ---------- فحص آلي: لقطات للحركة والرمي والانفجار
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shots%s/%s.png" % [OS.get_environment("TAG"), name])

func _wait_fire(n0: int, limit: float) -> bool:
	var t := 0.0
	while Tank.shots_fired == n0 and t < limit:
		await get_tree().process_frame; t += get_process_delta_time()
	return Tank.shots_fired > n0

func _run_autotest() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots" + OS.get_environment("TAG"))
	for t in Tank.all: t.cd = 999.0
	var fxt := OS.get_environment("FXT")
	if fxt != "":
		await get_tree().create_timer(.5).timeout
		var p := player.global_position + Vector3(0, 1.6, -8)
		var back := Vector3(0, 0, -1)
		if fxt == "probe":
			player.goal = player.global_position + Vector3(-6, 0, -16)
			var t0 := Time.get_ticks_msec()
			for i in 70:
				await get_tree().create_timer(.6).timeout
				await _shot("x_%02d" % i)
				var img := get_viewport().get_texture().get_image()
				var v := img.get_pixel(360, 780).v
				var rec := "F%d t=%.1f v=%.3f" % [i, (Time.get_ticks_msec() - t0) / 1000.0, v]
				if false:
					for n in find_children("*", "GeometryInstance3D", true, false):
						if n.get_path().get_concatenated_names().contains("street"): continue
						var g := n as GeometryInstance3D
						if not g.is_visible_in_tree(): continue
						var ab: AABB = g.global_transform * g.get_aabb()
						rec += "\n   %s %s c=%s s=%s" % [n.name, n.get_class(), ab.get_center(), ab.size]
				print(rec)
			get_tree().quit(); return
		if fxt == "move":
			player.goal = player.global_position + Vector3(-6, 0, -16)
			for i in 24:
				await get_tree().create_timer(2.0).timeout; await _shot("x_%02d" % i)
			get_tree().quit(); return
		if fxt == "efire" or fxt == "pfire":
			var e: Tank = Tank.all[1]; e.global_position = player.global_position + Vector3(6, 0, -48)
			follow = false; cam_target = (player.global_position + e.global_position) * .5
			e.accuracy = 1.0; player.accuracy = 1.0; e.hp = 1000.0
			if fxt == "efire": e.cd = 0.0
			else: player.cd = 0.0
			await _wait_fire(Tank.shots_fired, 8.0)
			for t in Tank.all: t.cd = 999.0
		elif fxt == "die":
			var e: Tank = Tank.all[1]; e.global_position = player.global_position + Vector3(4, 0, -20); e.rotation.y = PI
			await get_tree().create_timer(.3).timeout
			e.die()
		elif fxt == "impact": FX.impact(p, back)
		elif fxt == "muzzle": FX.muzzle(p, Vector3(0, 0, -1), player.global_position)
		elif fxt == "m1": FX.burst(p + back * .8, 6, .18, FX.fire_tex, true, Vector2(1.6, 2.6), Vector2(8, 16), 12, back, Vector3.ZERO, [[0, Color(1, .9, .6, 1)], [1, Color(1, .5, .2, 0)]], [[0, .6], [1, 1.4]], 6.0, false)
		elif fxt == "m2": FX.burst(p + back * 1.5, 10, 3.2, FX.smoke_tex, false, Vector2(1.8, 3.2), Vector2(4, 12), 18, back, Vector3(.2, .5, .1), [[0, Color(.7, .68, .64, .85)], [1, Color(.75, .73, .7, 0)]], [[0, .5], [1, 2.6]], 5.0)
		elif fxt == "m3": FX.burst(player.global_position + Vector3(0, .5, 0), 18, 2.6, FX.smoke_tex, false, Vector2(2.2, 3.5), Vector2(6, 11), 90, Vector3(1, .05, 0), Vector3(0, .2, 0), [[0, Color(.66, .56, .44, .7)], [1, Color(.7, .62, .52, 0)]], [[0, .5], [1, 1.8]], 4.0)
		elif fxt == "light": FX.light(p, 6.0, 16.0, .2, Color(1, .8, .5))
		elif fxt == "flash": FX.flash(p, 4.0, .08)
		elif fxt == "sparks": FX.burst(p, 30, .7, FX.glow_tex, true, Vector2(.12, .3), Vector2(10, 28), 70, back, Vector3(0, -9.8, 0), [[0, Color(1, .9, .6, 1)], [1, Color(1, .4, .1, 0)]], [[0, 1], [1, .4]], 0.0, false)
		elif fxt == "smoke": FX.burst(p, 6, 2.5, FX.smoke_tex, false, Vector2(1.5, 2.5), Vector2(1, 3), 60, Vector3.UP, Vector3(.2, .6, 0), [[0, Color(.2, .19, .18, .85)], [1, Color(.3, .3, .3, 0)]], [[0, .6], [1, 2.0]], 1.0)
		for i in 6:
			await get_tree().create_timer(.5).timeout; await _shot("x_%d" % i)
		get_tree().quit(); return
	await get_tree().create_timer(1.0).timeout
	await _shot("a_start")
	player.goal = player.global_position + Vector3(-6, 0, -16)
	for i in 4:
		await get_tree().create_timer(.7).timeout; await _shot("b_move_%d" % i)
	# رمي دبابتك على T-72 قريبة
	var e: Tank = Tank.all[1]; e.global_position = player.global_position + Vector3(6, 0, -48)
	follow = false; cam_target = (player.global_position + e.global_position) * .5
	player.cd = 0.0
	var ok = await _wait_fire(Tank.shots_fired, 8.0)
	print("PLAYER_FIRED ", ok)
	for i in 8:
		await _shot("c_fire_%02d" % i); await get_tree().create_timer(.05 + i * .06).timeout
	# العدو يرمي على دبابتك
	e.cd = 0.0; ok = await _wait_fire(Tank.shots_fired, 8.0); e.cd = 999.0
	print("ENEMY_FIRED ", ok)
	for i in 4:
		await _shot("d_enemy_%02d" % i); await get_tree().create_timer(.1).timeout
	# طلقة قاتلة واحتراق
	if OS.get_environment("NOKILL") != "1": e.hp = 5.0
	player.accuracy = 1.0; player.cd = 0.0
	ok = await _wait_fire(Tank.shots_fired, 9.0)
	print("KILL_FIRED ", ok)
	for i in 6:
		await get_tree().create_timer(.5).timeout; await _shot("e_kill_%02d" % i)
		print("CAM ", cam.global_position, " shake ", FX.shake)
		if i == 3:
			var ps: Array = find_children("*", "GeometryInstance3D", true, false).filter(func(n): return not n.get_path().get_concatenated_names().contains("street") and not (n is MeshInstance3D and (n as MeshInstance3D).mesh is PlaneMesh))
			for n in ps:
				n.visible = false
				await _shot("y_" + str(n.get_instance_id()))
				var img := get_viewport().get_texture().get_image()
				var g := img.get_pixel(360, 700).v
				print("  HIDE ", n.get_path(), " ", n.get_class(), " v=", g)
				n.visible = true
	print("ENEMY_DEAD ", e.dead)
	# مدفعية قرب دبابتك
	FX.artillery(player.global_position + Vector3(12, 0, -14), 1.0)
	for i in 10:
		await get_tree().create_timer(.35).timeout; await _shot("f_blast_%02d" % i)
	cam_dist = 230.0; await get_tree().create_timer(.6).timeout; await _shot("g_far")
	cam_dist = 40.0; await get_tree().create_timer(.6).timeout; await _shot("h_close")
	print("AUTOTEST_DONE")
	get_tree().quit()
