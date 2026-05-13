extends Node2D


const SHEEP_COUNT := 20
const NAVIGATION_SYNC_MAX_FRAMES := 8
const SHEEP_SCENE := preload("res://TinySword/sheep.tscn")

@onready var map: NavigationRegion2D = $Map
@onready var follow_check_button: CheckButton = $CanvasLayer/FollowPanel/FollowCheckButton

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	follow_check_button.toggled.connect(_on_follow_check_button_toggled)
	call_deferred("_wait_for_navigation_sync")


func _wait_for_navigation_sync() -> void:
	await _await_navigation_sync()
	_spawn_sheep()


func _spawn_sheep() -> void:
	var navigation_polygon := map.navigation_polygon
	if navigation_polygon == null:
		return

	var vertices := navigation_polygon.get_vertices()
	var polygon_count := navigation_polygon.get_polygon_count()
	if polygon_count == 0:
		return

	var triangles: Array[PackedVector2Array] = []
	var cumulative_areas: Array[float] = []
	var total_area := 0.0

	for polygon_index in range(polygon_count):
		var polygon := navigation_polygon.get_polygon(polygon_index)
		if polygon.size() < 3:
			continue

		var anchor := vertices[polygon[0]]
		for index in range(1, polygon.size() - 1):
			var triangle := PackedVector2Array([
				anchor,
				vertices[polygon[index]],
				vertices[polygon[index + 1]],
			])
			var area := absf(_triangle_signed_area(triangle))
			if area <= 0.0:
				continue

			total_area += area
			triangles.append(triangle)
			cumulative_areas.append(total_area)

	if triangles.is_empty():
		return

	for _index in range(SHEEP_COUNT):
		var spawn_point := _sample_point(triangles, cumulative_areas, total_area)
		var sheep := SHEEP_SCENE.instantiate()
		sheep.global_position = map.to_global(spawn_point)
		add_child(sheep)


func _sample_point(
	triangles: Array[PackedVector2Array],
	cumulative_areas: Array[float],
	total_area: float
) -> Vector2:
	var target_area := rng.randf_range(0.0, total_area)
	var triangle_index := 0
	while triangle_index < cumulative_areas.size() and target_area > cumulative_areas[triangle_index]:
		triangle_index += 1

	var triangle := triangles[min(triangle_index, triangles.size() - 1)]
	var r1 := sqrt(rng.randf())
	var r2 := rng.randf()
	var a := triangle[0]
	var b := triangle[1]
	var c := triangle[2]
	return (1.0 - r1) * a + r1 * (1.0 - r2) * b + r1 * r2 * c


func _triangle_signed_area(triangle: PackedVector2Array) -> float:
	return (
		triangle[0].x * (triangle[1].y - triangle[2].y) +
		triangle[1].x * (triangle[2].y - triangle[0].y) +
		triangle[2].x * (triangle[0].y - triangle[1].y)
	) * 0.5


func _on_follow_check_button_toggled(toggled_on: bool) -> void:
	var player := _get_player() if toggled_on else null
	for sheep in get_tree().get_nodes_in_group("sheep"):
		sheep.set_forced_follow_player(player)


func _get_player() -> CharacterBody2D:
	return get_tree().get_first_node_in_group("player") as CharacterBody2D


func _await_navigation_sync() -> void:
	for _frame in range(NAVIGATION_SYNC_MAX_FRAMES):
		await get_tree().physics_frame
		var navigation_map := map.get_navigation_map()
		if navigation_map.is_valid() and NavigationServer2D.map_get_iteration_id(navigation_map) > 0:
			return
