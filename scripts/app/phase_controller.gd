class_name PhaseController
extends RefCounted
## 阶段迁移唯一入口。

signal phase_transition_started(from_phase: int, to_phase: int)
signal phase_changed(new_phase: int)

var current_phase: int = Phase.LAND

var _world: PlanetWorld
var _transitioning: bool = false

func setup(world: PlanetWorld) -> void:
	_world = world

func can_next() -> bool:
	return current_phase < Phase.SELECT and not _transitioning

func can_prev() -> bool:
	return current_phase > Phase.LAND and not _transitioning

func next() -> void:
	if not can_next():
		return
	_transitioning = true
	var from := current_phase
	var to := from + 1
	phase_transition_started.emit(from, to)

	match to:
		Phase.HEIGHT:
			_world.generate_height()
		Phase.CLIMATE:
			_world.start_climate()
		Phase.SELECT:
			pass  # UI 状态切换，无数据变更

	current_phase = to
	_transitioning = false
	phase_changed.emit(to)

func prev() -> void:
	if not can_prev():
		return
	_transitioning = true
	var from := current_phase
	var to := from - 1
	phase_transition_started.emit(from, to)

	match from:
		Phase.SELECT:
			pass
		Phase.CLIMATE:
			_world.stop_climate()
			_world.generate_height()
		Phase.HEIGHT:
			_world.data.clear_height()
			_world.generate_land()

	current_phase = to
	_transitioning = false
	phase_changed.emit(to)

## 从 world 现有状态推断当前阶段。用于切回 Generator 场景时恢复。
func infer_from_world(world: PlanetWorld) -> void:
	_world = world
	if world == null or world.data == null:
		current_phase = Phase.LAND
		return
	if world.data.has_climate():
		current_phase = Phase.SELECT  # 有气候 = 至少到过 CLIMATE
		return
	var has_height := false
	for v in world.data.f_elevation:
		if absf(v) > 0.0001:
			has_height = true
			break
	current_phase = Phase.HEIGHT if has_height else Phase.LAND