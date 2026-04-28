extends Node2D


const AXEMAN_SCENE = preload("res://Enemies/axeman.tscn")
const AXEMAN_DROP_HEIGHT = 420.0
const AXEMAN_DROP_OFFSET_X = 180.0
const AXEMAN_SUMMON_COUNT = 10
const AXEMAN_FORMATION_SPACING_X = 140.0
const BATTLE_START_EXTRA_DELAY = 1.0
const SCREEN_SHAKE_RANDOM := &"random"
const SCREEN_SHAKE_DIRECTIONAL := &"directional"

var player_near_flag := false
var summon_started := false
var battle_started := false
var battle_start_pending := false
var battle_start_delay := 0.0
var axeman_ground_position := Vector2.ZERO
var pending_spawn_lands := 0
var summoned_axeman_count := 0
var camera_base_y := 0.0
var camera_shake_time := 0.0
var camera_shake_duration := 0.0
var camera_shake_strength := Vector2.ZERO
var camera_shake_direction := Vector2.ZERO
var camera_shake_type: StringName = SCREEN_SHAKE_RANDOM
var camera_rng := RandomNumberGenerator.new()
var parallax_sprite_base_positions := {}
var active_enemies: Array[Node] = []
var current_boss_enemy: Node = null

@onready var player = $Player
@onready var camera_2d: Camera2D = $Camera2D
@onready var parallax_background: ParallaxBackground = $ParallaxBackground
@onready var axeman_template = $Axeman
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
	axeman_ground_position = axeman_template.global_position
	camera_base_y = player.global_position.y
	_cache_parallax_sprites()
	_bind_health_bar(player, player_health_bar)
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
			for enemy in active_enemies:
				if is_instance_valid(enemy):
					enemy.begin_battle()

	if summon_started or battle_start_pending:
		return

	if player_near_flag and summoned_axeman_count < AXEMAN_SUMMON_COUNT and Input.is_action_just_pressed("interact"):
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


func _bind_flag() -> void:
	flag_area.body_entered.connect(_on_flag_body_entered)
	flag_area.body_exited.connect(_on_flag_body_exited)
	flag.set_highlighted(false)
	interact_label.visible = false


func _prepare_encounter() -> void:
	axeman_template.set_battle_active(false)
	axeman_template.visible = false
	boss_label.visible = false
	boss_health_bar.visible = false
	active_enemies.clear()
	pending_spawn_lands = 0
	current_boss_enemy = null
	summoned_axeman_count = 0


func _on_flag_body_entered(body: Node) -> void:
	if body != player or summon_started or battle_start_pending:
		return

	player_near_flag = true
	flag.set_highlighted(true)
	interact_label.visible = true


func _on_flag_body_exited(body: Node) -> void:
	if body != player:
		return

	player_near_flag = false
	if not summon_started and not battle_start_pending:
		flag.set_highlighted(false)
		interact_label.visible = false


func _start_encounter() -> void:
	summon_started = true
	flag.set_highlighted(false)
	interact_label.visible = false
	_spawn_single_axeman()


func _on_axeman_landed() -> void:
	pending_spawn_lands = maxi(pending_spawn_lands - 1, 0)
	trigger_camera_shake_downward()
	if pending_spawn_lands > 0:
		return

	summon_started = false
	boss_label.visible = not active_enemies.is_empty()
	boss_health_bar.visible = not active_enemies.is_empty()
	if not active_enemies.is_empty():
		_set_current_boss_enemy(active_enemies[0])
	if battle_started:
		var latest_enemy = active_enemies[active_enemies.size() - 1]
		if is_instance_valid(latest_enemy):
			latest_enemy.begin_battle()
	else:
		battle_start_pending = true
		battle_start_delay = camera_shake_duration + BATTLE_START_EXTRA_DELAY

	if player_near_flag and summoned_axeman_count < AXEMAN_SUMMON_COUNT:
		flag.set_highlighted(true)
		interact_label.visible = true


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


func _spawn_single_axeman() -> void:
	pending_spawn_lands += 1
	var enemy = _create_axeman_instance()
	var formation_offset: float = float(summoned_axeman_count) * AXEMAN_FORMATION_SPACING_X
	var ground_position: Vector2 = Vector2(flag.global_position.x + AXEMAN_DROP_OFFSET_X + formation_offset, axeman_ground_position.y)
	var spawn_position: Vector2 = ground_position + Vector2(0.0, -AXEMAN_DROP_HEIGHT)
	summoned_axeman_count += 1
	enemy.start_spawn_fall(spawn_position)


func _create_axeman_instance() -> Node:
	var enemy = AXEMAN_SCENE.instantiate()
	enemy.scale = axeman_template.scale
	enemy.visible = false
	add_child(enemy)
	active_enemies.append(enemy)
	_bind_enemy(enemy)
	return enemy


func _bind_enemy(enemy: Node) -> void:
	enemy.health_changed.connect(func(current: int, maximum: int) -> void:
		if enemy != current_boss_enemy:
			return
		boss_health_bar.max_value = maximum
		boss_health_bar.value = current
	)
	enemy.died.connect(func() -> void:
		_on_enemy_died(enemy)
	)
	enemy.landed.connect(_on_axeman_landed)


func _on_enemy_died(enemy: Node) -> void:
	active_enemies = active_enemies.filter(func(existing: Node) -> bool:
		return is_instance_valid(existing) and existing != enemy
	)

	if active_enemies.is_empty():
		current_boss_enemy = null
		boss_health_bar.visible = false
		boss_label.visible = false
		if summoned_axeman_count >= AXEMAN_SUMMON_COUNT:
			_show_result("You Win")
		elif player_near_flag:
			flag.set_highlighted(true)
			interact_label.visible = true
		return

	var next_enemy = active_enemies[0]
	if is_instance_valid(next_enemy):
		_set_current_boss_enemy(next_enemy)


func _clear_active_enemies() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	current_boss_enemy = null


func _set_current_boss_enemy(enemy: Node) -> void:
	current_boss_enemy = enemy
	if current_boss_enemy == null or not is_instance_valid(current_boss_enemy):
		boss_health_bar.visible = false
		return

	boss_health_bar.visible = true
	boss_health_bar.max_value = current_boss_enemy.get_max_health()
	boss_health_bar.value = current_boss_enemy.current_health
