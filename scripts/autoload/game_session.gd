extends Node
## 跨场景数据容器。持有 PlanetWorld（唯一真相源）。
## autoload 名：GameSession（见 project.godot）。
##
## 生命周期：
##   - 首个场景 _ready 时通过 ensure_world() 创建
##   - 所有场景共享同一个 world 实例
##   - 应用退出时由 _exit_tree 清理

var world: PlanetWorld
var land_config: LandConfig
var height_config: HeightConfig
var climate_config: ClimateConfig
var selected_plot: int = -1

const DEFAULT_SUBDIVISION := 64
const DEFAULT_RADIUS := 1.0
const DEFAULT_PLOT_SUBDIV := 8

func ensure_world(subdiv: int = DEFAULT_SUBDIVISION,
		radius: float = DEFAULT_RADIUS,
		plot_subdiv: int = DEFAULT_PLOT_SUBDIV) -> PlanetWorld:
	if world != null:
		return world
	land_config = LandConfig.new()
	height_config = HeightConfig.new()
	climate_config = ClimateConfig.new()
	world = PlanetWorld.new()
	world.setup(subdiv, radius, land_config, height_config, climate_config, plot_subdiv)
	return world

func has_world() -> bool:
	return world != null

## 清空会话（调试 / 重开用）。
func reset() -> void:
	if world != null:
		world.stop_climate()
		world = null
	land_config = null
	height_config = null
	climate_config = null
	selected_plot = -1

func _exit_tree() -> void:
	reset()