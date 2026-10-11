class_name FaceLookup
extends RefCounted
## 方向 → 最近面索引 的快速查找。

const GRID_LON := 32
const GRID_LAT := 16

var gp: GoldbergPolyhedron
var _cells: Array = []

func setup(poly: GoldbergPolyhedron) -> void:
	gp = poly
	_cells.resize(GRID_LON * GRID_LAT)
	for i in _cells.size():
		_cells[i] = PackedInt32Array()

	for f in gp.face_count:
		var dir := gp.face_normals[f]
		var key := _cell_key(dir)
		_cells[key].append(f)

func find(dir: Vector3) -> int:
	if gp == null:
		return -1

	var lon_c := _lon_cell(dir)
	var lat_c := _lat_cell(dir)

	var best := -1
	var best_dot := -2.0

	for dl in range(-2, 3):
		for dr in range(-2, 3):
			var lc := posmod(lon_c + dl, GRID_LON)
			var rc := lat_c + dr
			if rc < 0 or rc >= GRID_LAT:
				continue
			var key := rc * GRID_LON + lc
			for f in _cells[key]:
				var d := gp.face_normals[f].dot(dir)
				if d > best_dot:
					best_dot = d
					best = f

	if best < 0 or best_dot < 0.9995:
		best = -1
		best_dot = -2.0
		for f in gp.face_count:
			var d := gp.face_normals[f].dot(dir)
			if d > best_dot:
				best_dot = d
				best = f

	return best

func _cell_key(dir: Vector3) -> int:
	return _lat_cell(dir) * GRID_LON + _lon_cell(dir)

func _lon_cell(dir: Vector3) -> int:
	var lon := atan2(dir.z, dir.x)
	return int((lon + PI) / TAU * GRID_LON) % GRID_LON

func _lat_cell(dir: Vector3) -> int:
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	return clampi(int((lat + PI / 2.0) / PI * GRID_LAT), 0, GRID_LAT - 1)