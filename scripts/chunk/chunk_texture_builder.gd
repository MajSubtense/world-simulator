class_name ChunkTextureBuilder
extends RefCounted
## 把 PlanetChunk 的采样数据转成一张 ImageTexture。
## 2D 俯视角下每个采样点 = 一个像素。

const MAT_WATER      := 0
const MAT_SAND       := 1
const MAT_GRASS      := 2
const MAT_FOREST     := 3
const MAT_ROCK       := 4
const MAT_SNOW       := 5
const MAT_TUNDRA     := 6
const MAT_DESERT     := 7
const MAT_SWAMP      := 8

func build(chunk: PlanetChunk) -> ImageTexture:
	var res := chunk.resolution
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for py in res:
		for px in res:
			var idx := chunk.local_index(px, py)
			var h := chunk.get_final_height(idx)
			var mat := chunk.get_final_material(idx)
			img.set_pixel(px, py, _color(mat, h))
	return ImageTexture.create_from_image(img)

func _color(mat: int, _h: float) -> Color:
	match mat:
		MAT_WATER:  return Color(0.10, 0.32, 0.62)
		MAT_SAND:   return Color(0.86, 0.78, 0.55)
		MAT_GRASS:  return Color(0.42, 0.68, 0.35)
		MAT_FOREST: return Color(0.22, 0.48, 0.22)
		MAT_ROCK:   return Color(0.48, 0.44, 0.40)
		MAT_SNOW:   return Color(0.94, 0.95, 0.97)
		MAT_TUNDRA: return Color(0.55, 0.58, 0.52)
		MAT_DESERT: return Color(0.82, 0.72, 0.42)
		MAT_SWAMP:  return Color(0.30, 0.42, 0.28)
	return Color(0.5, 0.5, 0.5)