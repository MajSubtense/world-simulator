class_name MapProjection
extends RefCounted
## 2D 地图 UV ↔ 球面单位方向向量。
## 供 WindArrows / MapBaker / MapView 高亮共用。
##
## 投影模式：
##   RECTANGULAR  等距圆柱（lon/lat 线性）
##   MOLLWEIDE    摩尔威（等积椭圆）

enum { RECTANGULAR, MOLLWEIDE }

## (u, v) → 单位方向向量；椭圆外返回 Vector3.ZERO。
static func uv_to_dir(u: float, v: float, proj: int) -> Vector3:
	if proj == RECTANGULAR:
		return _rectangular(u, v)
	return _mollweide(u, v)

## 单位方向向量 → (u, v)。逆投影。
static func dir_to_uv(dir: Vector3, proj: int) -> Vector2:
	if proj == RECTANGULAR:
		return _rect_inv(dir)
	return _moll_inv(dir)

static func _rectangular(u: float, v: float) -> Vector3:
	var lon := (u - 0.5) * TAU
	var lat := (0.5 - v) * PI
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon))

static func _mollweide(u: float, v: float) -> Vector3:
	var mx := (u - 0.5) * 2.0
	var my := (0.5 - v)
	if mx * mx + 4.0 * my * my > 1.0:
		return Vector3.ZERO

	var theta := asin(clampf(my * 2.0, -1.0, 1.0))
	var phi_term := (2.0 * theta + sin(2.0 * theta)) / PI
	var phi := asin(clampf(phi_term, -1.0, 1.0))

	var cos_t := cos(theta)
	var lam := 0.0
	if absf(cos_t) > 0.001:
		lam = PI * mx / cos_t

	var cos_lat := cos(phi)
	return Vector3(cos_lat * cos(lam), sin(phi), cos_lat * sin(lam))

static func _rect_inv(dir: Vector3) -> Vector2:
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var u := (lon + PI) / TAU
	var v := 0.5 - lat / PI
	return Vector2(u, v)

static func _moll_inv(dir: Vector3) -> Vector2:
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var lon := atan2(dir.z, dir.x)
	var phi_term := sin(lat)
	# 牛顿迭代解 (2*theta + sin(2*theta)) / PI = phi_term
	var theta := lat
	for _i in 10:
		var f := (2.0 * theta + sin(2.0 * theta)) / PI - phi_term
		var fp := (2.0 + 2.0 * cos(2.0 * theta)) / PI
		if absf(fp) < 0.0001:
			break
		theta -= f / fp
		if absf(f) < 0.000001:
			break
	var cos_t := cos(theta)
	var my := sin(theta) * 0.5
	var mx := 0.0
	if absf(cos_t) > 0.001:
		mx = lon * cos_t / PI
	var u := mx / 2.0 + 0.5
	var v := 0.5 - my
	return Vector2(u, v)