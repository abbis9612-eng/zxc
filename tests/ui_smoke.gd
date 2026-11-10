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
	# الضغط على بغداد في الخريطة يُظهر المنطقة ومحافظات العراق الـ18
	var map: Control = main.map
	map.focus_point(44.0, 33.0)
	await _wait(3)
	map._click(map.map_to_screen(map.to_map(44.4, 33.3)))
	main._refresh()
	await _shot("03b_iraq_regions")
	# البصرة: مواردها ومنشآتها، وطبقة الموارد على الخريطة
	map.focus_point(46.5, 31.5)
	map._click(map.map_to_screen(map.to_map(47.4, 30.6)))
	map.set_layer(4)
	main._refresh()
	await _shot("03c_basra_resources")
	map.set_layer(0)
	var names := ["state", "economy", "army", "research", "diplomacy", "intel", "news"]
	for t in names.size():
		main.tabs.current_tab = t
		main._refresh()
		await _shot("04_tab_%d_%s" % [t, names[t]])
		if names[t] == "state":
			(main.tabs.get_child(t) as ScrollContainer).scroll_vertical = 380
			await _shot("04_tab_0b_factions")
		if names[t] == "economy":
			(main.tabs.get_child(t) as ScrollContainer).scroll_vertical = 820
			await _shot("04_tab_1b_market")
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
	main._refresh()
	await _shot("08_front")
	# تبويب الجيش: الفرق، وطبقة المدى
	main.tabs.current_tab = 2
	main._refresh()
	await _shot("09_divisions")
	map.set_layer(5)
	map.focus_point(44.0, 33.0)
	map.queue_redraw()
	await _shot("10_range_layer")
	quit()
