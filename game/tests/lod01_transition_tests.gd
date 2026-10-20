extends SceneTree

const Fixture := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const ProductionMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const SEED := 424242
const MIN_LATTICE := Vector3i(-4, 4, -6)
const ASSERT_TOLERANCE := 0.00001

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("LOD01_TRANSITION_TEST: Godot=%s seed=%d generator=%d" % [Engine.get_version_info().string, SEED, Field.GENERATOR_VERSION])
	_test_global_lattice_and_negative_floor()
	_test_common_sample_parity()
	_test_transition_topology()
	_test_production_tetra_face_parity()
	_test_cave_and_narrow_features()
	_test_ordered_ledger_parity_and_revision_identity()
	_test_matched_lod_references_and_normals()
	_test_snapshot_identity_and_capacity_guards()
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
	_check(not Fixture.build_transition_cell(SEED, MIN_LATTICE, [Fixture.FACE_X_NEG], unbounded).get("valid", false), "fixture enforces canonical ledger capacity without expanding authority")


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
