class_name World
extends Node3D

## Infinite, chunk-streamed voxel world.
##
## Terrain is a pure deterministic function of (x, y, z) and world_seed. Broad
## noise regions form plains and stepped plateaus, masked ridged noise forms tall
## mountain chains, and 3D noise carves caves below the surface. The world is
## split into CHUNK_SIZE x CHUNK_SIZE column chunks that stream around the player.
## Player edits are kept separately and re-applied when a chunk regenerates.
##
## Performance:
## - The expensive part of chunk generation (noise sampling for terrain and
##   trees) runs on WorkerThreadPool threads. It is a pure function of the
##   chunk coordinate, so workers touch no shared state; the main thread only
##   merges the finished block data and updates visuals/colliders, inside a
##   per-frame time budget, so streaming never blocks a frame for long.
## - Only *exposed* blocks (those with at least one open face) get a MultiMesh
##   instance and a collider. Buried blocks are pure dictionary data until
##   mining reveals them. This cuts instance and collider counts ~6x.
##
## Rendering: one MultiMeshInstance3D per block type. Grass additionally gets a
## green top quad from its own MultiMesh. Collision: one shared StaticBody3D
## with one CollisionShape3D per exposed block.

const CHUNK_SIZE: int = 16
const RENDER_DISTANCE: int = 5  # chunks (chebyshev radius) kept loaded around player
const UNLOAD_DISTANCE: int = 8  # chunks beyond this radius are unloaded
const INITIAL_SYNC_RADIUS: int = 1  # 3x3 generated synchronously (ground under spawn)
const INITIAL_STREAM_RADIUS: int = 6  # 13x13 initial world, streamed in the background
const COLLISION_DISTANCE: int = 1  # only chunks this close to the player get colliders
const GEN_BUDGET_USEC: int = 3500  # per-frame time budget for chunk work

const SURFACE_DEPTH: int = 24  # enough underground volume for explorable caves
const DEFAULT_SEED: int = 1337
const RUNTIME_SEED_SETTING: String = "game/runtime_world_seed"
const SEA_LEVEL: int = 0  # surface at-or-below this is sand (beaches)
const SNOW_LINE: int = 18  # above this, mountain tops turn to bare stone
const SPAWN_CLEAR_RADIUS: int = 6  # no trees this close to spawn
const CAVE_MIN_DEPTH: int = 4  # preserve a solid roof and safe spawn surface
const CAVE_BOTTOM_MARGIN: int = 2  # never open the generated world's underside

# A midpoint of 0.567 (down from 0.60) expands plateau regions by roughly 25%
# across representative seeds while preserving rolling plains and mountains.
const PLATEAU_MASK_LOW: float = 0.447
const PLATEAU_MASK_HIGH: float = 0.687
const PLATEAU_BLEND_STRENGTH: float = 0.95

# Biome ids (derived from temperature/moisture noise per column).
const BIOME_PLAINS: int = 0
const BIOME_FOREST: int = 1
const BIOME_DESERT: int = 2
const BIOME_MOUNTAINS: int = 3

# Trees use a jittered grid: one candidate spot per TREE_CELL x TREE_CELL cell,
# accepted with a per-biome percent chance. Pure function of position, so
# chunks can generate in any order and always agree.
const TREE_CELL: int = 4
const TREE_CELL_CHANCE: Dictionary = {
	BIOME_PLAINS: 14,
	BIOME_FOREST: 80,
	BIOME_DESERT: 0,
	BIOME_MOUNTAINS: 22,
}

const TYPE_DIRT: String = "dirt"
const TYPE_GRASS: String = "grass"
const TYPE_COBBLE: String = "cobble"
const TYPE_WOOD: String = "wood"
const TYPE_LEAVES: String = "leaves"
const TYPE_SAND: String = "sand"

const ALL_BODY_TYPES: Array = [
	TYPE_DIRT, TYPE_GRASS, TYPE_COBBLE, TYPE_WOOD, TYPE_LEAVES, TYPE_SAND,
]
const INITIAL_CAPACITY: Dictionary = {
	TYPE_DIRT: 6000,
	TYPE_GRASS: 12000,
	TYPE_COBBLE: 8000,
	TYPE_WOOD: 1500,
	TYPE_LEAVES: 5000,
	TYPE_SAND: 8000,
}
const GRASS_TOP_CAPACITY: int = 12000
const POOL_GROW_STEP: int = 2000
const OFFSCREEN: Vector3 = Vector3(0.0, -10000.0, 0.0)

@export var world_seed: int = DEFAULT_SEED
@export var dirt_texture: Texture2D
@export var grass_top_texture: Texture2D
@export var cobble_texture: Texture2D
@export var wood_texture: Texture2D
@export var leaves_texture: Texture2D
@export var sand_texture: Texture2D

var _shape: BoxShape3D
var _collision_body: StaticBody3D

var _mm_inst: Dictionary = {}  # type → MultiMeshInstance3D
var _mm_used: Dictionary = {}  # type → int (highest-ever-allocated index)
var _mm_free: Dictionary = {}  # type → Array[int] freed indices

var _grass_top_mm: MultiMeshInstance3D
var _grass_top_used: int = 0
var _grass_top_free: Array[int] = []

# World data. _block_types holds every loaded block (visible or buried).
# The idx/collider dicts only have entries for exposed (visible) blocks.
var _block_types: Dictionary = {}  # Vector3i → String
var _block_body_idx: Dictionary = {}  # Vector3i → int
var _block_top_idx: Dictionary = {}  # Vector3i → int (grass blocks)
var _block_colliders: Dictionary = {}  # Vector3i → CollisionShape3D

# Chunk streaming state.
var _chunk_blocks: Dictionary = {}  # Vector2i → Dictionary(Vector3i → true)
var _loaded: Dictionary = {}  # Vector2i → true (fully generated)
var _queued: Dictionary = {}  # Vector2i → true (job in queue)
var _job_queue: Array = []  # Array[Dictionary] streaming jobs (FIFO)
var _edits: Dictionary = {}  # Vector3i → String; "" means block removed
var _column_cache: Dictionary = {}  # Vector2i → Array [height, biome]

# Threaded generation. Workers compute pure chunk data and drop it into
# _gen_results under _gen_mutex; the main thread picks results up in _job_step.
var _gen_mutex: Mutex = Mutex.new()
var _gen_tasks: Dictionary = {}  # Vector2i → int (WorkerThreadPool task id)
var _gen_results: Dictionary = {}  # Vector2i → {"blocks": ..., "columns": ...}

# _job_step outcomes.
const STEP_PROGRESS: int = 0  # did some work, call again
const STEP_DONE: int = 1  # job finished, remove from queue
const STEP_BLOCKED: int = 2  # waiting on a worker thread, skip for now

# Absolute usec deadline for the current _run_jobs pass. Batch loops check it
# so a step can stop mid-batch instead of overshooting the frame budget.
# Sync generation paths leave it at "infinity".
var _job_deadline_usec: int = 9223372036854775807

# Retired CollisionShape3D nodes ready for reuse. Creating/freeing collider
# nodes per block churned thousands of node allocations and tree operations
# every chunk crossing; pooled nodes just flip `disabled` instead.
var _collider_pool: Array = []

var _player: Node3D
var _last_player_chunk: Vector2i = Vector2i(1000000, 1000000)
var _collision_center: Vector2i = Vector2i.ZERO  # chunk the collider window follows
var _collided: Dictionary = {}  # Vector2i → true (chunks whose exposed blocks have colliders)
var _spawn_height: int = 0

# Noise layers (built once in _ready).
var _n_continental: FastNoiseLite
var _n_erosion: FastNoiseLite
var _n_hills: FastNoiseLite
var _n_plateau: FastNoiseLite
var _n_plateau_mask: FastNoiseLite
var _n_ridges: FastNoiseLite
var _n_mountain_mask: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_temperature: FastNoiseLite
var _n_moisture: FastNoiseLite
var _n_cave_tunnels: FastNoiseLite
var _n_cave_warp: FastNoiseLite
var _n_cave_chambers: FastNoiseLite


func _ready() -> void:
	add_to_group("world")
	if ProjectSettings.has_setting(RUNTIME_SEED_SETTING):
		world_seed = int(ProjectSettings.get_setting(RUNTIME_SEED_SETTING, DEFAULT_SEED))
	_build_noises()
	_build_resources()
	print("Generating deterministic world with seed %d" % world_seed)
	_spawn_height = _column_info(0, 0)[0]
	# Generate a small core synchronously so the player has ground to stand on
	# from frame one, then queue a much larger initial area that streams in
	# over the next seconds without hurting the frame rate.
	for cx in range(-INITIAL_SYNC_RADIUS, INITIAL_SYNC_RADIUS + 1):
		for cz in range(-INITIAL_SYNC_RADIUS, INITIAL_SYNC_RADIUS + 1):
			_generate_chunk_sync(Vector2i(cx, cz))
	_queue_initial_area()


func _exit_tree() -> void:
	# Every WorkerThreadPool task must be waited on before we go away.
	_flush_gen_tasks()


## Queues the rest of the starting world (out to INITIAL_STREAM_RADIUS),
## nearest chunks first, to be generated by the per-frame job budget.
func _queue_initial_area() -> void:
	var wanted: Array = []
	for cx in range(-INITIAL_STREAM_RADIUS, INITIAL_STREAM_RADIUS + 1):
		for cz in range(-INITIAL_STREAM_RADIUS, INITIAL_STREAM_RADIUS + 1):
			var c: Vector2i = Vector2i(cx, cz)
			if not _loaded.has(c) and not _queued.has(c):
				wanted.append(c)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chebyshev(a, Vector2i.ZERO) < _chebyshev(b, Vector2i.ZERO))
	for c in wanted:
		_queued[c] = true
		_dispatch_gen(c)
		_job_queue.append(_make_gen_job(c))


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var pc: Vector2i = _chunk_of_xz(
		int(floor(_player.global_position.x)),
		int(floor(_player.global_position.z))
	)
	if pc != _last_player_chunk:
		_last_player_chunk = pc
		_refresh_collision_window(pc)
		_refresh_desired_chunks(pc)
	# Safety net: never let the player stand in an ungenerated chunk
	# (teleports / extreme speed). Rare, so a one-off hitch is fine.
	if not _loaded.has(pc):
		_generate_chunk_sync(pc)
	_run_jobs(GEN_BUDGET_USEC)


# ------------------------- chunk streaming -------------------------

func _chunk_of_xz(x: int, z: int) -> Vector2i:
	return Vector2i(x >> 4, z >> 4)  # floor division by CHUNK_SIZE (16)


func _chunk_of(pos: Vector3i) -> Vector2i:
	return Vector2i(pos.x >> 4, pos.z >> 4)


func _refresh_desired_chunks(pc: Vector2i) -> void:
	# Queue missing chunks within RENDER_DISTANCE, nearest first.
	var wanted: Array = []
	for dx in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for dz in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			var c: Vector2i = pc + Vector2i(dx, dz)
			if not _loaded.has(c) and not _queued.has(c):
				wanted.append(c)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chebyshev(a, pc) < _chebyshev(b, pc))
	for c in wanted:
		_queued[c] = true
		# Chunks the player is about to stand in get high-priority workers.
		_dispatch_gen(c, _chebyshev(c, pc) <= 1)
		_job_queue.append(_make_gen_job(c))
	# Queue unloads for chunks that drifted too far.
	for c_variant in _loaded.keys():
		var c: Vector2i = c_variant
		if _chebyshev(c, pc) > UNLOAD_DISTANCE and not _queued.has(c):
			_queued[c] = true
			_job_queue.append({"kind": "unload", "coord": c, "phase": 0, "idx": 0, "list": []})
	# Re-order the whole queue: collider window first, then generation
	# nearest-to-player first, unloads last. Without this, chunks in the
	# flight path sit behind stale jobs and the player outruns streaming,
	# hitting the expensive synchronous fallback.
	_job_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _job_priority(a, pc) < _job_priority(b, pc))


func _job_priority(job: Dictionary, pc: Vector2i) -> int:
	match String(job["kind"]):
		"collide_on", "collide_off":
			return -1000
		"gen":
			return _chebyshev(job["coord"], pc)
		_:
			return 1000  # unloads can always wait


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Colliders only exist in a small window of chunks around the player.
## When the window moves, chunks entering/leaving it get high-priority jobs
## that add/remove colliders for their exposed blocks in budgeted batches.
func _refresh_collision_window(pc: Vector2i) -> void:
	_collision_center = pc
	var priority_jobs: Array = []
	for c_variant in _loaded.keys():
		var c: Vector2i = c_variant
		var want: bool = _chebyshev(c, pc) <= COLLISION_DISTANCE
		if want and not _collided.has(c):
			_collided[c] = true
			priority_jobs.append({"kind": "collide_on", "coord": c, "phase": 0, "idx": 0, "list": []})
		elif not want and _collided.has(c):
			_collided.erase(c)
			priority_jobs.append({"kind": "collide_off", "coord": c, "phase": 0, "idx": 0, "list": []})
 	# Front of the queue: the player may be walking toward these blocks.
	for i in range(priority_jobs.size() - 1, -1, -1):
		_job_queue.push_front(priority_jobs[i])


func _collide_step(job: Dictionary, enable: bool) -> bool:
	# Collision-window changes can leave the opposite job queued behind the new
	# one. Drop stale work before it undoes the current desired state.
	if enable != _collided.has(job["coord"]):
		return true
	if job["phase"] == 0:
		var list: Array = []
		for pos_variant in _chunk_blocks.get(job["coord"], {}).keys():
			if _block_body_idx.has(pos_variant):  # exposed blocks only
				list.append(pos_variant)
		job["list"] = list
		job["phase"] = 1
		job["idx"] = 0
	var blocks: Array = job["list"]
	var idx: int = job["idx"]
	var end: int = mini(idx + 128, blocks.size())
	while idx < end and Time.get_ticks_usec() < _job_deadline_usec:
		var pos: Vector3i = blocks[idx]
		if enable:
			if _block_types.has(pos) and _block_body_idx.has(pos) and not _block_colliders.has(pos):
				_create_collider(pos)
		else:
			_free_collider(pos)
		idx += 1
	job["idx"] = idx
	return idx >= blocks.size()


func _make_gen_job(coord: Vector2i) -> Dictionary:
	return {"kind": "gen", "coord": coord, "phase": 0, "idx": 0, "list": []}


## Kicks off the pure chunk computation on a worker thread.
func _dispatch_gen(coord: Vector2i, high_priority: bool = false) -> void:
	if _gen_tasks.has(coord):
		return
	_gen_tasks[coord] = WorkerThreadPool.add_task(
		_thread_generate.bind(coord), high_priority, "chunk gen")


## Worker-thread entry point. Only reads noise objects and constants.
func _thread_generate(coord: Vector2i) -> void:
	var result: Dictionary = _compute_chunk(coord)
	_gen_mutex.lock()
	_gen_results[coord] = result
	_gen_mutex.unlock()


## Removes and returns the worker result for coord ({} if none).
func _take_gen_result(coord: Vector2i) -> Dictionary:
	_gen_mutex.lock()
	var result: Dictionary = _gen_results.get(coord, {})
	_gen_results.erase(coord)
	_gen_mutex.unlock()
	return result


## Retires the worker task for coord: STEP_BLOCKED while it is still running,
## STEP_DONE once it has been waited upon (and its result discarded if asked).
func _retire_gen_task(coord: Vector2i, discard_result: bool) -> int:
	var task_id: int = _gen_tasks.get(coord, -1)
	if task_id != -1:
		if not WorkerThreadPool.is_task_completed(task_id):
			return STEP_BLOCKED
		WorkerThreadPool.wait_for_task_completion(task_id)
		_gen_tasks.erase(coord)
	if discard_result:
		_take_gen_result(coord)
	return STEP_DONE


## Blocks until every outstanding worker task finished, then drops all results.
func _flush_gen_tasks() -> void:
	for coord_variant in _gen_tasks.keys():
		WorkerThreadPool.wait_for_task_completion(_gen_tasks[coord_variant])
	_gen_tasks.clear()
	_gen_mutex.lock()
	_gen_results.clear()
	_gen_mutex.unlock()


func _run_jobs(budget_usec: int) -> void:
	var start: int = Time.get_ticks_usec()
	_job_deadline_usec = start + budget_usec
	var i: int = 0
	while i < _job_queue.size():
		var job: Dictionary = _job_queue[i]
		var status: int = _job_step(job)
		if status == STEP_DONE:
			_job_queue.remove_at(i)
			var kind: String = String(job["kind"])
			if kind == "gen" or kind == "unload":
				_queued.erase(job["coord"])
			# If an unload had already started when the player returned, rebuild
			# the chunk without waiting for another chunk-boundary crossing.
			if kind == "unload" and not _loaded.has(job["coord"]) \
					and _chebyshev(job["coord"], _last_player_chunk) <= RENDER_DISTANCE:
				var coord: Vector2i = job["coord"]
				_queued[coord] = true
				_dispatch_gen(coord, true)
				_job_queue.append(_make_gen_job(coord))
		elif status == STEP_BLOCKED:
			i += 1  # let jobs behind it run while the worker finishes
		if Time.get_ticks_usec() >= _job_deadline_usec:
			break
	_job_deadline_usec = 9223372036854775807


func _generate_chunk_sync(coord: Vector2i) -> void:
	if _loaded.has(coord):
		return
	# Drop any queued gen job for this coord; we're doing it now.
	for i in range(_job_queue.size() - 1, -1, -1):
		if _job_queue[i]["kind"] == "gen" and _job_queue[i]["coord"] == coord:
			_job_queue.remove_at(i)
			_queued.erase(coord)
	# If a worker is already computing this chunk, block on it (cheaper than
	# recomputing); otherwise phase 0 computes it on the main thread.
	var task_id: int = _gen_tasks.get(coord, -1)
	if task_id != -1:
		WorkerThreadPool.wait_for_task_completion(task_id)
		_gen_tasks.erase(coord)
	var job: Dictionary = _make_gen_job(coord)
	while _job_step(job) != STEP_DONE:
		pass


## Runs one small batch of work for a job (see STEP_* constants).
func _job_step(job: Dictionary) -> int:
	var coord: Vector2i = job["coord"]
	if job["kind"] == "unload":
		# The player may have returned while this low-priority job waited.
		if job["phase"] == 0 and _chebyshev(coord, _last_player_chunk) <= UNLOAD_DISTANCE:
			return STEP_DONE
		return STEP_DONE if _unload_step(job, coord) else STEP_PROGRESS
	if job["kind"] == "collide_on":
		return STEP_DONE if _collide_step(job, true) else STEP_PROGRESS
	if job["kind"] == "collide_off":
		return STEP_DONE if _collide_step(job, false) else STEP_PROGRESS
	if _loaded.has(coord):
		return _retire_gen_task(coord, true)
	# Abandon generation of chunks the player has left behind (once the worker
	# is done — its result is simply discarded).
	if job["phase"] <= 1 and _last_player_chunk.x != 1000000 \
			and _chebyshev(coord, _last_player_chunk) > UNLOAD_DISTANCE:
		return _retire_gen_task(coord, true)
	match int(job["phase"]):
		0:
			# Pick up the worker thread's result (or compute here if none ran).
			if _retire_gen_task(coord, false) == STEP_BLOCKED:
				return STEP_BLOCKED
			var result: Dictionary = _take_gen_result(coord)
			if result.is_empty():
				result = _compute_chunk(coord)
			_column_cache.merge(result["columns"], true)
			job["blocks"] = result["blocks"]
			job["list"] = (result["blocks"] as Dictionary).keys()
			job["phase"] = 1
			job["idx"] = 0
		1:
			_gen_step_merge(job, coord)
		2:
			_gen_step_edits(coord)
			if _chebyshev(coord, _collision_center) <= COLLISION_DISTANCE:
				_collided[coord] = true  # exposure pass will create colliders too
			job["phase"] = 3
			job["idx"] = 0
			job["list"] = _build_exposure_list(coord)
		3:
			if _gen_step_exposure(job):
				_loaded[coord] = true
				return STEP_DONE
	return STEP_PROGRESS


## Pure chunk computation: terrain, landmarks and trees for one chunk.
## Touches no shared mutable state (local column cache, reads only noise
## objects), so it is safe to run on a worker thread. Player edits are
## deliberately ignored here; the main-thread merge step applies them.
func _compute_chunk(coord: Vector2i) -> Dictionary:
	var cache: Dictionary = {}
	var blocks: Dictionary = {}
	var base_x: int = coord.x * CHUNK_SIZE
	var base_z: int = coord.y * CHUNK_SIZE
	for x in range(base_x, base_x + CHUNK_SIZE):
		for z in range(base_z, base_z + CHUNK_SIZE):
			var info: Array = _column_info_cached(x, z, cache)
			var surface_y: int = info[0]
			var biome: int = info[1]
			for dy in range(0, SURFACE_DEPTH + 1):
				var y: int = surface_y - dy
				if _is_cave(x, y, z, surface_y):
					continue
				blocks[Vector3i(x, y, z)] = _block_for_depth(biome, surface_y, dy)
	_place_landmarks(coord, blocks, cache)
	# Scan the chunk plus a 2-column border so trees rooted in neighboring
	# chunks still drop their leaves into this one.
	for x in range(base_x - 2, base_x + CHUNK_SIZE + 2):
		for z in range(base_z - 2, base_z + CHUNK_SIZE + 2):
			if not _tree_at(x, z, cache):
				continue
			var surface_y: int = _column_info_cached(x, z, cache)[0]
			for entry in _tree_blocks(x, z, surface_y):
				var pos: Vector3i = entry[0]
				if _chunk_of(pos) != coord or blocks.has(pos):
					continue
				blocks[pos] = entry[1]
	return {"blocks": blocks, "columns": cache}


## Dirt tower at (5, 5) — placed as terrain when its chunk generates.
func _place_landmarks(coord: Vector2i, blocks: Dictionary, cache: Dictionary) -> void:
	if coord != _chunk_of_xz(5, 5):
		return
	var surface_y: int = _column_info_cached(5, 5, cache)[0]
	for dy in range(1, 6):
		var pos: Vector3i = Vector3i(5, surface_y + dy, 5)
		if not blocks.has(pos):
			blocks[pos] = TYPE_DIRT


## Merges worker-computed blocks into the world dictionaries in small batches,
## skipping positions the player has edited.
func _gen_step_merge(job: Dictionary, coord: Vector2i) -> void:
	var blocks: Dictionary = job["blocks"]
	var list: Array = job["list"]
	var idx: int = job["idx"]
	var end: int = mini(idx + 512, list.size())
	var chunk_dict: Dictionary = _chunk_blocks.get_or_add(coord, {})
	while idx < end and Time.get_ticks_usec() < _job_deadline_usec:
		var pos: Vector3i = list[idx]
		idx += 1
		if _edits.has(pos) or _block_types.has(pos):
			continue
		_block_types[pos] = blocks[pos]
		chunk_dict[pos] = true
	job["idx"] = idx
	if idx >= list.size():
		job["phase"] = 2
		job["idx"] = 0


func _gen_step_edits(coord: Vector2i) -> void:
	# Player-placed blocks inside this chunk (removals were already skipped).
	var chunk_dict: Dictionary = _chunk_blocks.get_or_add(coord, {})
	for pos_variant in _edits.keys():
		var pos: Vector3i = pos_variant
		if _chunk_of(pos) != coord:
			continue
		var type: String = _edits[pos]
		if type.is_empty() or _block_types.has(pos):
			continue
		_block_types[pos] = type
		chunk_dict[pos] = true


func _build_exposure_list(coord: Vector2i) -> Array:
	var list: Array = _chunk_blocks.get(coord, {}).keys()
	# Border blocks of loaded neighbors may have just become buried (or newly
	# open to air after an unload) — re-evaluate them too.
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nc: Vector2i = coord + dir
		if not _loaded.has(nc):
			continue
		# The neighbor-chunk column line that touches this chunk.
		var edge_x: int = (nc.x * CHUNK_SIZE) if dir.x > 0 else (nc.x * CHUNK_SIZE + CHUNK_SIZE - 1)
		var edge_z: int = (nc.y * CHUNK_SIZE) if dir.y > 0 else (nc.y * CHUNK_SIZE + CHUNK_SIZE - 1)
		for pos_variant in _chunk_blocks.get(nc, {}).keys():
			var pos: Vector3i = pos_variant
			if dir.x != 0 and pos.x == edge_x:
				list.append(pos)
			elif dir.y != 0 and pos.z == edge_z:
				list.append(pos)
	return list


func _gen_step_exposure(job: Dictionary) -> bool:
	var list: Array = job["list"]
	var idx: int = job["idx"]
	var end: int = mini(idx + 256, list.size())
	while idx < end and Time.get_ticks_usec() < _job_deadline_usec:
		_update_exposure(list[idx])
		idx += 1
	job["idx"] = idx
	return idx >= list.size()


func _unload_step(job: Dictionary, coord: Vector2i) -> bool:
	match int(job["phase"]):
		0:
			job["list"] = _chunk_blocks.get(coord, {}).keys()
			job["phase"] = 1
			job["idx"] = 0
		1:
			var list: Array = job["list"]
			var idx: int = job["idx"]
			var end: int = mini(idx + 256, list.size())
			while idx < end and Time.get_ticks_usec() < _job_deadline_usec:
				var pos: Vector3i = list[idx]
				if _block_types.has(pos):
					_hide_block(pos)
					_block_types.erase(pos)
				idx += 1
			job["idx"] = idx
			if idx >= list.size():
				_chunk_blocks.erase(coord)
				_loaded.erase(coord)
				_collided.erase(coord)
				_evict_column_cache(coord)
				job["list"] = _build_exposure_list(coord)  # neighbor borders only now
				job["phase"] = 2
				job["idx"] = 0
		2:
			# Walls of still-loaded neighbors are open to air again.
			if _gen_step_exposure(job):
				return true
	return false


func _evict_column_cache(coord: Vector2i) -> void:
	var base_x: int = coord.x * CHUNK_SIZE
	var base_z: int = coord.y * CHUNK_SIZE
	for x in range(base_x, base_x + CHUNK_SIZE):
		for z in range(base_z, base_z + CHUNK_SIZE):
			_column_cache.erase(Vector2i(x, z))


# ------------------------- terrain functions (pure) -------------------------

func _make_noise(seed_offset: int, freq: float, octaves: int, type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = world_seed + seed_offset
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n


func _build_noises() -> void:
	_n_continental = _make_noise(0, 0.0065, 3)
	_n_erosion = _make_noise(31, 0.014, 2)
	_n_hills = _make_noise(67, 0.035, 3)
	_n_plateau = _make_noise(89, 0.009, 2)
	_n_plateau_mask = _make_noise(97, 0.006, 2)
	_n_ridges = _make_noise(103, 0.022, 4, FastNoiseLite.TYPE_SIMPLEX)
	_n_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_mountain_mask = _make_noise(139, 0.008, 2)
	_n_detail = _make_noise(173, 0.14, 2)
	_n_temperature = _make_noise(211, 0.009, 2)
	_n_moisture = _make_noise(251, 0.011, 2)
	_n_cave_tunnels = _make_noise(307, 0.075, 3, FastNoiseLite.TYPE_SIMPLEX)
	_n_cave_warp = _make_noise(349, 0.028, 2)
	_n_cave_chambers = _make_noise(383, 0.045, 2)


## Returns [surface_height, biome] for a column. Pure + cached.
func _column_info(x: int, z: int) -> Array:
	return _column_info_cached(x, z, _column_cache)


## Same as _column_info but with an explicit cache dictionary, so worker
## threads can use a private cache without touching shared state.
func _column_info_cached(x: int, z: int, cache: Dictionary) -> Array:
	var key: Vector2i = Vector2i(x, z)
	var cached: Array = cache.get(key, [])
	if not cached.is_empty():
		return cached
	var fx: float = float(x)
	var fz: float = float(z)

	var c: float = (_n_continental.get_noise_2d(fx, fz) + 1.0) * 0.5
	var e: float = (_n_erosion.get_noise_2d(fx, fz) + 1.0) * 0.5
	var mmask: float = (_n_mountain_mask.get_noise_2d(fx, fz) + 1.0) * 0.5
	var plateau_mask: float = smoothstep(
		PLATEAU_MASK_LOW, PLATEAU_MASK_HIGH,
		(_n_plateau_mask.get_noise_2d(fx, fz) + 1.0) * 0.5)

	# Continental elevation supplies large lowlands and uplands. Eroded regions
	# stay broad and calm instead of turning every noise bump into a hill.
	var h: float = lerpf(-4.0, 8.0, smoothstep(0.12, 0.88, c))
	h += _n_hills.get_noise_2d(fx, fz) * lerpf(1.0, 4.5, e)

	# Quantize broad plateau noise into four-block shelves, then blend it into the
	# base terrain. This creates wide walkable tops with recognizable escarpments
	# while the mask keeps normal rolling plains elsewhere.
	var plateau_raw: float = h + _n_plateau.get_noise_2d(fx, fz) * 11.0 + 4.0
	var plateau_height: float = round(plateau_raw / 4.0) * 4.0
	h = lerpf(h, plateau_height, plateau_mask * PLATEAU_BLEND_STRENGTH)

	# Mountain chains use a much broader mask than their ridges. A minimum massif
	# lift produces foothills and pow() sharpens only the high ridges into peaks.
	var mstrength: float = smoothstep(0.56, 0.78, mmask)
	if mstrength > 0.0:
		var ridge: float = clampf((_n_ridges.get_noise_2d(fx, fz) + 1.0) * 0.5, 0.0, 1.0)
		var peak_height: float = 8.0 + pow(ridge, 1.7) * 30.0
		h += peak_height * mstrength * lerpf(0.72, 1.0, e)

	# Fine roughness is intentionally subdued on plateau tops.
	h += _n_detail.get_noise_2d(fx, fz) * lerpf(0.9, 0.2, plateau_mask)

	var surface_y: int = int(round(h))

	var temp: float = (_n_temperature.get_noise_2d(fx, fz) + 1.0) * 0.5
	var moist: float = (_n_moisture.get_noise_2d(fx, fz) + 1.0) * 0.5
	var biome: int
	if mstrength > 0.5 and surface_y > 8:
		biome = BIOME_MOUNTAINS
	elif temp > 0.62 and moist < 0.42:
		biome = BIOME_DESERT
	elif moist > 0.55:
		biome = BIOME_FOREST
	else:
		biome = BIOME_PLAINS

	var info: Array = [surface_y, biome]
	cache[key] = info
	return info


## Deterministic 3D cave field. Thin absolute-noise bands make connected winding
## tunnels; a second low-frequency field varies their width and occasionally
## opens chambers. Keeping a roof and floor avoids unsafe spawn holes and voids.
func _is_cave(x: int, y: int, z: int, surface_y: int) -> bool:
	var depth: int = surface_y - y
	if depth < CAVE_MIN_DEPTH or depth > SURFACE_DEPTH - CAVE_BOTTOM_MARGIN:
		return false
	var fx: float = float(x)
	var fy: float = float(y) * 0.78
	var fz: float = float(z)
	var warp: float = _n_cave_warp.get_noise_3d(fx, fy, fz)
	var tunnel: float = absf(_n_cave_tunnels.get_noise_3d(
		fx + warp * 11.0, fy, fz - warp * 11.0))
	var width: float = lerpf(0.065, 0.13, smoothstep(-0.45, 0.55, warp))
	var chamber: float = _n_cave_chambers.get_noise_3d(fx, fy, fz)
	return tunnel < width or chamber > 0.68


func _block_for_depth(biome: int, surface_y: int, dy: int) -> String:
	# Deserts: deep sand over stone, like real Minecraft deserts.
	if biome == BIOME_DESERT:
		return TYPE_SAND if dy <= 3 else TYPE_COBBLE
	# High mountain tops are bare stone above the snow line.
	if biome == BIOME_MOUNTAINS and surface_y >= SNOW_LINE:
		return TYPE_COBBLE
	if dy == 0:
		# Beaches: anything at or below sea level gets sand.
		return TYPE_GRASS if surface_y > SEA_LEVEL else TYPE_SAND
	if dy <= 3:
		return TYPE_DIRT if surface_y > SEA_LEVEL else TYPE_SAND
	return TYPE_COBBLE


## Pure per-column tree test: one jittered candidate spot per 4x4 cell,
## accepted with a per-biome chance, only on grass, never near spawn.
func _tree_at(x: int, z: int, cache: Dictionary) -> bool:
	if absi(x) <= SPAWN_CLEAR_RADIUS and absi(z) <= SPAWN_CLEAR_RADIUS:
		return false
	var cell: Vector2i = Vector2i(x >> 2, z >> 2)
	var h: int = absi(hash(Vector3i(cell.x, cell.y, world_seed)))
	var jx: int = cell.x * TREE_CELL + ((h >> 8) % TREE_CELL)
	var jz: int = cell.y * TREE_CELL + ((h >> 16) % TREE_CELL)
	if x != jx or z != jz:
		return false
	var info: Array = _column_info_cached(x, z, cache)
	if _block_for_depth(info[1], info[0], 0) != TYPE_GRASS:
		return false
	return (h % 100) < int(TREE_CELL_CHANCE[info[1]])


## Pure list of [Vector3i, type] pairs for a tree rooted at (x, surface_y, z).
func _tree_blocks(x: int, z: int, surface_y: int) -> Array:
	var out: Array = []
	var trunk_h: int = 4 + (absi(hash(Vector3i(x, z, world_seed))) % 3)  # 4-6 blocks tall
	for dh in range(1, trunk_h + 1):
		out.append([Vector3i(x, surface_y + dh, z), TYPE_WOOD])
	var top_y: int = surface_y + trunk_h
	# 5x3x5 leaves cluster, corners + tapered top removed.
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for dy in range(-1, 2):
				if absi(dx) == 2 and absi(dz) == 2:
					continue
				if dy == 1 and (absi(dx) >= 2 or absi(dz) >= 2):
					continue
				if dx == 0 and dz == 0 and dy <= 0:
					continue  # trunk occupies the center column
				out.append([Vector3i(x + dx, top_y + dy, z + dz), TYPE_LEAVES])
	return out


# ------------------------- exposure (visuals + colliders) -------------------------

## A block is exposed if any face can be seen: up, the four sides, or below
## (except the world's underside, which faces the void and is skipped).
func _is_exposed(pos: Vector3i) -> bool:
	if not _block_types.has(pos + Vector3i.UP):
		return true
	for n in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if not _block_types.has(pos + n):
			return true
	var below: Vector3i = pos + Vector3i.DOWN
	if _block_types.has(below):
		return false
	# Open below: only counts if it's above the generated world bottom
	# (i.e. a real tunnel ceiling, not the chunk underside facing the void).
	var bottom: int = _column_info(pos.x, pos.z)[0] - SURFACE_DEPTH
	return below.y >= bottom


func _update_exposure(pos: Vector3i) -> void:
	if not _block_types.has(pos):
		return
	var exposed: bool = _is_exposed(pos)
	var shown: bool = _block_body_idx.has(pos)
	if exposed and not shown:
		_show_block(pos)
	elif not exposed and shown:
		_hide_block(pos)


func _create_collider(pos: Vector3i) -> void:
	var collider: CollisionShape3D
	if _collider_pool.is_empty():
		collider = CollisionShape3D.new()
		collider.shape = _shape
		collider.position = Vector3(pos)
		_collision_body.add_child(collider)
	else:
		collider = _collider_pool.pop_back()
		collider.position = Vector3(pos)
		collider.disabled = false
	_block_colliders[pos] = collider


func _free_collider(pos: Vector3i) -> void:
	var collider: CollisionShape3D = _block_colliders.get(pos)
	if collider != null and is_instance_valid(collider):
		collider.disabled = true
		_collider_pool.append(collider)
	_block_colliders.erase(pos)


func _show_block(pos: Vector3i) -> void:
	var type: String = _block_types[pos]
	if not _mm_inst.has(type):
		return
	var idx: int = _allocate_body_idx(type)
	_mm_inst[type].multimesh.set_instance_transform(idx, Transform3D(Basis(), Vector3(pos)))
	_block_body_idx[pos] = idx

	if _collided.has(_chunk_of(pos)):
		_create_collider(pos)

	if type == TYPE_GRASS and _grass_top_mm != null:
		var top_idx: int = _allocate_grass_top_idx()
		var top_basis: Basis = Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0))
		var top_xform: Transform3D = Transform3D(top_basis, Vector3(pos) + Vector3(0.0, 0.501, 0.0))
		_grass_top_mm.multimesh.set_instance_transform(top_idx, top_xform)
		_block_top_idx[pos] = top_idx


func _hide_block(pos: Vector3i) -> void:
	if not _block_body_idx.has(pos):
		return
	var type: String = _block_types[pos]
	var idx: int = _block_body_idx[pos]
	var off: Transform3D = Transform3D(Basis(), OFFSCREEN)
	_mm_inst[type].multimesh.set_instance_transform(idx, off)
	(_mm_free[type] as Array).append(idx)
	_block_body_idx.erase(pos)

	_free_collider(pos)

	if _block_top_idx.has(pos):
		var top_idx: int = _block_top_idx[pos]
		_grass_top_mm.multimesh.set_instance_transform(top_idx, off)
		_grass_top_free.append(top_idx)
		_block_top_idx.erase(pos)


# ------------------------- public block API -------------------------

func add_block(pos: Vector3i, type: String) -> bool:
	if _block_types.has(pos):
		return false
	if not _mm_inst.has(type):
		return false
	_edits[pos] = type
	var coord: Vector2i = _chunk_of(pos)
	if not _loaded.has(coord):
		return true  # applied when that chunk streams in
	_block_types[pos] = type
	_chunk_blocks.get_or_add(coord, {})[pos] = true
	_update_exposure(pos)
	for n in _neighbors(pos):
		_update_exposure(n)
	return true


func remove_block(pos: Vector3i) -> String:
	if not _block_types.has(pos):
		return ""
	var type: String = _block_types[pos]
	_edits[pos] = ""
	_hide_block(pos)
	_block_types.erase(pos)
	_chunk_blocks.get_or_add(_chunk_of(pos), {}).erase(pos)
	for n in _neighbors(pos):
		_update_exposure(n)
	return type


func _neighbors(pos: Vector3i) -> Array:
	return [
		pos + Vector3i.UP, pos + Vector3i.DOWN,
		pos + Vector3i(1, 0, 0), pos + Vector3i(-1, 0, 0),
		pos + Vector3i(0, 0, 1), pos + Vector3i(0, 0, -1),
	]


func get_block_type(pos: Vector3i) -> String:
	return _block_types.get(pos, "")


func has_block(pos: Vector3i) -> bool:
	return _block_types.has(pos)


func get_spawn_height() -> int:
	return _spawn_height


func get_world_seed() -> int:
	return world_seed


## Highest solid block's top surface at (x, z). Scans the full terrain range
## (tallest mountains + trees down to the bottom of the dug-out depth); if the
## column has no loaded blocks the chunk isn't streamed in yet, so fall back to
## the generated terrain height, which is a pure function of position.
func get_surface_y(x: int, z: int) -> int:
	for y in range(64, -48, -1):
		if has_block(Vector3i(x, y, z)):
			return y + 1
	return get_ground_surface_y(x, z)


## Natural terrain surface, intentionally ignoring tree trunks and leaves.
func get_ground_surface_y(x: int, z: int) -> int:
	return _column_info(x, z)[0] + 1


## True when an animal can stand here without intersecting a generated or loaded tree.
## The pure generation check also works before an outer chunk finishes streaming.
func is_safe_animal_spawn(x: int, z: int, horizontal_clearance: int = 1) -> bool:
	var ground_y: int = get_ground_surface_y(x, z)
	for offset_x: int in range(-horizontal_clearance, horizontal_clearance + 1):
		for offset_z: int in range(-horizontal_clearance, horizontal_clearance + 1):
			var check_x: int = x + offset_x
			var check_z: int = z + offset_z
			if _generated_tree_occupies_column(check_x, check_z):
				return false
			for check_y: int in range(ground_y, ground_y + 8):
				var block_type: String = get_block_type(Vector3i(check_x, check_y, check_z))
				if block_type == TYPE_WOOD or block_type == TYPE_LEAVES:
					return false
	return true


func _generated_tree_occupies_column(x: int, z: int) -> bool:
	var cache: Dictionary = {}
	for root_x: int in range(x - 2, x + 3):
		for root_z: int in range(z - 2, z + 3):
			if not _tree_at(root_x, root_z, cache):
				continue
			var root_surface_y: int = _column_info_cached(root_x, root_z, cache)[0]
			for entry: Array in _tree_blocks(root_x, root_z, root_surface_y):
				var block_pos: Vector3i = entry[0]
				if block_pos.x == x and block_pos.z == z:
					return true
	return false


## Tries several random points and returns an empty dictionary if none are tree-safe.
func find_safe_animal_spawn(
	min_radius: int, max_radius: int, max_attempts: int = 32
) -> Dictionary:
	for attempt: int in max_attempts:
		var angle: float = randf_range(0.0, TAU)
		var radius: float = randf_range(float(min_radius), float(max_radius))
		var x: int = int(round(cos(angle) * radius))
		var z: int = int(round(sin(angle) * radius))
		if not is_safe_animal_spawn(x, z):
			continue
		var y: int = get_ground_surface_y(x, z)
		return {"position": Vector3(float(x) + 0.5, float(y) + 0.1, float(z) + 0.5)}
	return {}


# ------------------------- multiplayer sync -------------------------

## Terrain is deterministic from world_seed on every peer, so snapshots carry
## only player edits (type "" = removed block). Multiplayer sessions derive the
## same seed from their shared room code before this scene loads.
func get_block_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	snapshot.resize(_edits.size())
	var i: int = 0
	for pos_variant in _edits.keys():
		var pos: Vector3i = pos_variant
		snapshot[i] = {
			"x": pos.x,
			"y": pos.y,
			"z": pos.z,
			"type": String(_edits[pos]),
		}
		i += 1
	return snapshot


func apply_block_snapshot(snapshot: Array) -> void:
	_edits.clear()
	for item_variant in snapshot:
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		var pos: Vector3i = Vector3i(
			int(item.get("x", 0)),
			int(item.get("y", 0)),
			int(item.get("z", 0))
		)
		_edits[pos] = String(item.get("type", ""))
	# Rebuild loaded chunks so the received edits take effect everywhere.
	# Include chunks still being merged: they already own blocks but are not in
	# _loaded yet, and clearing their jobs alone would leave those blocks behind.
	var coords: Array = _chunk_blocks.keys()
	for coord_variant in _loaded.keys():
		if not coords.has(coord_variant):
			coords.append(coord_variant)
	for coord_variant in coords:
		_unload_chunk_sync(coord_variant)
	_flush_gen_tasks()  # stale worker results would resurrect old terrain
	_job_queue.clear()
	_queued.clear()
	var center: Vector2i = Vector2i.ZERO
	if _player != null and is_instance_valid(_player):
		center = _chunk_of_xz(
			int(floor(_player.global_position.x)),
			int(floor(_player.global_position.z))
		)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_generate_chunk_sync(center + Vector2i(dx, dz))
	_last_player_chunk = Vector2i(1000000, 1000000)  # force re-queue of the rest


func apply_block_edit(pos: Vector3i, type: String, add: bool) -> void:
	if add:
		add_block(pos, type)
	else:
		if _block_types.has(pos):
			remove_block(pos)
		else:
			_edits[pos] = ""  # chunk not loaded here; applies on stream-in


func _unload_chunk_sync(coord: Vector2i) -> void:
	var job: Dictionary = {"kind": "unload", "coord": coord, "phase": 0, "idx": 0, "list": []}
	while not _unload_step(job, coord):
		pass


# ------------------------- rendering pools -------------------------

func _build_resources() -> void:
	_shape = BoxShape3D.new()
	_shape.size = Vector3.ONE

	_collision_body = StaticBody3D.new()
	_collision_body.name = "WorldCollision"
	add_child(_collision_body)

	for t in ALL_BODY_TYPES:
		var tex: Texture2D = _texture_for_body(t)
		var mmi: MultiMeshInstance3D = _build_box_mm(t, tex, int(INITIAL_CAPACITY[t]))
		if mmi != null:
			add_child(mmi)
			_mm_inst[t] = mmi
			_mm_used[t] = 0
			_mm_free[t] = []

	_grass_top_mm = _build_grass_top_mm(GRASS_TOP_CAPACITY)
	if _grass_top_mm != null:
		add_child(_grass_top_mm)


func _build_box_mm(type: String, tex: Texture2D, capacity: int) -> MultiMeshInstance3D:
	if tex == null:
		return null
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	box.material = mat

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = capacity
	_initialize_offscreen(mm, 0, capacity)

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "MM_" + type
	mmi.multimesh = mm
	return mmi


func _build_grass_top_mm(capacity: int) -> MultiMeshInstance3D:
	if grass_top_texture == null:
		return null
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = grass_top_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = mat

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = capacity
	_initialize_offscreen(mm, 0, capacity)

	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "MM_grass_top"
	mmi.multimesh = mm
	return mmi


func _initialize_offscreen(mm: MultiMesh, start: int, end: int) -> void:
	var off: Transform3D = Transform3D(Basis(), OFFSCREEN)
	for i in range(start, end):
		mm.set_instance_transform(i, off)


func _texture_for_body(type: String) -> Texture2D:
	match type:
		TYPE_DIRT, TYPE_GRASS:
			return dirt_texture
		TYPE_COBBLE:
			return cobble_texture
		TYPE_WOOD:
			return wood_texture
		TYPE_LEAVES:
			return leaves_texture
		TYPE_SAND:
			return sand_texture
	return null


func _allocate_body_idx(type: String) -> int:
	var free_arr: Array = _mm_free[type]
	if not free_arr.is_empty():
		return free_arr.pop_back()
	var idx: int = _mm_used[type]
	var mm: MultiMesh = _mm_inst[type].multimesh
	if idx >= mm.instance_count:
		_grow_multimesh(mm)
	_mm_used[type] = idx + 1
	return idx


## Grows a MultiMesh pool while PRESERVING existing instance transforms.
## (Setting instance_count alone wipes the whole transform buffer.)
## Grows geometrically so growth events get rarer as the world gets bigger,
## and fills the new tail with raw buffer writes instead of a
## set_instance_transform loop — that loop caused a visible hitch per growth.
func _grow_multimesh(mm: MultiMesh) -> void:
	var old_count: int = mm.instance_count
	var new_cap: int = maxi(old_count * 2, old_count + POOL_GROW_STEP)
	var buf: PackedFloat32Array = mm.buffer
	const FLOATS_PER_INSTANCE: int = 12  # TRANSFORM_3D, no colors/custom data
	if buf.size() == old_count * FLOATS_PER_INSTANCE and not buf.is_empty():
		buf.resize(new_cap * FLOATS_PER_INSTANCE)
		for i in range(old_count, new_cap):
			var base: int = i * FLOATS_PER_INSTANCE
			buf[base] = 1.0  # identity basis, offscreen origin
			buf[base + 3] = OFFSCREEN.x
			buf[base + 5] = 1.0
			buf[base + 7] = OFFSCREEN.y
			buf[base + 10] = 1.0
			buf[base + 11] = OFFSCREEN.z
		mm.instance_count = new_cap
		mm.buffer = buf
	else:
		# Headless/dummy renderer: no buffer readback, nothing visual to keep.
		mm.instance_count = new_cap
		_initialize_offscreen(mm, old_count, new_cap)


func _allocate_grass_top_idx() -> int:
	if not _grass_top_free.is_empty():
		return _grass_top_free.pop_back()
	var idx: int = _grass_top_used
	var mm: MultiMesh = _grass_top_mm.multimesh
	if idx >= mm.instance_count:
		_grow_multimesh(mm)
	_grass_top_used = idx + 1
	return idx
