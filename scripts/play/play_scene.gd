extends Node2D
## 游玩场景。从 GameSession 读 world，展示 2D 俯视世界。
## 自管 Camera2D（跟随玩家）。
## 按 M 切换地图，按 ESC 返回 Generator。
##
## 大世界时间在本场景持续流动 —— 每帧调用 world.update(delta)。

const GENERATOR_SCENE := "res://scenes/generator.tscn"

@export_group("Chunk")
@export var chunk_resolution: int = 128
@export var chunk_load_radius: int = 2

@export_group("Spawn")
## 出生 plot 索引。>= 0 时优先使用；否则使用 session.selected_plot。
@export var player_spawn_plot: int = -1

@export_group("Map")
@export var map_bake_width: int = 1024
@export var map_bake_height: int = 512
@export var map_default_mode: int = -1   # -1 表示用 FieldId.TEMPERATURE

@export_group("Camera")
@export var camera_zoom_min: float = 0.5
@export var camera_zoom_max: float = 8.0
@export var camera_zoom_step: float = 1.15
@export var camera_zoom_initial: float = 2.0

@export_group("Debug")
@export var debug_print: bool = false

var _session: Node
var world: PlanetWorld

# 2D 世界
var world_2d: Node2D
var chunk_manager: PlanetChunkManager
var player: PlanetPlayer
var play_camera: Camera2D

# 地图
var map_layer: CanvasLayer
var map_view: MapView
var map_field_atlas: FieldAtlas
var map_baker: MapBaker
var _map_mode: int = 2
var _map_baked: bool = false

# HUD
var hud: CanvasLayer
var hint_label: Label

# 当前 plot
var _spawn_plot: int = 0

# ============================================================
func _ready() -> void:
	_session = get_node("/root/GameSession")
	if not _session.has_world():
		push_error("[PlayScene] GameSession 无 world，返回生成器场景")
		get_tree().change_scene_to_file(GENERATOR_SCENE)
		return
	world = _session.world

	# 决定出生 plot
	_spawn_plot = _resolve_spawn_plot()

	if debug_print:
		print("[PlayScene] world ok, cell_count=", world.gp.face_count,
			" plot_count=", world.plot_map.face_count(),
			" spawn_plot=", _spawn_plot)

	_setup_background()
	_setup_camera()
	_setup_2d_world()
	_setup_map()
	_setup_hud()

	if debug_print:
		print("[PlayScene] ready done")

func _resolve_spawn_plot() -> int:
	if player_spawn_plot >= 0:
		return player_spawn_plot
	if _session.selected_plot >= 0:
		return _session.selected_plot
	return 0

# ============================================================
#  背景
# ============================================================
func _setup_background() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.name = "BackgroundLayer"
	bg_layer.layer = -10
	add_child(bg_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg)

# ============================================================
#  相机
# ============================================================
func _setup_camera() -> void:
	play_camera = Camera2D.new()
	play_camera.name = "PlayCamera"
	play_camera.zoom = Vector2(camera_zoom_initial, camera_zoom_initial)
	play_camera.enabled = true
	play_camera.position_smoothing_enabled = false
	add_child(play_camera)
	play_camera.make_current()

# ============================================================
#  2D 世界
# ============================================================
func _setup_2d_world() -> void:
	world_2d = Node2D.new()
	world_2d.name = "World2D"
	add_child(world_2d)

	chunk_manager = PlanetChunkManager.new()
	chunk_manager.default_resolution = chunk_resolution
	chunk_manager.load_radius = chunk_load_radius
	# 第一个参数用 plot 层的 gp（低精度），第五个参数用 cell 层的 face_lookup
	chunk_manager.setup(world.plot_map.gp, world.data,
		world.land_gen, world.height_gen,
		world.face_lookup, world.plot_geo, world.gp.radius)
	chunk_manager.set_current_plot_if_needed(_spawn_plot)
	world_2d.add_child(chunk_manager)

	player = PlanetPlayer.new()
	player.global_position = Vector2.ZERO
	world_2d.add_child(player)

	chunk_manager.update_for_player(player.global_position)

	if play_camera != null:
		play_camera.global_position = player.global_position

	if debug_print:
		print("[Play] spawn_plot=", _spawn_plot,
			" chunk_count=", chunk_manager.loaded_chunk_count())

# ============================================================
#  地图
# ============================================================
func _setup_map() -> void:
	map_baker = MapBaker.new()
	if not map_baker.setup(world.face_lookup.export_grid(), world.gp.face_normals):
		push_error("[PlayScene] MapBaker 初始化失败")

	map_field_atlas = FieldAtlas.new()
	map_field_atlas.setup(world.gp.face_count)

	map_layer = CanvasLayer.new()
	map_layer.name = "MapLayer"
	map_layer.visible = false
	map_layer.layer = 5
	add_child(map_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(bg)

	map_view = MapView.new()
	map_view.min_zoom = 0.3
	map_view.max_zoom = 12.0
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_layer.add_child(map_view)

	map_view.set_wind_face_lookup(world.face_lookup)
	map_view.set_wind_map_size(map_bake_width, map_bake_height)
	map_view.set_wind_projection(0)
	map_view.set_field_atlas(map_field_atlas)

	# 默认显示模式
	if map_default_mode >= 0:
		_map_mode = map_default_mode
	else:
		_map_mode = FieldId.shader_mode(FieldId.TEMPERATURE)

# ============================================================
#  HUD
# ============================================================
func _setup_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)

	hint_label = Label.new()
	hint_label.text = "WASD: move  ·  Wheel: zoom  ·  M: map  ·  ESC: back"
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_label.add_theme_constant_override("outline_size", 3)
	hint_label.position = Vector2(20, 20)
	hud.add_child(hint_label)

# ============================================================
#  输入
# ============================================================
func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return

	if event is InputEventMouseButton and not map_layer.visible:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(camera_zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0 / camera_zoom_step)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			var vp1 := get_viewport()
			if vp1 != null:
				vp1.set_input_as_handled()
			_toggle_map()
		elif event.keycode == KEY_ESCAPE:
			var vp2 := get_viewport()
			if vp2 != null:
				vp2.set_input_as_handled()
			get_tree().change_scene_to_file(GENERATOR_SCENE)

func _zoom_camera(factor: float) -> void:
	if play_camera == null:
		return
	var z := play_camera.zoom.x * factor
	z = clampf(z, camera_zoom_min, camera_zoom_max)
	play_camera.zoom = Vector2(z, z)

func _toggle_map() -> void:
	var show_map := not map_layer.visible
	map_layer.visible = show_map
	world_2d.visible = not show_map

	if show_map:
		if not _map_baked:
			_bake_map()
		map_view.set_use_shader(true)
		map_view.set_mode(_map_mode)
		_refresh_river_if_needed()
		if player != null:
			player.set_physics_process(false)
	else:
		if player != null:
			player.set_physics_process(true)

# ============================================================
#  地图烘焙与字段更新
# ============================================================
func _bake_map() -> void:
	var result := map_baker.bake(world.data, map_bake_width, map_bake_height, 0)
	if result.is_empty():
		push_error("[PlayScene] 地图烘焙失败")
		return
	map_view.set_baked_textures(result["base_texture"], result["face_texture"])
	_map_baked = true
	if debug_print:
		print("[PlayScene] map baked")

func _update_map_fields() -> void:
	var d := world.data
	if d.f_temperature.size() == 0:
		return
	map_field_atlas.upload(FieldId.TEMPERATURE, d.f_temperature)
	map_field_atlas.upload(FieldId.PRESSURE, d.f_pressure)
	map_field_atlas.upload_wind(d.f_wind)
	map_field_atlas.upload(FieldId.HUM_ATM, d.f_humidity_atm)
	map_field_atlas.upload(FieldId.PRECIP, d.f_precipitation)
	map_field_atlas.upload(FieldId.CLOUD, d.f_cloud)
	map_field_atlas.upload(FieldId.SNOW, d.f_snow)
	map_field_atlas.upload(FieldId.SOIL, d.f_soil_water)
	map_view.set_wind_data(d.f_wind)

func _refresh_river_if_needed() -> void:
	if _map_mode != FieldId.shader_mode(FieldId.RIVER):
		return
	var flow := world.data.f_flow
	var max_factor := 0.001
	for v in flow:
		if v > max_factor:
			max_factor = v
	map_field_atlas.update_river(flow, max_factor)

# ============================================================
#  每帧
# ============================================================
func _process(delta: float) -> void:
	# 大世界时间持续流动
	world.update(delta)

	# 相机跟随玩家（非地图视图时）
	if play_camera != null and player != null and not map_layer.visible:
		play_camera.global_position = player.global_position

	# 地图打开时同步字段
	if map_layer.visible:
		_update_map_fields()

# ============================================================
#  清理
# ============================================================
func _exit_tree() -> void:
	if map_baker != null:
		map_baker.dispose()
		map_baker = null
	# world 由 GameSession 持有，不清理
