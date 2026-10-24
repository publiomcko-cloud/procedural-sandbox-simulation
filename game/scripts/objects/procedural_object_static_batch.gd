extends RefCounted
class_name ProceduralObjectStaticBatch

## Combines immutable, unmodified static instances into one surface per region.
## Stateful/deleted representatives remain individual and are never authoritative here.
const MAX_BATCH_VERTICES := 96000 # 64 objects x 500 triangles x 3 flat vertices.


static func build(items: Array[Dictionary]) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var sorted_items := items.duplicate()
	sorted_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("instance_id", "")) < String(b.get("instance_id", "")))
	var ids: Array[String] = []
	for item in sorted_items:
		if not item.get("mesh", null) is ArrayMesh:
			return _failure("static_batch_mesh_invalid")
		var source: ArrayMesh = item["mesh"]
		if source.get_surface_count() != 1:
			return _failure("static_batch_surface_count_invalid")
		var arrays: Array = source.surface_get_arrays(0)
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if source_vertices.is_empty() or source_vertices.size() != source_normals.size() or source_vertices.size() % 3 != 0:
			return _failure("static_batch_geometry_invalid")
		if vertices.size() + source_vertices.size() > MAX_BATCH_VERTICES:
			return _failure("static_batch_vertex_budget_exceeded")
		var scale_values: Vector3i = item.get("scale_milli", Vector3i(1000, 1000, 1000))
		var rotation_y := deg_to_rad(float(item.get("yaw_mdeg", 0)) / 1000.0)
		var position: Vector3 = item.get("position", Vector3.ZERO)
		var basis := Basis(Vector3.UP, rotation_y).scaled(Vector3(scale_values) / 1000.0)
		var normal_basis := basis.inverse().transposed()
		for index in range(source_vertices.size()):
			var transformed: Vector3 = basis * source_vertices[index] + position
			var transformed_normal: Vector3 = (normal_basis * source_normals[index]).normalized()
			if not transformed.is_finite() or not transformed_normal.is_finite() or transformed_normal.length_squared() < 0.99:
				return _failure("static_batch_nonfinite_transform")
			vertices.append(transformed)
			normals.append(transformed_normal)
		ids.append(String(item["instance_id"]))
	if vertices.is_empty():
		return {"ok": true, "reason": "empty_batch", "mesh": null, "instance_ids": [], "vertex_count": 0, "triangle_count": 0, "build_usec": Time.get_ticks_usec() - started_usec}
	var output_arrays: Array = []
	output_arrays.resize(Mesh.ARRAY_MAX)
	output_arrays[Mesh.ARRAY_VERTEX] = vertices
	output_arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output_arrays)
	if mesh.get_surface_count() != 1:
		return _failure("static_batch_commit_failed")
	return {"ok": true, "reason": "ok", "mesh": mesh, "instance_ids": ids, "vertex_count": vertices.size(), "triangle_count": vertices.size() / 3, "build_usec": Time.get_ticks_usec() - started_usec}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
