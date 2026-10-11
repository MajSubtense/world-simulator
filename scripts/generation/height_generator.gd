class_name HeightGenerator
extends RefCounted
## 高程生成器（阶段 2）。
##
## 分层结构（从低到高）：
##   陆地基底  ← land_score 决定，内陆中心抬升
##   + 高原    ← 低频阈值化，形成台地
##   + 山脉带  ← belt 噪声圈定区域，ridge 噪声在其中起脊
##   + 丘陵    ← 高频细节
##   海洋      ← 基础深度 + 洋底起伏
##
## 参数来源：
##   全部从 HeightConfig 读取。
##
## 与 LandGenerator 的耦合：
##   通过 config 的 land_gen 引用调用 land_score_at(dir)，
##   保证山脉与海岸线对齐。

var config: HeightConfig
var land_gen: LandGenerator

# ---- 噪声缓存（惰性创建）----
var _plateau_noise: FastNoiseLite
var _belt_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _hill_noise: FastNoiseLite
var _ocean_noise: FastNoiseLite
var _ocean_detail_noise: FastNoiseLite

# ============================================================
#  外部接口
# ============================================================

func setup(cfg: HeightConfig, lg: LandGenerator) -> void:
	config = cfg
	land_gen = lg
	invalidate()

## 参数变化后调用，丢弃缓存的噪声，下次采样时重建。
func invalidate() -> void:
	_plateau_noise = null
	_belt_noise = null
	_ridge_noise = null
	_hill_noise = null
	_ocean_noise = null
	_ocean_detail_noise = null

func generate(data: PlanetData) -> void:
	if config == null:
		push_error("HeightGenerator: config 未设置")
		return
	_ensure_noises()

	var gp := data.gp
	for v in gp.vertex_count:
		var dir := gp.vertex_positions[v].normalized()
		var is_land := data.v_is_land[v] == 1
		var ls := 1.0
		if land_gen != null:
			ls = land_gen.land_score_at(dir)
		data.v_height[v] = sample_height(dir, is_land, ls)

	data.sync_face_elevation()

# ============================================================
#  采样
# ============================================================

## 在任意方向上采样高度（单位：球面半径倍数）。
## 供 ChunkGenerator / 地图 / 玩家附近的精细采样复用。
## 输入：
##   dir        单位方向向量
##   is_land    该方向是否陆地
##   land_score 该方向的 land_score（0=海岸，1=内陆最深处）
func sample_height(dir: Vector3, is_land: bool, land_score: float) -> float:
	_ensure_noises()
	if is_land:
		return _land_height(dir, land_score)
	else:
		return _ocean_height(dir)

func _land_height(dir: Vector3, land_score: float) -> float:
	var lc := clampf(land_score, 0.0, 1.0)

	# ---- 1. 内陆基底 ----
	var base := pow(lc, config.continental_pow) * config.continental_rise

	# ---- 2. 海岸衰减 ----
	var coast := smoothstep(0.0, config.coast_damping, lc)
	base += config.land_base * coast
	base *= coast

	# ---- 3. 高原 ----
	var p := _plateau_noise.get_noise_3d(dir.x, dir.y, dir.z) * 0.5 + 0.5
	var plateau_mask := smoothstep(
		config.plateau_threshold, config.plateau_threshold + 0.25, p)
	var plateau := plateau_mask * config.plateau_height

	# ---- 4. 山脉带 ----
	var belt_raw := _belt_noise.get_noise_3d(dir.x, dir.y, dir.z) * 0.5 + 0.5
	var belt := smoothstep(
		config.belt_threshold, config.belt_threshold + 0.20, belt_raw)

	var ridge_raw := _ridge_noise.get_noise_3d(dir.x, dir.y, dir.z)
	var ridge := maxf(ridge_raw, 0.0)

	var mountain_mask := smoothstep(0.05, 0.20, lc)
	var mountain := belt * ridge * config.mountain_peak * mountain_mask
	# 高原上抑制山脉
	mountain *= (1.0 - plateau_mask * 0.5)

	# ---- 5. 丘陵 ----
	var hill := _hill_noise.get_noise_3d(dir.x, dir.y, dir.z) * config.hill_detail

	return base + plateau + mountain + hill

func _ocean_height(dir: Vector3) -> float:
	var o := _ocean_noise.get_noise_3d(dir.x, dir.y, dir.z)
	var od := _ocean_detail_noise.get_noise_3d(dir.x, dir.y, dir.z)
	var depth := config.ocean_depth * 0.5 + o * config.ocean_depth * 0.3 \
		+ od * config.ocean_detail
	return -maxf(depth, 0.005)

# ============================================================
#  噪声
# ============================================================

func _ensure_noises() -> void:
	if _plateau_noise != null:
		return
	if config == null:
		return
	_plateau_noise = _make_noise(config.plateau_seed, config.plateau_freq, 3)
	_belt_noise    = _make_noise(config.mountain_seed, config.belt_freq, 3)
	_ridge_noise   = _make_noise(config.mountain_seed + 1, config.ridge_freq, 4)
	_hill_noise    = _make_noise(config.mountain_seed + 777, config.hill_freq, 3)
	_ocean_noise   = _make_noise(config.ocean_seed, config.ocean_freq, 4)
	_ocean_detail_noise = _make_noise(config.ocean_seed + 888, config.ocean_detail_freq, 3)

func _make_noise(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n