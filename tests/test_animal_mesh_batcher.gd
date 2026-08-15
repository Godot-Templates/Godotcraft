class_name TestAnimalMeshBatcher
extends Node

const BATCHER: Script = preload("res://scripts/animal_mesh_batcher.gd")


func _optimized_mesh_count(scene_path: String, animated_names: Array[String]) -> Array[int]:
	var scene: PackedScene = load(scene_path) as PackedScene
	var animal: Node3D = scene.instantiate() as Node3D
	var model: Node3D = animal.get_node("Model") as Node3D
	var before: int = model.find_children("*", "MeshInstance3D", true, false).size()
	var animated_roots: Array[MeshInstance3D] = []
	for part_name: String in animated_names:
		animated_roots.append(model.get_node(part_name) as MeshInstance3D)
	var materials: Array[StandardMaterial3D] = BATCHER.optimize(model, animated_roots)
	var after: int = model.find_children("*", "MeshInstance3D", true, false).size()
	assert(not materials.is_empty())
	var minor_details: MeshInstance3D = model.get_node_or_null("MinorDetails") as MeshInstance3D
	if minor_details != null:
		assert(minor_details.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	animal.free()
	return [before, after]


func test_four_legged_animals_batch_static_parts_and_hooves() -> void:
	var animated: Array[String] = ["FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg"]
	for path: String in ["res://scenes/pig.tscn", "res://scenes/sheep.tscn", "res://scenes/cow.tscn"]:
		var counts: Array[int] = _optimized_mesh_count(path, animated)
		assert(counts[1] < counts[0])


func test_cat_keeps_tail_pivot_but_batches_static_details() -> void:
	var animated: Array[String] = ["FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg", "Tail"]
	var counts: Array[int] = _optimized_mesh_count("res://scenes/cat.tscn", animated)
	assert(counts[1] < counts[0])


func test_chicken_keeps_leg_and_wing_pivots() -> void:
	var animated: Array[String] = ["LeftLeg", "RightLeg", "LeftWing", "RightWing"]
	var counts: Array[int] = _optimized_mesh_count("res://scenes/chicken.tscn", animated)
	assert(counts[1] < counts[0])
