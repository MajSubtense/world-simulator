class_name PlanetData
extends Resource

enum Phase { LAND, HEIGHT, CLIMATE }

var gp: GoldbergPolyhedron

# ---- 阶段 1 ----
var v_is_land: PackedByteArray

# ---- 阶段 2 ----
var v_height: PackedFloat32Array
var f_elevation: PackedFloat32Array

# ---- 阶段 3：气候 ----
var f_temperature: PackedFloat32Array
var f_pressure: PackedFloat32Array
var f_wind: PackedVector3Array
var f_humidity_atm: PackedFloat32Array
var f_cloud: PackedFloat32Array
var f_precipitation: PackedFloat32Array
var f_snow: PackedFloat32Array
var f_soil_water: PackedFloat32Array     # ★ 唯一的陆地水字段
var f_river_input: PackedFloat32Array

# ---- 阶段 3：河流 ----
var f_flow_dir: PackedInt32Array
var f_flow: PackedFloat32Array

# ---- 气候常量 ----
var f_heat_capacity: PackedFloat32Array
var f_base_temperature: PackedFloat32Array

# ★ 从 LAND 阶段就存在
var f_is_land_face: PackedByteArray
var f_land_score: PackedFloat32Array

var phase: int = Phase.LAND

# ============================================================
func init(poly: GoldbergPolyhedron) -> void:
	gp = poly
	var V := gp.vertex_count
	var N := gp.face_count

	v_is_land.resize(V); v_is_land.fill(0)
	v_height.resize(V); v_height.fill(0.0)
	f_elevation.resize(N); f_elevation.fill(0.0)

	f_temperature = PackedFloat32Array()
	f_pressure = PackedFloat32Array()
	f_wind = PackedVector3Array()
	f_humidity_atm = PackedFloat32Array()
	f_cloud = PackedFloat32Array()
	f_precipitation = PackedFloat32Array()
	f_snow = PackedFloat32Array()
	f_soil_water = PackedFloat32Array()
	f_river_input = PackedFloat32Array()
	f_flow_dir = PackedInt32Array()
	f_flow = PackedFloat32Array()
	f_heat_capacity = PackedFloat32Array()
	f_base_temperature = PackedFloat32Array()

	f_is_land_face = PackedByteArray(); f_is_land_face.resize(N)
	f_land_score = PackedFloat32Array(); f_land_score.resize(N)
	for f in N:
		f_is_land_face[f] = 1 if _face_is_land(f) else 0

	phase = Phase.LAND

func sync_face_elevation() -> void:
	for f in gp.face_count:
		var start := gp.face_vertex_offsets[f]
		var end := gp.face_vertex_offsets[f + 1]
		var s := 0.0
		for i in range(start, end):
			s += v_height[gp.face_vertex_indices[i]]
		f_elevation[f] = s / float(end - start)

func init_climate() -> void:
	var N := gp.face_count

	f_temperature = PackedFloat32Array(); f_temperature.resize(N)
	f_pressure    = PackedFloat32Array(); f_pressure.resize(N)
	f_wind        = PackedVector3Array(); f_wind.resize(N)
	f_humidity_atm = PackedFloat32Array(); f_humidity_atm.resize(N)
	f_cloud = PackedFloat32Array(); f_cloud.resize(N)
	f_precipitation = PackedFloat32Array(); f_precipitation.resize(N)
	f_snow = PackedFloat32Array(); f_snow.resize(N)
	f_soil_water = PackedFloat32Array(); f_soil_water.resize(N)
	f_river_input = PackedFloat32Array(); f_river_input.resize(N)
	f_flow_dir = PackedInt32Array(); f_flow_dir.resize(N)
	f_flow = PackedFloat32Array(); f_flow.resize(N)
	f_heat_capacity   = PackedFloat32Array(); f_heat_capacity.resize(N)
	f_base_temperature= PackedFloat32Array(); f_base_temperature.resize(N)

	for f in N:
		var dir := gp.face_normals[f]
		var lat := dir.y

		var base := 1.0 - absf(lat) * 1.6
		base = clampf(base, -0.4, 1.0)
		f_base_temperature[f] = base
		f_temperature[f] = base

		var land := f_is_land_face[f] == 1
		f_heat_capacity[f] = 0.8 if land else 1.0

		var lat_abs := absf(lat)
		f_humidity_atm[f] = clampf(0.55 - lat_abs * 0.40, 0.05, 0.60)
		f_snow[f] = 0.0
		f_soil_water[f] = 0.10
		f_river_input[f] = 0.0
		f_flow_dir[f] = -1
		f_flow[f] = 0.0
		f_precipitation[f] = 0.0
		f_cloud[f] = 0.0
		f_pressure[f] = 0.0

func _face_is_land(f: int) -> bool:
	var start := gp.face_vertex_offsets[f]
	var end := gp.face_vertex_offsets[f + 1]
	var land := 0
	for i in range(start, end):
		land += v_is_land[gp.face_vertex_indices[i]]
	return land * 2 > (end - start)

func refresh_face_land_flags() -> void:
	for f in gp.face_count:
		f_is_land_face[f] = 1 if _face_is_land(f) else 0

func clear_height() -> void:
	v_height.fill(0.0)
	f_elevation.fill(0.0)

func clear_climate() -> void:
	f_temperature = PackedFloat32Array()
	f_pressure = PackedFloat32Array()
	f_wind = PackedVector3Array()
	f_humidity_atm = PackedFloat32Array()
	f_cloud = PackedFloat32Array()
	f_precipitation = PackedFloat32Array()
	f_snow = PackedFloat32Array()
	f_soil_water = PackedFloat32Array()
	f_river_input = PackedFloat32Array()
	f_flow_dir = PackedInt32Array()
	f_flow = PackedFloat32Array()
	f_heat_capacity = PackedFloat32Array()
	f_base_temperature = PackedFloat32Array()

func has_climate() -> bool:
	return f_temperature.size() == gp.face_count