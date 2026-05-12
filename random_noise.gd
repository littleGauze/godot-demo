extends Node2D

const LOGO_TEXTURE: Texture2D = preload("res://icon.png")

@export var logo_count := 24
@export var screen_margin := 32.0

var _noise = FastNoiseLite.new()
var _rng = RandomNumberGenerator.new()

func _ready():
	_rng.randomize()

	# Configure the FastNoiseLite instance.
	_noise.noise_type = FastNoiseLite.NoiseType.TYPE_SIMPLEX_SMOOTH
	_noise.seed = _rng.randi()
	_noise.fractal_octaves = 4
	_noise.frequency = 1.0 / 20.0

	_spawn_logos()


func _spawn_logos():
	var viewport_rect := get_viewport_rect()
	var screen_size := viewport_rect.size

	for i in logo_count:
		var logo := Sprite2D.new()
		var noise_x := _noise.get_noise_1d(float(i) * 2.3)
		var noise_y := _noise.get_noise_1d(float(i) * 2.3 + 100.0)
		var noise_scale := _noise.get_noise_1d(float(i) * 1.7 + 10.0)

		logo.texture = LOGO_TEXTURE
		logo.centered = true
		logo.position = Vector2(
			_remap_noise_to_screen(noise_x, screen_size.x),
			_remap_noise_to_screen(noise_y, screen_size.y)
		)
		logo.rotation = _rng.randf_range(0.0, TAU)
		logo.scale = Vector2.ONE * remap(noise_scale, -1.0, 1.0, 0.35, 1.1)

		add_child(logo)


func _remap_noise_to_screen(noise_value: float, axis_size: float) -> float:
	return remap(noise_value, -1.0, 1.0, screen_margin, max(screen_margin, axis_size - screen_margin))
