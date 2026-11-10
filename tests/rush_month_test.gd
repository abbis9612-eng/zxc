## اختبار «الشهر التالي»: يجري الوقت حتى أول الشهر القادم ويتوقف هناك بالضبط.
##   godot --headless --path . -s tests/rush_month_test.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("Game")
	game.start_new("IRQ", 1, 2026)
	var m0 := int(game.sim.state["date"]["m"])
	game.rush_month()
	var frames := 0
	while game.rushing and frames < 2000:
		await process_frame
		frames += 1
	var d: Dictionary = game.sim.state["date"]
	var ok: bool = not game.rushing and game.paused and int(d["m"]) == (m0 % 12) + 1 and int(d["d"]) == 1
	print("بعد %d إطاراً: %d/%d، متوقف=%s" % [frames, int(d["d"]), int(d["m"]), str(game.paused)])
	print("نجح" if ok else "FAIL")
	quit(0 if ok else 1)
