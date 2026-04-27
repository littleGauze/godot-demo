extends RigidBody2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.



func _on_area_2d_body_entered(_body:Node2D) -> void:
	print("Coin hit!")
	apply_central_impulse(Vector2(0, -1000))
