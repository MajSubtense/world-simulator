class_name PlanetPlayer
extends CharacterBody2D
## 2D 俯视角玩家。WASD 移动，鼠标滚轮缩放。

@export var move_speed: float = 100.0

var camera: Camera2D

func _ready() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(3.0, 3.0)
	camera.enabled = true
	add_child(camera)
	camera.make_current()

func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_S): dir.y += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
	velocity = dir * move_speed
	move_and_slide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.15).clamp(Vector2(1, 1), Vector2(20, 20))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.15).clamp(Vector2(1, 1), Vector2(20, 20))