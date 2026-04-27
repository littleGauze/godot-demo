extends Node2D


@onready var outline_sprite: AnimatedSprite2D = $OutlineSprite2D


func _ready() -> void:
	set_highlighted(false)


func set_highlighted(is_highlighted: bool) -> void:
	outline_sprite.visible = is_highlighted
