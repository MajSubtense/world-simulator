class_name GoldbergSerializer
extends RefCounted
## GoldbergPolyhedron 的二进制序列化。
## 格式头：MAGIC (4B) + VERSION (4B)，便于未来格式升级时校验。

const MAGIC := 0x47504F4C   # "GPOL"
const VERSION := 1

static func save(gp: GoldbergPolyhedron, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("GoldbergSerializer: 无法写入 %s" % path)
		return false
	f.store_32(MAGIC)
	f.store_32(VERSION)
	f.store_32(gp.subdivision)
	f.store_float(gp.radius)
	f.store_32(gp.face_count)
	f.store_32(gp.vertex_count)
	f.store_var(gp.face_centers)
	f.store_var(gp.face_normals)
	f.store_var(gp.face_areas)
	f.store_var(gp.face_sides)
	f.store_var(gp.face_is_pentagon)
	f.store_var(gp.face_neighbors)
	f.store_var(gp.face_neighbor_count)
	f.store_var(gp.face_edge_dirs)
	f.store_var(gp.face_edge_arc)
	f.store_var(gp.vertex_positions)
	f.store_var(gp.face_vertex_offsets)
	f.store_var(gp.face_vertex_indices)
	f.close()
	return true

static func load_binary(path: String) -> GoldbergPolyhedron:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null

	var magic := f.get_32()
	if magic != MAGIC:
		push_error("GoldbergSerializer: magic 不匹配 0x%X" % magic)
		f.close()
		return null
	var version := f.get_32()
	if version != VERSION:
		push_error("GoldbergSerializer: 版本不匹配 %d（当前 %d）" % [version, VERSION])
		f.close()
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