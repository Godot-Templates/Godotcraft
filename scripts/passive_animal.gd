class_name PassiveAnimal
extends CharacterBody3D

## Shared wandering, damage, and blocky walk behavior for passive four-legged mobs.

const GRAVITY: float = 25.0
const HIT_FLASH_SEC: float = 0.15
const KNOCKBACK_SPEED: float = 3.0
const WANDER_MIN_SEC: float = 2.5
const WANDER_MAX_SEC: float = 6.0

@export var animal_group: StringName = &"animal"
@export var walk_speed: float = 1.0
@export var max_health: int = 5
@export_range(0.0, 1.0) var idle_chance: float = 0.3
@export var walk_cycle_speed: float = 7.0

var _wander_dir: Vector3 = Vector3.ZERO
var _wander_time_left: float = 0.0
var _materials: Array[StandardMaterial3D] = []
var _material_base_colors: Dictionary = {}
var _walk_phase: float = 0.0
var _health: int = 1
var _hit_flash_time: float = 0.0
var _dead: bool = false

@onready var _model: Node3D = $Model
@onready var _front_left_leg: MeshInstance3D = $Model/FrontLeftLeg
@onready var _front_right_leg: MeshInstance3D = $Model/FrontRightLeg
@onready var _back_left_leg: MeshInstance3D = $Model/BackLeftLeg
@onready var _back_right_leg: MeshInstance3D = $Model/BackRightLeg
@onready var _tail: MeshInstance3D = get_node_or_null("Model/Tail") as MeshInstance3D


func _ready() -> void:
	add_to_group(animal_group)
	add_to_group(&"passive_animal")
	collision_layer = 1
	collision_mask = 1
	_health = max_health
	_cache_model_materials()
	_pick_new_wander_dir()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	_wander_time_left -= delta
	if _wander_time_left <= 0.0:
		_pick_new_wander_dir()

	if _hit_flash_time <= 0.0:
		velocity.x = _wander_dir.x * walk_speed
		velocity.z = _wander_dir.z * walk_speed
		if _wander_dir.length() > 0.01:
			look_at(global_position + _wander_dir, Vector3.UP)
	move_and_slide()
	_animate_model(delta)

	if _hit_flash_time > 0.0:
		_hit_flash_time = max(0.0, _hit_flash_time - delta)
		if _hit_flash_time == 0.0:
			_restore_material_colors()


func _pick_new_wander_dir() -> void:
	_wander_time_left = randf_range(WANDER_MIN_SEC, WANDER_MAX_SEC)
	var angle: float = randf_range(0.0, TAU)
	if randf() < idle_chance:
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
		_dead = true
		queue_free()


func _cache_model_materials() -> void:
	var material_copies: Dictionary = {}
	for child: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = child as MeshInstance3D
		var source_mesh: PrimitiveMesh = part.mesh as PrimitiveMesh
		if source_mesh == null or not source_mesh.material is StandardMaterial3D:
			continue
		var mesh_copy: PrimitiveMesh = source_mesh.duplicate() as PrimitiveMesh
		var source_material: StandardMaterial3D = source_mesh.material as StandardMaterial3D
		var material: StandardMaterial3D
		if material_copies.has(source_material):
			material = material_copies[source_material] as StandardMaterial3D
		else:
			material = source_material.duplicate() as StandardMaterial3D
			material_copies[source_material] = material
			_materials.append(material)
			_material_base_colors[material] = material.albedo_color
		mesh_copy.material = material
		part.mesh = mesh_copy


func _animate_model(delta: float) -> void:
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.1 and is_on_floor()
	var leg_swing: float = 0.0
	var target_bob: float = 0.0
	if moving:
		_walk_phase += delta * walk_cycle_speed
		leg_swing = sin(_walk_phase) * 0.35
		target_bob = abs(sin(_walk_phase * 2.0)) * 0.025
	_front_left_leg.rotation.x = lerp_angle(_front_left_leg.rotation.x, leg_swing, min(1.0, delta * 10.0))
	_back_right_leg.rotation.x = lerp_angle(_back_right_leg.rotation.x, leg_swing, min(1.0, delta * 10.0))
	_front_right_leg.rotation.x = lerp_angle(_front_right_leg.rotation.x, -leg_swing, min(1.0, delta * 10.0))
	_back_left_leg.rotation.x = lerp_angle(_back_left_leg.rotation.x, -leg_swing, min(1.0, delta * 10.0))
	_model.position.y = lerp(_model.position.y, target_bob, min(1.0, delta * 9.0))
	if _tail != null:
		var tail_swing: float = sin(_walk_phase * 0.7) * 0.18 if moving else sin(Time.get_ticks_msec() * 0.003) * 0.08
		_tail.rotation.y = lerp_angle(_tail.rotation.y, tail_swing, min(1.0, delta * 5.0))


func _flash_materials() -> void:
	for material: StandardMaterial3D in _materials:
		var base_color: Color = _material_base_colors.get(material, Color.WHITE)
		material.albedo_color = base_color.lerp(Color(1.0, 0.12, 0.1), 0.7)


func _restore_material_colors() -> void:
	for material: StandardMaterial3D in _materials:
		material.albedo_color = _material_base_colors.get(material, Color.WHITE)
