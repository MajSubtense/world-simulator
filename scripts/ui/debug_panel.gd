class_name DebugPanel
extends PanelContainer
## 左下角调试面板。
## 显示：FPS、GPU dispatch、GPU readback、Physics、Frame Total。
##
## 通过 Callable 注入 profile 数据源，不反向引用 main 或任何业务类。

const UPDATE_INTERVAL := 0.3

## 返回 Dictionary 的 Callable。字典 key 见 KEYS。
var profile_provider: Callable

var _timer: float = 0.0
var _fps_label: Label
var _season_label: Label
var _day_label: Label
var _lines: Dictionary = {}

const KEYS := [
	["dispatch",      "GPU Dispatch"],
	["readback",      "GPU Readback"],
	["total",         "GPU Tick"],
	["physics_total", "Physics"],
	["3d_render",     "3D Render"],
	["frame_total",   "FRAME TOTAL"],
]

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.10, 0.88)
	style.border_color = Color(0.30, 0.50, 0.60, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	var title := Label.new()
	title.text = "Profiler"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	vbox.add_child(title)

	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_fps_label)

	_season_label = Label.new()
	_season_label.add_theme_font_size_override("font_size", 11)
	_season_label.text = "Season: --"
	vbox.add_child(_season_label)

	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 11)
	_day_label.text = "Day: --"
	vbox.add_child(_day_label)

	for pair in KEYS:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 11)
		l.text = "%s: --" % pair[1]
		vbox.add_child(l)
		_lines[pair[0]] = l

func _process(delta: float) -> void:
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0
	_refresh()

func _refresh() -> void:
	var fps := Engine.get_frames_per_second()
	_fps_label.text = "FPS: %d" % fps
	if fps < 30:
		_fps_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
	elif fps < 55:
		_fps_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	else:
		_fps_label.add_theme_color_override("font_color", Color(0.70, 1.0, 0.70))

	# 季节显示
	if profile_provider.is_valid():
		var p0: Variant = profile_provider.call()
		if p0 is Dictionary:
			if p0.has("season"):
				var s: float = float(p0["season"])
				_season_label.text = "Season: %s (%.2f)" % [_season_name(s), s]
			if p0.has("day"):
				_day_label.text = "Day: %.0f%%" % (float(p0["day"]) * 100.0)

	var merged: Dictionary = {}
	if profile_provider.is_valid():
		var p: Variant = profile_provider.call()
		if p is Dictionary:
			merged = p

	for pair in KEYS:
		var key: String = pair[0]
		var label: Label = _lines[key]
		if not merged.has(key):
			label.visible = false
			continue
		label.visible = true
		var us: float = float(merged[key])
		var ms := us / 1000.0
		label.text = "%s: %.2f ms" % [pair[1], ms]

		var col := Color(0.80, 0.90, 0.85)
		if key in ["total"]:
			col = Color(0.95, 1.0, 0.75)
		if ms > 40.0:
			col = Color(1.0, 0.40, 0.40)
		elif ms > 15.0:
			col = Color(1.0, 0.80, 0.40)
		label.add_theme_color_override("font_color", col)

func _season_name(s: float) -> String:
	# s ∈ [0, 1]：0=春分，0.25=夏至，0.5=秋分，0.75=冬至
	var ss := fposmod(s, 1.0)
	if ss < 0.125 or ss >= 0.875:
		return "春季"
	elif ss < 0.375:
		return "夏季"
	elif ss < 0.625:
		return "秋季"
	return "冬季"