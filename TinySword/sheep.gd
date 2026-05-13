extends CharacterBody2D


const WALK_SPEED := 45.0
const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"
const STATE_GRASS := &"grass"
const NOISE_TIME_SCALE := 0.8
const NOISE_DIRECTION_OFFSET := 137.0
const FOLLOW_STOP_DISTANCE := 20.0
const WANDER_TARGET_DISTANCE := 88.0
const FOLLOW_REPATH_INTERVAL := 0.2
const WANDER_REPATH_INTERVAL := 0.8
const STUCK_DISTANCE_EPSILON := 1.0
const STUCK_TIME_LIMIT := 0.6
const NAVMESH_REJOIN_DISTANCE := 6.0
const NAVIGATION_SYNC_MAX_FRAMES := 8

var rng := RandomNumberGenerator.new()
var walk_noise := FastNoiseLite.new()
var current_state: StringName = STATE_GRASS
var state_time_left := 0.0
var walk_direction := Vector2.ZERO
var walk_noise_time := 0.0
var target_player: CharacterBody2D
var forced_follow_player: CharacterBody2D
var navigation_refresh_left := 0.0
var current_navigation_target := Vector2.ZERO
var follow_slot_angle := 0.0
var follow_slot_radius := 56.0
var last_position := Vector2.ZERO
var stuck_time := 0.0
var navigation_ready := false

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $Area2D
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	add_to_group("sheep")
	set_physics_process(false)
	rng.randomize()
	walk_noise.noise_type = FastNoiseLite.NoiseType.TYPE_SIMPLEX_SMOOTH
	walk_noise.seed = rng.randi()
	walk_noise.frequency = 0.35
	walk_noise.fractal_octaves = 2
	walk_noise_time = rng.randf_range(0.0, 1000.0)
	follow_slot_angle = rng.randf_range(0.0, TAU)
	follow_slot_radius = rng.randf_range(40.0, 84.0)
	navigation_agent_2d.avoidance_enabled = false
	navigation_agent_2d.max_speed = WALK_SPEED
	navigation_agent_2d.path_desired_distance = 10.0
	navigation_agent_2d.target_desired_distance = FOLLOW_STOP_DISTANCE
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	call_deferred("_wait_for_navigation_sync")


func _wait_for_navigation_sync() -> void:
	await _await_navigation_sync()
	_update_target_player_from_overlaps()
	_pick_next_state()
	last_position = global_position
	current_navigation_target = _get_closest_navigation_point(global_position)
	navigation_ready = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not navigation_ready:
		return

	navigation_refresh_left = maxf(0.0, navigation_refresh_left - delta)

	var follow_target := _get_follow_target()
	if is_instance_valid(follow_target):
		_follow_player()
		move_and_slide()
		_ensure_on_navigation_mesh()
		_update_stuck_state(delta, true)
		return

	state_time_left -= delta
	if state_time_left <= 0.0:
		_pick_next_state()

	if current_state == STATE_WALK:
		walk_noise_time += delta * NOISE_TIME_SCALE
		_wander()
	else:
		_stop_navigation()
		animated_sprite_2d.play(current_state)

	move_and_slide()
	_ensure_on_navigation_mesh()
	_update_stuck_state(delta, current_state == STATE_WALK)


func _follow_player() -> void:
	var follow_target := _get_follow_target()
	if not is_instance_valid(follow_target):
		return

	if navigation_refresh_left <= 0.0:
		var offset := Vector2.from_angle(follow_slot_angle) * follow_slot_radius
		current_navigation_target = _get_closest_navigation_point(follow_target.global_position + offset)
		navigation_agent_2d.target_position = current_navigation_target
		navigation_refresh_left = FOLLOW_REPATH_INTERVAL

	_move_along_navigation(STATE_IDLE, STATE_WALK)


func _wander() -> void:
	if navigation_refresh_left <= 0.0 or navigation_agent_2d.is_navigation_finished():
		walk_direction = _get_smooth_walk_direction()
		current_navigation_target = _get_closest_navigation_point(
			global_position + walk_direction * WANDER_TARGET_DISTANCE
		)
		navigation_agent_2d.target_position = current_navigation_target
		navigation_refresh_left = WANDER_REPATH_INTERVAL

	_move_along_navigation(STATE_IDLE, STATE_WALK)


func _move_along_navigation(idle_animation: StringName, move_animation: StringName) -> void:
	if navigation_agent_2d.is_navigation_finished():
		velocity = Vector2.ZERO
		animated_sprite_2d.play(idle_animation)
		return

	var next_path_position := navigation_agent_2d.get_next_path_position()
	if global_position.distance_to(next_path_position) < 2.0 and global_position.distance_to(current_navigation_target) > FOLLOW_STOP_DISTANCE:
		velocity = Vector2.ZERO
		animated_sprite_2d.play(idle_animation)
		return

	var move_direction := global_position.direction_to(next_path_position)
	velocity = move_direction * WALK_SPEED

	if velocity.length_squared() <= 1.0:
		animated_sprite_2d.play(idle_animation)
	else:
		animated_sprite_2d.play(move_animation)
		_update_sprite_facing(velocity)


func _stop_navigation() -> void:
	navigation_agent_2d.target_position = global_position
	velocity = Vector2.ZERO
	navigation_refresh_left = 0.0
	stuck_time = 0.0


func _pick_next_state() -> void:
	var roll := rng.randf()
	if roll < 0.2:
		_set_state(STATE_IDLE, rng.randf_range(1.5, 3.0))
	elif roll < 0.3:
		_set_state(STATE_WALK, rng.randf_range(1.0, 2.5))
	else:
		_set_state(STATE_GRASS, rng.randf_range(2.5, 5.0))


func _set_state(state: StringName, duration: float) -> void:
	current_state = state
	state_time_left = duration
	navigation_refresh_left = 0.0
	animated_sprite_2d.play(state)

	if state == STATE_WALK:
		walk_noise_time = rng.randf_range(0.0, 1000.0)
		walk_direction = _get_smooth_walk_direction()
		navigation_refresh_left = rng.randf_range(0.0, WANDER_REPATH_INTERVAL)
	else:
		walk_direction = Vector2.ZERO
		velocity = Vector2.ZERO


func _get_smooth_walk_direction() -> Vector2:
	var noise_x := walk_noise.get_noise_1d(walk_noise_time)
	var noise_y := walk_noise.get_noise_1d(walk_noise_time + NOISE_DIRECTION_OFFSET)
	var direction := Vector2(noise_x, noise_y)
	if direction.length_squared() < 0.01:
		return Vector2.RIGHT
	return direction.normalized()


func _update_sprite_facing(direction: Vector2) -> void:
	if direction.x < 0.0:
		animated_sprite_2d.flip_h = true
	elif direction.x > 0.0:
		animated_sprite_2d.flip_h = false


func _on_detection_area_body_entered(body: Node2D) -> void:
	if forced_follow_player != null:
		return
	if body.is_in_group("player"):
		target_player = body as CharacterBody2D


func _on_detection_area_body_exited(body: Node2D) -> void:
	if forced_follow_player != null:
		return
	if body == target_player:
		target_player = null
		_stop_navigation()
		_update_target_player_from_overlaps()
		_pick_next_state()


func _update_target_player_from_overlaps() -> void:
	if forced_follow_player != null:
		return
	for body in detection_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			target_player = body as CharacterBody2D
			return


func set_forced_follow_player(player: CharacterBody2D) -> void:
	forced_follow_player = player
	if is_instance_valid(player):
		target_player = player
		current_state = STATE_WALK
		navigation_refresh_left = rng.randf_range(0.0, FOLLOW_REPATH_INTERVAL)
		stuck_time = 0.0
	else:
		target_player = null
		_stop_navigation()
		_update_target_player_from_overlaps()
		_pick_next_state()


func _get_follow_target() -> CharacterBody2D:
	if is_instance_valid(forced_follow_player):
		return forced_follow_player
	if is_instance_valid(target_player):
		return target_player
	return null


func _get_closest_navigation_point(target: Vector2) -> Vector2:
	var navigation_map := navigation_agent_2d.get_navigation_map()
	if navigation_map.is_valid():
		return NavigationServer2D.map_get_closest_point(navigation_map, target)
	return target


func _update_stuck_state(delta: float, navigating: bool) -> void:
	var moved_distance := global_position.distance_to(last_position)

	if navigating and velocity.length_squared() > 1.0 and moved_distance < STUCK_DISTANCE_EPSILON:
		stuck_time += delta
	else:
		stuck_time = 0.0

	if stuck_time >= STUCK_TIME_LIMIT:
		_resolve_stuck()

	last_position = global_position


func _resolve_stuck() -> void:
	stuck_time = 0.0
	velocity = Vector2.ZERO

	if is_instance_valid(_get_follow_target()):
		follow_slot_angle += rng.randf_range(0.6, 1.4)
		follow_slot_radius = rng.randf_range(32.0, 96.0)
		navigation_refresh_left = 0.0
		return

	if current_state == STATE_WALK:
		walk_noise_time = rng.randf_range(0.0, 1000.0)
		walk_direction = _get_smooth_walk_direction()
		navigation_refresh_left = 0.0


func _ensure_on_navigation_mesh() -> void:
	var closest_point := _get_closest_navigation_point(global_position)
	if global_position.distance_to(closest_point) < NAVMESH_REJOIN_DISTANCE:
		return

	global_position = closest_point
	velocity = Vector2.ZERO
	stuck_time = 0.0
	navigation_refresh_left = 0.0
	navigation_agent_2d.target_position = closest_point


func _await_navigation_sync() -> void:
	for _frame in range(NAVIGATION_SYNC_MAX_FRAMES):
		await get_tree().physics_frame
		var navigation_map := navigation_agent_2d.get_navigation_map()
		if navigation_map.is_valid() and NavigationServer2D.map_get_iteration_id(navigation_map) > 0:
			return
