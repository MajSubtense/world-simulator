class_name MapView
extends Control
## 地图显示：支持缩放拖拽 + CPU 纹理 / GPU shader 两种模式 + 风箭头。

var min_zoom: float = 0.3
var max_zoom: float = 12.0
var zoom_step: float = 1.15

var _cpu_rect: TextureRect
var _gpu_rect: ColorRect
var _material: ShaderMaterial
var _zoom: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _use_shader: bool = false

var wind_arrows: WindArrows

const SHADER_PATH := "res://scripts/rendering/map_display.gdshader"

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true

	_cpu_rect = TextureRect.new()
	_cpu_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cpu_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_cpu_rect.mouse_filter = MOUSE_FILTER_IGNORE
	_cpu_rect.visible = true
	add_child(_cpu_rect)

	_gpu_rect = ColorRect.new()
	_gpu_rect.mouse_filter = MOUSE_FILTER_IGNORE
	_gpu_rect.visible = false
	var shader: Shader = load(SHADER_PATH)
	if shader != null:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_gpu_rect.material = _material
	add_child(_gpu_rect)

	wind_arrows = WindArrows.new()
	wind_arrows.visible = false
	add_child(wind_arrows)

	_update_transform()

# ============================================================
#  模式切换
# ============================================================
func set_use_shader(use_shader: bool) -> void:
	_use_shader = use_shader
	_cpu_rect.visible = not use_shader
	_gpu_rect.visible = use_shader
	_update_transform()

func is_using_shader() -> bool:
	return _use_shader

# ============================================================
#  纹理接口
# ============================================================
func set_texture_cpu(tex: Texture2D) -> void:
	if _cpu_rect:
		_cpu_rect.texture = tex
		if not _use_shader:
			_update_transform()

func set_texture(tex: Texture2D) -> void:
	set_texture_cpu(tex)

func set_baked_textures(base_tex: Texture2D, face_tex: Texture2D) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("base_tex", base_tex)
	_material.set_shader_parameter("face_tex", face_tex)

func set_field_textures(
		temp_tex: Texture2D,
		pressure_tex: Texture2D,
		wind_tex: Texture2D,
		hum_atm_tex: Texture2D,
		hum_land_tex: Texture2D,
		precip_tex: Texture2D,
		cloud_tex: Texture2D,
		snow_tex: Texture2D,
		soil_tex: Texture2D,
		field_size: Vector2i) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("temp_tex", temp_tex)
	_material.set_shader_parameter("pressure_tex", pressure_tex)
	_material.set_shader_parameter("wind_tex", wind_tex)
	_material.set_shader_parameter("hum_atm_tex", hum_atm_tex)
	_material.set_shader_parameter("hum_land_tex", hum_land_tex)
	_material.set_shader_parameter("precip_tex", precip_tex)
	_material.set_shader_parameter("cloud_tex", cloud_tex)
	_material.set_shader_parameter("snow_tex", snow_tex)
	_material.set_shader_parameter("soil_tex", soil_tex)
	_material.set_shader_parameter("field_size", field_size)

func set_river_texture(tex: Texture2D) -> void:
	if _material:
		_material.set_shader_parameter("river_tex", tex)

func set_mode(mode: int) -> void:
	if _material:
		_material.set_shader_parameter("mode", mode)

func set_sun_dir(d: Vector3) -> void:
	if _material:
		_material.set_shader_parameter("sun_dir", d)

# ============================================================
#  风箭头接口
# ============================================================
func set_wind_arrows_visible(v: bool) -> void:
	if wind_arrows:
		wind_arrows.visible = v

func set_wind_data(wind: PackedVector3Array) -> void:
	if wind_arrows:
		wind_arrows.update_wind(wind)

func set_wind_face_lookup(lookup: FaceLookup) -> void:
	if wind_arrows:
		wind_arrows.face_lookup = lookup

func set_wind_map_size(w: int, h: int) -> void:
	if wind_arrows:
		wind_arrows.set_map_size(w, h)

func set_wind_projection(proj: int) -> void:
	if wind_arrows:
		wind_arrows.set_projection(proj)

# ============================================================
#  视图控制
# ============================================================
func reset_view() -> void:
	_zoom = 1.0
	_offset = Vector2.ZERO
	_update_transform()

# ============================================================
#  输入
# ============================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, zoom_step)
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / zoom_step)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_offset += event.relative
		_update_transform()
		accept_event()

# ============================================================
#  内部
# ============================================================
func _base_size() -> Vector2:
	var s := minf(size.x / 2.0, size.y / 1.0)
	return Vector2(2.0 * s, 1.0 * s)

func _update_transform() -> void:
	var base := _base_size() * _zoom
	var pos := (size - base) * 0.5 + _offset
	if _cpu_rect:
		_cpu_rect.size = base
		_cpu_rect.position = pos
	if _gpu_rect:
		_gpu_rect.size = base
		_gpu_rect.position = pos
	if wind_arrows:
		wind_arrows.position = pos
		wind_arrows.set_display_size(base)

func _zoom_at(mouse_pos: Vector2, factor: float) -> void:
	var old_zoom := _zoom
	_zoom = clampf(_zoom * factor, min_zoom, max_zoom)
	var real_factor := _zoom / old_zoom
	var center := size * 0.5 + _offset
	var rel := mouse_pos - center
	_offset -= rel * (real_factor - 1.0)
	_update_transform()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _cpu_rect != null:
		_update_transform()