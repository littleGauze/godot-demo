extends CharacterBody2D


signal health_changed(current: int, maximum: int)
signal died
signal landed

const SPEED = 130.0
const ATTACK_RANGE = 85.0
const MOVE_TARGET_RANGE = 24.0
const ATTACK_COOLDOWN = 2.0
const MAX_HEALTH = 180
const SPAWN_FALL_SPEED_LIMIT = 900.0
const ATTACK_STATES := [&"attack1", &"attack2", &"attack3"]
const STATE_DURATIONS := {
	&"attack1": 0.6,
	&"attack2": 0.9,
	&"attack3": 1.0,
	&"hurt": 0.3,
	&"death": 0.3,
}
const ATTACK_DATA := {
	&"attack1": {"damage": 10, "hit_time": 0.24},
	&"attack2": {"damage": 14, "hit_time": 0.32},
	&"attack3": {"damage": 18, "hit_time": 0.4},
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

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")


func _ready() -> void:
	add_to_group("enemies")
	animation_tree.active = true
	_emit_health_changed()
	visible = battle_active
	_update_animation_conditions()


func _physics_process(delta: float) -> void:
	attack_cooldown = max(attack_cooldown - delta, 0.0)

	if is_spawning:
		_process_spawn_fall(delta)
		return

	if not battle_active:
		return

	if not is_on_floor():
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
	animated_sprite_2d.flip_h = distance_x < 0.0

	if absf(distance_x) <= ATTACK_RANGE and attack_cooldown <= 0.0:
		_trigger_attack(_pick_random_attack())
	else:
		velocity.x = sign(distance_x) * SPEED if absf(distance_x) > MOVE_TARGET_RANGE else 0.0
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

	if current_health == 0:
		_die()
		return

	active_attack = &""
	attack_has_hit = false
	action_timer = STATE_DURATIONS[&"hurt"]
	is_hurt = true
	is_idle = false
	is_moving = false
	_reset_attack_flags()
	state_machine.travel(&"hurt")
	_update_animation_conditions()


func _process_attack(delta: float) -> void:
	action_timer -= delta
	velocity.x = 0.0

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
	active_attack = state
	attack_has_hit = false
	action_timer = STATE_DURATIONS[state]
	attack_cooldown = STATE_DURATIONS[state] + ATTACK_COOLDOWN
	is_idle = false
	is_moving = false
	is_attack1 = state == &"attack1"
	is_attack2 = state == &"attack2"
	is_attack3 = state == &"attack3"
	_update_animation_conditions()
	state_machine.travel(state)


func _apply_attack_hit(damage: int) -> void:
	var player := _get_player()
	if player == null:
		return

	if absf(player.global_position.x - global_position.x) > ATTACK_RANGE:
		return

	var facing_left := animated_sprite_2d.flip_h
	var player_is_left := player.global_position.x < global_position.x
	if facing_left != player_is_left:
		return

	player.take_damage(damage, global_position)


func _die() -> void:
	is_dead = true
	is_hurt = false
	active_attack = &""
	attack_has_hit = false
	velocity.x = 0.0
	_reset_attack_flags()
	is_idle = false
	is_moving = false
	_update_animation_conditions()
	state_machine.travel(&"death")
	died.emit()


func _pick_random_attack() -> StringName:
	return ATTACK_STATES[randi() % ATTACK_STATES.size()]


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
	_reset_attack_flags()
	_update_animation_conditions()
	state_machine.travel(&"idle")


func _process_spawn_fall(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity * 1.35 * delta, SPAWN_FALL_SPEED_LIMIT)
	move_and_slide()

	if is_on_floor():
		velocity = Vector2.ZERO
		is_spawning = false
		battle_active = false
		landed.emit()
