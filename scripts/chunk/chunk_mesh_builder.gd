class_name ChunkMeshBuilder
extends RefCounted
## 把 PlanetChunk 的采样数据转成 ArrayMesh（规则网格三角化）。
##
## 每个采样点 = 一个顶点，相邻 4 点形成 2 个三角形。
## 顶点颜色 = color_for_height(h)。
## 使用 height_z_scale 可把高程映射到 z 轴（默认 0，纯 2D）。
##
## 采样点覆盖 [0, res]，共 (res+1)×(res+1) 个顶点，
## 与相邻 chunk 共享边界（避免裂缝）。

const MAT_WATER      := 0
const MAT_SAND       := 1
const MAT_GRASS      := 2
const MAT_FOREST     := 3
const MAT_ROCK       := 4
const MAT_SNOW       := 5
const MAT_TUNDRA     := 6
const MAT_DESERT     := 7
const MAT_SWAMP      := 8

## 生成三角网格。
func build_mesh(chunk: PlanetChunk, height_z_scale: float = 0.0) -> ArrayMesh:
	var res := chunk.resolution
	if res < 2:
		return ArrayMesh.new()

	var points := res + 1        # 每边 (res+1) 个点
	var step := chunk.world_size / float(res)
	var half := float(res) * 0.5

	var total := points * points
	var verts := PackedVector3Array(); verts.resize(total)
	var colors := PackedColorArray(); colors.resize(total)

	for py in range(points):
		for px in range(points):
			var idx := chunk.local_index(px, py)
			var h := chunk.get_final_height(idx)
			var wx := (float(px) - half) * step
			var wy := (float(py) - half) * step
			var wz := h * height_z_scale
			var vi := py * points + px
			verts[vi] = Vector3(wx, wy, wz)
			colors[vi] = color_for_height(h)

	var quads := res * res
	var indices := PackedInt32Array(); indices.resize(quads * 6)
	var ii := 0
	for py in range(res):
		for px in range(res):
			var v00 := py * points + px
			var v10 := v00 + 1
			var v01 := v00 + points
			var v11 := v01 + 1
			indices[ii] = v00; ii += 1
			indices[ii] = v10; ii += 1
			indices[ii] = v01; ii += 1
			indices[ii] = v10; ii += 1
			indices[ii] = v11; ii += 1
			indices[ii] = v01; ii += 1

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## 按高度分层配色。与 map_view.gdshader 的 height_color 视觉一致。
static func color_for_height(h: float) -> Color:
	if h < 0.0:
		var t := clampf(-h / 0.30, 0.0, 1.0)
		return Color(0.22, 0.52, 0.72).lerp(Color(0.05, 0.14, 0.34), t)
	if h < 0.02:
		return Color(0.86, 0.80, 0.58)
	if h < 0.08:
		return Color(0.86, 0.80, 0.58).lerp(
			Color(0.45, 0.72, 0.35), (h - 0.02) / 0.06)
	if h < 0.20:
		return Color(0.45, 0.72, 0.35).lerp(
			Color(0.25, 0.50, 0.25), (h - 0.08) / 0.12)
	if h < 0.35:
		return Color(0.25, 0.50, 0.25).lerp(
			Color(0.55, 0.58, 0.32), (h - 0.20) / 0.15)
	if h < 0.50:
		return Color(0.55, 0.58, 0.32).lerp(
			Color(0.60, 0.55, 0.48), (h - 0.35) / 0.15)
	return Color(0.60, 0.55, 0.48).lerp(
		Color(0.95, 0.96, 0.98), clampf((h - 0.50) / 0.20, 0.0, 1.0))