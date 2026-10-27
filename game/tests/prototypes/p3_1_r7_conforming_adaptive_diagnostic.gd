extends SceneTree

## R7 bounded topology/collider diagnostic. This script and its dependencies are
## test-only; it creates disposable in-memory physics proxies and never loads
## production terrain nodes or writes user saves.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Transition := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Picker := preload("res://scripts/terrain/terrain_brush_picker.gd")
const Fixture := preload("res://tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd")

const SEED := 131102026
const REGION := Vector2i.ZERO
const EXPECTED_UNEDITED_VERTICAL_OPENING := 1.75
const APPROACHES := ["A_conforming_propagation", "B_shared_faces_transitions", "C_hybrid_one_cell_halo"]
const SCENARIOS := ["zero_edit", "cave_wall_carve", "center_fill_then_wall_carve"]
const MAX_DIAGNOSTIC_SECONDS := 900

var _assertions := 0
var _failures: Array[String] = []
var _started_usec := 0
var _preflight_only := false
var _run_edited_after_preflight := false
var _scenario_records: Array[Dictionary] = []
var _skipped_scenarios: Array[String] = []


func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	var user_args := OS.get_cmdline_user_args()
	_preflight_only = user_args.has("--preflight-only")
	_run_edited_after_preflight = user_args.has("--run-edited-after-preflight")
	call_deferred("_run")


func _run() -> void:
	# The zero-edit topology/collider control is always first. Edited cases require
	# an explicit opt-in and are skipped if this preflight produces any failure.
	var scenarios: Array[String] = ["zero_edit"]
	if not _preflight_only and _run_edited_after_preflight:
		scenarios = SCENARIOS
	for scenario_index in range(scenarios.size()):
		var scenario: String = scenarios[scenario_index]
		if float(Time.get_ticks_usec() - _started_usec) / 1000000.0 > MAX_DIAGNOSTIC_SECONDS:
			_failures.append("diagnostic_stop_loss_runtime_exceeded")
			break
		var snapshot_result := _make_snapshot(String(scenario))
		_check(bool(snapshot_result.get("valid", false)), "%s_frozen_ledger_setup" % scenario)
		if not snapshot_result.get("valid", false):
			continue
		var snapshot: Dictionary = snapshot_result.snapshot
		var input_payload := _scenario_input_payload(String(scenario), snapshot)
		var input_canonical_json := JSON.stringify(input_payload)
		var input_sha256 := _sha256(input_canonical_json.to_utf8_buffer())
		var fixture := Fixture.new()
		var configured: bool = fixture.configure(SEED, snapshot)
		_check(configured, "%s_canonical_patch_setup" % scenario)
		if not configured:
			_failures.append("%s:%s" % [scenario, fixture.last_reason])
			continue
		var canonical_diameter := _vertical_diameter(func(point: Vector3) -> float:
			return Transition.sample_canonical(SEED, point, snapshot), _cave_center(10.0))
		if scenario == "zero_edit":
			_check(absf(canonical_diameter - EXPECTED_UNEDITED_VERTICAL_OPENING) <= 0.000001,
				"frozen_canonical_cave_opening_is_1_75")
		var approach_meshes: Dictionary = {}
		var approach_records: Array[Dictionary] = []
		for approach in APPROACHES:
			var begin := Time.get_ticks_usec()
			var built: Dictionary = fixture.build_approach(String(approach))
			var elapsed := Time.get_ticks_usec() - begin
			var record: Dictionary = {"approach": approach, "valid": bool(built.get("valid", false)),
				"elapsed_usec": elapsed}
			if built.get("valid", false):
				var stats: Dictionary = built.get("stats", {})
				var field_metrics := _field_metrics(fixture, String(approach), snapshot)
				var topology: Dictionary = stats.get("topology", {})
				var interfaces: Dictionary = stats.get("actual_cell_interface_contours", {})
				var structural_failures: Array[String] = []
				if int(topology.get("internal_open_edge_crack_count", -1)) != 0:
					structural_failures.append("internal_open_edges")
				if int(topology.get("nonmanifold_edge_count", -1)) != 0:
					structural_failures.append("nonmanifold_edges")
				if int(topology.get("degenerate_triangle_count", -1)) != 0:
					structural_failures.append("degenerate_triangles")
				if int(interfaces.get("interfaces_with_nonmatching_extracted_contours", -1)) != 0:
					structural_failures.append("nonmatching_interface_contours")
				if int(interfaces.get("duplicate_coplanar_surface_interfaces", -1)) != 0:
					structural_failures.append("duplicated_coplanar_surface_interfaces")
				if int(interfaces.get("strict_t_junction_vertex_on_contour_segment_count", -1)) != 0:
					structural_failures.append("t_junctions")
				_check(structural_failures.is_empty(), "%s_%s_mesh_topology_gate" % [scenario, approach])
				record["structural_gate"] = "PASS" if structural_failures.is_empty() else "FAIL"
				record["structural_failures"] = structural_failures
				var mesh_sha256 := _mesh_sha256(built.positions, built.normals)
				record["mesh_output_sha256"] = mesh_sha256
				record.merge({"stats": stats, "field_geometry": field_metrics}, true)
				approach_meshes[String(approach)] = {"positions": built.positions, "normals": built.normals,
					"triangle_count": built.triangle_count, "stats": stats}
			else:
				record["rejection_reason"] = String(built.get("reason", "unknown"))
				record["bounded_rejection"] = _is_expected_bounded_rejection(String(built.get("reason", "")))
				_check(bool(record.bounded_rejection), "%s_%s_rejects_only_declared_limit_or_topology" % [scenario, approach])
			approach_records.append(record)
			print("R7_APPROACH " + JSON.stringify({"scenario": scenario, "seed": SEED, "revision": snapshot.get("revision", -1), "record": record}))
		var collider_metrics: Dictionary
		if approach_meshes.has(APPROACHES[0]) and approach_meshes.has(APPROACHES[1]) and approach_meshes.has(APPROACHES[2]):
			collider_metrics = await _physics_proxy_metrics(approach_meshes, snapshot)
			_check(String(collider_metrics.get("status", "")) == "MEASURED_TEST_ONLY_CONCAVE_POLYGON_PROXIES",
				"%s_collision_proxy_available" % scenario)
			_check(int(collider_metrics.get("ray_hit_outcome_mismatches_vs_canonical", -1)) == 0,
				"%s_all_test_only_collider_ray_hit_outcomes_match_canonical" % scenario)
		else:
			collider_metrics = {"status": "NOT_MEASURED", "reason": "one_or_more_mesh_approaches_were_rejected"}
		var scenario_record := {"scenario": scenario, "scenario_version": "P3.1.R7.%s.v1" % String(scenario).to_upper(),
			"seed": SEED, "generator_version": Field.GENERATOR_VERSION,
			"region": [REGION.x, REGION.y], "operation_count": snapshot.get("centers", PackedVector3Array()).size(),
			"input_manifest_canonical_json": input_canonical_json, "input_manifest_sha256": input_sha256,
			"ordered_commands": input_payload.get("ordered_commands", []),
			"mesh_output_sha256_by_approach": _approach_mesh_hashes(approach_records),
			"ledger_revision": snapshot.get("revision", -1), "canonical_vertical_opening_world": canonical_diameter,
			"geometry_tolerances": "NO_OWNER_APPROVED_TOLERANCES", "approaches": approach_records,
			"test_only_physics_collision_proxy": collider_metrics}
		_scenario_records.append(scenario_record)
		print("R7_SCENARIO " + JSON.stringify(scenario_record))
		if scenario == "zero_edit" and not _failures.is_empty() and scenario_index + 1 < scenarios.size():
			for skipped_index in range(scenario_index + 1, scenarios.size()):
				_skipped_scenarios.append(scenarios[skipped_index])
			break
	var result := {"suite": "P3_1_R7_CONFORMING_ADAPTIVE_DIAGNOSTIC", "status": "FAIL" if not _failures.is_empty() else "PASS",
		"preflight_only": _preflight_only, "scenario_count": _scenario_records.size(),
		"run_edited_after_preflight_requested": _run_edited_after_preflight,
		"skipped_scenarios": _skipped_scenarios,
		"assertions": _assertions, "failures": _failures,
		"duration_usec": Time.get_ticks_usec() - _started_usec,
		"scope": "bounded test-only A/B/C geometry and physics proxies; results are exploratory, not product acceptance"}
	print("R7_RESULT " + JSON.stringify(result))
	quit(1 if not _failures.is_empty() else 0)


func _make_snapshot(scenario: String) -> Dictionary:
	var ledger: RefCounted = Brush.new(SEED, Field.GENERATOR_VERSION)
	var center := _cave_center(8.0)
	if scenario == "cave_wall_carve":
		if not ledger.add_sphere(Brush.Mode.CARVE, center + Vector3(0.0, 0.0, 0.80), 0.58):
			return {"valid": false, "reason": "frozen_wall_carve_rejected"}
	elif scenario == "center_fill_then_wall_carve":
		if not ledger.add_sphere(Brush.Mode.FILL, center, 0.58):
			return {"valid": false, "reason": "frozen_center_fill_rejected"}
		if not ledger.add_sphere(Brush.Mode.CARVE, center + Vector3(0.0, 0.0, 0.82), 0.58):
			return {"valid": false, "reason": "frozen_wall_carve_after_fill_rejected"}
	elif scenario != "zero_edit":
		return {"valid": false, "reason": "scenario_not_frozen"}
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	var expected := 0 if scenario == "zero_edit" else (1 if scenario == "cave_wall_carve" else 2)
	if int(snapshot.get("revision", -1)) != expected \
		or snapshot.get("centers", PackedVector3Array()).size() != expected \
		or snapshot.get("radii", PackedFloat32Array()).size() != expected \
		or snapshot.get("modes", PackedByteArray()).size() != expected:
		return {"valid": false, "reason": "frozen_snapshot_identity_mismatch"}
	return {"valid": true, "snapshot": snapshot}


func _scenario_input_payload(scenario: String, snapshot: Dictionary) -> Dictionary:
	var commands: Array[Dictionary] = []
	var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
	var radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
	var modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
	for index in range(centers.size()):
		var point: Vector3 = centers[index]
		commands.append({"sequence": index, "mode": int(modes[index]),
			"center": [point.x, point.y, point.z], "radius": float(radii[index])})
	return {"scenario_id": "P3.1.R7.%s.v1" % scenario.to_upper(), "seed": SEED,
		"generator_version": Field.GENERATOR_VERSION, "region": [REGION.x, REGION.y],
		"canonical_field": "SDF_v1_sample_canonical", "ordered_commands": commands}


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "HASH_START_FAILED"
	context.update(bytes)
	return context.finish().hex_encode()


func _mesh_sha256(positions: PackedVector3Array, normals: PackedVector3Array) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "HASH_START_FAILED"
	context.update(PackedInt32Array([positions.size(), normals.size()]).to_byte_array())
	context.update(positions.to_byte_array())
	context.update(normals.to_byte_array())
	return context.finish().hex_encode()


func _approach_mesh_hashes(records: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for record in records:
		if record.has("mesh_sha256"):
			result[String(record.approach)] = String(record.mesh_sha256)
	return result


func _field_metrics(fixture: RefCounted, approach: String, snapshot: Dictionary) -> Dictionary:
	var centerline_open := 0
	var centerline_count := 0
	var diameters := PackedFloat64Array()
	var picker_hits_equal := 0
	var picker_position_errors := PackedFloat64Array()
	for index in range(1, 32):
		var world_x := 8.0 + float(index) * 0.125
		var center := _cave_center(world_x)
		var density: float = fixture.sample_approach(center, approach)
		centerline_count += 1
		if density < 0.0:
			centerline_open += 1
			var radii: Array[float] = []
			for angle_index in range(16):
				var angle := TAU * float(angle_index) / 16.0
				var direction := Vector3(0.0, sin(angle), cos(angle))
				var radius := _first_canonical_or_candidate_zero(center, direction, fixture, approach, snapshot)
				if radius >= 0.0: radii.append(radius)
			if radii.size() >= 8:
				diameters.append(_max_float(radii) * 2.0)
		var exact_sampler: Callable = func(point: Vector3) -> float:
			return Transition.sample_canonical(SEED, point, snapshot)
		var candidate_sampler: Callable = func(point: Vector3) -> float:
			return fixture.sample_approach(point, approach)
		var reference_pick: Dictionary = Picker.pick_sdf_v1_surface(center + Vector3.DOWN * 2.5, Vector3.UP, exact_sampler)
		var candidate_pick: Dictionary = Picker.pick_sdf_v1_surface(center + Vector3.DOWN * 2.5, Vector3.UP, candidate_sampler)
		if bool(reference_pick.get("hit", false)) == bool(candidate_pick.get("hit", false)):
			picker_hits_equal += 1
			if reference_pick.get("hit", false):
				picker_position_errors.append(reference_pick.position.distance_to(candidate_pick.position))
	return {"centerline_open_samples": centerline_open, "centerline_total_samples": centerline_count,
		"radial_diameter_world": _summary(diameters), "picker_hit_outcomes_equal": picker_hits_equal,
		"picker_queries": centerline_count, "picker_position_error_world": _summary(picker_position_errors),
		"note": "field and picker results describe piecewise sampled fields; mesh topology is reported separately"}


func _vertical_diameter(sample: Callable, center: Vector3) -> float:
	var below := 0
	var above := 0
	for direction in [-1, 1]:
		for index in range(1, 65):
			var point := center + Vector3(0.0, float(direction * index) * 0.0625, 0.0)
			if float(sample.call(point)) < 0.0:
				if direction < 0: below += 1
				else: above += 1
			else:
				break
	return float(below + above) * 0.0625


func _first_canonical_or_candidate_zero(center: Vector3, direction: Vector3,
		fixture: RefCounted, approach: String, snapshot: Dictionary) -> float:
	var previous := float(fixture.sample_approach(center, approach))
	if previous >= 0.0: return -1.0
	var prior_radius := 0.0
	for step_index in range(1, 61):
		var radius := float(step_index) * 0.05
		var density := float(fixture.sample_approach(center + direction * radius, approach))
		if not is_finite(density): return -1.0
		if density >= 0.0:
			var low := prior_radius
			var high := radius
			for _iteration in range(16):
				var middle := (low + high) * 0.5
				if fixture.sample_approach(center + direction * middle, approach) < 0.0: low = middle
				else: high = middle
			return (low + high) * 0.5
		prior_radius = radius
	return -1.0


func _physics_proxy_metrics(meshes: Dictionary, snapshot: Dictionary) -> Dictionary:
	if get_root().world_3d == null:
		get_root().world_3d = World3D.new()
	var space_state := get_root().world_3d.direct_space_state
	if space_state == null:
		return {"status": "NOT_AVAILABLE", "reason": "headless_world_has_no_direct_physics_space"}
	var body_nodes: Array[StaticBody3D] = []
	var approach_names := [APPROACHES[0], APPROACHES[1], APPROACHES[2]]
	for index in range(approach_names.size()):
		var approach: String = String(approach_names[index])
		var data: Dictionary = meshes[approach]
		var vertices: PackedVector3Array = data.positions
		if vertices.is_empty() or vertices.size() % 3 != 0:
			return {"status": "NOT_AVAILABLE", "reason": "%s_mesh_not_collider_ready" % approach}
		var local_faces := PackedVector3Array()
		local_faces.resize(vertices.size())
		for vertex_index in range(vertices.size()):
			local_faces[vertex_index] = vertices[vertex_index] - Fixture.PATCH_MIN
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(local_faces)
		var body := StaticBody3D.new()
		body.collision_layer = 1 << index
		body.collision_mask = 0
		body.position = Fixture.PATCH_MIN + Vector3(float(index) * 30.0, 0.0, 0.0)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		get_root().add_child(body)
		body_nodes.append(body)
	await physics_frame
	space_state = get_root().world_3d.direct_space_state
	var center := _cave_center(10.0)
	var ray_records: Array[Dictionary] = []
	var penetration_records: Array[Dictionary] = []
	var sphere := SphereShape3D.new()
	sphere.radius = 0.10
	for index in range(approach_names.size()):
		var approach: String = String(approach_names[index])
		var mask: int = 1 << index
		for angle_index in range(12):
			var angle := TAU * float(angle_index) / 12.0
			var direction := Vector3(0.0, sin(angle), cos(angle))
			var offset := Vector3(float(index) * 30.0, 0.0, 0.0)
			var canonical_radius := _canonical_radius(center, direction, snapshot)
			for reverse_ray in [false, true]:
				var from_center := center + offset
				var from_outside := from_center + direction * 2.5
				var ray := PhysicsRayQueryParameters3D.create(from_outside, from_center, mask) if reverse_ray \
					else PhysicsRayQueryParameters3D.create(from_center, from_outside, mask)
				ray.hit_back_faces = true
				var ray_result: Dictionary = space_state.intersect_ray(ray)
				var ray_distance := INF
				var measured_radius := INF
				if not ray_result.is_empty():
					ray_distance = Vector3(ray_result.position).distance_to(ray.from)
					measured_radius = 2.5 - ray_distance if reverse_ray else ray_distance
				var expected_hit := is_finite(canonical_radius) and canonical_radius > 0.0
				ray_records.append({"approach": approach, "angle_index": angle_index,
					"direction": "outside_to_cave" if reverse_ray else "cave_to_outside",
					"hit": not ray_result.is_empty(), "expected_hit": expected_hit,
					"hit_outcome_matches_canonical": (not ray_result.is_empty()) == expected_hit,
					"ray_distance_world": ray_distance, "measured_surface_radius_world": measured_radius,
					"canonical_sdf_surface_radius_world": canonical_radius,
					"surface_difference_world": absf(measured_radius - canonical_radius) if is_finite(measured_radius) else INF})
			var first_sphere_contact := INF
			for probe_step in range(1, 49):
				var distance := float(probe_step) * 0.05
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = sphere
				query.transform = Transform3D(Basis.IDENTITY, center + offset + direction * distance)
				query.collision_mask = mask
				query.collide_with_bodies = true
				query.collide_with_areas = false
				if not space_state.intersect_shape(query, 1).is_empty():
					first_sphere_contact = distance
					break
			penetration_records.append({"approach": approach, "angle_index": angle_index,
				"sphere_radius_world": sphere.radius, "first_overlap_center_distance_world": first_sphere_contact,
				"canonical_expected_contact_center_distance_world": maxf(0.0, canonical_radius - sphere.radius),
				"contact_difference_world": absf(first_sphere_contact - maxf(0.0, canonical_radius - sphere.radius)) if is_finite(first_sphere_contact) else INF})
	for body in body_nodes:
		body.queue_free()
	await physics_frame
	var ray_differences := PackedFloat64Array()
	var penetration_differences := PackedFloat64Array()
	var ray_outcome_mismatches := 0
	var outside_to_cave_ray_outcome_mismatches := 0
	var cave_to_outside_ray_outcome_mismatches := 0
	for record in ray_records:
		if not bool(record.hit_outcome_matches_canonical):
			ray_outcome_mismatches += 1
			if String(record.direction) == "outside_to_cave": outside_to_cave_ray_outcome_mismatches += 1
			else: cave_to_outside_ray_outcome_mismatches += 1
		if is_finite(float(record.surface_difference_world)):
			ray_differences.append(float(record.surface_difference_world))
	for record in penetration_records:
		if is_finite(float(record.contact_difference_world)):
			penetration_differences.append(float(record.contact_difference_world))
	return {"status": "MEASURED_TEST_ONLY_CONCAVE_POLYGON_PROXIES",
		"production_terrain_collision_provider": "ABSENT_AT_PINNED_SOURCE",
		"ray_query_count": ray_records.size(), "ray_hit_records": ray_records,
		"ray_hit_outcome_mismatches_vs_canonical": ray_outcome_mismatches,
		"outside_to_cave_ray_hit_outcome_mismatches": outside_to_cave_ray_outcome_mismatches,
		"cave_to_outside_ray_hit_outcome_mismatches": cave_to_outside_ray_outcome_mismatches,
		"ray_surface_difference_world": _summary(ray_differences),
		"sphere_probe_count": penetration_records.size(), "sphere_penetration_proxy_records": penetration_records,
		"sphere_contact_difference_world": _summary(penetration_differences),
		"limitations": "discrete 0.05-unit sphere sweep, no continuous collision/MTV or production terrain collider claim"}


func _canonical_radius(center: Vector3, direction: Vector3, snapshot: Dictionary) -> float:
	var previous := Transition.sample_canonical(SEED, center, snapshot)
	if previous >= 0.0: return -1.0
	var low := 0.0
	var high := 0.0
	for index in range(1, 121):
		high = float(index) * 0.025
		if Transition.sample_canonical(SEED, center + direction * high, snapshot) >= 0.0:
			for _iteration in range(18):
				var middle := (low + high) * 0.5
				if Transition.sample_canonical(SEED, center + direction * middle, snapshot) < 0.0: low = middle
				else: high = middle
			return (low + high) * 0.5
		low = high
	return INF


func _cave_center(world_x: float) -> Vector3:
	var cross_section: Vector2 = Field.cave_center(SEED, REGION, world_x)
	return Vector3(world_x, cross_section.y, cross_section.x)


func _is_expected_bounded_rejection(reason: String) -> bool:
	return reason.begins_with("transition_topology_unsupported_faces_") \
		or reason in ["propagation_radius_limit_exceeded", "propagation_cell_limit_exceeded",
			"fine_payload_limit_exceeded", "mesh_triangle_limit_exceeded"]


func _max_float(values: Array[float]) -> float:
	var result := -INF
	for value in values: result = maxf(result, value)
	return result


func _summary(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty(): return {"count": 0, "p50": NAN, "p95": NAN, "max": NAN}
	var sorted: Array[float] = []
	for value in values: sorted.append(value)
	sorted.sort()
	return {"count": sorted.size(), "p50": _percentile(sorted, 0.5),
		"p95": _percentile(sorted, 0.95), "max": sorted.back()}


func _percentile(values: Array[float], q: float) -> float:
	if values.is_empty(): return NAN
	return values[clampi(ceili(q * values.size()) - 1, 0, values.size() - 1)]


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)
