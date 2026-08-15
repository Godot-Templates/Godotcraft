class_name ChickenSpawner
extends Node3D

## Spawns a handful of wandering chickens around world spawn on ready.

@export var world_path: NodePath
@export var chicken_scene: PackedScene = preload("res://scenes/chicken.tscn")
@export var spawn_count: int = 5
@export var spawn_min_radius: int = 6
@export var spawn_max_radius: int = 14

var _world: Node


func _ready() -> void:
    if world_path != NodePath(""):
        _world = get_node_or_null(world_path)
    if _world == null or chicken_scene == null:
        return
    for i in spawn_count:
        call_deferred("_spawn_one")


func _spawn_one() -> void:
    var angle: float = randf_range(0.0, TAU)
    var r: float = randf_range(float(spawn_min_radius), float(spawn_max_radius))
    var x: int = int(round(cos(angle) * r))
    var z: int = int(round(sin(angle) * r))
    var y: int = _world.get_surface_y(x, z)

    var chicken: Node3D = chicken_scene.instantiate()
    var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
    parent.add_child(chicken)
    chicken.global_position = Vector3(float(x) + 0.5, float(y) + 0.1, float(z) + 0.5)
