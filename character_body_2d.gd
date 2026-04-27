extends CharacterBody2D


var movement_speed: float = 200: set = set_movement_speed
var movement_target_position: Vector2 = Vector2(912, 427)
var movement_delta: float = 0.0

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D

func set_movement_speed(value: float):
	movement_speed = value
	# if navigation_agent:
	# 	navigation_agent.avoidance_priority = value / 100

func _ready():
	navigation_agent.path_desired_distance = 20
	navigation_agent.target_desired_distance = 20
	navigation_agent.path_max_distance = 30
	navigation_agent.velocity_computed.connect(_on_velocity_computed)
	movement_speed = randf_range(200, 250)

func actor_setup():
	await get_tree().physics_frame
	position = _get_random_target_position()
	set_movement_target(_get_random_target_position())

func set_movement_target(target_position: Vector2):
	navigation_agent.target_position = target_position

func _process(_delta: float) -> void:
	if global_position.distance_to(get_global_mouse_position()) > 20:
		set_movement_target(get_global_mouse_position())

func _physics_process(_delta: float) -> void:
	if navigation_agent.is_navigation_finished():
		# set_movement_target(_get_random_target_position())
		return

	if navigation_agent.is_target_reached():
		return

	var current_agent_position: Vector2 = global_position
	var next_path_position: Vector2 = navigation_agent.get_next_path_position()

	movement_delta = _delta * movement_speed
	var direction: Vector2 = current_agent_position.direction_to(next_path_position)
	var new_velocity: Vector2 = direction * movement_delta

	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(new_velocity)
	else:
		_on_velocity_computed(new_velocity)


func _on_velocity_computed(safe_velocity: Vector2):
	global_position = global_position.move_toward(global_position + safe_velocity, movement_delta)
	

func _get_random_target_position() -> Vector2:
	return Vector2(
		randf_range(0, get_viewport_rect().size.x),
		randf_range(0, get_viewport_rect().size.y)
	)
