class_name ClimateSimulator
extends RefCounted
## 气候模拟器（阶段 3）。
##
## 职责：
##   1. 驱动 tick 节奏（现实时间 → 模拟时间）
##   2. 每 tick 计算太阳方向（自转 + 公转）
##   3. 调用 GpuClimate.tick()，回读结果到 PlanetData
##   4. 控制河流累积的触发频率
##
## 所有物理参数从 ClimateConfig 读。

var config: ClimateConfig
var data: PlanetData
var gpu: GpuClimate

var tick_count: int = 0
var _accumulator: float = 0.0
const MAX_TICKS_PER_FRAME := 8
const TICKS_PER_YEAR := 14400

var river_interval: int = 120
var _river_counter: int = 0

var profile: Dictionary = {"total": 0}

signal tick_advanced(tick: int)
signal river_updated

var _sun_dir: Vector3 = Vector3(1.0, 0.0, 0.0)

# ============================================================
func setup(d: PlanetData, cfg: ClimateConfig) -> void:
	data = d
	config = cfg
	gpu = GpuClimate.new()
	if not gpu.setup(d.gp, d):
		push_error("GpuClimate 初始化失败")
		gpu = null
	_river_counter = 0

func update(delta: float) -> void:
	if data == null or gpu == null or config == null:
		return
	_accumulator += delta * config.ticks_per_second
	_accumulator = minf(_accumulator, float(MAX_TICKS_PER_FRAME))
	var count := 0
	while _accumulator >= 1.0 and count < MAX_TICKS_PER_FRAME:
		_accumulator -= 1.0
		_run_tick()
		count += 1

func get_sun_dir() -> Vector3:
	return _sun_dir

func step_once() -> void:
	if gpu != null:
		_run_tick()

# ============================================================
func _run_tick() -> void:
	tick_count += 1

	var year_angle := float(tick_count % TICKS_PER_YEAR) / float(TICKS_PER_YEAR) * TAU
	var season = (year_angle / TAU + config.sun_season) - floor(year_angle / TAU + config.sun_season)
	_sun_dir = SolarModel.sun_direction(
		tick_count, config.day_length, config.sun_tilt, season)

	var t0 := Time.get_ticks_usec()

	_river_counter += 1
	var do_river := _river_counter >= river_interval
	if do_river:
		_river_counter = 0

	gpu.tick(_sun_dir, 1.0, config, do_river)
	_readback_to_data(do_river)

	profile["total"] = Time.get_ticks_usec() - t0
	tick_advanced.emit(tick_count)

func _readback_to_data(do_river: bool) -> void:
	var t := gpu.get_temperature()
	if t.size() == data.f_temperature.size(): data.f_temperature = t
	var p := gpu.get_pressure()
	if p.size() == data.f_pressure.size(): data.f_pressure = p
	var w := gpu.get_wind()
	if w.size() == data.f_wind.size(): data.f_wind = w
	var ha := gpu.get_humidity_atm()
	if ha.size() == data.f_humidity_atm.size(): data.f_humidity_atm = ha
	var pr := gpu.get_precipitation()
	if pr.size() == data.f_precipitation.size(): data.f_precipitation = pr
	var cl := gpu.get_cloud()
	if cl.size() == data.f_cloud.size(): data.f_cloud = cl
	var sn := gpu.get_snow()
	if sn.size() == data.f_snow.size(): data.f_snow = sn
	var so := gpu.get_soil()
	if so.size() == data.f_soil_water.size(): data.f_soil_water = so
	var ri := gpu.get_river_input()
	if ri.size() == data.f_river_input.size(): data.f_river_input = ri

	if do_river:
		var fl := gpu.get_flow()
		if fl.size() == data.f_flow.size(): data.f_flow = fl
		var fd := gpu.get_flow_dir()
		if fd.size() == data.f_flow_dir.size(): data.f_flow_dir = fd
		river_updated.emit()