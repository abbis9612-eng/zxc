## خط صغير يرسم تاريخ قيمة (مثل سعر مورد) مع خط مرجعي عند 1.0
extends Control

var values: Array = []
var color: Color = Color("e0b84a")
var reference: float = 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(90, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if values.size() < 2:
		return
	var lo := reference
	var hi := reference
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span := maxf(0.05, hi - lo)
	var pts := PackedVector2Array()
	for i in values.size():
		var x := size.x * float(i) / float(values.size() - 1)
		var y := size.y - (float(values[i]) - lo) / span * (size.y - 2.0) - 1.0
		pts.append(Vector2(x, y))
	var ry := size.y - (reference - lo) / span * (size.y - 2.0) - 1.0
	draw_line(Vector2(0, ry), Vector2(size.x, ry), Color(1, 1, 1, 0.15), 1.0)
	draw_polyline(pts, color, 1.5, true)
