class_name ClimateBuffers
extends RefCounted
## 气候 + 河流模拟的所有 GPU buffer 的声明与生命周期。
## 提供具名访问器，避免调用点使用裸字符串。

# ---- 拓扑 ----
const B_NEIGHBORS    := &"neighbors"
const B_EDGE_DIRS    := &"edge_dirs"
const B_NORMALS      := &"normals"
const B_ELEVATION    := &"elevation"
const B_IS_LAND      := &"is_land"
const B_LAND_SCORE   := &"land_score"

# ---- 气候状态 ----
const B_TEMP         := &"temp"
const B_TEMP_BUF     := &"temp_buf"
const B_PRESSURE     := &"pressure"
const B_WIND         := &"wind"
const B_HUM_ATM      := &"hum_atm"
const B_HUM_ATM_BUF  := &"hum_atm_buf"
const B_CLOUD        := &"cloud"
const B_CLOUD_BUF    := &"cloud_buf"
const B_PRECIP       := &"precip"
const B_SNOW         := &"snow"
const B_SOIL         := &"soil"
const B_RIVER_INPUT  := &"river_input"

# ---- 河流状态 ----
const B_FLOW_DIR     := &"flow_dir"
const B_STORAGE_A    := &"storage_a"
const B_STORAGE_B    := &"storage_b"
const B_FLOW_OUT_A   := &"flow_out_a"
const B_FLOW_OUT_B   := &"flow_out_b"

# ---- 生态 ----
const B_VEG_POTENTIAL := &"veg_potential"
const B_VEG_DENSITY   := &"veg_density"

# ---- 常量 ----
const B_HEAT_CAP     := &"heat_cap"
const B_BASE_TEMP    := &"base_temp"
const B_TEMP_EMA     := &"temp_ema"

var store: ComputeBuffers
var N: int = 0
var groups: int = 0

# ============================================================
static func create(rd: RenderingDevice, gp: GoldbergPolyhedron,
		data: PlanetData) -> ClimateBuffers:
	var cb := ClimateBuffers.new()
	cb.N = gp.face_count
	cb.groups = int(ceil(float(cb.N) / 64.0))
	cb.store = ComputeBuffers.new(rd)
	cb._allocate(gp, data)
	return cb

func _allocate(gp: GoldbergPolyhedron, data: PlanetData) -> void:
	# ---- 拓扑 ----
	store.add(B_NEIGHBORS, N * 6 * 4, gp.face_neighbors.to_byte_array())

	var ed := PackedFloat32Array(); ed.resize(N * 6 * 4)
	var src := gp.face_edge_dirs
	for i in N * 6:
		var v := src[i]
		var j := i * 4
		ed[j] = v.x; ed[j + 1] = v.y; ed[j + 2] = v.z
		ed[j + 3] = gp.face_edge_arc[i]
	store.add(B_EDGE_DIRS, N * 6 * 16, ed.to_byte_array())

	var nm := PackedFloat32Array(); nm.resize(N * 4)
	for i in N:
		var v := gp.face_normals[i]
		var j := i * 4
		nm[j] = v.x; nm[j + 1] = v.y; nm[j + 2] = v.z; nm[j + 3] = 0.0
	store.add(B_NORMALS, N * 16, nm.to_byte_array())

	store.add_f32(B_ELEVATION, N, data.f_elevation)

	var il := PackedInt32Array(); il.resize(N)
	for i in N:
		il[i] = data.f_is_land_face[i]
	store.add(B_IS_LAND, N * 4, il.to_byte_array())

	store.add_f32(B_LAND_SCORE, N, data.f_land_score)

	# ---- 气候状态 ----
	store.add_f32(B_TEMP, N, data.f_temperature)
	store.add(B_TEMP_BUF, N * 4)
	store.add(B_PRESSURE, N * 4)

	var zw := PackedFloat32Array(); zw.resize(N * 4)
	store.add(B_WIND, N * 16, zw.to_byte_array())

	store.add_f32(B_HUM_ATM, N, data.f_humidity_atm)
	store.add(B_HUM_ATM_BUF, N * 4)
	store.add_f32(B_CLOUD, N, data.f_cloud)
	store.add(B_CLOUD_BUF, N * 4)
	store.add(B_PRECIP, N * 4)
	store.add_f32(B_SNOW, N, data.f_snow)
	store.add_f32(B_SOIL, N, data.f_soil_water)
	store.add_f32(B_RIVER_INPUT, N, data.f_river_input)

	# ---- 河流状态 ----
	var zero := PackedFloat32Array(); zero.resize(N)
	store.add(B_STORAGE_A,  N * 4, zero.to_byte_array())
	store.add(B_STORAGE_B,  N * 4, zero.to_byte_array())
	store.add(B_FLOW_OUT_A, N * 4, zero.to_byte_array())
	store.add(B_FLOW_OUT_B, N * 4, zero.to_byte_array())
	store.add(B_FLOW_DIR,   N * 4)

	# ---- 生态 ----
	store.add_f32(B_VEG_POTENTIAL, N, PackedFloat32Array())
	store.add_f32(B_VEG_DENSITY,   N, PackedFloat32Array())

	# ---- 常量 ----
	store.add_f32(B_HEAT_CAP, N, data.f_heat_capacity)
	store.add_f32(B_BASE_TEMP, N, data.f_base_temperature)
	store.add_f32(B_TEMP_EMA, N, data.f_temperature)

# ---- 具名访问器 ----
func neighbors() -> RID:    return store.get_buf(B_NEIGHBORS)
func edge_dirs() -> RID:    return store.get_buf(B_EDGE_DIRS)
func normals() -> RID:      return store.get_buf(B_NORMALS)
func elevation() -> RID:    return store.get_buf(B_ELEVATION)
func is_land() -> RID:      return store.get_buf(B_IS_LAND)
func land_score() -> RID:   return store.get_buf(B_LAND_SCORE)

func temp() -> RID:         return store.get_buf(B_TEMP)
func temp_buf() -> RID:     return store.get_buf(B_TEMP_BUF)
func pressure() -> RID:     return store.get_buf(B_PRESSURE)
func wind() -> RID:         return store.get_buf(B_WIND)
func hum_atm() -> RID:      return store.get_buf(B_HUM_ATM)
func hum_atm_buf() -> RID:  return store.get_buf(B_HUM_ATM_BUF)
func cloud() -> RID:        return store.get_buf(B_CLOUD)
func cloud_buf() -> RID:    return store.get_buf(B_CLOUD_BUF)
func precip() -> RID:       return store.get_buf(B_PRECIP)
func snow() -> RID:         return store.get_buf(B_SNOW)
func soil() -> RID:         return store.get_buf(B_SOIL)
func river_input() -> RID:  return store.get_buf(B_RIVER_INPUT)

func flow_dir() -> RID:     return store.get_buf(B_FLOW_DIR)
func storage_a() -> RID:    return store.get_buf(B_STORAGE_A)
func storage_b() -> RID:    return store.get_buf(B_STORAGE_B)
func flow_out_a() -> RID:   return store.get_buf(B_FLOW_OUT_A)
func flow_out_b() -> RID:   return store.get_buf(B_FLOW_OUT_B)

func veg_potential() -> RID: return store.get_buf(B_VEG_POTENTIAL)
func veg_density() -> RID:   return store.get_buf(B_VEG_DENSITY)

func heat_cap() -> RID:     return store.get_buf(B_HEAT_CAP)
func base_temp() -> RID:    return store.get_buf(B_BASE_TEMP)
func temp_ema() -> RID:     return store.get_buf(B_TEMP_EMA)

# ---- 更新 ----
func update_land_arrays(data: PlanetData) -> void:
	store.update_f32(B_LAND_SCORE, data.f_land_score)
	store.update_f32(B_ELEVATION, data.f_elevation)
	var il := PackedInt32Array(); il.resize(N)
	for i in N:
		il[i] = data.f_is_land_face[i]
	store.update_i32(B_IS_LAND, il)

# ---- 释放 ----
func free_all() -> void:
	if store != null:
		store.free_all()
		store = null