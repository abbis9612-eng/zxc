## اختبار التمرير باللمس: سحب يبدأ فوق زر يمرر القائمة ولا يضغط الزر، واللمسة القصيرة تبقى ضغطة.
##   godot --path . -s tests/touch_scroll_test.gd
extends SceneTree

var pressed_count := 0


func _initialize() -> void:
	change_scene_to_file("res://ui/main.tscn")
	_run.call_deferred()


func _wait(n: int = 5) -> void:
	for i in n:
		await process_frame


func _touch(pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = root.get_final_transform() * pos
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = root.get_final_transform() * pos
	e.relative = root.get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _first_button(sc: ScrollContainer) -> Button:
	for b in sc.find_children("*", "Button", true, false):
		var bb: Button = b
		if bb.is_visible_in_tree() and bb.size.y > 20.0:
			return bb
	return null


func _run() -> void:
	await _wait(20)
	var game: Node = root.get_node("Game")
	var main: Node = current_scene
	game.start_new("IRQ", 1, 2026)
	await _wait(5)
	main.dialog_queue.clear()
	for ch in main.overlay.get_children():
		ch.queue_free()
	main.dialog_open = false
	main._open_tab(4)   # العلاقات: قائمة طويلة فيها أزرار
	main.selected = "SYR"
	main._refresh()
	await _wait(20)
	var sc: ScrollContainer = main.tabs.get_child(4)
	var btn: Button = _first_button(sc)
	if btn != null:
		# نضع الزر في منتصف القائمة حتى يبقى مجال للسحب للأعلى
		sc.scroll_vertical = int(btn.global_position.y - sc.global_position.y + sc.scroll_vertical - sc.size.y * 0.6)
		await _wait(5)
	var ok := true
	if btn == null:
		print("FAIL لا يوجد زر ظاهر في القائمة")
		quit(1)
		return
	btn.pressed.connect(func(): pressed_count += 1)
	# 1) سحب للأعلى يبدأ فوق الزر
	var p := btn.get_global_rect().get_center()
	var before := sc.scroll_vertical
	_touch(p, true)
	await _wait(2)
	for i in 12:
		p += Vector2(0, -15)
		_drag(p, Vector2(0, -15))
		await _wait(1)
	_touch(p, false)
	await _wait(3)
	var moved := sc.scroll_vertical - before
	print("التمرير بعد السحب: ", moved, " · ضغطات الزر: ", pressed_count)
	if moved < 100 or pressed_count != 0:
		ok = false
	# 2) الاندفاع يكمل بعد رفع الإصبع (أو يقف عند الحافة)
	var after_release := sc.scroll_vertical
	await _wait(20)
	print("الاندفاع بعد الرفع: ", sc.scroll_vertical - after_release)
	# 3) لمسة قصيرة ثابتة على زر تبقى ضغطة
	sc.scroll_vertical = 0
	await _wait(5)
	var target: Button = _first_button(sc)
	sc.scroll_vertical = int(target.global_position.y - sc.global_position.y + sc.scroll_vertical - sc.size.y * 0.5)
	await _wait(5)
	var taps := [0]
	target.pressed.connect(func(): taps[0] += 1)
	var tp := target.get_global_rect().get_center()
	_touch(tp, true)
	await _wait(2)
	_touch(tp + Vector2(2, 3), false)
	await _wait(3)
	print("ضغطات اللمسة القصيرة: ", taps[0])
	if taps[0] != 1:
		ok = false
	print("نجح" if ok else "FAIL")
	quit(0 if ok else 1)
