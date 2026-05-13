extends Node2D


@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	var frames := animated_sprite_2d.sprite_frames
	if frames == null:
		return

	var animation_name := animated_sprite_2d.animation
	var frame_count := frames.get_frame_count(animation_name)
	if frame_count <= 0:
		return

	animated_sprite_2d.play(animation_name)
	animated_sprite_2d.frame = randi() % frame_count
	animated_sprite_2d.frame_progress = randf()
