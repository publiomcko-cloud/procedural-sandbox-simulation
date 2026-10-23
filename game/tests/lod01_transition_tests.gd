extends SceneTree

const Fixture := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const ProductionMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const BenchmarkContract := preload("res://tests/p1_1b_benchmark_contract.gd")
const SEED := 424242
const MIN_LATTICE := Vector3i(-4, 4, -6)
const SEAM_LATTICE := Vector3i(-4, -2, -6)
const ASSERT_TOLERANCE := 0.00001

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("LOD01_TRANSITION_TEST: Godot=%s seed=%d generator=%d" % [Engine.get_version_info().string, SEED, Field.GENERATOR_VERSION])
	_test_global_lattice_and_negative_floor()
	_test_lod1_origin_alignment_guards()
	_test_common_sample_parity()
	_test_transition_topology()
	_test_production_tetra_face_parity()
	_test_adjacent_reference_mesh_seams()
	_test_cave_and_narrow_features()
	_test_ordered_ledger_parity_and_revision_identity()
	_test_matched_lod_references_and_normals()
	_test_snapshot_identity_and_capacity_guards()
	_test_nonfinite_density_rejection()
	_benchmark_transition_fixture()
	if failures == 0:
		print("LOD01_TRANSITION_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("LOD01_TRANSITION_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_global_lattice_and_negative_floor() -> void:
	_check(Fixture.step_for_lod(0) == 0.5 and Fixture.step_for_lod(1) == 1.0, "only the approved LOD 0/1 spacings are available")
	_check(Fixture.step_for_lod(2) < 0.0, "LOD 2 is explicitly unsupported because current chunk Z grouping is non-integral")
	_check(Fixture.lattice_floor(Vector3(-0.25, -1.01, -1.5), 0) == Vector3i(-1, -3, -3), "LOD0 lattice uses mathematical floor for negative positions")
	_check(Fixture.lattice_floor(Vector3(-0.25, -1.01, -1.5), 1) == Vector3i(-1, -2, -2), "LOD1 lattice uses mathematical floor for negative positions")
	var common := Fixture.world_position_for_lattice(Vector3i(-4, 4, -6), 0)
	_check(common == Fixture.world_position_for_lattice(Vector3i(-2, 2, -3), 1), "coincident samples share globally anchored integer lattice positions")
	_check(Fixture.world_position_for_lattice(Vector3i.ZERO, 3).is_finite() == false, "unsupported LOD cannot silently produce a coordinate")
	_check(Fixture.is_lod1_aligned_origin(Vector3i(-4, 4, -6)), "negative and positive even LOD0 lattice indices align to global LOD1")


func _test_lod1_origin_alignment_guards() -> void:
	var invalid_origins: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-3, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	for origin in invalid_origins:
		_check(not Fixture.is_lod1_aligned_origin(origin), "odd signed origin is rejected by the LOD1 alignment predicate: %s" % origin)
		var sample_calls := [0]
		var counter_sampler := func(_point: Vector3) -> float:
			sample_calls[0] = int(sample_calls[0]) + 1
			return 1.0
		var transition := Fixture.build_transition_cell(SEED, origin, [Fixture.FACE_X_NEG], {}, counter_sampler)
		_check(not transition.get("valid", false) and transition.get("reason", "") == "misaligned_lod1_cell_origin", "transition rejects odd signed origin with a deterministic reason")
		var reference := Fixture.build_uniform_reference_cell(SEED, origin, 1, {}, counter_sampler)
		_check_lod1_alignment_reference(reference)
		_check(Fixture.interface_triangles(origin, Fixture.FACE_X_NEG, 1).is_empty(), "coarse public interface helper rejects odd signed origins")
		_check(sample_calls[0] == 0, "misaligned LOD1 requests fail before invoking a density sampler")
		var fine_reference := Fixture.build_uniform_reference_cell(SEED, origin, 0)
		_check(fine_reference.get("valid", false), "LOD0 reference preserves odd fine-lattice origins")
	_check(Fixture.interface_triangles(Vector3i(1, 0, 0), Fixture.FACE_X_NEG, 2).size() == 8, "fine-resolution interface helper permits an odd LOD0 origin")


func _check_lod1_alignment_reference(reference: Dictionary) -> void:
	_check(not reference.get("valid", false) and reference.get("reason", "") == "misaligned_lod1_cell_origin", "LOD1 reference rejects odd signed origin with a deterministic reason")


func _test_common_sample_parity() -> void:
	var checked := 0
	for z in range(-12, 13, 2):
		for y in range(-4, 17, 2):
			for x in range(-16, 17, 2):
				var lod1_index := Vector3i(x / 2, y / 2, z / 2)
				var point0 := Fixture.world_position_for_lattice(Vector3i(x, y, z), 0)
				var point1 := Fixture.world_position_for_lattice(lod1_index, 1)
				_check(point0 == point1, "common LOD sample coordinates are identical")
				var d0 := Fixture.sample_canonical(SEED, point0)
				var d1 := Fixture.sample_canonical(SEED, point1)
				_check(d0 == d1, "common LOD sample evaluates the exact canonical SDF v1 value")
				checked += 1
	_check(checked > 500, "parity covers a broad signed 3D lattice domain")


func _test_transition_topology() -> void:
	var plane := func(point: Vector3) -> float:
		var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
		return (point.x - base.x) + (point.y - base.y) + (point.z - base.z) - 1.37
	var configurations := [
		{"name": "negative_face", "faces": [Fixture.FACE_X_NEG]},
		{"name": "negative_edge", "faces": [Fixture.FACE_X_NEG, Fixture.FACE_Y_NEG]},
		{"name": "negative_corner", "faces": [Fixture.FACE_X_NEG, Fixture.FACE_Y_NEG, Fixture.FACE_Z_NEG]},
		{"name": "positive_corner", "faces": [Fixture.FACE_X_POS, Fixture.FACE_Y_POS, Fixture.FACE_Z_POS]},
	]
	for configuration in configurations:
		var faces: Array[int] = []
		for face_value in configuration["faces"]:
			faces.append(int(face_value))
		var result: Dictionary = Fixture.build_transition_cell(SEED, MIN_LATTICE, faces, {}, plane)
		_check(result.get("valid", false), "%s transition cell builds" % configuration["name"])
		_check(int(result.get("triangle_count", 0)) > 0, "%s transition produces surface triangles" % configuration["name"])
		_check(_all_finite(result.get("vertices", PackedVector3Array())), "%s transition vertices are finite" % configuration["name"])
		_check(_all_unit_normals(result.get("normals", PackedVector3Array())), "%s transition normals are finite and normalized" % configuration["name"])
		_check(_no_degenerate_or_duplicate_triangles(result), "%s transition contains no degenerate or duplicate triangles" % configuration["name"])
		_check(_winding_matches_density(result, plane), "%s triangle winding points toward empty space" % configuration["name"])
		_check(_shared_vertex_normals_are_consistent(result), "%s duplicate seam positions carry identical normals" % configuration["name"])
		_check(_internal_surface_edges_are_paired(result), "%s internal surface edges are paired; exterior fixture boundary is excluded" % configuration["name"])
		print("LOD01_TOPOLOGY: case=%s triangles=%d samples=%d internal_edge_incidence=2" % [configuration["name"], result["triangle_count"], result["sample_count"]])
		for fine_face in faces:
			_check_interface_matches(result, fine_face, 2, plane, "%s fine interface face %d" % [configuration["name"], fine_face])
			_check_interface_matches(result, fine_face ^ 1, 1, plane, "%s coarse interface face %d" % [configuration["name"], fine_face ^ 1])
	var duplicate_faces: Array[int] = [Fixture.FACE_X_NEG, Fixture.FACE_X_NEG]
	_check(not Fixture.build_transition_cell(SEED, MIN_LATTICE, duplicate_faces).get("valid", false), "duplicate face requests fail closed")
	_check(not Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG, Fixture.FACE_X_POS]).get("valid", false), "opposing fine faces in one transition cell fail closed")


func _test_production_tetra_face_parity() -> void:
	for face in range(6):
		for resolution in [1, 2]:
			var actual := _triangle_face_key_set(Fixture.interface_triangles(MIN_LATTICE, face, resolution))
			var expected: Dictionary = {}
			var subdivisions: int = resolution
			var axis := int(face / 2)
			var u_axis := (axis + 1) % 3
			var v_axis := (axis + 2) % 3
			var fixed := float(face % 2)
			for v in range(subdivisions):
				for u in range(subdivisions):
					for source_triangle in _production_cube_face_triangles(axis, int(fixed)):
						var transformed: Array[Vector3] = []
						for source_point in source_triangle:
							var point := Vector3.ZERO
							point[axis] = fixed
							point[u_axis] = float(u) / float(subdivisions) + source_point[u_axis] / float(subdivisions)
							point[v_axis] = float(v) / float(subdivisions) + source_point[v_axis] / float(subdivisions)
							transformed.append(Vector3(MIN_LATTICE) * Fixture.LOD0_STEP + point)
						expected[_triangle_key(transformed)] = true
			_check(actual == expected, "LOD%d interface triangulation matches production marching-tetrahedra face topology (face=%d)" % [1 if resolution == 1 else 0, face])


func _production_cube_face_triangles(axis: int, side: int) -> Array[Array]:
	var result: Array[Array] = []
	for tetra in ProductionMesher.TETRAHEDRA:
		var face_points: Array[Vector3] = []
		for corner_index in tetra:
			var corner: Vector3i = ProductionMesher.CORNERS[corner_index]
			if corner[axis] == side:
				face_points.append(Vector3(corner))
		if face_points.size() == 3:
			result.append(face_points)
	return result


func _triangle_face_key_set(triangles: Array[Array]) -> Dictionary:
	var result: Dictionary = {}
	for triangle in triangles:
		result[_triangle_key(triangle)] = true
	return result


func _triangle_key(triangle: Array) -> String:
	var keys: Array[String] = []
	for point in triangle:
		keys.append(_point_key(point))
	keys.sort()
	return "%s|%s|%s" % [keys[0], keys[1], keys[2]]


func _check_interface_matches(result: Dictionary, face: int, resolution: int, sampler: Callable, label: String) -> void:
	var expected := _reference_interface_segments(face, resolution, sampler)
	var actual := _mesh_interface_segments(result, face)
	print("LOD01_TOPOLOGY_INTERFACE: %s resolution=%d reference_segments=%d transition_segments=%d" % [label, resolution, expected.size(), actual.size()])
	_check(not expected.is_empty(), "%s has a nonempty isosurface contour" % label)
	_check(expected.keys().size() == actual.keys().size(), "%s transition and adjacent LOD have the same contour segment count" % label)
	for key in expected:
		_check(actual.has(key), "%s transition contour exactly matches adjacent LOD triangle edges" % label)


func _reference_interface_segments(face: int, resolution: int, sampler: Callable) -> Dictionary:
	var result: Dictionary = {}
	for triangle in Fixture.interface_triangles(MIN_LATTICE, face, resolution):
		var hits: Array[Vector3] = []
		for edge in range(3):
			var a: Vector3 = triangle[edge]
			var b: Vector3 = triangle[(edge + 1) % 3]
			var da := float(sampler.call(a))
			var db := float(sampler.call(b))
			if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
				hits.append(a.lerp(b, da / (da - db)))
		if hits.size() == 2:
			result[_segment_key(hits[0], hits[1])] = true
	return result


func _mesh_interface_segments(mesh_data: Dictionary, face: int) -> Dictionary:
	var result: Dictionary = {}
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
	var axis := int(face / 2)
	var plane := base[axis] + (0.0 if face % 2 == 0 else Fixture.LOD1_STEP)
	for start in range(0, vertices.size(), 3):
		var triangle := [vertices[start], vertices[start + 1], vertices[start + 2]]
		for edge in range(3):
			var a: Vector3 = triangle[edge]
			var b: Vector3 = triangle[(edge + 1) % 3]
			if absf(a[axis] - plane) <= ASSERT_TOLERANCE and absf(b[axis] - plane) <= ASSERT_TOLERANCE:
				result[_segment_key(a, b)] = true
	return result


func _test_adjacent_reference_mesh_seams() -> void:
	_test_adjacent_reference_aabb_contracts()
	var base := Vector3(SEAM_LATTICE) * Fixture.LOD0_STEP
	var nonlinear_field := func(point: Vector3) -> float:
		var local := point - base
		return 0.38 * local.x + 0.31 * local.y + 0.27 * local.z + 0.18 * local.x * local.y - 0.45
	var configurations := [
		{"name": "face_x_negative", "faces": [Fixture.FACE_X_NEG]},
		{"name": "face_x_positive", "faces": [Fixture.FACE_X_POS]},
		{"name": "face_y_negative", "faces": [Fixture.FACE_Y_NEG]},
		{"name": "face_y_positive", "faces": [Fixture.FACE_Y_POS]},
		{"name": "face_z_negative", "faces": [Fixture.FACE_Z_NEG]},
		{"name": "face_z_positive", "faces": [Fixture.FACE_Z_POS]},
		{"name": "negative_edge", "faces": [Fixture.FACE_X_NEG, Fixture.FACE_Y_NEG]},
		{"name": "mixed_sign_edge", "faces": [Fixture.FACE_X_POS, Fixture.FACE_Y_NEG]},
		{"name": "mixed_sign_corner", "faces": [Fixture.FACE_X_NEG, Fixture.FACE_Y_POS, Fixture.FACE_Z_NEG]},
		{"name": "positive_corner", "faces": [Fixture.FACE_X_POS, Fixture.FACE_Y_POS, Fixture.FACE_Z_POS]},
	]
	for configuration in configurations:
		var faces: Array[int] = []
		for face_value in configuration["faces"]:
			faces.append(int(face_value))
		var transition := Fixture.build_transition_cell(SEED, SEAM_LATTICE, faces, {}, nonlinear_field)
		_check(transition.get("valid", false), "%s transition builds on signed XYZ coordinates with nonlinear samples" % configuration["name"])
		_check(nonlinear_field.call(base) < 0.0 and nonlinear_field.call(base + Vector3.ONE) > 0.0, "%s uses a nontrivial field crossing its signed unit cell" % configuration["name"])
		for fine_face in faces:
			var fine_neighbors := _adjacent_lod0_reference_meshes(SEAM_LATTICE, fine_face, nonlinear_field)
			var fine_neighbor_origin := _adjacent_reference_origin(SEAM_LATTICE, fine_face)
			_check(fine_neighbors.size() == 1, "%s independently builds a neighboring LOD0 reference mesh for face %d" % [configuration["name"], fine_face])
			_check(fine_neighbors[0].get("triangle_count", 0) > 0 and _no_degenerate_or_duplicate_triangles(fine_neighbors[0]), "%s LOD0 reference has nondegenerate triangles" % configuration["name"])
			_assert_adjacent_mesh_seam(transition, fine_neighbors, fine_face, SEAM_LATTICE, [fine_neighbor_origin], 0, base, "%s LOD0 face %d" % [configuration["name"], fine_face])
			var coarse_face: int = fine_face ^ 1
			var coarse_neighbor := _adjacent_lod1_reference_mesh(SEAM_LATTICE, coarse_face, nonlinear_field)
			var coarse_neighbor_origin := _adjacent_reference_origin(SEAM_LATTICE, coarse_face)
			var coarse_neighbors: Array[Dictionary] = [coarse_neighbor]
			_check(coarse_neighbor.get("triangle_count", 0) > 0 and _no_degenerate_or_duplicate_triangles(coarse_neighbor), "%s LOD1 reference has nondegenerate triangles" % configuration["name"])
			_assert_adjacent_mesh_seam(transition, coarse_neighbors, coarse_face, SEAM_LATTICE, [coarse_neighbor_origin], 1, base, "%s LOD1 face %d" % [configuration["name"], coarse_face])


func _test_adjacent_reference_aabb_contracts() -> void:
	var base := Vector3(SEAM_LATTICE) * Fixture.LOD0_STEP
	var transition_bounds := _unit_domain_aabb(SEAM_LATTICE)
	# Reproduce the reviewed defect before checking corrected placements: one
	# LOD0 index is only 0.5 world units, so the full-unit reference overlaps.
	var bad_origin := SEAM_LATTICE
	bad_origin.x -= 1
	var bad_bounds := _unit_domain_aabb(bad_origin)
	_check(transition_bounds["min"].x == -2.0 and transition_bounds["max"].x == -1.0, "reproduction transition AABB is exactly x=[-2,-1]")
	_check(bad_bounds["min"].x == -2.5 and bad_bounds["max"].x == -1.5, "reviewed -1 LOD0-index neighbor AABB is exactly x=[-2.5,-1.5]")
	_check(bad_bounds["max"].x > transition_bounds["min"].x, "reviewed -1 offset reproduces 0.5-unit interior overlap")
	var bad_spatial := _adjacency_aabb_checks(transition_bounds, bad_bounds, Fixture.FACE_X_NEG)
	_check(not bad_spatial["touches_requested_plane"] and not bad_spatial["interiors_disjoint"], "deliberately incorrect -1 offset fails the independent spatial adjacency contract")

	for lod in [0, 1]:
		for face in range(6):
			var neighbor_origin := _adjacent_reference_origin(SEAM_LATTICE, face)
			var neighbor_bounds := _unit_domain_aabb(neighbor_origin)
			var spatial := _adjacency_aabb_checks(transition_bounds, neighbor_bounds, face)
			_check(spatial["touches_requested_plane"], "LOD%d reference face %d touches the requested external boundary plane exactly" % [lod, face])
			_check(spatial["interiors_disjoint"], "LOD%d reference face %d has no interior overlap with transition domain" % [lod, face])
			_check(spatial["tangent_ranges_match"], "LOD%d reference face %d has identical ranges on both tangent axes" % [lod, face])
			var axis := int(face / 2)
			var expected_plane := base[axis] + (0.0 if face % 2 == 0 else Fixture.LOD1_STEP)
			_check(neighbor_bounds["max"][axis] == expected_plane if face % 2 == 0 else neighbor_bounds["min"][axis] == expected_plane, "LOD%d reference face %d uses the exact signed-world contact coordinate %.3f" % [lod, face, expected_plane])
			_check(spatial["neighbor_min"].is_finite() and spatial["neighbor_max"].is_finite(), "LOD%d reference face %d has finite signed AABB coordinates" % [lod, face])

	var corrected_origin := _adjacent_reference_origin(SEAM_LATTICE, Fixture.FACE_X_NEG)
	var corrected_bounds := _unit_domain_aabb(corrected_origin)
	_check(corrected_origin.x == SEAM_LATTICE.x - 2 and corrected_bounds["max"].x == transition_bounds["min"].x, "corrected negative X neighbor shifts -2 indices and touches at x=-2")


func _unit_domain_aabb(origin: Vector3i) -> Dictionary:
	var minimum := Vector3(origin) * Fixture.LOD0_STEP
	return {"min": minimum, "max": minimum + Vector3.ONE}


func _adjacent_reference_origin(origin: Vector3i, face: int) -> Vector3i:
	var neighbor_origin := origin
	var axis := int(face / 2)
	neighbor_origin[axis] += -2 if face % 2 == 0 else 2
	return neighbor_origin


func _adjacency_aabb_checks(transition: Dictionary, neighbor: Dictionary, face: int) -> Dictionary:
	var axis := int(face / 2)
	var negative := face % 2 == 0
	var transition_min: Vector3 = transition["min"]
	var transition_max: Vector3 = transition["max"]
	var neighbor_min: Vector3 = neighbor["min"]
	var neighbor_max: Vector3 = neighbor["max"]
	var boundary_matches := neighbor_max[axis] == transition_min[axis] if negative else neighbor_min[axis] == transition_max[axis]
	var disjoint := neighbor_max[axis] <= transition_min[axis] if negative else neighbor_min[axis] >= transition_max[axis]
	var tangents_match := true
	for tangent_axis in range(3):
		if tangent_axis == axis:
			continue
		if neighbor_min[tangent_axis] != transition_min[tangent_axis] or neighbor_max[tangent_axis] != transition_max[tangent_axis]:
			tangents_match = false
	return {
		"touches_requested_plane": boundary_matches,
		"interiors_disjoint": disjoint,
		"tangent_ranges_match": tangents_match,
		"neighbor_min": neighbor_min,
		"neighbor_max": neighbor_max,
	}


func _adjacent_lod0_reference_meshes(origin: Vector3i, face: int, sampler: Callable) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var neighbor_origin := _adjacent_reference_origin(origin, face)
	result.append(Fixture.build_uniform_reference_cell(SEED, neighbor_origin, 0, {}, sampler))
	return result


func _adjacent_lod1_reference_mesh(origin: Vector3i, face: int, sampler: Callable) -> Dictionary:
	var neighbor_origin := _adjacent_reference_origin(origin, face)
	return Fixture.build_uniform_reference_cell(SEED, neighbor_origin, 1, {}, sampler)


func _assert_adjacent_mesh_seam(transition: Dictionary, neighbors: Array[Dictionary], face: int, transition_origin: Vector3i, neighbor_origins: Array[Vector3i], neighbor_lod: int, base: Vector3, label: String) -> void:
	_check(neighbor_lod == 0 or neighbor_lod == 1, "%s reference builder uses a supported LOD level" % label)
	_check(neighbors.size() == neighbor_origins.size(), "%s has one declared physical neighbor origin per independently built mesh" % label)
	var transition_bounds := _unit_domain_aabb(transition_origin)
	for index in range(mini(neighbors.size(), neighbor_origins.size())):
		var neighbor_bounds := _unit_domain_aabb(neighbor_origins[index])
		var spatial := _adjacency_aabb_checks(transition_bounds, neighbor_bounds, face)
		_check(spatial["touches_requested_plane"], "%s neighbor and transition share the requested external plane before contour comparison" % label)
		_check(spatial["interiors_disjoint"], "%s neighbor and transition interiors are disjoint before contour comparison" % label)
		_check(spatial["tangent_ranges_match"], "%s neighbor and transition have the same interface ranges before contour comparison" % label)
	for neighbor in neighbors:
		_check(neighbor.get("valid", false), "%s adjacent uniform reference mesh builds independently" % label)
	var axis := int(face / 2)
	var plane := base[axis] + (0.0 if face % 2 == 0 else Fixture.LOD1_STEP)
	var transition_meshes: Array[Dictionary] = [transition]
	var actual := _collect_boundary_contours(transition_meshes, axis, plane)
	var expected := _collect_boundary_contours(neighbors, axis, plane)
	if neighbor_lod == 0:
		var actual_contract := BenchmarkContract.boundary_contour(transition, axis, plane, 0.00001, 0.000001)
		var expected_contract := BenchmarkContract.boundary_contour(neighbors[0], axis, plane, 0.00001, 0.000001)
		_check(actual_contract.get("valid", false), "%s transition contour passes the independent R7 precision and T-junction oracle" % label)
		_check(expected_contract.get("valid", false), "%s independent LOD0 contour passes the independent R7 precision and T-junction oracle" % label)
	_check(not expected["segments"].is_empty(), "%s adjacent mesh produces a nonempty boundary contour" % label)
	_check(bool(actual["boundary_geometry_valid"]) and bool(expected["boundary_geometry_valid"]), "%s interface has no zero-length or degenerate boundary segments" % label)
	_check(actual["segments"] == expected["segments"], "%s actual transition contour equals independently meshed neighboring cells" % label)
	_check(_contours_have_no_t_junctions(actual["segment_points"]), "%s transition contour has no endpoint T-junctions" % label)
	_check(_contours_have_no_t_junctions(expected["segment_points"]), "%s independently generated neighbor contour has no endpoint T-junctions" % label)
	_check(bool(actual["normals_valid"]) and bool(expected["normals_valid"]), "%s boundary vertices have internally consistent normals" % label)
	_check(actual["normals"].keys().size() == expected["normals"].keys().size(), "%s reference and transition contour have the same normal-bearing vertices" % label)
	for point_key in expected["normals"]:
		_check(actual["normals"].has(point_key), "%s transition contains neighbor contour vertex %s" % [label, point_key])
		if actual["normals"].has(point_key):
			var actual_normal: Vector3 = actual["normals"][point_key]
			var expected_normal: Vector3 = expected["normals"][point_key]
			_check(actual_normal.distance_to(expected_normal) <= 0.000001, "%s shared boundary normal is identical within tolerance" % label)


func _collect_boundary_contours(meshes: Array[Dictionary], axis: int, plane: float) -> Dictionary:
	var segments: Dictionary = {}
	var segment_points: Dictionary = {}
	var normals: Dictionary = {}
	var normals_valid := true
	var boundary_geometry_valid := true
	for mesh_data in meshes:
		if not mesh_data.get("valid", false):
			normals_valid = false
			continue
		var vertices: PackedVector3Array = mesh_data["vertices"]
		var mesh_normals: PackedVector3Array = mesh_data["normals"]
		for triangle_start in range(0, vertices.size(), 3):
			for edge in range(3):
				var a_index := triangle_start + edge
				var b_index := triangle_start + (edge + 1) % 3
				var a: Vector3 = vertices[a_index]
				var b: Vector3 = vertices[b_index]
				if absf(a[axis] - plane) > ASSERT_TOLERANCE or absf(b[axis] - plane) > ASSERT_TOLERANCE:
					continue
				if a.distance_squared_to(b) <= ASSERT_TOLERANCE * ASSERT_TOLERANCE:
					boundary_geometry_valid = false
					continue
				var segment_key := _segment_key(a, b)
				segments[segment_key] = true
				segment_points[segment_key] = [a, b]
				for endpoint in [[a, mesh_normals[a_index]], [b, mesh_normals[b_index]]]:
					var point: Vector3 = endpoint[0]
					var normal: Vector3 = endpoint[1]
					var key := _point_key(point)
					if normals.has(key):
						var existing_normal: Vector3 = normals[key]
						if existing_normal.distance_to(normal) > 0.000001:
							normals_valid = false
					normals[key] = normal
	return {"segments": segments, "segment_points": segment_points, "normals": normals, "normals_valid": normals_valid, "boundary_geometry_valid": boundary_geometry_valid}


func _contours_have_no_t_junctions(segment_points: Dictionary) -> bool:
	var points: Dictionary = {}
	for endpoints in segment_points.values():
		points[_point_key(endpoints[0])] = endpoints[0]
		points[_point_key(endpoints[1])] = endpoints[1]
	for endpoints in segment_points.values():
		var a: Vector3 = endpoints[0]
		var b: Vector3 = endpoints[1]
		var ab := b - a
		var length_squared := ab.length_squared()
		if length_squared <= ASSERT_TOLERANCE * ASSERT_TOLERANCE:
			return false
		for point_variant in points.values():
			var point: Vector3 = point_variant
			if point.distance_to(a) <= ASSERT_TOLERANCE or point.distance_to(b) <= ASSERT_TOLERANCE:
				continue
			var t := (point - a).dot(ab) / length_squared
			if t > ASSERT_TOLERANCE and t < 1.0 - ASSERT_TOLERANCE:
				if point.distance_to(a + ab * t) <= ASSERT_TOLERANCE:
					return false
	return true


func _test_cave_and_narrow_features() -> void:
	var cave_sampler := func(point: Vector3) -> float:
		var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
		var local := point - base
		var cave_tube := Vector2(local.y - 0.5, local.z - 0.5).length() - 0.18
		return minf(0.72 - local.y, cave_tube)
	var cave_result: Dictionary = Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], {}, cave_sampler)
	_check(cave_result.get("valid", false) and cave_result["triangle_count"] > 0, "cave-like tube and terrain ceiling generate a deterministic transition surface")
	_check(_no_degenerate_or_duplicate_triangles(cave_result), "cave-like transition has no degenerate or duplicate faces")
	var narrow_sampler := func(point: Vector3) -> float:
		var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
		return 0.02 - absf((point.y - base.y) - 0.25)
	var narrow_a: Dictionary = Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], {}, narrow_sampler)
	var narrow_b: Dictionary = Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], {}, narrow_sampler)
	_check(_same_triangle_positions(narrow_a, narrow_b), "sub-grid narrow surface behavior is deterministic")
	_check(narrow_a["triangle_count"] == 0, "a 0.04-unit feature may disappear at LOD lattice samples and is not claimed preserved")
	var canonical := Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG])
	_check(canonical.get("valid", false), "canonical SDF v1 transition fixture builds independently of the production scene")
	var cave_lattice := Vector3i(-32, 2, 10) # world box x=[-16,-15], y=[1,2], z=[5,6]
	var canonical_cave := Fixture.build_transition_cell(SEED, cave_lattice, [Fixture.FACE_X_NEG])
	_check(canonical_cave.get("valid", false) and canonical_cave["triangle_count"] > 0, "canonical versioned SDF tunnel wall crosses the signed-world LOD transition fixture")


func _test_ordered_ledger_parity_and_revision_identity() -> void:
	var ledger: RefCounted = Brush.new(SEED, Field.GENERATOR_VERSION)
	var snapshots: Dictionary = {0: ledger.get_meshing_snapshot()}
	var counts := [1, 32, 128, 256]
	var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
	for index in range(256):
		var center := base + Vector3(0.45 + float(index % 3) * 0.07, 0.43 + float(index % 5) * 0.03, 0.48 + float(index % 4) * 0.04)
		var mode: int = Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
		_check(ledger.add_sphere(mode, center, 0.45), "ordered brush operation %d is accepted by unchanged canonical ledger" % index)
		if counts.has(index + 1):
			snapshots[index + 1] = ledger.get_meshing_snapshot()
	for count in counts:
		var snapshot: Dictionary = snapshots[count]
		_check(snapshot["centers"].size() == count, "history snapshot includes exactly %d operations" % count)
		var probe_points := [base + Vector3(0.25, 0.25, 0.25), base + Vector3(0.5, 0.5, 0.5), base + Vector3(0.75, 0.25, 0.75)]
		for point in probe_points:
			var mapped: Dictionary = Spatial.world_to_region_local(point)
			var expected := Brush.sample_density_snapshot(SEED, mapped["region_key"], mapped["local_position"], false, snapshot)
			var actual := Fixture.sample_canonical(SEED, point, snapshot)
			_check(expected == actual, "%d-op fixture replays the exact ordered canonical ledger" % count)
		var built: Dictionary = Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], snapshot)
		_check(built.get("valid", false), "%d-op transition build accepts immutable snapshot" % count)
		_check(Fixture.result_matches_request(built, SEED, Field.GENERATOR_VERSION, count, MIN_LATTICE, [Fixture.FACE_X_NEG]), "%d-op transition result carries its immutable request identity" % count)
		_check(not Fixture.result_matches_request(built, SEED, Field.GENERATOR_VERSION, count + 1, MIN_LATTICE, [Fixture.FACE_X_NEG]), "%d-op result is rejected when ledger revision becomes obsolete" % count)
	_check(ledger.get_edit_count() == 256 and ledger.get_last_sequence() == 255, "fixture leaves the canonical 256-command ordered ledger intact")
	_check(not ledger.add_sphere(Brush.Mode.CARVE, base, 0.45), "fixture does not weaken canonical ledger capacity")
	var final_snapshot: Dictionary = ledger.get_meshing_snapshot()
	var edited_transition: Dictionary = Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], final_snapshot)
	_check(_interface_normals_match_canonical(edited_transition, final_snapshot), "shared LOD seam normals use the same canonical SDF gradient and fixed physical epsilon")
	_test_distributed_256_history()


func _test_distributed_256_history() -> void:
	var region_keys := [
		Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
		Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	var ledger: RefCounted = Brush.new(SEED, Field.GENERATOR_VERSION)
	for index in range(256):
		var key: Vector2i = region_keys[index % region_keys.size()]
		var origin := Spatial.region_origin_world(key)
		var local_center := Vector3(8.0, 3.0, 6.0)
		if key == Vector2i(-1, -1):
			local_center = Vector3(14.0, 2.5, 9.0)
		var mode: int = Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
		_check(ledger.add_sphere(mode, origin + local_center, 0.45), "distributed 256-op command %d is accepted" % index)
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	_check(ledger.get_edit_count() == 256 and ledger.get_last_sequence() == 255, "distributed ledger preserves all 256 commands and global order")
	var probes := [Vector3(-2.0, 2.25, -3.0), Vector3(-1.5, 2.5, -2.5), Vector3(-1.0, 2.75, -2.0)]
	for point in probes:
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var expected := Brush.sample_density_snapshot(SEED, mapped["region_key"], mapped["local_position"], false, snapshot)
		_check(expected == Fixture.sample_canonical(SEED, point, snapshot), "distributed history gives identical canonical LOD sample values")
	var mesh: Dictionary = Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], snapshot)
	_check(mesh["valid"] and mesh["ledger_revision"] == 256, "distributed history remains an input to the same transition data contract")


func _test_matched_lod_references_and_normals() -> void:
	var lod0 := Fixture.build_uniform_reference_cell(SEED, MIN_LATTICE, 0)
	var lod1 := Fixture.build_uniform_reference_cell(SEED, MIN_LATTICE, 1)
	var transition := Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG])
	_check(lod0["valid"] and lod1["valid"] and transition["valid"], "matched LOD0, LOD1 and transition reference fixtures build")
	_check(lod0["triangle_count"] >= lod1["triangle_count"], "LOD0 reference uses at least the coarse cell resolution without altering the SDF")
	_check(_all_finite(lod0["vertices"]) and _all_finite(lod1["vertices"]), "both matched reference meshes have finite positions")
	var residual0 := _max_abs_density_residual(lod0)
	var residual1 := _max_abs_density_residual(lod1)
	var residual_transition := _max_abs_density_residual(transition)
	print("LOD01_GEOMETRY: mode=exploratory seed=%d max_abs_canonical_density_at_surface_vertices lod0=%.8f lod1=%.8f transition=%.8f triangles=%d/%d/%d" % [SEED, residual0, residual1, residual_transition, lod0["triangle_count"], lod1["triangle_count"], transition["triangle_count"]])
	_check(is_finite(residual0) and is_finite(residual1) and is_finite(residual_transition), "geometric residual measurements are finite; no unapproved tolerance is asserted")
	_check(_interface_normals_match_canonical(transition, {}), "unmodified seam normals equal canonical SDF gradient samples")


func _test_snapshot_identity_and_capacity_guards() -> void:
	var ledger: RefCounted = Brush.new(SEED, Field.GENERATOR_VERSION)
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	var wrong_seed := snapshot.duplicate(true)
	wrong_seed["world_seed"] = SEED + 1
	_check(not Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], wrong_seed).get("valid", false), "fixture rejects a ledger snapshot from a different world seed")
	var wrong_version := snapshot.duplicate(true)
	wrong_version["generator_version"] = Field.GENERATOR_VERSION + 1
	_check(not Fixture.build_uniform_reference_cell(SEED, MIN_LATTICE, 0, wrong_version).get("valid", false), "fixture rejects an unsupported generator version")
	var populated_ledger: RefCounted = Brush.new(SEED, Field.GENERATOR_VERSION)
	_check(populated_ledger.add_sphere(Brush.Mode.CARVE, Vector3(0.0, 1.0, 0.0), Brush.MIN_RADIUS), "canonical ledger accepts fixture snapshot seed operation")
	var valid_command_snapshot: Dictionary = populated_ledger.get_meshing_snapshot()
	var invalid_mode := valid_command_snapshot.duplicate(true)
	var invalid_modes: PackedByteArray = invalid_mode["modes"]
	invalid_modes[0] = 2
	invalid_mode["modes"] = invalid_modes
	_expect_snapshot_failure(invalid_mode, "unsupported_snapshot_mode", "mode byte 2 is not silently reinterpreted as FILL")
	var nan_center := valid_command_snapshot.duplicate(true)
	var nan_centers: PackedVector3Array = nan_center["centers"]
	nan_centers[0] = Vector3(NAN, 0.0, 0.0)
	nan_center["centers"] = nan_centers
	_expect_snapshot_failure(nan_center, "invalid_snapshot_center", "snapshot rejects a nonfinite center")
	var infinite_center := valid_command_snapshot.duplicate(true)
	var infinite_centers: PackedVector3Array = infinite_center["centers"]
	infinite_centers[0] = Vector3(0.0, INF, 0.0)
	infinite_center["centers"] = infinite_centers
	_expect_snapshot_failure(infinite_center, "invalid_snapshot_center", "snapshot rejects an infinite center")
	var unbounded_center := valid_command_snapshot.duplicate(true)
	var unbounded_centers: PackedVector3Array = unbounded_center["centers"]
	unbounded_centers[0] = Vector3(Brush.MAX_ABS_WORLD_COORDINATE + 1.0, 0.0, 0.0)
	unbounded_center["centers"] = unbounded_centers
	_expect_snapshot_failure(unbounded_center, "invalid_snapshot_center", "snapshot rejects centers outside canonical world bounds")
	var nan_radius := valid_command_snapshot.duplicate(true)
	var nan_radii: PackedFloat64Array = nan_radius["radii"]
	nan_radii[0] = NAN
	nan_radius["radii"] = nan_radii
	_expect_snapshot_failure(nan_radius, "invalid_snapshot_radius", "snapshot rejects a nonfinite radius")
	var infinite_radius := valid_command_snapshot.duplicate(true)
	var infinite_radii: PackedFloat64Array = infinite_radius["radii"]
	infinite_radii[0] = INF
	infinite_radius["radii"] = infinite_radii
	_expect_snapshot_failure(infinite_radius, "invalid_snapshot_radius", "snapshot rejects an infinite radius")
	var undersized_radius := valid_command_snapshot.duplicate(true)
	var undersized_radii: PackedFloat64Array = undersized_radius["radii"]
	undersized_radii[0] = Brush.MIN_RADIUS - 0.01
	undersized_radius["radii"] = undersized_radii
	_expect_snapshot_failure(undersized_radius, "invalid_snapshot_radius", "snapshot rejects radii below the canonical bound")
	var oversized_radius := valid_command_snapshot.duplicate(true)
	var oversized_radii: PackedFloat64Array = oversized_radius["radii"]
	oversized_radii[0] = Brush.MAX_RADIUS + 0.01
	oversized_radius["radii"] = oversized_radii
	_expect_snapshot_failure(oversized_radius, "invalid_snapshot_radius", "snapshot rejects radii above the canonical bound")
	var negative_revision := valid_command_snapshot.duplicate(true)
	negative_revision["revision"] = -1
	_expect_snapshot_failure(negative_revision, "invalid_snapshot_revision", "snapshot rejects negative revisions")
	var malformed_revision := valid_command_snapshot.duplicate(true)
	malformed_revision["revision"] = "1"
	_expect_snapshot_failure(malformed_revision, "malformed_snapshot_metadata", "snapshot rejects non-integer revision metadata")
	var malformed_seed := valid_command_snapshot.duplicate(true)
	malformed_seed["world_seed"] = str(SEED)
	_expect_snapshot_failure(malformed_seed, "malformed_snapshot_metadata", "snapshot rejects non-integer world-seed metadata")
	var missing_revision := valid_command_snapshot.duplicate(true)
	missing_revision.erase("revision")
	_expect_snapshot_failure(missing_revision, "malformed_snapshot_metadata", "snapshot rejects missing revision metadata")
	var impossible_revision := valid_command_snapshot.duplicate(true)
	impossible_revision["revision"] = 0
	_expect_snapshot_failure(impossible_revision, "invalid_snapshot_revision", "revision cannot precede the number of retained commands")
	var mismatched_lengths := valid_command_snapshot.duplicate(true)
	mismatched_lengths["radii"] = PackedFloat64Array()
	_expect_snapshot_failure(mismatched_lengths, "invalid_snapshot_command_count", "snapshot rejects mismatched packed-array lengths")
	var unbounded := snapshot.duplicate(true)
	var excessive_centers := PackedVector3Array()
	var excessive_radii := PackedFloat64Array()
	var excessive_modes := PackedByteArray()
	for _index in range(Brush.MAX_EDITS + 1):
		excessive_centers.append(Vector3.ZERO)
		excessive_radii.append(0.5)
		excessive_modes.append(Brush.Mode.CARVE)
	unbounded["centers"] = excessive_centers
	unbounded["radii"] = excessive_radii
	unbounded["modes"] = excessive_modes
	_expect_snapshot_failure(unbounded, "invalid_snapshot_command_count", "fixture enforces canonical ledger capacity without expanding authority")


func _expect_snapshot_failure(snapshot: Dictionary, expected_reason: String, label: String) -> void:
	var result := Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], snapshot)
	_check(not result.get("valid", false) and result.get("reason", "") == expected_reason, label)


func _test_nonfinite_density_rejection() -> void:
	var nan_sampler := func(_point: Vector3) -> float:
		return NAN
	var nan_transition := Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], {}, nan_sampler)
	_check(not nan_transition.get("valid", false) and nan_transition.get("reason", "") == "non_finite_sample_density", "transition rejects NaN density with a deterministic reason")
	var infinity_sampler := func(_point: Vector3) -> float:
		return INF
	var infinity_reference := Fixture.build_uniform_reference_cell(SEED, MIN_LATTICE, 0, {}, infinity_sampler)
	_check(not infinity_reference.get("valid", false) and infinity_reference.get("reason", "") == "non_finite_sample_density", "uniform reference rejects infinite density with a deterministic reason")
	var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
	var normal_only_infinity_sampler := func(point: Vector3) -> float:
		var scaled := point * 2.0
		if absf(scaled.x - roundf(scaled.x)) > 0.0001 or absf(scaled.y - roundf(scaled.y)) > 0.0001 or absf(scaled.z - roundf(scaled.z)) > 0.0001:
			return INF
		var local := point - base
		return local.x + local.y + local.z - 1.37
	var normal_failure := Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], {}, normal_only_infinity_sampler)
	_check(not normal_failure.get("valid", false) and normal_failure.get("reason", "") == "non_finite_sample_density", "nonfinite normal-probe density cannot leave a valid partial mesh")
	_check(not normal_failure.has("timings_usec") and not normal_failure.has("vertices"), "failed nonfinite build exposes no accepted mesh or timing payload")


func _benchmark_transition_fixture() -> void:
	print("LOD01_BENCH: mode=exploratory headless; resolution=CPU fixture only; warmup=2 samples=12 workers=0 publication=ArrayMesh; CPU=local host, GPU/frame metrics unavailable")
	var ledger: RefCounted = Brush.new(SEED, Field.GENERATOR_VERSION)
	var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
	var operation_counts := [0, 1, 32, 128, 256]
	for count in operation_counts:
		while ledger.get_edit_count() < count:
			var index: int = ledger.get_edit_count()
			var mode: int = Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
			ledger.add_sphere(mode, base + Vector3(0.5, 0.5, 0.5), 0.45)
		var snapshot: Dictionary = ledger.get_meshing_snapshot()
		var transition_builder := func() -> Dictionary:
			return Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], snapshot)
		var lod0_builder := func() -> Dictionary:
			return Fixture.build_uniform_reference_cell(SEED, MIN_LATTICE, 0, snapshot)
		_measure_benchmark("transition", count, transition_builder)
		_measure_benchmark("lod0_reference", count, lod0_builder)


func _measure_benchmark(kind: String, operation_count: int, builder: Callable) -> void:
	var times: Array[int] = []
	var transition_geometry_sum := 0
	var sample_sum := 0
	var triangulation_sum := 0
	var normal_sum := 0
	var publication_sum := 0
	var last_result: Dictionary = {}
	for run in range(14):
		var started := Time.get_ticks_usec()
		last_result = builder.call()
		var total := Time.get_ticks_usec() - started
		if run >= 2:
			times.append(total)
			var timing: Dictionary = last_result["timings_usec"]
			transition_geometry_sum += timing["transition_geometry"]
			sample_sum += timing["sdf_ledger_sampling"]
			triangulation_sum += timing["lod_mesh_triangulation"]
			normal_sum += timing["normal_computation"]
			var mesh := ArrayMesh.new()
			if last_result["triangle_count"] > 0:
				var arrays: Array = []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = last_result["vertices"]
				arrays[Mesh.ARRAY_NORMAL] = last_result["normals"]
				var publish_started := Time.get_ticks_usec()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				publication_sum += Time.get_ticks_usec() - publish_started
			mesh = null
	_check(last_result.get("valid", false), "%s benchmark fixture completes for %d operations" % [kind, operation_count])
	var sorted := times.duplicate()
	sorted.sort()
	print("LOD01_BENCH_RESULT: kind=%s ops=%d n=%d p50_us=%d p95_us=%d p99_us=%d max_us=%d transition_geometry_avg_us=%d sample_avg_us=%d triangulation_avg_us=%d normals_avg_us=%d ArrayMesh_publish_avg_us=%d cpu_array_bytes_est=%d triangles=%d" % [
		kind, operation_count, sorted.size(), _percentile(sorted, 0.50), _percentile(sorted, 0.95), _percentile(sorted, 0.99), sorted[-1],
		transition_geometry_sum / sorted.size(), sample_sum / sorted.size(), triangulation_sum / sorted.size(), normal_sum / sorted.size(), publication_sum / sorted.size(),
		int(last_result.get("cpu_array_bytes", 0)), int(last_result.get("triangle_count", 0))
	])


func _no_degenerate_or_duplicate_triangles(result: Dictionary) -> bool:
	var vertices: PackedVector3Array = result["vertices"]
	var seen: Dictionary = {}
	for start in range(0, vertices.size(), 3):
		var a: Vector3 = vertices[start]
		var b: Vector3 = vertices[start + 1]
		var c: Vector3 = vertices[start + 2]
		if (b - a).cross(c - a).length_squared() <= 1.0e-12:
			return false
		var keys := [_point_key(a), _point_key(b), _point_key(c)]
		keys.sort()
		var triangle_key := "%s|%s|%s" % [keys[0], keys[1], keys[2]]
		if seen.has(triangle_key):
			return false
		seen[triangle_key] = true
	return true


func _interface_normals_match_canonical(result: Dictionary, snapshot: Dictionary) -> bool:
	var vertices: PackedVector3Array = result["vertices"]
	var normals: PackedVector3Array = result["normals"]
	var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
	for start in range(0, vertices.size(), 3):
		for offset in range(3):
			var point: Vector3 = vertices[start + offset]
			var on_interface := absf(point.x - base.x) <= ASSERT_TOLERANCE or absf(point.x - (base.x + 1.0)) <= ASSERT_TOLERANCE
			if on_interface:
				var expected := Fixture.canonical_outward_normal(SEED, point, snapshot)
				if expected.length_squared() > 1.0e-12 and normals[start + offset] != expected:
					return false
	return true


func _shared_vertex_normals_are_consistent(result: Dictionary) -> bool:
	var vertices: PackedVector3Array = result["vertices"]
	var normals: PackedVector3Array = result["normals"]
	var seen: Dictionary = {}
	for index in range(vertices.size()):
		var key := _point_key(vertices[index])
		var normal: Vector3 = normals[index]
		if seen.has(key) and normal != seen[key]:
			return false
		seen[key] = normal
	return true


func _max_abs_density_residual(result: Dictionary) -> float:
	var maximum := 0.0
	var vertices: PackedVector3Array = result["vertices"]
	for point in vertices:
		maximum = maxf(maximum, absf(Fixture.sample_canonical(SEED, point)))
	return maximum


func _internal_surface_edges_are_paired(result: Dictionary) -> bool:
	var vertices: PackedVector3Array = result["vertices"]
	var counts: Dictionary = {}
	var boundary: Dictionary = {}
	var base := Vector3(MIN_LATTICE) * Fixture.LOD0_STEP
	for start in range(0, vertices.size(), 3):
		var tri := [vertices[start], vertices[start + 1], vertices[start + 2]]
		for edge in range(3):
			var a: Vector3 = tri[edge]
			var b: Vector3 = tri[(edge + 1) % 3]
			var key := _segment_key(a, b)
			counts[key] = int(counts.get(key, 0)) + 1
			if _on_same_outer_plane(a, b, base):
				boundary[key] = true
	for key in counts:
		var count := int(counts[key])
		if boundary.has(key):
			if count > 2:
				return false
		elif count != 2:
			return false
	return true


func _on_same_outer_plane(a: Vector3, b: Vector3, base: Vector3) -> bool:
	for axis in range(3):
		if absf(a[axis] - base[axis]) <= ASSERT_TOLERANCE and absf(b[axis] - base[axis]) <= ASSERT_TOLERANCE:
			return true
		if absf(a[axis] - (base[axis] + 1.0)) <= ASSERT_TOLERANCE and absf(b[axis] - (base[axis] + 1.0)) <= ASSERT_TOLERANCE:
			return true
	return false


func _winding_matches_density(result: Dictionary, sampler: Callable) -> bool:
	var vertices: PackedVector3Array = result["vertices"]
	var normals: PackedVector3Array = result["normals"]
	for start in range(0, vertices.size(), 3):
		var a: Vector3 = vertices[start]
		var b: Vector3 = vertices[start + 1]
		var c: Vector3 = vertices[start + 2]
		var geometric := (b - a).cross(c - a).normalized()
		var normal: Vector3 = normals[start]
		if geometric.dot(normal) <= 0.0:
			return false
		var center := (a + b + c) / 3.0
		var sample_step := 0.0005
		var gradient := Vector3(
			float(sampler.call(center + Vector3.RIGHT * sample_step)) - float(sampler.call(center - Vector3.RIGHT * sample_step)),
			float(sampler.call(center + Vector3.UP * sample_step)) - float(sampler.call(center - Vector3.UP * sample_step)),
			float(sampler.call(center + Vector3.BACK * sample_step)) - float(sampler.call(center - Vector3.BACK * sample_step))
		)
		if gradient.length_squared() > 1.0e-12 and geometric.dot(-gradient.normalized()) <= 0.0:
			return false
	return true


func _same_triangle_positions(a: Dictionary, b: Dictionary) -> bool:
	return a.get("triangle_count", -1) == b.get("triangle_count", -2) \
		and a.get("vertices", PackedVector3Array()) == b.get("vertices", PackedVector3Array())


func _all_finite(values: PackedVector3Array) -> bool:
	for value in values:
		if not value.is_finite():
			return false
	return true


func _all_unit_normals(values: PackedVector3Array) -> bool:
	for value in values:
		if not value.is_finite() or absf(value.length() - 1.0) > 0.0001:
			return false
	return true


func _segment_key(a: Vector3, b: Vector3) -> String:
	var ak := _point_key(a)
	var bk := _point_key(b)
	return "%s|%s" % [ak, bk] if ak < bk else "%s|%s" % [bk, ak]


func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 100000.0), roundi(point.y * 100000.0), roundi(point.z * 100000.0)]


func _percentile(sorted_values: Array[int], percentile: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := clampi(int(ceil(float(sorted_values.size()) * percentile)) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("LOD01_ASSERT_FAIL: " + message)
