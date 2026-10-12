extends Node3D
## 生成器场景：三阶段参数 + 3D 预览 + Map 预览。
## CLIMATE 之后进入 SELECT 阶段选择部署地块，再进入 Play 场景。

@export_group("Planet")
@export var initial_subdivision: int = 64
@export var initial_radius: float = 1.0
@export var plot_subdivision: int = 8

@export_group("Map")
@export var map_bake_width: int = 1024
@export var map_bake_height: int = 512
@export var map_zoom_min: float = 0.3
@export var map_zoom_max: float = 12.0

@export_group("Camera")
@export var camera_distance: float = 3.2
@export var camera_min_distance: float = 1.2
@export var camera_max_distance: float = 20.0

const PLAY_SCENE := "res://scenes/play.tscn"

# ---- Config ----
var land_config: LandConfig
var height_config: HeightConfig
var climate_config: ClimateConfig

# ---- 会话 ----
var session: Node

# ---- 子系统 ----
var world: PlanetWorld
var phase_ctrl: PhaseController
var view_router: ViewRouter

# ---- 场景节点 ----
var pivot: Node3D
var orbit: CameraOrbit
var gpu_view: PlanetView3D
var map_baker: MapBaker
var map_field_atlas: FieldAtlas
var map_layer: CanvasLayer
var map_viewer: MapView

# ---- UI ----
var panel: ParameterPanel
var debug_panel: DebugPanel

# ---- 地块选择 ----
var _hover_highlight: MeshInstance3D
var _selected_highlight: MeshInstance3D
var _hovered_plot: int = -1
var _selected_plot: int = -1
var _3d_layer: int = PlanetView3D.MODE_TEMPERATURE

var _frame_profile: Dictionary = {
	"physics_total": 0, "3d_render": 0, "frame_total": 0,
}

# ============================================================
func _ready() -> void:
	session = get_node("/root/GameSession")
	world = session.ensure_world(
		initial_subdivision, initial_radius, plot_subdivision)
	land_config = session.land_config
	height_config = session.height_config
	climate_config = session.climate_config

	var win := get_window()
	win.content_scale_size = Vector2i(0, 0)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	_setup_environment()
	_setup_world()
	_setup_planet_view()
	_setup_camera()
	_setup_highlight()
	_setup_map()
	_setup_ui()

	_restore_phase_view()

# ============================================================
func _restore_phase_view() -> void:
	match phase_ctrl.current_phase:
		Phase.CLIMATE, Phase.SELECT:
			if world.climate == null:
				world.start_climate()
			phase_ctrl.current_phase = Phase.CLIMATE
			panel.show_phase(Phase.CLIMATE)
			gpu_view.rebuild_mesh()
			gpu_view.set_sun_dir(world.get_sun_dir())
			_3d_layer = PlanetView3D.MODE_TEMPERATURE
			_update_3d_field()
			view_router.set_map_mode(FieldId.shader_mode(FieldId.TEMPERATURE))
			view_router.invalidate_map()
		Phase.HEIGHT:
			panel.show_phase(Phase.HEIGHT)
			gpu_view.rebuild_mesh()
			gpu_view.update_height()
			view_router.set_map_mode(1)
			view_router.invalidate_map()
		_:
			world.generate_land()
			panel.show_phase(Phase.LAND)
			view_router.set_map_mode(0)
			view_router.invalidate_map()

	if view_router.is_map:
		view_router.bake_map()

# ============================================================
func _process(delta: float) -> void:
	var ft0 := Time.get_ticks_usec()
	if world == null:
		return
	_sim_process(delta)
	_update_hover_highlight()
	_frame_profile["frame_total"] = Time.get_ticks_usec() - ft0

func _sim_process(delta: float) -> void:
	var p := phase_ctrl.current_phase
	if p == Phase.CLIMATE:
		var p0 := Time.get_ticks_usec()
		world.update(delta)
		_frame_profile["physics_total"] = Time.get_ticks_usec() - p0

		if not view_router.is_map and gpu_view.visible:
			gpu_view.set_sun_dir(world.get_sun_dir())
			_update_3d_field()
		elif view_router.is_map:
			map_viewer.set_sun_dir(world.get_sun_dir())
			view_router.update_map_fields()
	elif p == Phase.SELECT:
		if view_router.is_map:
			map_viewer.set_sun_dir(world.get_sun_dir())
			view_router.update_map_fields()

# ============================================================
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.55, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.90, 1.0)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# ============================================================
func _setup_world() -> void:
	phase_ctrl = PhaseController.new()
	phase_ctrl.infer_from_world(world)

	if not world.land_regenerated.is_connected(_on_land_regenerated):
		world.land_regenerated.connect(_on_land_regenerated)
	if not world.height_regenerated.is_connected(_on_height_regenerated):
		world.height_regenerated.connect(_on_height_regenerated)
	if not world.climate_started.is_connected(_on_climate_started):
		world.climate_started.connect(_on_climate_started)
	if not world.climate_stopped.is_connected(_on_climate_stopped):
		world.climate_stopped.connect(_on_climate_stopped)
	if not world.climate_ticked.is_connected(_on_climate_ticked):
		world.climate_ticked.connect(_on_climate_ticked)
	if not phase_ctrl.phase_changed.is_connected(_on_phase_changed):
		phase_ctrl.phase_changed.connect(_on_phase_changed)

func _setup_planet_view() -> void:
	pivot = Node3D.new()
	pivot.name = "PlanetPivot"
	add_child(pivot)

	gpu_view = PlanetView3D.new()
	gpu_view.terrain_scale = 0.20
	pivot.add_child(gpu_view)
	gpu_view.setup(world.data)

func _setup_camera() -> void:
	orbit = CameraOrbit.new()
	orbit.distance = camera_distance
	orbit.min_distance = camera_min_distance
	orbit.max_distance = camera_max_distance
	add_child(orbit)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.0
	light.light_color = Color(1.0, 0.96, 0.90)
	add_child(light)

# ============================================================
#  地块高亮：悬停 + 选中
# ============================================================
func _setup_highlight() -> void:
	_hover_highlight = MeshInstance3D.new()
	_hover_highlight.name = "HoverHighlight"
	_hover_highlight.visible = false
	var hover_mat := StandardMaterial3D.new()
	hover_mat.albedo_color = Color(0.55, 0.90, 1.0, 0.30)
	hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hover_highlight.material_override = hover_mat
	pivot.add_child(_hover_highlight)

	_selected_highlight = MeshInstance3D.new()
	_selected_highlight.name = "SelectedHighlight"
	_selected_highlight.visible = false
	var sel_mat := StandardMaterial3D.new()
	sel_mat.albedo_color = Color(1.0, 0.85, 0.2, 1.0)
	sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_selected_highlight.material_override = sel_mat
	pivot.add_child(_selected_highlight)

func _show_hover_highlight(plot_idx: int) -> void:
	if plot_idx < 0 or plot_idx >= world.plot_map.face_count() \
			or plot_idx == _selected_plot:
		_hover_highlight.visible = false
		return
	_hover_highlight.mesh = _build_face_fill(world.plot_map.gp, plot_idx, 1.12)
	_hover_highlight.visible = true

func _show_selected_highlight(plot_idx: int) -> void:
	if plot_idx < 0 or plot_idx >= world.plot_map.face_count():
		_selected_highlight.visible = false
		return
	_selected_highlight.mesh = _build_face_outline(world.plot_map.gp, plot_idx, 1.15)
	_selected_highlight.visible = true

func _build_face_fill(gp: GoldbergPolyhedron, f: int, lift: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var start := gp.face_vertex_offsets[f]
	var end := gp.face_vertex_offsets[f + 1]
	var n := end - start
	if n < 3:
		return ArrayMesh.new()
	var base := verts.size()
	verts.append(gp.face_centers[f] * lift)
	for i in n:
		var vi := gp.face_vertex_indices[start + i]
		verts.append(gp.vertex_positions[vi] * lift)
	for i in n:
		indices.append(base)
		indices.append(base + 1 + i)
		indices.append(base + 1 + ((i + 1) % n))
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_face_outline(gp: GoldbergPolyhedron, f: int, lift: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var start := gp.face_vertex_offsets[f]
	var end := gp.face_vertex_offsets[f + 1]
	var n := end - start
	if n < 3:
		return ArrayMesh.new()
	for i in n:
		var vi_a := gp.face_vertex_indices[start + i]
		var vi_b := gp.face_vertex_indices[start + ((i + 1) % n)]
		var va := gp.vertex_positions[vi_a] * lift
		var vb := gp.vertex_positions[vi_b] * lift
		indices.append(verts.size())
		verts.append(va)
		indices.append(verts.size())
		verts.append(vb)
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh

# ---- 悬停追踪（每帧）----
func _update_hover_highlight() -> void:
	if phase_ctrl.current_phase != Phase.SELECT:
		if _hover_highlight.visible:
			_hover_highlight.visible = false
			_hovered_plot = -1
		return
	if view_router.is_map:
		if _hover_highlight.visible:
			_hover_highlight.visible = false
			_hovered_plot = -1
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var plot_idx := _pick_plot(mouse_pos)
	if plot_idx == _hovered_plot:
		return
	_hovered_plot = plot_idx
	_show_hover_highlight(plot_idx)

func _pick_plot(mouse_pos: Vector2) -> int:
	var cam := orbit.get_camera()
	if cam == null:
		return -1
	var origin := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var r := world.plot_map.gp.radius
	var b := origin.dot(dir)
	var c := origin.dot(origin) - r * r
	var disc := b * b - c
	if disc < 0.0:
		return -1
	var t := -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)
	if t < 0.0:
		return -1
	var hit := origin + dir * t
	if hit.normalized().dot(origin) < 0.0:
		return -1
	return world.plot_map.face_at(hit.normalized())

# ============================================================
#  地图
# ============================================================
func _setup_map() -> void:
	map_baker = MapBaker.new()
	if not map_baker.setup(world.face_lookup.export_grid(), world.gp.face_normals):
		push_error("[main] MapBaker 初始化失败")

	map_field_atlas = FieldAtlas.new()
	map_field_atlas.setup(world.gp.face_count)

	map_layer = CanvasLayer.new()
	map_layer.visible = false
	add_child(map_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(bg)

	map_viewer = MapView.new()
	map_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_layer.add_child(map_viewer)

	view_router = ViewRouter.new()
	view_router.setup(world, gpu_view, map_layer, map_viewer, map_baker, map_field_atlas)
	view_router.map_bake_width = map_bake_width
	view_router.map_bake_height = map_bake_height
	view_router.map_zoom_min = map_zoom_min
	view_router.map_zoom_max = map_zoom_max
	view_router.view_mode_changed.connect(_on_router_view_mode_changed)
	view_router.map_mode_changed.connect(_on_router_map_mode_changed)

	map_viewer.set_field_atlas(map_field_atlas)
	map_viewer.set_plot_gp(world.plot_map.gp)
	map_viewer.map_clicked.connect(_on_map_clicked)
	map_viewer.map_hovered.connect(_on_map_hovered)

# ============================================================
#  UI
# ============================================================
func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	panel = ParameterPanel.new()
	panel.land_config = land_config
	panel.height_config = height_config
	panel.climate_config = climate_config
	layer.add_child(panel)

	panel.land_params_changed.connect(_on_land_params_changed)
	panel.height_params_changed.connect(_on_height_params_changed)
	panel.next_step_pressed.connect(_on_next_step)
	panel.prev_step_pressed.connect(_on_prev_step)
	panel.view_mode_changed.connect(_on_panel_view_mode_changed)
	panel.map_projection_changed.connect(_on_map_projection_changed)
	panel.map_mode_changed.connect(_on_panel_map_mode_changed)
	panel.wind_arrows_toggled.connect(_on_wind_arrows_toggled)
	panel.terminator_toggled.connect(_on_terminator_toggled)
	panel.layer_3d_changed.connect(_on_layer_3d_changed)
	panel.confirm_deploy_pressed.connect(_on_confirm_deploy_pressed)
	panel.cancel_select_pressed.connect(_on_cancel_select_pressed)

	await get_tree().process_frame
	panel.sync_from_config()

	_setup_debug_panel(layer)

func _setup_debug_panel(_parent_layer: CanvasLayer) -> void:
	var dlayer := CanvasLayer.new()
	dlayer.layer = 10
	add_child(dlayer)

	debug_panel = DebugPanel.new()
	debug_panel.profile_provider = Callable(self, "get_frame_profile")
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	debug_panel.offset_left = 20
	debug_panel.offset_right = 260
	debug_panel.offset_top = -220
	debug_panel.offset_bottom = -20
	dlayer.add_child(debug_panel)

func get_frame_profile() -> Dictionary:
	var merged := {}
	for k in _frame_profile:
		merged[k] = _frame_profile[k]
	if world != null and world.climate != null:
		for k in world.climate.profile:
			merged[k] = world.climate.profile[k]
		var climate := world.climate
		var tpy := maxi(1, climate.config.ticks_per_year)
		var year_angle := float(climate.tick_count % tpy) / float(tpy) * TAU
		var season := fposmod(year_angle / TAU + climate.config.initial_season, 1.0)
		merged["season"] = season
		var tpd := maxi(1, climate.config.ticks_per_day)
		merged["days_per_year"] = float(tpy) / float(tpd)
		merged["day"] = float(climate.tick_count % tpd) / float(tpd)
	return merged

# ============================================================
#  输入
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if phase_ctrl.current_phase != Phase.SELECT:
		return
	if view_router.is_map:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var plot_idx := _pick_plot(event.position)
		if plot_idx >= 0:
			_select_plot(plot_idx)

func _on_map_clicked(u: float, v: float) -> void:
	if phase_ctrl.current_phase != Phase.SELECT:
		return
	var proj := map_viewer.get_projection()
	var dir := MapProjection.uv_to_dir(u, v, proj)
	if dir == Vector3.ZERO:
		return
	var plot_idx := world.plot_map.face_at(dir)
	if plot_idx >= 0:
		_select_plot(plot_idx)

func _on_map_hovered(u: float, v: float) -> void:
	if phase_ctrl.current_phase != Phase.SELECT:
		map_viewer.set_hover_plot(-1)
		return
	if u < 0.0 or v < 0.0:
		map_viewer.set_hover_plot(-1)
		return
	var proj := map_viewer.get_projection()
	var dir := MapProjection.uv_to_dir(u, v, proj)
	if dir == Vector3.ZERO:
		map_viewer.set_hover_plot(-1)
		return
	var plot_idx := world.plot_map.face_at(dir)
	map_viewer.set_hover_plot(plot_idx)

func _select_plot(plot_idx: int) -> void:
	_selected_plot = plot_idx
	_hovered_plot = -1
	_show_selected_highlight(plot_idx)
	_show_hover_highlight(-1)
	map_viewer.set_selected_plot(plot_idx)
	map_viewer.set_hover_plot(-1)
	panel.set_selected_plot(plot_idx)
	# 相机聚焦到选中地块
	_focus_camera_on_plot(plot_idx)

func _focus_camera_on_plot(plot_idx: int) -> void:
	if plot_idx < 0 or plot_idx >= world.plot_map.face_count():
		return
	if view_router.is_map:
		return   # Map 视图下不动 3D 相机
	var dir := world.plot_map.gp.face_normals[plot_idx]
	orbit.focus_on_dir(dir)

# ============================================================
#  信号处理
# ============================================================
func _on_land_params_changed() -> void:
	if phase_ctrl.current_phase == Phase.LAND:
		world.generate_land()

func _on_height_params_changed() -> void:
	if phase_ctrl.current_phase == Phase.HEIGHT:
		world.generate_height()

func _on_next_step() -> void:
	phase_ctrl.next()

func _on_prev_step() -> void:
	phase_ctrl.prev()

func _on_phase_changed(new_phase: int) -> void:
	panel.show_phase(new_phase)
	match new_phase:
		Phase.LAND:
			gpu_view.rebuild_mesh()
			gpu_view.update_land()
			view_router.set_map_mode(0)
			view_router.invalidate_map()
		Phase.HEIGHT:
			gpu_view.rebuild_mesh()
			gpu_view.update_height()
			view_router.set_map_mode(1)
			view_router.invalidate_map()
		Phase.CLIMATE:
			gpu_view.set_sun_dir(world.get_sun_dir())
			_3d_layer = PlanetView3D.MODE_TEMPERATURE
			_update_3d_field()
			view_router.set_map_mode(FieldId.shader_mode(FieldId.TEMPERATURE))
			view_router.invalidate_map()
		Phase.SELECT:
			# SELECT 阶段显示高程
			gpu_view.update_height()
			view_router.set_map_mode(1)
			view_router.invalidate_map()
			# 清空上次选择
			_selected_plot = -1
			_hovered_plot = -1
			_show_selected_highlight(-1)
			_show_hover_highlight(-1)
			map_viewer.clear_highlights()
			panel.set_selected_plot(-1)
	if view_router.is_map:
		view_router.bake_map()

func _on_land_regenerated() -> void:
	gpu_view.rebuild_mesh()
	gpu_view.update_land()
	view_router.invalidate_map()
	if view_router.is_map:
		view_router.bake_map()

func _on_height_regenerated() -> void:
	gpu_view.rebuild_mesh()
	gpu_view.update_height()
	view_router.invalidate_map()
	if view_router.is_map:
		view_router.bake_map()

func _on_climate_started() -> void:
	map_viewer.set_use_shader(true)
	map_viewer.set_mode(view_router.map_mode)

func _on_climate_stopped() -> void:
	view_router.invalidate_map()

func _on_climate_ticked(_tick: int) -> void:
	if view_router.is_map and view_router.map_mode == FieldId.shader_mode(FieldId.RIVER):
		view_router.refresh_river_texture()

# ---- 视图 ----
func _on_panel_view_mode_changed(is_map: bool) -> void:
	if is_map:
		view_router.switch_to_map()
	else:
		view_router.switch_to_3d()
		_update_3d_field()
	if not is_map:
		_hovered_plot = -1
		_show_hover_highlight(-1)
	else:
		_hover_highlight.visible = false

func _on_panel_map_mode_changed(mode: int) -> void:
	view_router.set_map_mode(mode)
	if mode == FieldId.shader_mode(FieldId.RIVER):
		view_router.refresh_river_texture()

func _on_router_view_mode_changed(is_map: bool) -> void:
	panel.set_view_is_map(is_map)

func _on_router_map_mode_changed(mode: int) -> void:
	panel.set_map_mode(mode)

func _on_map_projection_changed(proj: int) -> void:
	view_router.set_projection(proj)
	# 投影变化后高亮重绘（由 MapView.set_wind_projection 内部触发）

func _on_wind_arrows_toggled(show_wind: bool) -> void:
	map_viewer.set_wind_arrows_visible(show_wind)

func _on_terminator_toggled(show_terminator: bool) -> void:
	map_viewer.set_terminator_visible(show_terminator)

# ---- 3D 层 ----
func _update_3d_field() -> void:
	if gpu_view == null or not gpu_view.visible:
		return
	if phase_ctrl.current_phase != Phase.CLIMATE:
		return
	match _3d_layer:
		PlanetView3D.MODE_TEMPERATURE:
			gpu_view.update_field(world.data.f_temperature, _3d_layer)
		PlanetView3D.MODE_PRECIP:
			gpu_view.update_field(world.data.f_precipitation, _3d_layer)
		PlanetView3D.MODE_CLOUD:
			gpu_view.update_field(world.data.f_cloud, _3d_layer)
		PlanetView3D.MODE_SNOW:
			gpu_view.update_field(world.data.f_snow, _3d_layer)
		PlanetView3D.MODE_HUM_ATM:
			gpu_view.update_field(world.data.f_humidity_atm, _3d_layer)
		PlanetView3D.MODE_VEG_TYPE:
			if world.data.f_potential_veg.size() == world.data.f_temperature.size():
				gpu_view.update_field(world.data.f_potential_veg, _3d_layer)
		PlanetView3D.MODE_VEG_DENSITY:
			if world.data.f_veg_density.size() == world.data.f_temperature.size():
				gpu_view.update_field(world.data.f_veg_density, _3d_layer)
		PlanetView3D.MODE_TEMP_EMA:
			if world.data.f_temp_ema.size() == world.data.f_temperature.size():
				gpu_view.update_field(world.data.f_temp_ema, _3d_layer)
		_:
			gpu_view.update_field(world.data.f_temperature,
				PlanetView3D.MODE_TEMPERATURE)

func _on_layer_3d_changed(mode: int) -> void:
	_3d_layer = mode
	_update_3d_field()

# ---- 选择部署 ----
func _on_confirm_deploy_pressed() -> void:
	if _selected_plot < 0:
		return
	session.selected_plot = _selected_plot
	get_tree().change_scene_to_file(PLAY_SCENE)

func _on_cancel_select_pressed() -> void:
	_selected_plot = -1
	_hovered_plot = -1
	_show_selected_highlight(-1)
	_show_hover_highlight(-1)
	map_viewer.clear_highlights()
	panel.set_selected_plot(-1)
	phase_ctrl.prev()

# ============================================================
#  退出清理
# ============================================================
func _exit_tree() -> void:
	if map_baker != null:
		map_baker.dispose()
		map_baker = null