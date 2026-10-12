class_name GoldbergMeshBuilder
extends RefCounted
## Goldberg 多面体 → ArrayMesh 的构建器。
## 从 core 拆出，渲染逻辑不再混在拓扑数据类里。
##
## 用法：
##   var mesh := GoldbergMeshBuilder.build(gp, colors)
##   var mi := GoldbergMeshBuilder.build_instance(gp, colors)

## colors 为空时：五边形红色，六边形按面索引蓝→橙渐变。
static func build(gp: GoldbergPolyhedron, colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var use_custom := colors.size() == gp.face_count

	var out_verts := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_colors := PackedColorArray()
	var out_indices := PackedInt32Array()

	for f_idx in gp.face_count:
		var center: Vector3 = gp.face_centers[f_idx]
		var center_n: Vector3 = gp.face_normals[f_idx]
		var start := gp.face_vertex_offsets[f_idx]
		var end := gp.face_vertex_offsets[f_idx + 1]
		var n := end - start

		var col: Color
		if use_custom:
			col = colors[f_idx]
		elif gp.is_pentagon(f_idx):
			col = Color(1.0, 0.35, 0.25)
		else:
			var t: float = float(f_idx) / float(gp.face_count)
			col = Color(0.20, 0.45, 0.85).lerp(Color(0.95, 0.75, 0.45), t)

		var base: int = out_verts.size()
		out_verts.append(center)
		out_normals.append(center_n)
		out_colors.append(col)

		for i in n:
			var vi: int = gp.face_vertex_indices[start + i]
			var vp: Vector3 = gp.vertex_positions[vi]
			out_verts.append(vp)
			out_normals.append(vp.normalized())
			out_colors.append(col)

		for i in n:
			var a: int = base + 1 + i
			var b: int = base + 1 + ((i + 1) % n)
			out_indices.append(base)
			out_indices.append(a)
			out_indices.append(b)

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_verts
	arrays[Mesh.ARRAY_NORMAL] = out_normals
	arrays[Mesh.ARRAY_COLOR] = out_colors
	arrays[Mesh.ARRAY_INDEX] = out_indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## 便捷方法：生成带默认材质的 MeshInstance3D。
static func build_instance(gp: GoldbergPolyhedron,
		colors: PackedColorArray = PackedColorArray()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build(gp, colors)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.metallic = 0.0
	mi.material_override = mat
	return mi