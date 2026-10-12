class_name GoldbergPolyhedron
extends RefCounted
## 戈德堡多面体的数据容器。
##
## 拓扑约定
## --------
##   每个 GP 面（五边形/六边形）对应一个测地线顶点。
##   每个 GP 顶点对应一个测地线三角形重心。
##   面与面相邻  <=>  对应的测地线顶点共享一条测地线边。
##
## GPU 数据布局（扁平、固定步长）
## ----------------------------
##   面索引 f ∈ [0, face_count)
##   邻居槽 s ∈ [0, 6)
##   邻居索引      face_neighbors[f * 6 + s]     无效为 -1
##   切向单位向量  face_edge_dirs[f * 6 + s]     从 f 指向邻居
##   弧长          face_edge_arc[f * 6 + s]      radius * 球面中心夹角
##
## 构建逻辑见 GoldbergBuilder，序列化见 GoldbergSerializer。

const MAX_NEIGHBORS := 6
const MAX_SUBDIVISION := 64

# ---- 权威数据 ----
var subdivision: int = 0
var radius: float = 1.0

# ---- 面 ----
var face_count: int = 0
var face_centers: PackedVector3Array
var face_normals: PackedVector3Array
var face_areas: PackedFloat32Array
var face_sides: PackedInt32Array
var face_is_pentagon: PackedByteArray

# ---- 邻接（固定步长 6） ----
var face_neighbors: PackedInt32Array
var face_neighbor_count: PackedInt32Array
var face_edge_dirs: PackedVector3Array
var face_edge_arc: PackedFloat32Array

# ---- 顶点（面角点） ----
var vertex_count: int = 0
var vertex_positions: PackedVector3Array

# ---- 面 → 顶点环 ----
var face_vertex_offsets: PackedInt32Array
var face_vertex_indices: PackedInt32Array

# ============================================================
#  工厂 + 缓存
# ============================================================

static var _cache: Dictionary = {}

static func get_or_create(subdiv: int, r: float = 1.0) -> GoldbergPolyhedron:
	var key := "%d_%d" % [subdiv, int(round(r * 1000.0))]
	if _cache.has(key):
		return _cache[key]
	var gp := GoldbergPolyhedron.new()
	GoldbergBuilder.build(gp, subdiv, r)
	_cache[key] = gp
	return gp

static func clear_cache() -> void:
	_cache.clear()

# ============================================================
#  查询
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
#  GPU 数据打包
# ============================================================

func export_gpu_buffers() -> Dictionary:
	return {
		"face_count": face_count,
		"vertex_count": vertex_count,
		"max_neighbors": MAX_NEIGHBORS,
		"face_centers": face_centers,
		"face_normals": face_normals,
		"face_areas": face_areas,
		"face_sides": face_sides,
		"face_is_pentagon": face_is_pentagon,
		"face_neighbors": face_neighbors,
		"face_neighbor_count": face_neighbor_count,
		"face_edge_dirs": face_edge_dirs,
		"face_edge_arc": face_edge_arc,
		"vertex_positions": vertex_positions,
		"face_vertex_offsets": face_vertex_offsets,
		"face_vertex_indices": face_vertex_indices,
	}