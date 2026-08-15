class_name CowSpawner
extends Node3D

## Spawns a small herd of wandering cows around world spawn on ready.

@export var world_path: NodePath
@export var cow_scene: PackedScene = preload("res://scenes/cow.tscn")
@export var spawn_count: int = 3
@export var spawn_min_radius: int = 10
@export var spawn_max_radius: int = 20

var _world: Node


func _ready() -> void:
	if world_path != NodePath(""):
		_world = get_node_or_null(world_path)
	if _world == null or cow_scene == null:
		return
	for index: int in spawn_count:
		call_deferred("_spawn_one")


func _spawn_one() -> void:
	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(float(spawn_min_radius), float(spawn_max_radius))
	var x: int = int(round(cos(angle) * radius))
	var z: int = int(round(sin(angle) * radius))
	var y: int = _world.get_surface_y(x, z)
	var cow: Node3D = cow_scene.instantiate()
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	parent.add_child(cow)
	cow.global_position = Vector3(float(x) + 0.5, float(y) + 0.1, float(z) + 0.5)
