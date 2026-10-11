class_name GoldbergPolyhedron
extends RefCounted
## 戈德堡多面体的最终数据容器。
##
## 拓扑约定
## --------
##   每个 GP 面（五边形/六边形）对应一个测地线顶点。
##   每个 GP 顶点对应一个测地线三角形重心。
##   面与面相邻  <=>  对应的测地线顶点共享一条测地线边。
##
## GPU 数据布局（全部扁平、固定步长）
## --------------------------------
##   面索引 f ∈ [0, face_count)
##   邻居槽 s ∈ [0, 6)
##   邻居索引      face_neighbors[f * 6 + s]     无效为 -1
##   切向单位向量  face_edge_dirs[f * 6 + s]     从 f 指向邻居
##   弧长          face_edge_arc[f * 6 + s]      radius * 球面中心夹角
##
## 该文件一旦定型，后续不应再修改。物理模拟相关的数据
## （温度、湿度、气压等标量场）请放到 PlanetWorld 中维护。

const MAX_NEIGHBORS := 6
const PHI := (1.0 + sqrt(5.0)) / 2.0
const DEDUPE_SCALE := 10000.0
const MAX_SUBDIVISION := 64

# ============================================================
#  权威数据
# ============================================================

var subdivision: int = 0
var radius: float = 1.0

# ---- 面 ----
var face_count: int = 0
var face_centers: PackedVector3Array       # N      ：面中心（已乘 radius）
var face_normals: PackedVector3Array       # N      ：面中心方向（单位向量）
var face_areas: PackedFloat32Array         # N      ：球面面积
var face_sides: PackedInt32Array           # N      ：边数（5 / 6）
var face_is_pentagon: PackedByteArray      # N      ：1 表示五边形

# ---- 邻接（固定步长 6） ----
var face_neighbors: PackedInt32Array       # N*6    ：邻居索引，无效槽为 -1
var face_neighbor_count: PackedInt32Array  # N      ：有效邻居数
var face_edge_dirs: PackedVector3Array     # N*6    ：切向单位向量 i→j
var face_edge_arc: PackedFloat32Array      # N*6    ：弧长

# ---- 顶点（面角点） ----
var vertex_count: int = 0
var vertex_positions: PackedVector3Array   # V      ：角点坐标（已乘 radius）

# ---- 面 → 顶点环（扁平化） ----
var face_vertex_offsets: PackedInt32Array  # N+1    ：每个面顶点环在 indices 中的起止
var face_vertex_indices: PackedInt32Array  # 全部顶点环拼接

# ============================================================
#  工厂 + 缓存
# ============================================================

static var _cache: Dictionary = {}

## 相同 subdivision/radius 返回同一实例，避免重复构建。
static func get_or_create(subdiv: int, r: float = 1.0) -> GoldbergPolyhedron:
	var key := "%d_%d" % [subdiv, int(round(r * 1000.0))]
	if _cache.has(key):
		return _cache[key]
	var gp := GoldbergPolyhedron.new()
	gp._build(subdiv, r)
	_cache[key] = gp
	return gp

static func clear_cache() -> void:
	_cache.clear()

# ============================================================
#  查询便捷方法
# ============================================================

func get_face_count() -> int:
	return face_count

func get_vertex_count() -> int:
	return vertex_count

func get_face_center(f: int) -> Vector3:
	return face_centers[f]

func get_neighbor(f: int, slot: int) -> int:
	return face_neighbors[f * MAX_NEIGHBORS + slot]

func get_edge_dir(f: int, slot: int) -> Vector3:
	return face_edge_dirs[f * MAX_NEIGHBORS + slot]

func get_edge_arc(f: int, slot: int) -> float:
	return face_edge_arc[f * MAX_NEIGHBORS + slot]

func is_pentagon(f: int) -> bool:
	return face_is_pentagon[f] == 1

# ============================================================
#  构建
# ============================================================

func _build(subdiv: int, r: float) -> void:
	subdivision = clampi(subdiv, 1, MAX_SUBDIVISION)
	radius = r

	var geo := _build_geodesic(subdivision)
	var geo_verts: Array = geo.vertices
	var geo_tris: Array = geo.triangles

	# ---- 1. GP 顶点 = 测地线三角形重心 ----
	var g_verts := PackedVector3Array()
	g_verts.resize(geo_tris.size())
	for i in geo_tris.size():
		var t: Array = geo_tris[i]
		var c: Vector3 = (geo_verts[t[0]] + geo_verts[t[1]] + geo_verts[t[2]]) / 3.0
		g_verts[i] = c.normalized() * radius
	vertex_positions = g_verts
	vertex_count = g_verts.size()

	# ---- 2. 测地线顶点 → 相邻三角形 ----
	var v_to_tris: Dictionary = {}
	for ti in geo_tris.size():
		for v in geo_tris[ti]:
			if not v_to_tris.has(v):
				v_to_tris[v] = PackedInt32Array()
			v_to_tris[v].append(ti)

	# ---- 3. GP 面 ----
	var f_count: int = geo_verts.size()
	face_count = f_count

	face_centers = PackedVector3Array()
	face_centers.resize(f_count)
	face_normals = PackedVector3Array()
	face_normals.resize(f_count)
	face_areas = PackedFloat32Array()
	face_areas.resize(f_count)
	face_sides = PackedInt32Array()
	face_sides.resize(f_count)
	face_is_pentagon = PackedByteArray()
	face_is_pentagon.resize(f_count)

	face_vertex_offsets = PackedInt32Array()
	face_vertex_offsets.resize(f_count + 1)
	var v_indices := PackedInt32Array()

	for v_idx in f_count:
		var v_dir: Vector3 = geo_verts[v_idx].normalized()
		face_centers[v_idx] = v_dir * radius
		face_normals[v_idx] = v_dir

		var tris: PackedInt32Array = v_to_tris.get(v_idx, PackedInt32Array())
		face_sides[v_idx] = tris.size()
		face_is_pentagon[v_idx] = 1 if tris.size() == 5 else 0

		# 绕 v_dir 的切平面基（用于稳定排序）
		var ref: Vector3 = Vector3.UP if abs(v_dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u: Vector3 = ref.cross(v_dir).normalized()
		var w: Vector3 = v_dir.cross(u)

		var sorted: Array = []
		for ti in tris:
			var c: Vector3 = g_verts[ti]
			var d: Vector3 = c - v_dir * c.dot(v_dir)
			sorted.append({"angle": atan2(d.dot(w), d.dot(u)), "tri": ti})
		sorted.sort_custom(_angle_less)

		face_vertex_offsets[v_idx] = v_indices.size()
		for item in sorted:
			v_indices.append(item.tri)

	face_vertex_offsets[f_count] = v_indices.size()
	face_vertex_indices = v_indices

	# ---- 4. 面邻接（通过测地线边） ----
	var edges: Dictionary = {}
	for tri in geo_tris:
		for k in 3:
			var a: int = tri[k]
			var b: int = tri[(k + 1) % 3]
			var lo: int = min(a, b)
			var hi: int = max(a, b)
			edges[Vector2i(lo, hi)] = true

	var adj_lists: Array = []
	adj_lists.resize(f_count)
	for i in f_count:
		adj_lists[i] = []
	for key in edges.keys():
		adj_lists[key.x].append(key.y)
		adj_lists[key.y].append(key.x)

	# 按切平面角度对邻居排序，保证槽位顺序跨平台一致
	for f_idx in f_count:
		var c_i: Vector3 = face_normals[f_idx]
		var ref2: Vector3 = Vector3.UP if abs(c_i.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u2: Vector3 = ref2.cross(c_i).normalized()
		var w2: Vector3 = c_i.cross(u2)
		var ordered: Array = []
		for nb in adj_lists[f_idx]:
			var d: Vector3 = face_normals[nb] - c_i * face_normals[nb].dot(c_i)
			ordered.append({"angle": atan2(d.dot(w2), d.dot(u2)), "idx": nb})
		ordered.sort_custom(func(a, b):
			if abs(a.angle - b.angle) < 0.0001:
				return a.idx < b.idx
			return a.angle < b.angle
		)
		adj_lists[f_idx] = ordered

	# 固定步长扁平化
	face_neighbors = PackedInt32Array()
	face_neighbors.resize(f_count * MAX_NEIGHBORS)
	face_neighbor_count = PackedInt32Array()
	face_neighbor_count.resize(f_count)
	face_edge_dirs = PackedVector3Array()
	face_edge_dirs.resize(f_count * MAX_NEIGHBORS)
	face_edge_arc = PackedFloat32Array()
	face_edge_arc.resize(f_count * MAX_NEIGHBORS)

	for f_idx in f_count:
		var ordered: Array = adj_lists[f_idx]
		face_neighbor_count[f_idx] = ordered.size()
		for s in MAX_NEIGHBORS:
			var base := f_idx * MAX_NEIGHBORS + s
			if s < ordered.size():
				var nb: int = ordered[s].idx
				face_neighbors[base] = nb

				# 切向单位方向（球面切平面上的 i→j 方向）
				var dot_c: float = face_normals[nb].dot(face_normals[f_idx])
				var d: Vector3 = face_normals[nb] - face_normals[f_idx] * dot_c
				if d.length() > 1e-6:
					d = d.normalized()
				face_edge_dirs[base] = d

				# 弧长
				var angle: float = acos(clampf(dot_c, -1.0, 1.0))
				face_edge_arc[base] = radius * angle
			else:
				face_neighbors[base] = -1
				face_edge_dirs[base] = Vector3.ZERO
				face_edge_arc[base] = 0.0

	# ---- 5. 面面积（球面过多边形面积） ----
	for f_idx in f_count:
		face_areas[f_idx] = _compute_face_area(f_idx) * radius * radius

func _angle_less(a: Dictionary, b: Dictionary) -> bool:
	if abs(a.angle - b.angle) < 0.0001:
		return a.tri < b.tri
	return a.angle < b.angle

# ============================================================
#  球面几何
# ============================================================

func _compute_face_area(f_idx: int) -> float:
	var start := face_vertex_offsets[f_idx]
	var end := face_vertex_offsets[f_idx + 1]
	var n := end - start
	if n < 3:
		return 0.0
	var c := face_normals[f_idx]
	var total := 0.0
	for i in n:
		var a := vertex_positions[face_vertex_indices[start + i]].normalized()
		var b := vertex_positions[face_vertex_indices[start + ((i + 1) % n)]].normalized()
		total += _spherical_triangle_area(c, a, b)
	return total

func _spherical_triangle_area(a: Vector3, b: Vector3, c: Vector3) -> float:
	# L'Huilier 公式（单位球面）
	var ab := acos(clampf(a.dot(b), -1.0, 1.0))
	var bc := acos(clampf(b.dot(c), -1.0, 1.0))
	var ca := acos(clampf(c.dot(a), -1.0, 1.0))
	var s := (ab + bc + ca) * 0.5
	var t := tan(s * 0.5) * tan((s - ab) * 0.5) * tan((s - bc) * 0.5) * tan((s - ca) * 0.5)
	if t <= 0.0:
		return 0.0
	return 4.0 * atan(sqrt(t))

# ============================================================
#  测地线球面构建
# ============================================================

func _build_geodesic(n: int) -> Dictionary:
	var ico_verts := _make_icosahedron()
	var ico_faces := _make_icosahedron_faces()

	var verts: Array = []
	var triangles: Array = []
	var cache: Dictionary = {}

	for face in ico_faces:
		var A: Vector3 = ico_verts[face[0]]
		var B: Vector3 = ico_verts[face[1]]
		var C: Vector3 = ico_verts[face[2]]

		var grid: Array = []
		for i in range(n + 1):
			var row: Array = []
			for j in range(n + 1 - i):
				var k: int = n - i - j
				var p: Vector3 = (A * float(i) + B * float(j) + C * float(k)) / float(n)
				p = p.normalized() * radius
				row.append(_dedupe(verts, cache, p))
			grid.append(row)

		for i in range(n):
			for j in range(n - i):
				var v0: int = grid[i][j]
				var v1: int = grid[i + 1][j]
				var v2: int = grid[i][j + 1]
				triangles.append([v0, v1, v2])
				if j < n - i - 1:
					var v3: int = grid[i + 1][j + 1]
					triangles.append([v1, v3, v2])

	return {"vertices": verts, "triangles": triangles}

func _make_icosahedron() -> Array:
	var t := PHI
	var verts := [
		Vector3(-1,  t,  0), Vector3( 1,  t,  0),
		Vector3(-1, -t,  0), Vector3( 1, -t,  0),
		Vector3( 0, -1,  t), Vector3( 0,  1,  t),
		Vector3( 0, -1, -t), Vector3( 0,  1, -t),
		Vector3( t,  0, -1), Vector3( t,  0,  1),
		Vector3(-t,  0, -1), Vector3(-t,  0,  1),
	]
	for i in verts.size():
		verts[i] = verts[i].normalized() * radius
	return verts

func _make_icosahedron_faces() -> Array:
	return [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

func _dedupe(verts: Array, cache: Dictionary, p: Vector3) -> int:
	var key := Vector3i(
		int(round(p.x * DEDUPE_SCALE)),
		int(round(p.y * DEDUPE_SCALE)),
		int(round(p.z * DEDUPE_SCALE)),
	)
	if cache.has(key):
		return cache[key]
	verts.append(p)
	var idx: int = verts.size() - 1
	cache[key] = idx
	return idx

# ============================================================
#  GPU 缓冲区导出
# ============================================================

## 返回一个字典，值全部为 Packed 数组，可直接上传到 RenderingDevice。
func export_gpu_buffers() -> Dictionary:
	return {
		"face_count": face_count,
		"vertex_count": vertex_count,
		"max_neighbors": MAX_NEIGHBORS,
		"face_centers": face_centers,               # PackedVector3Array
		"face_normals": face_normals,               # PackedVector3Array
		"face_areas": face_areas,                   # PackedFloat32Array
		"face_sides": face_sides,                   # PackedInt32Array
		"face_is_pentagon": face_is_pentagon,       # PackedByteArray
		"face_neighbors": face_neighbors,           # PackedInt32Array (N*6)
		"face_neighbor_count": face_neighbor_count, # PackedInt32Array (N)
		"face_edge_dirs": face_edge_dirs,           # PackedVector3Array (N*6)
		"face_edge_arc": face_edge_arc,             # PackedFloat32Array (N*6)
		"vertex_positions": vertex_positions,       # PackedVector3Array
		"face_vertex_offsets": face_vertex_offsets, # PackedInt32Array (N+1)
		"face_vertex_indices": face_vertex_indices, # PackedInt32Array
	}

# ============================================================
#  序列化
# ============================================================

func save_binary(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入：%s" % path)
		return false
	f.store_32(subdivision)
	f.store_float(radius)
	f.store_32(face_count)
	f.store_32(vertex_count)
	f.store_var(face_centers)
	f.store_var(face_normals)
	f.store_var(face_areas)
	f.store_var(face_sides)
	f.store_var(face_is_pentagon)
	f.store_var(face_neighbors)
	f.store_var(face_neighbor_count)
	f.store_var(face_edge_dirs)
	f.store_var(face_edge_arc)
	f.store_var(vertex_positions)
	f.store_var(face_vertex_offsets)
	f.store_var(face_vertex_indices)
	f.close()
	return true

static func load_binary(path: String) -> GoldbergPolyhedron:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var gp := GoldbergPolyhedron.new()
	gp.subdivision = f.get_32()
	gp.radius = f.get_float()
	gp.face_count = f.get_32()
	gp.vertex_count = f.get_32()
	gp.face_centers = f.get_var()
	gp.face_normals = f.get_var()
	gp.face_areas = f.get_var()
	gp.face_sides = f.get_var()
	gp.face_is_pentagon = f.get_var()
	gp.face_neighbors = f.get_var()
	gp.face_neighbor_count = f.get_var()
	gp.face_edge_dirs = f.get_var()
	gp.face_edge_arc = f.get_var()
	gp.vertex_positions = f.get_var()
	gp.face_vertex_offsets = f.get_var()
	gp.face_vertex_indices = f.get_var()
	f.close()
	return gp

# ============================================================
#  渲染
# ============================================================

## 三角扇构建 ArrayMesh。
## colors 为空 → 五边形红色、六边形按索引渐变。
func build_mesh(colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var use_custom := colors.size() == face_count

	var out_verts := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_colors := PackedColorArray()
	var out_indices := PackedInt32Array()

	for f_idx in face_count:
		var center: Vector3 = face_centers[f_idx]
		var center_n: Vector3 = face_normals[f_idx]
		var start := face_vertex_offsets[f_idx]
		var end := face_vertex_offsets[f_idx + 1]
		var n := end - start

		var col: Color
		if use_custom:
			col = colors[f_idx]
		elif is_pentagon(f_idx):
			col = Color(1.0, 0.35, 0.25)
		else:
			var t: float = float(f_idx) / float(face_count)
			col = Color(0.20, 0.45, 0.85).lerp(Color(0.95, 0.75, 0.45), t)

		var base: int = out_verts.size()
		out_verts.append(center)
		out_normals.append(center_n)
		out_colors.append(col)

		for i in n:
			var vi: int = face_vertex_indices[start + i]
			var vp: Vector3 = vertex_positions[vi]
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
func build_mesh_instance(colors: PackedColorArray = PackedColorArray()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build_mesh(colors)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.metallic = 0.0
	mi.material_override = mat
	return mi