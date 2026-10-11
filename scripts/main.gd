extends Node3D
## 主入口：3D 世界地图 + 2D 俯视游玩。

@export_group("Planet")
@export var initial_subdivision: int = 64
@export var initial_radius: float = 1.0

@export_group("Map")
@export var map_bake_width: int = 1024
@export var map_bake_height: int = 512
@export var map_zoom_min: float = 0.3
@export var map_zoom_max: float = 12.0

@export_group("Camera")
@export var camera_distance: float = 3.2
@export var camera_min_distance: float = 1.2
@export var camera_max_distance: float = 20.0

@export_group("Play")
@export var chunk_resolution: int = 128
@export var chunk_load_radius: int = 2
@export var player_spawn_plot: int = 0

# ---- Config ----
var land_config: LandConfig
var height_config: HeightConfig
var climate_config: ClimateConfig

# ---- 宏观数据 ----
var gp: GoldbergPolyhedron
var data: PlanetData
var land_gen: LandGenerator
var height_gen: HeightGenerator
var climate_sim: ClimateSimulator
var face_lookup: FaceLookup
var plot_geo: PlotGeometry

# ---- 3D 场景 ----
var pivot: Node3D
var orbit: CameraOrbit
var gpu_view: GpuPlanetView

# ---- UI ----
var panel: ParameterPanel
var debug_panel: DebugPanel

# ---- 3D 地图 ----
var map_baker_gpu: MapBakerGpu
var map_fields: FieldTextures
var map_layer: CanvasLayer
var map_viewer: MapView
var _view_is_map: bool = false
var _current_map_mode: int = 0
var _map_baked: bool = false

# ---- 2D 游玩 ----
var world_2d: Node2D
var chunk_manager: PlanetChunkManager
var player: PlanetPlayer
var _play_mode: bool = false

var _frame_profile: Dictionary = {
	"physics_total": 0, "3d_render": 0, "frame_total": 0,
}
func get_frame_profile() -> Dictionary:
	return _frame_profile

# ============================================================
func _ready() -> void:
	land_config = LandConfig.new()
	height_config = HeightConfig.new()
	climate_config = ClimateConfig.new()

	var win := get_window()
	win.content_scale_size = Vector2i(0, 0)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	_setup_environment()
	_setup_planet()
	_setup_camera()
	_setup_map_ui()
	_setup_ui()

	gpu_view.setup(data)
	_regenerate_land()

# ============================================================
func _process(delta: float) -> void:
	var ft0 := Time.get_ticks_usec()

	if data == null:
		return

	if _play_mode:
		_play_process(delta)
	else:
		_sim_process(delta)

	_frame_profile["frame_total"] = Time.get_ticks_usec() - ft0

func _sim_process(delta: float) -> void:
	if climate_sim != null and data.phase == PlanetData.Phase.CLIMATE:
		var p0 := Time.get_ticks_usec()
		climate_sim.update(delta)
		_frame_profile["physics_total"] = Time.get_ticks_usec() - p0

	if not _view_is_map and gpu_view.visible and data.phase == PlanetData.Phase.CLIMATE:
		gpu_view.set_sun_dir(climate_sim.get_sun_dir())
		gpu_view.update_temperature(data.f_temperature)

	if _view_is_map and map_fields != null and data.phase == PlanetData.Phase.CLIMATE:
		_update_map_fields()

func _play_process(_delta: float) -> void:
	if chunk_manager != null and player != null:
		chunk_manager.update_for_player(player.global_position)

# ============================================================
#  环境
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
#  星球 + 相机
# ============================================================
func _setup_planet() -> void:
	gp = GoldbergPolyhedron.get_or_create(initial_subdivision, initial_radius)
	data = PlanetData.new()
	data.init(gp)

	land_gen = LandGenerator.new()
	land_gen.setup(land_config)

	height_gen = HeightGenerator.new()
	height_gen.setup(height_config, land_gen)

	climate_sim = ClimateSimulator.new()

	face_lookup = FaceLookup.new()
	face_lookup.setup(gp)

	plot_geo = PlotGeometry.new()
	plot_geo.setup(gp)

	pivot = Node3D.new()
	pivot.name = "PlanetPivot"
	add_child(pivot)

	gpu_view = GpuPlanetView.new()
	gpu_view.terrain_scale = 0.20
	pivot.add_child(gpu_view)

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
#  地图 UI
# ============================================================
func _setup_map_ui() -> void:
	map_baker_gpu = MapBakerGpu.new()
	if not map_baker_gpu.setup(face_lookup):
		push_error("[main] MapBakerGpu 初始化失败")

	map_fields = FieldTextures.new()

	map_layer = CanvasLayer.new()
	map_layer.visible = false
	add_child(map_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(bg)

	map_viewer = MapView.new()
	map_viewer.min_zoom = map_zoom_min
	map_viewer.max_zoom = map_zoom_max
	map_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_layer.add_child(map_viewer)

	map_viewer.set_wind_face_lookup(face_lookup)
	map_viewer.set_wind_map_size(map_bake_width, map_bake_height)
	map_viewer.set_wind_projection(0)

# ============================================================
#  参数面板
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
	panel.climate_params_changed.connect(_on_climate_params_changed)
	panel.next_step_pressed.connect(_on_next_step)
	panel.prev_step_pressed.connect(_on_prev_step)
	panel.view_mode_changed.connect(_on_view_mode_changed)
	panel.map_projection_changed.connect(_on_map_projection_changed)
	panel.map_mode_changed.connect(_on_map_mode_changed)
	panel.wind_arrows_toggled.connect(_on_wind_arrows_toggled)

	await get_tree().process_frame
	panel.sync_from_config()

	_setup_debug_panel()

func _setup_debug_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var anchor := Control.new()
	anchor.anchor_left = 0.0
	anchor.anchor_right = 0.0
	anchor.anchor_top = 1.0
	anchor.anchor_bottom = 1.0
	anchor.offset_left = 20
	anchor.offset_right = 260
	anchor.offset_top = -220
	anchor.offset_bottom = -20
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(anchor)

	debug_panel = DebugPanel.new()
	debug_panel.climate_sim = climate_sim
	debug_panel.main = self
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	debug_panel.offset_left = 0
	debug_panel.offset_right = 220
	debug_panel.offset_top = -200
	debug_panel.offset_bottom = 0
	anchor.add_child(debug_panel)

# ============================================================
#  信号
# ============================================================
func _on_land_params_changed() -> void:
	if data.phase == PlanetData.Phase.LAND:
		_regenerate_land()

func _on_height_params_changed() -> void:
	if data.phase == PlanetData.Phase.HEIGHT:
		_regenerate_height()

func _on_climate_params_changed() -> void:
	pass

func _on_next_step() -> void:
	match data.phase:
		PlanetData.Phase.LAND:
			_current_map_mode = 1
			panel.set_map_mode(1)
			data.phase = PlanetData.Phase.HEIGHT
			panel.show_phase(data.phase)
			data.refresh_face_land_flags()
			_recompute_face_land_score()
			_regenerate_height()

			_map_baked = false
			if _view_is_map:
				_bake_map_gpu()
				map_viewer.set_mode(_current_map_mode)

		PlanetData.Phase.HEIGHT:
			_current_map_mode = 2
			panel.set_map_mode(2)
			data.phase = PlanetData.Phase.CLIMATE
			data.init_climate()
			panel.show_phase(data.phase)

			await get_tree().process_frame

			climate_sim.setup(data, climate_config)
			climate_sim.river_updated.connect(_on_river_updated)

			gpu_view.set_sun_dir(climate_sim.get_sun_dir())
			gpu_view.update_temperature(data.f_temperature)

			map_fields.setup(data.gp.face_count)
			map_viewer.set_field_textures(
				map_fields.temp_texture,
				map_fields.pressure_texture,
				map_fields.wind_texture,
				map_fields.hum_atm_texture,
				map_fields.hum_land_texture,
				map_fields.precip_texture,
				map_fields.cloud_texture,
				map_fields.snow_texture,
				map_fields.soil_texture,
				map_fields.get_field_size())
			map_viewer.set_river_texture(map_fields.river_texture)
			map_viewer.set_mode(_current_map_mode)
			_map_baked = false

			if _view_is_map:
				_bake_map_gpu()
				map_viewer.set_use_shader(true)
				map_viewer.set_mode(_current_map_mode)

func _on_prev_step() -> void:
	match data.phase:
		PlanetData.Phase.CLIMATE:
			_current_map_mode = 1
			panel.set_map_mode(1)
			if climate_sim != null and climate_sim.river_updated.is_connected(_on_river_updated):
				climate_sim.river_updated.disconnect(_on_river_updated)
			data.clear_climate()
			data.phase = PlanetData.Phase.HEIGHT
			panel.show_phase(data.phase)
			data.refresh_face_land_flags()
			_recompute_face_land_score()
			gpu_view.rebuild_mesh()
			gpu_view.update_height()
			_map_baked = false
			if _view_is_map:
				_bake_map_gpu()
				map_viewer.set_mode(_current_map_mode)

		PlanetData.Phase.HEIGHT:
			_current_map_mode = 0
			panel.set_map_mode(0)
			data.clear_height()
			data.phase = PlanetData.Phase.LAND
			panel.show_phase(data.phase)
			data.refresh_face_land_flags()
			_recompute_face_land_score()
			gpu_view.rebuild_mesh()
			gpu_view.update_land()
			_map_baked = false
			if _view_is_map:
				_bake_map_gpu()
				map_viewer.set_mode(_current_map_mode)

# ---- 河流 ----
func _on_river_updated() -> void:
	if _view_is_map and _current_map_mode == 10:
		_refresh_river_texture()

func _refresh_river_texture() -> void:
	if map_fields == null or data == null:
		return
	var flow := data.f_flow
	var max_factor := 0.001
	for v in flow:
		if v > max_factor:
			max_factor = v
	map_fields.update_river(flow, max_factor)

# ---- 视图 ----
func _on_view_mode_changed(is_map: bool) -> void:
	_view_is_map = is_map
	map_layer.visible = is_map
	panel.set_view_is_map(is_map)
	gpu_view.visible = not is_map

	if is_map:
		map_viewer.reset_view()
		if not _map_baked:
			_bake_map_gpu()
		map_viewer.set_use_shader(true)
		map_viewer.set_mode(_current_map_mode)
		if _current_map_mode == 10:
			_refresh_river_texture()

func _on_map_projection_changed(proj: int) -> void:
	map_viewer.set_wind_projection(proj)
	_map_baked = false
	if _view_is_map:
		_bake_map_gpu()

func _on_map_mode_changed(mode: int) -> void:
	_current_map_mode = mode
	map_viewer.set_mode(mode)
	if mode == 10:
		_refresh_river_texture()

func _on_wind_arrows_toggled(show_wind_arrows: bool) -> void:
	map_viewer.set_wind_arrows_visible(show_wind_arrows)

# ============================================================
#  GPU 地图烘焙
# ============================================================
func _bake_map_gpu() -> void:
	if map_baker_gpu == null:
		return
	print("[Map] GPU 烘焙开始…")
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = map_baker_gpu.bake(
		data, map_bake_width, map_bake_height, 0)
	if result.is_empty():
		push_error("[Map] GPU 烘焙失败")
		return
	map_viewer.set_baked_textures(
		result["base_texture"], result["face_texture"])
	_map_baked = true
	print("[Map] 完成，耗时 %d ms" % (Time.get_ticks_msec() - t0))

# ============================================================
#  生成
# ============================================================
func _regenerate_land() -> void:
	if panel == null or data == null:
		return
	land_gen.generate(data)
	data.refresh_face_land_flags()
	_recompute_face_land_score()

	gpu_view.rebuild_mesh()
	gpu_view.update_land()
	if _view_is_map:
		_map_baked = false
		_bake_map_gpu()

func _regenerate_height() -> void:
	if panel == null or data == null:
		return
	height_gen.invalidate()
	height_gen.generate(data)
	gpu_view.rebuild_mesh()
	gpu_view.update_height()
	if _view_is_map:
		_map_baked = false
		_bake_map_gpu()

func _recompute_face_land_score() -> void:
	var n := data.gp.face_count
	if data.f_land_score.size() != n:
		data.f_land_score.resize(n)
	for f in n:
		var dir := data.gp.face_normals[f]
		data.f_land_score[f] = land_gen.land_score_at(dir)
	if climate_sim != null and climate_sim.gpu != null:
		climate_sim.gpu.update_land_score()

func _update_map_fields() -> void:
	map_fields.update_temperature(data.f_temperature)
	map_fields.update_pressure(data.f_pressure)
	map_fields.update_wind(data.f_wind)
	map_fields.update_hum_atm(data.f_humidity_atm)
	map_fields.update_hum_land(data.f_soil_water)
	map_fields.update_precip(data.f_precipitation)
	map_fields.update_cloud(data.f_cloud)
	map_fields.update_snow(data.f_snow)
	map_fields.update_soil(data.f_soil_water)
	map_viewer.set_wind_data(data.f_wind)

# ============================================================
#  2D 游玩模式
# ============================================================
func enter_play_mode(plot_id: int = -1) -> void:
	if _play_mode:
		return
	if data.phase != PlanetData.Phase.CLIMATE:
		push_warning("[Play] 需要先进入 CLIMATE 阶段")
		return

	_play_mode = true
	_view_is_map = false
	map_layer.visible = false
	gpu_view.visible = false
	orbit.visible = false

	if plot_id < 0:
		plot_id = player_spawn_plot

	# 2D 世界根
	world_2d = Node2D.new()
	world_2d.name = "World2D"
	add_child(world_2d)

	# ChunkManager
	chunk_manager = PlanetChunkManager.new()
	chunk_manager.default_resolution = chunk_resolution
	chunk_manager.load_radius = chunk_load_radius
	chunk_manager.setup(gp, data, land_gen, height_gen, face_lookup, plot_geo, initial_radius)
	chunk_manager.set_current_plot_if_needed(plot_id)
	world_2d.add_child(chunk_manager)

	# 玩家
	player = PlanetPlayer.new()
	player.global_position = Vector2.ZERO
	world_2d.add_child(player)

	chunk_manager.update_for_player(player.global_position)

	print("[Play] plot=", plot_id, " world_2d children=", world_2d.get_child_count())

func exit_play_mode() -> void:
	if not _play_mode:
		return
	_play_mode = false
	if world_2d:
		world_2d.queue_free()
		world_2d = null
		chunk_manager = null
		player = null
	orbit.visible = true
	gpu_view.visible = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			enter_play_mode()
		elif event.keycode == KEY_F6:
			exit_play_mode()