class_name MapProjectionHelper
extends RefCounted
## 2D 地图 UV → 球面单位方向向量。
## 供 WindArrows / MapBakerGpu / MapRenderer 共用。

enum MapProjection { RECTANGULAR, MOLLWEIDE }

## 返回单位方向向量；椭圆外返回 Vector3.ZERO。
static func uv_to_dir(u: float, v: float, proj: int) -> Vector3:
	if proj == MapProjection.RECTANGULAR:
		return _rectangular(u, v)
	return _mollweide(u, v)

## 等距圆柱投影
static func _rectangular(u: float, v: float) -> Vector3:
	var lon := (u - 0.5) * TAU
	var lat := (0.5 - v) * PI
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon))

## 摩尔威投影
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