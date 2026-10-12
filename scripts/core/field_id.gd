class_name FieldId
extends RefCounted
## Field 的统一标识。驱动：
##   1. ParameterPanel 的 map mode 下拉列表
##   2. FieldAtlas 的纹理索引
##   3. map_view.gdshader 的 mode 映射
##   4. ViewRouter / main 每帧上传循环

enum {
	TEMPERATURE,
	PRESSURE,
	WIND,
	HUM_ATM,
	PRECIP,
	CLOUD,
	SNOW,
	SOIL,
	RIVER,
	VEG_TYPE,
	VEG_DENSITY,
	TEMP_EMA,
}

const MODES := [
	{"id": TEMPERATURE, "label": "Temperature",        "shader_mode": 2},
	{"id": PRESSURE,    "label": "Pressure",           "shader_mode": 3},
	{"id": WIND,        "label": "Wind",               "shader_mode": 4},
	{"id": HUM_ATM,     "label": "Atm Humidity",       "shader_mode": 5},
	{"id": PRECIP,      "label": "Precipitation",      "shader_mode": 6},
	{"id": CLOUD,       "label": "Cloud",              "shader_mode": 7},
	{"id": SNOW,        "label": "Snow",               "shader_mode": 8},
	{"id": SOIL,        "label": "Soil Water",         "shader_mode": 9},
	{"id": RIVER,       "label": "Rivers",             "shader_mode": 10},
	{"id": VEG_TYPE,    "label": "Vegetation Type",    "shader_mode": 11},
	{"id": VEG_DENSITY, "label": "Vegetation Density", "shader_mode": 12},
	{"id": TEMP_EMA,    "label": "Temperature (EMA)",  "shader_mode": 13},
]

static func all() -> Array:
	return MODES

static func count() -> int:
	return MODES.size()

static func shader_mode(id: int) -> int:
	if id < 0 or id >= MODES.size():
		return 0
	return MODES[id]["shader_mode"]

static func label(id: int) -> String:
	if id < 0 or id >= MODES.size():
		return "Unknown"
	return MODES[id]["label"]