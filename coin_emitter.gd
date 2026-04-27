extends Node2D

const CoinScene: PackedScene = preload("res://coin.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	generate_coin()

func generate_coin(pos: Vector2 = Vector2(0, 0)):
	var start = Time.get_ticks_msec()
	var coin = CoinScene.instantiate()
	coin.position = pos
	add_child(coin)
	print(Time.get_ticks_msec() - start)


func _on_area_2d_mouse_exited() -> void:
	pass # Replace with function body.

func _on_area_2d_mouse_entered() -> void:
	await get_tree().create_timer(0.1).timeout
	var pos = get_global_mouse_position()
	generate_coin(pos)
