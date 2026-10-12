class_name PlanetChunk
extends RefCounted
## 一个区块的采样数据。最小加载/卸载单元。
##
## 采样数据分三层：
##   heights / land_scores / temperatures / humidities  —— 全局宏观数据
##   is_lands / materials                              —— 派生标记
##   delta_heights / delta_materials                   —— 玩家修改（稀疏）

const HALO := 1

var plot_id: int = -1
var ci: int = 0
var cj: int = 0
var resolution: int = 128
var sample_width: int = 130

# 2D 世界坐标（用于 Sprite2D 定位）
var world_center: Vector2 = Vector2.ZERO
var world_size: float = 128.0

# 采样数据
var heights: PackedFloat32Array
var land_scores: PackedFloat32Array
var temperatures: PackedFloat32Array
var humidities: PackedFloat32Array
var is_lands: PackedByteArray
var materials: PackedByteArray

# 玩家修改（稀疏）
var delta_heights: Dictionary = {}
var delta_materials: Dictionary = {}

func init(p: int, i: int, j: int, res: int) -> void:
	plot_id = p
	ci = i
	cj = j
	resolution = res
	sample_width = res + 2 * HALO
	var total := sample_width * sample_width
	heights.resize(total)
	land_scores.resize(total)
	temperatures.resize(total)
	humidities.resize(total)
	is_lands.resize(total)
	materials.resize(total)

func local_index(px: int, py: int) -> int:
	return (py + HALO) * sample_width + (px + HALO)

func get_final_height(idx: int) -> float:
	if delta_heights.has(idx):
		return heights[idx] + delta_heights[idx]
	return heights[idx]

func get_final_material(idx: int) -> int:
	if delta_materials.has(idx):
		return delta_materials[idx]
	return materials[idx]