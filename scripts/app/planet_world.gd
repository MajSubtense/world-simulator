class_name PlanetWorld
extends RefCounted
## 聚合根：数据 + 生成器 + 气候调度器。
## 唯一数据入口。
##
## 层：
##   plot_map  = 地块层（subdiv=8，642 面）
##   gp        = cell 层（subdiv=64，40962 面）
##   data      = 数据容器

signal land_regenerated
signal height_regenerated
signal climate_started
signal climate_stopped
signal climate_ticked(tick: int)

var gp: GoldbergPolyhedron          # cell 层
var plot_map: PlotMap               # plot 层
var data: PlanetData
var land_gen: LandGenerator
var height_gen: HeightGenerator
var climate: ClimateScheduler
var face_lookup: FaceLookup         # cell 层查找
var plot_geo: PlotGeometry          # plot 内切平面参数化

var _climate_config: ClimateConfig

# ============================================================
func setup(subdiv: int, radius: float,
		land_cfg: LandConfig, height_cfg: HeightConfig,
		climate_cfg: ClimateConfig,
		plot_subdiv: int = PlotMap.DEFAULT_SUBDIV) -> void:
	# cell 层
	gp = GoldbergPolyhedron.get_or_create(subdiv, radius)
	data = PlanetData.new()
	data.init(gp)

	# plot 层
	plot_map = PlotMap.new()
	plot_map.setup(plot_subdiv, radius)

	land_gen = LandGenerator.new()
	land_gen.setup(land_cfg)

	height_gen = HeightGenerator.new()
	height_gen.setup(height_cfg, land_gen)

	face_lookup = FaceLookup.new()
	face_lookup.setup(gp)

	plot_geo = PlotGeometry.new()
	plot_geo.setup(plot_map.gp)   # ← 基于 plot_map，不是 gp

	_climate_config = climate_cfg

# ============================================================
#  阶段 1：海陆
# ============================================================
func generate_land() -> void:
	land_gen.generate(data)
	data.refresh_face_land_flags()
	update_land_score()
	land_regenerated.emit()

# ============================================================
#  阶段 2：高程
# ============================================================
func generate_height() -> void:
	height_gen.invalidate()
	height_gen.generate(data)
	height_regenerated.emit()

# ============================================================
#  阶段 3：气候
# ============================================================
func start_climate() -> void:
	if climate != null:
		return
	data.init_climate()
	climate = ClimateScheduler.new()
	climate.setup(data, _climate_config)
	climate.tick_advanced.connect(_on_climate_tick)
	climate_started.emit()

func stop_climate() -> void:
	if climate == null:
		return
	if climate.tick_advanced.is_connected(_on_climate_tick):
		climate.tick_advanced.disconnect(_on_climate_tick)
	climate.dispose()
	climate = null
	data.clear_climate()
	climate_stopped.emit()

func update(delta: float) -> void:
	if climate != null:
		climate.update(delta)

func get_sun_dir() -> Vector3:
	return climate.get_sun_dir() if climate != null else Vector3(1, 0, 0)

# ============================================================
#  land_score 同步
# ============================================================
func update_land_score() -> void:
	var n := gp.face_count
	if data.f_land_score.size() != n:
		data.f_land_score.resize(n)
	for f in n:
		data.f_land_score[f] = land_gen.land_score_at(gp.face_normals[f])
	if climate != null:
		climate.engine.update_land_score(data)

# ============================================================
#  查询接口
# ============================================================
## 方向 → cell 索引
func cell_at(dir: Vector3) -> int:
	return face_lookup.find(dir)

## 方向 → plot 索引
func plot_at(dir: Vector3) -> int:
	return plot_map.face_at(dir)

## 取 cell 处的气候快照
func sample_climate(dir: Vector3) -> Dictionary:
	var f := cell_at(dir)
	if f < 0 or not data.has_climate():
		return {}
	return {
		"temperature": data.f_temperature[f],
		"humidity_atm": data.f_humidity_atm[f],
		"elevation": data.f_elevation[f],
		"is_land": data.f_is_land_face[f] == 1,
	}

# ============================================================
func _on_climate_tick(tick: int) -> void:
	climate_ticked.emit(tick)
