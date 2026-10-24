class_name ProceduralRockMeshAdapter
extends RefCounted

## Converts a data-only stacked_spheres_v1 recipe into one irregular faceted stone.
## Lobe bounds determine the body envelope; the recipe lobes are not rendered as spheres.
const MAX_LOBES := 32
const SUBDIVISION_LEVELS := 2
const EXPECTED_TRIANGLES := 320
const MAX_ABS_SEED := 2147483647
const GEOMETRY_VERSION := 2
const MIN_RADIUS_MM := 50
const MAX_RADIUS_MM := 5000
const MIN_TRIANGLE_AREA_SQUARED := 1.0e-12
const MAX_RADIAL_VARIATION := 0.15


static func build_mesh(lobes: Array, variation_seed: int) -> Dictionary:
	if lobes.is_empty() or lobes.size() > MAX_LOBES:
		return _failure("invalid_lobe_count")
	if variation_seed < 0 or variation_seed > MAX_ABS_SEED:
		return _failure("invalid_variation_seed")
	var bounds := _recipe_bounds(lobes)
	if not bounds.get("ok", false):
		return bounds
	var center_mm: Vector3 = bounds["center_mm"]
	var half_extents_mm: Vector3 = bounds["half_extents_mm"]
	var sphere := _create_icosphere()
	var unit_vertices: Array[Vector3] = sphere["vertices"]
	var faces: Array[Vector3i] = sphere["faces"]
	var deformed_vertices: Array[Vector3] = []
	deformed_vertices.resize(unit_vertices.size())
	var center := center_mm / 1000.0
	var half_extents := half_extents_mm / 1000.0
	for index in range(unit_vertices.size()):
		var direction: Vector3 = unit_vertices[index]
		var radial_scale := 1.0 + _radial_variation(direction, variation_seed, index)
		deformed_vertices[index] = center + Vector3(
			direction.x * half_extents.x,
			direction.y * half_extents.y,
			direction.z * half_extents.z
		) * radial_scale
	var output_vertices := PackedVector3Array()
	var output_normals := PackedVector3Array()
	for face in faces:
		var a: Vector3 = deformed_vertices[face.x]
		var b: Vector3 = deformed_vertices[face.y]
		var c: Vector3 = deformed_vertices[face.z]
		var face_normal := (b - a).cross(c - a)
		if face_normal.length_squared() <= MIN_TRIANGLE_AREA_SQUARED:
			return _failure("degenerate_triangle")
		var face_center := (a + b + c) / 3.0
		var outward := face_center - center
		if face_normal.dot(outward) < 0.0:
			var swap := b
			b = c
			c = swap
			face_normal = (b - a).cross(c - a)
		if not face_normal.is_finite() or face_normal.length_squared() <= MIN_TRIANGLE_AREA_SQUARED:
			return _failure("invalid_face_normal")
		var normal := face_normal.normalized()
		output_vertices.append_array(PackedVector3Array([a, b, c]))
		output_normals.append_array(PackedVector3Array([normal, normal, normal]))
	if faces.size() != EXPECTED_TRIANGLES:
		return _failure("unexpected_icosphere_topology")
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = output_vertices
	arrays[Mesh.ARRAY_NORMAL] = output_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() != 1:
		return _failure("mesh_commit_failed")
	return {
		"ok": true,
		"mesh": mesh,
		"vertex_count": output_vertices.size(),
		"triangle_count": faces.size(),
		"mesh_center": center,
		"half_extents": half_extents,
		"variation_seed": variation_seed,
		"geometry_version": GEOMETRY_VERSION,
	}


static func _recipe_bounds(lobes: Array) -> Dictionary:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for lobe_value in lobes:
		if not lobe_value is Dictionary or not lobe_value.get("center_mm") is Vector3i:
			return _failure("invalid_lobe_record")
		var center_mm: Vector3i = lobe_value["center_mm"]
		var radius_mm := int(lobe_value.get("radius_mm", 0))
		if radius_mm < MIN_RADIUS_MM or radius_mm > MAX_RADIUS_MM:
			return _failure("invalid_lobe_radius")
		var radius := Vector3.ONE * float(radius_mm)
		var lobe_center := Vector3(center_mm)
		minimum = minimum.min(lobe_center - radius)
		maximum = maximum.max(lobe_center + radius)
	var half_extents := (maximum - minimum) * 0.5
	if not half_extents.is_finite() or minf(half_extents.x, minf(half_extents.y, half_extents.z)) < MIN_RADIUS_MM:
		return _failure("invalid_recipe_envelope")
	return {"ok": true, "center_mm": (minimum + maximum) * 0.5, "half_extents_mm": half_extents}


static func _radial_variation(direction: Vector3, seed: int, vertex_index: int) -> float:
	var phase := float(seed % 100003) * 0.0137
	var broad := sin(direction.dot(Vector3(4.7, 7.1, 3.9)) + phase)
	var medium := sin(direction.dot(Vector3(-8.3, 2.9, 6.2)) - phase * 0.71)
	var fine := sin(direction.dot(Vector3(11.9, -9.1, 5.3)) + phase * 1.37)
	var hash_value := posmod(seed * 48271 + (vertex_index + 1) * 69621, MAX_ABS_SEED)
	var vertex_jitter := float(hash_value % 20001) / 10000.0 - 1.0
	return clampf(broad * 0.055 + medium * 0.035 + fine * 0.02 + vertex_jitter * 0.035, -MAX_RADIAL_VARIATION, MAX_RADIAL_VARIATION)


static func _create_icosphere() -> Dictionary:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var vertices: Array[Vector3] = [
		Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1),
	]
	for index in range(vertices.size()):
		vertices[index] = vertices[index].normalized()
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	for _level in range(SUBDIVISION_LEVELS):
		var midpoint_cache: Dictionary = {}
		var subdivided: Array[Vector3i] = []
		for face in faces:
			var ab := _midpoint_index(face.x, face.y, vertices, midpoint_cache)
			var bc := _midpoint_index(face.y, face.z, vertices, midpoint_cache)
			var ca := _midpoint_index(face.z, face.x, vertices, midpoint_cache)
			subdivided.append(Vector3i(face.x, ab, ca))
			subdivided.append(Vector3i(face.y, bc, ab))
			subdivided.append(Vector3i(face.z, ca, bc))
			subdivided.append(Vector3i(ab, bc, ca))
		faces = subdivided
	return {"vertices": vertices, "faces": faces}


static func _midpoint_index(first: int, second: int, vertices: Array[Vector3], midpoint_cache: Dictionary) -> int:
	var lower := mini(first, second)
	var upper := maxi(first, second)
	var key := lower * 1000 + upper
	if midpoint_cache.has(key):
		return int(midpoint_cache[key])
	var midpoint := (vertices[first] + vertices[second]).normalized()
	var index := vertices.size()
	vertices.append(midpoint)
	midpoint_cache[key] = index
	return index


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
