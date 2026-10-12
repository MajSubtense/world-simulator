class_name NoiseFactory
extends RefCounted
## 统一噪声构造。LandGenerator 与 HeightGenerator 共用。

## Simplex + FBM 分形。
static func simplex(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n

## Simplex + Ridged 分形。适合山脊。
static func ridged(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := simplex(seed_val, freq, octaves)
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	return n