class_name PassiveAnimalSpawner
extends Node3D

## Spawns one species of passive animal around world spawn on ready.

@export var world_path: NodePath
@export var animal_scene: PackedScene
@export var spawn_count: int = 3
@export var spawn_min_radius: int = 8
@export var spawn_max_radius: int = 20

var _world: Node


func _ready() -> void:
	if world_path != NodePath(""):
		_world = get_node_or_null(world_path)
	if _world == null or animal_scene == null:
		return
	for index: int in spawn_count:
		call_deferred("_spawn_one")


func _spawn_one() -> void:
	var spawn: Dictionary = _world.find_safe_animal_spawn(spawn_min_radius, spawn_max_radius)
	if spawn.is_empty():
		return
	var animal: Node3D = animal_scene.instantiate()
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	parent.add_child(animal)
	animal.global_position = spawn["position"] as Vector3
