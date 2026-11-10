## مولّد أرقام عشوائية حتمي: نفس البذرة تعطي نفس التسلسل على كل الأجهزة.
## لا تستخدم randf() أو randi() داخل المحاكاة إطلاقاً، استخدم هذا فقط.
extends RefCounted

const MASK := 0xFFFFFFFF

var state: int = 1


func _init(seed_value: int = 1) -> void:
	state = seed_value & MASK
	if state == 0:
		state = 1


func next_u32() -> int:
	# xorshift32
	var x := state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	state = x & MASK
	return state


## رقم بين 0 و 1 (لا يصل إلى 1)
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next_float()


func chance(p: float) -> bool:
	return next_float() < p
