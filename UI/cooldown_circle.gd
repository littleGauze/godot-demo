extends Control


@export_range(0.0, 1.0, 0.01) var progress := 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var fill_color := Color(0.55, 0.85, 1.0, 0.95)
@export var background_color := Color(0.08, 0.1, 0.14, 0.8)
@export var border_color := Color(1.0, 1.0, 1.0, 0.75)


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 2.0
	if radius <= 0.0:
		return

	draw_circle(center, radius, background_color)

	if progress > 0.0:
		var points := PackedVector2Array([center])
		var start_angle: float = -PI * 0.5
		var end_angle: float = start_angle + (TAU * progress)
		var steps: int = maxi(6, int(36.0 * progress))
		for i in range(steps + 1):
			var t: float = float(i) / float(steps)
			var angle: float = lerpf(start_angle, end_angle, t)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, fill_color)

	draw_arc(center, radius, 0.0, TAU, 48, border_color, 2.0)
