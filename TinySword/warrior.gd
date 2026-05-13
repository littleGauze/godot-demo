extends CharacterBody2D


const SWORD_SFX := preload("res://TinySword/Audio/sword.mp3")
const SPEED := 300.0
const ATTACK_ANIMATIONS := [&"attack1", &"attack2"]
const ATTACK_DAMAGE := 1
const ATTACK_ZONE_ACTIVE_FRAME := 1
const ATTACK_ZONE_INACTIVE_FRAME := 3

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_zone: Area2D = $AttackZone
@onready var attack_zone_shape: CollisionShape2D = $AttackZone/CollisionShape2D

var active_attack := false
var hit_bodies := {}


func _ready() -> void:
	add_to_group("player")
	attack_zone.body_entered.connect(_on_attack_zone_body_entered)
	_set_attack_zone_active(false)


func _physics_process(_delta: float) -> void:
	if animated_sprite_2d.animation in ATTACK_ANIMATIONS and animated_sprite_2d.is_playing():
		velocity = Vector2.ZERO
		_update_attack_zone()
		_damage_overlapping_sheep()
		move_and_slide()
		return

	if active_attack:
		_finish_attack()

	if Input.is_action_pressed("shield"):
		velocity = Vector2.ZERO
		animated_sprite_2d.play("shield")
		move_and_slide()
		return

	if Input.is_action_just_pressed("attack_1"):
		velocity = Vector2.ZERO
		_start_attack(&"attack1")
		move_and_slide()
		return

	if Input.is_action_just_pressed("attack_2"):
		velocity = Vector2.ZERO
		_start_attack(&"attack2")
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
		attack_zone.scale.x = -1.0
	elif input_direction.x > 0.0:
		animated_sprite_2d.flip_h = false
		attack_zone.scale.x = 1.0

	move_and_slide()


func _start_attack(animation_name: StringName) -> void:
	active_attack = true
	hit_bodies.clear()
	animated_sprite_2d.play(animation_name)
	_update_attack_zone()
	_play_sfx(SWORD_SFX)


func _update_attack_zone() -> void:
	if animated_sprite_2d.animation not in ATTACK_ANIMATIONS or not animated_sprite_2d.is_playing():
		_finish_attack()
		return

	var frame := animated_sprite_2d.frame
	var zone_active := frame >= ATTACK_ZONE_ACTIVE_FRAME and frame <= ATTACK_ZONE_INACTIVE_FRAME
	_set_attack_zone_active(zone_active)


func _set_attack_zone_active(enabled: bool) -> void:
	attack_zone_shape.disabled = not enabled


func _finish_attack() -> void:
	active_attack = false
	hit_bodies.clear()
	_set_attack_zone_active(false)


func _damage_overlapping_sheep() -> void:
	if not active_attack or attack_zone_shape.disabled:
		return

	for body in attack_zone.get_overlapping_bodies():
		_try_damage_body(body)


func _on_attack_zone_body_entered(body: Node2D) -> void:
	_try_damage_body(body)


func _try_damage_body(body: Node2D) -> void:
	if not active_attack or attack_zone_shape.disabled:
		return
	if not body.is_in_group("sheep") or not body.has_method("take_damage"):
		return
	if hit_bodies.has(body.get_instance_id()):
		return

	hit_bodies[body.get_instance_id()] = true
	body.take_damage(ATTACK_DAMAGE, global_position)


func _play_sfx(stream: AudioStream) -> void:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	add_child(player)
	player.global_position = global_position
	player.play()
	player.finished.connect(player.queue_free)
