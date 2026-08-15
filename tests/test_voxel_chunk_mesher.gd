class_name TestVoxelChunkMesher
extends Node

const MESHER: Script = preload("res://scripts/voxel_chunk_mesher.gd")
const CHUNK_SIZE: int = 16
const GRASS: String = "grass"
const DIRT: String = "dirt"


func _bottoms_for(positions: Array[Vector3i], bottom_y: int = -1) -> Dictionary:
	var bottoms: Dictionary = {}
	for pos: Vector3i in positions:
		bottoms[Vector2i(pos.x, pos.z)] = bottom_y
	return bottoms


func _chunk_index(positions: Array[Vector3i]) -> Dictionary:
	var index: Dictionary = {}
	for pos: Vector3i in positions:
		index[pos] = true
	return index


func test_single_block_emits_six_quads() -> void:
	var positions: Array[Vector3i] = [Vector3i.ZERO]
	var blocks: Dictionary = {Vector3i.ZERO: DIRT}
	var surfaces: Dictionary = MESHER.build(Vector2i.ZERO, blocks, _chunk_index(positions), _bottoms_for(positions), CHUNK_SIZE, GRASS, DIRT)
	assert(MESHER.quad_count(surfaces) == 6)


func test_adjacent_blocks_remove_shared_face_and_greedy_merge() -> void:
	var positions: Array[Vector3i] = [Vector3i.ZERO, Vector3i.RIGHT]
	var blocks: Dictionary = {Vector3i.ZERO: DIRT, Vector3i.RIGHT: DIRT}
	var surfaces: Dictionary = MESHER.build(Vector2i.ZERO, blocks, _chunk_index(positions), _bottoms_for(positions), CHUNK_SIZE, GRASS, DIRT)
	assert(MESHER.quad_count(surfaces) == 6)


func test_grass_uses_grass_top_and_dirt_sides() -> void:
	var positions: Array[Vector3i] = [Vector3i.ZERO]
	var blocks: Dictionary = {Vector3i.ZERO: GRASS}
	var surfaces: Dictionary = MESHER.build(Vector2i.ZERO, blocks, _chunk_index(positions), _bottoms_for(positions), CHUNK_SIZE, GRASS, DIRT)
	assert(surfaces.has(GRASS))
	assert(surfaces.has(DIRT))
	assert((surfaces[GRASS]["indices"] as Array).size() == 6)
	assert((surfaces[DIRT]["indices"] as Array).size() == 30)


func test_neighbor_chunk_block_hides_shared_border_face() -> void:
	var local_pos: Vector3i = Vector3i(15, 0, 0)
	var neighbor_pos: Vector3i = Vector3i(16, 0, 0)
	var positions: Array[Vector3i] = [local_pos]
	var blocks: Dictionary = {local_pos: DIRT, neighbor_pos: DIRT}
	var surfaces: Dictionary = MESHER.build(Vector2i.ZERO, blocks, _chunk_index(positions), _bottoms_for([local_pos, neighbor_pos]), CHUNK_SIZE, GRASS, DIRT)
	assert(MESHER.quad_count(surfaces) == 5)


func test_generated_underside_face_is_suppressed() -> void:
	var positions: Array[Vector3i] = [Vector3i.ZERO]
	var blocks: Dictionary = {Vector3i.ZERO: DIRT}
	var surfaces: Dictionary = MESHER.build(Vector2i.ZERO, blocks, _chunk_index(positions), _bottoms_for(positions, 0), CHUNK_SIZE, GRASS, DIRT)
	assert(MESHER.quad_count(surfaces) == 5)
