class_name ParameterPanel
extends PanelContainer
## 三阶段参数面板。
## 用 ConfigSchema 反射生成滑块，分组由本文件声明。
##
## 信号发射用显式 .emit() 而不是 emit_signal("字符串")，
## 让 GDScript 静态分析器能识别信号被使用。

signal land_params_changed
signal height_params_changed
signal climate_params_changed
signal next_step_pressed
signal prev_step_pressed
signal view_mode_changed(is_map: bool)
signal map_projection_changed(projection: int)
signal map_mode_changed(mode: int)
signal wind_arrows_toggled(show: bool)
signal enter_select_pressed
signal confirm_deploy_pressed
signal cancel_select_pressed

# ---- 配置对象（外部注入）----
var land_config: LandConfig
var height_config: HeightConfig
var climate_config: ClimateConfig

# ---- 分组结构（UI 概念）----
const GROUPS := {
	"land": [
		{"title": "Land / Ocean", "open": true, "keys": [
			"land_ratio", "land_dispersion", "land_seed",
			"erosion_strength", "erosion_seed"]},
	],
	"height": [
		{"title": "Base", "open": true, "keys": [
			"land_base", "continental_rise", "continental_pow", "coast_damping"]},
		{"title": "Plateau", "open": false, "keys": [
			"plateau_height", "plateau_freq", "plateau_threshold", "plateau_seed"]},
		{"title": "Mountain", "open": false, "keys": [
			"mountain_peak", "belt_freq", "belt_threshold",
			"ridge_freq", "mountain_seed"]},
		{"title": "Hill", "open": false, "keys": [
			"hill_detail", "hill_freq"]},
		{"title": "Ocean", "open": true, "keys": [
			"ocean_depth", "ocean_freq", "ocean_seed",
			"ocean_detail", "ocean_detail_freq"]},
	],
	"climate": [
		{"title": "Time", "open": true, "keys": [
			"ticks_per_second", "day_length", "sun_tilt", "sun_season"]},
		{"title": "Temperature", "open": false, "keys": [
			"solar_absorption", "thermal_emission", "base_relaxation",
			"lapse_rate", "advection_speed", "diffusion_coeff"]},
		{"title": "Wind / Circulation", "open": false, "keys": [
			"circulation_amp", "wind_scale"]},
		{"title": "Humidity", "open": false, "keys": [
			"humidity_advection", "humidity_diffusion_atm"]},
		{"title": "Cloud / Rain", "open": false, "keys": [
			"cloud_form_rate", "cloud_decay", "cloud_threshold",
			"release_rate", "cloud_advection"]},
		{"title": "Evaporation", "open": false, "keys": [
			"evap_rate_ocean", "evap_rate_land", "latent_heat",
			"orographic_factor", "latent_heat_release",
			"sat_base", "sat_temp_factor"]},
		{"title": "Snow / Soil", "open": false, "keys": [
			"melt_rate", "runoff_ratio", "baseflow_rate"]},
		{"title": "River", "open": false, "keys": [
			"river_trigger_interval", "river_substeps", "river_flow_rate"]},
	],
}

# ---- 组件 ----
var _sliders: Dictionary = {}        # key → HSlider
var _spinboxes: Dictionary = {}      # key → SpinBox
var _value_labels: Dictionary = {}   # key → Label
var _rows: Dictionary = {}           # key → HBoxContainer

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

var _select_btn: Button
var _confirm_btn: Button
var _cancel_btn: Button
var _selected_plot_label: Label

var _current_phase: int = Phase.LAND
var _is_map: bool = false
var _dragging: bool = false

# ============================================================
#  生命周期
# ============================================================
func _ready() -> void:
	_build_style()
	_build_ui()
	show_phase(Phase.LAND)
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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			visible = not visible
			get_viewport().set_input_as_handled()

# ============================================================
#  拖拽标题
# ============================================================
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
	position.x = clampf(position.x, -size.x + 80.0, vp.x - 80.0)
	position.y = clampf(position.y, 0.0, vp.y - 40.0)

func _place_at_default_position() -> void:
	await get_tree().process_frame
	reset_size()
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	var my_size := size
	if my_size.x <= 0:
		my_size.x = 400
	if my_size.y <= 0:
		my_size.y = 700
	position = Vector2(vp.x - my_size.x - 20, 20)
	_clamp_position()

# ============================================================
#  样式
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
#  主布局
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

	_build_view_row(vbox)
	_build_projection_row(vbox)
	_build_map_mode_row(vbox)

	_land_group = VBoxContainer.new()
	_land_group.add_theme_constant_override("separation", 4)
	vbox.add_child(_land_group)

	_height_group = VBoxContainer.new()
	_height_group.add_theme_constant_override("separation", 4)
	vbox.add_child(_height_group)

	_climate_group = VBoxContainer.new()
	_climate_group.add_theme_constant_override("separation", 4)
	vbox.add_child(_climate_group)

	_build_step_buttons(vbox)

	var hint := Label.new()
	hint.text = "Tab: toggle panel  ·  drag title"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75))
	vbox.add_child(hint)

# ============================================================
#  视图行
# ============================================================
func _build_view_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = "View"
	lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(lbl)

	var btn_3d := Button.new()
	btn_3d.text = "3D"
	btn_3d.toggle_mode = true
	btn_3d.button_pressed = true
	btn_3d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_3d.focus_mode = Control.FOCUS_NONE
	row.add_child(btn_3d)

	var btn_map := Button.new()
	btn_map.text = "Map"
	btn_map.toggle_mode = true
	btn_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_map.focus_mode = Control.FOCUS_NONE
	row.add_child(btn_map)

	btn_3d.pressed.connect(func():
		btn_map.button_pressed = false
		view_mode_changed.emit(false))
	btn_map.pressed.connect(func():
		btn_3d.button_pressed = false
		view_mode_changed.emit(true))

# ============================================================
#  投影行
# ============================================================
func _build_projection_row(parent: Control) -> void:
	_projection_row = HBoxContainer.new()
	_projection_row.add_theme_constant_override("separation", 6)
	_projection_row.visible = false
	parent.add_child(_projection_row)

	var lbl := Label.new()
	lbl.text = "Projection"
	lbl.custom_minimum_size = Vector2(80, 0)
	_projection_row.add_child(lbl)

	var opt := OptionButton.new()
	opt.add_item("Rectangle", 0)
	opt.add_item("Ellipse", 1)
	opt.select(0)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.focus_mode = Control.FOCUS_NONE
	_projection_row.add_child(opt)

	opt.item_selected.connect(func(idx): map_projection_changed.emit(idx))

# ============================================================
#  地图模式行
# ============================================================
func _build_map_mode_row(parent: Control) -> void:
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 6)
	_mode_row.visible = false
	parent.add_child(_mode_row)

	var lbl := Label.new()
	lbl.text = "Map Mode"
	lbl.custom_minimum_size = Vector2(80, 0)
	_mode_row.add_child(lbl)

	_mode_opt = OptionButton.new()
	_mode_opt.add_item("Land", 0)
	_mode_opt.add_item("Height", 1)
	for entry in FieldId.all():
		_mode_opt.add_item(entry["label"], entry["shader_mode"])
	_mode_opt.select(0)
	_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_opt.focus_mode = Control.FOCUS_NONE
	_mode_row.add_child(_mode_opt)

	_mode_opt.item_selected.connect(func(idx):
		var mode: int = _mode_opt.get_item_id(idx)
		map_mode_changed.emit(mode)
		_refresh_map_rows())

	_arrow_check = CheckBox.new()
	_arrow_check.text = "Arrows"
	_arrow_check.button_pressed = false
	_arrow_check.focus_mode = Control.FOCUS_NONE
	_mode_row.add_child(_arrow_check)
	_arrow_check.toggled.connect(func(v): wind_arrows_toggled.emit(v))

# ============================================================
#  阶段按钮
# ============================================================
func _build_step_buttons(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	_prev_btn = Button.new()
	_prev_btn.text = "← Prev"
	_prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_btn.focus_mode = Control.FOCUS_NONE
	_prev_btn.pressed.connect(func(): prev_step_pressed.emit())
	row.add_child(_prev_btn)

	_next_btn = Button.new()
	_next_btn.text = "Next →"
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(func(): next_step_pressed.emit())
	row.add_child(_next_btn)

	# ---- 部署区 ----
	# CLIMATE 阶段：选择部署位置
	_select_btn = Button.new()
	_select_btn.text = "▶  选择部署位置"
	_select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_select_btn.focus_mode = Control.FOCUS_NONE
	_select_btn.visible = false
	_select_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_select_btn.pressed.connect(func(): enter_select_pressed.emit())
	parent.add_child(_select_btn)

	# SELECT 阶段：显示已选地块 + 确认/返回
	_selected_plot_label = Label.new()
	_selected_plot_label.text = "未选择地块"
	_selected_plot_label.add_theme_font_size_override("font_size", 12)
	_selected_plot_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_selected_plot_label.visible = false
	parent.add_child(_selected_plot_label)

	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 6)
	parent.add_child(sel_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "← 返回"
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(func(): cancel_select_pressed.emit())
	sel_row.add_child(_cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "✓ 确认部署"
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_confirm_btn.visible = false
	_confirm_btn.disabled = true
	_confirm_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_confirm_btn.pressed.connect(func(): confirm_deploy_pressed.emit())
	sel_row.add_child(_confirm_btn)

# ============================================================
#  从 Config 生成 UI
# ============================================================
func sync_from_config() -> void:
	_build_config_group(_land_group, land_config, "land")
	_build_config_group(_height_group, height_config, "height")
	_build_config_group(_climate_group, climate_config, "climate")

func _build_config_group(parent: Control, cfg: Resource, group_id: String) -> void:
	if cfg == null:
		return
	var on_change := _make_emit_callback(group_id)
	var specs: Dictionary = ConfigSchema.by_key(cfg)
	var group_defs: Array = GROUPS.get(group_id, [])
	for gd in group_defs:
		var body := _make_collapsible(parent, gd.title, Color.WHITE, gd.open)
		for key in gd.keys:
			if not specs.has(key):
				continue
			var spec: Dictionary = specs[key]
			if spec.is_int:
				_make_spinbox(body, cfg, spec, on_change)
			else:
				_make_slider(body, cfg, spec, on_change)

## 根据 group_id 返回显式的信号发射回调。
## 用 Callable 而非字符串 emit_signal 是为了让 GDScript 静态分析器
## 能识别信号被使用，避免 UNUSED_SIGNAL 警告。
func _make_emit_callback(group_id: String) -> Callable:
	match group_id:
		"land":
			return Callable(self, "_emit_land")
		"height":
			return Callable(self, "_emit_height")
		"climate":
			return Callable(self, "_emit_climate")
	return Callable(self, "_emit_nothing")

func _emit_land() -> void:
	land_params_changed.emit()

func _emit_height() -> void:
	height_params_changed.emit()

func _emit_climate() -> void:
	climate_params_changed.emit()

func _emit_nothing() -> void:
	pass

# ============================================================
#  可折叠组
# ============================================================
func _make_collapsible(parent: Control, title: String,
		color: Color, default_open: bool) -> VBoxContainer:
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
	header.text = ("▼  " if default_open else "▶  ") + title
	root.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.visible = default_open
	root.add_child(body)

	var state := {"open": default_open}
	header.pressed.connect(func():
		state.open = not state.open
		body.visible = state.open
		header.text = ("▼  " if state.open else "▶  ") + title)

	return body

# ============================================================
#  滑块 / SpinBox
# ============================================================
func _make_slider(parent: Control, cfg: Resource,
		spec: Dictionary, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	_rows[spec.key] = row

	var label := Label.new()
	label.text = spec.label
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = spec.min
	slider.max_value = spec.max
	slider.step = spec.step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(100, 0)
	slider.focus_mode = Control.FOCUS_NONE
	slider.set_value_no_signal(cfg.get(spec.key))
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = _format(float(cfg.get(spec.key)), spec.step >= 1.0)
	row.add_child(value_label)

	_sliders[spec.key] = slider
	_value_labels[spec.key] = value_label

	slider.value_changed.connect(func(v):
		value_label.text = _format(v, spec.step >= 1.0))
	slider.drag_ended.connect(func(_changed):
		var v := clampf(slider.value, spec.min, spec.max)
		slider.set_value_no_signal(v)
		value_label.text = _format(v, spec.step >= 1.0)
		cfg.set(spec.key, v)
		on_change.call())

func _make_spinbox(parent: Control, cfg: Resource,
		spec: Dictionary, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	_rows[spec.key] = row

	var label := Label.new()
	label.text = spec.label
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 9999999
	spin.step = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.set_value_no_signal(cfg.get(spec.key))
	row.add_child(spin)

	_spinboxes[spec.key] = spin

	var commit := func():
		cfg.set(spec.key, int(spin.value))
		on_change.call()
	var line_edit := spin.get_line_edit()
	if line_edit != null:
		line_edit.text_submitted.connect(func(_t): commit.call())
		line_edit.focus_exited.connect(func(): commit.call())

func _format(v: float, force_int: bool) -> String:
	return "%d" % int(round(v)) if force_int else "%.3f" % v

# ============================================================
#  阶段 / 视图
# ============================================================
func show_phase(phase: int) -> void:
	_current_phase = phase
	_land_group.visible = (phase == Phase.LAND)
	_height_group.visible = (phase == Phase.HEIGHT)
	_climate_group.visible = (phase == Phase.CLIMATE)

	_prev_btn.visible = (phase != Phase.LAND)
	_next_btn.visible = (phase != Phase.SELECT)

	if _select_btn != null:
		_select_btn.visible = (phase == Phase.CLIMATE)
	if _selected_plot_label != null:
		_selected_plot_label.visible = (phase == Phase.SELECT)
	if _cancel_btn != null:
		_cancel_btn.visible = (phase == Phase.SELECT)
	if _confirm_btn != null:
		_confirm_btn.visible = (phase == Phase.SELECT)

	match phase:
		Phase.LAND:
			_phase_label.text = "Step 1 / 4 · Land / Ocean"
		Phase.HEIGHT:
			_phase_label.text = "Step 2 / 4 · Height"
		Phase.CLIMATE:
			_phase_label.text = "Step 3 / 4 · Climate"
		Phase.SELECT:
			_phase_label.text = "Step 4 / 4 · Select Spawn"

	_refresh_map_rows()

func set_view_is_map(is_map: bool) -> void:
	_is_map = is_map
	_refresh_map_rows()

## 由 main 调用，更新已选地块显示。
func set_selected_plot(face_idx: int) -> void:
	if _selected_plot_label == null:
		return
	if face_idx < 0:
		_selected_plot_label.text = "未选择地块"
		if _confirm_btn != null:
			_confirm_btn.disabled = true
	else:
		_selected_plot_label.text = "已选地块 #%d" % face_idx
		if _confirm_btn != null:
			_confirm_btn.disabled = false

func _refresh_map_rows() -> void:
	if _projection_row != null:
		_projection_row.visible = _is_map
	if _mode_row != null:
		_mode_row.visible = _is_map
	if _mode_opt:
		var allow_all := (_current_phase == Phase.CLIMATE or _current_phase == Phase.SELECT)
		for i in _mode_opt.item_count:
			var item_id: int = _mode_opt.get_item_id(i)
			_mode_opt.set_item_disabled(i, item_id >= 2 and not allow_all)

func set_map_mode(mode: int) -> void:
	if _mode_opt == null:
		return
	for i in _mode_opt.item_count:
		if _mode_opt.get_item_id(i) == mode:
			_mode_opt.select(i)
			return
