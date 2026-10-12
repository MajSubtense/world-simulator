class_name FieldAtlas
extends RefCounted
## Field 纹理图集。用 FieldId 作为键，统一管理所有 field 的 Image / Texture。
##
## 用法：
##   atlas.setup(face_count)
##   atlas.upload(FieldId.TEMPERATURE, data.f_temperature)
##   atlas.upload(FieldId.WIND, data.f_wind)
##   var tex := atlas.get_texture(FieldId.TEMPERATURE)
##   atlas.update_river(data.f_flow, max_val)
##   var size := atlas.get_field_size()

const MAX_W := 1024

var width: int = 1024
var height: int = 1

var river_texture: ImageTexture

# FieldId → { img: Image, tex: ImageTexture, buf: PackedFloat32Array, fmt: int }
var _fields: Dictionary = {}
var _river_img: Image
var _river_buf: PackedFloat32Array
var _wind_flat_buf: PackedFloat32Array

# ============================================================
func setup(face_count: int) -> void:
	width = mini(face_count, MAX_W)
	height = maxi(1, int(ceil(float(face_count) / float(width))))
	var total := width * height

	_fields.clear()
	for entry in FieldId.all():
		var id: int = entry["id"]
		# 风是 vec3，其他都是标量
		var fmt := Image.FORMAT_RGBAF if id == FieldId.WIND else Image.FORMAT_RF
		var img := Image.create(width, height, false, fmt)
		img.fill(Color(0, 0, 0, 0))
		_fields[id] = {
			"img": img,
			"tex": ImageTexture.create_from_image(img),
			"buf": PackedFloat32Array(),
			"fmt": fmt,
		}

	_river_img = Image.create(width, height, false, Image.FORMAT_RF)
	_river_img.fill(Color(0, 0, 0, 0))
	river_texture = ImageTexture.create_from_image(_river_img)
	_river_buf.resize(total)
	_wind_flat_buf.resize(total * 4)

	for id in _fields.keys():
		var f: Dictionary = _fields[id]
		if f.fmt == Image.FORMAT_RGBAF:
			f.buf.resize(total * 4)
		else:
			f.buf.resize(total)

# ============================================================
#  上传
# ============================================================

## 上传标量 field。id 不能是 FieldId.WIND。
func upload(id: int, field: PackedFloat32Array) -> void:
	if id == FieldId.WIND:
		push_warning("FieldAtlas: WIND 请用 upload_wind()")
		return
	var f: Dictionary = _fields.get(id)
	if f == null:
		return
	var buf: PackedFloat32Array = f.buf
	var n := mini(field.size(), buf.size())
	for i in n:
		buf[i] = field[i]
	var img: Image = f.img
	img.set_data(width, height, false, Image.FORMAT_RF, buf.to_byte_array())
	var tex: ImageTexture = f.tex
	tex.update(img)

## 上传风场（vec3 → RGBAF）。
func upload_wind(field: PackedVector3Array) -> void:
	var f: Dictionary = _fields.get(FieldId.WIND)
	if f == null:
		return
	var n := mini(field.size(), width * height)
	for i in n:
		var v := field[i]
		_wind_flat_buf[i * 4] = v.x
		_wind_flat_buf[i * 4 + 1] = v.y
		_wind_flat_buf[i * 4 + 2] = v.z
		_wind_flat_buf[i * 4 + 3] = v.length()
	var img: Image = f.img
	img.set_data(width, height, false, Image.FORMAT_RGBAF,
		_wind_flat_buf.to_byte_array())
	var tex: ImageTexture = f.tex
	tex.update(img)

## 河流特殊处理：对数刻度 + 阈值。
func update_river(field: PackedFloat32Array, max_val: float) -> void:
	var n := mini(field.size(), _river_buf.size())
	if max_val < 0.001:
		for i in n:
			_river_buf[i] = 0.0
	else:
		var log_min := log(20.0)
		var log_max := log(maxf(max_val, 50.0))
		var log_range := log_max - log_min
		if log_range < 0.001:
			log_range = 0.001
		for i in n:
			var v := field[i]
			if v < 20.0:
				_river_buf[i] = 0.0
			else:
				var t := (log(v) - log_min) / log_range
				_river_buf[i] = clampf(t, 0.0, 1.0)
	_river_img.set_data(width, height, false, Image.FORMAT_RF,
		_river_buf.to_byte_array())
	river_texture.update(_river_img)

# ============================================================
#  访问
# ============================================================

func get_texture(id: int) -> ImageTexture:
	var f: Dictionary = _fields.get(id)
	return f.tex if f != null else null

func get_field_size() -> Vector2i:
	return Vector2i(width, height)

func get_river_texture() -> ImageTexture:
	return river_texture