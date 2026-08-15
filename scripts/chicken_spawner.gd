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
    var spawn: Dictionary = _world.find_safe_animal_spawn(spawn_min_radius, spawn_max_radius)
    if spawn.is_empty():
        return
    var chicken: Node3D = chicken_scene.instantiate()
    var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
    parent.add_child(chicken)
    chicken.global_position = spawn["position"] as Vector3
