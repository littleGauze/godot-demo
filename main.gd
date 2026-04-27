extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(func():
		print("Hello, world!")
	)
	print("Timer added.")
