# يحرّك تسلسل صور الانفجار (من المحاكاة) ويخفيه تدريجياً في آخره
extends Node
class_name BlastRunner
static var list: Array[Sprite3D] = []
static func add(s: Sprite3D) -> void: list.append(s)
func _process(dt: float) -> void:
	var T: Array = FX.blast_meta.get("times", [])
	if T.is_empty(): return
	var last: float = T[T.size() - 1]
	for s in list.duplicate():
		if not is_instance_valid(s): list.erase(s); continue
		var t: float = s.get_meta("t") + dt; s.set_meta("t", t)
		var i := 0
		while i < T.size() - 1 and float(T[i + 1]) <= t: i += 1
		s.texture = FX.blast_frames[i]
		var a := 1.0
		if t > last: a = max(0.0, 1.0 - (t - last) / 3.0)
		s.modulate.a = a
		if a <= 0.0: list.erase(s); s.queue_free()
