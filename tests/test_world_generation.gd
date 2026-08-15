class_name TestWorldGeneration
extends Node

const WORLD_SCRIPT: Script = preload("res://scripts/world.gd")


func _world_for_seed(seed_value: int) -> World:
	var world: World = WORLD_SCRIPT.new() as World
	world.world_seed = seed_value
	world._build_noises()
	return world


func test_same_seed_repeats_identical_columns_and_caves() -> void:
	var first: World = _world_for_seed(24681357)
	var second: World = _world_for_seed(24681357)
	for x in range(-96, 97, 13):
		for z in range(-96, 97, 17):
			var first_info: Array = first._column_info(x, z)
			var second_info: Array = second._column_info(x, z)
			assert(first_info == second_info)
			var surface_y: int = first_info[0]
			for depth in range(first.CAVE_MIN_DEPTH, first.SURFACE_DEPTH):
				assert(first._is_cave(x, surface_y - depth, z, surface_y) \
					== second._is_cave(x, surface_y - depth, z, surface_y))


func test_different_seeds_change_the_starting_world() -> void:
	var first: World = _world_for_seed(1111)
	var second: World = _world_for_seed(2222)
	var differences: int = 0
	for x in range(-64, 65, 8):
		for z in range(-64, 65, 8):
			if first._column_info(x, z) != second._column_info(x, z):
				differences += 1
	assert(differences > 20)


func test_generation_contains_flat_land_and_mountain_relief() -> void:
	var world: World = _world_for_seed(1337)
	var min_height: int = 2147483647
	var max_height: int = -2147483648
	var flat_edges: int = 0
	var sampled_edges: int = 0
	for x in range(-128, 128, 4):
		for z in range(-128, 128, 4):
			var height: int = world._column_info(x, z)[0]
			var next_height: int = world._column_info(x + 4, z)[0]
			min_height = mini(min_height, height)
			max_height = maxi(max_height, height)
			sampled_edges += 1
			if absi(height - next_height) <= 1:
				flat_edges += 1
	assert(max_height - min_height >= 20)
	assert(float(flat_edges) / float(sampled_edges) >= 0.25)


func test_caves_exist_but_keep_roof_and_bottom_solid() -> void:
	var world: World = _world_for_seed(1337)
	var cave_cells: int = 0
	for x in range(-48, 49, 4):
		for z in range(-48, 49, 4):
			var surface_y: int = world._column_info(x, z)[0]
			assert(not world._is_cave(x, surface_y - 1, z, surface_y))
			assert(not world._is_cave(x, surface_y - world.SURFACE_DEPTH, z, surface_y))
			for depth in range(world.CAVE_MIN_DEPTH, world.SURFACE_DEPTH):
				if world._is_cave(x, surface_y - depth, z, surface_y):
					cave_cells += 1
	assert(cave_cells > 30)


func test_animal_spawn_rejects_generated_tree_columns() -> void:
	var world: World = _world_for_seed(1337)
	var cache: Dictionary = {}
	var tree_found: bool = false
	for x in range(-64, 65):
		for z in range(-64, 65):
			if not world._tree_at(x, z, cache):
				continue
			tree_found = true
			assert(not world.is_safe_animal_spawn(x, z))
			assert(world.get_ground_surface_y(x, z) == world._column_info(x, z)[0] + 1)
			break
		if tree_found:
			break
	assert(tree_found)
