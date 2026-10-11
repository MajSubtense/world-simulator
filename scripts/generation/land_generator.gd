class_name LandGenerator
extends RefCounted
## 海陆生成器（阶段 1）。
##
## 算法：
##   1. 在每个顶点采样 3D 噪声 → 海陆分数 score
##   2. 按目标陆地比例，在分位数上确定海平面阈值 sea_level
##   3. 海蚀：用第二个噪声扰动海岸线附近的海平面，使海岸不规则
##   4. 输出二值 v_is_land
##
## 复用约定：
##   - last_land_noise / last_erosion_noise / last_sea_level 在 generate() 后
##     保留为快照。后续模块（HeightGenerator、ChunkGenerator）通过
##     land_score_at() 复用同一套噪声参数，保证地形严格一致。
##
## 参数来源：
##   全部从 LandConfig 读取；本类不缓存参数副本。

var config: LandConfig

# ---- 生成参数快照（generate() 后有效）----
var last_land_noise: FastNoiseLite
var last_erosion_noise: FastNoiseLite
var last_sea_level: float = 0.0

# ---- 常量 ----
const FREQ_MIN := 0.70
const FREQ_MAX := 3.50
const EROSION_FREQ := 5.0
const EROSION_AMPLITUDE := 0.35
const EROSION_BAND := 0.15

# ============================================================
#  外部接口
# ============================================================

func setup(cfg: LandConfig) -> void:
	config = cfg

func generate(data: PlanetData) -> void:
	if config == null:
		push_error("LandGenerator: config 未设置")
		return

	var gp := data.gp
	var V := gp.vertex_count

	# ---- 1. 基础噪声 ----
	var base_noise := _make_noise(
		config.land_seed,
		lerpf(FREQ_MIN, FREQ_MAX, config.land_dispersion),
		5)

	var score := PackedFloat32Array()
	score.resize(V)
	for v in V:
		var dir := gp.vertex_positions[v].normalized()
		score[v] = base_noise.get_noise_3d(dir.x, dir.y, dir.z)

	# ---- 2. 分位数确定海平面 ----
	var sea_level := _find_sea_level(score, config.land_ratio)

	# ---- 3. 海蚀噪声（可选）----
	var erosion_noise: FastNoiseLite = null
	if config.erosion_strength > 0.001:
		erosion_noise = _make_noise(config.erosion_seed, EROSION_FREQ, 3)

	# ---- 4. 写入 v_is_land ----
	for v in V:
		var local_threshold := sea_level
		if erosion_noise != null:
			var dir := gp.vertex_positions[v].normalized()
			var e := erosion_noise.get_noise_3d(dir.x, dir.y, dir.z)
			var proximity := clampf(
				1.0 - absf(score[v] - sea_level) / EROSION_BAND, 0.0, 1.0)
			local_threshold = sea_level - e * config.erosion_strength \
				* EROSION_AMPLITUDE * proximity
		data.v_is_land[v] = 1 if score[v] > local_threshold else 0

	# ---- 保存快照 ----
	last_land_noise = base_noise
	last_erosion_noise = erosion_noise
	last_sea_level = sea_level

## 在任意方向上求连续 land_score：
##   0.0 = 海洋深处 / 远离海岸
##   0.5 = 海岸线
##   1.0 = 内陆最深处
## 供 HeightGenerator、ChunkGenerator 复用，保证与 v_is_land 一致。
func land_score_at(dir: Vector3) -> float:
	if last_land_noise == null:
		return 0.5
	var score := last_land_noise.get_noise_3d(dir.x, dir.y, dir.z)
	var local_threshold := last_sea_level
	if last_erosion_noise != null:
		var e := last_erosion_noise.get_noise_3d(dir.x, dir.y, dir.z)
		var proximity := clampf(
			1.0 - absf(score - last_sea_level) / EROSION_BAND, 0.0, 1.0)
		local_threshold = last_sea_level - e * config.erosion_strength \
			* EROSION_AMPLITUDE * proximity

	# raw = 分数离海平面的距离；陆地为正，海洋为负
	var raw := score - local_threshold
	# 映射到 [0, 1]：raw = 0 → 0.5（海岸线）
	return clampf(raw * 2.5 + 0.5, 0.0, 1.0)

## 在任意方向上判断是否陆地。和 generate() 用同一套噪声 + 海蚀逻辑。
func sample_is_land(dir: Vector3) -> bool:
	if last_land_noise == null:
		return false
	var score := last_land_noise.get_noise_3d(dir.x, dir.y, dir.z)
	var local_threshold := last_sea_level
	if last_erosion_noise != null:
		var e := last_erosion_noise.get_noise_3d(dir.x, dir.y, dir.z)
		var proximity := clampf(
			1.0 - absf(score - last_sea_level) / EROSION_BAND, 0.0, 1.0)
		local_threshold = last_sea_level - e * config.erosion_strength \
			* EROSION_AMPLITUDE * proximity
	return score > local_threshold

# ============================================================
#  内部
# ============================================================

## 用分位数找到对应 land_ratio 的海平面阈值。
func _find_sea_level(score: PackedFloat32Array, land_ratio: float) -> float:
	var sorted := score.duplicate()
	sorted.sort()
	var idx := int(round((1.0 - land_ratio) * (sorted.size() - 1)))
	idx = clampi(idx, 0, sorted.size() - 1)
	return sorted[idx]

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