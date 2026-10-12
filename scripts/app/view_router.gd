class_name ViewRouter
extends RefCounted
## 3D / Map / Play 三种视图的切换。
## 不创建 PlanetChunkManager（由 main 创建注入）。
## 只管可见性、bake、地图模式。

signal view_mode_changed(is_map: bool)
signal map_mode_changed(mode: int)

var gpu_view: PlanetView3D
var map_layer: CanvasLayer
var map_view: MapView
var map_baker: MapBaker
var map_field_atlas: FieldAtlas
var world: PlanetWorld

var map_bake_width: int = 1024
var map_bake_height: int = 512
var map_zoom_min: float = 0.3
var map_zoom_max: float = 12.0

var is_map: bool = false
var map_mode: int = 0
var _map_baked: bool = false

# ============================================================
func setup(w: PlanetWorld, view: PlanetView3D,
		layer: CanvasLayer, viewer: MapView,
		baker: MapBaker, atlas: FieldAtlas) -> void:
	world = w
	gpu_view = view
	map_layer = layer
	map_view = viewer
	map_baker = baker
	map_field_atlas = atlas

	map_view.min_zoom = map_zoom_min
	map_view.max_zoom = map_zoom_max
	map_view.set_wind_face_lookup(w.face_lookup)
	map_view.set_wind_map_size(map_bake_width, map_bake_height)
	map_view.set_wind_projection(0)

# ============================================================
func switch_to_3d() -> void:
	is_map = false
	map_layer.visible = false
	gpu_view.visible = true
	view_mode_changed.emit(false)

func switch_to_map() -> void:
	is_map = true
	map_layer.visible = true
	gpu_view.visible = false
	map_view.reset_view()
	if not _map_baked:
		bake_map()
	map_view.set_use_shader(true)
	map_view.set_mode(map_mode)
	view_mode_changed.emit(true)

func set_map_mode(mode: int) -> void:
	map_mode = mode
	if is_map and map_view != null:
		map_view.set_mode(mode)
	map_mode_changed.emit(mode)

func set_projection(proj: int) -> void:
	if map_view == null:
		return
	map_view.set_wind_projection(proj)
	_map_baked = false
	if is_map:
		bake_map()

func refresh_river_texture() -> void:
	if map_field_atlas == null or world == null:
		return
	var flow := world.data.f_flow
	var max_factor := 0.001
	for v in flow:
		if v > max_factor:
			max_factor = v
	map_field_atlas.update_river(flow, max_factor)

# ============================================================
#  地图烘焙
# ============================================================
func invalidate_map() -> void:
	_map_baked = false

func bake_map() -> void:
	if map_baker == null or world == null:
		return
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = map_baker.bake(
		world.data, map_bake_width, map_bake_height, 0)
	if result.is_empty():
		push_error("[ViewRouter] GPU 烘焙失败")
		return
	map_view.set_baked_textures(
		result["base_texture"], result["face_texture"])
	_map_baked = true
	print("[Map] 完成，耗时 %d ms" % (Time.get_ticks_msec() - t0))

# ============================================================
#  每帧地图字段更新
# ============================================================
func update_map_fields() -> void:
	if map_field_atlas == null or world == null:
		return
	var d := world.data
	map_field_atlas.upload(FieldId.TEMPERATURE, d.f_temperature)
	map_field_atlas.upload(FieldId.PRESSURE, d.f_pressure)
	map_field_atlas.upload_wind(d.f_wind)
	map_field_atlas.upload(FieldId.HUM_ATM, d.f_humidity_atm)
	map_field_atlas.upload(FieldId.PRECIP, d.f_precipitation)
	map_field_atlas.upload(FieldId.CLOUD, d.f_cloud)
	map_field_atlas.upload(FieldId.SNOW, d.f_snow)
	map_field_atlas.upload(FieldId.SOIL, d.f_soil_water)
	if d.f_potential_veg.size() == d.f_temperature.size():
		map_field_atlas.upload(FieldId.VEG_TYPE, d.f_potential_veg)
	if d.f_veg_density.size() == d.f_temperature.size():
		map_field_atlas.upload(FieldId.VEG_DENSITY, d.f_veg_density)
	if d.f_temp_ema.size() == d.f_temperature.size():
		map_field_atlas.upload(FieldId.TEMP_EMA, d.f_temp_ema)
	map_view.set_wind_data(d.f_wind)

func is_map_baked() -> bool:
	return _map_baked