## أشكال المعركة من صناديق بسيطة نصنعها نحن: طائرة وصاروخ وسفينة ودبابة وجندي.
## لا أصول خارجية، واللون يميز الطرف. المقدمة نحو +X.
extends RefCounted


static func make(kind: String, tint: Color) -> Node3D:
	var root := Node3D.new()
	match kind:
		"air":
			_plane(root, tint)
		"strike":
			_missile(root, tint)
		"sea":
			_ship(root, tint)
		"soldier":
			_soldier(root, tint)
		_:
			_tank(root, tint)
	return root


static func _mat(tint: Color, dark: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint.darkened(dark)
	mat.roughness = 0.5
	return mat


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = mat
	parent.add_child(node)


static func _plane(root: Node3D, tint: Color) -> void:
	var body := _mat(tint)
	var shade := _mat(tint, 0.28)
	_box(root, Vector3(1.9, 0.18, 0.28), Vector3(0.1, 0.28, 0), body)
	_box(root, Vector3(0.42, 0.06, 1.45), Vector3(0.05, 0.34, 0), shade)
	_box(root, Vector3(0.38, 0.05, 0.9), Vector3(-0.7, 0.4, 0), shade)
	_box(root, Vector3(0.18, 0.38, 0.1), Vector3(-0.7, 0.55, 0), body)


static func _missile(root: Node3D, tint: Color) -> void:
	var body := _mat(tint)
	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color(1.0, 0.55, 0.15)
	flame.emission_enabled = true
	flame.emission = Color(1.0, 0.4, 0.05)
	flame.emission_energy_multiplier = 2.0
	_box(root, Vector3(1.35, 0.14, 0.14), Vector3(0, 0.55, 0), body)
	_box(root, Vector3(0.28, 0.2, 0.2), Vector3(-0.62, 0.55, 0), flame)


static func _ship(root: Node3D, tint: Color) -> void:
	var hull := _mat(tint, 0.15)
	var deck := _mat(tint)
	_box(root, Vector3(3.1, 0.32, 0.7), Vector3(0, 0.24, 0), hull)
	_box(root, Vector3(0.85, 0.48, 0.46), Vector3(-0.2, 0.58, 0), deck)
	_box(root, Vector3(1.1, 0.08, 0.18), Vector3(0.85, 0.46, 0), deck)


static func _tank(root: Node3D, tint: Color) -> void:
	var hull := _mat(tint, 0.12)
	var gun := _mat(tint.darkened(0.45))
	_box(root, Vector3(1.35, 0.36, 0.82), Vector3(0, 0.3, 0), hull)
	_box(root, Vector3(0.55, 0.3, 0.52), Vector3(0.05, 0.58, 0), _mat(tint))
	_box(root, Vector3(1.05, 0.1, 0.1), Vector3(0.85, 0.62, 0), gun)


static func _soldier(root: Node3D, tint: Color) -> void:
	_box(root, Vector3(0.22, 0.42, 0.22), Vector3(0, 0.32, 0), _mat(tint))
	_box(root, Vector3(0.16, 0.16, 0.16), Vector3(0.02, 0.6, 0), _mat(tint, 0.2))
