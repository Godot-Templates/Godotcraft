class_name World
extends Node3D

## Voxel chunk with 6 block types and procedural terrain.
##
## Rendering: one MultiMeshInstance3D per block type (one draw call per type for
## thousands of blocks). Grass uses the dirt body texture + a separate per-block
## green QuadMesh placed just above the top face (its own MultiMesh).
##
## Collision: a single shared StaticBody3D with one CollisionShape3D child per
## block. Mining still works — we look up the block at the hit position in the
## type dictionary and remove that one block's mesh-instance + collider.

const CHUNK_RADIUS: int = 16
const SURFACE_DEPTH: int = 8  # blocks generated below surface
const SEED_VAL: int = 1337
const SEA_LEVEL: int = 0  # surface at-or-below this is sand (beaches)
const TREE_CHANCE_PERCENT: int = 4

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
    TYPE_DIRT: 4000,
    TYPE_GRASS: 1500,
    TYPE_COBBLE: 6000,
    TYPE_WOOD: 500,
    TYPE_LEAVES: 2500,
    TYPE_SAND: 500,
}
const GRASS_TOP_CAPACITY: int = 1500
const OFFSCREEN: Vector3 = Vector3(0.0, -10000.0, 0.0)

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

var _block_types: Dictionary = {}  # Vector3i → String
var _block_body_idx: Dictionary = {}  # Vector3i → int
var _block_top_idx: Dictionary = {}  # Vector3i → int (grass blocks)
var _block_colliders: Dictionary = {}  # Vector3i → CollisionShape3D

var _spawn_height: int = 0


func _ready() -> void:
    _build_resources()
    _generate_chunk()


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
        var new_cap: int = mm.instance_count + 500
        mm.instance_count = new_cap
        _initialize_offscreen(mm, idx, new_cap)
    _mm_used[type] = idx + 1
    return idx


func _allocate_grass_top_idx() -> int:
    if not _grass_top_free.is_empty():
        return _grass_top_free.pop_back()
    var idx: int = _grass_top_used
    var mm: MultiMesh = _grass_top_mm.multimesh
    if idx >= mm.instance_count:
        var new_cap: int = mm.instance_count + 500
        mm.instance_count = new_cap
        _initialize_offscreen(mm, idx, new_cap)
    _grass_top_used = idx + 1
    return idx


func add_block(pos: Vector3i, type: String) -> bool:
    if _block_types.has(pos):
        return false
    if not _mm_inst.has(type):
        return false

    var idx: int = _allocate_body_idx(type)
    var xform: Transform3D = Transform3D(Basis(), Vector3(pos))
    _mm_inst[type].multimesh.set_instance_transform(idx, xform)

    var collider: CollisionShape3D = CollisionShape3D.new()
    collider.shape = _shape
    collider.position = Vector3(pos)
    _collision_body.add_child(collider)

    _block_types[pos] = type
    _block_body_idx[pos] = idx
    _block_colliders[pos] = collider

    if type == TYPE_GRASS and _grass_top_mm != null:
        var top_idx: int = _allocate_grass_top_idx()
        var top_basis: Basis = Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0))
        var top_xform: Transform3D = Transform3D(top_basis, Vector3(pos) + Vector3(0.0, 0.501, 0.0))
        _grass_top_mm.multimesh.set_instance_transform(top_idx, top_xform)
        _block_top_idx[pos] = top_idx
    return true


func remove_block(pos: Vector3i) -> String:
    if not _block_types.has(pos):
        return ""
    var type: String = _block_types[pos]
    var idx: int = _block_body_idx[pos]
    var off: Transform3D = Transform3D(Basis(), OFFSCREEN)
    _mm_inst[type].multimesh.set_instance_transform(idx, off)
    (_mm_free[type] as Array).append(idx)

    var collider: Node = _block_colliders[pos]
    if collider != null and is_instance_valid(collider):
        collider.queue_free()

    if type == TYPE_GRASS and _block_top_idx.has(pos):
        var top_idx: int = _block_top_idx[pos]
        _grass_top_mm.multimesh.set_instance_transform(top_idx, off)
        _grass_top_free.append(top_idx)
        _block_top_idx.erase(pos)

    _block_types.erase(pos)
    _block_body_idx.erase(pos)
    _block_colliders.erase(pos)
    return type


func get_block_type(pos: Vector3i) -> String:
    return _block_types.get(pos, "")


func has_block(pos: Vector3i) -> bool:
    return _block_types.has(pos)


func get_spawn_height() -> int:
    return _spawn_height


func get_block_snapshot() -> Array[Dictionary]:
    var snapshot: Array[Dictionary] = []
    snapshot.resize(_block_types.size())
    var i: int = 0
    for pos_variant in _block_types.keys():
        var pos: Vector3i = pos_variant
        snapshot[i] = {
            "x": pos.x,
            "y": pos.y,
            "z": pos.z,
            "type": String(_block_types[pos]),
        }
        i += 1
    return snapshot


func apply_block_snapshot(snapshot: Array) -> void:
    _clear_all_blocks()
    for item_variant in snapshot:
        if typeof(item_variant) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = item_variant
        var pos: Vector3i = Vector3i(
            int(item.get("x", 0)),
            int(item.get("y", 0)),
            int(item.get("z", 0))
        )
        var type: String = String(item.get("type", ""))
        if not type.is_empty():
            add_block(pos, type)


func apply_block_edit(pos: Vector3i, type: String, add: bool) -> void:
    if add:
        add_block(pos, type)
    else:
        remove_block(pos)


func _clear_all_blocks() -> void:
    var positions: Array = _block_types.keys()
    for pos_variant in positions:
        var pos: Vector3i = pos_variant
        remove_block(pos)


func _generate_chunk() -> void:
    var noise: FastNoiseLite = FastNoiseLite.new()
    noise.seed = SEED_VAL
    noise.noise_type = FastNoiseLite.TYPE_PERLIN
    noise.frequency = 0.09
    noise.fractal_octaves = 4
    noise.fractal_lacunarity = 2.0
    noise.fractal_gain = 0.5

    var mountain_noise: FastNoiseLite = FastNoiseLite.new()
    mountain_noise.seed = SEED_VAL + 100
    mountain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
    mountain_noise.frequency = 0.045

    var heights: Dictionary = {}
    for x in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
        for z in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
            # Base rolling hills.
            var base_h: float = noise.get_noise_2d(float(x), float(z)) * 6.0 + 1.0
            # Mountain mask: pow steepens peaks so plains stay flat and mountains rise sharply.
            var m: float = (mountain_noise.get_noise_2d(float(x), float(z)) + 1.0) * 0.5
            m = pow(m, 3.0)
            base_h += m * 20.0
            heights[Vector2i(x, z)] = int(round(base_h))

    for x in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
        for z in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
            var surface_y: int = heights[Vector2i(x, z)]
            for dy in range(0, SURFACE_DEPTH + 1):
                var y: int = surface_y - dy
                var t: String
                if dy == 0:
                    t = TYPE_GRASS if surface_y > SEA_LEVEL else TYPE_SAND
                elif dy <= 3:
                    t = TYPE_DIRT
                else:
                    t = TYPE_COBBLE
                add_block(Vector3i(x, y, z), t)

    # Trees on a deterministic ~4% of grass blocks. Big buffer around spawn so
    # the player has a clear view on day one.
    for x in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
        for z in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
            if absi(x) <= 4 and absi(z) <= 4:
                continue
            var surface_y: int = heights[Vector2i(x, z)]
            if get_block_type(Vector3i(x, surface_y, z)) != TYPE_GRASS:
                continue
            var h: int = absi(hash(Vector3i(x, surface_y, z)))
            if (h % 100) >= TREE_CHANCE_PERCENT:
                continue
            _place_tree(x, surface_y, z)

    _spawn_height = heights[Vector2i(0, 0)]

    # Carve a 7×5×7 open-air pocket above spawn so even intruding leaves clear out.
    for dx in range(-3, 4):
        for dz in range(-3, 4):
            for dy in range(1, 6):
                var p: Vector3i = Vector3i(dx, _spawn_height + dy, dz)
                if has_block(p):
                    remove_block(p)


func _place_tree(x: int, surface_y: int, z: int) -> void:
    var trunk_h: int = 4 + (absi(hash(Vector2i(x, z))) % 3)  # 4-6 blocks tall
    for dh in range(1, trunk_h + 1):
        var p: Vector3i = Vector3i(x, surface_y + dh, z)
        if not has_block(p):
            add_block(p, TYPE_WOOD)
    var top_y: int = surface_y + trunk_h
    # 5×3×5 leaves cluster, corners + tapered top removed.
    for dx in range(-2, 3):
        for dz in range(-2, 3):
            for dy in range(-1, 2):
                if absi(dx) == 2 and absi(dz) == 2:
                    continue
                if dy == 1 and (absi(dx) >= 2 or absi(dz) >= 2):
                    continue
                if dx == 0 and dz == 0 and dy < 0:
                    continue
                var p: Vector3i = Vector3i(x + dx, top_y + dy, z + dz)
                if not has_block(p):
                    add_block(p, TYPE_LEAVES)
