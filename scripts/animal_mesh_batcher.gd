class_name AnimalMeshBatcher
extends RefCounted

## Batches the many primitive MeshInstance3D parts in a blocky animal into a
## small set of ArrayMeshes. Animated branch roots keep their pivots, while all
## static shadow-casting and tiny non-shadow-casting parts are combined.

const NO_SHADOW_TOKENS: PackedStringArray = [
	"eye", "nostril", "ear", "beak", "comb", "wattle", "muzzle", "snout", "nose",
]


static func optimize(model: Node3D, animated_roots: Array[MeshInstance3D]) -> Array[StandardMaterial3D]:
	var all_parts: Array[MeshInstance3D] = []
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		all_parts.append(child as MeshInstance3D)
	var material_copies: Dictionary = {}
	var static_shadow: Array[MeshInstance3D] = []
	var static_no_shadow: Array[MeshInstance3D] = []
	for part: MeshInstance3D in all_parts:
		if _animated_owner(part, animated_roots) != null:
			continue
		if _is_minor_part(part.name):
			static_no_shadow.append(part)
		else:
			static_shadow.append(part)
	_batch_static_group(model, static_shadow, "StaticBody", true, material_copies)
	_batch_static_group(model, static_no_shadow, "MinorDetails", false, material_copies)
	for root: MeshInstance3D in animated_roots:
		_batch_animated_branch(root, all_parts, material_copies)
	var materials: Array[StandardMaterial3D] = []
	for material_variant: Variant in material_copies.values():
		materials.append(material_variant as StandardMaterial3D)
	return materials


static func _batch_static_group(
	model: Node3D,
	parts: Array[MeshInstance3D],
	group_name: String,
	casts_shadow: bool,
	material_copies: Dictionary
) -> void:
	if parts.is_empty():
		return
	var combined: ArrayMesh = _combine(parts, model, material_copies)
	if combined.get_surface_count() == 0:
		return
	var merged: MeshInstance3D = MeshInstance3D.new()
	merged.name = group_name
	merged.mesh = combined
	if not casts_shadow:
		merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(merged)
	for part: MeshInstance3D in parts:
		if is_instance_valid(part):
			part.free()


static func _batch_animated_branch(
	root: MeshInstance3D,
	all_parts: Array[MeshInstance3D],
	material_copies: Dictionary
) -> void:
	var branch: Array[MeshInstance3D] = []
	for part: MeshInstance3D in all_parts:
		if not is_instance_valid(part):
			continue
		if part == root or root.is_ancestor_of(part):
			branch.append(part)
	if branch.is_empty():
		return
	var combined: ArrayMesh = _combine(branch, root, material_copies)
	if combined.get_surface_count() > 0:
		root.mesh = combined
	for part: MeshInstance3D in branch:
		if part != root and is_instance_valid(part):
			part.free()


static func _combine(
	parts: Array[MeshInstance3D], relative_to: Node3D, material_copies: Dictionary
) -> ArrayMesh:
	var grouped: Dictionary = {}
	for part: MeshInstance3D in parts:
		if part.mesh == null:
			continue
		var transform: Transform3D = _relative_transform(part, relative_to)
		var normal_basis: Basis = transform.basis.inverse().transposed()
		for surface_index: int in part.mesh.get_surface_count():
			var source_material: Material = part.mesh.surface_get_material(surface_index)
			if source_material == null or not source_material is StandardMaterial3D:
				continue
			var material: StandardMaterial3D = _material_copy(source_material as StandardMaterial3D, material_copies)
			if not grouped.has(material):
				grouped[material] = {"vertices": [], "normals": [], "uvs": [], "indices": []}
			var output: Dictionary = grouped[material] as Dictionary
			var arrays: Array = part.mesh.surface_get_arrays(surface_index)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			var source_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			var vertices: Array = output["vertices"] as Array
			var normals: Array = output["normals"] as Array
			var uvs: Array = output["uvs"] as Array
			var indices: Array = output["indices"] as Array
			var base: int = vertices.size()
			for vertex_index: int in source_vertices.size():
				vertices.append(transform * source_vertices[vertex_index])
				var normal: Vector3 = source_normals[vertex_index] if vertex_index < source_normals.size() else Vector3.UP
				normals.append((normal_basis * normal).normalized())
				uvs.append(source_uvs[vertex_index] if vertex_index < source_uvs.size() else Vector2.ZERO)
			if source_indices.is_empty():
				for vertex_index: int in source_vertices.size():
					indices.append(base + vertex_index)
			else:
				for source_index: int in source_indices:
					indices.append(base + source_index)
	var combined: ArrayMesh = ArrayMesh.new()
	for material_variant: Variant in grouped.keys():
		var material: StandardMaterial3D = material_variant as StandardMaterial3D
		var output: Dictionary = grouped[material] as Dictionary
		var surface_arrays: Array = []
		surface_arrays.resize(Mesh.ARRAY_MAX)
		surface_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(output["vertices"] as Array)
		surface_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(output["normals"] as Array)
		surface_arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(output["uvs"] as Array)
		surface_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(output["indices"] as Array)
		combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		combined.surface_set_material(combined.get_surface_count() - 1, material)
	return combined


static func _relative_transform(node: Node3D, relative_to: Node3D) -> Transform3D:
	if node == relative_to:
		return Transform3D.IDENTITY
	var transform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null and parent != relative_to:
		if parent is Node3D:
			transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return transform


static func _material_copy(
	source: StandardMaterial3D, material_copies: Dictionary
) -> StandardMaterial3D:
	if material_copies.has(source):
		return material_copies[source] as StandardMaterial3D
	var copy: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	material_copies[source] = copy
	return copy


static func _animated_owner(
	part: MeshInstance3D, animated_roots: Array[MeshInstance3D]
) -> MeshInstance3D:
	for root: MeshInstance3D in animated_roots:
		if part == root or root.is_ancestor_of(part):
			return root
	return null


static func _is_minor_part(part_name: StringName) -> bool:
	var lower_name: String = String(part_name).to_lower()
	for token: String in NO_SHADOW_TOKENS:
		if lower_name.contains(token):
			return true
	return false
