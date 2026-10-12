class_name Phase
extends RefCounted
## 三阶段枚举。PlanetData 不再持有 phase 字段，
## PhaseController.current_phase 是唯一状态源。
##
## 放在 core/ 而非 app/ 是为了让 ui/ 能直接引用，
## 而不必依赖 app/phase_controller.gd。

enum {
	LAND,
	HEIGHT,
	CLIMATE,
}

static func name_of(p: int) -> String:
	var names := ["LAND", "HEIGHT", "CLIMATE"]
	if p < 0 or p >= names.size():
		return "UNKNOWN"
	return names[p]