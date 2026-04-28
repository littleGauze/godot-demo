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
const DAMAGE_INVULNERABILITY_DURATION = 1.0
const HURT_PARTICLE_LIFETIME = 0.52
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
var damage_invulnerability_timer := 0.0
var active_attack: StringName = &""
var attack_has_hit := false
var attack_sfx_played := false
var current_attack_damage := 0
var blocked_attack_areas: Dictionary = {}

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var attack_zone: Area2D = $AttackZone
@onready var shield: Area2D = $Shield
@onready var shield_shape: CollisionShape2D = $Shield/CollisionShape2D


func _ready() -> void:
	add_to_group("player")
	animation_tree.active = true
	attack_zone.body_entered.connect(_on_attack_zone_body_entered)
	shield.area_entered.connect(_on_shield_area_entered)
	shield.area_exited.connect(_on_shield_area_exited)
	_set_facing(animated_sprite_2d.flip_h)
	_emit_health_changed()
	_update_animation_conditions()


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	var can_jump := is_on_floor() and not is_block and not _has_pending_attack() and not is_hurt and not is_dead
	var can_dash := not is_dead and not is_hurt and not is_block and not _has_pending_attack() and dash_cooldown_timer <= 0.0
	var gravity_scale := FALL_GRAVITY_MULTIPLIER if velocity.y > 0.0 else 1.0
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	damage_invulnerability_timer = maxf(damage_invulnerability_timer - delta, 0.0)

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
		_process_block(delta)
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
		_set_facing(direction < 0)

	move_and_slide()


func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if is_dead or is_dashing or damage_invulnerability_timer > 0.0:
		return
	if is_block and _is_source_in_front(source_position):
		velocity.x = sign(global_position.x - source_position.x) * 140.0
		_play_sfx(&"block", global_position, randf_range(0.96, 1.06), -1.5)
		return

	current_health = max(current_health - amount, 0)
	_emit_health_changed()
	velocity.x = sign(global_position.x - source_position.x) * 110.0
	_spawn_hurt_particles(source_position)
	_play_sfx(&"player_hurt", global_position, randf_range(0.97, 1.05), -2.0)

	if current_health == 0:
		_die()
		return

	is_hurt = true
	is_block = false
	active_attack = &""
	attack_has_hit = false
	attack_sfx_played = false
	current_attack_damage = 0
	damage_invulnerability_timer = DAMAGE_INVULNERABILITY_DURATION
	action_timer = STATE_DURATIONS[&"hurt"]
	is_idle = false
	is_moving = false
	_clear_blocked_attack_areas()
	_reset_attack_flags()
	_update_animation_conditions()
	state_machine.travel(&"hurt")


func _process_attack(delta: float) -> void:
	action_timer -= delta
	var attack_info: Dictionary = ATTACK_DATA[active_attack]
	if is_on_floor():
		velocity.x = 0.0
	else:
		var direction := Input.get_axis("ui_left", "ui_right")
		velocity.x = direction * SPEED
		if not is_zero_approx(direction):
			_set_facing(direction < 0)

	if not attack_sfx_played:
		var trigger_time: float = float(STATE_DURATIONS[active_attack]) - float(attack_info["hit_time"])
		if action_timer <= trigger_time:
			attack_sfx_played = true
			_play_sfx(_get_attack_sfx_cue(active_attack), global_position, randf_range(0.96, 1.08), -4.0)

	move_and_slide()

	if action_timer <= 0.0:
		active_attack = &""
		attack_has_hit = false
		attack_sfx_played = false
		current_attack_damage = 0
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


func _process_block(delta: float) -> void:
	velocity.x = 0.0
	if not Input.is_action_pressed("block"):
		is_block = false
		_clear_blocked_attack_areas()
		is_idle = true
		is_moving = false
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
	attack_sfx_played = false
	current_attack_damage = ATTACK_DATA[state]["damage"]
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

func _die() -> void:
	is_dead = true
	is_hurt = false
	is_block = false
	is_dashing = false
	_set_dash_enemy_collision_enabled(true)
	active_attack = &""
	attack_has_hit = false
	attack_sfx_played = false
	current_attack_damage = 0
	velocity.x = 0.0
	_clear_blocked_attack_areas()
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
		_set_facing(dash_direction < 0.0)


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
	var spawn_points: Array[Vector2] = []
	var base_offsets := [
		Vector2(-38, -16),
		Vector2(34, -24),
		Vector2(-30, 20),
		Vector2(42, 12),
		Vector2(-12, -34),
		Vector2(18, 30),
		Vector2(-46, 4),
		Vector2(50, -6),
		Vector2(-6, 42),
		Vector2(28, -40),
		Vector2(-24, -2),
		Vector2(12, 16),
	]

	for i in range(mini(DASH_READY_PARTICLE_COUNT, base_offsets.size())):
		spawn_points.append(center + base_offsets[i] * (DASH_READY_PARTICLE_RADIUS / 30.0))

	for i in range(spawn_points.size()):
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


func _set_facing(face_left: bool) -> void:
	animated_sprite_2d.flip_h = face_left
	var mirror_scale := -1.0 if face_left else 1.0
	attack_zone.scale.x = mirror_scale
	shield.scale.x = mirror_scale


func _clear_blocked_attack_areas() -> void:
	blocked_attack_areas.clear()


func _can_damage_with_active_attack() -> bool:
	return active_attack != StringName() and not attack_has_hit and current_attack_damage > 0


func _on_attack_zone_body_entered(body: Node) -> void:
	if not _can_damage_with_active_attack():
		return
	if not body.is_in_group("enemies") or not body.has_method("take_damage"):
		return

	attack_has_hit = true
	body.take_damage(current_attack_damage, global_position)


func _on_shield_area_entered(area: Area2D) -> void:
	if not is_block or is_dead:
		return

	var attacker := area.get_parent() as Node2D
	if attacker == null or not attacker.is_in_group("enemies"):
		return
	if not _is_source_in_front(attacker.global_position):
		return
	_spawn_block_spark(area)


func _on_shield_area_exited(area: Area2D) -> void:
	blocked_attack_areas.erase(area.get_instance_id())


func _spawn_block_spark(area: Area2D) -> void:
	var effect_parent := get_parent()
	if effect_parent == null:
		return

	var spark_root := Node2D.new()
	effect_parent.add_child(spark_root)

	var shield_center := shield_shape.global_position
	var area_center := area.global_position
	var impact_position := shield_center.lerp(area_center, 0.45)
	var impact_normal := (shield_center - area_center).normalized()
	if impact_normal == Vector2.ZERO:
		impact_normal = Vector2.LEFT if animated_sprite_2d.flip_h else Vector2.RIGHT

	spark_root.global_position = impact_position
	spark_root.z_index = animated_sprite_2d.z_index + 2

	var shard_count := 7
	for i in range(shard_count):
		var spark := Polygon2D.new()
		var length := randf_range(14.0, 30.0)
		var width := randf_range(4.0, 8.0)
		spark.polygon = PackedVector2Array([
			Vector2(-width * 0.5, -1.0),
			Vector2(length, 0.0),
			Vector2(-width * 0.5, 1.0),
		])
		spark.modulate = Color(
			randf_range(0.95, 1.0),
			randf_range(0.72, 0.88),
			randf_range(0.18, 0.32),
			1.0
		)

		var angle_offset := randf_range(-0.6, 0.6)
		var direction := impact_normal.rotated(angle_offset).normalized()
		spark.rotation = direction.angle()
		spark.position = direction * randf_range(4.0, 16.0)
		spark.scale = Vector2.ONE * randf_range(1.8, 2.3)
		spark_root.add_child(spark)

		var distance := randf_range(36.0, 68.0)
		var tween := spark.create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", spark.position + direction * distance, 0.18)
		tween.tween_property(spark, "scale", Vector2(0.4, 0.4), 0.18)
		tween.tween_property(spark, "modulate:a", 0.0, 0.18)

	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([
		Vector2(-10, 0),
		Vector2(0, -6),
		Vector2(22, 0),
		Vector2(0, 6),
	])
	flash.rotation = impact_normal.angle()
	flash.modulate = Color(1.0, 0.95, 0.75, 0.9)
	spark_root.add_child(flash)

	var flash_tween := flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(3.6, 2.8), 0.08)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.08)

	var cleanup_tween := spark_root.create_tween()
	cleanup_tween.tween_interval(0.22)
	cleanup_tween.tween_callback(spark_root.queue_free)


func _spawn_hurt_particles(source_position: Vector2) -> void:
	var effect_parent := get_parent()
	if effect_parent == null:
		return

	var burst_root := Node2D.new()
	burst_root.z_index = animated_sprite_2d.z_index + 2
	effect_parent.add_child(burst_root)
	burst_root.global_position = global_position + Vector2(0.0, -24.0)

	var base_direction := (global_position - source_position).normalized()
	if base_direction == Vector2.ZERO:
		base_direction = Vector2.RIGHT if animated_sprite_2d.flip_h else Vector2.LEFT

	var burst_count := 9
	for i in range(burst_count):
		var shard := Polygon2D.new()
		shard.polygon = PackedVector2Array([
			Vector2(0, -3),
			Vector2(3, 0),
			Vector2(0, 3),
			Vector2(-3, 0),
		])
		shard.modulate = Color(
			randf_range(0.58, 0.75),
			randf_range(0.16, 0.24),
			randf_range(0.1, 0.14),
			randf_range(0.9, 1.0)
		)

		var spread := randf_range(-1.05, 1.05)
		var direction := base_direction.rotated(spread).normalized()
		shard.rotation = randf_range(-0.8, 0.8)
		shard.position = direction * randf_range(10.0, 22.0)
		shard.scale = Vector2.ONE * randf_range(4.4, 7.6)
		burst_root.add_child(shard)

		var distance := randf_range(90.0, 160.0)
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", shard.position + direction * distance + Vector2(randf_range(-18.0, 18.0), randf_range(-22.0, 28.0)), HURT_PARTICLE_LIFETIME)
		tween.tween_property(shard, "scale", Vector2(0.56, 0.56), HURT_PARTICLE_LIFETIME)
		tween.tween_property(shard, "modulate:a", 0.0, HURT_PARTICLE_LIFETIME)

	var cleanup_tween := burst_root.create_tween()
	cleanup_tween.tween_interval(HURT_PARTICLE_LIFETIME)
	cleanup_tween.tween_callback(burst_root.queue_free)


func _play_sfx(cue: StringName, position: Vector2, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var manager := get_tree().get_first_node_in_group("sfx_manager")
	if manager != null and manager.has_method("play_cue"):
		manager.play_cue(cue, position, pitch_scale, volume_db)


func _get_attack_sfx_cue(state: StringName) -> StringName:
	match state:
		&"attack1":
			return &"player_attack1"
		&"attack2":
			return &"player_attack2"
		&"attack3":
			return &"player_attack3"
		_:
			return &"player_attack1"


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
