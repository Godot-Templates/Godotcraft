class_name Cow
extends CharacterBody3D

## A sturdy wandering cow mob with a simple blocky walk animation.

const GRAVITY: float = 25.0
const WALK_SPEED: float = 0.8
const WANDER_MIN_SEC: float = 3.0
const WANDER_MAX_SEC: float = 7.0
const MAX_HEALTH: int = 7
const HIT_FLASH_SEC: float = 0.15
const KNOCKBACK_SPEED: float = 2.5
const MID_SIM_INTERVAL: float = AnimalLodPolicy.MID_SIM_INTERVAL

var _wander_dir: Vector3 = Vector3.ZERO
var _wander_time_left: float = 0.0
var _materials: Array[StandardMaterial3D] = []
var _material_base_colors: Dictionary = {}
var _walk_phase: float = 0.0
var _health: int = MAX_HEALTH
var _hit_flash_time: float = 0.0
var _dead: bool = false
var _player: Node3D
var _world: World
var _lod_accum: float = 0.0
var _full_animation: bool = true
var _far_sleeping: bool = false

@onready var _model: Node3D = $Model
@onready var _front_left_leg: MeshInstance3D = $Model/FrontLeftLeg
@onready var _front_right_leg: MeshInstance3D = $Model/FrontRightLeg
@onready var _back_left_leg: MeshInstance3D = $Model/BackLeftLeg
@onready var _back_right_leg: MeshInstance3D = $Model/BackRightLeg


func _ready() -> void:
	add_to_group("cow")
	collision_layer = 1
	collision_mask = 1
	_cache_model_materials()
	_pick_new_wander_dir()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var simulation_delta: float = _lod_simulation_delta(delta)
	if simulation_delta <= 0.0:
		return
	var movement_scale: float = simulation_delta / delta
	if not is_on_floor():
		velocity.y -= GRAVITY * simulation_delta
	else:
		velocity.y = 0.0

	_wander_time_left -= simulation_delta
	if _wander_time_left <= 0.0:
		_pick_new_wander_dir()

	if _hit_flash_time <= 0.0:
		velocity.x = _wander_dir.x * WALK_SPEED * movement_scale
		velocity.z = _wander_dir.z * WALK_SPEED * movement_scale
		if _wander_dir.length() > 0.01:
			look_at(global_position + _wander_dir, Vector3.UP)
	move_and_slide()
	if _full_animation:
		_animate_model(delta)

	if _hit_flash_time > 0.0:
		_hit_flash_time = max(0.0, _hit_flash_time - simulation_delta)
		if _hit_flash_time == 0.0:
			_restore_material_colors()


func _lod_simulation_delta(delta: float) -> float:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	var distance_sq: float = 0.0 if _player == null else global_position.distance_squared_to(_player.global_position)
	var tier: int = AnimalLodPolicy.tier_for_distance_squared(distance_sq)
	if tier == AnimalLodPolicy.Tier.SLEEPING or not _terrain_collision_ready():
		_set_far_sleeping(true)
		_lod_accum = 0.0
		return 0.0
	_set_far_sleeping(false)
	if tier == AnimalLodPolicy.Tier.THROTTLED:
		_full_animation = false
		_lod_accum += delta
		if _lod_accum < MID_SIM_INTERVAL:
			return 0.0
		var accumulated: float = _lod_accum
		_lod_accum = 0.0
		return accumulated
	_full_animation = true
	_lod_accum = 0.0
	return delta


func _terrain_collision_ready() -> bool:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group(&"world") as World
	return _world == null or _world.is_collision_ready_at(global_position)


func _set_far_sleeping(sleeping: bool) -> void:
	if _far_sleeping == sleeping:
		return
	_far_sleeping = sleeping
	_model.visible = not sleeping
	if sleeping:
		velocity = Vector3.ZERO


func _pick_new_wander_dir() -> void:
	_wander_time_left = randf_range(WANDER_MIN_SEC, WANDER_MAX_SEC)
	var angle: float = randf_range(0.0, TAU)
	if randf() < 0.35:
		_wander_dir = Vector3.ZERO
	else:
		_wander_dir = Vector3(cos(angle), 0.0, sin(angle))


func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	_health -= amount
	_hit_flash_time = HIT_FLASH_SEC
	_flash_materials()
	var away: Vector3 = -_wander_dir
	if away.length() <= 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	velocity.x = away.x * KNOCKBACK_SPEED
	velocity.z = away.z * KNOCKBACK_SPEED
	if _health <= 0:
		_die()


func _die() -> void:
	_dead = true
	queue_free()


func _cache_model_materials() -> void:
	var animated_roots: Array[MeshInstance3D] = [
		_front_left_leg, _front_right_leg, _back_left_leg, _back_right_leg,
	]
	_materials = AnimalMeshBatcher.optimize(_model, animated_roots)
	_material_base_colors.clear()
	for material: StandardMaterial3D in _materials:
		_material_base_colors[material] = material.albedo_color


func _animate_model(delta: float) -> void:
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.1 and is_on_floor()
	var leg_swing: float = 0.0
	var target_bob: float = 0.0
	if moving:
		_walk_phase += delta * 5.5
		leg_swing = sin(_walk_phase) * 0.3
		target_bob = abs(sin(_walk_phase * 2.0)) * 0.025
	_front_left_leg.rotation.x = lerp_angle(_front_left_leg.rotation.x, leg_swing, min(1.0, delta * 9.0))
	_back_right_leg.rotation.x = lerp_angle(_back_right_leg.rotation.x, leg_swing, min(1.0, delta * 9.0))
	_front_right_leg.rotation.x = lerp_angle(_front_right_leg.rotation.x, -leg_swing, min(1.0, delta * 9.0))
	_back_left_leg.rotation.x = lerp_angle(_back_left_leg.rotation.x, -leg_swing, min(1.0, delta * 9.0))
	_model.position.y = lerp(_model.position.y, target_bob, min(1.0, delta * 8.0))


func _flash_materials() -> void:
	for material: StandardMaterial3D in _materials:
		var base_color: Color = _material_base_colors.get(material, Color.WHITE)
		material.albedo_color = base_color.lerp(Color(1.0, 0.12, 0.1), 0.7)


func _restore_material_colors() -> void:
	for material: StandardMaterial3D in _materials:
		material.albedo_color = _material_base_colors.get(material, Color.WHITE)
