class_name Chicken
extends CharacterBody3D

## A wandering chicken mob. Picks a random walk direction every few seconds
## and periodically drops a feather — but ONLY while Weather.is_raining.

const GRAVITY: float = 25.0
const WALK_SPEED: float = 1.2
const WANDER_MIN_SEC: float = 2.0
const WANDER_MAX_SEC: float = 5.0
const DROP_MIN_SEC: float = 8.0
const DROP_MAX_SEC: float = 16.0
const FEATHER_TEXTURE_PATH: String = "res://assets/generated/feather_frame_0.png"
const MAX_HEALTH: int = 3
const HIT_FLASH_SEC: float = 0.15
const KNOCKBACK_SPEED: float = 3.5
const DEATH_FEATHER_MIN: int = 1
const DEATH_FEATHER_MAX: int = 2

var _wander_dir: Vector3 = Vector3.ZERO
var _wander_time_left: float = 0.0
var _drop_time_left: float = randf_range(DROP_MIN_SEC, DROP_MAX_SEC)
var _weather: Node
var _feather_texture: Texture2D = load(FEATHER_TEXTURE_PATH)
@onready var _model: Node3D = $Model
@onready var _left_leg: MeshInstance3D = $Model/LeftLeg
@onready var _right_leg: MeshInstance3D = $Model/RightLeg
@onready var _left_wing: MeshInstance3D = $Model/LeftWing
@onready var _right_wing: MeshInstance3D = $Model/RightWing
var _materials: Array[StandardMaterial3D] = []
var _material_base_colors: Dictionary = {}
var _walk_phase: float = 0.0
var _health: int = MAX_HEALTH
var _hit_flash_time: float = 0.0
var _dead: bool = false


func _ready() -> void:
	add_to_group("chicken")
	collision_layer = 1
	collision_mask = 1
	_cache_model_materials()
	_weather = get_tree().get_first_node_in_group("weather")
	_pick_new_wander_dir()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _weather == null:
		_weather = get_tree().get_first_node_in_group("weather")

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	_wander_time_left -= delta
	if _wander_time_left <= 0.0:
		_pick_new_wander_dir()

	if _hit_flash_time <= 0.0:
		velocity.x = _wander_dir.x * WALK_SPEED
		velocity.z = _wander_dir.z * WALK_SPEED
		if _wander_dir.length() > 0.01:
			look_at(global_position + _wander_dir, Vector3.UP)
	move_and_slide()
	_animate_model(delta)

	if _hit_flash_time > 0.0:
		_hit_flash_time = max(0.0, _hit_flash_time - delta)
		if _hit_flash_time == 0.0:
			_restore_material_colors()

	_drop_time_left -= delta
	if _drop_time_left <= 0.0:
		_drop_time_left = randf_range(DROP_MIN_SEC, DROP_MAX_SEC)
		_maybe_drop_feather()


func _pick_new_wander_dir() -> void:
	_wander_time_left = randf_range(WANDER_MIN_SEC, WANDER_MAX_SEC)
	var angle: float = randf_range(0.0, TAU)
	# Small chance to just stand still, like a real chicken deciding nothing matters.
	if randf() < 0.25:
		_wander_dir = Vector3.ZERO
	else:
		_wander_dir = Vector3(cos(angle), 0.0, sin(angle))


func _maybe_drop_feather() -> void:
	var raining: bool = _weather != null and _weather.get("is_raining") == true
	if not raining:
		return
	var drop: ItemDrop = ItemDrop.new()
	drop.block_type = "feather"
	drop.block_texture = _feather_texture
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	parent.add_child(drop)
	drop.global_position = global_position + Vector3(0.0, 0.6, 0.0)


func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	_health -= amount
	_hit_flash_time = HIT_FLASH_SEC
	_flash_materials()
	# A little knockback away from where the hit came from (away from wander dir works
	# fine as a cheap "flinch" — good enough without needing the attacker's position).
	var away: Vector3 = -_wander_dir if _wander_dir.length() > 0.01 else Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	velocity.x = away.x * KNOCKBACK_SPEED
	velocity.z = away.z * KNOCKBACK_SPEED
	if _health <= 0:
		_die()


func _die() -> void:
	_dead = true
	var count: int = randi_range(DEATH_FEATHER_MIN, DEATH_FEATHER_MAX)
	for i in count:
		var drop: ItemDrop = ItemDrop.new()
		drop.block_type = "feather"
		drop.block_texture = _feather_texture
		var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
		parent.add_child(drop)
		drop.global_position = global_position + Vector3(0.0, 0.6, 0.0) + Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
	queue_free()


func _cache_model_materials() -> void:
	_materials.clear()
	_material_base_colors.clear()
	var material_copies: Dictionary = {}
	for child: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = child as MeshInstance3D
		var source_mesh: PrimitiveMesh = part.mesh as PrimitiveMesh
		if source_mesh == null or not source_mesh.material is StandardMaterial3D:
			continue
		# Mesh and material resources from the scene are shared by default. Duplicate
		# them per chicken so one chicken's damage flash never tints the whole flock.
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
	if _model == null:
		return
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.1 and is_on_floor()
	var leg_swing: float = 0.0
	var wing_swing: float = 0.0
	var target_bob: float = 0.0
	if moving:
		_walk_phase += delta * 9.0
		leg_swing = sin(_walk_phase) * 0.45
		wing_swing = sin(_walk_phase * 2.0) * 0.06
		target_bob = abs(sin(_walk_phase)) * 0.035
	_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, leg_swing, min(1.0, delta * 12.0))
	_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, -leg_swing, min(1.0, delta * 12.0))
	_left_wing.rotation.z = lerp_angle(
		_left_wing.rotation.z, -0.12 - wing_swing, min(1.0, delta * 10.0)
	)
	_right_wing.rotation.z = lerp_angle(
		_right_wing.rotation.z, 0.12 + wing_swing, min(1.0, delta * 10.0)
	)
	_model.position.y = lerp(_model.position.y, target_bob, min(1.0, delta * 10.0))


func _flash_materials() -> void:
	for material: StandardMaterial3D in _materials:
		var base_color: Color = _material_base_colors.get(material, Color.WHITE)
		material.albedo_color = base_color.lerp(Color(1.0, 0.12, 0.1), 0.7)


func _restore_material_colors() -> void:
	for material: StandardMaterial3D in _materials:
		material.albedo_color = _material_base_colors.get(material, Color.WHITE)
