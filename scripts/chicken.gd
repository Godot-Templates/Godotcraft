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
var _sprite: MeshInstance3D
var _sprite_mat: StandardMaterial3D
var _health: int = MAX_HEALTH
var _hit_flash_time: float = 0.0
var _dead: bool = false


func _ready() -> void:
	add_to_group("chicken")
	collision_layer = 1
	collision_mask = 1
	_build_collider()
	_build_sprite()
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

	if _hit_flash_time > 0.0:
		_hit_flash_time = max(0.0, _hit_flash_time - delta)
		if _hit_flash_time == 0.0 and _sprite_mat != null:
			_sprite_mat.albedo_color = Color.WHITE

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
	if _sprite_mat != null:
		_sprite_mat.albedo_color = Color(1.0, 0.35, 0.35)
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


func _build_collider() -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.7)
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, 0.25, 0.0)
	add_child(collider)


func _build_sprite() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/generated/chicken_frame_0.png")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.6, 0.6)
	mesh.material = mat
	_sprite_mat = mat

	_sprite = MeshInstance3D.new()
	_sprite.name = "Sprite"
	_sprite.mesh = mesh
	_sprite.position = Vector3(0.0, 0.35, 0.0)
	add_child(_sprite)
