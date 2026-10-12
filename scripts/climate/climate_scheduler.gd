class_name ClimateScheduler
extends RefCounted
## CPU 侧气候调度器。
##
## 职责：
##   1. 按现实时间驱动 tick 节奏
##   2. 每 tick 计算太阳方向（自转 + 公转）
##   3. 调用 ClimateEngine.tick()，引擎内部回读数据
##   4. 控制河流累积的触发频率
##
## 不直接使用 RenderingDevice —— 所有 GPU 调用在 compute/climate/。

const MAX_TICKS_PER_FRAME := 8

var data: PlanetData
var config: ClimateConfig
var engine: ClimateEngine

var tick_count: int = 0
var _accumulator: float = 0.0
var _river_counter: int = 0
var _sun_dir: Vector3 = Vector3(1.0, 0.0, 0.0)
var _initialized: bool = false
var _ecology_counter: int = 0

var profile: Dictionary = {"total": 0}

signal tick_advanced(tick: int)
signal river_updated

# ============================================================
func setup(d: PlanetData, cfg: ClimateConfig) -> void:
	data = d
	config = cfg
	engine = ClimateEngine.new()
	if not engine.setup(d.gp, d):
		push_error("[ClimateScheduler] ClimateEngine 初始化失败")
		engine = null
		return
	_river_counter = 0
	_initialized = true

func update(delta: float) -> void:
	if data == null or engine == null or config == null or not _initialized:
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
	if engine != null and _initialized:
		_run_tick()

## 释放 GPU 资源。必须在离开 CLIMATE 阶段时调用。
func dispose() -> void:
	if engine != null:
		engine.dispose()
		engine = null
	_initialized = false

# ============================================================
func _run_tick() -> void:
	tick_count += 1

	var ticks_per_year := maxi(1, config.ticks_per_year)
	var year_angle := float(tick_count % ticks_per_year) / float(ticks_per_year) * TAU
	var season := fposmod(year_angle / TAU + config.initial_season, 1.0)
	_sun_dir = SolarModel.sun_direction(
		tick_count, config.ticks_per_day, config.axial_tilt, season)

	var t0 := Time.get_ticks_usec()

	_river_counter += 1
	var do_river := _river_counter >= config.river_trigger_interval
	if do_river:
		_river_counter = 0

	_ecology_counter += 1
	var do_ecology := _ecology_counter >= config.ecology_interval
	if do_ecology:
		_ecology_counter = 0

	engine.tick(_sun_dir, 1.0, config, do_river, do_ecology)
	engine.writeback_to(data, do_river, do_ecology)
	profile = engine.profile
	profile["total"] = Time.get_ticks_usec() - t0

	tick_advanced.emit(tick_count)
	if do_river:
		river_updated.emit()