class_name PlanetChunkManager
extends Node2D
## 2D 俯视区块管理器。基于玩家 2D 世界坐标加载/卸载区块。

const CHUNKS_PER_PLOT := 8

@export var default_resolution: int = 128
@export var load_radius: int = 2

# 依赖
var gp: GoldbergPolyhedron
var data: PlanetData
var land_gen: LandGenerator
var height_gen: HeightGenerator
var face_lookup: FaceLookup
var plot_geo: PlotGeometry
var planet_radius: float = 1.0

# 当前地块
var current_plot: int = -1

# 运行时
var chunks: Dictionary = {}         # Vector2i(ci, cj) → PlanetChunk
var chunk_views: Dictionary = {}    # Vector2i(ci, cj) → Sprite2D
var _texture_builder: ChunkTextureBuilder
var _last_center: Vector2i = Vector2i(-1, -1)

# ============================================================
func setup(poly: GoldbergPolyhedron, d: PlanetData,
		lg: LandGenerator, hg: HeightGenerator,
		lookup: FaceLookup, geo: PlotGeometry, radius: float) -> void:
	gp = poly
	data = d
	land_gen = lg
	height_gen = hg
	face_lookup = lookup
	plot_geo = geo
	planet_radius = radius
	_texture_builder = ChunkTextureBuilder.new()

## 切换当前地块
func set_plot(plot_id: int) -> void:
	if plot_id == current_plot:
		return
	_clear_all()
	current_plot = plot_id
	_last_center = Vector2i(-1, -1)

# ============================================================
#  每帧调用
# ============================================================

func update_for_player(player_pos: Vector2) -> void:
	if current_plot < 0 or plot_geo == null:
		return

	var uv := plot_geo.world_to_uv(current_plot, player_pos)
	var ci := clampi(int(uv.x * float(CHUNKS_PER_PLOT)), 0, CHUNKS_PER_PLOT - 1)
	var cj := clampi(int(uv.y * float(CHUNKS_PER_PLOT)), 0, CHUNKS_PER_PLOT - 1)
	var center := Vector2i(ci, cj)

	if center == _last_center:
		return
	_last_center = center

	var needed: Dictionary = {}
	for di in range(-load_radius, load_radius + 1):
		for dj in range(-load_radius, load_radius + 1):
			var nci := ci + di
			var ncj := cj + dj
			if nci < 0 or nci >= CHUNKS_PER_PLOT: continue
			if ncj < 0 or ncj >= CHUNKS_PER_PLOT: continue
			needed[Vector2i(nci, ncj)] = true

	# 卸载
	var to_remove: Array = []
	for key in chunks.keys():
		if not needed.has(key):
			to_remove.append(key)
	for key in to_remove:
		_unload_chunk(key)

	# 加载
	for key in needed:
		if not chunks.has(key):
			_load_chunk(key)

# ============================================================
#  加载 / 卸载
# ============================================================

func _load_chunk(key: Vector2i) -> void:
	var chunk := PlanetChunk.new()
	chunk.init(current_plot, key.x, key.y, default_resolution)

	# 世界坐标
	var cu := (float(key.x) + 0.5) / float(CHUNKS_PER_PLOT)
	var cv := (float(key.y) + 0.5) / float(CHUNKS_PER_PLOT)
	chunk.world_center = plot_geo.uv_to_world(current_plot, cu, cv)
	chunk.world_size = PlotGeometry.PLOT_WORLD_SIZE / float(CHUNKS_PER_PLOT)

	_sample_chunk(chunk)
	chunks[key] = chunk

	# Sprite2D
	var tex := _texture_builder.build(chunk)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.position = chunk.world_center
	sprite.name = "Chunk_%d_%d" % [key.x, key.y]
	# 纹理像素 → 世界单位缩放
	var tex_res := float(chunk.resolution)
	var scale_factor := chunk.world_size / tex_res
	sprite.scale = Vector2(scale_factor, scale_factor)
	add_child(sprite)
	chunk_views[key] = sprite

	print("[Chunk] key=", key, " world_center=", chunk.world_center,
		" tex_size=", tex.get_width(), "x", tex.get_height())

func _unload_chunk(key: Vector2i) -> void:
	if chunk_views.has(key):
		var s: Sprite2D = chunk_views[key]
		s.queue_free()
		chunk_views.erase(key)
	chunks.erase(key)

func _clear_all() -> void:
	for key in chunk_views.keys():
		var s: Sprite2D = chunk_views[key]
		s.queue_free()
	chunk_views.clear()
	chunks.clear()

# ============================================================
#  采样一个区块
# ============================================================

func _sample_chunk(chunk: PlanetChunk) -> void:
	if land_gen == null or height_gen == null:
		return

	var res := chunk.resolution
	var per_plot := float(CHUNKS_PER_PLOT)

	# 气候数据从 GP 面取——地块中心的 face
	var center_u := (float(chunk.ci) + 0.5) / per_plot
	var center_v := (float(chunk.cj) + 0.5) / per_plot
	var center_dir := plot_geo.uv_to_dir(chunk.plot_id, center_u, center_v)
	var climate_face := face_lookup.find(center_dir)
	if climate_face < 0:
		climate_face = chunk.plot_id

	var global_temp := 0.5
	var global_hum := 0.5
	if climate_face < data.f_temperature.size():
		global_temp = data.f_temperature[climate_face]
	if climate_face < data.f_humidity_atm.size():
		global_hum = data.f_humidity_atm[climate_face]

	for py in range(-1, res + 1):
		for px in range(-1, res + 1):
			var u := (float(chunk.ci) * float(res) + float(px)) / (per_plot * float(res))
			var v := (float(chunk.cj) * float(res) + float(py)) / (per_plot * float(res))
			var dir := plot_geo.uv_to_dir(chunk.plot_id, u, v)

			var is_land := land_gen.sample_is_land(dir)
			var land_score := land_gen.land_score_at(dir)
			var h := height_gen.sample_height(dir, is_land, land_score)

			var idx := chunk.local_index(px, py)
			chunk.heights[idx] = h
			chunk.land_scores[idx] = land_score
			chunk.is_lands[idx] = 1 if is_land else 0
			chunk.temperatures[idx] = global_temp
			chunk.humidities[idx] = global_hum
			chunk.materials[idx] = _derive_material(h, is_land, global_temp, global_hum)

func _derive_material(h: float, is_land: bool, t: float, hum: float) -> int:
	if not is_land:
		return ChunkTextureBuilder.MAT_WATER
	if h < 0.02:
		return ChunkTextureBuilder.MAT_SAND
	if h > 0.50:
		return ChunkTextureBuilder.MAT_SNOW
	if t < 0.20:
		return ChunkTextureBuilder.MAT_TUNDRA
	if hum < 0.25:
		return ChunkTextureBuilder.MAT_DESERT
	if hum > 0.75:
		return ChunkTextureBuilder.MAT_SWAMP
	if hum > 0.55:
		return ChunkTextureBuilder.MAT_FOREST
	if h > 0.30:
		return ChunkTextureBuilder.MAT_ROCK
	return ChunkTextureBuilder.MAT_GRASS

# ============================================================
func loaded_chunk_count() -> int:
	return chunks.size()

func set_current_plot_if_needed(plot_id: int) -> void:
	if current_plot == plot_id:
		return
	_clear_all()
	current_plot = plot_id
	_last_center = Vector2i(-1, -1)