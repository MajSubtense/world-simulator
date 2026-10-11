class_name ParameterPanel
extends PanelContainer
## 三阶段参数面板。
##
## 设计：滑块直接读写外部传入的 Config 对象。
##   参数变化 → 写回 config → 发信号给 main.gd
##   Config 变更后调用 sync_from_config() 刷新滑块显示。
##
## 改默认值 → 只改 Config 文件。

signal land_params_changed
signal height_params_changed
signal climate_params_changed
signal next_step_pressed
signal prev_step_pressed
signal view_mode_changed(is_map: bool)
signal map_projection_changed(projection: int)
signal map_mode_changed(mode: int)
signal wind_arrows_toggled(show: bool)

# ---- 配置对象（外部注入）----
var land_config: LandConfig
var height_config: HeightConfig
var climate_config: ClimateConfig

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _spinboxes: Dictionary = {}

var _land_group: VBoxContainer
var _height_group: VBoxContainer
var _climate_group: VBoxContainer

var _next_btn: Button
var _prev_btn: Button
var _phase_label: Label
var _fps_label: Label

var _projection_row: HBoxContainer
var _mode_row: HBoxContainer
var _mode_opt: OptionButton
var _arrow_check: CheckBox

var _current_phase: int = PlanetData.Phase.LAND
var _is_map: bool = false
var _current_map_mode: int = 2

var _dragging: bool = false

# ============================================================
func _ready() -> void:
	_build_style()
	_build_ui()
	show_phase(PlanetData.Phase.LAND)
	_place_at_default_position()

func _process(_delta: float) -> void:
	if _fps_label and visible:
		var fps := Engine.get_frames_per_second()
		_fps_label.text = "FPS: %d" % fps
		if fps < 30:
			_fps_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		elif fps < 55:
			_fps_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		else:
			_fps_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))

# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			visible = not visible
			get_viewport().set_input_as_handled()

func _on_title_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		position += event.relative
		_clamp_position()
		accept_event()

func _clamp_position() -> void:
	var vp := get_viewport_rect().size
	var min_x := -size.x + 80.0
	var max_x := vp.x - 80.0
	var min_y := 0.0
	var max_y := vp.y - 40.0
	position.x = clampf(position.x, min_x, max_x)
	position.y = clampf(position.y, min_y, max_y)

func _place_at_default_position() -> void:
	await get_tree().process_frame
	reset_size()
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	var my_size := size
	if my_size.x <= 0: my_size.x = 400
	if my_size.y <= 0: my_size.y = 700
	position = Vector2(vp.x - my_size.x - 20, 20)
	_clamp_position()

# ============================================================
func _build_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.94)
	style.border_color = Color(0.30, 0.40, 0.55, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

# ============================================================
func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var title := Label.new()
	title.text = "World Generator"
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.gui_input.connect(_on_title_drag)
	vbox.add_child(title)

	_fps_label = Label.new()
	_fps_label.text = "FPS: --"
	_fps_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_fps_label)

	_phase_label = Label.new()
	_phase_label.text = "Step 1 / 3"
	_phase_label.add_theme_font_size_override("font_size", 12)
	_phase_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	vbox.add_child(_phase_label)

	# View
	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 6)
	vbox.add_child(view_row)

	var view_label := Label.new()
	view_label.text = "View"
	view_label.custom_minimum_size = Vector2(60, 0)
	view_row.add_child(view_label)

	var btn_3d := Button.new()
	btn_3d.text = "3D"
	btn_3d.toggle_mode = true
	btn_3d.button_pressed = true
	btn_3d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_3d.focus_mode = Control.FOCUS_NONE
	view_row.add_child(btn_3d)

	var btn_map := Button.new()
	btn_map.text = "Map"
	btn_map.toggle_mode = true
	btn_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_map.focus_mode = Control.FOCUS_NONE
	view_row.add_child(btn_map)

	btn_3d.pressed.connect(func():
		btn_map.button_pressed = false
		view_mode_changed.emit(false)
	)
	btn_map.pressed.connect(func():
		btn_3d.button_pressed = false
		view_mode_changed.emit(true)
	)

	# Projection
	_projection_row = HBoxContainer.new()
	_projection_row.add_theme_constant_override("separation", 6)
	_projection_row.visible = false
	vbox.add_child(_projection_row)

	var proj_label := Label.new()
	proj_label.text = "Projection"
	proj_label.custom_minimum_size = Vector2(80, 0)
	_projection_row.add_child(proj_label)

	var proj_opt := OptionButton.new()
	proj_opt.add_item("Rectangle", 0)
	proj_opt.add_item("Ellipse",   1)
	proj_opt.select(0)
	proj_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	proj_opt.focus_mode = Control.FOCUS_NONE
	_projection_row.add_child(proj_opt)

	proj_opt.item_selected.connect(func(idx):
		map_projection_changed.emit(idx)
	)

	# Map Mode
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 6)
	_mode_row.visible = false
	vbox.add_child(_mode_row)

	var mode_label := Label.new()
	mode_label.text = "Map Mode"
	mode_label.custom_minimum_size = Vector2(80, 0)
	_mode_row.add_child(mode_label)

	_mode_opt = OptionButton.new()
	_mode_opt.add_item("Land",          0)
	_mode_opt.add_item("Height",        1)
	_mode_opt.add_item("Temperature",   2)
	_mode_opt.add_item("Pressure",      3)
	_mode_opt.add_item("Wind",          4)
	_mode_opt.add_item("Atm Humidity",  5)
	_mode_opt.add_item("Precipitation", 6)
	_mode_opt.add_item("Cloud",         7)
	_mode_opt.add_item("Snow",          8)
	_mode_opt.add_item("Soil Water",    9)
	_mode_opt.add_item("Rivers",       10)
	_mode_opt.select(2)
	_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_opt.focus_mode = Control.FOCUS_NONE
	_mode_row.add_child(_mode_opt)

	_mode_opt.item_selected.connect(func(idx):
		_current_map_mode = idx
		map_mode_changed.emit(idx)
		_refresh_map_rows()
	)

	_arrow_check = CheckBox.new()
	_arrow_check.text = "Arrows"
	_arrow_check.button_pressed = false
	_arrow_check.focus_mode = Control.FOCUS_NONE
	_mode_row.add_child(_arrow_check)
	_arrow_check.toggled.connect(func(v):
		wind_arrows_toggled.emit(v)
	)

	# ============================================================
	#  海陆
	# ============================================================
	_land_group = VBoxContainer.new()
	_land_group.add_theme_constant_override("separation", 4)
	vbox.add_child(_land_group)

	var land_body := _make_collapsible(_land_group, "Land / Ocean",
		Color(0.65, 0.82, 1.0), true)
	_make_slider(land_body, "land_ratio",       "Land Ratio",       0.0, 1.0, 0.01, "land")
	_make_slider(land_body, "land_dispersion",  "Land Dispersion",  0.0, 1.0, 0.01, "land")
	_make_spinbox(land_body, "land_seed",       "Land Seed",        "land")
	_make_slider(land_body, "erosion_strength", "Erosion Strength", 0.0, 1.0, 0.01, "land")
	_make_spinbox(land_body, "erosion_seed",    "Erosion Seed",     "land")

	# ============================================================
	#  高程
	# ============================================================
	_height_group = VBoxContainer.new()
	_height_group.add_theme_constant_override("separation", 4)
	vbox.add_child(_height_group)

	var h_body := _make_collapsible(_height_group, "Land Height",
		Color(0.65, 1.0, 0.65), true)
	_make_slider(h_body, "land_base",         "Base Height",      0.0, 0.05, 0.005, "height")
	_make_slider(h_body, "continental_rise",  "Continental Rise", 0.0, 0.40, 0.01, "height")
	_make_slider(h_body, "continental_pow",   "Continental Pow",  0.5, 4.0, 0.1, "height")
	_make_slider(h_body, "coast_damping",     "Coast Damping",    0.05, 0.5, 0.01, "height")

	_make_slider(h_body, "plateau_height",    "Plateau Height",   0.0, 0.20, 0.005, "height")
	_make_slider(h_body, "plateau_freq",      "Plateau Freq",     0.3, 3.0, 0.05, "height")
	_make_slider(h_body, "plateau_threshold", "Plateau Threshold",-0.5, 0.5, 0.01, "height")
	_make_spinbox(h_body, "plateau_seed",     "Plateau Seed",     "height")

	_make_slider(h_body, "mountain_peak",     "Mountain Peak",    0.0, 1.0, 0.01, "height")
	_make_slider(h_body, "belt_freq",         "Belt Freq",        0.3, 3.0, 0.05, "height")
	_make_slider(h_body, "belt_threshold",    "Belt Threshold",   0.0, 0.5, 0.01, "height")
	_make_slider(h_body, "ridge_freq",        "Ridge Freq",       1.0, 8.0, 0.1, "height")
	_make_spinbox(h_body, "mountain_seed",    "Mountain Seed",    "height")

	_make_slider(h_body, "hill_detail",       "Hill Detail",      0.0, 0.10, 0.005, "height")
	_make_slider(h_body, "hill_freq",         "Hill Freq",        4.0, 24.0, 0.5, "height")

	var o_body := _make_collapsible(_height_group, "Ocean Depth",
		Color(0.65, 0.82, 1.0), true)
	_make_slider(o_body, "ocean_depth",  "Ocean Depth",  0.0, 0.40, 0.01, "height")
	_make_slider(o_body, "ocean_freq",   "Ocean Freq",   0.5, 8.0, 0.1, "height")
	_make_spinbox(o_body, "ocean_seed",  "Ocean Seed",   "height")
	_make_slider(o_body, "ocean_detail", "Ocean Detail", 0.0, 0.10, 0.005, "height")
	_make_slider(o_body, "ocean_detail_freq", "Detail Freq", 0.5, 20.0, 0.1, "height")

	# ============================================================
	#  气候
	# ============================================================
	_climate_group = VBoxContainer.new()
	_climate_group.add_theme_constant_override("separation", 4)
	vbox.add_child(_climate_group)

	var t_body := _make_collapsible(_climate_group, "Time",
		Color(1.0, 0.85, 0.55), true)
	_make_slider(t_body, "ticks_per_second", "Ticks / Sec", 0.1, 60.0, 0.1, "climate")
	_make_slider(t_body, "day_length",       "Day Ticks",   24, 720, 1, "climate")
	_make_slider(t_body, "sun_tilt",         "Sun Tilt",    0.0, 0.7, 0.01, "climate")
	_make_slider(t_body, "sun_season",       "Season",      0.0, 1.0, 0.01, "climate")

	var temp_body := _make_collapsible(_climate_group, "Temperature",
		Color(1.0, 0.65, 0.65), false)
	_make_slider(temp_body, "solar_absorption", "Solar Absorb", 0.0, 0.05, 0.001, "climate")
	_make_slider(temp_body, "thermal_emission", "Thermal Emit", 0.0, 0.03, 0.001, "climate")
	_make_slider(temp_body, "base_relaxation",  "Base Relax",   0.0, 0.05, 0.001, "climate")
	_make_slider(temp_body, "lapse_rate",       "Lapse Rate",   0.0, 3.0, 0.1, "climate")
	_make_slider(temp_body, "advection_speed",  "Advection",    0.0, 2.0, 0.05, "climate")
	_make_slider(temp_body, "diffusion_coeff",  "Diffusion",    0.0, 0.5, 0.01, "climate")

	var wind_body := _make_collapsible(_climate_group, "Wind / Circulation",
		Color(0.75, 0.95, 1.0), false)
	_make_slider(wind_body, "circulation_amp", "Circulation", 0.0, 1.0, 0.01, "climate")
	_make_slider(wind_body, "wind_scale",      "Wind Scale",  0.0, 3.0, 0.05, "climate")

	var hum_body := _make_collapsible(_climate_group, "Humidity",
		Color(0.55, 0.85, 1.0), false)
	_make_slider(hum_body, "humidity_advection",     "Hum Advect",      0.0, 0.20, 0.005, "climate")
	_make_slider(hum_body, "humidity_diffusion_atm", "Hum Diffuse Atm", 0.0, 0.10, 0.005, "climate")

	var cloud_body := _make_collapsible(_climate_group, "Cloud / Rain",
		Color(0.85, 0.75, 1.0), false)
	_make_slider(cloud_body, "cloud_form_rate",  "Cloud Form",  0.0, 1.0, 0.01, "climate")
	_make_slider(cloud_body, "cloud_decay",      "Cloud Decay", 0.0, 0.1, 0.005, "climate")
	_make_slider(cloud_body, "cloud_threshold",  "Cloud Thresh",0.0, 1.0, 0.01, "climate")
	_make_slider(cloud_body, "release_rate",     "Release Rate",0.0, 1.0, 0.05, "climate")
	_make_slider(cloud_body, "cloud_advection",  "Cloud Advect",0.0, 2.0, 0.05, "climate")

	var evap_body := _make_collapsible(_climate_group, "Evaporation",
		Color(0.85, 0.75, 1.0), false)
	_make_slider(evap_body, "evap_rate_ocean",     "Evap Ocean",  0.0, 0.50, 0.01, "climate")
	_make_slider(evap_body, "evap_rate_land",      "Evap Land",   0.0, 0.30, 0.01, "climate")
	_make_slider(evap_body, "latent_heat",         "Latent Heat", 0.0, 1.0, 0.05, "climate")
	_make_slider(evap_body, "orographic_factor",   "Orographic",  0.0, 0.5, 0.005, "climate")
	_make_slider(evap_body, "latent_heat_release", "Heat Release",0.0, 1.0, 0.05, "climate")
	_make_slider(evap_body, "sat_base",            "Sat Base",    0.05, 0.5, 0.01, "climate")
	_make_slider(evap_body, "sat_temp_factor",     "Sat Temp F",  0.5, 5.0, 0.1, "climate")

	var snow_body := _make_collapsible(_climate_group, "Snow / Baseflow",
		Color(0.85, 0.95, 1.0), false)
	_make_slider(snow_body, "melt_rate",     "Melt Rate",     0.0, 0.5, 0.005, "climate")
	_make_slider(snow_body, "runoff_ratio",  "Runoff Ratio",  0.0, 1.0, 0.01, "climate")
	_make_slider(snow_body, "baseflow_rate", "Baseflow Rate", 0.0, 0.05, 0.001, "climate")

	# ---- 阶段按钮 ----
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	_prev_btn = Button.new()
	_prev_btn.text = "← Prev"
	_prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_btn.focus_mode = Control.FOCUS_NONE
	_prev_btn.pressed.connect(func(): prev_step_pressed.emit())
	btn_row.add_child(_prev_btn)

	_next_btn = Button.new()
	_next_btn.text = "Next →"
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(func(): next_step_pressed.emit())
	btn_row.add_child(_next_btn)

	var hint := Label.new()
	hint.text = "Tab: toggle panel  ·  drag title"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75))
	vbox.add_child(hint)

# ============================================================
#  可折叠
# ============================================================
func _make_collapsible(parent: Control, title: String, color: Color,
		default_open: bool) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	parent.add_child(root)

	var header := Button.new()
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = Control.FOCUS_NONE
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.add_theme_color_override("font_color", color)
	header.add_theme_color_override("font_hover_color", color.lightened(0.2))
	header.add_theme_color_override("font_pressed_color", color)
	header.add_theme_font_size_override("font_size", 12)

	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		header.add_theme_stylebox_override(s, empty)

	header.text = _header_text(title, default_open)
	root.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.visible = default_open
	root.add_child(body)

	var state := {"open": default_open}
	header.pressed.connect(func():
		state.open = not state.open
		body.visible = state.open
		header.text = _header_text(title, state.open)
	)

	return body

func _header_text(title: String, open: bool) -> String:
	return ("▼  " if open else "▶  ") + title

# ============================================================
#  滑块 / SpinBox（从 Config 读写）
# ============================================================
func _make_slider(parent: Control, key: String, label_text: String,
		minv: float, maxv: float, step: float, group: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(100, 0)
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	_sliders[key] = slider
	_value_labels[key] = value_label

	# 拖动中：只更新显示 + 触发 config 写入，不打断滑块
	slider.value_changed.connect(func(raw_v):
		var v := clampf(raw_v, minv, maxv)
		value_label.text = _format(v, step >= 1.0)
		_apply_to_config(key, v, group)
	)
	# 松手：夹回范围，防止越界残留
	slider.drag_ended.connect(func(_changed):
		var v := clampf(slider.value, minv, maxv)
		slider.set_value_no_signal(v)
		value_label.text = _format(v, step >= 1.0)
		_apply_to_config(key, v, group)
	)

func _make_spinbox(parent: Control, key: String, label_text: String,
		group: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 9999999
	spin.step = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)

	_spinboxes[key] = spin
	spin.value_changed.connect(func(v): _apply_to_config(key, v, group))

func _format(v: float, force_int: bool) -> String:
	return "%d" % int(round(v)) if force_int else "%.3f" % v

## 把滑块 / spinbox 值写回对应 Config 对象，并发信号。
func _apply_to_config(key: String, v: float, group: String) -> void:
	match group:
		"land":
			if land_config == null: return
			match key:
				"land_ratio":       land_config.land_ratio = v
				"land_dispersion":  land_config.land_dispersion = v
				"land_seed":        land_config.land_seed = int(v)
				"erosion_strength": land_config.erosion_strength = v
				"erosion_seed":     land_config.erosion_seed = int(v)
			land_params_changed.emit()
		"height":
			if height_config == null: return
			match key:
				"land_base":         height_config.land_base = v
				"continental_rise":  height_config.continental_rise = v
				"continental_pow":   height_config.continental_pow = v
				"coast_damping":     height_config.coast_damping = v
				"plateau_height":    height_config.plateau_height = v
				"plateau_freq":      height_config.plateau_freq = v
				"plateau_threshold": height_config.plateau_threshold = v
				"plateau_seed":      height_config.plateau_seed = int(v)
				"mountain_peak":     height_config.mountain_peak = v
				"belt_freq":         height_config.belt_freq = v
				"belt_threshold":    height_config.belt_threshold = v
				"ridge_freq":        height_config.ridge_freq = v
				"mountain_seed":     height_config.mountain_seed = int(v)
				"hill_detail":       height_config.hill_detail = v
				"hill_freq":         height_config.hill_freq = v
				"ocean_depth":       height_config.ocean_depth = v
				"ocean_freq":        height_config.ocean_freq = v
				"ocean_seed":        height_config.ocean_seed = int(v)
				"ocean_detail":      height_config.ocean_detail = v
				"ocean_detail_freq": height_config.ocean_detail_freq = v
			height_params_changed.emit()
		"climate":
			if climate_config == null: return
			match key:
				"ticks_per_second": climate_config.ticks_per_second = v
				"day_length":       climate_config.day_length = int(v)
				"sun_tilt":         climate_config.sun_tilt = v
				"sun_season":       climate_config.sun_season = v
				"solar_absorption": climate_config.solar_absorption = v
				"thermal_emission": climate_config.thermal_emission = v
				"base_relaxation":  climate_config.base_relaxation = v
				"lapse_rate":       climate_config.lapse_rate = v
				"advection_speed":  climate_config.advection_speed = v
				"diffusion_coeff":  climate_config.diffusion_coeff = v
				"circulation_amp":  climate_config.circulation_amp = v
				"wind_scale":       climate_config.wind_scale = v
				"humidity_advection":     climate_config.humidity_advection = v
				"humidity_diffusion_atm": climate_config.humidity_diffusion_atm = v
				"cloud_form_rate":  climate_config.cloud_form_rate = v
				"cloud_decay":      climate_config.cloud_decay = v
				"cloud_threshold":  climate_config.cloud_threshold = v
				"release_rate":     climate_config.release_rate = v
				"cloud_advection":  climate_config.cloud_advection = v
				"evap_rate_ocean":  climate_config.evap_rate_ocean = v
				"evap_rate_land":   climate_config.evap_rate_land = v
				"latent_heat":      climate_config.latent_heat = v
				"orographic_factor": climate_config.orographic_factor = v
				"latent_heat_release": climate_config.latent_heat_release = v
				"sat_base":         climate_config.sat_base = v
				"sat_temp_factor":  climate_config.sat_temp_factor = v
				"melt_rate":        climate_config.melt_rate = v
				"runoff_ratio":     climate_config.runoff_ratio = v
				"baseflow_rate":    climate_config.baseflow_rate = v
			climate_params_changed.emit()

# ============================================================
#  从 Config 同步到 UI（初始化 / 载入存档时用）
# ============================================================
func sync_from_config() -> void:
	if land_config != null:
		_sync_slider("land_ratio", land_config.land_ratio, false)
		_sync_slider("land_dispersion", land_config.land_dispersion, false)
		_sync_spin("land_seed", land_config.land_seed)
		_sync_slider("erosion_strength", land_config.erosion_strength, false)
		_sync_spin("erosion_seed", land_config.erosion_seed)

	if height_config != null:
		for pair in [
			["land_base", height_config.land_base],
			["continental_rise", height_config.continental_rise],
			["continental_pow", height_config.continental_pow],
			["coast_damping", height_config.coast_damping],
			["plateau_height", height_config.plateau_height],
			["plateau_freq", height_config.plateau_freq],
			["plateau_threshold", height_config.plateau_threshold],
			["mountain_peak", height_config.mountain_peak],
			["belt_freq", height_config.belt_freq],
			["belt_threshold", height_config.belt_threshold],
			["ridge_freq", height_config.ridge_freq],
			["hill_detail", height_config.hill_detail],
			["hill_freq", height_config.hill_freq],
			["ocean_depth", height_config.ocean_depth],
			["ocean_freq", height_config.ocean_freq],
			["ocean_detail", height_config.ocean_detail],
			["ocean_detail_freq", height_config.ocean_detail_freq],
		]:
			_sync_slider(pair[0], pair[1], false)
		_sync_spin("plateau_seed", height_config.plateau_seed)
		_sync_spin("mountain_seed", height_config.mountain_seed)
		_sync_spin("ocean_seed", height_config.ocean_seed)

	if climate_config != null:
		for pair in [
			["ticks_per_second", climate_config.ticks_per_second],
			["sun_tilt", climate_config.sun_tilt],
			["sun_season", climate_config.sun_season],
			["solar_absorption", climate_config.solar_absorption],
			["thermal_emission", climate_config.thermal_emission],
			["base_relaxation", climate_config.base_relaxation],
			["lapse_rate", climate_config.lapse_rate],
			["advection_speed", climate_config.advection_speed],
			["diffusion_coeff", climate_config.diffusion_coeff],
			["circulation_amp", climate_config.circulation_amp],
			["wind_scale", climate_config.wind_scale],
			["humidity_advection", climate_config.humidity_advection],
			["humidity_diffusion_atm", climate_config.humidity_diffusion_atm],
			["cloud_form_rate", climate_config.cloud_form_rate],
			["cloud_decay", climate_config.cloud_decay],
			["cloud_threshold", climate_config.cloud_threshold],
			["release_rate", climate_config.release_rate],
			["cloud_advection", climate_config.cloud_advection],
			["evap_rate_ocean", climate_config.evap_rate_ocean],
			["evap_rate_land", climate_config.evap_rate_land],
			["latent_heat", climate_config.latent_heat],
			["orographic_factor", climate_config.orographic_factor],
			["latent_heat_release", climate_config.latent_heat_release],
			["sat_base", climate_config.sat_base],
			["sat_temp_factor", climate_config.sat_temp_factor],
			["melt_rate", climate_config.melt_rate],
			["runoff_ratio", climate_config.runoff_ratio],
			["baseflow_rate", climate_config.baseflow_rate],
		]:
			_sync_slider(pair[0], pair[1], false)
		_sync_slider("day_length", climate_config.day_length, true)

func _sync_slider(key: String, v: float, force_int: bool) -> void:
	if not _sliders.has(key): return
	var s: HSlider = _sliders[key]
	s.set_value_no_signal(v)
	if _value_labels.has(key):
		_value_labels[key].text = _format(v, force_int)

func _sync_spin(key: String, v: int) -> void:
	if not _spinboxes.has(key): return
	_spinboxes[key].set_value_no_signal(v)

# ============================================================
#  阶段 / 视图
# ============================================================
func show_phase(phase: int) -> void:
	_current_phase = phase
	_land_group.visible = (phase == PlanetData.Phase.LAND)
	_height_group.visible = (phase == PlanetData.Phase.HEIGHT)
	_climate_group.visible = (phase == PlanetData.Phase.CLIMATE)

	_prev_btn.visible = (phase != PlanetData.Phase.LAND)
	_next_btn.visible = (phase != PlanetData.Phase.CLIMATE)

	match phase:
		PlanetData.Phase.LAND:
			_phase_label.text = "Step 1 / 3 · Land / Ocean"
		PlanetData.Phase.HEIGHT:
			_phase_label.text = "Step 2 / 3 · Height"
		PlanetData.Phase.CLIMATE:
			_phase_label.text = "Step 3 / 3 · Climate"

	_refresh_map_rows()

func set_view_is_map(is_map: bool) -> void:
	_is_map = is_map
	_refresh_map_rows()

func _refresh_map_rows() -> void:
	if _projection_row: _projection_row.visible = _is_map
	if _mode_row: _mode_row.visible = _is_map
	if _mode_opt:
		var allow_all := (_current_phase == PlanetData.Phase.CLIMATE)
		for i in _mode_opt.item_count:
			_mode_opt.set_item_disabled(i, (i > 1) and not allow_all)

func set_map_mode(mode: int) -> void:
	_current_map_mode = mode
	if _mode_opt: _mode_opt.select(mode)

func get_map_mode() -> int:
	return _current_map_mode