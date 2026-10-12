class_name ClimateEngine
extends RefCounted
## GPU 气候 + 河流 + 生态模拟引擎。
##
## 一个 tick 的 dispatch 顺序：
##   气候：solar → pressure → wind → evaporate
##        → advect_temp → diffuse_temp
##        → advect_hum → diffuse_hum
##        → advect_cloud → copy_cloud
##        → orographic → condense
##   河流（每 river_trigger_interval tick 一次）：
##        river_step × river_substeps
##   生态（每 ecology_interval tick 一次）：
##        ecology
##
## 依赖方向：
##   ClimateEngine  → ClimateBuffers, ClimatePipeline, ClimateIO
##   ClimatePipeline → ComputeProgram, ClimateBuffers, ComputeBuffers
##   ClimateIO      → ClimateBuffers
##   ClimateBuffers → ComputeBuffers

var rd: RenderingDevice
var buffers: ClimateBuffers
var pipeline: ClimatePipeline
var io: ClimateIO

var _N: int = 0
var _groups: int = 0
var _initialized: bool = false

## Profiler 契约。DebugPanel 期望 key: dispatch / readback / total
var profile: Dictionary = {
	"dispatch": 0,
	"readback": 0,
	"total": 0,
}

# ============================================================
func setup(gp: GoldbergPolyhedron, data: PlanetData) -> bool:
	_N = gp.face_count
	_groups = int(ceil(float(_N) / 64.0))

	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("[ClimateEngine] RD 创建失败")
		return false

	buffers = ClimateBuffers.create(rd, gp, data)

	pipeline = ClimatePipeline.new()
	if not pipeline.compile_all(rd):
		push_error("[ClimateEngine] shader 编译失败")
		return false
	pipeline.build_all_sets(buffers)

	io = ClimateIO.create(rd, buffers)

	pipeline.compute_flow_dir_once(_groups)
	data.f_flow_dir = io.read_flow_dir()

	_initialized = true
	return true

func tick(sun_dir: Vector3, dt: float, cfg: ClimateConfig,
		do_river: bool, do_ecology: bool) -> void:
	if not _initialized:
		return

	var t_dispatch := Time.get_ticks_usec()
	pipeline.upload_params(sun_dir, dt, cfg)
	pipeline.dispatch_climate(_groups)
	if do_river:
		pipeline.dispatch_river(_groups, cfg.river_substeps, buffers)
	if do_ecology:
		pipeline.upload_ecology_params(cfg)
		pipeline.dispatch_ecology(_groups)
	profile["dispatch"] = Time.get_ticks_usec() - t_dispatch

	var t_read := Time.get_ticks_usec()
	_readback_into_engine_cache(do_river, cfg.river_substeps, do_ecology)
	profile["readback"] = Time.get_ticks_usec() - t_read

# ============================================================
#  回读 → 引擎缓存
# ============================================================

var _cache_temperature: PackedFloat32Array
var _cache_pressure: PackedFloat32Array
var _cache_wind: PackedVector3Array
var _cache_hum_atm: PackedFloat32Array
var _cache_precip: PackedFloat32Array
var _cache_cloud: PackedFloat32Array
var _cache_snow: PackedFloat32Array
var _cache_soil: PackedFloat32Array
var _cache_river_input: PackedFloat32Array
var _cache_flow: PackedFloat32Array
var _cache_veg_potential: PackedFloat32Array
var _cache_veg_density: PackedFloat32Array
var _cache_temp_ema: PackedFloat32Array

func _readback_into_engine_cache(do_river: bool, substeps: int,
		do_ecology: bool) -> void:
	_cache_temperature = io.read_temperature()
	_cache_pressure = io.read_pressure()
	_cache_wind = io.read_wind()
	_cache_hum_atm = io.read_hum_atm()
	_cache_precip = io.read_precip()
	_cache_cloud = io.read_cloud()
	_cache_snow = io.read_snow()
	_cache_soil = io.read_soil()
	_cache_river_input = io.read_river_input()
	if do_river:
		_cache_flow = io.read_flow(substeps)
	if do_ecology:
		_cache_veg_potential = io.read_veg_potential()
		_cache_veg_density = io.read_veg_density()
		_cache_temp_ema = io.read_temp_ema()

# ---- 数据访问 ----
func get_temperature() -> PackedFloat32Array: return _cache_temperature
func get_pressure() -> PackedFloat32Array: return _cache_pressure
func get_wind() -> PackedVector3Array: return _cache_wind
func get_humidity_atm() -> PackedFloat32Array: return _cache_hum_atm
func get_precipitation() -> PackedFloat32Array: return _cache_precip
func get_cloud() -> PackedFloat32Array: return _cache_cloud
func get_snow() -> PackedFloat32Array: return _cache_snow
func get_soil() -> PackedFloat32Array: return _cache_soil
func get_river_input() -> PackedFloat32Array: return _cache_river_input
func get_flow() -> PackedFloat32Array: return _cache_flow
func get_veg_potential() -> PackedFloat32Array: return _cache_veg_potential
func get_veg_density() -> PackedFloat32Array: return _cache_veg_density
func get_flow_dir() -> PackedInt32Array: return io.read_flow_dir()
func is_initialized() -> bool: return _initialized

# ============================================================
#  写回 PlanetData。由 ClimateScheduler 调用。
# ============================================================
func writeback_to(data: PlanetData, do_river: bool, do_ecology: bool) -> void:
	if _cache_temperature.size() == data.f_temperature.size():
		data.f_temperature = _cache_temperature
	if _cache_pressure.size() == data.f_pressure.size():
		data.f_pressure = _cache_pressure
	if _cache_wind.size() == data.f_wind.size():
		data.f_wind = _cache_wind
	if _cache_hum_atm.size() == data.f_humidity_atm.size():
		data.f_humidity_atm = _cache_hum_atm
	if _cache_precip.size() == data.f_precipitation.size():
		data.f_precipitation = _cache_precip
	if _cache_cloud.size() == data.f_cloud.size():
		data.f_cloud = _cache_cloud
	if _cache_snow.size() == data.f_snow.size():
		data.f_snow = _cache_snow
	if _cache_soil.size() == data.f_soil_water.size():
		data.f_soil_water = _cache_soil
	if _cache_river_input.size() == data.f_river_input.size():
		data.f_river_input = _cache_river_input
	if do_river and _cache_flow.size() == data.f_flow.size():
		data.f_flow = _cache_flow
	if do_ecology:
		if _cache_veg_potential.size() == data.f_potential_veg.size():
			data.f_potential_veg = _cache_veg_potential
		if _cache_veg_density.size() == data.f_veg_density.size():
			data.f_veg_density = _cache_veg_density
		if _cache_temp_ema.size() == data.f_temp_ema.size():
			data.f_temp_ema = _cache_temp_ema

# ============================================================
#  玩家操作：直接修改植被密度
# ============================================================
## 砍伐：把 cell 处的植被密度减去 amount（0~1）。
## 下个气候 tick 起生效（蒸发减弱 → 湿度下降 → 潜在植被也可能变化）。
func deforest(cell_idx: int, amount: float) -> void:
	if not _initialized:
		return
	if cell_idx < 0 or cell_idx >= _N:
		return
	if not buffers.store.has(ClimateBuffers.B_VEG_DENSITY):
		return
	var buf := buffers.veg_density()
	var cur_bytes := rd.buffer_get_data(buf, cell_idx * 4, 4)
	if cur_bytes.size() < 4:
		return
	var cur := cur_bytes.to_float32_array()[0]
	var new_val := maxf(0.0, cur - amount)
	rd.buffer_update(buf, cell_idx * 4, 4,
		PackedFloat32Array([new_val]).to_byte_array())

## 种植：把 cell 处的植被密度提升到 at_least。
func plant(cell_idx: int, at_least: float) -> void:
	if not _initialized:
		return
	if cell_idx < 0 or cell_idx >= _N:
		return
	if not buffers.store.has(ClimateBuffers.B_VEG_DENSITY):
		return
	var buf := buffers.veg_density()
	var cur_bytes := rd.buffer_get_data(buf, cell_idx * 4, 4)
	if cur_bytes.size() < 4:
		return
	var cur := cur_bytes.to_float32_array()[0]
	var new_val := maxf(cur, at_least)
	rd.buffer_update(buf, cell_idx * 4, 4,
		PackedFloat32Array([new_val]).to_byte_array())

# ============================================================
#  地形变化后重算流向
# ============================================================
func update_land_score(data: PlanetData) -> void:
	if not _initialized:
		return
	buffers.update_land_arrays(data)
	pipeline.compute_flow_dir_once(_groups)
	data.f_flow_dir = io.read_flow_dir()

# ============================================================
#  释放
# ============================================================
func dispose() -> void:
	if not _initialized:
		return
	if pipeline != null:
		pipeline.free_all()
		pipeline = null
	if buffers != null:
		buffers.free_all()
		buffers = null
	io = null
	rd = null
	_initialized = false