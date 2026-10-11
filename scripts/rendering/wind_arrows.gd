class_name WindArrows
extends Node2D
## 地图风场箭头。
## 优化：
##   - 静态数据只在参数变化时计算一次
##   - 每 0.3 秒重绘一次
##   - 全部用三角形批量提交（1 次 draw call）
## 视觉：
##   - 主干是细矩形
##   - 头部是三角形
##   - 从中心对称伸出（视觉重心在采样点）

@export var sample_step: int = 32
@export var arrow_length: float = 12.0
@export var arrow_color: Color = Color(0.95, 0.95, 1.0, 0.9)
@export var min_magnitude: float = 0.0005
@export var strength_scale: float = 30.0
@export var update_interval: float = 0.3

var face_lookup: FaceLookup
var wind_data: PackedVector3Array
var projection: int = 0

var map_width: int = 512
var map_height: int = 256
var display_size: Vector2 = Vector2(1024, 512)

var _samples: Array = []
var _timer: float = 0.0

var _tri_points := PackedVector2Array()
var _tri_colors := PackedColorArray()

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		queue_redraw()

# ============================================================
#  外部接口
# ============================================================
func update_wind(wind: PackedVector3Array) -> void:
	wind_data = wind

func set_map_size(w: int, h: int) -> void:
	if map_width == w and map_height == h:
		return
	map_width = w
	map_height = h
	_rebuild_samples()
	queue_redraw()

func set_projection(proj: int) -> void:
	if projection == proj:
		return
	projection = proj
	_rebuild_samples()
	queue_redraw()

func set_display_size(size: Vector2) -> void:
	display_size = size
	queue_redraw()

func set_arrow_color(c: Color) -> void:
	arrow_color = c
	queue_redraw()

func set_sample_step(step: int) -> void:
	sample_step = maxi(8, step)
	_rebuild_samples()
	queue_redraw()

# ============================================================
#  静态数据缓存
# ============================================================
func _rebuild_samples() -> void:
	_samples.clear()
	if face_lookup == null:
		return

	var eps := 0.002
	var gy := 0
	while gy < map_height:
		var gx := 0
		while gx < map_width:
			var u := (float(gx) + 0.5) / float(map_width)
			var v := (float(gy) + 0.5) / float(map_height)
			var dir3 := MapProjectionHelper.uv_to_dir(u, v, projection)

			if dir3 != Vector3.ZERO:
				var pu := MapProjectionHelper.uv_to_dir(u + eps, v, projection)
				var pv := MapProjectionHelper.uv_to_dir(u, v + eps, projection)
				if pu != Vector3.ZERO and pv != Vector3.ZERO:
					var dx := pu - dir3
					var dy := pv - dir3
					if dx.length_squared() > 0.000001 \
							and dy.length_squared() > 0.000001:
						dx = dx.normalized()
						dy = dy.normalized()
						var f := face_lookup.find(dir3)
						_samples.append({
							"gx": gx,
							"gy": gy,
							"face": f,
							"dx": dx,
							"dy": dy,
						})
			gx += sample_step
		gy += sample_step

# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	if wind_data.size() == 0 or _samples.is_empty():
		return

	var sx := display_size.x / float(map_width)
	var sy := display_size.y / float(map_height)
	var display_scale := (sx + sy) * 0.5

	_tri_points.clear()
	_tri_colors.clear()

	# 顶点缓存
	var p0: Vector2
	var p1: Vector2
	var p2: Vector2
	var p3: Vector2
	var p4: Vector2
	var p5: Vector2

	for s in _samples:
		var f: int = s.face
		if f < 0 or f >= wind_data.size():
			continue

		var w3: Vector3 = wind_data[f]
		var dx: Vector3 = s.dx
		var dy: Vector3 = s.dy
		var w2 := Vector2(w3.dot(dx), w3.dot(dy))
		var mag := w2.length()
		if mag < min_magnitude:
			continue

		var dir2 := w2 / mag
		var len_px := arrow_length * display_scale \
			* clampf(mag * strength_scale, 0.35, 1.4)

		# 从采样点沿方向伸出，尾部留 30%
		var center := Vector2(s.gx * sx, s.gy * sy)
		var tip := center + dir2 * len_px * 0.7
		var tail := center - dir2 * len_px * 0.3

		var perp := Vector2(-dir2.y, dir2.x)

		var head_len := maxf(len_px * 0.35, 2.0)
		var head_w := maxf(len_px * 0.22, 1.4)
		var stem_half := maxf(len_px * 0.07, 0.7)

		var head_base := tip - dir2 * head_len
		var stem_p := perp * stem_half
		var head_p := perp * head_w

		# ---- 主干矩形（2 个三角形）----
		p0 = tail + stem_p
		p1 = tail - stem_p
		p2 = head_base + stem_p
		p3 = head_base - stem_p
		# 三角形 1
		_tri_points.append(p0)
		_tri_points.append(p1)
		_tri_points.append(p2)
		# 三角形 2
		_tri_points.append(p1)
		_tri_points.append(p3)
		_tri_points.append(p2)

		# ---- 头部三角形（1 个）----
		p4 = head_base + head_p
		p5 = head_base - head_p
		_tri_points.append(tip)
		_tri_points.append(p4)
		_tri_points.append(p5)

		# 颜色
		for i in 9:
			_tri_colors.append(arrow_color)

	if _tri_points.size() > 0:
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(),
			PackedInt32Array(),
			_tri_points,
			_tri_colors)
