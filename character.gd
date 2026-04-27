class_name Character

var heath := 10
var _name := ""

func print_health():
	print("Health: ", heath)

func print_script_three_times():
	print(get_script())
	print(ResourceLoader.load("res://character.gd"))
	print(Character)

func _init(name: String):
	_name = name