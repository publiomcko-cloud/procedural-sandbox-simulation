extends SceneTree

const ChunkGrid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const LodPolicy := preload("res://scripts/terrain/terrain_lod_policy.gd")
const TerrainMesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const DemoScript := preload("res://scripts/terrain/terrain_demo.gd")

const SEED := 424242
const EPSILON := 0.0002

var assertions := 0
var failures := 0
var measured_lod1_usec := 0
var measured_shared_builder_usec := 0
var measured_reference_builder_usec := 0
var measured_lod0_triangles := 0
var measured_lod1_triangles := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_hysteresis_and_fail_closed_selection()
	_test_chunk_boundary_transition_masks()
	await _test_chunk_boundary_mesh_seams()
	_test_shared_builder_matches_per_cell_reference()
	_test_lod_reduces_triangle_count()
	await _test_edit_replay_and_reload_equivalence()
	_test_stage_staleness_and_lod0_fallback()
	if failures == 0:
		print("TERRAIN_LOD_RUNTIME_PASS: assertions=%d failures=0 lod1_build_ms=%.3f shared_builder_ms=%.3f per_cell_reference_ms=%.3f same_chunk_triangles_lod0=%d lod1=%d" % [assertions, float(measured_lod1_usec) / 1000.0, float(measured_shared_builder_usec) / 1000.0, float(measured_reference_builder_usec) / 1000.0, measured_lod0_triangles, measured_lod1_triangles])
	else:
		push_error("TERRAIN_LOD_RUNTIME_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_hysteresis_and_fail_closed_selection() -> void:
	_check(LodPolicy.select_lod(40.0, 0) == 0, "near camera keeps chunk at LOD0")
	_check(LodPolicy.select_lod(60.0, 0) == 1, "far camera moves chunk to LOD1")
	_check(LodPolicy.select_lod(50.0, 0) == 0, "middle band retains fine current state")
	_check(LodPolicy.select_lod(50.0, 1) == 1, "middle band retains coarse current state")
	_check(LodPolicy.select_lod(46.0, 1) == 0, "near threshold returns to LOD0")
	_check(LodPolicy.select_lod(56.0, 0) == 1, "far threshold enters LOD1")
	_check(LodPolicy.select_lod(NAN, 1) == 0, "nonfinite camera distance fails closed to LOD0")
	_check(LodPolicy.select_lod(-1.0, 1) == 0, "negative camera distance fails closed to LOD0")
	_check(LodPolicy.select_lod(80.0, 1, false) == 0, "disabled LOD selects the LOD0 rollback path")


func _test_chunk_boundary_transition_masks() -> void:
	_check(LodMesher.transition_faces_for_cell(Vector3i(0, 4, 1), Vector3i(4, 10, 3)) == [0], "negative-X chunk face has a fine-compatible transition face")
	_check(LodMesher.transition_faces_for_cell(Vector3i(3, 4, 1), Vector3i(4, 10, 3)) == [1], "positive-X chunk face has a fine-compatible transition face")
	_check(LodMesher.transition_faces_for_cell(Vector3i(1, 4, 0), Vector3i(4, 10, 3)) == [4], "negative-Z chunk face has a fine-compatible transition face")
	_check(LodMesher.transition_faces_for_cell(Vector3i(1, 4, 2), Vector3i(4, 10, 3)) == [5], "positive-Z chunk face has a fine-compatible transition face")
	_check(LodMesher.transition_faces_for_cell(Vector3i(0, 4, 0), Vector3i(4, 10, 3)) == [0, 4], "X/Z corner combines two nonopposing transition faces")
	_check(LodMesher.transition_faces_for_cell(Vector3i(3, 4, 2), Vector3i(4, 10, 3)) == [1, 5], "opposite X/Z corner combines two nonopposing transition faces")
	_check(LodMesher.transition_faces_for_cell(Vector3i(1, 4, 1), Vector3i(4, 10, 3)).is_empty(), "interior coarse cell uses the regular LOD1 reference builder")


func _test_chunk_boundary_mesh_seams() -> void:
	var negative_corner := Vector2i.ZERO
	var coarse_negative_corner: Dictionary = _build_lod1(negative_corner, Vector2i.ZERO)
	var fine_negative_x: Dictionary = _build_lod0(Vector2i(-1, 0), Vector2i(3, 0))
	var fine_negative_z: Dictionary = _build_lod0(Vector2i(0, -1), Vector2i(0, 3))
	_assert_seam(coarse_negative_corner, negative_corner, Vector2i.ZERO, fine_negative_x, Vector2i(-1, 0), Vector2i(3, 0), 0, 0.0, "negative-X signed chunk boundary")
	_assert_seam(coarse_negative_corner, negative_corner, Vector2i.ZERO, fine_negative_z, Vector2i(0, -1), Vector2i(0, 3), 2, 0.0, "negative-Z signed chunk boundary")
	var coarse_positive_x: Dictionary = _build_lod1(Vector2i.ZERO, Vector2i(3, 0))
	var fine_positive_x: Dictionary = _build_lod0(Vector2i(1, 0), Vector2i.ZERO)
	_assert_seam(coarse_positive_x, Vector2i.ZERO, Vector2i(3, 0), fine_positive_x, Vector2i(1, 0), Vector2i.ZERO, 0, 16.0, "positive-X region boundary")
	var coarse_positive_z: Dictionary = _build_lod1(Vector2i.ZERO, Vector2i(0, 3))
	var fine_positive_z: Dictionary = _build_lod0(Vector2i(0, 1), Vector2i.ZERO)
	_assert_seam(coarse_positive_z, Vector2i.ZERO, Vector2i(0, 3), fine_positive_z, Vector2i(0, 1), Vector2i.ZERO, 2, 12.0, "positive-Z region boundary")
	_check(int(coarse_negative_corner.get("transition_cell_count", 0)) > 0, "LOD1 corner chunk includes a bounded transition-cell layer")
	_check(Spatial.region_key_for_cell(-1, -1) == Vector2i(-1, -1), "negative-world seam fixture retains mathematical-floor region ownership")


func _test_shared_builder_matches_per_cell_reference() -> void:
	var coordinate := Vector2i(1, 1)
	var shared_started_usec := Time.get_ticks_usec()
	var optimized: Dictionary = LodMesher.build_chunk_cpu_data(
		SEED, Vector2i.ZERO, coordinate, {}, Callable(self, "_synthetic_density")
	)
	measured_shared_builder_usec = Time.get_ticks_usec() - shared_started_usec
	var reference_started_usec := Time.get_ticks_usec()
	var reference: Dictionary = LodMesher.build_chunk_cpu_data_per_cell_reference(
		SEED, Vector2i.ZERO, coordinate, {}, Callable(self, "_synthetic_density")
	)
	measured_reference_builder_usec = Time.get_ticks_usec() - reference_started_usec
	_check(bool(optimized.get("valid", false)) and bool(reference.get("valid", false)), "shared-cache and independent per-cell LOD1 builders both succeed")
	_check(optimized.get("positions", PackedVector3Array()) == reference.get("positions", PackedVector3Array()), "shared-cache LOD1 builder preserves exact ordered geometry")
	_check(optimized.get("normals", PackedVector3Array()) == reference.get("normals", PackedVector3Array()), "shared-cache LOD1 builder preserves exact normals")
	_check(optimized.get("transition_cell_count", -1) == reference.get("transition_cell_count", -2), "shared-cache LOD1 builder preserves transition-cell coverage")


func _test_lod_reduces_triangle_count() -> void:
	var coordinate := Vector2i(1, 1)
	var lod0: Dictionary = TerrainMesher.build_chunk_cpu_data(SEED, Vector2i.ZERO, coordinate, false, {}, Callable(self, "_synthetic_density"))
	var lod1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, Vector2i.ZERO, coordinate, {}, Callable(self, "_synthetic_density"))
	measured_lod0_triangles = int(lod0.get("triangle_count", 0))
	measured_lod1_triangles = int(lod1.get("triangle_count", 0))
	_check(bool(lod0.get("valid", false)) and bool(lod1.get("valid", false)), "same-coordinate LOD0 and LOD1 chunks build for complexity comparison")
	_check(measured_lod1_triangles < measured_lod0_triangles, "LOD1 chunk has fewer triangles than its LOD0 counterpart")


func _test_edit_replay_and_reload_equivalence() -> void:
	var ledger: RefCounted = BrushState.new(SEED, Field.GENERATOR_VERSION)
	var empty_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i.ZERO)
	var before_job: Variant = _make_lod1_job(Vector2i.ZERO, Vector2i.ZERO, empty_snapshot)
	before_job.run()
	_check(bool(before_job.result.get("valid", false)), "LOD1 worker path builds canonical mesh data before editing")
	var edit_accepted: bool = ledger.add_sphere(BrushState.Mode.CARVE, Vector3(0.1, 2.2, 1.5), 0.6)
	_check(edit_accepted, "canonical carve adjacent to an X/Z interface is accepted once")
	var edited_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i.ZERO)
	var after_job: Variant = _make_lod1_job(Vector2i.ZERO, Vector2i.ZERO, edited_snapshot)
	after_job.run()
	_check(bool(after_job.result.get("valid", false)), "LOD1 worker path replays the canonical edited snapshot")
	_check(after_job.result.get("positions") != before_job.result.get("positions"), "interface-adjacent edit changes derived LOD1 geometry")
	var reloaded_job: Variant = _make_lod1_job(Vector2i.ZERO, Vector2i.ZERO, edited_snapshot)
	reloaded_job.run()
	_check(reloaded_job.result.get("positions") == after_job.result.get("positions"), "unloaded/reloaded LOD1 rebuild is deterministic from the canonical ledger snapshot")
	_check(int(after_job.result.get("ledger_revision", -1)) == ledger.revision, "LOD1 result reports the ledger revision used for sampling")


func _test_stage_staleness_and_lod0_fallback() -> void:
	var demo: Node3D = DemoScript.new()
	var test_camera := Camera3D.new()
	root.add_child(test_camera)
	demo.set("camera", test_camera)
	demo.set("lod_enabled", true)
	var coordinate := Vector2i.ZERO
	var chunk_id: String = ChunkGrid.stable_id(Vector2i.ZERO, coordinate)
	var center: Vector3 = Spatial.region_origin_world(Vector2i.ZERO) + ChunkGrid.origin_for(coordinate) + ChunkGrid.size_for(coordinate) * 0.5
	test_camera.global_position = center + Vector3(60.0, 0.0, 0.0)
	_check(int(demo.call("_desired_lod_for_chunk", Vector2i.ZERO, coordinate, 0)) == 1, "playable selector requests coarse mesh beyond the camera threshold")
	var stage := {"region_key": Vector2i.ZERO, "chunk_coordinates": [coordinate], "lod_by_coordinate": {coordinate: 1}}
	_check(bool(demo.call("_stage_lod_selection_is_current", stage)), "far-camera LOD request remains current before publication")
	test_camera.global_position = center + Vector3(40.0, 0.0, 0.0)
	_check(not bool(demo.call("_stage_lod_selection_is_current", stage)), "camera reversal rejects a stale coarse result before publication")
	var chunk_node := MeshInstance3D.new()
	demo.call("_set_chunk_lod_state", chunk_id, chunk_node, 0, true)
	test_camera.global_position = center + Vector3(80.0, 0.0, 0.0)
	_check(int(demo.call("_desired_lod_for_chunk", Vector2i.ZERO, coordinate, 0)) == 0, "failed LOD1 chunk stays on LOD0 fallback until explicit retry/toggle")
	demo.free()
	chunk_node.free()
	test_camera.queue_free()


func _build_lod1(region_key: Vector2i, coordinate: Vector2i) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var result: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region_key, coordinate, {}, Callable(self, "_synthetic_density"))
	measured_lod1_usec += Time.get_ticks_usec() - started_usec
	_check(bool(result.get("valid", false)), "LOD1 chunk assembly succeeds for %s/%s" % [region_key, coordinate])
	return result


func _build_lod0(region_key: Vector2i, coordinate: Vector2i) -> Dictionary:
	var result: Dictionary = TerrainMesher.build_chunk_cpu_data(SEED, region_key, coordinate, false, {}, Callable(self, "_synthetic_density"))
	_check(bool(result.get("valid", false)), "LOD0 reference chunk builds for %s/%s" % [region_key, coordinate])
	return result


func _make_lod1_job(region_key: Vector2i, coordinate: Vector2i, snapshot: Dictionary) -> Variant:
	var JobScript := load("res://scripts/terrain/terrain_mesh_job.gd")
	return JobScript.new(SEED, region_key, coordinate, false, snapshot, Time.get_ticks_usec(), 1)


func _synthetic_density(point: Vector3) -> float:
	return point.y + 0.12 * sin(point.x * 0.17 + point.z * 0.61) + 0.035 * cos(point.z * 0.23) - 2.73


func _assert_seam(coarse: Dictionary, coarse_region: Vector2i, coarse_coordinate: Vector2i, fine: Dictionary, fine_region: Vector2i, fine_coordinate: Vector2i, axis: int, plane: float, label: String) -> void:
	var coarse_boundary := _extract_boundary_segments(coarse, coarse_region, coarse_coordinate, axis, plane)
	var fine_boundary := _extract_boundary_segments(fine, fine_region, fine_coordinate, axis, plane)
	_check(not coarse_boundary["segments"].is_empty() and not fine_boundary["segments"].is_empty(), label + " has nonempty actual boundary contours")
	_check(coarse_boundary["segments"] == fine_boundary["segments"], label + " has exact LOD0/transition contour-segment equality")
	var normals_match := true
	for point_key in coarse_boundary["normals"]:
		if not fine_boundary["normals"].has(point_key):
			normals_match = false
			break
		var a: Vector3 = (coarse_boundary["normals"][point_key] as Array)[0]
		var b: Vector3 = (fine_boundary["normals"][point_key] as Array)[0]
		if a.dot(b) < 0.999:
			normals_match = false
			break
	_check(normals_match, label + " shares canonical endpoint normals")


func _extract_boundary_segments(result: Dictionary, region_key: Vector2i, coordinate: Vector2i, axis: int, plane: float) -> Dictionary:
	var origin: Vector3 = Spatial.region_origin_world(region_key) + ChunkGrid.origin_for(coordinate)
	var positions: PackedVector3Array = result.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = result.get("normals", PackedVector3Array())
	var segments: Dictionary = {}
	var endpoint_normals: Dictionary = {}
	for index in range(0, positions.size(), 3):
		var boundary_points: Array[Vector3] = []
		for corner in range(3):
			var point: Vector3 = positions[index + corner] + origin
			if absf(point[axis] - plane) <= EPSILON:
				boundary_points.append(point)
		if boundary_points.size() != 2:
			continue
		var key_a := _point_key(boundary_points[0])
		var key_b := _point_key(boundary_points[1])
		if key_a == key_b:
			continue
		var endpoints := [key_a, key_b]
		endpoints.sort()
		var segment_key := String(endpoints[0]) + "|" + String(endpoints[1])
		segments[segment_key] = int(segments.get(segment_key, 0)) + 1
		for corner in range(3):
			var point: Vector3 = positions[index + corner] + origin
			if absf(point[axis] - plane) > EPSILON:
				continue
			var point_key := _point_key(point)
			if not endpoint_normals.has(point_key):
				endpoint_normals[point_key] = []
			(endpoint_normals[point_key] as Array).append((normals[index + corner] as Vector3).normalized())
	return {"segments": segments, "normals": endpoint_normals}


func _point_key(point: Vector3) -> String:
	return "%.4f,%.4f,%.4f" % [point.x, point.y, point.z]


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ASSERTION FAILED: " + label)
