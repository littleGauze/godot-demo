extends CharacterBody2D


signal health_changed(current: int, maximum: int)
signal died

const SPEED = 300.0
const JUMP_VELOCITY = -550.0
const FALL_GRAVITY_MULTIPLIER = 3.0
const DASH_SPEED = 980.0
const DASH_DURATION = 0.2
const DASH_COOLDOWN = 2.0
const DASH_GHOST_INTERVAL = 0.03
const DASH_GHOST_LIFETIME = 0.18
const DASH_READY_PARTICLE_COUNT = 12
const DASH_READY_PARTICLE_RADIUS = 30.0
const DASH_READY_PARTICLE_DURATION = 0.22
const MAX_HEALTH = 100
const ATTACK_RANGE = 80.0
const ATTACK_STATES := [&"attack1", &"attack2", &"attack3"]
const ACTION_STATES := [&"attack1", &"attack2", &"attack3", &"block"]
const STATE_DURATIONS := {
	&"attack1": 0.3,
	&"attack2": 0.45,
	&"attack3": 0.5,
	&"block": 0.3,
	&"hurt": 0.3,
	&"death": 0.3,
}
const ATTACK_DATA := {
	&"attack1": {"damage": 14, "hit_time": 0.11},
	&"attack2": {"damage": 18, "hit_time": 0.16},
	&"attack3": {"damage": 24, "hit_time": 0.2},
}

var gravity := ProjectSettings.get_setting("physics/2d/default_gravity") as float
var current_health := MAX_HEALTH
var is_attack1 := false
var is_attack2 := false
var is_attack3 := false
var is_block := false
var is_idle := true
var is_moving := false
var is_hurt := false
var is_dead := false
var is_dashing := false
var action_timer := 0.0
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_direction := 1.0
var dash_ghost_timer := 0.0
var dash_ready_announced := true
var active_attack: StringName = &""
var attack_has_hit := false

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")


func _ready() -> void:
	add_to_group("player")
	animation_tree.active = true
	_emit_health_changed()
	_update_animation_conditions()


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	var can_jump := is_on_floor() and not is_block and not _has_pending_attack() and not is_hurt and not is_dead
	var can_dash := not is_dead and not is_hurt and not is_block and not _has_pending_attack() and dash_cooldown_timer <= 0.0
	var gravity_scale := FALL_GRAVITY_MULTIPLIER if velocity.y > 0.0 else 1.0
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)

	if not dash_ready_announced and dash_cooldown_timer <= 0.0:
		dash_ready_announced = true
		_spawn_dash_ready_particles()

	if Input.is_action_just_pressed("dash") and can_dash:
		_start_dash(direction)

	if is_dashing:
		_process_dash(delta)
		return

	if not is_on_floor():
		velocity.y += gravity * gravity_scale * delta
	elif Input.is_action_just_pressed("jump") and can_jump:
		velocity.y = JUMP_VELOCITY

	if is_dead:
		velocity.x = 0.0
		move_and_slide()
		return

	if is_hurt:
		_process_hurt(delta)
		return

	if active_attack != StringName():
		_process_attack(delta)
		return

	if is_block:
		_process_block()
		return

	if Input.is_action_just_pressed("block"):
		_trigger_block()
		return

	if Input.is_action_just_pressed("attack_1"):
		_trigger_attack(&"attack1")
		return

	if Input.is_action_just_pressed("attack_2"):
		_trigger_attack(&"attack2")
		return

	if Input.is_action_just_pressed("attack_3"):
		_trigger_attack(&"attack3")
		return

	is_moving = not is_zero_approx(direction)
	is_idle = is_on_floor() and not is_moving
	velocity.x = direction * SPEED
	_update_animation_conditions()

	if not is_zero_approx(direction):
		animated_sprite_2d.flip_h = direction < 0

	move_and_slide()


func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if is_dead or is_dashing:
		return

	if is_block and _is_source_in_front(source_position):
		return

	current_health = max(current_health - amount, 0)
	_emit_health_changed()
	velocity.x = sign(global_position.x - source_position.x) * 110.0

	if current_health == 0:
		_die()
		return

	is_hurt = true
	is_block = false
	active_attack = &""
	attack_has_hit = false
	action_timer = STATE_DURATIONS[&"hurt"]
	is_idle = false
	is_moving = false
	_reset_attack_flags()
	_update_animation_conditions()
	state_machine.travel(&"hurt")


func _process_attack(delta: float) -> void:
	action_timer -= delta
	if is_on_floor():
		velocity.x = 0.0
	else:
		var direction := Input.get_axis("ui_left", "ui_right")
		velocity.x = direction * SPEED
		if not is_zero_approx(direction):
			animated_sprite_2d.flip_h = direction < 0

	if not attack_has_hit:
		var attack_info: Dictionary = ATTACK_DATA[active_attack]
		if action_timer <= STATE_DURATIONS[active_attack] - attack_info["hit_time"]:
			attack_has_hit = true
			_apply_attack_hit(attack_info["damage"])

	move_and_slide()

	if action_timer <= 0.0:
		active_attack = &""
		attack_has_hit = false
		_reset_attack_flags()
		is_idle = true
		is_moving = false
		_update_animation_conditions()
		state_machine.travel(&"idle")


func _process_dash(delta: float) -> void:
	dash_timer = maxf(dash_timer - delta, 0.0)
	dash_ghost_timer = maxf(dash_ghost_timer - delta, 0.0)
	velocity.x = dash_direction * DASH_SPEED
	velocity.y = 0.0

	if dash_ghost_timer <= 0.0:
		dash_ghost_timer = DASH_GHOST_INTERVAL
		_spawn_dash_ghost()

	move_and_slide()

	if dash_timer <= 0.0:
		is_dashing = false
		_set_dash_enemy_collision_enabled(true)
		velocity.x = 0.0
		is_moving = false
		is_idle = is_on_floor()
		_update_animation_conditions()


func _process_block() -> void:
	velocity.x = 0.0
	if not Input.is_action_pressed("block"):
		is_block = false
		is_idle = true
		_update_animation_conditions()
		state_machine.travel(&"idle")

	move_and_slide()


func _process_hurt(delta: float) -> void:
	action_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, SPEED * delta)
	move_and_slide()

	if action_timer <= 0.0:
		is_hurt = false
		is_idle = true
		is_moving = false
		_update_animation_conditions()
		state_machine.travel(&"idle")


func _trigger_attack(state: StringName) -> void:
	if is_block or is_hurt or is_dead or is_dashing:
		return

	active_attack = state
	attack_has_hit = false
	action_timer = STATE_DURATIONS[state]
	is_attack1 = state == &"attack1"
	is_attack2 = state == &"attack2"
	is_attack3 = state == &"attack3"
	is_idle = false
	is_moving = false
	_update_animation_conditions()
	state_machine.travel(state)


func _trigger_block() -> void:
	if is_hurt or is_dead or _has_pending_attack() or not is_on_floor() or is_dashing:
		return

	is_block = true
	action_timer = STATE_DURATIONS[&"block"]
	is_idle = false
	is_moving = false
	_reset_attack_flags()
	_update_animation_conditions()
	state_machine.travel(&"block")


func _apply_attack_hit(damage: int) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_method("take_damage"):
			continue
		if absf(enemy.global_position.x - global_position.x) > ATTACK_RANGE:
			continue
		if not _is_target_in_front(enemy.global_position):
			continue
		enemy.take_damage(damage, global_position)
		return


func _die() -> void:
	is_dead = true
	is_hurt = false
	is_block = false
	is_dashing = false
	_set_dash_enemy_collision_enabled(true)
	active_attack = &""
	attack_has_hit = false
	velocity.x = 0.0
	_reset_attack_flags()
	is_idle = false
	is_moving = false
	_update_animation_conditions()
	state_machine.travel(&"death")
	died.emit()


func _has_pending_attack() -> bool:
	return active_attack != StringName()


func _start_dash(direction: float) -> void:
	is_dashing = true
	dash_timer = DASH_DURATION
	dash_cooldown_timer = DASH_COOLDOWN
	dash_ghost_timer = 0.0
	dash_ready_announced = false
	_set_dash_enemy_collision_enabled(false)
	dash_direction = direction if not is_zero_approx(direction) else (-1.0 if animated_sprite_2d.flip_h else 1.0)
	is_idle = false
	is_moving = true
	_reset_attack_flags()
	_update_animation_conditions()

	if not is_zero_approx(dash_direction):
		animated_sprite_2d.flip_h = dash_direction < 0.0


func _spawn_dash_ghost() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return

	var frames := animated_sprite_2d.sprite_frames
	if frames == null:
		return

	var frame_texture := frames.get_frame_texture(animated_sprite_2d.animation, animated_sprite_2d.frame)
	if frame_texture == null:
		return

	var ghost := Sprite2D.new()
	ghost.texture = frame_texture
	ghost.global_position = animated_sprite_2d.global_position
	ghost.global_scale = animated_sprite_2d.global_scale
	ghost.flip_h = animated_sprite_2d.flip_h
	ghost.modulate = Color(0.55, 0.85, 1.0, 0.45)
	ghost.z_index = animated_sprite_2d.z_index - 1
	parent_node.add_child(ghost)

	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, DASH_GHOST_LIFETIME)
	tween.tween_callback(ghost.queue_free)


func _spawn_dash_ready_particles() -> void:
	var center := animated_sprite_2d.position
	var side_count := maxi(DASH_READY_PARTICLE_COUNT / 4, 1)
	var vertical_spacing := 12.0
	var horizontal_spacing := 12.0
	var spawn_points: Array[Vector2] = []

	for i in range(side_count):
		var offset_index := float(i - (side_count - 1) * 0.5)
		spawn_points.append(center + Vector2(-DASH_READY_PARTICLE_RADIUS, offset_index * vertical_spacing))
		spawn_points.append(center + Vector2(DASH_READY_PARTICLE_RADIUS, offset_index * vertical_spacing))
		spawn_points.append(center + Vector2(offset_index * horizontal_spacing, -DASH_READY_PARTICLE_RADIUS))
		spawn_points.append(center + Vector2(offset_index * horizontal_spacing, DASH_READY_PARTICLE_RADIUS))

	for i in range(mini(DASH_READY_PARTICLE_COUNT, spawn_points.size())):
		var particle := Polygon2D.new()
		particle.polygon = PackedVector2Array([
			Vector2(0, -3),
			Vector2(3, 0),
			Vector2(0, 3),
			Vector2(-3, 0),
		])
		particle.position = spawn_points[i]
		particle.modulate = Color(0.85, 0.97, 1.0, 0.6)
		particle.z_index = animated_sprite_2d.z_index + 1
		add_child(particle)

		var tween := particle.create_tween()
		tween.tween_property(particle, "position", center, DASH_READY_PARTICLE_DURATION)
		tween.parallel().tween_property(particle, "modulate:a", 0.0, DASH_READY_PARTICLE_DURATION)
		tween.parallel().tween_property(particle, "scale", Vector2(0.35, 0.35), DASH_READY_PARTICLE_DURATION)
		tween.tween_callback(particle.queue_free)


func _set_dash_enemy_collision_enabled(is_enabled: bool) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is PhysicsBody2D:
			var enemy_body := enemy as PhysicsBody2D
			if is_enabled:
				remove_collision_exception_with(enemy_body)
			else:
				add_collision_exception_with(enemy_body)


func _is_target_in_front(target_position: Vector2) -> bool:
	var facing_left := animated_sprite_2d.flip_h
	var target_is_left := target_position.x < global_position.x
	return facing_left == target_is_left


func _is_source_in_front(source_position: Vector2) -> bool:
	return _is_target_in_front(source_position)


func _reset_attack_flags() -> void:
	is_attack1 = false
	is_attack2 = false
	is_attack3 = false


func _update_animation_conditions() -> void:
	animation_tree.set("parameters/conditions/isAttack1", is_attack1)
	animation_tree.set("parameters/conditions/isAttack2", is_attack2)
	animation_tree.set("parameters/conditions/isAttack3", is_attack3)
	animation_tree.set("parameters/conditions/isBlock", is_block)
	animation_tree.set("parameters/conditions/isDead", is_dead)
	animation_tree.set("parameters/conditions/isHurt", is_hurt)
	animation_tree.set("parameters/conditions/isIdle", is_idle)
	animation_tree.set("parameters/conditions/isMoving", is_moving)


func _emit_health_changed() -> void:
	health_changed.emit(current_health, MAX_HEALTH)


func get_max_health() -> int:
	return MAX_HEALTH


func get_dash_cooldown_progress() -> float:
	if DASH_COOLDOWN <= 0.0:
		return 1.0
	return 1.0 - clampf(dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0)
