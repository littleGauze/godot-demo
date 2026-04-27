extends Node2D


const AXEMAN_DROP_HEIGHT = 420.0
const AXEMAN_DROP_OFFSET_X = 180.0
const BATTLE_START_EXTRA_DELAY = 1.0
const SCREEN_SHAKE_RANDOM := &"random"
const SCREEN_SHAKE_DIRECTIONAL := &"directional"

var player_near_flag := false
var summon_started := false
var battle_started := false
var battle_start_pending := false
var battle_start_delay := 0.0
var axeman_ground_position := Vector2.ZERO
var camera_base_y := 0.0
var camera_shake_time := 0.0
var camera_shake_duration := 0.0
var camera_shake_strength := Vector2.ZERO
var camera_shake_direction := Vector2.ZERO
var camera_shake_type: StringName = SCREEN_SHAKE_RANDOM
var camera_rng := RandomNumberGenerator.new()
var parallax_sprite_base_positions := {}

@onready var player = $Player
@onready var camera_2d: Camera2D = $Camera2D
@onready var parallax_background: ParallaxBackground = $ParallaxBackground
@onready var axeman = $Axeman
@onready var flag = $Platform/Items/Flag
@onready var flag_area: Area2D = $Platform/Items/Flag/InteractArea
@onready var player_health_bar: ProgressBar = $CanvasLayer/PlayerHealthBar
@onready var dash_cooldown_indicator = $CanvasLayer/DashCooldownIndicator
@onready var boss_health_bar: ProgressBar = $CanvasLayer/BossHealthBar
@onready var boss_label: Label = $CanvasLayer/BossLabel
@onready var interact_label: Label = $CanvasLayer/InteractLabel
@onready var result_panel: Panel = $CanvasLayer/ResultPanel
@onready var result_label: Label = $CanvasLayer/ResultPanel/ResultLabel
@onready var restart_button: Button = $CanvasLayer/ResultPanel/RestartButton


func _ready() -> void:
	randomize()
	camera_rng.randomize()
	axeman_ground_position = axeman.global_position
	camera_base_y = player.global_position.y
	_cache_parallax_sprites()
	_bind_health_bar(player, player_health_bar)
	_bind_health_bar(axeman, boss_health_bar)
	_bind_endings()
	_bind_flag()
	_prepare_encounter()
	result_panel.visible = false
	restart_button.pressed.connect(_restart_scene)
	_update_camera(0.0)


func _process(delta: float) -> void:
	_update_camera(delta)
	dash_cooldown_indicator.progress = player.get_dash_cooldown_progress()

	if battle_start_pending:
		battle_start_delay = maxf(battle_start_delay - delta, 0.0)
		if battle_start_delay <= 0.0:
			battle_start_pending = false
			battle_started = true
			axeman.begin_battle()

	if summon_started or battle_started or battle_start_pending:
		return

	if player_near_flag and Input.is_action_just_pressed("interact"):
		_start_encounter()


func _bind_health_bar(actor: Node, bar: ProgressBar) -> void:
	if actor == null:
		bar.visible = false
		return

	actor.health_changed.connect(func(current: int, maximum: int) -> void:
		bar.max_value = maximum
		bar.value = current
	)
	bar.max_value = actor.get_max_health()
	bar.value = actor.current_health


func _bind_endings() -> void:
	if player != null:
		player.died.connect(func() -> void:
			_show_result("You Lose")
		)

	if axeman != null:
		axeman.died.connect(func() -> void:
			_show_result("You Win")
		)
		axeman.landed.connect(_on_axeman_landed)


func _bind_flag() -> void:
	flag_area.body_entered.connect(_on_flag_body_entered)
	flag_area.body_exited.connect(_on_flag_body_exited)
	flag.set_highlighted(false)
	interact_label.visible = false


func _prepare_encounter() -> void:
	axeman.set_battle_active(false)
	axeman.visible = false
	boss_label.visible = false
	boss_health_bar.visible = false


func _on_flag_body_entered(body: Node) -> void:
	if body != player or summon_started or battle_started:
		return

	player_near_flag = true
	flag.set_highlighted(true)
	interact_label.visible = true


func _on_flag_body_exited(body: Node) -> void:
	if body != player:
		return

	player_near_flag = false
	if not summon_started and not battle_started:
		flag.set_highlighted(false)
		interact_label.visible = false


func _start_encounter() -> void:
	summon_started = true
	player_near_flag = false
	flag.set_highlighted(false)
	interact_label.visible = false
	axeman_ground_position = Vector2(flag.global_position.x + AXEMAN_DROP_OFFSET_X, axeman_ground_position.y)
	var spawn_position := axeman_ground_position + Vector2(0.0, -AXEMAN_DROP_HEIGHT)
	axeman.start_spawn_fall(spawn_position)


func _on_axeman_landed() -> void:
	summon_started = false
	battle_start_pending = true
	boss_label.visible = true
	boss_health_bar.visible = true
	trigger_camera_shake_downward()
	battle_start_delay = camera_shake_duration + BATTLE_START_EXTRA_DELAY


func _show_result(message: String) -> void:
	result_label.text = message
	result_panel.visible = true


func _restart_scene() -> void:
	get_tree().reload_current_scene()


func shake_screen(
	duration: float = 0.25,
	strength: Vector2 = Vector2(10.0, 10.0),
	direction: Vector2 = Vector2.ZERO,
	shake_type: StringName = SCREEN_SHAKE_RANDOM
) -> void:
	camera_shake_duration = duration
	camera_shake_time = duration
	camera_shake_strength = strength
	camera_shake_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO
	camera_shake_type = shake_type


func trigger_camera_shake_downward(duration: float = 0.18, amplitude: float = 18.0) -> void:
	shake_screen(
		duration,
		Vector2(amplitude * 0.2, amplitude),
		Vector2.DOWN,
		SCREEN_SHAKE_DIRECTIONAL
	)


func _update_camera(delta: float) -> void:
	if camera_shake_time > 0.0:
		camera_shake_time = maxf(camera_shake_time - delta, 0.0)

	var shake_offset := Vector2.ZERO
	if camera_shake_time > 0.0 and camera_shake_duration > 0.0:
		var fade := camera_shake_time / camera_shake_duration
		if camera_shake_type == SCREEN_SHAKE_DIRECTIONAL:
			shake_offset = camera_shake_direction * camera_shake_strength * fade
		else:
			shake_offset = Vector2(
				camera_rng.randf_range(-camera_shake_strength.x, camera_shake_strength.x),
				camera_rng.randf_range(-camera_shake_strength.y, camera_shake_strength.y)
			) * fade

	camera_2d.global_position = Vector2(player.global_position.x, camera_base_y) + shake_offset
	camera_2d.offset = Vector2.ZERO
	_apply_parallax_shake(shake_offset)


func _cache_parallax_sprites() -> void:
	parallax_sprite_base_positions.clear()
	for node in parallax_background.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		parallax_sprite_base_positions[sprite] = sprite.position


func _apply_parallax_shake(shake_offset: Vector2) -> void:
	for sprite in parallax_sprite_base_positions:
		var base_position: Vector2 = parallax_sprite_base_positions[sprite]
		var scale_safe := Vector2(
			sprite.scale.x if not is_zero_approx(sprite.scale.x) else 1.0,
			sprite.scale.y if not is_zero_approx(sprite.scale.y) else 1.0
		)
		sprite.position = base_position - (shake_offset / scale_safe)
