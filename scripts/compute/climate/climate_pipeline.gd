class_name ClimatePipeline
extends RefCounted
## 气候 + 河流 + 生态的 dispatch 顺序。
## 持有 12 个 ComputeProgram 和 13 个参数 buffer，不持有状态 buffer
## （状态 buffer 由 ClimateBuffers 提供）。
##
## Uniform set 由本类自行构造：状态 buffer 从 ClimateBuffers 取具名 RID，
## 参数 buffer 是本类自己的 RID，两者混合绑定。

var rd: RenderingDevice

# ---- Programs ----
var _solar: ComputeProgram
var _pressure: ComputeProgram
var _wind: ComputeProgram
var _advect: ComputeProgram
var _diffuse: ComputeProgram
var _copy: ComputeProgram
var _evaporate: ComputeProgram
var _orographic: ComputeProgram
var _condense: ComputeProgram
var _river_flow: ComputeProgram
var _river_step: ComputeProgram
var _ecology: ComputeProgram

# ---- 参数 buffer ----
var _p_solar: RID
var _p_pressure: RID
var _p_wind: RID
var _p_advect: RID
var _p_advect_hum: RID
var _p_advect_cloud: RID
var _p_diffuse_temp: RID
var _p_diffuse_hum_atm: RID
var _p_evaporate: RID
var _p_orographic: RID
var _p_condense: RID
var _p_river: RID
var _p_ecology: RID

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
var _us_ecology: RID

# ============================================================
#  编译
# ============================================================

func compile_all(rendering_device: RenderingDevice) -> bool:
	rd = rendering_device
	_solar      = ComputeProgram.compile(rd, ClimateShaders.SOLAR,  "solar")
	_pressure   = ComputeProgram.compile(rd, ClimateShaders.PRESSURE, "pressure")
	_wind       = ComputeProgram.compile(rd, ClimateShaders.WIND, "wind")
	_advect     = ComputeProgram.compile(rd, ClimateShaders.ADVECT, "advect")
	_diffuse    = ComputeProgram.compile(rd, ClimateShaders.DIFFUSE, "diffuse")
	_copy       = ComputeProgram.compile(rd, ClimateShaders.COPY, "copy")
	_evaporate  = ComputeProgram.compile(rd, WaterShaders.EVAPORATE, "evaporate")
	_orographic = ComputeProgram.compile(rd, WaterShaders.OROGRAPHIC, "orographic")
	_condense   = ComputeProgram.compile(rd, WaterShaders.CONDENSE, "condense")
	_river_flow = ComputeProgram.compile(rd, RiverShaders.RIVER_FLOW, "river_flow")
	_river_step = ComputeProgram.compile(rd, RiverShaders.RIVER_STEP, "river_step")
	_ecology    = ComputeProgram.compile(rd, EcologyShaders.ECOLOGY, "ecology")

	var all := [_solar, _pressure, _wind, _advect, _diffuse, _copy,
				_evaporate, _orographic, _condense, _river_flow, _river_step,
				_ecology]
	for p in all:
		if p == null:
			return false

	_p_solar        = rd.storage_buffer_create(48)
	_p_pressure     = rd.storage_buffer_create(32)
	_p_wind         = rd.storage_buffer_create(16)
	_p_advect       = rd.storage_buffer_create(16)
	_p_advect_hum   = rd.storage_buffer_create(16)
	_p_advect_cloud = rd.storage_buffer_create(16)
	_p_diffuse_temp = rd.storage_buffer_create(16)
	_p_diffuse_hum_atm = rd.storage_buffer_create(16)
	_p_evaporate    = rd.storage_buffer_create(48)
	_p_orographic   = rd.storage_buffer_create(16)
	_p_condense     = rd.storage_buffer_create(64)
	_p_river        = rd.storage_buffer_create(16)
	_p_ecology      = rd.storage_buffer_create(16)
	return true

# ============================================================
#  Uniform set
# ============================================================

func build_all_sets(b: ClimateBuffers) -> void:
	_us_solar = _make_set(_solar, [
		b.normals(), b.heat_cap(), b.base_temp(),
		b.elevation(), b.temp(), _p_solar])
	_us_pressure = _make_set(_pressure, [
		b.temp(), b.elevation(), b.normals(), b.pressure(), _p_pressure])

	_us_wind = _make_set(_wind, [
		b.neighbors(), b.edge_dirs(), b.pressure(), b.wind(), _p_wind])

	_us_advect_temp = _make_set(_advect, [
		b.neighbors(), b.edge_dirs(), b.wind(),
		b.temp(), b.temp_buf(), _p_advect])
	_us_diffuse_temp = _make_set(_diffuse, [
		b.neighbors(), b.temp_buf(), b.temp(), _p_diffuse_temp])

	_us_advect_hum = _make_set(_advect, [
		b.neighbors(), b.edge_dirs(), b.wind(),
		b.hum_atm(), b.hum_atm_buf(), _p_advect_hum])
	_us_diffuse_hum = _make_set(_diffuse, [
		b.neighbors(), b.hum_atm_buf(), b.hum_atm(), _p_diffuse_hum_atm])

	_us_advect_cloud = _make_set(_advect, [
		b.neighbors(), b.edge_dirs(), b.wind(),
		b.cloud(), b.cloud_buf(), _p_advect_cloud])
	_us_copy_cloud = _make_set(_copy, [b.cloud_buf(), b.cloud()])

	# 注意：EVAPORATE 现在有 7 个 binding
	# 0 is_land, 1 normals, 2 soil, 3 hum_atm, 4 temp, 5 veg_density, 6 params
	_us_evaporate = _make_set(_evaporate, [
		b.is_land(), b.normals(), b.soil(), b.hum_atm(), b.temp(),
		b.veg_density(), _p_evaporate])

	_us_orographic = _make_set(_orographic, [
		b.neighbors(), b.edge_dirs(), b.elevation(), b.wind(), b.is_land(),
		b.hum_atm(), b.soil(), b.temp(), b.precip(), _p_orographic])

	_us_condense = _make_set(_condense, [
		b.normals(), b.is_land(), b.elevation(),
		b.hum_atm(), b.soil(), b.temp(), b.precip(), b.cloud(),
		b.snow(), b.river_input(), _p_condense])

	_us_river_flow = _make_set(_river_flow, [
		b.neighbors(), b.elevation(), b.is_land(), b.flow_dir(), b.land_score()])

	_us_river_a2b = _make_set(_river_step, [
		b.neighbors(), b.flow_dir(), b.is_land(), b.river_input(),
		b.storage_a(), b.flow_out_a(), b.storage_b(), b.flow_out_b(), _p_river])
	_us_river_b2a = _make_set(_river_step, [
		b.neighbors(), b.flow_dir(), b.is_land(), b.river_input(),
		b.storage_b(), b.flow_out_b(), b.storage_a(), b.flow_out_a(), _p_river])

	_us_ecology = _make_set(_ecology, [
		b.temp(), b.hum_atm(), b.elevation(), b.is_land(),
		b.veg_potential(), b.veg_density(), b.temp_ema(), _p_ecology])

# ============================================================
#  参数上传
# ============================================================

func upload_params(sun_dir: Vector3, dt: float, cfg: ClimateConfig) -> void:
	rd.buffer_update(_p_solar, 0, 48, PackedFloat32Array([
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		dt, cfg.solar_absorption, cfg.thermal_emission, cfg.base_relaxation,
		cfg.lapse_rate, 0.0, 0.0, 0.0,
	]).to_byte_array())

	rd.buffer_update(_p_pressure, 0, 32, PackedFloat32Array([
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		cfg.circulation_amp, 0.0, 0.0, 0.0,
	]).to_byte_array())

	rd.buffer_update(_p_wind, 0, 16,
		PackedFloat32Array([cfg.wind_scale, 0.0, 0.0, 0.0]).to_byte_array())

	rd.buffer_update(_p_advect, 0, 16,
		PackedFloat32Array([dt * cfg.advection_speed, 0.0, 0.0, 0.0]).to_byte_array())
	rd.buffer_update(_p_advect_hum, 0, 16,
		PackedFloat32Array([dt * cfg.humidity_advection, 0.0, 0.0, 0.0]).to_byte_array())
	rd.buffer_update(_p_advect_cloud, 0, 16,
		PackedFloat32Array([dt * cfg.cloud_advection, 0.0, 0.0, 0.0]).to_byte_array())

	rd.buffer_update(_p_diffuse_temp, 0, 16,
		PackedFloat32Array([cfg.diffusion_coeff, 0.0, 0.0, 0.0]).to_byte_array())
	rd.buffer_update(_p_diffuse_hum_atm, 0, 16,
		PackedFloat32Array([cfg.humidity_diffusion_atm, 0.0, 0.0, 0.0]).to_byte_array())

	rd.buffer_update(_p_evaporate, 0, 48, PackedFloat32Array([
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		cfg.evap_rate_ocean, cfg.evap_rate_land, cfg.latent_heat,
		cfg.sat_base, cfg.sat_temp_factor, 0.0, 0.0, 0.0,
	]).to_byte_array())

	rd.buffer_update(_p_orographic, 0, 16, PackedFloat32Array([
		cfg.orographic_factor, cfg.latent_heat_release,
		cfg.sat_base, cfg.sat_temp_factor,
	]).to_byte_array())

	rd.buffer_update(_p_condense, 0, 64, PackedFloat32Array([
		sun_dir.x, sun_dir.y, sun_dir.z, 0.0,
		cfg.sat_base, cfg.sat_temp_factor,
		cfg.cloud_form_rate, cfg.cloud_decay, cfg.cloud_threshold,
		cfg.release_rate, cfg.latent_heat_release, dt,
		cfg.melt_rate, cfg.runoff_ratio, cfg.baseflow_rate, 0.0,
	]).to_byte_array())

	var substeps := maxi(1, cfg.river_substeps)
	rd.buffer_update(_p_river, 0, 16, PackedFloat32Array([
		cfg.river_flow_rate, 1.0 / float(substeps), 0.0, 0.0,
	]).to_byte_array())

func upload_ecology_params(cfg: ClimateConfig,
		rate_override: float = -1.0) -> void:
	var rate := rate_override if rate_override >= 0.0 else cfg.ecology_recovery_rate
	rd.buffer_update(_p_ecology, 0, 16, PackedFloat32Array([
		rate,
		cfg.ecology_density_scale,
		cfg.ecology_temp_ema,
		0.0,
	]).to_byte_array())

# ============================================================
#  Dispatch
# ============================================================

func dispatch_climate(groups: int) -> void:
	var cl := rd.compute_list_begin()
	_bind(cl, _solar, _us_solar, groups)
	_bind(cl, _pressure, _us_pressure, groups)
	_bind(cl, _wind, _us_wind, groups)
	_bind(cl, _evaporate, _us_evaporate, groups)
	_bind(cl, _advect, _us_advect_temp, groups)
	_bind(cl, _diffuse, _us_diffuse_temp, groups)
	_bind(cl, _advect, _us_advect_hum, groups)
	_bind(cl, _diffuse, _us_diffuse_hum, groups)
	_bind(cl, _advect, _us_advect_cloud, groups)
	_bind(cl, _copy, _us_copy_cloud, groups)
	_bind(cl, _orographic, _us_orographic, groups)
	_bind(cl, _condense, _us_condense, groups, false)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func dispatch_ecology(groups: int) -> void:
	var cl := rd.compute_list_begin()
	_bind(cl, _ecology, _us_ecology, groups, false)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

## 河流子步：substeps 为偶数。
func dispatch_river(groups: int, substeps: int, b: ClimateBuffers) -> void:
	var n := b.N
	b.store.zero_fill(ClimateBuffers.B_FLOW_OUT_A, n)
	b.store.zero_fill(ClimateBuffers.B_FLOW_OUT_B, n)
	b.store.zero_fill(ClimateBuffers.B_STORAGE_A, n)
	b.store.zero_fill(ClimateBuffers.B_STORAGE_B, n)

	var cl := rd.compute_list_begin()
	for i in substeps:
		var us: RID = _us_river_a2b if (i % 2 == 0) else _us_river_b2a
		rd.compute_list_bind_compute_pipeline(cl, _river_step.pipeline)
		rd.compute_list_bind_uniform_set(cl, us, 0)
		rd.compute_list_dispatch(cl, groups, 1, 1)
		rd.compute_list_add_barrier(cl)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func compute_flow_dir_once(groups: int) -> void:
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _river_flow.pipeline)
	rd.compute_list_bind_uniform_set(cl, _us_river_flow, 0)
	rd.compute_list_dispatch(cl, groups, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

# ============================================================
#  释放
# ============================================================

func free_all() -> void:
	for us in [_us_solar, _us_pressure, _us_wind,
			_us_advect_temp, _us_diffuse_temp, _us_advect_hum, _us_diffuse_hum,
			_us_advect_cloud, _us_copy_cloud, _us_evaporate, _us_orographic,
			_us_condense, _us_river_flow, _us_river_a2b, _us_river_b2a,
			_us_ecology]:
		if us != RID():
			rd.free_rid(us)

	for p in [_solar, _pressure, _wind, _advect, _diffuse, _copy,
			_evaporate, _orographic, _condense, _river_flow, _river_step,
			_ecology]:
		if p != null:
			p.dispose()

	for pb in [_p_solar, _p_pressure, _p_wind, _p_advect, _p_advect_hum,
			_p_advect_cloud, _p_diffuse_temp, _p_diffuse_hum_atm,
			_p_evaporate, _p_orographic, _p_condense, _p_river, _p_ecology]:
		if pb != RID():
			rd.free_rid(pb)

# ============================================================
#  内部
# ============================================================

func _bind(cl: int, prog: ComputeProgram, us: RID, groups: int,
		barrier := true) -> void:
	if prog == null or us == RID():
		return
	rd.compute_list_bind_compute_pipeline(cl, prog.pipeline)
	rd.compute_list_bind_uniform_set(cl, us, 0)
	rd.compute_list_dispatch(cl, groups, 1, 1)
	if barrier:
		rd.compute_list_add_barrier(cl)

func _make_set(prog: ComputeProgram, buffers: Array) -> RID:
	var uniforms: Array = []
	for i in buffers.size():
		var buf: RID = buffers[i]
		if buf == RID():
			push_error("[ClimatePipeline] 空 buffer 于 binding %d" % i)
			return RID()
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buf)
		uniforms.append(u)
	return rd.uniform_set_create(uniforms, prog.shader, 0)
