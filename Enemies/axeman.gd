extends CharacterBody2D


signal health_changed(current: int, maximum: int)
signal died
signal landed

const SPEED = 130.0
const MOVE_TARGET_RANGE = 24.0
const ATTACK_COOLDOWN = 1
const MAX_HEALTH = 180
const SPAWN_FALL_SPEED_LIMIT = 900.0
const HURT_PARTICLE_LIFETIME = 0.56
const DAMAGE_POPUP_LIFETIME = 0.55
const ATTACK_CHOICES := [
	&"attack1_melee",
	&"attack1_jump",
	&"attack2",
	&"attack3_melee",
	&"attack3_jump",
]
const STATE_DURATIONS := {
	&"attack1": 0.6,
	&"attack2": 0.9,
	&"attack3": 1.0,
	&"hurt": 0.3,
	&"death": 0.3,
}
const ATTACK_DATA := {
	&"attack1_melee": {
		"animation": &"attack1",
		"damage": 10,
		"hit_time": 0.42,
		"min_range": 0.0,
		"range": 132.0,
	},
	&"attack1_jump": {
		"animation": &"attack1",
		"damage": 12,
		"hit_time": 0.42,
		"min_range": 42.0,
		"range": 132.0,
		"jump_velocity": -365.0,
		"jump_gravity_scale": 1.1,
		"jump_speed": 210.0,
		"air_control": 920.0,
		"dive_gravity_scale": 1.5,
	},
	&"attack2": {
		"animation": &"attack2",
		"damage": 14,
		"hit_time": 0.32,
		"min_range": 0.0,
		"range": 132.0,
		"move_speed": 155.0,
	},
	&"attack3_melee": {
		"animation": &"attack3",
		"damage": 18,
		"hit_time": 0.56,
		"min_range": 0.0,
		"range": 156.0,
	},
	&"attack3_jump": {
		"animation": &"attack3",
		"damage": 20,
		"hit_time": 0.56,
		"min_range": 88.0,
		"range": 180.0,
		"jump_velocity": -470.0,
		"jump_gravity_scale": 0.95,
		"jump_speed": 250.0,
		"air_control": 780.0,
		"dive_gravity_scale": 2.05,
	},
}

var gravity := ProjectSettings.get_setting("physics/2d/default_gravity") as float
var current_health := MAX_HEALTH
var is_attack1 := false
var is_attack2 := false
var is_attack3 := false
var is_idle := true
var is_moving := false
var is_hurt := false
var is_dead := false
var battle_active := true
var is_spawning := false
var action_timer := 0.0
var attack_cooldown := 0.0
var active_attack: StringName = &""
var attack_has_hit := false
var attack_sfx_played := false
var current_attack_damage := 0
var attack_target_x := 0.0
var queued_attack: StringName = &""

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var attack_zone: Area2D = $AttackZone


func _ready() -> void:
	add_to_group("enemies")
	animation_tree.active = true
	attack_zone.body_entered.connect(_on_attack_zone_body_entered)
	_set_facing(animated_sprite_2d.flip_h)
	_emit_health_changed()
	visible = battle_active
	_update_animation_conditions()


func _physics_process(delta: float) -> void:
	attack_cooldown = max(attack_cooldown - delta, 0.0)
	var uses_custom_attack_motion := _uses_custom_attack_motion()

	if is_spawning:
		_process_spawn_fall(delta)
		return

	if not battle_active:
		return

	if not is_on_floor() and not uses_custom_attack_motion:
		velocity.y = minf(velocity.y + gravity * delta, SPAWN_FALL_SPEED_LIMIT)

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

	var player := _get_player()
	if player == null or not player.has_method("take_damage") or player.get("is_dead"):
		velocity.x = 0.0
		is_moving = false
		is_idle = true
		_update_animation_conditions()
		move_and_slide()
		return

	var distance_x := player.global_position.x - global_position.x
	if active_attack == StringName():
		_set_facing(distance_x < 0.0)
	var target_distance := absf(distance_x)

	if attack_cooldown <= 0.0 and queued_attack == StringName():
		queued_attack = _pick_random_attack()

	if queued_attack != StringName():
		var attack_info: Dictionary = ATTACK_DATA[queued_attack]
		var min_attack_range: float = float(attack_info["min_range"])
		var max_attack_range: float = float(attack_info["range"])
		if target_distance >= min_attack_range and target_distance <= max_attack_range:
			_trigger_attack(queued_attack)
			return

		var move_direction: float = sign(distance_x)
		if target_distance < min_attack_range:
			move_direction *= -1.0
		velocity.x = move_direction * SPEED if not is_zero_approx(move_direction) else 0.0
	else:
		if target_distance > MOVE_TARGET_RANGE:
			velocity.x = sign(distance_x) * SPEED
		else:
			velocity.x = 0.0

	is_moving = not is_zero_approx(velocity.x)
	is_idle = not is_moving
	_update_animation_conditions()
	move_and_slide()


func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return

	current_health = max(current_health - amount, 0)
	_emit_health_changed()
	velocity.x = sign(global_position.x - source_position.x) * 90.0
	_spawn_hurt_particles(source_position)
	_spawn_damage_popup(amount)
	_play_sfx(&"enemy_hurt", global_position, randf_range(0.92, 1.02), -2.5)

	if current_health == 0:
		_die()
		return

	active_attack = &""
	attack_has_hit = false
	attack_sfx_played = false
	current_attack_damage = 0
	attack_target_x = global_position.x
	queued_attack = &""
	action_timer = STATE_DURATIONS[&"hurt"]
	is_hurt = true
	is_idle = false
	is_moving = false
	_reset_attack_flags()
	state_machine.travel(&"hurt")
	_update_animation_conditions()


func _process_attack(delta: float) -> void:
	action_timer -= delta
	var attack_info: Dictionary = ATTACK_DATA[active_attack]
	var animation_state: StringName = attack_info["animation"]

	if attack_info.has("jump_velocity"):
		_process_jump_attack(delta, attack_info)
	elif attack_info.has("move_speed"):
		_process_advancing_attack(delta, attack_info)
	else:
		velocity.x = 0.0

	if not attack_sfx_played:
		var trigger_time: float = float(STATE_DURATIONS[animation_state]) - float(attack_info["hit_time"])
		if action_timer <= trigger_time:
			attack_sfx_played = true
			_play_sfx(_get_attack_sfx_cue(animation_state), global_position, randf_range(0.92, 1.04), -4.0)

	move_and_slide()

	var can_finish_attack := action_timer <= 0.0
	if can_finish_attack and attack_info.has("jump_velocity") and not is_on_floor():
		can_finish_attack = false

	if can_finish_attack:
		active_attack = &""
		attack_has_hit = false
		attack_sfx_played = false
		current_attack_damage = 0
		attack_target_x = global_position.x
		queued_attack = &""
		velocity.x = 0.0
		_reset_attack_flags()
		is_idle = true
		is_moving = false
		_update_animation_conditions()
		state_machine.travel(&"idle")


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
	var attack_info: Dictionary = ATTACK_DATA[state]
	var player := _get_player()
	if player != null:
		attack_target_x = player.global_position.x
	else:
		attack_target_x = global_position.x

	active_attack = state
	queued_attack = &""
	attack_has_hit = false
	attack_sfx_played = false
	current_attack_damage = attack_info["damage"]
	var animation_state: StringName = attack_info["animation"]
	action_timer = STATE_DURATIONS[animation_state]
	attack_cooldown = STATE_DURATIONS[animation_state] + ATTACK_COOLDOWN
	is_idle = false
	is_moving = false
	is_attack1 = animation_state == &"attack1"
	is_attack2 = animation_state == &"attack2"
	is_attack3 = animation_state == &"attack3"
	_begin_attack_movement(attack_info)
	_update_animation_conditions()
	state_machine.travel(animation_state)


func _begin_attack_movement(attack_info: Dictionary) -> void:
	if attack_info.has("jump_velocity"):
		var horizontal_offset: float = attack_target_x - global_position.x
		var desired_direction: float = sign(horizontal_offset)
		if is_zero_approx(desired_direction):
			desired_direction = -1.0 if animated_sprite_2d.flip_h else 1.0

		_set_facing(desired_direction < 0.0)
		velocity.x = desired_direction * float(attack_info["jump_speed"])
		velocity.y = float(attack_info["jump_velocity"])
		return

	if attack_info.has("move_speed"):
		var forward_direction: float = -1.0 if animated_sprite_2d.flip_h else 1.0
		velocity.x = forward_direction * float(attack_info["move_speed"])
		return

	velocity.x = 0.0


func _process_jump_attack(delta: float, attack_info: Dictionary) -> void:
	var distance_to_target: float = attack_target_x - global_position.x
	var desired_direction: float = sign(distance_to_target)
	if is_zero_approx(desired_direction):
		desired_direction = -1.0 if animated_sprite_2d.flip_h else 1.0

	var desired_speed: float = desired_direction * float(attack_info["jump_speed"])
	velocity.x = move_toward(velocity.x, desired_speed, float(attack_info["air_control"]) * delta)

	var gravity_scale: float = float(attack_info["jump_gravity_scale"])
	if velocity.y > 0.0:
		gravity_scale = float(attack_info["dive_gravity_scale"])
	velocity.y = minf(velocity.y + gravity * gravity_scale * delta, SPAWN_FALL_SPEED_LIMIT)

	if is_on_floor() and velocity.y >= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, float(attack_info["air_control"]) * delta)


func _process_advancing_attack(delta: float, attack_info: Dictionary) -> void:
	var forward_direction: float = -1.0 if animated_sprite_2d.flip_h else 1.0
	velocity.x = forward_direction * float(attack_info["move_speed"])
	velocity.y = 0.0 if is_on_floor() else minf(velocity.y + gravity * 0.85 * delta, SPAWN_FALL_SPEED_LIMIT)


func _die() -> void:
	is_dead = true
	is_hurt = false
	active_attack = &""
	attack_has_hit = false
	attack_sfx_played = false
	current_attack_damage = 0
	attack_target_x = global_position.x
	queued_attack = &""
	velocity.x = 0.0
	_reset_attack_flags()
	is_idle = false
	is_moving = false
	_update_animation_conditions()
	state_machine.travel(&"death")
	died.emit()


func _pick_random_attack() -> StringName:
	return ATTACK_CHOICES[randi() % ATTACK_CHOICES.size()]


func _pick_attack_for_distance(distance: float) -> StringName:
	var available_attacks: Array[StringName] = []

	for attack_state in ATTACK_CHOICES:
		var attack_info: Dictionary = ATTACK_DATA[attack_state]
		if distance >= attack_info["min_range"] and distance <= attack_info["range"]:
			available_attacks.append(attack_state)

	if available_attacks.is_empty():
		return StringName()

	return available_attacks[randi() % available_attacks.size()]


func _get_player() -> CharacterBody2D:
	return get_tree().get_first_node_in_group("player") as CharacterBody2D


func _reset_attack_flags() -> void:
	is_attack1 = false
	is_attack2 = false
	is_attack3 = false


func _update_animation_conditions() -> void:
	animation_tree.set("parameters/conditions/isAttack1", is_attack1)
	animation_tree.set("parameters/conditions/isAttack2", is_attack2)
	animation_tree.set("parameters/conditions/isAttack3", is_attack3)
	animation_tree.set("parameters/conditions/isDead", is_dead)
	animation_tree.set("parameters/conditions/isHurt", is_hurt)
	animation_tree.set("parameters/conditions/isIdle", is_idle)
	animation_tree.set("parameters/conditions/isMoving", is_moving)


func _emit_health_changed() -> void:
	health_changed.emit(current_health, MAX_HEALTH)


func get_max_health() -> int:
	return MAX_HEALTH


func set_battle_active(active: bool) -> void:
	battle_active = active
	visible = active or is_spawning
	if not active:
		velocity = Vector2.ZERO
		active_attack = &""
		attack_has_hit = false
		attack_sfx_played = false
		current_attack_damage = 0
		attack_target_x = global_position.x
		queued_attack = &""
		attack_cooldown = 0.0
		is_hurt = false
		is_idle = true
		is_moving = false
		_reset_attack_flags()
		_update_animation_conditions()


func begin_battle() -> void:
	battle_active = true
	is_idle = true
	is_moving = false
	_update_animation_conditions()


func start_spawn_fall(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	is_spawning = true
	battle_active = false
	visible = true
	is_idle = true
	is_moving = false
	is_hurt = false
	is_dead = false
	attack_target_x = global_position.x
	queued_attack = &""
	attack_sfx_played = false
	_reset_attack_flags()
	_update_animation_conditions()
	state_machine.travel(&"idle")


func _process_spawn_fall(delta: float) -> void:
	var player := _get_player()
	if player != null:
		_set_facing(player.global_position.x < global_position.x)

	velocity.y = minf(velocity.y + gravity * 1.35 * delta, SPAWN_FALL_SPEED_LIMIT)
	move_and_slide()

	if is_on_floor():
		velocity = Vector2.ZERO
		is_spawning = false
		battle_active = false
		landed.emit()


func register_blocked_target(target: Node) -> void:
	if not _can_damage_with_active_attack():
		return
	if target == _get_player():
		attack_has_hit = true


func _can_damage_with_active_attack() -> bool:
	return active_attack != StringName() and not attack_has_hit and current_attack_damage > 0


func _uses_custom_attack_motion() -> bool:
	if active_attack == StringName() or not ATTACK_DATA.has(active_attack):
		return false

	var attack_info: Dictionary = ATTACK_DATA[active_attack]
	return attack_info.has("jump_velocity") or attack_info.has("move_speed")


func _set_facing(face_left: bool) -> void:
	animated_sprite_2d.flip_h = face_left
	attack_zone.scale.x = -1.0 if face_left else 1.0


func _play_sfx(cue: StringName, position: Vector2, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var manager := get_tree().get_first_node_in_group("sfx_manager")
	if manager != null and manager.has_method("play_cue"):
		manager.play_cue(cue, position, pitch_scale, volume_db)


func _get_attack_sfx_cue(animation_state: StringName) -> StringName:
	match animation_state:
		&"attack1":
			return &"enemy_attack1"
		&"attack2":
			return &"enemy_attack2"
		&"attack3":
			return &"enemy_attack3"
		_:
			return &"enemy_attack1"


func _spawn_hurt_particles(source_position: Vector2) -> void:
	var effect_parent := get_parent()
	if effect_parent == null:
		return

	var burst_root := Node2D.new()
	burst_root.z_index = animated_sprite_2d.z_index + 2
	effect_parent.add_child(burst_root)
	burst_root.global_position = global_position + Vector2(0.0, -26.0)

	var base_direction := (global_position - source_position).normalized()
	if base_direction == Vector2.ZERO:
		base_direction = Vector2.LEFT if animated_sprite_2d.flip_h else Vector2.RIGHT

	for i in range(10):
		var shard := Polygon2D.new()
		shard.polygon = PackedVector2Array([
			Vector2(0, -3),
			Vector2(3, 0),
			Vector2(0, 3),
			Vector2(-3, 0),
		])
		shard.modulate = Color(
			randf_range(0.62, 0.8),
			randf_range(0.16, 0.24),
			randf_range(0.1, 0.14),
			randf_range(0.92, 1.0)
		)

		var spread := randf_range(-1.15, 1.15)
		var direction := base_direction.rotated(spread).normalized()
		shard.rotation = randf_range(-0.9, 0.9)
		shard.position = direction * randf_range(10.0, 24.0)
		shard.scale = Vector2.ONE * randf_range(4.8, 8.0)
		burst_root.add_child(shard)

		var distance := randf_range(96.0, 172.0)
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", shard.position + direction * distance + Vector2(randf_range(-20.0, 20.0), randf_range(-24.0, 32.0)), HURT_PARTICLE_LIFETIME)
		tween.tween_property(shard, "scale", Vector2(0.6, 0.6), HURT_PARTICLE_LIFETIME)
		tween.tween_property(shard, "modulate:a", 0.0, HURT_PARTICLE_LIFETIME)

	var cleanup_tween := burst_root.create_tween()
	cleanup_tween.tween_interval(HURT_PARTICLE_LIFETIME)
	cleanup_tween.tween_callback(burst_root.queue_free)


func _spawn_damage_popup(amount: int) -> void:
	var effect_parent := get_parent()
	if effect_parent == null:
		return

	var popup := Label.new()
	popup.text = str(amount)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	popup.add_theme_font_size_override("font_size", 28 + mini(amount / 3, 12))
	popup.modulate = _get_damage_popup_color(amount)
	popup.z_index = animated_sprite_2d.z_index + 3
	effect_parent.add_child(popup)
	popup.global_position = global_position + Vector2(randf_range(-14.0, 14.0), -72.0 + randf_range(-10.0, 6.0))

	var drift := Vector2(randf_range(-22.0, 22.0), randf_range(-86.0, -64.0))
	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "global_position", popup.global_position + drift, DAMAGE_POPUP_LIFETIME)
	tween.tween_property(popup, "modulate:a", 0.0, DAMAGE_POPUP_LIFETIME)
	tween.tween_property(popup, "scale", Vector2(1.08, 1.08), 0.12)
	tween.chain().tween_property(popup, "scale", Vector2(0.9, 0.9), DAMAGE_POPUP_LIFETIME - 0.12)
	tween.tween_callback(popup.queue_free)


func _get_damage_popup_color(amount: int) -> Color:
	var t := clampf((float(amount) - 10.0) / 14.0, 0.0, 1.0)
	return Color(
		lerpf(1.0, 0.9, t),
		lerpf(0.72, 0.18, t),
		lerpf(0.2, 0.16, t),
		1.0
	)


func _on_attack_zone_body_entered(body: Node) -> void:
	if not _can_damage_with_active_attack():
		return
	if not body.is_in_group("player") or not body.has_method("take_damage"):
		return

	attack_has_hit = true
	body.take_damage(current_attack_damage, global_position)
