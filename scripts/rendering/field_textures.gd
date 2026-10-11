class_name FieldTextures
extends RefCounted

const MAX_W := 1024

var width: int = 1024
var height: int = 1

var temp_texture: ImageTexture
var pressure_texture: ImageTexture
var wind_texture: ImageTexture
var hum_atm_texture: ImageTexture
var hum_land_texture: ImageTexture    # ★ 现在指向 soil 数据
var precip_texture: ImageTexture
var cloud_texture: ImageTexture
var snow_texture: ImageTexture
var soil_texture: ImageTexture
var river_texture: ImageTexture

var _temp_img: Image
var _pressure_img: Image
var _wind_img: Image
var _hum_atm_img: Image
var _hum_land_img: Image
var _precip_img: Image
var _cloud_img: Image
var _snow_img: Image
var _soil_img: Image
var _river_img: Image

var _temp_buf: PackedFloat32Array
var _pressure_buf: PackedFloat32Array
var _wind_buf: PackedFloat32Array
var _hum_atm_buf: PackedFloat32Array
var _hum_land_buf: PackedFloat32Array
var _precip_buf: PackedFloat32Array
var _cloud_buf: PackedFloat32Array
var _snow_buf: PackedFloat32Array
var _soil_buf: PackedFloat32Array
var _river_buf: PackedFloat32Array

func setup(face_count: int) -> void:
	width = mini(face_count, MAX_W)
	height = maxi(1, int(ceil(float(face_count) / float(width))))
	var total := width * height

	_temp_img = Image.create(width, height, false, Image.FORMAT_RF)
	_pressure_img = Image.create(width, height, false, Image.FORMAT_RF)
	_wind_img = Image.create(width, height, false, Image.FORMAT_RGBAF)
	_hum_atm_img = Image.create(width, height, false, Image.FORMAT_RF)
	_hum_land_img = Image.create(width, height, false, Image.FORMAT_RF)
	_precip_img = Image.create(width, height, false, Image.FORMAT_RF)
	_cloud_img = Image.create(width, height, false, Image.FORMAT_RF)
	_snow_img = Image.create(width, height, false, Image.FORMAT_RF)
	_soil_img = Image.create(width, height, false, Image.FORMAT_RF)
	_river_img = Image.create(width, height, false, Image.FORMAT_RF)

	for img in [_temp_img, _pressure_img, _wind_img, _hum_atm_img,
			_hum_land_img, _precip_img, _cloud_img, _snow_img,
			_soil_img, _river_img]:
		img.fill(Color(0,0,0,0))

	temp_texture = ImageTexture.create_from_image(_temp_img)
	pressure_texture = ImageTexture.create_from_image(_pressure_img)
	wind_texture = ImageTexture.create_from_image(_wind_img)
	hum_atm_texture = ImageTexture.create_from_image(_hum_atm_img)
	hum_land_texture = ImageTexture.create_from_image(_hum_land_img)
	precip_texture = ImageTexture.create_from_image(_precip_img)
	cloud_texture = ImageTexture.create_from_image(_cloud_img)
	snow_texture = ImageTexture.create_from_image(_snow_img)
	soil_texture = ImageTexture.create_from_image(_soil_img)
	river_texture = ImageTexture.create_from_image(_river_img)

	_temp_buf.resize(total)
	_pressure_buf.resize(total)
	_wind_buf.resize(total * 4)
	_hum_atm_buf.resize(total)
	_hum_land_buf.resize(total)
	_precip_buf.resize(total)
	_cloud_buf.resize(total)
	_snow_buf.resize(total)
	_soil_buf.resize(total)
	_river_buf.resize(total)

func update_temperature(f: PackedFloat32Array) -> void:
	_upload_r(_temp_img, temp_texture, _temp_buf, f)

func update_pressure(f: PackedFloat32Array) -> void:
	_upload_r(_pressure_img, pressure_texture, _pressure_buf, f)

func update_hum_atm(f: PackedFloat32Array) -> void:
	_upload_r(_hum_atm_img, hum_atm_texture, _hum_atm_buf, f)

## ★ hum_land_texture 现在用 soil 数据填充
func update_hum_land(f: PackedFloat32Array) -> void:
	_upload_r(_hum_land_img, hum_land_texture, _hum_land_buf, f)

func update_precip(f: PackedFloat32Array) -> void:
	_upload_r(_precip_img, precip_texture, _precip_buf, f)

func update_cloud(f: PackedFloat32Array) -> void:
	_upload_r(_cloud_img, cloud_texture, _cloud_buf, f)

func update_snow(f: PackedFloat32Array) -> void:
	_upload_r(_snow_img, snow_texture, _snow_buf, f)

func update_soil(f: PackedFloat32Array) -> void:
	_upload_r(_soil_img, soil_texture, _soil_buf, f)

func update_river(f: PackedFloat32Array, max_val: float) -> void:
	var n := mini(f.size(), _river_buf.size())
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
			var v := f[i]
			if v < 20.0:
				_river_buf[i] = 0.0
			else:
				var t := (log(v) - log_min) / log_range
				_river_buf[i] = clampf(t, 0.0, 1.0)
	_river_img.set_data(width, height, false, Image.FORMAT_RF, _river_buf.to_byte_array())
	river_texture.update(_river_img)

func update_wind(field: PackedVector3Array) -> void:
	for i in field.size():
		var v := field[i]
		_wind_buf[i*4] = v.x
		_wind_buf[i*4+1] = v.y
		_wind_buf[i*4+2] = v.z
		_wind_buf[i*4+3] = v.length()
	_wind_img.set_data(width, height, false, Image.FORMAT_RGBAF, _wind_buf.to_byte_array())
	wind_texture.update(_wind_img)

func _upload_r(img: Image, tex: ImageTexture,
		buf: PackedFloat32Array, field: PackedFloat32Array) -> void:
	var n := mini(field.size(), buf.size())
	for i in n:
		buf[i] = field[i]
	img.set_data(width, height, false, Image.FORMAT_RF, buf.to_byte_array())
	tex.update(img)

func get_field_size() -> Vector2i:
	return Vector2i(width, height)