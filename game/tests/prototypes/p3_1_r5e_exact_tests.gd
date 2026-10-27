extends SceneTree

const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const R5Density := preload("res://tests/prototypes/r5_exact_density.gd")

const SEED := 131102026
var _assertions := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_usec()
	var fixture := "res://tests/fixtures/p3_1_r4/issue131/P31.EDIT.CONCENTRATED.N8192.v1.R01.commands.json"
	var fixture_bytes := FileAccess.get_file_as_bytes(fixture)
	_check(not fixture_bytes.is_empty(), "frozen_8192_fixture_present")
	var parsed: Variant = JSON.parse_string(fixture_bytes.get_string_from_utf8())
	_check(typeof(parsed) == TYPE_ARRAY and (parsed as Array).size() == 8192, "frozen_8192_fixture_count")
	if not _failures.is_empty():
		_finish(started)
		return
	var ledger: RefCounted = Brush.new(SEED, 1)
	for index in range((parsed as Array).size()):
		var command: Dictionary = parsed[index]
		var center_mm: Array = command.center_mm
		var center := Vector3(float(center_mm[0]), float(center_mm[1]), float(center_mm[2])) / 1000.0
		var mode := Brush.Mode.CARVE if String(command.mode) == "CARVE" else Brush.Mode.FILL
		_check(ledger.add_sphere(mode, center, float(command.radius_mm) / 1000.0), "ledger_append_%d" % index)
		if not _failures.is_empty():
			break
	var region := Vector2i.ZERO
	var chunk := Vector2i.ZERO
	var canonical: Dictionary = ledger.get_meshing_snapshot()
	var projected: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	_check(bool(projected.get("valid", false)), "canonical_chunk_projection_ready")
	_check(int(projected.get("candidate_operation_count", -1)) == 8192, "concentrated_local_history_retained_without_radius_filter")
	var evaluator := R5Density.new()
	_check(evaluator.configure(SEED, region, projected), "r5_exact_evaluator_configured")
	var probes: Array[Vector3] = []
	var canonical_query_times := PackedInt64Array()
	var optimized_query_times := PackedInt64Array()
	var origin := Spatial.region_origin_world(region) + Grid.origin_for(chunk)
	var size := Grid.size_for(chunk)
	for index in range(768):
		var x := origin.x + size.x * float(posmod(index * 17, 769)) / 768.0
		var y := Grid.MIN_BOUND.y + (Grid.MAX_BOUND.y - Grid.MIN_BOUND.y) * float(posmod(index * 31, 769)) / 768.0
		var z := origin.z + size.z * float(posmod(index * 43, 769)) / 768.0
		probes.append(Vector3(x, y, z))
	# Include command centers, face/edge/corner probes, signed region transitions,
	# and points within a guarded distance threshold.
	for index in [0, 1, 31, 255, 2047, 4095, 8191]:
		var center: Vector3 = projected.centers[index]
		probes.append(center)
		probes.append(center + Vector3(0.5800005, 0.0, 0.0))
		probes.append(center + Vector3(0.5799995, 0.0, 0.0))
	for seam in [Vector3(-0.001, 2.0, 1.0), Vector3(0.0, 2.0, 1.0),
		Vector3(15.999, 2.0, 11.999), Vector3(16.0, 2.0, 12.0),
		Vector3(-16.0, -0.25, -12.0), Vector3(-31.999, 1.15, -767.999)]:
		probes.append(seam)
	var cave_center: Vector2 = Field.cave_center(SEED, Vector2i.ZERO, 2.5)
	probes.append(Vector3(2.5, cave_center.y, cave_center.x))
	for point in probes:
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var canonical_started := Time.get_ticks_usec()
		var expected := Brush.sample_density_snapshot(SEED, mapped.region_key, mapped.local_position, false, canonical)
		canonical_query_times.append(Time.get_ticks_usec() - canonical_started)
		var optimized_started := Time.get_ticks_usec()
		var actual := evaluator.sample_world(point)
		optimized_query_times.append(Time.get_ticks_usec() - optimized_started)
		_check(expected == actual,
			"r5_axis_guard_density_equivalence_%d" % _assertions)
	# Compare exact CPU mesh outputs through the real canonical meshers. Callback
	# evaluation uses identical world points and the same immutable projection.
	var lod1_density_mismatches := 0
	var lod1_first_density_mismatch: Dictionary = {}
	var density_callback := func(point: Vector3) -> float:
		return R5Density.sample_world_optimized(SEED, region, projected, point)
	var lod1_density_callback := func(point: Vector3) -> float:
		var candidate_density: float = R5Density.sample_world_optimized(SEED, region, projected, point, false, true)
		var mapped: Dictionary = Spatial.world_to_region_local(point)
		var reference_density: float = Brush.sample_density_snapshot(SEED, mapped.region_key,
			mapped.local_position, false, canonical)
		if candidate_density != reference_density:
			lod1_density_mismatches += 1
			if lod1_first_density_mismatch.is_empty():
				lod1_first_density_mismatch = {"point": [point.x, point.y, point.z],
					"candidate": candidate_density, "reference": reference_density}
		return candidate_density
	var lod0_started := Time.get_ticks_usec()
	var reference_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, canonical)
	var reference_lod0_usec := Time.get_ticks_usec() - lod0_started
	var candidate_lod0_started := Time.get_ticks_usec()
	var candidate_lod0: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, {}, density_callback)
	var candidate_lod0_usec := Time.get_ticks_usec() - candidate_lod0_started
	_check(bool(reference_lod0.get("valid", false)) and bool(candidate_lod0.get("valid", false)), "lod0_meshes_valid")
	_check(_mesh_equal(reference_lod0, candidate_lod0), "lod0_exact_positions_normals_topology")
	var lod1_started := Time.get_ticks_usec()
	var reference_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region, chunk, canonical)
	var reference_lod1_usec := Time.get_ticks_usec() - lod1_started
	var candidate_lod1_started := Time.get_ticks_usec()
	var candidate_lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region, chunk, {}, lod1_density_callback)
	var candidate_lod1_usec := Time.get_ticks_usec() - candidate_lod1_started
	_check(bool(reference_lod1.get("valid", false)) and bool(candidate_lod1.get("valid", false)), "lod1_meshes_valid")
	var lod1_positions_equal: bool = reference_lod1.get("positions") == candidate_lod1.get("positions")
	var lod1_normals_equal: bool = reference_lod1.get("normals") == candidate_lod1.get("normals")
	var lod1_topology_equal: bool = int(reference_lod1.get("triangle_count", -1)) == int(candidate_lod1.get("triangle_count", -2))
	_check(lod1_positions_equal and lod1_normals_equal and lod1_topology_equal,
		"lod1_exact_positions_normals_topology")
	_check(lod1_density_mismatches == 0, "lod1_all_requested_density_samples_exact")
	var stats: Dictionary = evaluator.statistics()
	var ratio := float(stats.exact_distance_evaluations) / maxf(1.0, float(stats.queries * stats.ledger_operations))
	var result := {"status": "FAIL" if not _failures.is_empty() else "PASS",
		"source_baseline": "92b442d7f5b605c7bc9c48fac2aceea9d71813aa",
		"inherited_r4_head": "051249642611a7fa9cd2006be450bad0e184e4ee",
		"scenario": "P31.R5E.CONCENTRATED.N8192.v1", "fixture_sha256": _sha256(fixture_bytes),
		"candidate_operations": int(projected.candidate_operation_count), "probe_count": probes.size(),
		"query_statistics": stats, "exact_distance_fraction": ratio,
		"canonical_query_usec": _summary(canonical_query_times),
		"optimized_query_usec": _summary(optimized_query_times),
		"lod0_reference_usec": reference_lod0_usec, "lod0_candidate_usec": candidate_lod0_usec,
		"lod1_reference_usec": reference_lod1_usec, "lod1_candidate_usec": candidate_lod1_usec,
		"lod1_positions_equal": lod1_positions_equal, "lod1_normals_equal": lod1_normals_equal,
		"lod1_topology_equal": lod1_topology_equal,
		"lod1_density_mismatches": lod1_density_mismatches,
		"lod1_first_density_mismatch": lod1_first_density_mismatch,
		"failures": _failures, "assertions": _assertions,
		"timing_note": "single headless process; exploratory, no presented-frame/GPU claim"}
	_finish(started, result)


func _mesh_equal(a: Dictionary, b: Dictionary) -> bool:
	return a.get("positions", PackedVector3Array()) == b.get("positions", PackedVector3Array()) \
		and a.get("normals", PackedVector3Array()) == b.get("normals", PackedVector3Array()) \
		and int(a.get("triangle_count", -1)) == int(b.get("triangle_count", -2))


func _check(value: bool, label: String) -> void:
	_assertions += 1
	if not value:
		_failures.append(label)
		push_error("R5E_FAIL " + label)


func _summary(values: PackedInt64Array) -> Dictionary:
	var ordered: Array[int] = []
	for value in values: ordered.append(value)
	ordered.sort()
	return {"count": ordered.size(), "p50": _percentile(ordered, 0.5), "p95": _percentile(ordered, 0.95),
		"p99": _percentile(ordered, 0.99), "max": ordered[-1] if not ordered.is_empty() else 0}


func _percentile(values: Array[int], q: float) -> int:
	if values.is_empty(): return 0
	return values[clampi(ceili(q * values.size()) - 1, 0, values.size() - 1)]


func _finish(started: int, result: Dictionary = {}) -> void:
	var output := {"assertions": _assertions, "failures": _failures,
		"duration_usec": Time.get_ticks_usec() - started}
	if not result.is_empty():
		output.merge(result, true)
	_print_json(output)
	print("P31_R5E_TESTS_%s assertions=%d failures=%d" % ["FAIL" if not _failures.is_empty() else "PASS", _assertions, _failures.size()])
	quit(1 if not _failures.is_empty() else 0)


func _print_json(value: Dictionary) -> void:
	print("P31_R5E_JSON " + JSON.stringify(value))


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
