## إسقاط الكرة: من خط الطول والعرض إلى الشاشة وبالعكس. بلا عقد وبدون حالة، حتى يطابق الاختبار الكاميرا.
extends RefCounted

const FOV := 50.0


static func to_map(lon: float, lat: float) -> Vector2:
	return Vector2(lon + 180.0, 90.0 - lat)


static func on_sphere(lon: float, lat: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


static func distance(zoom: float) -> float:
	return clampf(2.55 / sqrt(maxf(zoom, 0.25)), 1.12, 3.35)


## العين تنظر إلى سطح الأرض عند الاقتراب، وإلى مركز الكرة عند الابتعاد حتى تظهر الكرة كاملة.
static func frame(center: Vector2, zoom: float) -> Dictionary:
	var lon := center.x - 180.0
	var lat := 90.0 - center.y
	var target := on_sphere(lon, lat)
	var dist := distance(zoom)
	var look_k := clampf((dist - 1.15) / 1.7, 0.0, 1.0)
	var look := target * (1.0 - look_k * 0.92)
	var eye := target * dist
	var back := (eye - look).normalized()
	var right := Vector3.UP.cross(back)
	if right.length() < 0.001:
		right = Vector3.RIGHT.cross(back)
	right = right.normalized()
	var up := back.cross(right).normalized()
	return {"eye": eye, "look": look, "right": right, "up": up, "back": back, "dist": dist}


static func project(center: Vector2, zoom: float, viewport: Vector2, lon: float, lat: float) -> Vector2:
	if viewport.x < 2.0 or viewport.y < 2.0:
		return Vector2(-10000, -10000)
	var f := frame(center, zoom)
	var p := on_sphere(lon, lat)
	var eye: Vector3 = f["eye"]
	if p.dot(eye) < 0.05:
		return Vector2(-10000, -10000)
	var rel := p - eye
	var back: Vector3 = f["back"]
	var depth := -rel.dot(back)
	if depth < 0.04:
		return Vector2(-10000, -10000)
	var right: Vector3 = f["right"]
	var up: Vector3 = f["up"]
	var aspect := viewport.x / viewport.y
	var focal := 1.0 / tan(deg_to_rad(FOV) * 0.5)
	var ndc_x := (rel.dot(right) / depth) * focal / aspect
	var ndc_y := (rel.dot(up) / depth) * focal
	return Vector2((ndc_x * 0.5 + 0.5) * viewport.x, (1.0 - (ndc_y * 0.5 + 0.5)) * viewport.y)


## إحداثيات الخريطة (خط طول +180، 90 − خط العرض)، أو (−1, −1) إن لم يصب الشعاع الكرة.
static func unproject(center: Vector2, zoom: float, viewport: Vector2, screen: Vector2) -> Vector2:
	if viewport.x < 2.0 or viewport.y < 2.0:
		return Vector2(-1, -1)
	var f := frame(center, zoom)
	var eye: Vector3 = f["eye"]
	var right: Vector3 = f["right"]
	var up: Vector3 = f["up"]
	var back: Vector3 = f["back"]
	var aspect := viewport.x / viewport.y
	var focal := 1.0 / tan(deg_to_rad(FOV) * 0.5)
	var ndc_x := (screen.x / viewport.x) * 2.0 - 1.0
	var ndc_y := (1.0 - screen.y / viewport.y) * 2.0 - 1.0
	var dir_cam := Vector3(ndc_x * aspect / focal, ndc_y / focal, -1.0).normalized()
	var dir := (right * dir_cam.x + up * dir_cam.y + back * dir_cam.z).normalized()
	var b := eye.dot(dir)
	var c := eye.dot(eye) - 1.0
	var disc := b * b - c
	if disc < 0.0:
		return Vector2(-1, -1)
	var t := -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	if t < 0.0:
		return Vector2(-1, -1)
	var hit := eye + dir * t
	var lat := rad_to_deg(asin(clampf(hit.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(hit.x, hit.z))
	return Vector2(lon + 180.0, 90.0 - lat)
