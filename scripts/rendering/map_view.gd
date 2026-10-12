class_name MapView
extends Control
## 地图显示：支持缩放拖拽 + CPU 纹理 / GPU shader 两种模式 + 风箭头。
##
## 左键点击发 map_clicked(u, v)；鼠标移动发 map_hovered(u, v)。
## u/v 是 [0,1] 归一化坐标。移出或越界发 (-1, -1)。
##
## 悬停 / 选中高亮：通过 set_plot_gp() 注入 plot 层网格后，
## 用球面逆投影在 2D 上画出地块边界（有畸变）。

signal map_clicked(u: float, v: float)
signal map_hovered(u: float, v: float)

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
var _projection: int = 0

var wind_arrows: WindArrows

# ---- 高亮 ----
var _plot_gp: GoldbergPolyhedron = null
var _hover_plot: int = -1
var _selected_plot: int = -1
var _highlight_canvas: Control

const SHADER_PATH := "res://scripts/rendering/map_view.gdshader"

# 内部高亮画布
class HighlightCanvas extends Control:
	var map_view_ref: MapView
	func _draw() -> void:
		if map_view_ref != null:
			map_view_ref.render_highlights(self)

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true

	_cpu_rect = TextureRect.new()
	_cpu_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cpu_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_cpu_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cpu_rect.visible = true
	add_child(_cpu_rect)

	_gpu_rect = ColorRect.new()
	_gpu_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	_highlight_canvas = HighlightCanvas.new()
	_highlight_canvas.map_view_ref = self
	_highlight_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_highlight_canvas)

	_update_transform()

# ============================================================
#  模式
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

func set_baked_textures(base_tex: Texture2D, face_tex: Texture2D) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("base_tex", base_tex)
	_material.set_shader_parameter("face_tex", face_tex)

func set_field_atlas(atlas: FieldAtlas) -> void:
	if _material == null or atlas == null:
		return
	_material.set_shader_parameter("temp_tex",        atlas.get_texture(FieldId.TEMPERATURE))
	_material.set_shader_parameter("pressure_tex",    atlas.get_texture(FieldId.PRESSURE))
	_material.set_shader_parameter("wind_tex",        atlas.get_texture(FieldId.WIND))
	_material.set_shader_parameter("hum_atm_tex",     atlas.get_texture(FieldId.HUM_ATM))
	_material.set_shader_parameter("precip_tex",      atlas.get_texture(FieldId.PRECIP))
	_material.set_shader_parameter("cloud_tex",       atlas.get_texture(FieldId.CLOUD))
	_material.set_shader_parameter("snow_tex",        atlas.get_texture(FieldId.SNOW))
	_material.set_shader_parameter("soil_tex",        atlas.get_texture(FieldId.SOIL))
	_material.set_shader_parameter("river_tex",       atlas.get_river_texture())
	_material.set_shader_parameter("veg_type_tex",    atlas.get_texture(FieldId.VEG_TYPE))
	_material.set_shader_parameter("veg_density_tex", atlas.get_texture(FieldId.VEG_DENSITY))
	_material.set_shader_parameter("temp_ema_tex",    atlas.get_texture(FieldId.TEMP_EMA))
	_material.set_shader_parameter("field_size",      atlas.get_field_size())

func set_mode(mode: int) -> void:
	if _material:
		_material.set_shader_parameter("mode", mode)

## 更新太阳方向，用于昼夜遮罩。
func set_sun_dir(d: Vector3) -> void:
	if _material:
		_material.set_shader_parameter("sun_dir", d)

## 是否显示昼夜遮罩（晨昏圈）。
func set_terminator_visible(v: bool) -> void:
	if _material:
		_material.set_shader_parameter("show_terminator", v)

# ============================================================
#  高亮接口
# ============================================================
func set_plot_gp(gp: GoldbergPolyhedron) -> void:
	_plot_gp = gp
	_highlight_canvas.queue_redraw()

func set_hover_plot(idx: int) -> void:
	if idx == _hover_plot:
		return
	_hover_plot = idx
	_highlight_canvas.queue_redraw()

func set_selected_plot(idx: int) -> void:
	if idx == _selected_plot:
		return
	_selected_plot = idx
	_highlight_canvas.queue_redraw()

func clear_highlights() -> void:
	_hover_plot = -1
	_selected_plot = -1
	_highlight_canvas.queue_redraw()

# ============================================================
#  风箭头
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
	_projection = proj
	if wind_arrows:
		wind_arrows.set_projection(proj)
	if _material:
		_material.set_shader_parameter("projection", proj)
	_highlight_canvas.queue_redraw()

func get_projection() -> int:
	return _projection

# ============================================================
#  视图
# ============================================================
func reset_view() -> void:
	_zoom = 1.0
	_offset = Vector2.ZERO
	_update_transform()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var uv := _mouse_to_uv(event.position)
			if uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0:
				map_clicked.emit(uv.x, uv.y)
			accept_event()
			return

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, zoom_step)
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / zoom_step)
			accept_event()
	elif event is InputEventMouseMotion:
		var uv := _mouse_to_uv(event.position)
		if uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0:
			map_hovered.emit(uv.x, uv.y)
		else:
			map_hovered.emit(-1.0, -1.0)

		if _dragging:
			_offset += event.relative
			_update_transform()
			accept_event()

# ============================================================
#  高亮渲染
# ============================================================
func render_highlights(canvas: Control) -> void:
	if _plot_gp == null:
		return
	var base := _base_size() * _zoom
	var origin := (size - base) * 0.5 + _offset

	# 先悬停（填充），再选中（线框）
	if _hover_plot >= 0 and _hover_plot < _plot_gp.face_count:
		_draw_plot_polygon(canvas, _hover_plot,
			Color(0.55, 0.90, 1.0, 0.35), base, origin)

	if _selected_plot >= 0 and _selected_plot < _plot_gp.face_count:
		_draw_plot_outline(canvas, _selected_plot,
			Color(1.0, 0.85, 0.2, 1.0), base, origin)

func _draw_plot_polygon(canvas: Control, plot_idx: int,
		color: Color, base: Vector2, origin: Vector2) -> void:
	var start := _plot_gp.face_vertex_offsets[plot_idx]
	var end := _plot_gp.face_vertex_offsets[plot_idx + 1]
	var n := end - start
	if n < 3:
		return

	var pts := PackedVector2Array()
	var min_u := 1.0
	var max_u := 0.0
	for i in n:
		var vi := _plot_gp.face_vertex_indices[start + i]
		var v3 := _plot_gp.vertex_positions[vi].normalized()
		var uv := MapProjection.dir_to_uv(v3, _projection)
		min_u = minf(min_u, uv.x)
		max_u = maxf(max_u, uv.x)
		pts.append(origin + uv * base)

	# 跨越 180° 经线时跳过填充（避免横穿整幅地图）
	if max_u - min_u > 0.5:
		return
	canvas.draw_colored_polygon(pts, color)

func _draw_plot_outline(canvas: Control, plot_idx: int,
		color: Color, base: Vector2, origin: Vector2) -> void:
	var start := _plot_gp.face_vertex_offsets[plot_idx]
	var end := _plot_gp.face_vertex_offsets[plot_idx + 1]
	var n := end - start
	if n < 3:
		return
	for i in n:
		var vi_a := _plot_gp.face_vertex_indices[start + i]
		var vi_b := _plot_gp.face_vertex_indices[start + ((i + 1) % n)]
		var va := _plot_gp.vertex_positions[vi_a].normalized()
		var vb := _plot_gp.vertex_positions[vi_b].normalized()
		var uva := MapProjection.dir_to_uv(va, _projection)
		var uvb := MapProjection.dir_to_uv(vb, _projection)
		# 跨越 180° 经线时跳过该边
		if absf(uva.x - uvb.x) > 0.5:
			continue
		canvas.draw_line(origin + uva * base, origin + uvb * base, color, 2.0)

# ============================================================
#  内部
# ============================================================
func _base_size() -> Vector2:
	var s := minf(size.x / 2.0, size.y / 1.0)
	return Vector2(2.0 * s, 1.0 * s)

func _mouse_to_uv(mouse_pos: Vector2) -> Vector2:
	var base := _base_size() * _zoom
	var pos := (size - base) * 0.5 + _offset
	return (mouse_pos - pos) / base

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
	if _highlight_canvas:
		_highlight_canvas.queue_redraw()

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
	elif what == NOTIFICATION_MOUSE_EXIT:
		map_hovered.emit(-1.0, -1.0)
