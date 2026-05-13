extends CharacterBody2D


const SPEED := 300.0
const ATTACK_ANIMATIONS := [&"attack1", &"attack2"]

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("player")


func _physics_process(_delta: float) -> void:
	if animated_sprite_2d.animation in ATTACK_ANIMATIONS and animated_sprite_2d.is_playing():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_pressed("shield"):
		velocity = Vector2.ZERO
		animated_sprite_2d.play("shield")
		move_and_slide()
		return

	if Input.is_action_just_pressed("attack_1"):
		velocity = Vector2.ZERO
		animated_sprite_2d.play("attack1")
		move_and_slide()
		return

	if Input.is_action_just_pressed("attack_2"):
		velocity = Vector2.ZERO
		animated_sprite_2d.play("attack2")
		move_and_slide()
		return

	var input_direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_direction * SPEED

	if input_direction == Vector2.ZERO:
		animated_sprite_2d.play("idle")
	else:
		animated_sprite_2d.play("walk")

	if input_direction.x < 0.0:
		animated_sprite_2d.flip_h = true
	elif input_direction.x > 0.0:
		animated_sprite_2d.flip_h = false

	move_and_slide()
