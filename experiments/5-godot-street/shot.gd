# قذيفة دبابة: خط ضوئي سريع (الأثر المرئي للقذيفة الحقيقية) ثم إصابة أو ارتطام بالأرض
extends MeshInstance3D
class_name Shot

const VIS_SPEED := 700.0      # م/ث معروضة (الحقيقية نحو 1700 م/ث، وبها لا ترى العين شيئاً على الشاشة)
var a: Vector3
var b: Vector3
var t := 0.0
var dur := .1
var target: Tank
var dmg := 0.0
static var _mat: StandardMaterial3D

static func spawn(parent: Node, from: Vector3, to: Vector3, tgt: Tank, damage: float) -> void:
	var s := Shot.new(); s.a = from; s.b = to; s.target = tgt; s.dmg = damage
	s.dur = max(.06, from.distance_to(to) / VIS_SPEED)
	var m := BoxMesh.new(); m.size = Vector3(.18, .18, 1)
	if _mat == null:
		_mat = StandardMaterial3D.new(); _mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(1, .85, .55); _mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	s.mesh = m; s.material_override = _mat; s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(s)
	s._place(0.0)

func _place(k: float) -> void:
	var head := a.lerp(b, k); var tail := a.lerp(b, max(0.0, k - 14.0 / a.distance_to(b)))
	var mid := (head + tail) * .5; var L: float = max(.2, head.distance_to(tail))
	# اتجاه الخط يُحسب مرة واحدة من البداية للنهاية (ثابت طوال الطيران)
	var d := b - a
	if d.length() < .01: d = Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, L)), mid)

func _process(dt: float) -> void:
	t += dt; var k: float = min(1.0, t / dur)
	_place(k)
	if k >= 1.0:
		if target and is_instance_valid(target): target.take_hit(dmg, a)
		else: FX.dirt_hit(Vector3(b.x, 0, b.z))
		queue_free()
