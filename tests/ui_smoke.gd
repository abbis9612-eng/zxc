## فحص الواجهة: يشغّل الشاشة الرئيسية ويمر على كل التبويبات ويحفظ لقطات.
##   godot --path . -s tests/ui_smoke.gd -- <مجلد_اللقطات>
extends SceneTree

var out_dir := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	change_scene_to_file("res://ui/main.tscn")
	_run.call_deferred()


func _wait(frames: int = 10) -> void:
	for i in frames:
		await process_frame


func _shot(name: String) -> void:
	await _wait(6)
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("لقطة: ", name)


func _run() -> void:
	await _wait(20)
	var game: Node = root.get_node("Game")
	var main: Node = current_scene
	await _shot("01_start")
	game.start_new("IRQ", 1, 2026)
	await _shot("02_welcome")
	# إغلاق نافذة الترحيب
	main.dialog_queue.clear()
	for ch in main.overlay.get_children():
		ch.queue_free()
	main.dialog_open = false
	# صدمة نفطية حتى يظهر أثر السوق في الرسوم
	load("res://sim/market.gd").apply_shock(game.sim, {"oil": 1.6}, 3)
	for i in 95:
		game.step_day()
	main.dialog_queue.clear()
	for ch in main.overlay.get_children():
		ch.queue_free()
	main.dialog_open = false
	main._dirty = true
	await _shot("03_state")
	# لمس بغداد: بطاقة السياق بأهم الأرقام والأفعال
	var map: Control = main.map
	map.focus_point(44.0, 33.0)
	await _wait(3)
	map._click(map.map_to_screen(map.to_map(44.4, 33.3)))
	await _shot("03b_context_baghdad")
	# وضع التحريك: الوجهات الممكنة مظللة، ومعاينة الطريق مع المدة
	var pid: String = game.sim.state["player"]
	var divs: Array = load("res://sim/divisions.gd").of(game.sim, pid)
	var from: String = divs[0]["region"]
	main._start_move([int(divs[0]["id"])], from)
	map.preview_target = ""
	for rid in map.move_reach:
		if rid != from and game.sim.db.regions[rid]["name_en"] == "Al-Basrah":
			map.preview_target = rid
	await _shot("03c_move_preview")
	var target: String = map.preview_target
	if target != "":
		main._move_to(target)
		game.step_day()
		game.step_day()
		map.focus_point(45.5, 32.0)
		await _shot("03d_moving")
	# طبقة الموارد ومفتاحها
	main._pick_layer(4)
	await _shot("03e_resources_layer")
	main._pick_layer(0)
	main._toggle_alerts()
	main._update_advisor()
	await _shot("03f_alerts")
	main._toggle_alerts()
	var names := ["state", "economy", "army", "research", "diplomacy", "intel", "news"]
	for t in names.size():
		main._open_tab(t)
		main._refresh()
		await _shot("04_tab_%d_%s" % [t, names[t]])
		if names[t] == "state":
			(main.tabs.get_child(t) as ScrollContainer).scroll_vertical = 380
			await _shot("04_tab_0b_factions")
		if names[t] == "economy":
			(main.tabs.get_child(t) as ScrollContainer).scroll_vertical = 820
			await _shot("04_tab_1b_market")
	main._close_sheet()
	await _wait(12)
	# لمس سوريا على الخريطة: بطاقة دولة أجنبية
	map.focus_point(38.0, 35.0)
	await _wait(3)
	game.sim.player()["intel"]["SYR"] = 55.0
	map._click(map.map_to_screen(map.to_map(38.9, 35.0)))
	await _shot("05a_context_syria")
	main._on_country_selected("SYR")
	game.sim.player()["intel"]["SYR"] = 55.0
	main._refresh()
	await _shot("05_select_syria")
	(main.tabs.get_child(4) as ScrollContainer).scroll_vertical = 900
	await _shot("05b_covert_ops")
	main._confirm_war("SYR")
	await _shot("06_war_forecast")
	# إعلان الحرب فعلاً ومتابعة المعارك
	main.dialog_queue.clear()
	for ch in main.overlay.get_children():
		ch.queue_free()
	main.dialog_open = false
	game.sim.declare_war("IRQ", "SYR")
	for i in 60:
		game.step_day()
	main.dialog_queue.clear()
	for ch in main.overlay.get_children():
		ch.queue_free()
	main.dialog_open = false
	main._show_battle_report()
	await _shot("07_battle_report")
	main.dialog_queue.clear()
	for ch in main.overlay.get_children():
		ch.queue_free()
	main.dialog_open = false
	map.focus_point(39.0, 34.5)
	map._zoom = 3.5
	main._refresh()
	await _shot("08_front")
	# تبويب الجيش: الفرق، وطبقة المدى
	main._close_sheet()
	await _wait(12)
	map.focus_point(39.0, 34.5)
	await _shot("08b_front_closeup")
	main._open_tab(2)
	main._refresh()
	await _shot("09_divisions")
	map.set_layer(5)
	map.focus_point(44.0, 33.0)
	map.queue_redraw()
	await _shot("10_range_layer")
	# تبديل الثيم أثناء اللعب: الشاشة تُبنى من جديد واللعبة مستمرة
	var light_before: bool = game.light_theme
	game.set_light_theme(not light_before)
	await _wait(30)
	await _shot("11_theme_switched")
	game.set_light_theme(light_before)
	await _wait(10)
	quit()
