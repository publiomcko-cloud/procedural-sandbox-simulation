extends RefCounted
class_name ProceduralObjectStaticBatch

## Combines procedural instance CPU geometry into one regional surface.
## D.7.2 splits CPU transformation/concatenation from ArrayMesh creation so the
## expensive deterministic work can run on WorkerThreadPool. Rendering-resource
## commits remain main-thread only.
const MAX_BATCH_VERTICES := 96000 # 64 objects x 500 triangles x 3 flat vertices.


static func prepare(items: Array[Dictionary]) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var sorted_items := items.duplicate()
	sorted_items.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("instance_id", "")) < String(b.get("instance_id", ""))
	)
	var ids: Array[String] = []
	var cpu_source_count := 0
	var mesh_source_count := 0
	for item in sorted_items:
		var source_vertices := PackedVector3Array()
		var source_normals := PackedVector3Array()
		var cpu_value: Variant = item.get("cpu_data", {})
		if (
			typeof(cpu_value) == TYPE_DICTIONARY
			and not (cpu_value as Dictionary).is_empty()
		):
			var cpu_data: Dictionary = cpu_value
			if not cpu_data.get("ok", false):
				return _failure("static_batch_cpu_data_invalid")
			source_vertices = cpu_data.get(
				"positions", PackedVector3Array()
			)
			source_normals = cpu_data.get(
				"normals", PackedVector3Array()
			)
			cpu_source_count += 1
		else:
			# Legacy synchronous callers may still prepare from an ArrayMesh.
			# D.7.2 worker jobs reject such items before entering this function.
			if not item.get("mesh", null) is ArrayMesh:
				return _failure("static_batch_mesh_invalid")
			var source: ArrayMesh = item["mesh"]
			if source.get_surface_count() != 1:
				return _failure("static_batch_surface_count_invalid")
			var arrays: Array = source.surface_get_arrays(0)
			source_vertices = arrays[Mesh.ARRAY_VERTEX]
			source_normals = arrays[Mesh.ARRAY_NORMAL]
			mesh_source_count += 1
		if (
			source_vertices.is_empty()
			or source_vertices.size() != source_normals.size()
			or source_vertices.size() % 3 != 0
		):
			return _failure("static_batch_geometry_invalid")
		if vertices.size() + source_vertices.size() > MAX_BATCH_VERTICES:
			return _failure("static_batch_vertex_budget_exceeded")
		var position: Vector3 = item.get("position", Vector3.ZERO)
		var basis: Basis
		if typeof(item.get("basis", null)) == TYPE_BASIS:
			basis = item["basis"]
		else:
			var scale_values: Vector3i = item.get(
				"scale_milli", Vector3i(1000, 1000, 1000)
			)
			var rotation_y := deg_to_rad(
				float(item.get("yaw_mdeg", 0)) / 1000.0
			)
			basis = Basis(Vector3.UP, rotation_y).scaled_local(
				Vector3(scale_values) / 1000.0
			)
		if not position.is_finite() or not basis.is_finite():
			return _failure("static_batch_transform_invalid")
		var normal_basis := basis.inverse().transposed()
		for index in range(source_vertices.size()):
			var transformed: Vector3 = (
				basis * source_vertices[index] + position
			)
			var transformed_normal: Vector3 = (
				normal_basis * source_normals[index]
			).normalized()
			if (
				not transformed.is_finite()
				or not transformed_normal.is_finite()
				or transformed_normal.length_squared() < 0.99
			):
				return _failure("static_batch_nonfinite_transform")
			vertices.append(transformed)
			normals.append(transformed_normal)
		ids.append(String(item["instance_id"]))
	return {
		"ok": true,
		"reason": "empty_batch" if vertices.is_empty() else "ok",
		"positions": vertices,
		"normals": normals,
		"instance_ids": ids,
		"vertex_count": vertices.size(),
		"triangle_count": vertices.size() / 3,
		"cpu_source_count": cpu_source_count,
		"mesh_source_count": mesh_source_count,
		"prepare_usec": Time.get_ticks_usec() - started_usec,
	}


static func commit(prepared: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not prepared.get("ok", false):
		return _failure(String(
			prepared.get("reason", "static_batch_prepare_invalid")
		))
	var vertices: PackedVector3Array = prepared.get(
		"positions", PackedVector3Array()
	)
	var normals: PackedVector3Array = prepared.get(
		"normals", PackedVector3Array()
	)
	if (
		vertices.size() != normals.size()
		or vertices.size() % 3 != 0
		or vertices.size() > MAX_BATCH_VERTICES
	):
		return _failure("static_batch_prepared_geometry_invalid")
	var common := {
		"ok": true,
		"reason": "empty_batch" if vertices.is_empty() else "ok",
		"instance_ids": prepared.get("instance_ids", []).duplicate(),
		"vertex_count": vertices.size(),
		"triangle_count": vertices.size() / 3,
		"cpu_source_count": int(prepared.get("cpu_source_count", 0)),
		"mesh_source_count": int(prepared.get("mesh_source_count", 0)),
		"prepare_usec": int(prepared.get("prepare_usec", 0)),
	}
	if vertices.is_empty():
		common["mesh"] = null
		common["commit_usec"] = Time.get_ticks_usec() - started_usec
		return common
	var output_arrays: Array = []
	output_arrays.resize(Mesh.ARRAY_MAX)
	output_arrays[Mesh.ARRAY_VERTEX] = vertices
	output_arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output_arrays)
	if mesh.get_surface_count() != 1:
		return _failure("static_batch_commit_failed")
	common["mesh"] = mesh
	common["commit_usec"] = Time.get_ticks_usec() - started_usec
	return common


static func build(items: Array[Dictionary]) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var prepared := prepare(items)
	if not prepared.get("ok", false):
		return prepared
	var committed := commit(prepared)
	if not committed.get("ok", false):
		return committed
	committed["build_usec"] = Time.get_ticks_usec() - started_usec
	return committed


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
