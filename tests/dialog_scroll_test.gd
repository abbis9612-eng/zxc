## نافذة أطول من الشاشة تبقى داخلها: المتن يتمرّر بالسحب، والأزرار تبقى ظاهرة.
##   godot --path . --resolution 1100x520 -s tests/dialog_scroll_test.gd -- --mobile-preview [مجلد_لقطات]
##   godot --path . --resolution 420x760 -s tests/dialog_scroll_test.gd -- --mobile-preview --narrow [مجلد_لقطات]
extends SceneTree

var pressed := 0
var out_dir := ""
var narrow := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--narrow":
			narrow = true
		elif a != "--mobile-preview":
			out_dir = a
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
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


func _fail(msg: String) -> void:
	print("FAIL ", msg)
	quit(1)


func _close_dialogs(main: Node) -> void:
	main.dialog_queue.clear()
	for ch in main.overlay.get_children():
		ch.queue_free()
	main.dialog_open = false
	main.touch_scroll.set_modal(null)


func _inside(vp: Rect2, r: Rect2) -> bool:
	return r.position.x >= vp.position.x - 1.0 and r.position.y >= vp.position.y - 1.0 \
			and r.end.x <= vp.end.x + 1.0 and r.end.y <= vp.end.y + 1.0


func _shot(name: String) -> void:
	if out_dir == "":
		return
	await _wait(2)
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("لقطة: ", name)


func _run() -> void:
	await _wait(20)
	await _wait(4)
	var game: Node = root.get_node("Game")
	var main: Node = current_scene
	var vp: Rect2 = main.get_viewport_rect()
	print("الشاشة ", vp.size, " نافذة ", DisplayServer.window_get_size())
	if narrow:
		await _check_narrow_menu(main)
		return
	if vp.size.y > 560.0:
		_fail("ارتفاع الشاشة %s ليس قصيراً، شغّل الاختبار بنافذة قصيرة" % vp.size)
		return
	game.start_new("USA", 1, 2026)
	await _wait(8)
	_close_dialogs(main)
	await _wait(3)
	# قائمة خلف النافذة: السحب على النافذة لا يمرّرها
	main._open_tab(4)
	main.selected = "IRN"
	main._refresh()
	await _wait(6)
	var sheet: ScrollContainer = main.tabs.get_child(4)
	sheet.scroll_vertical = 120
	await _wait(2)
	var sheet_before := sheet.scroll_vertical
	main._confirm_war("IRN")
	await _wait(12)
	var panel: Control = main.overlay.find_child("DialogPanel", true, false)
	var scroll: ScrollContainer = main.overlay.find_child("DialogScroll", true, false)
	if panel == null or scroll == null:
		_fail("نافذة الحرب بلا لوحة أو تمرير")
		return
	vp = main.get_viewport_rect()
	var pr: Rect2 = panel.get_global_rect()
	print("اللوحة ", pr, " التمرير ", scroll.size, " المحتوى ", scroll.get_v_scroll_bar().max_value)
	if not _inside(vp, pr):
		_fail("اللوحة خرجت من الشاشة %s خارج %s" % [pr, vp])
		return
	var buttons: Array = panel.find_children("*", "Button", true, false)
	if buttons.size() < 2:
		_fail("أزرار النافذة ناقصة")
		return
	for b in buttons:
		var bb: Button = b
		bb.pressed.connect(func(): pressed += 1)
		var br: Rect2 = bb.get_global_rect()
		print("زر ", bb.text, " ", br)
		if not _inside(vp, br) or not pr.encloses(br.grow(-1)):
			_fail("الزر «%s» خارج النافذة أو الشاشة" % bb.text)
			return
	var hidden := scroll.get_v_scroll_bar().max_value - scroll.size.y
	if hidden < 40.0:
		_fail("متن الحرب يجب أن يزيد عن ارتفاع الشاشة القصيرة، الفرق %s" % hidden)
		return
	await _shot("war_top")
	var tail: Label = null
	for n in scroll.find_children("*", "Label", true, false):
		var l: Label = n
		if "تُخاض" in l.text or "منطقة بمنطقة" in l.text:
			tail = l
	if tail == null:
		_fail("سطر نهاية التوقع غير موجود")
		return
	var sr: Rect2 = scroll.get_global_rect()
	if sr.encloses(tail.get_global_rect()):
		_fail("سطر النهاية ظاهر بالكامل قبل التمرير")
		return
	# سحب من العنوان لا يحرّك قائمة الخلفية
	var title_pos := pr.position + Vector2(pr.size.x * 0.5, 30)
	_touch(title_pos, true)
	await _wait(1)
	var p := title_pos
	for i in 8:
		p += Vector2(0, -18)
		_drag(p, Vector2(0, -18))
		await _wait(1)
	_touch(p, false)
	await _wait(3)
	if sheet.scroll_vertical != sheet_before:
		_fail("السحب على النافذة مرّر القائمة التي تحتها")
		return
	# سحب المتن للأعلى يُظهر ما كان مقطوعاً ولا يضغط الأزرار
	var before := scroll.scroll_vertical
	var origin := sr.get_center()
	_touch(origin, true)
	await _wait(2)
	p = origin
	for i in 12:
		p += Vector2(0, -16)
		_drag(p, Vector2(0, -16))
		await _wait(1)
	_touch(p, false)
	await _wait(4)
	var moved := scroll.scroll_vertical - before
	print("التمرير بعد السحب: ", moved, " ضغطات: ", pressed, " خلفية: ", sheet.scroll_vertical)
	if moved < 40 or pressed != 0 or sheet.scroll_vertical != sheet_before:
		_fail("السحب لم يمرّر المتن أو ضغط زراً أو حرّك الخلفية")
		return
	var btn_y_before := (buttons[0] as Control).get_global_rect().position.y
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _wait(3)
	if not sr.grow(2).encloses(tail.get_global_rect()) and not sr.intersects(tail.get_global_rect()):
		_fail("نهاية المتن لا تصل إلى المنطقة الظاهرة بعد التمرير لآخرها")
		return
	if absf((buttons[0] as Control).get_global_rect().position.y - btn_y_before) > 1.0:
		_fail("التمرير حرّك الأزرار")
		return
	await _shot("war_scrolled")
	# لمسة قصيرة على «تراجع» تغلق النافذة
	var back: Button = null
	for b in buttons:
		if (b as Button).text == "تراجع":
			back = b
	if back == null:
		_fail("زر التراجع مفقود")
		return
	var tp := back.get_global_rect().get_center()
	_touch(tp, true)
	await _wait(2)
	_touch(tp + Vector2(1, 2), false)
	await _wait(6)
	if main.overlay.find_child("DialogPanel", true, false) != null:
		_fail("لمسة التراجع لم تغلق النافذة")
		return
	# نافذة قصيرة لا تُمدَّد على طول الشاشة وأزرارها ظاهرة
	main._show_dialog("اختبار", "سطر واحد فقط.", [{"text": "حسناً"}])
	await _wait(12)
	panel = main.overlay.find_child("DialogPanel", true, false)
	vp = main.get_viewport_rect()
	if panel == null or not _inside(vp, panel.get_global_rect()):
		_fail("النافذة القصيرة خرجت من الشاشة")
		return
	if panel.size.y > vp.size.y * 0.55:
		_fail("النافذة القصيرة تمددت بلا داعٍ: %s" % panel.size.y)
		return
	for b in panel.find_children("*", "Button", true, false):
		if not _inside(vp, (b as Control).get_global_rect()):
			_fail("زر النافذة القصيرة خارج الشاشة")
			return
	await _shot("short_dialog")
	print("نجح")
	quit(0)


func _check_narrow_menu(main: Node) -> void:
	var vp: Rect2 = main.get_viewport_rect()
	if vp.size.x > 560.0:
		_fail("العرض ليس ضيقاً: %s" % vp.size)
		return
	var game: Node = root.get_node("Game")
	game.start_new("USA", 1, 2026)
	await _wait(8)
	_close_dialogs(main)
	await _wait(3)
	main._show_menu()
	await _wait(12)
	var panel: Control = main.overlay.find_child("DialogPanel", true, false)
	vp = main.get_viewport_rect()
	if panel == null or not _inside(vp, panel.get_global_rect()):
		_fail("قائمة الأزرار خرجت من الشاشة الضيقة")
		return
	var n_btns := 0
	var wrapped := false
	var first_y := -1.0
	for b in panel.find_children("*", "Button", true, false):
		n_btns += 1
		var br2: Rect2 = (b as Control).get_global_rect()
		print("زر ", (b as Button).text, " ", br2)
		if not _inside(vp, br2):
			_fail("زر القائمة «%s» خارج الشاشة الضيقة" % (b as Button).text)
			return
		if first_y < 0.0:
			first_y = br2.position.y
		elif absf(br2.position.y - first_y) > 8.0:
			wrapped = true
	if n_btns < 4 or not wrapped:
		_fail("أزرار القائمة لم تلتف في العرض الضيق")
		return
	await _shot("narrow_menu")
	print("نجح")
	quit(0)
