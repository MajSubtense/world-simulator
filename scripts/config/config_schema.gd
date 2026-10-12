class_name ConfigSchema
extends RefCounted
## Resource 字段反射工具。用 @export 元数据生成 UI 描述。
##
## 用法：
##   var entries := ConfigSchema.entries(cfg)
##   # → [{ key, label, min, max, step, is_int, is_seed }, ...]
##
## 分组由调用方（ParameterPanel）声明，因为分组是 UI 概念。

## 返回 cfg 的所有 @export 字段的元数据列表。
static func entries(cfg: Resource) -> Array:
	var out: Array = []
	for prop in cfg.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		if prop.usage & PROPERTY_USAGE_GROUP:
			continue
		if prop.name.begins_with("_") or prop.name == "script":
			continue
		if prop.type != TYPE_INT and prop.type != TYPE_FLOAT:
			continue
		var e := {
			"key": prop.name,
			"label": _humanize(prop.name),
			"min": 0.0,
			"max": 1.0,
			"step": 0.01,
			"is_int": prop.type == TYPE_INT,
			"is_seed": prop.name.ends_with("_seed"),
		}
		if prop.hint == PROPERTY_HINT_RANGE:
			var parts = prop.hint_string.split(",")
			if parts.size() >= 1 and parts[0].is_valid_float():
				e.min = parts[0].to_float()
			if parts.size() >= 2 and parts[1].is_valid_float():
				e.max = parts[1].to_float()
			if parts.size() >= 3 and parts[2].is_valid_float():
				e.step = parts[2].to_float()
		out.append(e)
	return out

## 按 key 建立 { key: entry } 字典，便于快速查询。
static func by_key(cfg: Resource) -> Dictionary:
	var out: Dictionary = {}
	for e in entries(cfg):
		out[e.key] = e
	return out

static func _humanize(snake: String) -> String:
	var words := snake.split("_")
	var out: Array = []
	for w in words:
		out.append(w.capitalize())
	return " ".join(out)