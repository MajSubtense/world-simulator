class_name PlanetChunkManager
extends Node2D
## 2D 俯视区块管理器。基于玩家 2D 世界坐标加载/卸载区块。
##
## 渲染：每个 chunk 是 MeshInstance2D + ArrayMesh（规则网格三角化）。
##
## LOD：根据 chunk 到玩家所在 chunk 的切比雪夫距离切换分辨率。
##   dist 0~1 → default_resolution
##   dist 2~3 → default_resolution / 2
##   dist 4+  → max(16, default_resolution / 4)
##
## 依赖关系：
##   gp / data / land_gen / height_gen / face_lookup / plot_geo 由 main 注入。

const CHUNKS_PER_PLOT := 16
const SHADER_PATH := "res://scripts/rendering/chunk_2d.gdshader"

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
var chunks: Dictionary = {}         # Vector2i → PlanetChunk
var chunk_views: Dictionary = {}    # Vector2i → MeshInstance2D
var _mesh_builder: ChunkMeshBuilder
var _chunk_shader: Shader
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
	_mesh_builder = ChunkMeshBuilder.new()
	_chunk_shader = load(SHADER_PATH)

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
			if nci < 0 or nci >= CHUNKS_PER_PLOT:
				continue
			if ncj < 0 or ncj >= CHUNKS_PER_PLOT:
				continue
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
#  LOD
# ============================================================

func _resolution_for_distance(dist: int) -> int:
	if dist <= 1:
		return default_resolution
	elif dist <= 3:
		@warning_ignore("INTEGER_DIVISION")
		return maxi(16, default_resolution / 2)
	else:
		@warning_ignore("INTEGER_DIVISION")
		return maxi(8, default_resolution / 4)

func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

# ============================================================
#  加载 / 卸载
# ============================================================

func _load_chunk(key: Vector2i) -> void:
	var dist := _chebyshev(key, _last_center)
	var res := _resolution_for_distance(dist)

	var chunk := PlanetChunk.new()
	chunk.init(current_plot, key.x, key.y, res)

	var cu := (float(key.x) + 0.5) / float(CHUNKS_PER_PLOT)
	var cv := (float(key.y) + 0.5) / float(CHUNKS_PER_PLOT)
	chunk.world_center = plot_geo.uv_to_world(current_plot, cu, cv)
	chunk.world_size = PlotGeometry.PLOT_WORLD_SIZE / float(CHUNKS_PER_PLOT)

	_sample_chunk(chunk)
	chunks[key] = chunk

	# 生成 mesh
	var mesh := _mesh_builder.build_mesh(chunk)
	var mi := MeshInstance2D.new()
	mi.mesh = mesh
	mi.position = chunk.world_center
	mi.name = "Chunk_%d_%d_res%d" % [key.x, key.y, res]

	if _chunk_shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = _chunk_shader
		mi.material = mat

	add_child(mi)
	chunk_views[key] = mi

func _unload_chunk(key: Vector2i) -> void:
	if chunk_views.has(key):
		var mi: MeshInstance2D = chunk_views[key]
		mi.queue_free()
		chunk_views.erase(key)
	chunks.erase(key)

func _clear_all() -> void:
	for key in chunk_views.keys():
		var mi: MeshInstance2D = chunk_views[key]
		mi.queue_free()
	chunk_views.clear()
	chunks.clear()

# ============================================================
#  采样一个区块
# ============================================================
# 采样范围 px/py ∈ [0, res]，共 (res+1)×(res+1) 个点，
# 与相邻 chunk 共享边界（避免 mesh 裂缝）。

func _sample_chunk(chunk: PlanetChunk) -> void:
	if land_gen == null or height_gen == null:
		return

	var res := chunk.resolution
	var per_plot := float(CHUNKS_PER_PLOT)

	# 气候数据：取 chunk 中心方向对应的 cell
	var center_u := (float(chunk.ci) + 0.5) / per_plot
	var center_v := (float(chunk.cj) + 0.5) / per_plot
	var center_dir := plot_geo.uv_to_dir(chunk.plot_id, center_u, center_v)
	var climate_face := face_lookup.find(center_dir)
	if climate_face < 0:
		climate_face = 0

	var global_temp := 0.5
	var global_hum := 0.5
	if climate_face < data.f_temperature.size():
		global_temp = data.f_temperature[climate_face]
	if climate_face < data.f_humidity_atm.size():
		global_hum = data.f_humidity_atm[climate_face]

	for py in range(0, res + 1):
		for px in range(0, res + 1):
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
		return ChunkMeshBuilder.MAT_WATER
	if h < 0.02:
		return ChunkMeshBuilder.MAT_SAND
	if h > 0.50:
		return ChunkMeshBuilder.MAT_SNOW
	if t < 0.20:
		return ChunkMeshBuilder.MAT_TUNDRA
	if hum < 0.25:
		return ChunkMeshBuilder.MAT_DESERT
	if hum > 0.75:
		return ChunkMeshBuilder.MAT_SWAMP
	if hum > 0.55:
		return ChunkMeshBuilder.MAT_FOREST
	if h > 0.30:
		return ChunkMeshBuilder.MAT_ROCK
	return ChunkMeshBuilder.MAT_GRASS

# ============================================================
func loaded_chunk_count() -> int:
	return chunks.size()

func set_current_plot_if_needed(plot_id: int) -> void:
	if current_plot == plot_id:
		return
	_clear_all()
	current_plot = plot_id
	_last_center = Vector2i(-1, -1)