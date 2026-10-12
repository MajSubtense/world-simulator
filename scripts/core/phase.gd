class_name Phase
extends RefCounted
## 阶段枚举。PlanetData 不再持有 phase 字段，
## PhaseController.current_phase 是唯一状态源。

enum {
	LAND,
	HEIGHT,
	CLIMATE,
	SELECT,
}

static func name_of(p: int) -> String:
	var names := ["LAND", "HEIGHT", "CLIMATE", "SELECT"]
	if p < 0 or p >= names.size():
		return "UNKNOWN"
	return names[p]