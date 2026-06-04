class_name ItemDrop
extends RigidBody3D

## A dropped block, post-mining. RigidBody falls naturally; within MAGNET_RANGE
## we override velocity to home in on the player, and within PICKUP_RANGE we
## hand the type to the HUD and queue_free. Collides with world only (not player).

const MAGNET_RANGE: float = 2.0
const PICKUP_RANGE: float = 0.6
const MAGNET_SPEED: float = 7.0
const SIZE: float = 0.32

@export var block_type: String = ""
@export var block_texture: Texture2D

var _player: Node3D
var _hud: Node


func _ready() -> void:
    add_to_group("item_drop")
    _build_visuals_and_collider()
    # World collides on layer 1; we sit on layer 4 and only listen to layer 1 — never collide with the player.
    collision_layer = 4
    collision_mask = 1
    # A tiny pop so dropped items don't stack on each other invisibly.
    linear_velocity = Vector3(0.0, 1.5, 0.0)
    # Resolve refs lazily from groups.
    _player = get_tree().get_first_node_in_group("player")
    var huds: Array = get_tree().get_nodes_in_group("hud")
    if not huds.is_empty():
        _hud = huds[0]


func _build_visuals_and_collider() -> void:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(SIZE, SIZE, SIZE)
    if block_texture != null:
        var mat: StandardMaterial3D = StandardMaterial3D.new()
        mat.albedo_texture = block_texture
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
        mesh.material = mat
    var mesh_inst: MeshInstance3D = MeshInstance3D.new()
    mesh_inst.mesh = mesh
    mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mesh_inst)

    var shape: BoxShape3D = BoxShape3D.new()
    shape.size = Vector3(SIZE, SIZE, SIZE)
    var collider: CollisionShape3D = CollisionShape3D.new()
    collider.shape = shape
    add_child(collider)


func _physics_process(_delta: float) -> void:
    if _player == null:
        _player = get_tree().get_first_node_in_group("player")
        if _player == null:
            return
    # Target the player's chest so the pickup feels natural.
    var target: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)
    var to_player: Vector3 = target - global_position
    var dist: float = to_player.length()

    if dist <= PICKUP_RANGE:
        _pickup()
        return

    if dist <= MAGNET_RANGE:
        # Override the rigid body's velocity to fly toward the player.
        linear_velocity = to_player.normalized() * MAGNET_SPEED


func _pickup() -> void:
    if _hud != null and _hud.has_method("add_item") and block_type != "":
        _hud.add_item(block_type, 1)
    queue_free()
