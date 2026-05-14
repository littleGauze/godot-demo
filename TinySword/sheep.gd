extends CharacterBody2D


const MEAT_TEXTURE := preload("res://TinySword/Texture/Sheep/Meat Resource.png")
const MEAT_DROP_SCRIPT := preload("res://TinySword/meat_drop.gd")
const DUST_SCENE := preload("res://TinySword/Texture/VFX/dust2.tscn")
const HIT_DUST_SCENE := preload("res://TinySword/Texture/VFX/dust1.tscn")
const SHEEP_SFX := preload("res://TinySword/Audio/sheep.mp3")
const HIT_HURT_SFX := preload("res://TinySword/Audio/hitHurt.wav")
const MAX_HEALTH := 3
const WALK_SPEED_MIN := 38.0
const WALK_SPEED_MAX := 52.0
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
const NAVMESH_EDGE_TOLERANCE := 6.0
const NAVMESH_TELEPORT_DISTANCE := 96.0
const NAVIGATION_SYNC_MAX_FRAMES := 60
const NAVIGATION_CLEARANCE_RADIUS := 18.0
const SAFE_NAVIGATION_POINT_ATTEMPTS := 16
const SAFE_NAVIGATION_POINT_RADIUS := 72.0
const PATH_NAVMESH_SAMPLE_STEP := 16.0
const PATH_NAVMESH_MAX_DISTANCE := 8.0
const PATH_TARGET_REACHED_DISTANCE := 12.0
const HURT_FLASH_TIME := 0.12
const MEAT_DROP_HORIZONTAL_RANGE := 18.0
const MEAT_DROP_ARC_HEIGHT := 34.0
const MEAT_DROP_TIME := 0.38
const FLEE_ALERT_RADIUS := 260.0
const FLEE_DISTANCE := 120.0
const FLEE_DURATION := 1.2
const FLEE_REPATH_INTERVAL := 0.25
const KNOCKBACK_SPEED := 135.0
const KNOCKBACK_TIME := 0.16
const DEBUG_PATH_COLOR := Color(0.1, 0.85, 1.0, 0.85)
const DEBUG_NEXT_POINT_COLOR := Color(1.0, 0.85, 0.1, 0.95)
const DEBUG_NEXT_DIRECTION_COLOR := Color(1.0, 0.1, 0.1, 0.95)
const DEBUG_TARGET_COLOR := Color(0.2, 1.0, 0.25, 0.9)
const DEBUG_REVERSE_ARROW_LENGTH := 28.0

var rng := RandomNumberGenerator.new()
var walk_noise := FastNoiseLite.new()
var walk_speed := 45.0
var current_state: StringName = STATE_GRASS
var state_time_left := 0.0
var walk_direction := Vector2.ZERO
var walk_noise_time := 0.0
var target_player: CharacterBody2D
var forced_follow_player: CharacterBody2D
var suppress_sensor_follow := false
var navigation_refresh_left := 0.0
var current_navigation_target := Vector2.ZERO
var follow_slot_angle := 0.0
var follow_slot_radius := 56.0
var last_position := Vector2.ZERO
var stuck_time := 0.0
var navigation_ready := false
var spawn_position := Vector2.ZERO
var has_spawn_position := false
var current_navigation_path := PackedVector2Array()
var current_navigation_path_index := 0
var health := MAX_HEALTH
var is_dead := false
var hurt_flash_tween: Tween
var flee_time_left := 0.0
var flee_source_position := Vector2.ZERO
var knockback_time_left := 0.0
var knockback_velocity := Vector2.ZERO
var debug_navigation_draw_enabled := false
var desired_navigation_velocity := Vector2.ZERO

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $Area2D
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	_apply_spawn_position()
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
	walk_speed = rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
	navigation_agent_2d.avoidance_enabled = true
	navigation_agent_2d.max_speed = walk_speed
	navigation_agent_2d.path_desired_distance = 10.0
	navigation_agent_2d.target_desired_distance = FOLLOW_STOP_DISTANCE
	navigation_agent_2d.debug_enabled = false
	navigation_agent_2d.velocity_computed.connect(_on_navigation_velocity_computed)
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	call_deferred("_wait_for_navigation_sync")


func initialize_spawn_position(value: Vector2) -> void:
	spawn_position = value
	has_spawn_position = true
	_apply_spawn_position()


func _apply_spawn_position() -> void:
	if has_spawn_position:
		global_position = spawn_position


func _wait_for_navigation_sync() -> void:
	var navigation_synced := await _await_navigation_sync()
	_apply_spawn_position()
	_update_target_player_from_overlaps()
	_pick_next_state()
	last_position = global_position
	current_navigation_target = global_position
	if navigation_synced:
		current_navigation_target = _get_closest_navigation_point(global_position)
	navigation_ready = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if is_dead or not navigation_ready:
		return

	if knockback_time_left > 0.0:
		_apply_knockback(delta)
		move_and_slide()
		_update_stuck_state(delta, false)
		if debug_navigation_draw_enabled:
			queue_redraw()
		return

	navigation_refresh_left = maxf(0.0, navigation_refresh_left - delta)

	if flee_time_left > 0.0:
		_flee(delta)
		move_and_slide()
		_ensure_on_navigation_mesh()
		_update_stuck_state(delta, true)
		if debug_navigation_draw_enabled:
			queue_redraw()
		return

	var follow_target := _get_follow_target()
	if is_instance_valid(follow_target):
		current_state = STATE_WALK
		state_time_left = 0.0
		_follow_player()
		move_and_slide()
		_ensure_on_navigation_mesh()
		_update_stuck_state(delta, true)
		if debug_navigation_draw_enabled:
			queue_redraw()
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
	if debug_navigation_draw_enabled:
		queue_redraw()


func _follow_player() -> void:
	var follow_target := _get_follow_target()
	if not is_instance_valid(follow_target):
		return

	if navigation_refresh_left <= 0.0:
		var target_position := follow_target.global_position
		if not is_instance_valid(forced_follow_player):
			target_position += Vector2.from_angle(follow_slot_angle) * follow_slot_radius

		if not _try_set_navigation_target(target_position):
			_refresh_follow_slot()
			navigation_refresh_left = FOLLOW_REPATH_INTERVAL
			if current_navigation_path.is_empty():
				_set_navigation_velocity(Vector2.ZERO)
				animated_sprite_2d.play(STATE_IDLE)
				return
			_move_along_navigation(STATE_IDLE, STATE_WALK)
			return
		navigation_refresh_left = FOLLOW_REPATH_INTERVAL

	_move_along_navigation(STATE_IDLE, STATE_WALK)


func _wander() -> void:
	if navigation_refresh_left <= 0.0 or _is_navigation_path_finished():
		walk_direction = _get_smooth_walk_direction()
		if not _try_set_navigation_target(global_position + walk_direction * WANDER_TARGET_DISTANCE):
			_stop_navigation()
			animated_sprite_2d.play(STATE_IDLE)
			navigation_refresh_left = WANDER_REPATH_INTERVAL
			return
		navigation_refresh_left = WANDER_REPATH_INTERVAL

	_move_along_navigation(STATE_IDLE, STATE_WALK)


func _flee(delta: float) -> void:
	flee_time_left = maxf(0.0, flee_time_left - delta)

	if flee_time_left <= 0.0:
		_stop_navigation()
		_pick_next_state()
		return

	if navigation_refresh_left <= 0.0 or _is_navigation_path_finished():
		var away_direction := flee_source_position.direction_to(global_position)
		if away_direction.length_squared() < 0.01:
			away_direction = Vector2.from_angle(rng.randf_range(0.0, TAU))

		var spread_direction := away_direction.rotated(rng.randf_range(-0.45, 0.45)).normalized()
		var flee_target := global_position + spread_direction * FLEE_DISTANCE
		if not _try_set_navigation_target(flee_target):
			_stop_navigation()
			animated_sprite_2d.play(STATE_IDLE)
			navigation_refresh_left = FLEE_REPATH_INTERVAL
			return
		navigation_refresh_left = FLEE_REPATH_INTERVAL

	_move_along_navigation(STATE_IDLE, STATE_WALK)


func _move_along_navigation(idle_animation: StringName, move_animation: StringName) -> void:
	if current_navigation_path.is_empty() or current_navigation_path_index >= current_navigation_path.size():
		_set_navigation_velocity(Vector2.ZERO)
		_update_navigation_animation(idle_animation, move_animation)
		return

	var next_path_position := current_navigation_path[current_navigation_path_index]
	while (
		current_navigation_path_index < current_navigation_path.size() - 1
		and global_position.distance_to(next_path_position) <= navigation_agent_2d.path_desired_distance
	):
		current_navigation_path_index += 1
		next_path_position = current_navigation_path[current_navigation_path_index]

	if global_position.distance_to(current_navigation_target) <= FOLLOW_STOP_DISTANCE:
		_set_navigation_velocity(Vector2.ZERO)
		_update_navigation_animation(idle_animation, move_animation)
		return

	var move_direction := global_position.direction_to(next_path_position)
	_set_navigation_velocity(move_direction * walk_speed)
	_update_navigation_animation(idle_animation, move_animation)

func _set_navigation_velocity(new_velocity: Vector2) -> void:
	desired_navigation_velocity = new_velocity
	if navigation_agent_2d.avoidance_enabled:
		navigation_agent_2d.set_velocity(desired_navigation_velocity)
	else:
		_on_navigation_velocity_computed(desired_navigation_velocity)


func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	if is_dead or knockback_time_left > 0.0:
		return
	velocity = safe_velocity


func _update_navigation_animation(idle_animation: StringName, move_animation: StringName) -> void:
	if velocity.length_squared() <= 1.0 and desired_navigation_velocity.length_squared() <= 1.0:
		animated_sprite_2d.play(idle_animation)
	else:
		animated_sprite_2d.play(move_animation)
	var facing_velocity := velocity if velocity.length_squared() > 1.0 else desired_navigation_velocity
	_update_sprite_facing(facing_velocity)


func _draw() -> void:
	if not debug_navigation_draw_enabled:
		return

	if current_navigation_path.size() >= 2:
		var local_points := PackedVector2Array()
		for point in current_navigation_path:
			local_points.append(to_local(point))
		draw_polyline(local_points, DEBUG_PATH_COLOR, 2.0)

	if current_navigation_target != Vector2.ZERO:
		draw_circle(to_local(current_navigation_target), 5.0, DEBUG_TARGET_COLOR)

	var next_path_position := _get_next_debug_path_position()
	if next_path_position == Vector2.INF:
		return

	var local_next_point := to_local(next_path_position)
	draw_circle(local_next_point, 4.0, DEBUG_NEXT_POINT_COLOR)

	var next_direction := global_position.direction_to(next_path_position)
	if next_direction.length_squared() < 0.01:
		return

	var arrow_end := global_position + next_direction * DEBUG_REVERSE_ARROW_LENGTH
	_draw_arrow(global_position, arrow_end, DEBUG_NEXT_DIRECTION_COLOR)


func _get_next_debug_path_position() -> Vector2:
	if current_navigation_path.is_empty() or current_navigation_path_index >= current_navigation_path.size():
		return Vector2.INF
	return current_navigation_path[current_navigation_path_index]


func _draw_arrow(from_global: Vector2, to_global: Vector2, color: Color) -> void:
	var from := to_local(from_global)
	var to := to_local(to_global)
	draw_line(from, to, color, 2.0)

	var direction := from.direction_to(to)
	if direction.length_squared() < 0.01:
		return

	var left := to - direction.rotated(0.65) * 8.0
	var right := to - direction.rotated(-0.65) * 8.0
	draw_line(to, left, color, 2.0)
	draw_line(to, right, color, 2.0)


func _is_navigation_path_finished() -> bool:
	return (
		current_navigation_path.is_empty()
		or current_navigation_path_index >= current_navigation_path.size()
		or global_position.distance_to(current_navigation_target) <= FOLLOW_STOP_DISTANCE
	)


func _stop_navigation() -> void:
	navigation_agent_2d.target_position = global_position
	current_navigation_path = PackedVector2Array()
	current_navigation_path_index = 0
	desired_navigation_velocity = Vector2.ZERO
	if navigation_agent_2d.avoidance_enabled:
		navigation_agent_2d.set_velocity(Vector2.ZERO)
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
	if suppress_sensor_follow:
		return
	if body.is_in_group("player"):
		target_player = body as CharacterBody2D
		_play_sfx(SHEEP_SFX)


func _on_detection_area_body_exited(body: Node2D) -> void:
	if forced_follow_player != null:
		return
	if body.is_in_group("player") and suppress_sensor_follow:
		suppress_sensor_follow = false
		target_player = null
		return
	if body == target_player:
		target_player = null
		_stop_navigation()
		_update_target_player_from_overlaps()
		_pick_next_state()


func _update_target_player_from_overlaps() -> void:
	if forced_follow_player != null:
		return
	if suppress_sensor_follow:
		target_player = null
		return
	for body in detection_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			target_player = body as CharacterBody2D
			return


func set_forced_follow_player(player: CharacterBody2D) -> void:
	if is_dead:
		return

	forced_follow_player = player
	if is_instance_valid(player):
		target_player = player
		current_state = STATE_WALK
		state_time_left = 0.0
		navigation_refresh_left = rng.randf_range(0.0, FOLLOW_REPATH_INTERVAL)
		stuck_time = 0.0
	else:
		target_player = null
		_stop_navigation()
		_update_target_player_from_overlaps()
		_pick_next_state()


func set_debug_navigation_draw_enabled(enabled: bool) -> void:
	debug_navigation_draw_enabled = enabled
	navigation_agent_2d.debug_enabled = enabled
	queue_redraw()


func _get_follow_target() -> CharacterBody2D:
	if is_instance_valid(forced_follow_player):
		return forced_follow_player
	if suppress_sensor_follow:
		return null
	if is_instance_valid(target_player):
		return target_player
	return null


func _get_closest_navigation_point(target: Vector2) -> Vector2:
	var navigation_map := navigation_agent_2d.get_navigation_map()
	if not navigation_map.is_valid() or NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		return target

	var closest_point := NavigationServer2D.map_get_closest_point(navigation_map, target)
	if closest_point == Vector2.ZERO and target.distance_to(Vector2.ZERO) > NAVMESH_EDGE_TOLERANCE:
		return target
	if _is_clear_at(closest_point):
		return closest_point

	for _attempt in range(SAFE_NAVIGATION_POINT_ATTEMPTS):
		var offset := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(
			NAVIGATION_CLEARANCE_RADIUS,
			SAFE_NAVIGATION_POINT_RADIUS
		)
		var candidate := NavigationServer2D.map_get_closest_point(navigation_map, closest_point + offset)
		if candidate != Vector2.ZERO and _is_clear_at(candidate):
			return candidate

	return target


func _try_set_navigation_target(target: Vector2) -> bool:
	var navigation_map := navigation_agent_2d.get_navigation_map()
	if not navigation_map.is_valid() or NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		return false

	var origin := _get_closest_navigation_point(global_position)
	var destination := _get_closest_navigation_point(target)
	var path := _get_complete_path(navigation_map, origin, destination)
	if path.is_empty():
		return false

	current_navigation_target = destination
	current_navigation_path = path
	current_navigation_path_index = 1 if current_navigation_path.size() > 1 else 0
	navigation_agent_2d.target_position = current_navigation_target
	return true


func _get_complete_path(navigation_map: RID, origin: Vector2, destination: Vector2) -> PackedVector2Array:
	if origin.distance_to(destination) <= PATH_TARGET_REACHED_DISTANCE:
		return PackedVector2Array([origin, destination])

	var path := NavigationServer2D.map_get_path(
		navigation_map,
		origin,
		destination,
		true,
		navigation_agent_2d.navigation_layers
	)
	if path.size() < 2:
		return PackedVector2Array()

	if path[path.size() - 1].distance_to(destination) > PATH_TARGET_REACHED_DISTANCE:
		return PackedVector2Array()

	if not _is_path_on_navigation_mesh(navigation_map, path):
		return PackedVector2Array()

	return path


func _is_clear_at(point: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = NAVIGATION_CLEARANCE_RADIUS

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]

	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _is_path_on_navigation_mesh(navigation_map: RID, path: PackedVector2Array) -> bool:
	for index in range(path.size() - 1):
		if not _is_path_segment_on_navigation_mesh(navigation_map, path[index], path[index + 1]):
			return false
	return true


func _is_path_segment_on_navigation_mesh(navigation_map: RID, start_point: Vector2, end_point: Vector2) -> bool:
	var segment_length := start_point.distance_to(end_point)
	if segment_length <= PATH_NAVMESH_SAMPLE_STEP:
		return _is_point_on_navigation_mesh(navigation_map, start_point) and _is_point_on_navigation_mesh(navigation_map, end_point)

	var sample_count := ceili(segment_length / PATH_NAVMESH_SAMPLE_STEP)
	for sample_index in range(sample_count + 1):
		var weight := float(sample_index) / float(sample_count)
		var sample_point := start_point.lerp(end_point, weight)
		if not _is_point_on_navigation_mesh(navigation_map, sample_point):
			return false
	return true


func _is_point_on_navigation_mesh(navigation_map: RID, point: Vector2) -> bool:
	var closest_point := NavigationServer2D.map_get_closest_point(navigation_map, point)
	return point.distance_to(closest_point) <= PATH_NAVMESH_MAX_DISTANCE


func take_damage(amount: int = 1, _source_position: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return

	health -= amount
	_apply_hit_knockback(_source_position)
	_play_sfx(HIT_HURT_SFX)
	_spawn_hit_dust()
	_flash_hurt()
	_alert_nearby_sheep(_source_position)

	if health <= 0:
		_die()


func flee_from(source_position: Vector2) -> void:
	if is_dead:
		return

	flee_source_position = source_position
	flee_time_left = FLEE_DURATION
	if forced_follow_player == null:
		suppress_sensor_follow = true
		target_player = null
	current_state = STATE_WALK
	stuck_time = 0.0
	navigation_refresh_left = 0.0


func _apply_hit_knockback(source_position: Vector2) -> void:
	var direction := source_position.direction_to(global_position)
	if source_position == Vector2.ZERO or direction.length_squared() < 0.01:
		direction = Vector2.from_angle(rng.randf_range(0.0, TAU))

	knockback_velocity = direction.normalized() * KNOCKBACK_SPEED
	knockback_time_left = KNOCKBACK_TIME
	_stop_navigation()


func _apply_knockback(delta: float) -> void:
	knockback_time_left = maxf(0.0, knockback_time_left - delta)
	var progress := 1.0 - (knockback_time_left / KNOCKBACK_TIME)
	desired_navigation_velocity = Vector2.ZERO
	velocity = knockback_velocity.lerp(Vector2.ZERO, progress)
	animated_sprite_2d.play(STATE_WALK)
	_update_sprite_facing(velocity)

	if knockback_time_left <= 0.0:
		velocity = Vector2.ZERO
		navigation_refresh_left = 0.0


func _alert_nearby_sheep(source_position: Vector2) -> void:
	if source_position == Vector2.ZERO:
		source_position = global_position

	for sheep in get_tree().get_nodes_in_group("sheep"):
		if sheep == self or not sheep.has_method("flee_from"):
			continue
		if global_position.distance_to(sheep.global_position) > FLEE_ALERT_RADIUS:
			continue

		sheep.flee_from(source_position)


func _flash_hurt() -> void:
	if hurt_flash_tween != null:
		hurt_flash_tween.kill()

	animated_sprite_2d.modulate = Color(1.0, 0.25, 0.25, 1.0)
	hurt_flash_tween = create_tween()
	hurt_flash_tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, HURT_FLASH_TIME)


func _die() -> void:
	is_dead = true
	_stop_navigation()
	set_physics_process(false)
	_spawn_death_dust()
	_spawn_meat()
	queue_free()


func _spawn_meat() -> void:
	var meat := Sprite2D.new()
	meat.name = "Meat"
	meat.add_to_group("meat")
	meat.set_script(MEAT_DROP_SCRIPT)
	meat.texture = MEAT_TEXTURE
	meat.z_index = z_index
	get_parent().add_child(meat)
	meat.global_position = global_position
	meat.scale = Vector2(0.25, 0.25)
	meat.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var drop_start := global_position
	var drop_end := global_position + Vector2(rng.randf_range(-MEAT_DROP_HORIZONTAL_RANGE, MEAT_DROP_HORIZONTAL_RANGE), 8.0)
	var drop_control := global_position + Vector2((drop_end.x - drop_start.x) * 0.5, -MEAT_DROP_ARC_HEIGHT)
	meat.call("play_drop", drop_start, drop_control, drop_end, MEAT_DROP_TIME)


func _spawn_death_dust() -> void:
	var dust := DUST_SCENE.instantiate() as GPUParticles2D
	_play_dust(dust)


func _spawn_hit_dust() -> void:
	var dust := HIT_DUST_SCENE.instantiate() as GPUParticles2D
	_play_dust(dust)


func _play_dust(dust: GPUParticles2D) -> void:
	get_parent().add_child(dust)
	dust.global_position = global_position
	dust.z_as_relative = false
	dust.z_index = z_index + 10
	dust.one_shot = true
	dust.emitting = true

	var cleanup_timer := get_tree().create_timer(dust.lifetime + 0.1)
	cleanup_timer.timeout.connect(dust.queue_free)


func _play_sfx(stream: AudioStream) -> void:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	get_parent().add_child(player)
	player.global_position = global_position
	player.play()
	player.finished.connect(player.queue_free)


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
		_refresh_follow_slot()
		navigation_refresh_left = 0.0
		return

	if current_state == STATE_WALK:
		walk_noise_time = rng.randf_range(0.0, 1000.0)
		walk_direction = _get_smooth_walk_direction()
		navigation_refresh_left = 0.0


func _ensure_on_navigation_mesh() -> void:
	var closest_point := _get_closest_navigation_point(global_position)
	var distance_to_navmesh := global_position.distance_to(closest_point)
	if distance_to_navmesh < NAVMESH_EDGE_TOLERANCE:
		return

	velocity = Vector2.ZERO
	desired_navigation_velocity = Vector2.ZERO
	stuck_time = 0.0
	navigation_refresh_left = 0.0

	if distance_to_navmesh >= NAVMESH_TELEPORT_DISTANCE and _is_clear_at(closest_point):
		global_position = closest_point
		navigation_agent_2d.target_position = closest_point
	else:
		navigation_agent_2d.target_position = global_position
	current_navigation_path = PackedVector2Array()
	current_navigation_path_index = 0


func _refresh_follow_slot() -> void:
	follow_slot_angle += rng.randf_range(0.6, 1.4)
	follow_slot_radius = rng.randf_range(32.0, 96.0)


func _await_navigation_sync() -> bool:
	for _frame in range(NAVIGATION_SYNC_MAX_FRAMES):
		await get_tree().physics_frame
		var navigation_map := navigation_agent_2d.get_navigation_map()
		if navigation_map.is_valid() and NavigationServer2D.map_get_iteration_id(navigation_map) > 0:
			return true

	return false
