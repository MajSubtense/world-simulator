class_name PlanetPlayer
extends CharacterBody2D
## 2D 俯视角玩家。WASD 移动（InputMap: move_up / move_down / move_left / move_right）。
## 不携带相机 —— 相机由 PlayScene 管理并跟随本节点。

@export var move_speed: float = 100.0

func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * move_speed
	move_and_slide()