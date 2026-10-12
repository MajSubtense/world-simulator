class_name GoldbergBuilder
extends RefCounted
## Goldberg 多面体构建。从测地线球面组装 GP 面拓扑。
## 对外只暴露 build()。

const PHI := (1.0 + sqrt(5.0)) / 2.0
const DEDUPE_SCALE := 10000.0

static func build(gp: GoldbergPolyhedron, subdiv: int, r: float) -> void:
	gp.subdivision = clampi(subdiv, 1, GoldbergPolyhedron.MAX_SUBDIVISION)
	gp.radius = r

	var geo := _build_geodesic(gp.subdivision, r)
	var geo_verts: Array = geo.vertices
	var geo_tris: Array = geo.triangles

	# ---- 1. GP 顶点 = 测地线三角形重心 ----
	var g_verts := PackedVector3Array()
	g_verts.resize(geo_tris.size())
	for i in geo_tris.size():
		var t: Array = geo_tris[i]
		var c: Vector3 = (geo_verts[t[0]] + geo_verts[t[1]] + geo_verts[t[2]]) / 3.0
		g_verts[i] = c.normalized() * r
	gp.vertex_positions = g_verts
	gp.vertex_count = g_verts.size()

	# ---- 2. 测地线顶点 → 相邻三角形 ----
	var v_to_tris: Dictionary = {}
	for ti in geo_tris.size():
		for v in geo_tris[ti]:
			if not v_to_tris.has(v):
				v_to_tris[v] = PackedInt32Array()
			v_to_tris[v].append(ti)

	# ---- 3. GP 面 ----
	var f_count: int = geo_verts.size()
	gp.face_count = f_count

	gp.face_centers = PackedVector3Array(); gp.face_centers.resize(f_count)
	gp.face_normals = PackedVector3Array(); gp.face_normals.resize(f_count)
	gp.face_areas = PackedFloat32Array(); gp.face_areas.resize(f_count)
	gp.face_sides = PackedInt32Array(); gp.face_sides.resize(f_count)
	gp.face_is_pentagon = PackedByteArray(); gp.face_is_pentagon.resize(f_count)

	gp.face_vertex_offsets = PackedInt32Array()
	gp.face_vertex_offsets.resize(f_count + 1)
	var v_indices := PackedInt32Array()

	for v_idx in f_count:
		var v_dir: Vector3 = geo_verts[v_idx].normalized()
		gp.face_centers[v_idx] = v_dir * r
		gp.face_normals[v_idx] = v_dir

		var tris: PackedInt32Array = v_to_tris.get(v_idx, PackedInt32Array())
		gp.face_sides[v_idx] = tris.size()
		gp.face_is_pentagon[v_idx] = 1 if tris.size() == 5 else 0

		var ref: Vector3 = Vector3.UP if abs(v_dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u: Vector3 = ref.cross(v_dir).normalized()
		var w: Vector3 = v_dir.cross(u)

		var sorted: Array = []
		for ti in tris:
			var c: Vector3 = g_verts[ti]
			var d: Vector3 = c - v_dir * c.dot(v_dir)
			sorted.append({"angle": atan2(d.dot(w), d.dot(u)), "tri": ti})
		sorted.sort_custom(_angle_less)

		gp.face_vertex_offsets[v_idx] = v_indices.size()
		for item in sorted:
			v_indices.append(item.tri)

	gp.face_vertex_offsets[f_count] = v_indices.size()
	gp.face_vertex_indices = v_indices

	# ---- 4. 面邻接 ----
	var edges: Dictionary = {}
	for tri in geo_tris:
		for k in 3:
			var a: int = tri[k]
			var b: int = tri[(k + 1) % 3]
			var lo: int = mini(a, b)
			var hi: int = maxi(a, b)
			edges[Vector2i(lo, hi)] = true

	var adj_lists: Array = []
	adj_lists.resize(f_count)
	for i in f_count:
		adj_lists[i] = []
	for key in edges.keys():
		adj_lists[key.x].append(key.y)
		adj_lists[key.y].append(key.x)

	for f_idx in f_count:
		var c_i: Vector3 = gp.face_normals[f_idx]
		var ref2: Vector3 = Vector3.UP if abs(c_i.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u2: Vector3 = ref2.cross(c_i).normalized()
		var w2: Vector3 = c_i.cross(u2)
		var ordered: Array = []
		for nb in adj_lists[f_idx]:
			var d: Vector3 = gp.face_normals[nb] - c_i * gp.face_normals[nb].dot(c_i)
			ordered.append({"angle": atan2(d.dot(w2), d.dot(u2)), "idx": nb})
		ordered.sort_custom(func(a, b):
			if abs(a.angle - b.angle) < 0.0001:
				return a.idx < b.idx
			return a.angle < b.angle
		)
		adj_lists[f_idx] = ordered

	gp.face_neighbors = PackedInt32Array()
	gp.face_neighbors.resize(f_count * GoldbergPolyhedron.MAX_NEIGHBORS)
	gp.face_neighbor_count = PackedInt32Array()
	gp.face_neighbor_count.resize(f_count)
	gp.face_edge_dirs = PackedVector3Array()
	gp.face_edge_dirs.resize(f_count * GoldbergPolyhedron.MAX_NEIGHBORS)
	gp.face_edge_arc = PackedFloat32Array()
	gp.face_edge_arc.resize(f_count * GoldbergPolyhedron.MAX_NEIGHBORS)

	for f_idx in f_count:
		var ordered: Array = adj_lists[f_idx]
		gp.face_neighbor_count[f_idx] = ordered.size()
		for s in GoldbergPolyhedron.MAX_NEIGHBORS:
			var base := f_idx * GoldbergPolyhedron.MAX_NEIGHBORS + s
			if s < ordered.size():
				var nb: int = ordered[s].idx
				gp.face_neighbors[base] = nb

				var dot_c: float = gp.face_normals[nb].dot(gp.face_normals[f_idx])
				var d: Vector3 = gp.face_normals[nb] - gp.face_normals[f_idx] * dot_c
				if d.length() > 1e-6:
					d = d.normalized()
				gp.face_edge_dirs[base] = d

				var angle: float = acos(clampf(dot_c, -1.0, 1.0))
				gp.face_edge_arc[base] = r * angle
			else:
				gp.face_neighbors[base] = -1
				gp.face_edge_dirs[base] = Vector3.ZERO
				gp.face_edge_arc[base] = 0.0

	# ---- 5. 面面积 ----
	for f_idx in f_count:
		gp.face_areas[f_idx] = _compute_face_area(gp, f_idx) * r * r

# ============================================================
#  内部工具
# ============================================================

static func _angle_less(a: Dictionary, b: Dictionary) -> bool:
	if abs(a.angle - b.angle) < 0.0001:
		return a.tri < b.tri
	return a.angle < b.angle

static func _compute_face_area(gp: GoldbergPolyhedron, f_idx: int) -> float:
	var start := gp.face_vertex_offsets[f_idx]
	var end := gp.face_vertex_offsets[f_idx + 1]
	var n := end - start
	if n < 3:
		return 0.0
	var c := gp.face_normals[f_idx]
	var total := 0.0
	for i in n:
		var a := gp.vertex_positions[gp.face_vertex_indices[start + i]].normalized()
		var b := gp.vertex_positions[gp.face_vertex_indices[start + ((i + 1) % n)]].normalized()
		total += _spherical_triangle_area(c, a, b)
	return total

static func _spherical_triangle_area(a: Vector3, b: Vector3, c: Vector3) -> float:
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
#  测地线球面
# ============================================================

static func _build_geodesic(n: int, r: float) -> Dictionary:
	var ico_verts := _make_icosahedron(r)
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
				p = p.normalized() * r
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

static func _make_icosahedron(r: float) -> Array:
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
		verts[i] = verts[i].normalized() * r
	return verts

static func _make_icosahedron_faces() -> Array:
	return [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

static func _dedupe(verts: Array, cache: Dictionary, p: Vector3) -> int:
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