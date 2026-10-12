class_name PlanetView3D
extends MeshInstance3D
## 三阶段统一的 GPU 行星渲染视图。
##   mode 0 = LAND
##   mode 1 = HEIGHT
##   mode 2 = TEMPERATURE（+昼夜）
##   mode 3 = PRECIPITATION
##   mode 4 = CLOUD
##   mode 5 = SNOW
##   mode 6 = HUM_ATM
##
## 只读数据，不写 PlanetData。

@export var terrain_scale: float = 0.15

var data: PlanetData
var _mesh: ArrayMesh
var _material: ShaderMaterial

var _field_img: Image
var _field_tex: ImageTexture
var _land_img: Image
var _land_tex: ImageTexture
var _tex_w: int = 1024
var _tex_h: int = 1
var _N: int = 0

const SHADER_PATH := "res://scripts/rendering/planet_view_3d.gdshader"
const MAX_W := 1024

# 与 shader 的 mode 编号对齐
const MODE_LAND        := 0
const MODE_HEIGHT      := 1
const MODE_TEMPERATURE := 2
const MODE_PRECIP      := 3
const MODE_CLOUD       := 4
const MODE_SNOW        := 5
const MODE_HUM_ATM     := 6

func _ready() -> void:
	var shader: Shader = load(SHADER_PATH)
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("night_brightness", 0.22)
	material_override = _material

func setup(d: PlanetData) -> void:
	data = d
	_N = data.gp.face_count
	_tex_w = mini(_N, MAX_W)
	_tex_h = maxi(1, int(ceil(float(_N) / float(_tex_w))))

	_field_img = Image.create(_tex_w, _tex_h, false, Image.FORMAT_RF)
	_field_img.fill(Color(0, 0, 0, 0))
	_field_tex = ImageTexture.create_from_image(_field_img)

	_land_img = Image.create(_tex_w, _tex_h, false, Image.FORMAT_RF)
	_land_img.fill(Color(0, 0, 0, 0))
	_land_tex = ImageTexture.create_from_image(_land_img)

	_material.set_shader_parameter("field_tex", _field_tex)
	_material.set_shader_parameter("is_land_tex", _land_tex)
	_material.set_shader_parameter("tex_size", Vector2i(_tex_w, _tex_h))

# ============================================================
#  外部接口
# ============================================================
func rebuild_mesh() -> void:
	_build_mesh()

func update_land() -> void:
	_upload_is_land()
	var buf := _face_land_mask()
	_upload_field(buf)
	set_mode(MODE_LAND)

func update_height() -> void:
	var buf := PackedFloat32Array(); buf.resize(_tex_w * _tex_h)
	for f in _N:
		buf[f] = data.f_elevation[f]
	_upload_field(buf)
	set_mode(MODE_HEIGHT)

## 通用 field 上传。data 是 face_count 长度的标量数组。
func update_field(data_arr: PackedFloat32Array, mode: int) -> void:
	var buf := PackedFloat32Array(); buf.resize(_tex_w * _tex_h)
	var n := mini(data_arr.size(), _tex_w * _tex_h)
	for i in n:
		buf[i] = data_arr[i]
	_upload_field(buf)
	set_mode(mode)

## 兼容旧接口。内部走 update_field。
func update_temperature(temp: PackedFloat32Array) -> void:
	update_field(temp, MODE_TEMPERATURE)

func set_mode(mode: int) -> void:
	_material.set_shader_parameter("mode", mode)

func set_sun_dir(d: Vector3) -> void:
	_material.set_shader_parameter("sun_dir", d)

# ============================================================
#  内部
# ============================================================
func _upload_is_land() -> void:
	var buf := _face_land_mask()
	_land_img.set_data(_tex_w, _tex_h, false, Image.FORMAT_RF, buf.to_byte_array())
	_land_tex.update(_land_img)

func _face_land_mask() -> PackedFloat32Array:
	var buf := PackedFloat32Array(); buf.resize(_tex_w * _tex_h)
	for f in _N:
		buf[f] = 1.0 if data.face_is_land(f) else 0.0
	return buf

func _upload_field(buf: PackedFloat32Array) -> void:
	_field_img.set_data(_tex_w, _tex_h, false, Image.FORMAT_RF, buf.to_byte_array())
	_field_tex.update(_field_img)

func _build_mesh() -> void:
	var gp := data.gp
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var smooth_normals := PackedVector3Array()
	smooth_normals.resize(gp.vertex_count)
	for v in gp.vertex_count:
		smooth_normals[v] = Vector3.ZERO
	for f in gp.face_count:
		var start := gp.face_vertex_offsets[f]
		var end := gp.face_vertex_offsets[f + 1]
		var n := gp.face_normals[f]
		for i in range(start, end):
			var vi := gp.face_vertex_indices[i]
			smooth_normals[vi] += n
	for v in gp.vertex_count:
		var sn := smooth_normals[v]
		smooth_normals[v] = sn.normalized() if sn.length() > 0.001 else Vector3.UP

	for f in gp.face_count:
		var start := gp.face_vertex_offsets[f]
		var end := gp.face_vertex_offsets[f + 1]
		var n := end - start
		var center_dir := gp.face_normals[f]
		var center_h := data.f_elevation[f]
		var center_pos := center_dir * (gp.radius + center_h * terrain_scale)
		var fi := float(f)

		var base := verts.size()
		verts.append(center_pos)
		normals.append(center_dir)
		uvs.append(Vector2(fi, 0.0))

		for i in n:
			var vi: int = gp.face_vertex_indices[start + i]
			var vp: Vector3 = gp.vertex_positions[vi]
			var vh: float = data.v_height[vi]
			var lifted := vp.normalized() * (gp.radius + vh * terrain_scale)
			verts.append(lifted)
			normals.append(smooth_normals[vi])
			uvs.append(Vector2(fi, 0.0))

		for i in n:
			indices.append(base)
			indices.append(base + 1 + i)
			indices.append(base + 1 + ((i + 1) % n))

	_mesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = _mesh