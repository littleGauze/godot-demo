extends Sprite2D


func play_drop(start_point: Vector2, control_point: Vector2, end_point: Vector2, duration: float) -> void:
	global_position = start_point

	set_meta(&"drop_start", start_point)
	set_meta(&"drop_control", control_point)
	set_meta(&"drop_end", end_point)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_drop_progress, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, duration * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, duration * 0.35)


func _set_drop_progress(progress: float) -> void:
	var start := get_meta(&"drop_start") as Vector2
	var control := get_meta(&"drop_control") as Vector2
	var end := get_meta(&"drop_end") as Vector2
	var inverse := 1.0 - progress
	global_position = (
		inverse * inverse * start +
		2.0 * inverse * progress * control +
		progress * progress * end
	)
