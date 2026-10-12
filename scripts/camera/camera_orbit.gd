class_name CameraOrbit
extends Node3D
## 相机围绕原点旋转。
##   - 鼠标中键拖拽：旋转视角
##   - 滚轮：拉近拉远
## 相机自身不跟随任何节点，看的是世界空间原点。

@export var distance: float = 3.2
@export var min_distance: float = 1.2
@export var max_distance: float = 20.0
@export var rotate_speed: float = 0.006
@export var zoom_step: float = 1.10
@export var fov: float = 50.0

var yaw: float = 0.0
var pitch: float = 0.30

const PITCH_MARGIN := 0.15

var _dragging: bool = false
var _cam: Camera3D

func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = fov
	add_child(_cam)
	_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance / zoom_step)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * zoom_step)
			_update_camera()

	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * rotate_speed
		pitch += event.relative.y * rotate_speed
		var limit := PI / 2.0 - PITCH_MARGIN
		pitch = clampf(pitch, -limit, limit)
		_update_camera()

func _update_camera() -> void:
	var cp := cos(pitch)
	var offset := Vector3(
		cp * sin(yaw),
		sin(pitch),
		cp * cos(yaw)
	) * distance
	_cam.position = offset
	_cam.look_at(Vector3.ZERO)

func get_camera() -> Camera3D:
	return _cam

## 让相机聚焦到给定方向。相机位置位于 dir * distance，看向原点。
## 因此 dir 方向的面朝相机。
func focus_on_dir(dir: Vector3) -> void:
	if dir.length_squared() < 0.000001:
		return
	var d := dir.normalized()
	pitch = asin(clampf(d.y, -1.0, 1.0))
	yaw = atan2(d.x, d.z)
	var limit := PI / 2.0 - PITCH_MARGIN
	pitch = clampf(pitch, -limit, limit)
	_update_camera()