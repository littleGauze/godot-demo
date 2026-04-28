extends Node


const BUS := &"Master"

var stream_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("sfx_manager")
	stream_cache[&"player_attack1"] = load("res://Audio/player_attack1.wav")
	stream_cache[&"player_attack2"] = load("res://Audio/player_attack2.wav")
	stream_cache[&"player_attack3"] = load("res://Audio/player_attack3.wav")
	stream_cache[&"enemy_attack1"] = load("res://Audio/enemy_attack1.wav")
	stream_cache[&"enemy_attack2"] = load("res://Audio/enemy_attack2.wav")
	stream_cache[&"enemy_attack3"] = load("res://Audio/enemy_attack3.wav")
	stream_cache[&"player_hurt"] = load("res://Audio/player_hurt.wav")
	stream_cache[&"enemy_hurt"] = load("res://Audio/enemy_hurt.wav")
	stream_cache[&"block"] = load("res://Audio/block.wav")


func play_cue(cue: StringName, position: Vector2, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if not stream_cache.has(cue):
		return

	var player := AudioStreamPlayer2D.new()
	player.stream = stream_cache[cue]
	player.bus = BUS
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	add_child(player)
	player.global_position = position
	player.play()
	player.finished.connect(player.queue_free)
