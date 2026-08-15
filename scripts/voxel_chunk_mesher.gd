class_name VoxelChunkMesher
extends RefCounted

## Pure greedy mesher for one column chunk. It reads world-coordinate voxel
## dictionaries and returns chunk-local vertex arrays grouped by render material.

const FACE_UP: int = 0
const FACE_DOWN: int = 1
const FACE_POS_X: int = 2
const FACE_NEG_X: int = 3
const FACE_POS_Z: int = 4
const FACE_NEG_Z: int = 5


static func build(
	coord: Vector2i,
	blocks: Dictionary,
	chunk_blocks: Dictionary,
	bottom_by_xz: Dictionary,
	chunk_size: int,
	grass_type: String,
	dirt_type: String
) -> Dictionary:
	var surfaces: Dictionary = {}
	if chunk_blocks.is_empty():
		return surfaces
	var min_y: int = 2147483647
	var max_y: int = -2147483648
	for pos_variant: Variant in chunk_blocks.keys():
		var pos: Vector3i = pos_variant as Vector3i
		min_y = mini(min_y, pos.y)
		max_y = maxi(max_y, pos.y)
	var origin_x: int = coord.x * chunk_size
	var origin_z: int = coord.y * chunk_size
	_build_horizontal_faces(surfaces, blocks, bottom_by_xz, origin_x, origin_z, min_y, max_y, chunk_size, grass_type, dirt_type)
	_build_x_faces(surfaces, blocks, origin_x, origin_z, min_y, max_y, chunk_size, grass_type, dirt_type)
	_build_z_faces(surfaces, blocks, origin_x, origin_z, min_y, max_y, chunk_size, grass_type, dirt_type)
	return surfaces


static func _build_horizontal_faces(
	surfaces: Dictionary,
	blocks: Dictionary,
	bottom_by_xz: Dictionary,
	origin_x: int,
	origin_z: int,
	min_y: int,
	max_y: int,
	chunk_size: int,
	grass_type: String,
	dirt_type: String
) -> void:
	for y: int in range(min_y, max_y + 1):
		var up_mask: Array[String] = _empty_mask(chunk_size * chunk_size)
		var down_mask: Array[String] = _empty_mask(chunk_size * chunk_size)
		for lz: int in chunk_size:
			for lx: int in chunk_size:
				var pos: Vector3i = Vector3i(origin_x + lx, y, origin_z + lz)
				var block_type: String = String(blocks.get(pos, ""))
				if block_type.is_empty():
					continue
				var mask_index: int = lz * chunk_size + lx
				if not blocks.has(pos + Vector3i.UP):
					up_mask[mask_index] = grass_type if block_type == grass_type else block_type
				var below: Vector3i = pos + Vector3i.DOWN
				var bottom_y: int = int(bottom_by_xz.get(Vector2i(pos.x, pos.z), -2147483648))
				if not blocks.has(below) and below.y >= bottom_y:
					down_mask[mask_index] = dirt_type if block_type == grass_type else block_type
		_emit_horizontal_rects(surfaces, up_mask, y, chunk_size, FACE_UP)
		_emit_horizontal_rects(surfaces, down_mask, y, chunk_size, FACE_DOWN)


static func _emit_horizontal_rects(
	surfaces: Dictionary, mask: Array[String], y: int, chunk_size: int, face: int
) -> void:
	for rect_variant: Variant in _greedy_rectangles(mask, chunk_size, chunk_size):
		var rect: Dictionary = rect_variant as Dictionary
		var x0: float = float(int(rect["u"])) - 0.5
		var x1: float = x0 + float(int(rect["width"]))
		var z0: float = float(int(rect["v"])) - 0.5
		var z1: float = z0 + float(int(rect["height"]))
		var plane_y: float = float(y) + (0.5 if face == FACE_UP else -0.5)
		var corners: Array[Vector3]
		var normal: Vector3
		if face == FACE_UP:
			normal = Vector3.UP
			corners = [Vector3(x0, plane_y, z0), Vector3(x1, plane_y, z0), Vector3(x1, plane_y, z1), Vector3(x0, plane_y, z1)]
		else:
			normal = Vector3.DOWN
			corners = [Vector3(x0, plane_y, z0), Vector3(x0, plane_y, z1), Vector3(x1, plane_y, z1), Vector3(x1, plane_y, z0)]
		_append_quad(surfaces, String(rect["key"]), corners, normal, float(rect["width"]), float(rect["height"]))


static func _build_x_faces(
	surfaces: Dictionary,
	blocks: Dictionary,
	origin_x: int,
	origin_z: int,
	min_y: int,
	max_y: int,
	chunk_size: int,
	grass_type: String,
	dirt_type: String
) -> void:
	var y_count: int = max_y - min_y + 1
	for lx: int in chunk_size:
		var pos_mask: Array[String] = _empty_mask(chunk_size * y_count)
		var neg_mask: Array[String] = _empty_mask(chunk_size * y_count)
		for yi: int in y_count:
			var y: int = min_y + yi
			for lz: int in chunk_size:
				var pos: Vector3i = Vector3i(origin_x + lx, y, origin_z + lz)
				var block_type: String = String(blocks.get(pos, ""))
				if block_type.is_empty():
					continue
				var key: String = dirt_type if block_type == grass_type else block_type
				var mask_index: int = yi * chunk_size + lz
				if not blocks.has(pos + Vector3i.RIGHT):
					pos_mask[mask_index] = key
				if not blocks.has(pos + Vector3i.LEFT):
					neg_mask[mask_index] = key
		_emit_x_rects(surfaces, pos_mask, lx, min_y, chunk_size, y_count, FACE_POS_X)
		_emit_x_rects(surfaces, neg_mask, lx, min_y, chunk_size, y_count, FACE_NEG_X)


static func _emit_x_rects(
	surfaces: Dictionary,
	mask: Array[String],
	lx: int,
	min_y: int,
	chunk_size: int,
	y_count: int,
	face: int
) -> void:
	for rect_variant: Variant in _greedy_rectangles(mask, chunk_size, y_count):
		var rect: Dictionary = rect_variant as Dictionary
		var z0: float = float(int(rect["u"])) - 0.5
		var z1: float = z0 + float(int(rect["width"]))
		var y0: float = float(min_y + int(rect["v"])) - 0.5
		var y1: float = y0 + float(int(rect["height"]))
		var plane_x: float = float(lx) + (0.5 if face == FACE_POS_X else -0.5)
		var corners: Array[Vector3]
		var normal: Vector3
		if face == FACE_POS_X:
			normal = Vector3.RIGHT
			corners = [Vector3(plane_x, y0, z0), Vector3(plane_x, y0, z1), Vector3(plane_x, y1, z1), Vector3(plane_x, y1, z0)]
		else:
			normal = Vector3.LEFT
			corners = [Vector3(plane_x, y0, z0), Vector3(plane_x, y1, z0), Vector3(plane_x, y1, z1), Vector3(plane_x, y0, z1)]
		_append_quad(surfaces, String(rect["key"]), corners, normal, float(rect["width"]), float(rect["height"]))


static func _build_z_faces(
	surfaces: Dictionary,
	blocks: Dictionary,
	origin_x: int,
	origin_z: int,
	min_y: int,
	max_y: int,
	chunk_size: int,
	grass_type: String,
	dirt_type: String
) -> void:
	var y_count: int = max_y - min_y + 1
	for lz: int in chunk_size:
		var pos_mask: Array[String] = _empty_mask(chunk_size * y_count)
		var neg_mask: Array[String] = _empty_mask(chunk_size * y_count)
		for yi: int in y_count:
			var y: int = min_y + yi
			for lx: int in chunk_size:
				var pos: Vector3i = Vector3i(origin_x + lx, y, origin_z + lz)
				var block_type: String = String(blocks.get(pos, ""))
				if block_type.is_empty():
					continue
				var key: String = dirt_type if block_type == grass_type else block_type
				var mask_index: int = yi * chunk_size + lx
				if not blocks.has(pos + Vector3i.BACK):
					pos_mask[mask_index] = key
				if not blocks.has(pos + Vector3i.FORWARD):
					neg_mask[mask_index] = key
		_emit_z_rects(surfaces, pos_mask, lz, min_y, chunk_size, y_count, FACE_POS_Z)
		_emit_z_rects(surfaces, neg_mask, lz, min_y, chunk_size, y_count, FACE_NEG_Z)


static func _emit_z_rects(
	surfaces: Dictionary,
	mask: Array[String],
	lz: int,
	min_y: int,
	chunk_size: int,
	y_count: int,
	face: int
) -> void:
	for rect_variant: Variant in _greedy_rectangles(mask, chunk_size, y_count):
		var rect: Dictionary = rect_variant as Dictionary
		var x0: float = float(int(rect["u"])) - 0.5
		var x1: float = x0 + float(int(rect["width"]))
		var y0: float = float(min_y + int(rect["v"])) - 0.5
		var y1: float = y0 + float(int(rect["height"]))
		var plane_z: float = float(lz) + (0.5 if face == FACE_POS_Z else -0.5)
		var corners: Array[Vector3]
		var normal: Vector3
		if face == FACE_POS_Z:
			normal = Vector3.BACK
			corners = [Vector3(x0, y0, plane_z), Vector3(x0, y1, plane_z), Vector3(x1, y1, plane_z), Vector3(x1, y0, plane_z)]
		else:
			normal = Vector3.FORWARD
			corners = [Vector3(x0, y0, plane_z), Vector3(x1, y0, plane_z), Vector3(x1, y1, plane_z), Vector3(x0, y1, plane_z)]
		_append_quad(surfaces, String(rect["key"]), corners, normal, float(rect["width"]), float(rect["height"]))


static func _empty_mask(size: int) -> Array[String]:
	var mask: Array[String] = []
	mask.resize(size)
	mask.fill("")
	return mask


static func _greedy_rectangles(mask: Array[String], width: int, height: int) -> Array[Dictionary]:
	var rectangles: Array[Dictionary] = []
	var consumed: PackedByteArray = PackedByteArray()
	consumed.resize(mask.size())
	for v: int in height:
		for u: int in width:
			var index: int = v * width + u
			var key: String = mask[index]
			if key.is_empty() or consumed[index] != 0:
				continue
			var rect_width: int = 1
			while u + rect_width < width:
				var next_index: int = v * width + u + rect_width
				if consumed[next_index] != 0 or mask[next_index] != key:
					break
				rect_width += 1
			var rect_height: int = 1
			while v + rect_height < height:
				var row_matches: bool = true
				for du: int in rect_width:
					var row_index: int = (v + rect_height) * width + u + du
					if consumed[row_index] != 0 or mask[row_index] != key:
						row_matches = false
						break
				if not row_matches:
					break
				rect_height += 1
			for dv: int in rect_height:
				for du: int in rect_width:
					consumed[(v + dv) * width + u + du] = 1
			rectangles.append({"key": key, "u": u, "v": v, "width": rect_width, "height": rect_height})
	return rectangles


static func _append_quad(
	surfaces: Dictionary,
	key: String,
	corners: Array[Vector3],
	normal: Vector3,
	uv_width: float,
	uv_height: float
) -> void:
	if not surfaces.has(key):
		surfaces[key] = {"vertices": [], "normals": [], "uvs": [], "indices": []}
	var surface: Dictionary = surfaces[key] as Dictionary
	var vertices: Array = surface["vertices"] as Array
	var normals: Array = surface["normals"] as Array
	var uvs: Array = surface["uvs"] as Array
	var indices: Array = surface["indices"] as Array
	var base: int = vertices.size()
	for corner: Vector3 in corners:
		vertices.append(corner)
		normals.append(normal)
	uvs.append(Vector2(0.0, 0.0))
	uvs.append(Vector2(uv_width, 0.0))
	uvs.append(Vector2(uv_width, uv_height))
	uvs.append(Vector2(0.0, uv_height))
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


static func quad_count(surfaces: Dictionary) -> int:
	var count: int = 0
	for surface_variant: Variant in surfaces.values():
		var surface: Dictionary = surface_variant as Dictionary
		count += int((surface["indices"] as Array).size() / 6.0)
	return count
