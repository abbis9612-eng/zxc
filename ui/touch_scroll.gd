## تمرير القوائم باللمس من أي مكان، حتى فوق الأزرار، مع اندفاع طبيعي بعد رفع الإصبع.
## المشكلة التي يحلها: الزر يمسك اللمسة فلا تصل للقائمة، فلا تتحرك إلا إن بدأت من فراغ.
## الحل: نراقب الإدخال قبل الواجهة؛ إن تحرك الإصبع عمودياً أكثر من عتبة صغيرة نلغي ضغطة الزر
## ونمرر القائمة بأنفسنا. اللمسة القصيرة الثابتة تبقى ضغطة عادية.
extends Node

## المسافة (بالبكسل المنطقي) التي تحوّل اللمسة إلى سحب
const THRESHOLD := 10.0
## تباطؤ الاندفاع: كلما كبر توقف أسرع
const FRICTION := 5.0
const FAR := Vector2(-99999, -99999)

var _scrolls: Array = []
var _active: ScrollContainer = null
var _start := Vector2.ZERO
var _start_scroll := 0
var _dragging := false
var _last := Vector2.ZERO
var _last_t := 0.0
var _vel := 0.0
var _fling: ScrollContainer = null
var _fling_pos := 0.0


func add(sc: ScrollContainer) -> void:
	# نعطّل السحب المدمج حتى لا يتحرك مرتين
	sc.scroll_deadzone = 100000
	_scrolls.append(sc)


func _target_at(pos: Vector2) -> ScrollContainer:
	for i in range(_scrolls.size() - 1, -1, -1):
		var sc = _scrolls[i]
		if not is_instance_valid(sc):
			continue
		var s: ScrollContainer = sc
		if s.is_visible_in_tree() and s.get_global_rect().has_point(pos) and s.get_v_scroll_bar().max_value > s.size.y + 1.0:
			return s
	return null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.position.x < -9000.0 or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_fling = null
			_active = _target_at(mb.position)
			_dragging = false
			if _active != null:
				_start = mb.position
				_last = mb.position
				_last_t = Time.get_ticks_msec() / 1000.0
				_start_scroll = _active.scroll_vertical
				_vel = 0.0
		else:
			if _dragging:
				# رفع الإصبع بعد سحب: لا ضغطة، والقائمة تكمل باندفاعها
				get_viewport().set_input_as_handled()
				if absf(_vel) > 60.0:
					_fling = _active
					_fling_pos = float(_active.scroll_vertical)
			_active = null
			_dragging = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _active == null or mm.position.x < -9000.0 or not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		var d := mm.position - _start
		if not _dragging:
			if absf(d.y) < THRESHOLD:
				return
			if absf(d.x) > absf(d.y):
				_active = null   # حركة أفقية: مثل سحب منزلق، نتركها للعنصر
				return
			_dragging = true
			_cancel_press()
		var now := Time.get_ticks_msec() / 1000.0
		var dt := maxf(now - _last_t, 0.001)
		var v := -(mm.position.y - _last.y) / dt
		_vel = lerpf(_vel, v, 0.4)
		_last = mm.position
		_last_t = now
		_active.scroll_vertical = int(_start_scroll - d.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _dragging:
		get_viewport().set_input_as_handled()


## يلغي ضغطة الزر الذي بدأ عليه الإصبع: نحرك «المؤشر» بعيداً ثم نرفعه هناك
func _cancel_press() -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = FAR
	mv.global_position = FAR
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = FAR
	up.global_position = FAR
	get_viewport().push_input(up)


func _process(delta: float) -> void:
	if _fling == null:
		return
	if not is_instance_valid(_fling) or not _fling.is_visible_in_tree():
		_fling = null
		return
	var before := _fling.scroll_vertical
	_fling_pos += _vel * delta
	_fling.scroll_vertical = int(_fling_pos)
	_vel *= exp(-FRICTION * delta)
	# توقف عند الحافة أو حين يبطؤ كثيراً
	if absf(_vel) < 30.0 or (_fling.scroll_vertical == before and absf(_vel * delta) >= 1.0):
		_fling = null
