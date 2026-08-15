class_name TestAnimalLod
extends Node


func test_distance_policy_uses_full_mid_and_sleep_tiers() -> void:
	assert(AnimalLodPolicy.tier_for_distance_squared(0.0) == AnimalLodPolicy.Tier.FULL)
	assert(AnimalLodPolicy.tier_for_distance_squared(24.0 * 24.0) == AnimalLodPolicy.Tier.FULL)
	assert(AnimalLodPolicy.tier_for_distance_squared(30.0 * 30.0) == AnimalLodPolicy.Tier.THROTTLED)
	assert(AnimalLodPolicy.tier_for_distance_squared(48.0 * 48.0) == AnimalLodPolicy.Tier.THROTTLED)
	assert(AnimalLodPolicy.tier_for_distance_squared(60.0 * 60.0) == AnimalLodPolicy.Tier.SLEEPING)


func test_world_collision_window_covers_active_animals() -> void:
	assert(World.COLLISION_DISTANCE * World.CHUNK_SIZE >= int(AnimalLodPolicy.SLEEP_DISTANCE))


func test_world_reports_collision_readiness_per_chunk() -> void:
	var world: World = World.new()
	var coord: Vector2i = Vector2i(2, -1)
	var position: Vector3 = Vector3(33.0, 4.0, -2.0)
	assert(not world.is_collision_ready_at(position))
	world._loaded[coord] = true
	assert(not world.is_collision_ready_at(position))
	var shape: CollisionShape3D = CollisionShape3D.new()
	world._chunk_collision_shapes[coord] = shape
	assert(world.is_collision_ready_at(position))
	shape.free()
	world.free()
