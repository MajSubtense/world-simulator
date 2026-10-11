class_name DebugPanel
extends PanelContainer
## 左下角调试面板。
## 显示：FPS、GPU dispatch、GPU 回读、地图平滑、纹理上传、总计。

const UPDATE_INTERVAL := 0.3

var climate_sim: ClimateSimulator
var main: Node = null

var _timer: float = 0.0
var _fps_label: Label
var _lines: Dictionary = {}

const KEYS := [
	["dispatch",       "GPU Dispatch"],
	["readback",       "GPU Readback"],
	["total",          "GPU Tick"],
	["physics_total",  "Physics"],
	["3d_render",      "3D Render"],
	["frame_total",    "FRAME TOTAL"],
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

	for pair in KEYS:
		var key: String = pair[0]
		var label_text: String = pair[1]
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 11)
		l.text = "%s: --" % label_text
		vbox.add_child(l)
		_lines[key] = l

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

	# 合并两个来源的 profile
	var merged := {}
	if climate_sim != null:
		for k in climate_sim.profile:
			merged[k] = climate_sim.profile[k]
	if main != null and main.has_method("get_frame_profile"):
		var fp: Dictionary = main.get_frame_profile()
		for k in fp:
			merged[k] = fp[k]

	for pair in KEYS:
		var key: String = pair[0]
		var label_text: String = pair[1]
		var label: Label = _lines[key]
		if not merged.has(key):
			label.visible = false
			continue
		label.visible = true
		var us: float = float(merged[key])
		var ms := us / 1000.0
		label.text = "%s: %.2f ms" % [label_text, ms]

		var col := Color(0.80, 0.90, 0.85)
		if key in ["total", "map_total"]:
			col = Color(0.95, 1.0, 0.75)
		if ms > 40.0:
			col = Color(1.0, 0.40, 0.40)
		elif ms > 15.0:
			col = Color(1.0, 0.80, 0.40)
		label.add_theme_color_override("font_color", col)