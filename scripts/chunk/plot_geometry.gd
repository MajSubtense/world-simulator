class_name PlotGeometry
extends RefCounted
## 每个 GP 面（地块）的切平面参数化。
##
## 2D 世界坐标：地块中心在 (0,0)，范围 [-PLOT_WORLD_SIZE/2, +PLOT_WORLD_SIZE/2]²
##   uv ∈ [0,1]²  →  world = (uv - 0.5) * PLOT_WORLD_SIZE
##
## 供 2D 俯视游玩和 3D 地图预览共用。

const PLOT_WORLD_SIZE := 1024.0

var gp: GoldbergPolyhedron
var tangents: PackedVector3Array
var bitangents: PackedVector3Array
var spreads: PackedFloat32Array

func setup(poly: GoldbergPolyhedron) -> void:
	gp = poly
	var n := gp.face_count
	tangents.resize(n)
	bitangents.resize(n)
	spreads.resize(n)

	for f in n:
		var c := gp.face_normals[f]
		var ref := Vector3.UP if absf(c.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var t := ref.cross(c).normalized()
		var b := c.cross(t)
		tangents[f] = t
		bitangents[f] = b

		var max_d := 0.0
		var start := gp.face_vertex_offsets[f]
		var end := gp.face_vertex_offsets[f + 1]
		for i in range(start, end):
			var vi := gp.face_vertex_indices[i]
			var vp := gp.vertex_positions[vi].normalized()
			var d := vp - c * vp.dot(c)
			max_d = maxf(max_d, d.length())
		spreads[f] = max_d * 1.05

## (u, v) → 球面单位方向
func uv_to_dir(f: int, u: float, v: float) -> Vector3:
	var c := gp.face_normals[f]
	var t := tangents[f]
	var b := bitangents[f]
	var s := spreads[f]
	var lu := (u - 0.5) * 2.0 * s
	var lv := (v - 0.5) * 2.0 * s
	return (c + t * lu + b * lv).normalized()

## (u, v) → 2D 世界坐标
func uv_to_world(_f: int, u: float, v: float) -> Vector2:
	return Vector2(u - 0.5, v - 0.5) * PLOT_WORLD_SIZE

## 2D 世界坐标 → (u, v)
func world_to_uv(_f: int, pos: Vector2) -> Vector2:
	return Vector2(pos.x / PLOT_WORLD_SIZE + 0.5, pos.y / PLOT_WORLD_SIZE + 0.5)