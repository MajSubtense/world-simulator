class_name GpuClimate
extends RefCounted
## GPU 气候 + 河流模拟器。
##
## 一个 tick 的 dispatch 顺序：
##   气候：solar → pressure → wind → evaporate
##        → advect_temp → diffuse_temp
##        → advect_hum → diffuse_hum
##        → advect_cloud → copy_cloud
##        → orographic → condense
##   河流（每 river_interval tick 一次）：
##        river_step × river_interval
##
## 所有 shader 从 ShadersClimate / ShadersWater / ShadersRiver 引用。
## 所有物理参数从 ClimateConfig 读。

# ---- 常量 ----
const RIVER_FLOW_RATE := 0.30

# ---- 依赖 ----
var rd: RenderingDevice
var gp: GoldbergPolyhedron
var data: PlanetData

# ---- 拓扑 buffer ----
var _b_neighbors: RID
var _b_edge_dirs: RID
var _b_normals: RID
var _b_elevation: RID
var _b_is_land: RID
var _b_land_score: RID

# ---- 气候状态 buffer ----
var _b_temp: RID
var _b_temp_buf: RID
var _b_pressure: RID
var _b_wind: RID
var _b_hum_atm: RID
var _b_hum_atm_buf: RID
var _b_cloud: RID
var _b_cloud_buf: RID
var _b_precip: RID
var _b_snow: RID
var _b_soil: RID
var _b_river_input: RID

# ---- 河流状态 buffer ----
var _b_flow_dir: RID
var _b_storage_a: RID
var _b_storage_b: RID
var _b_flow_out_a: RID
var _b_flow_out_b: RID

# ---- 常量 buffer ----
var _b_heat_cap: RID
var _b_base_temp: RID

# ---- 参数 buffer ----
var _b_p_solar: RID
var _b_p_pressure: RID
var _b_p_wind: RID
var _b_p_advect: RID
var _b_p_advect_hum: RID
var _b_p_advect_cloud: RID
var _b_p_diffuse_temp: RID
var _b_p_diffuse_hum_atm: RID
var _b_p_evaporate: RID
var _b_p_orographic: RID
var _b_p_condense: RID
var _b_p_river: RID

# ---- Shader / Pipeline ----
var _sh_solar: RID; var _pl_solar: RID
var _sh_pressure: RID; var _pl_pressure: RID
var _sh_wind: RID; var _pl_wind: RID
var _sh_advect: RID; var _pl_advect: RID
var _sh_diffuse: RID; var _pl_diffuse: RID
var _sh_copy: RID; var _pl_copy: RID
var _sh_evaporate: RID; var _pl_evaporate: RID
var _sh_orographic: RID; var _pl_orographic: RID
var _sh_condense: RID; var _pl_condense: RID
var _sh_river_flow: RID; var _pl_river_flow: RID
var _sh_river_step: RID; var _pl_river_step: RID

# ---- Uniform sets ----
var _us_solar: RID
var _us_pressure: RID
var _us_wind: RID
var _us_advect_temp: RID
var _us_diffuse_temp: RID
var _us_advect_hum: RID
var _us_diffuse_hum: RID
var _us_advect_cloud: RID
var _us_copy_cloud: RID
var _us_evaporate: RID
var _us_orographic: RID
var _us_condense: RID
var _us_river_flow: RID
var _us_river_a2b: RID
var _us_river_b2a: RID

var _N: int = 0
var _groups: int = 0
var _initialized: bool = false

# 河流触发频率（tick 数）
var river_interval: int = 120

# 回读缓存
var _rb_temperature: PackedFloat32Array
var _rb_pressure: PackedFloat32Array
var _rb_wind: PackedVector3Array
var _rb_hum_atm: PackedFloat32Array
var _rb_precip: PackedFloat32Array
var _rb_cloud: PackedFloat32Array
var _rb_snow: PackedFloat32Array
var _rb_soil: PackedFloat32Array
var _rb_river_input: PackedFloat32Array
var _rb_flow: PackedFloat32Array
var _rb_flow_dir: PackedInt32Array

# ============================================================
#  初始化
# ============================================================

func setup(poly: GoldbergPolyhedron, d: PlanetData) -> bool:
	gp = poly
	data = d
	_N = gp.face_count
	_groups = int(ceil(float(_N) / 64.0))

	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("GpuClimate: RD 创建失败")
		return false

	_upload_topology()
	_upload_state()
	if not _compile_all():
		return false
	_create_uniform_sets()
	_compute_flow_dir_once()
	_initialized = true
	return true

func tick(sun_dir: Vector3, dt: float, cfg: ClimateConfig, do_river: bool) -> void:
	if not _initialized:
		return
	_update_params(sun_dir, dt, cfg)
	_dispatch_climate()
	if do_river:
		_dispatch_river()
	_readback(do_river)

# ============================================================
#  Getter
# ============================================================

func get_temperature() -> PackedFloat32Array: return _rb_temperature
func get_pressure() -> PackedFloat32Array: return _rb_pressure
func get_wind() -> PackedVector3Array: return _rb_wind
func get_humidity_atm() -> PackedFloat32Array: return _rb_hum_atm
func get_precipitation() -> PackedFloat32Array: return _rb_precip
func get_cloud() -> PackedFloat32Array: return _rb_cloud
func get_snow() -> PackedFloat32Array: return _rb_snow
func get_soil() -> PackedFloat32Array: return _rb_soil
func get_river_input() -> PackedFloat32Array: return _rb_river_input
func get_flow() -> PackedFloat32Array: return _rb_flow
func get_flow_dir() -> PackedInt32Array: return _rb_flow_dir
func is_initialized() -> bool: return _initialized

# ============================================================
#  上传
# ============================================================

func _upload_topology() -> void:
	_b_neighbors = rd.storage_buffer_create(_N * 6 * 4,
		gp.face_neighbors.to_byte_array())

	var ed := PackedFloat32Array(); ed.resize(_N * 6 * 4)
	var src := gp.face_edge_dirs
	for i in _N * 6:
		var v := src[i]
		var j := i * 4
		ed[j] = v.x; ed[j+1] = v.y; ed[j+2] = v.z
		ed[j+3] = gp.face_edge_arc[i]
	_b_edge_dirs = rd.storage_buffer_create(_N * 6 * 16, ed.to_byte_array())

	var nm := PackedFloat32Array(); nm.resize(_N * 4)
	for i in _N:
		var v := gp.face_normals[i]
		var j := i * 4
		nm[j] = v.x; nm[j+1] = v.y; nm[j+2] = v.z; nm[j+3] = 0.0
	_b_normals = rd.storage_buffer_create(_N * 16, nm.to_byte_array())

	_b_elevation = rd.storage_buffer_create(_N * 4, data.f_elevation.to_byte_array())

	var il := PackedInt32Array(); il.resize(_N)
	for i in _N:
		il[i] = data.f_is_land_face[i]
	_b_is_land = rd.storage_buffer_create(_N * 4, il.to_byte_array())

	_b_land_score = rd.storage_buffer_create(_N * 4, data.f_land_score.to_byte_array())

func _upload_state() -> void:
	_b_temp = rd.storage_buffer_create(_N * 4, data.f_temperature.to_byte_array())
	_b_temp_buf = rd.storage_buffer_create(_N * 4)
	_b_pressure = rd.storage_buffer_create(_N * 4)

	var zw := PackedFloat32Array(); zw.resize(_N * 4)
	_b_wind = rd.storage_buffer_create(_N * 16, zw.to_byte_array())

	_b_hum_atm = rd.storage_buffer_create(_N * 4, data.f_humidity_atm.to_byte_array())
	_b_hum_atm_buf = rd.storage_buffer_create(_N * 4)
	_b_cloud = rd.storage_buffer_create(_N * 4, data.f_cloud.to_byte_array())
	_b_cloud_buf = rd.storage_buffer_create(_N * 4)
	_b_precip = rd.storage_buffer_create(_N * 4)
	_b_snow = rd.storage_buffer_create(_N * 4, data.f_snow.to_byte_array())
	_b_soil = rd.storage_buffer_create(_N * 4, data.f_soil_water.to_byte_array())
	_b_river_input = rd.storage_buffer_create(_N * 4, data.f_river_input.to_byte_array())

	var zero := PackedFloat32Array(); zero.resize(_N)
	_b_storage_a = rd.storage_buffer_create(_N * 4, zero.to_byte_array())
	_b_storage_b = rd.storage_buffer_create(_N * 4, zero.to_byte_array())
	_b_flow_out_a = rd.storage_buffer_create(_N * 4, zero.to_byte_array())
	_b_flow_out_b = rd.storage_buffer_create(_N * 4, zero.to_byte_array())
	_b_flow_dir = rd.storage_buffer_create(_N * 4)

	_b_heat_cap = rd.storage_buffer_create(_N * 4, data.f_heat_capacity.to_byte_array())
	_b_base_temp = rd.storage_buffer_create(_N * 4, data.f_base_temperature.to_byte_array())

	_rb_temperature = data.f_temperature.duplicate()
	_rb_pressure = PackedFloat32Array(); _rb_pressure.resize(_N)
	_rb_wind = PackedVector3Array(); _rb_wind.resize(_N)
	_rb_hum_atm = data.f_humidity_atm.duplicate()
	_rb_precip = PackedFloat32Array(); _rb_precip.resize(_N)
	_rb_cloud = data.f_cloud.duplicate()
	_rb_snow = data.f_snow.duplicate()
	_rb_soil = data.f_soil_water.duplicate()
	_rb_river_input = data.f_river_input.duplicate()
	_rb_flow = PackedFloat32Array(); _rb_flow.resize(_N)
	_rb_flow_dir = PackedInt32Array(); _rb_flow_dir.resize(_N)

# ============================================================
#  编译
# ============================================================

func _compile_all() -> bool:
	_sh_solar      = _compile(ShadersClimate.SOLAR)
	_sh_pressure   = _compile(ShadersClimate.PRESSURE)
	_sh_wind       = _compile(ShadersClimate.WIND)
	_sh_advect     = _compile(ShadersClimate.ADVECT)
	_sh_diffuse    = _compile(ShadersClimate.DIFFUSE)
	_sh_copy       = _compile(ShadersClimate.COPY)
	_sh_evaporate  = _compile(ShadersWater.EVAPORATE)
	_sh_orographic = _compile(ShadersWater.OROGRAPHIC)
	_sh_condense   = _compile(ShadersWater.CONDENSE)
	_sh_river_flow = _compile(ShadersRiver.RIVER_FLOW)
	_sh_river_step = _compile(ShadersRiver.RIVER_STEP)

	var all := [_sh_solar, _sh_pressure, _sh_wind, _sh_advect, _sh_diffuse,
				_sh_copy, _sh_evaporate, _sh_orographic, _sh_condense,
				_sh_river_flow, _sh_river_step]
	for s in all:
		if s == RID():
			return false

	_pl_solar      = rd.compute_pipeline_create(_sh_solar)
	_pl_pressure   = rd.compute_pipeline_create(_sh_pressure)
	_pl_wind       = rd.compute_pipeline_create(_sh_wind)
	_pl_advect     = rd.compute_pipeline_create(_sh_advect)
	_pl_diffuse    = rd.compute_pipeline_create(_sh_diffuse)
	_pl_copy       = rd.compute_pipeline_create(_sh_copy)
	_pl_evaporate  = rd.compute_pipeline_create(_sh_evaporate)
	_pl_orographic = rd.compute_pipeline_create(_sh_orographic)
	_pl_condense   = rd.compute_pipeline_create(_sh_condense)
	_pl_river_flow = rd.compute_pipeline_create(_sh_river_flow)
	_pl_river_step = rd.compute_pipeline_create(_sh_river_step)

	_b_p_solar        = rd.storage_buffer_create(48)
	_b_p_pressure     = rd.storage_buffer_create(32)
	_b_p_wind         = rd.storage_buffer_create(16)
	_b_p_advect       = rd.storage_buffer_create(16)
	_b_p_advect_hum   = rd.storage_buffer_create(16)
	_b_p_advect_cloud = rd.storage_buffer_create(16)
	_b_p_diffuse_temp = rd.storage_buffer_create(16)
	_b_p_diffuse_hum_atm = rd.storage_buffer_create(16)
	_b_p_evaporate    = rd.storage_buffer_create(48)
	_b_p_orographic   = rd.storage_buffer_create(16)
	_b_p_condense     = rd.storage_buffer_create(64)
	_b_p_river        = rd.storage_buffer_create(16)
	return true

func _compile(source: String) -> RID:
	var s := RDShaderSource.new()
	s.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	s.source_compute = source
	var sp := rd.shader_compile_spirv_from_source(s)
	if sp == null or sp.compile_error_compute != "":
		push_error("GpuClimate shader: " + (sp.compile_error_compute if sp else "空"))
		return RID()
	return rd.shader_create_from_spirv(sp)

# ============================================================
#  Uniform Sets
# ============================================================

func _create_uniform_sets() -> void:
	_us_solar = _make_us(_sh_solar,
		[_b_normals, _b_heat_cap, _b_base_temp, _b_elevation, _b_temp, _b_p_solar])
	_us_pressure = _make_us(_sh_pressure,
		[_b_temp, _b_elevation, _b_normals, _b_pressure, _b_p_pressure])
	_us_wind = _make_us(_sh_wind,
		[_b_neighbors, _b_edge_dirs, _b_pressure, _b_wind, _b_p_wind])

	_us_advect_temp = _make_us(_sh_advect,
		[_b_neighbors, _b_edge_dirs, _b_wind, _b_temp, _b_temp_buf, _b_p_advect])
	_us_diffuse_temp = _make_us(_sh_diffuse,
		[_b_neighbors, _b_temp_buf, _b_temp, _b_p_diffuse_temp])

	_us_advect_hum = _make_us(_sh_advect,
		[_b_neighbors, _b_edge_dirs, _b_wind,
		 _b_hum_atm, _b_hum_atm_buf, _b_p_advect_hum])
	_us_diffuse_hum = _make_us(_sh_diffuse,
		[_b_neighbors, _b_hum_atm_buf, _b_hum_atm, _b_p_diffuse_hum_atm])

	_us_advect_cloud = _make_us(_sh_advect,
		[_b_neighbors, _b_edge_dirs, _b_wind,
		 _b_cloud, _b_cloud_buf, _b_p_advect_cloud])
	_us_copy_cloud = _make_us(_sh_copy, [_b_cloud_buf, _b_cloud])

	_us_evaporate = _make_us(_sh_evaporate,
		[_b_is_land, _b_normals, _b_soil, _b_hum_atm, _b_temp, _b_p_evaporate])

	_us_orographic = _make_us(_sh_orographic,
		[_b_neighbors, _b_edge_dirs, _b_elevation, _b_wind, _b_is_land,
		 _b_hum_atm, _b_soil, _b_temp, _b_precip, _b_p_orographic])

	_us_condense = _make_us(_sh_condense, [
		_b_normals, _b_is_land, _b_elevation,
		_b_hum_atm, _b_soil, _b_temp, _b_precip, _b_cloud,
		_b_snow, _b_river_input, _b_p_condense])

	_us_river_flow = _make_us(_sh_river_flow,
		[_b_neighbors, _b_elevation, _b_is_land, _b_flow_dir, _b_land_score])

	_us_river_a2b = _make_us(_sh_river_step, [
		_b_neighbors, _b_flow_dir, _b_is_land, _b_river_input,
		_b_storage_a, _b_flow_out_a, _b_storage_b, _b_flow_out_b, _b_p_river])
	_us_river_b2a = _make_us(_sh_river_step, [
		_b_neighbors, _b_flow_dir, _b_is_land, _b_river_input,
		_b_storage_b, _b_flow_out_b, _b_storage_a, _b_flow_out_a, _b_p_river])

func _make_us(shader: RID, buffers: Array) -> RID:
	var u: Array = []
	for i in buffers.size():
		var r := RDUniform.new()
		r.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		r.binding = i
		r.add_id(buffers[i])
		u.append(r)
	return rd.uniform_set_create(u, shader, 0)

# ============================================================
#  参数
# ============================================================

func _update_params(sun_dir: Vector3, dt: float, cfg: ClimateConfig) -> void:
	_buf_update(_b_p_solar, PackedFloat32Array([
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		dt,
		cfg.solar_absorption,
		cfg.thermal_emission,
		cfg.base_relaxation,
		cfg.lapse_rate,
		0.0, 0.0, 0.0,
	]))

	_buf_update(_b_p_pressure, PackedFloat32Array([
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		cfg.circulation_amp,
		0.0, 0.0, 0.0,
	]))

	_buf_update(_b_p_wind, PackedFloat32Array([cfg.wind_scale]))

	_buf_update(_b_p_advect, PackedFloat32Array([dt * cfg.advection_speed]))
	_buf_update(_b_p_advect_hum, PackedFloat32Array([dt * cfg.humidity_advection]))
	_buf_update(_b_p_advect_cloud, PackedFloat32Array([dt * cfg.cloud_advection]))

	_buf_update(_b_p_diffuse_temp, PackedFloat32Array([cfg.diffusion_coeff]))
	_buf_update(_b_p_diffuse_hum_atm, PackedFloat32Array([cfg.humidity_diffusion_atm]))

	_buf_update(_b_p_evaporate, PackedFloat32Array([
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		cfg.evap_rate_ocean,
		cfg.evap_rate_land,
		cfg.latent_heat,
		cfg.sat_base,
		cfg.sat_temp_factor,
		0.0, 0.0, 0.0,
	]))

	_buf_update(_b_p_orographic, PackedFloat32Array([
		cfg.orographic_factor,
		cfg.latent_heat_release,
		cfg.sat_base,
		cfg.sat_temp_factor,
	]))

	_buf_update(_b_p_condense, PackedFloat32Array([
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		cfg.sat_base,
		cfg.sat_temp_factor,
		cfg.cloud_form_rate,
		cfg.cloud_decay,
		cfg.cloud_threshold,
		cfg.release_rate,
		cfg.latent_heat_release,
		dt,
		cfg.melt_rate,
		cfg.runoff_ratio,
		cfg.baseflow_rate,
		0.0,
	]))

	_buf_update(_b_p_river, PackedFloat32Array([
		RIVER_FLOW_RATE,
		1.0,
		0.0, 0.0,
	]))

func _buf_update(buf: RID, data_array: PackedFloat32Array) -> void:
	rd.buffer_update(buf, 0, data_array.size() * 4, data_array.to_byte_array())

# ============================================================
#  Dispatch
# ============================================================

func _dispatch_climate() -> void:
	var cl := rd.compute_list_begin()
	_dispatch(cl, _pl_solar, _us_solar)
	_dispatch(cl, _pl_pressure, _us_pressure)
	_dispatch(cl, _pl_wind, _us_wind)
	_dispatch(cl, _pl_evaporate, _us_evaporate)
	_dispatch(cl, _pl_advect, _us_advect_temp)
	_dispatch(cl, _pl_diffuse, _us_diffuse_temp)
	_dispatch(cl, _pl_advect, _us_advect_hum)
	_dispatch(cl, _pl_diffuse, _us_diffuse_hum)
	_dispatch(cl, _pl_advect, _us_advect_cloud)
	_dispatch(cl, _pl_copy, _us_copy_cloud)
	_dispatch(cl, _pl_orographic, _us_orographic)
	_dispatch(cl, _pl_condense, _us_condense, false)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func _dispatch(cl: int, pl: RID, us: RID, add_barrier: bool = true) -> void:
	rd.compute_list_bind_compute_pipeline(cl, pl)
	rd.compute_list_bind_uniform_set(cl, us, 0)
	rd.compute_list_dispatch(cl, _groups, 1, 1)
	if add_barrier:
		rd.compute_list_add_barrier(cl)

func _dispatch_river() -> void:
	var zero := PackedFloat32Array(); zero.resize(_N)
	rd.buffer_update(_b_flow_out_a, 0, _N * 4, zero.to_byte_array())

	var cl := rd.compute_list_begin()
	for i in river_interval:
		var us: RID = _us_river_a2b if (i % 2 == 0) else _us_river_b2a
		rd.compute_list_bind_compute_pipeline(cl, _pl_river_step)
		rd.compute_list_bind_uniform_set(cl, us, 0)
		rd.compute_list_dispatch(cl, _groups, 1, 1)
		rd.compute_list_add_barrier(cl)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func _compute_flow_dir_once() -> void:
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pl_river_flow)
	rd.compute_list_bind_uniform_set(cl, _us_river_flow, 0)
	rd.compute_list_dispatch(cl, _groups, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	_rb_flow_dir = rd.buffer_get_data(_b_flow_dir).to_int32_array()

# ============================================================
#  地形变化后重算流向
# ============================================================

func update_land_score() -> void:
	if _b_land_score == RID() or not _initialized:
		return
	rd.buffer_update(_b_land_score, 0, _N * 4,
		data.f_land_score.to_byte_array())
	rd.buffer_update(_b_elevation, 0, _N * 4,
		data.f_elevation.to_byte_array())
	var il := PackedInt32Array(); il.resize(_N)
	for i in _N:
		il[i] = data.f_is_land_face[i]
	rd.buffer_update(_b_is_land, 0, _N * 4, il.to_byte_array())
	_compute_flow_dir_once()

# ============================================================
#  回读
# ============================================================

func _readback(do_river: bool) -> void:
	_rb_temperature = rd.buffer_get_data(_b_temp).to_float32_array()
	_rb_pressure = rd.buffer_get_data(_b_pressure).to_float32_array()
	_rb_hum_atm = rd.buffer_get_data(_b_hum_atm).to_float32_array()
	_rb_precip = rd.buffer_get_data(_b_precip).to_float32_array()
	_rb_cloud = rd.buffer_get_data(_b_cloud).to_float32_array()
	_rb_snow = rd.buffer_get_data(_b_snow).to_float32_array()
	_rb_soil = rd.buffer_get_data(_b_soil).to_float32_array()
	_rb_river_input = rd.buffer_get_data(_b_river_input).to_float32_array()

	var wf := rd.buffer_get_data(_b_wind).to_float32_array()
	_rb_wind.resize(_N)
	for i in _N:
		_rb_wind[i] = Vector3(wf[i*4], wf[i*4+1], wf[i*4+2])

	if do_river:
		var final_out: RID = _b_flow_out_a if (river_interval % 2 == 0) else _b_flow_out_b
		_rb_flow = rd.buffer_get_data(final_out).to_float32_array()