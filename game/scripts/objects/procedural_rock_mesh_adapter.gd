class_name ProceduralRockMeshAdapter
extends RefCounted

## Builds versioned rock shells from intersections of oriented half-spaces.
## All noise is a deterministic function of local coordinates; no per-vertex RNG is used.
const GEOMETRY_VERSION := 3
const ALGORITHM := "geological_halfspace_v1"
const MAX_SEED := 2147483646
const MIN_TRIANGLES := 100
const MAX_TRIANGLES := 500
const MIN_AREA_SQUARED := 1.0e-12
const RECIPE_KEYS := [
	"algorithm", "profile", "half_extent_x_mm", "half_extent_y_mm", "half_extent_z_mm",
	"primary_plane_count", "fracture_plane_count", "anisotropy_axis", "anisotropy_milli",
	"bevel_count", "weathering_milli", "macro_roughness_mm", "meso_roughness_mm", "fine_roughness_mm"
]
const SEED_KEYS := ["structure", "fracture", "wear", "detail"]
const RAND_MOD := 2147483647


static func build_mesh(recipe: Dictionary, seeds: Dictionary) -> Dictionary:
	var cpu_data := build_cpu_data(recipe, seeds)
	if not cpu_data.get("ok", false):
		return cpu_data
	return mesh_from_cpu_data(cpu_data)


## Pure geometry path suitable for WorkerThreadPool. No Resource, RenderingServer
## or SceneTree object is created here.
static func build_cpu_data(recipe: Dictionary, seeds: Dictionary) -> Dictionary:
	var input_check := _validate_input(recipe, seeds)
	if not input_check.get("ok", false):
		return input_check
	var half_extents := Vector3(
		float(recipe["half_extent_x_mm"]),
		float(recipe["half_extent_y_mm"]),
		float(recipe["half_extent_z_mm"])
	) / 1000.0
	var center := Vector3(0.0, half_extents.y, 0.0)
	var shell := _create_box(half_extents)
	var points: Array[Vector3] = shell["points"]
	var polygons: Array = shell["polygons"]
	var point_cache: Dictionary = {}
	for index in range(points.size()):
		point_cache[_point_key(points[index])] = index
	var structure_state := int(seeds["structure"])
	for _index in range(int(recipe["primary_plane_count"])):
		var sampled: Dictionary = _random_unit(structure_state)
		structure_state = int(sampled["state"])
		var normal: Vector3 = sampled["vector"]
		var fraction := 0.64 + _random_unit_float(structure_state) * 0.20
		structure_state = _next_random(structure_state)
		var cut := _support_distance(normal, half_extents) * fraction
		var clipped := _clip_half_space(points, polygons, point_cache, normal, center.dot(normal) + cut)
		if not clipped.get("ok", false):
			return clipped
		polygons = clipped["polygons"]

	var fracture_state := int(seeds["fracture"])
	var preferred_axis := _axis_index(String(recipe["anisotropy_axis"]))
	for _index in range(int(recipe["fracture_plane_count"])):
		var sampled: Dictionary = _random_unit(fracture_state)
		fracture_state = int(sampled["state"])
		var normal: Vector3 = sampled["vector"]
		var attenuation := 1.0 - float(recipe["anisotropy_milli"]) / 2000.0
		normal[preferred_axis] *= attenuation
		if normal.length_squared() < 0.04:
			normal[preferred_axis] = 0.35
		normal = normal.normalized()
		var fraction := 0.62 + _random_unit_float(fracture_state) * 0.20
		fracture_state = _next_random(fracture_state)
		var cut := _support_distance(normal, half_extents) * fraction
		var clipped := _clip_half_space(points, polygons, point_cache, normal, center.dot(normal) + cut)
		if not clipped.get("ok", false):
			return clipped
		polygons = clipped["polygons"]

	var wear_state := int(seeds["wear"])
	for _index in range(int(recipe["bevel_count"])):
		var signs := Vector3(
			-1.0 if _random_bit(wear_state) == 0 else 1.0,
			-1.0 if _random_bit(_next_random(wear_state)) == 0 else 1.0,
			-1.0 if _random_bit(_next_random(_next_random(wear_state))) == 0 else 1.0
		)
		wear_state = _next_random(_next_random(_next_random(wear_state)))
		var normal := Vector3(signs.x / half_extents.x, signs.y / half_extents.y, signs.z / half_extents.z).normalized()
		var bevel_fraction := 0.055 + _random_unit_float(wear_state) * 0.065
		wear_state = _next_random(wear_state)
		var support := _support_distance(normal, half_extents)
		var clipped := _clip_half_space(points, polygons, point_cache, normal, center.dot(normal) + support * (1.0 - bevel_fraction))
		if not clipped.get("ok", false):
			return clipped
		polygons = clipped["polygons"]

	var triangulated := _triangulate_polygons(points, polygons, center)
	if not triangulated.get("ok", false):
		return triangulated
	var vertices: Array[Vector3] = triangulated["points"]
	var triangles: Array[Vector3i] = triangulated["triangles"]
	var subdivided := _subdivide_once(vertices, triangles)
	vertices = subdivided["points"]
	triangles = subdivided["triangles"]
	var weathering := float(recipe["weathering_milli"]) / 1000.0
	vertices = _wear_vertices(vertices, triangles, weathering, int(seeds["wear"]))
	vertices = _apply_coherent_roughness(vertices, triangles, recipe, int(seeds["detail"]), preferred_axis)
	var lowest_y := INF
	for vertex in vertices:
		lowest_y = minf(lowest_y, vertex.y)
	for vertex_index in range(vertices.size()):
		var grounded_vertex: Vector3 = vertices[vertex_index]
		grounded_vertex.y -= lowest_y
		vertices[vertex_index] = grounded_vertex
	center.y -= lowest_y
	if triangles.size() < MIN_TRIANGLES or triangles.size() > MAX_TRIANGLES:
		return _failure("triangle_budget_exceeded")

	var output_vertices := PackedVector3Array()
	var output_normals := PackedVector3Array()
	var signed_volume := 0.0
	var surface_area := 0.0
	for triangle in triangles:
		var a: Vector3 = vertices[triangle.x]
		var b: Vector3 = vertices[triangle.y]
		var c: Vector3 = vertices[triangle.z]
		var cross := (b - a).cross(c - a)
		if not cross.is_finite() or cross.length_squared() <= MIN_AREA_SQUARED:
			return _failure("degenerate_triangle")
		var face_center := (a + b + c) / 3.0
		if cross.dot(face_center - center) < 0.0:
			var temporary := b
			b = c
			c = temporary
			cross = (b - a).cross(c - a)
		var normal := cross.normalized()
		if not normal.is_finite() or normal.length_squared() < 0.99:
			return _failure("invalid_face_normal")
		output_vertices.append_array(PackedVector3Array([a, b, c]))
		output_normals.append_array(PackedVector3Array([normal, normal, normal]))
		signed_volume += a.dot(b.cross(c)) / 6.0
		surface_area += cross.length() * 0.5
	if not is_finite(signed_volume) or signed_volume <= 1.0e-8 or not is_finite(surface_area) or surface_area <= 0.0:
		return _failure("invalid_shell_measure")
	var bounds := _measure_bounds(vertices)
	return {
		"ok": true,
		"positions": output_vertices,
		"normals": output_normals,
		"triangle_count": triangles.size(),
		"vertex_count": output_vertices.size(),
		"unique_vertex_count": vertices.size(),
		"surface_area_m2": surface_area,
		"volume_m3": signed_volume,
		"bounds_min": bounds["min"],
		"bounds_max": bounds["max"],
		"profile": recipe["profile"],
		"geometry_version": GEOMETRY_VERSION,
		"algorithm": ALGORITHM,
		"geometry_seeds": seeds.duplicate(true),
	}


## Main-thread resource commit for worker-produced geometry data.
static func mesh_from_cpu_data(cpu_data: Dictionary) -> Dictionary:
	if not cpu_data.get("ok", false):
		return cpu_data
	var positions: PackedVector3Array = cpu_data.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = cpu_data.get("normals", PackedVector3Array())
	if positions.is_empty() or positions.size() != normals.size() or positions.size() % 3 != 0:
		return _failure("mesh_cpu_data_invalid")
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() != 1:
		return _failure("mesh_commit_failed")
	var result: Dictionary = cpu_data.duplicate(false)
	result["mesh"] = mesh
	result.erase("positions")
	result.erase("normals")
	return result


static func _validate_input(recipe: Dictionary, seeds: Dictionary) -> Dictionary:
	if recipe.size() != RECIPE_KEYS.size() or seeds.size() != SEED_KEYS.size():
		return _failure("geometry_recipe_or_seed_fields")
	for key in RECIPE_KEYS:
		if not recipe.has(key):
			return _failure("missing_geometry_recipe_field:%s" % key)
	for key in SEED_KEYS:
		if not seeds.has(key) or typeof(seeds[key]) != TYPE_INT or int(seeds[key]) < 1 or int(seeds[key]) > MAX_SEED:
			return _failure("invalid_geometry_seeds")
	if recipe["algorithm"] != ALGORITHM or not ["granite_massive_weathered_v1", "basalt_fractured_anisotropic_v1"].has(recipe["profile"]):
		return _failure("unsupported_geometry_version_or_profile:%s:%s" % [recipe["algorithm"], recipe["profile"]])
	for key in RECIPE_KEYS.slice(2):
		if key == "anisotropy_axis":
			if not ["x", "y", "z"].has(recipe[key]):
				return _failure("invalid_geometry_axis")
		elif not _is_integer(recipe[key]):
			return _failure("invalid_geometry_integer_field:%s" % key)
	for key in ["half_extent_x_mm", "half_extent_y_mm", "half_extent_z_mm"]:
		if int(recipe[key]) < 300 or int(recipe[key]) > 1800:
			return _failure("geometry_extent_out_of_range")
	if int(recipe["primary_plane_count"]) < 4 or int(recipe["primary_plane_count"]) > 10 or int(recipe["fracture_plane_count"]) < 1 or int(recipe["fracture_plane_count"]) > 7 or int(recipe["bevel_count"]) < 1 or int(recipe["bevel_count"]) > 5:
		return _failure("geometry_plane_count_out_of_range")
	if int(recipe["anisotropy_milli"]) < 700 or int(recipe["anisotropy_milli"]) > 1900 or int(recipe["weathering_milli"]) < 0 or int(recipe["weathering_milli"]) > 1000:
		return _failure("geometry_profile_parameter_out_of_range")
	if int(recipe["macro_roughness_mm"]) < 0 or int(recipe["macro_roughness_mm"]) > 100 or int(recipe["meso_roughness_mm"]) < 0 or int(recipe["meso_roughness_mm"]) > 60 or int(recipe["fine_roughness_mm"]) < 0 or int(recipe["fine_roughness_mm"]) > 30:
		return _failure("geometry_roughness_out_of_range")
	if recipe["profile"] == "granite_massive_weathered_v1" and (int(recipe["fracture_plane_count"]) > 3 or int(recipe["weathering_milli"]) < 600 or int(recipe["anisotropy_milli"]) > 1300):
		return _failure("granite_profile_parameters_invalid")
	if recipe["profile"] == "basalt_fractured_anisotropic_v1" and (int(recipe["fracture_plane_count"]) < 4 or int(recipe["weathering_milli"]) > 450 or int(recipe["anisotropy_milli"]) < 1300):
		return _failure("basalt_profile_parameters_invalid")
	return {"ok": true}


static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value and absf(value) <= 9007199254740991.0)


static func _create_box(half_extents: Vector3) -> Dictionary:
	var points: Array[Vector3] = [
		Vector3(-half_extents.x, 0.0, -half_extents.z), Vector3(half_extents.x, 0.0, -half_extents.z),
		Vector3(half_extents.x, half_extents.y * 2.0, -half_extents.z), Vector3(-half_extents.x, half_extents.y * 2.0, -half_extents.z),
		Vector3(-half_extents.x, 0.0, half_extents.z), Vector3(half_extents.x, 0.0, half_extents.z),
		Vector3(half_extents.x, half_extents.y * 2.0, half_extents.z), Vector3(-half_extents.x, half_extents.y * 2.0, half_extents.z),
	]
	var polygons: Array = [
		PackedInt32Array([0, 3, 2, 1]), PackedInt32Array([4, 5, 6, 7]),
		PackedInt32Array([0, 4, 7, 3]), PackedInt32Array([1, 2, 6, 5]),
		PackedInt32Array([0, 1, 5, 4]), PackedInt32Array([3, 7, 6, 2]),
	]
	return {"points": points, "polygons": polygons}


static func _clip_half_space(points: Array[Vector3], polygons: Array, point_cache: Dictionary, normal: Vector3, distance: float) -> Dictionary:
	var output_polygons: Array = []
	var cap_indices: Dictionary = {}
	var changed := false
	for polygon_value in polygons:
		var polygon: PackedInt32Array = polygon_value
		var output := PackedInt32Array()
		for edge_index in range(polygon.size()):
			var first_index: int = polygon[edge_index]
			var second_index: int = polygon[(edge_index + 1) % polygon.size()]
			var first: Vector3 = points[first_index]
			var second: Vector3 = points[second_index]
			var first_delta := normal.dot(first) - distance
			var second_delta := normal.dot(second) - distance
			var first_inside := first_delta <= 1.0e-8
			var second_inside := second_delta <= 1.0e-8
			if first_inside:
				_append_unique(output, first_index)
			else:
				changed = true
			if first_inside != second_inside:
				var denominator := first_delta - second_delta
				if absf(denominator) <= 1.0e-12:
					return _failure("unstable_plane_intersection")
				var amount := clampf(first_delta / denominator, 0.0, 1.0)
				var intersection: Vector3 = first.lerp(second, amount)
				var index := _insert_point(points, point_cache, intersection)
				_append_unique(output, index)
				cap_indices[index] = true
		output = _clean_polygon(output, points)
		if output.size() >= 3:
			output_polygons.append(output)
	if not changed:
		return {"ok": true, "polygons": polygons}
	if cap_indices.size() >= 3:
		var cap: Array[int] = []
		var cap_center := Vector3.ZERO
		for index_value in cap_indices:
			var index := int(index_value)
			cap.append(index)
			cap_center += points[index]
		cap_center /= float(cap.size())
		var reference := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.92 else Vector3.UP
		var basis_u := normal.cross(reference).normalized()
		var basis_v := normal.cross(basis_u).normalized()
		cap.sort_custom(func(a: int, b: int) -> bool:
			var delta_a: Vector3 = points[a] - cap_center
			var delta_b: Vector3 = points[b] - cap_center
			return atan2(delta_a.dot(basis_v), delta_a.dot(basis_u)) < atan2(delta_b.dot(basis_v), delta_b.dot(basis_u))
		)
		var cap_polygon := PackedInt32Array()
		for index in cap:
			_append_unique(cap_polygon, index)
		cap_polygon = _clean_polygon(cap_polygon, points)
		if cap_polygon.size() >= 3:
			output_polygons.append(cap_polygon)
	if output_polygons.size() < 4:
		return _failure("half_space_removed_shell")
	return {"ok": true, "polygons": output_polygons}


static func _triangulate_polygons(points: Array[Vector3], polygons: Array, center: Vector3) -> Dictionary:
	var output_points: Array[Vector3] = points.duplicate()
	var triangles: Array[Vector3i] = []
	for polygon_value in polygons:
		var polygon: PackedInt32Array = polygon_value
		if polygon.size() < 3:
			return _failure("invalid_clipped_face")
		var face_center := Vector3.ZERO
		for index in polygon:
			face_center += output_points[index]
		face_center /= float(polygon.size())
		var center_index := output_points.size()
		output_points.append(face_center)
		for edge_index in range(polygon.size()):
			var a: int = polygon[edge_index]
			var b: int = polygon[(edge_index + 1) % polygon.size()]
			var triangle := Vector3i(a, b, center_index)
			var normal := (output_points[b] - output_points[a]).cross(face_center - output_points[a])
			if normal.length_squared() <= MIN_AREA_SQUARED:
				return _failure("degenerate_clipped_face")
			if normal.dot(face_center - center) < 0.0:
				triangle = Vector3i(b, a, center_index)
			triangles.append(triangle)
	if triangles.size() < 25:
		return _failure("insufficient_base_surface")
	return {"ok": true, "points": output_points, "triangles": triangles}


static func _subdivide_once(points: Array[Vector3], triangles: Array[Vector3i]) -> Dictionary:
	var output_points: Array[Vector3] = points.duplicate()
	var midpoint_cache: Dictionary = {}
	var output_triangles: Array[Vector3i] = []
	for triangle in triangles:
		var ab := _midpoint_index(triangle.x, triangle.y, output_points, midpoint_cache)
		var bc := _midpoint_index(triangle.y, triangle.z, output_points, midpoint_cache)
		var ca := _midpoint_index(triangle.z, triangle.x, output_points, midpoint_cache)
		output_triangles.append(Vector3i(triangle.x, ab, ca))
		output_triangles.append(Vector3i(triangle.y, bc, ab))
		output_triangles.append(Vector3i(triangle.z, ca, bc))
		output_triangles.append(Vector3i(ab, bc, ca))
	return {"points": output_points, "triangles": output_triangles}


static func _wear_vertices(points: Array[Vector3], triangles: Array[Vector3i], weathering: float, seed: int) -> Array[Vector3]:
	var neighbors: Array = []
	var normal_sums: Array[Vector3] = []
	var face_normals: Array = []
	var curvature_values: Array[float] = []
	neighbors.resize(points.size())
	normal_sums.resize(points.size())
	curvature_values.resize(points.size())
	for index in range(points.size()):
		neighbors[index] = {}
		normal_sums[index] = Vector3.ZERO
		curvature_values[index] = 0.0
	for triangle in triangles:
		var normal := (points[triangle.y] - points[triangle.x]).cross(points[triangle.z] - points[triangle.x]).normalized()
		face_normals.append(normal)
		for vertex_index in [triangle.x, triangle.y, triangle.z]:
			normal_sums[vertex_index] = (normal_sums[vertex_index] as Vector3) + normal
		for pair in [[triangle.x, triangle.y], [triangle.y, triangle.z], [triangle.z, triangle.x]]:
			(neighbors[pair[0]] as Dictionary)[pair[1]] = true
			(neighbors[pair[1]] as Dictionary)[pair[0]] = true
	for triangle_index in range(triangles.size()):
		var triangle: Vector3i = triangles[triangle_index]
		var face_normal: Vector3 = face_normals[triangle_index]
		for vertex_index in [triangle.x, triangle.y, triangle.z]:
			var average_normal: Vector3 = (normal_sums[vertex_index] as Vector3).normalized()
			curvature_values[vertex_index] = maxf(curvature_values[vertex_index], 1.0 - average_normal.dot(face_normal))
	var output := points.duplicate()
	for index in range(points.size()):
		var average_normal: Vector3 = (normal_sums[index] as Vector3).normalized()
		var neighbor_center := Vector3.ZERO
		for neighbor_index in (neighbors[index] as Dictionary):
			neighbor_center += points[int(neighbor_index)]
		var neighbor_count := (neighbors[index] as Dictionary).size()
		if neighbor_count < 3 or average_normal.length_squared() < 0.5:
			continue
		neighbor_center /= float(neighbor_count)
		var wear_variation := 0.78 + 0.22 * (_value_noise(points[index] * 2.7, seed) * 0.5 + 0.5)
		var selective_blend := weathering * 0.24 * wear_variation * clampf(0.18 + curvature_values[index] * 2.8, 0.0, 1.0)
		output[index] = points[index].lerp(neighbor_center, selective_blend)
	return output


static func _apply_coherent_roughness(points: Array[Vector3], triangles: Array[Vector3i], recipe: Dictionary, seed: int, anisotropy_axis: int) -> Array[Vector3]:
	var normals: Array[Vector3] = []
	var shortest_edges: Array[float] = []
	normals.resize(points.size())
	shortest_edges.resize(points.size())
	for index in range(points.size()):
		normals[index] = Vector3.ZERO
		shortest_edges[index] = INF
	for triangle in triangles:
		var normal := (points[triangle.y] - points[triangle.x]).cross(points[triangle.z] - points[triangle.x]).normalized()
		normals[triangle.x] += normal
		normals[triangle.y] += normal
		normals[triangle.z] += normal
		for pair in [[triangle.x, triangle.y], [triangle.y, triangle.z], [triangle.z, triangle.x]]:
			var edge_length := points[pair[0]].distance_to(points[pair[1]])
			shortest_edges[pair[0]] = minf(shortest_edges[pair[0]], edge_length)
			shortest_edges[pair[1]] = minf(shortest_edges[pair[1]], edge_length)
	var scale := float(recipe["anisotropy_milli"]) / 1000.0
	var output := points.duplicate()
	for index in range(points.size()):
		var coordinate: Vector3 = points[index]
		coordinate[anisotropy_axis] *= scale
		var broad := _value_noise(coordinate * 1.6, seed)
		var middle := _value_noise(coordinate * 4.7, _derive_noise_seed(seed, 31))
		var fine := _value_noise(coordinate * 10.2, _derive_noise_seed(seed, 73))
		var displacement := broad * float(recipe["macro_roughness_mm"]) / 1000.0
		displacement += middle * float(recipe["meso_roughness_mm"]) / 1000.0
		displacement += fine * float(recipe["fine_roughness_mm"]) / 1000.0
		var configured_amplitude := (float(recipe["macro_roughness_mm"]) + float(recipe["meso_roughness_mm"]) + float(recipe["fine_roughness_mm"])) / 1000.0
		var maximum_safe_amplitude := minf(configured_amplitude, shortest_edges[index] * 0.07)
		displacement = clampf(displacement, -maximum_safe_amplitude, maximum_safe_amplitude)
		var normal: Vector3 = (normals[index] as Vector3).normalized()
		if normal.length_squared() > 0.5:
			output[index] = points[index] + normal * displacement
	return output


static func _value_noise(position: Vector3, seed: int) -> float:
	var cell := Vector3i(floori(position.x), floori(position.y), floori(position.z))
	var fraction := Vector3(position.x - floor(position.x), position.y - floor(position.y), position.z - floor(position.z))
	fraction = Vector3(_smooth(fraction.x), _smooth(fraction.y), _smooth(fraction.z))
	var values: Array[float] = []
	for z in range(2):
		for y in range(2):
			for x in range(2):
				values.append(_lattice_value(cell.x + x, cell.y + y, cell.z + z, seed))
	var x00 := lerpf(values[0], values[1], fraction.x)
	var x10 := lerpf(values[2], values[3], fraction.x)
	var x01 := lerpf(values[4], values[5], fraction.x)
	var x11 := lerpf(values[6], values[7], fraction.x)
	return lerpf(lerpf(x00, x10, fraction.y), lerpf(x01, x11, fraction.y), fraction.z)


static func _lattice_value(x: int, y: int, z: int, seed: int) -> float:
	var value := posmod(seed * 48271 + x * 69621 + y * 104729 + z * 130363 + 15485863, RAND_MOD)
	value = posmod(value * 16807 + 1013904223, RAND_MOD)
	return float(value) / float(RAND_MOD) * 2.0 - 1.0


static func _random_unit(state: int) -> Dictionary:
	var next := state
	var vector := Vector3.ZERO
	for axis in range(3):
		next = _next_random(next)
		vector[axis] = float(next) / float(RAND_MOD) * 2.0 - 1.0
	if vector.length_squared() < 0.08:
		vector = Vector3(0.71, 0.41, 0.57)
	return {"state": next, "vector": vector.normalized()}


static func _random_unit_float(state: int) -> float:
	return float(posmod(state, RAND_MOD)) / float(RAND_MOD)


static func _next_random(state: int) -> int:
	return int((state * 48271 + 1) % RAND_MOD)


static func _random_bit(state: int) -> int:
	return posmod(state, 2)


static func _derive_noise_seed(seed: int, discriminator: int) -> int:
	return posmod(seed * 69621 + discriminator * 48271 + 1, RAND_MOD)


static func _support_distance(normal: Vector3, extents: Vector3) -> float:
	return absf(normal.x) * extents.x + absf(normal.y) * extents.y + absf(normal.z) * extents.z


static func _axis_index(axis: String) -> int:
	match axis:
		"x": return 0
		"y": return 1
		"z": return 2
	return 1


static func _insert_point(points: Array[Vector3], cache: Dictionary, point: Vector3) -> int:
	var key := _point_key(point)
	if cache.has(key):
		return int(cache[key])
	var index := points.size()
	points.append(point)
	cache[key] = index
	return index


static func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 1000000.0), roundi(point.y * 1000000.0), roundi(point.z * 1000000.0)]


static func _append_unique(indices: PackedInt32Array, index: int) -> void:
	if indices.is_empty() or indices[indices.size() - 1] != index:
		indices.append(index)


static func _clean_polygon(indices: PackedInt32Array, points: Array[Vector3]) -> PackedInt32Array:
	var cleaned := PackedInt32Array()
	for index in indices:
		_append_unique(cleaned, index)
	if cleaned.size() > 1 and cleaned[0] == cleaned[cleaned.size() - 1]:
		cleaned.remove_at(cleaned.size() - 1)
	var changed := true
	while changed and cleaned.size() >= 3:
		changed = false
		for offset in range(cleaned.size()):
			var previous: Vector3 = points[cleaned[posmod(offset - 1, cleaned.size())]]
			var current: Vector3 = points[cleaned[offset]]
			var next: Vector3 = points[cleaned[(offset + 1) % cleaned.size()]]
			if (current - previous).cross(next - current).length_squared() <= MIN_AREA_SQUARED:
				cleaned.remove_at(offset)
				changed = true
				break
	return cleaned


static func _midpoint_index(first: int, second: int, points: Array[Vector3], cache: Dictionary) -> int:
	var low := mini(first, second)
	var high := maxi(first, second)
	var key := "%d:%d" % [low, high]
	if cache.has(key):
		return int(cache[key])
	var index := points.size()
	points.append((points[first] + points[second]) * 0.5)
	cache[key] = index
	return index


static func _measure_bounds(points: Array[Vector3]) -> Dictionary:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return {"min": minimum, "max": maximum}


static func _smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
