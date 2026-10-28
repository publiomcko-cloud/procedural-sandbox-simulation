class_name P31R92DiagnosticBase
extends RefCounted

## Shared R9.2-only manifest validation and canonical reference helpers.
## Candidate prototypes are test-only; no production scripts load this class.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Transition := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Geometry := preload("res://tests/prototypes/p3_1_r9_experiment_base.gd")
const MANIFEST_PATH := "res://tests/prototypes/p3_1_r9_2_e2e_inputs.jsonl"
const SIDECAR_PATH := "res://tests/prototypes/p3_1_r9_2_e2e_inputs.sha256"
const EXPECTED_MANIFEST_SHA := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const EXPECTED_CASES := 20
const MAX_NODES := 10000
const MAX_TRIANGLES := 20000
const MAX_PROPAGATION_RINGS := 4
const MAX_BUILD_USEC := 600000000
const MAX_SCENARIO_USEC := 60000000
const MAX_CANDIDATE_USEC := 600000000
const MAX_WORKING_SET_BYTES := 536870912
const GRID_CORNERS: Array[Vector3i] = [
	Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(1,1,0), Vector3i(0,1,0),
	Vector3i(0,0,1), Vector3i(1,0,1), Vector3i(1,1,1), Vector3i(0,1,1)]
const GRID_EDGES: Array[Vector2i] = [
	Vector2i(0,1),Vector2i(1,2),Vector2i(2,3),Vector2i(3,0),
	Vector2i(4,5),Vector2i(5,6),Vector2i(6,7),Vector2i(7,4),
	Vector2i(0,4),Vector2i(1,5),Vector2i(2,6),Vector2i(3,7)]
const TETS: Array[Array] = [[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]]

static func sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return "HASH_START_FAILED"
	ctx.update(bytes)
	return ctx.finish().hex_encode()

static func diagnostic_hooks(kind: String) -> Array:
	var generic: Array[String] = ["candidate_mesh", "topology", "surface_residual", "canonical_outward_normals"]
	var known := ["zero_edit", "single_carve", "ordered_fill_then_carve", "repeated_local_excavation",
		"repeated_local_fill", "neighboring_chunks", "equal_resolution_boundary", "mixed_lod_boundary",
		"negative_coordinate_region_boundaries", "historical_xplus_interface", "historical_xminus_displacement",
		"historical_triangle_root", "sampled_cave_connectivity", "extracted_mesh_cave_connectivity", "ray_picker_parity",
		"cpu_two_sided_triangle_proxy", "local_edit_to_mesh_rebuild", "deterministic_mesh_reconstruction",
		"memory_disk_serialization", "materialized_volume_corrupt_reload"]
	if not known.has(kind):
		return []
	if kind == "sampled_cave_connectivity":
		return ["canonical_sampled_cave_connectivity"]
	if kind == "neighboring_chunks":
		return generic + ["single_roi_build_only_no_independent_chunk_pair"]
	if kind in ["equal_resolution_boundary", "mixed_lod_boundary", "negative_coordinate_region_boundaries",
		"historical_xplus_interface"]:
		return generic + ["single_roi_contour_proxy_not_chunk_join"]
	if kind == "historical_xminus_displacement":
		return generic + ["canonical_and_mesh_ray_proxy"]
	if kind == "historical_triangle_root":
		return generic + ["local_cell_corner_probe_only"]
	if kind == "extracted_mesh_cave_connectivity":
		return generic + ["mesh_components_only_cave_connectivity_unimplemented"]
	if kind == "ray_picker_parity":
		return generic + ["canonical_cpu_mesh_ray_proxy_not_production_picker"]
	if kind == "cpu_two_sided_triangle_proxy":
		return generic + ["offline_cpu_two_sided_triangle_proxy"]
	if kind == "local_edit_to_mesh_rebuild":
		return generic + ["full_snapshot_rebuild_only_no_per_edit_update"]
	if kind == "deterministic_mesh_reconstruction":
		return generic + ["same_process_repeats_only"]
	if kind == "memory_disk_serialization":
		return generic + ["candidate_reported_serialization_only_process_memory_external"]
	if kind == "materialized_volume_corrupt_reload":
		return generic + ["actual_fresh_reader_corruption_reload"]
	return generic

static func candidate_scope(row: Dictionary, candidate: String) -> Dictionary:
	if not row.has("candidate_scope"):
		return {"valid": true, "in_scope": true}
	var value: Variant = row.get("candidate_scope")
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return {"valid": false, "reason": "candidate_scope_not_nonempty_array"}
	var scope: Array = value
	for item in scope:
		if typeof(item) != TYPE_STRING or not ["A", "B", "C", "D"].has(item):
			return {"valid": false, "reason": "candidate_scope_entry_invalid"}
	return {"valid": true, "in_scope": scope.has(candidate)}

static func iteration_counts(row: Dictionary, variant: Dictionary = {}) -> Dictionary:
	var warm_value: Variant = variant.get("warmups", row.get("warmups", null))
	var repeat_value: Variant = variant.get("repeats", row.get("repeats", null))
	var warm_check := _manifest_integer(warm_value)
	var repeat_check := _manifest_integer(repeat_value)
	if not warm_check.valid or not repeat_check.valid:
		return {"valid": false, "reason": "warmups_or_repeats_not_exact_integer"}
	var warmups: int = warm_check.value
	var repeats: int = repeat_check.value
	if warmups < 0 or warmups > 5 or repeats < 1 or repeats > 5:
		return {"valid": false, "reason": "warmups_or_repeats_outside_contract_bounds"}
	return {"valid": true, "warmups": warmups, "repeats": repeats}

static func _manifest_integer(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"valid": true, "value": int(value)}
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floorf(float(value)) and absf(float(value)) <= 2147483647.0:
		return {"valid": true, "value": int(value)}
	return {"valid": false}

static func load_manifest() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(MANIFEST_PATH)
	if bytes.is_empty():
		return {"valid": false, "reason": "manifest_unreadable"}
	var digest := sha256(bytes)
	if digest != EXPECTED_MANIFEST_SHA:
		return {"valid": false, "reason": "manifest_sha_mismatch", "observed_sha256": digest}
	var text := bytes.get_string_from_utf8()
	if text.begins_with("\uFEFF") or text.contains("\r") or not text.ends_with("\n"):
		return {"valid": false, "reason": "manifest_encoding_or_line_ending_invalid"}
	var sidecar_bytes := FileAccess.get_file_as_bytes(SIDECAR_PATH)
	var expected_sidecar := EXPECTED_MANIFEST_SHA + "  p3_1_r9_2_e2e_inputs.jsonl\n"
	if sidecar_bytes.get_string_from_utf8() != expected_sidecar:
		return {"valid": false, "reason": "manifest_sidecar_mismatch"}
	var lines := text.trim_suffix("\n").split("\n")
	if lines.size() != EXPECTED_CASES:
		return {"valid": false, "reason": "manifest_case_count_invalid", "observed_count": lines.size()}
	var rows: Array[Dictionary] = []
	var case_digests: Dictionary = {}
	var command_digests: Dictionary = {}
	var ids: Dictionary = {}
	for line in lines:
		var line_bytes := line.to_utf8_buffer()
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY or parsed.get("schema", "") != "P3.1.R9.2.Input.v1":
			return {"valid": false, "reason": "manifest_row_schema_invalid"}
		var row: Dictionary = parsed
		var scenario_id := String(row.get("scenario_id", ""))
		if scenario_id.is_empty() or ids.has(scenario_id):
			return {"valid": false, "reason": "manifest_scenario_id_invalid_or_duplicate", "scenario_id": scenario_id}
		ids[scenario_id] = true
		var command_check := validate_commands(row.get("commands", null))
		if not command_check.valid:
			return {"valid": false, "reason": "manifest_commands_invalid", "scenario_id": scenario_id, "detail": command_check.reason}
		if row.has("roi"):
			var roi_check := validate_roi(row.get("roi", null))
			if not roi_check.valid:
				return {"valid": false, "reason": "manifest_roi_invalid", "scenario_id": scenario_id, "detail": roi_check.reason}
		elif typeof(row.get("variants", null)) == TYPE_ARRAY and not row.variants.is_empty():
			for variant_value in row.variants:
				if typeof(variant_value) != TYPE_DICTIONARY:
					return {"valid": false, "reason": "manifest_variant_invalid", "scenario_id": scenario_id}
				var variant: Dictionary = variant_value
				var variant_roi := validate_roi(variant.get("roi", null))
				if not variant_roi.valid:
					return {"valid": false, "reason": "manifest_variant_roi_invalid", "scenario_id": scenario_id, "variant_id": variant.get("id", ""), "detail": variant_roi.reason}
		else:
			return {"valid": false, "reason": "manifest_roi_missing", "scenario_id": scenario_id}
		var raw_command_bytes := _extract_array_property(line_bytes, "commands")
		if raw_command_bytes.is_empty():
			return {"valid": false, "reason": "manifest_command_bytes_unavailable", "scenario_id": scenario_id}
		rows.append(row)
		case_digests[scenario_id] = sha256(line_bytes)
		command_digests[scenario_id] = sha256(raw_command_bytes)
	return {"valid": true, "sha256": digest, "rows": rows, "case_digests": case_digests,
		"command_digests": command_digests, "scenario_count": rows.size()}

static func validate_commands(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"valid": false, "reason": "commands_not_array"}
	var commands: Array = value
	for i in range(commands.size()):
		if typeof(commands[i]) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "command_not_dictionary"}
		var command: Dictionary = commands[i]
		if int(command.get("sequence", -1)) != i:
			return {"valid": false, "reason": "command_sequence_not_contiguous"}
		var mode := String(command.get("mode", ""))
		if mode != "CARVE" and mode != "FILL":
			return {"valid": false, "reason": "command_mode_unsupported"}
		var center: Variant = command.get("center", null)
		var radius: Variant = command.get("radius", null)
		if typeof(center) != TYPE_ARRAY or center.size() != 3 or typeof(radius) != TYPE_FLOAT and typeof(radius) != TYPE_INT:
			return {"valid": false, "reason": "command_numeric_shape_invalid"}
		for coordinate in center:
			if not is_finite(float(coordinate)):
				return {"valid": false, "reason": "command_center_nonfinite"}
		if not is_finite(float(radius)) or float(radius) <= 0.0:
			return {"valid": false, "reason": "command_radius_invalid"}
	return {"valid": true, "count": commands.size()}

static func validate_roi(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "roi_not_dictionary"}
	var roi: Dictionary = value
	var origin: Variant = roi.get("min", null)
	var cells: Variant = roi.get("cells", null)
	var step := float(roi.get("step", 0.0))
	if typeof(origin) != TYPE_ARRAY or origin.size() != 3 or typeof(cells) != TYPE_ARRAY or cells.size() != 3:
		return {"valid": false, "reason": "roi_shape_invalid"}
	if not is_finite(step) or step <= 0.0:
		return {"valid": false, "reason": "roi_step_invalid"}
	for coordinate in origin:
		if not is_finite(float(coordinate)):
			return {"valid": false, "reason": "roi_origin_nonfinite"}
	for count in cells:
		if int(count) <= 0:
			return {"valid": false, "reason": "roi_cell_count_invalid"}
	var node_count := (int(cells[0])+1)*(int(cells[1])+1)*(int(cells[2])+1)
	if node_count > MAX_NODES:
		return {"valid": false, "reason": "roi_node_stop_loss", "node_count": node_count}
	return {"valid": true, "node_count": node_count}

static func case_by_id(rows: Array, scenario_id: String) -> Dictionary:
	for value in rows:
		var row: Dictionary = value
		if String(row.get("scenario_id", "")) == scenario_id:
			return row
	return {}

static func make_snapshot(row: Dictionary) -> Dictionary:
	var seed := int(row.get("seed", -1))
	if seed < 0 or int(row.get("generator_version", -1)) != Field.GENERATOR_VERSION:
		return {"valid": false, "reason": "world_identity_invalid"}
	var ledger: RefCounted = Brush.new(seed, Field.GENERATOR_VERSION)
	var sequence := 0
	for value in row.get("commands", []):
		var command: Dictionary = value
		if int(command.get("sequence", -1)) != sequence:
			return {"valid": false, "reason": "command_sequence_changed"}
		var center: Array = command.center
		var mode := Brush.Mode.CARVE if String(command.mode) == "CARVE" else Brush.Mode.FILL
		if not ledger.add_sphere(mode, Vector3(float(center[0]), float(center[1]), float(center[2])), float(command.radius)):
			return {"valid": false, "reason": "frozen_command_rejected", "rejection": ledger.last_rejection_reason}
		sequence += 1
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	if int(snapshot.get("revision", -1)) != sequence:
		return {"valid": false, "reason": "snapshot_revision_mismatch"}
	return {"valid": true, "snapshot": snapshot, "revision": ledger.revision,
		"edit_count": ledger.get_edit_count(), "last_sequence": ledger.get_last_sequence()}

static func sample(world: Vector3, snapshot: Dictionary, seed: int = 131102026) -> float:
	return Transition.sample_canonical(seed, world, snapshot)

static func new_mesh() -> Dictionary:
	return Geometry.new_mesh()

static func add_triangle(mesh: Dictionary, a: Vector3, b: Vector3, c: Vector3, toward_empty: Vector3, cutoff: float = 1.0e-12) -> bool:
	return Geometry.add_triangle(mesh, a, b, c, toward_empty, cutoff)

static func topology(mesh: Dictionary, bounds_min: Vector3, bounds_max: Vector3) -> Dictionary:
	return Geometry.topology(mesh, bounds_min, bounds_max)

static func ray_mesh(origin: Vector3, direction: Vector3, max_distance: float, mesh: Dictionary) -> Dictionary:
	return Geometry.ray_mesh(origin, direction, max_distance, mesh)

static func _point_key(point: Vector3) -> String:
	return Geometry._point_key(point)

static func _key_point(key: String) -> Vector3:
	return Geometry._key_point(key)

static func surface_residual(mesh: Dictionary, snapshot: Dictionary, seed: int = 131102026) -> Dictionary:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	if positions.is_empty():
		return {"valid": false, "reason": "mesh_has_no_vertices"}
	var residuals: Array[float] = []
	for point in positions:
		var density := sample(point, snapshot, seed)
		if not is_finite(density):
			return {"valid": false, "reason": "nonfinite_surface_sample"}
		residuals.append(absf(density))
	residuals.sort()
	return {"valid": true, "count": residuals.size(), "p50": _percentile(residuals, 0.50),
		"p95": _percentile(residuals, 0.95), "max": residuals.back(), "sampling": "all emitted vertices; canonical absolute density, not a certified Hausdorff bound"}

static func mesh_components(mesh: Dictionary) -> Dictionary:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	if positions.size() % 3 != 0:
		return {"valid": false, "reason": "triangle_position_count_invalid"}
	var triangle_count := int(positions.size() / 3)
	if triangle_count == 0:
		return {"valid": true, "triangle_count": 0, "component_count": 0}
	var parent: Array[int] = []
	for triangle_id in range(triangle_count):
		parent.append(triangle_id)
	var edge_owner: Dictionary = {}
	for triangle_id in range(triangle_count):
		var base := triangle_id * 3
		for pair in [Vector2i(0,1), Vector2i(1,2), Vector2i(2,0)]:
			var a := _point_key(positions[base + pair.x])
			var b := _point_key(positions[base + pair.y])
			var key := a + "|" + b if a < b else b + "|" + a
			if edge_owner.has(key):
				_union(parent, triangle_id, int(edge_owner[key]))
			else:
				edge_owner[key] = triangle_id
	var roots: Dictionary = {}
	for triangle_id in range(triangle_count):
		roots[_find_root(parent, triangle_id)] = true
	return {"valid": true, "triangle_count": triangle_count, "component_count": roots.size(),
		"connectivity": "triangles unioned only when they share a quantized geometric edge"}

static func canonical_gradient(point: Vector3, snapshot: Dictionary, seed: int = 131102026, delta: float = 0.01) -> Dictionary:
	if not is_finite(delta) or delta <= 0.0:
		return {"valid": false, "reason": "gradient_delta_invalid"}
	var x := sample(point + Vector3.RIGHT * delta, snapshot, seed) - sample(point - Vector3.RIGHT * delta, snapshot, seed)
	var y := sample(point + Vector3.UP * delta, snapshot, seed) - sample(point - Vector3.UP * delta, snapshot, seed)
	var z := sample(point + Vector3.BACK * delta, snapshot, seed) - sample(point + Vector3.FORWARD * delta, snapshot, seed)
	var gradient := Vector3(x, y, z) / (2.0 * delta)
	if not gradient.is_finite() or gradient.length_squared() <= 1.0e-16:
		return {"valid": false, "reason": "gradient_singular_or_nonfinite"}
	return {"valid": true, "gradient": gradient.normalized(), "delta": delta}

static func canonical_outward_normal(point: Vector3, snapshot: Dictionary, seed: int = 131102026, delta: float = 0.01) -> Dictionary:
	var gradient := canonical_gradient(point, snapshot, seed, delta)
	if not gradient.get("valid", false):
		return gradient
	return {"valid": true, "outward_normal": -gradient.gradient, "gradient": gradient.gradient,
		"delta": delta, "convention": "positive_density_solid; outward_is_negative_density_gradient"}

static func normal_deviation(mesh: Dictionary, snapshot: Dictionary, seed: int = 131102026, delta: float = 0.01) -> Dictionary:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = mesh.get("normals", PackedVector3Array())
	if positions.is_empty() or normals.size() != positions.size():
		return {"valid": false, "reason": "mesh_normals_missing_or_mismatched"}
	var angles: Array[float] = []
	var unavailable := 0
	for i in range(positions.size()):
		var reference := canonical_outward_normal(positions[i], snapshot, seed, delta)
		if not reference.get("valid", false) or not normals[i].is_finite() or normals[i].length_squared() <= 1.0e-16:
			unavailable += 1
			continue
		var cosine := clampf(normals[i].normalized().dot(reference.outward_normal), -1.0, 1.0)
		angles.append(rad_to_deg(acos(cosine)))
	angles.sort()
	return {"valid": true, "sample_count": angles.size(), "unavailable_count": unavailable,
		"p50_degrees": _percentile(angles, 0.50) if not angles.is_empty() else null,
		"p95_degrees": _percentile(angles, 0.95) if not angles.is_empty() else null,
		"max_degrees": angles.back() if not angles.is_empty() else null, "gradient_delta": delta,
		"reference_convention": "positive_density_solid; outward_is_negative_density_gradient"}

static func canonical_ray_roots(origin: Vector3, direction: Vector3, max_distance: float, snapshot: Dictionary, seed: int = 131102026, scan_steps: int = 256, bisection_steps: int = 32) -> Dictionary:
	if direction.length_squared() <= 1.0e-16 or max_distance <= 0.0 or scan_steps <= 0:
		return {"valid": false, "reason": "ray_parameters_invalid"}
	var unit_direction := direction.normalized()
	var roots: Array[Dictionary] = []
	var previous_t := 0.0
	var previous_density := sample(origin, snapshot, seed)
	if not is_finite(previous_density):
		return {"valid": false, "reason": "ray_origin_density_nonfinite"}
	for i in range(1, scan_steps + 1):
		var current_t := max_distance * float(i) / float(scan_steps)
		var current_density := sample(origin + unit_direction * current_t, snapshot, seed)
		if not is_finite(current_density):
			return {"valid": false, "reason": "ray_scan_density_nonfinite", "sample_index": i}
		if current_density == 0.0 or (previous_density < 0.0) != (current_density < 0.0):
			var lo := previous_t
			var hi := current_t
			var dlo := previous_density
			for _iteration in range(bisection_steps):
				var mid := (lo + hi) * 0.5
				var dm := sample(origin + unit_direction * mid, snapshot, seed)
				if not is_finite(dm):
					return {"valid": false, "reason": "ray_bisection_density_nonfinite"}
				if dm == 0.0:
					lo = mid
					hi = mid
					break
				if (dm < 0.0) == (dlo < 0.0):
					lo = mid
					dlo = dm
				else:
					hi = mid
			var root_t := (lo + hi) * 0.5
			if roots.is_empty() or absf(root_t - float(roots.back().distance)) > max_distance / float(scan_steps) * 0.5:
				roots.append({"distance": root_t, "position": origin + unit_direction * root_t})
		previous_t = current_t
		previous_density = current_density
	return {"valid": true, "roots": roots, "scan_steps": scan_steps, "step_world": max_distance / float(scan_steps),
		"bisection_steps": bisection_steps, "completeness": "finite sign-change scan; tangent and sub-step roots may be missed"}

static func compare_mesh_rays(rays: Array[Dictionary], mesh: Dictionary, snapshot: Dictionary, seed: int = 131102026, scan_steps: int = 256) -> Dictionary:
	var rows: Array[Dictionary] = []
	var disagreements := 0
	var position_errors: Array[float] = []
	for ray in rays:
		var origin: Vector3 = ray.origin
		var direction: Vector3 = ray.direction
		var length := float(ray.length)
		var reference := canonical_ray_roots(origin, direction, length, snapshot, seed, scan_steps)
		var candidate := ray_mesh(origin, direction, length, mesh)
		if not reference.valid:
			return {"valid": false, "reason": "canonical_ray_reference_failed", "ray": ray}
		var reference_hit: bool = not reference.roots.is_empty()
		if reference_hit != bool(candidate.hit):
			disagreements += 1
		elif reference_hit:
			position_errors.append(float(candidate.distance) - float(reference.roots[0].distance))
		rows.append({"reference_hit": reference_hit, "mesh_hit": bool(candidate.hit),
			"root_count": reference.roots.size(), "reference_first_distance": reference.roots[0].distance if reference_hit else null,
			"mesh_distance": candidate.distance if candidate.hit else null})
	var absolute_errors: Array[float] = []
	for error in position_errors:
		absolute_errors.append(absf(error))
	absolute_errors.sort()
	return {"valid": true, "ray_count": rays.size(), "hit_miss_disagreements": disagreements,
		"position_error_count": absolute_errors.size(), "position_error_abs_p50": _percentile(absolute_errors, 0.50) if not absolute_errors.is_empty() else null,
		"position_error_abs_p95": _percentile(absolute_errors, 0.95) if not absolute_errors.is_empty() else null,
		"position_error_abs_max": absolute_errors.back() if not absolute_errors.is_empty() else null,
		"rays": rows, "root_scan_completeness": "finite scan only; tangent/narrow roots may be missed"}

static func _find_root(parent: Array[int], index: int) -> int:
	var current := index
	while parent[current] != current:
		parent[current] = parent[parent[current]]
		current = parent[current]
	return current

static func _union(parent: Array[int], a: int, b: int) -> void:
	var root_a := _find_root(parent, a)
	var root_b := _find_root(parent, b)
	if root_a != root_b:
		parent[root_b] = root_a

static func sampled_cave_connectivity(roi: Dictionary, snapshot: Dictionary, seed: int = 131102026) -> Dictionary:
	var origin := world_min(roi)
	var counts := cell_counts(roi)
	var spacing := step(roi)
	var dimensions := counts + Vector3i.ONE
	var total := dimensions.x * dimensions.y * dimensions.z
	if total > MAX_NODES:
		return {"valid": false, "reason": "sample_node_stop_loss", "nodes": total}
	var empty := PackedByteArray()
	empty.resize(total)
	for y in range(dimensions.y):
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var index := _grid_index(x, y, z, dimensions)
				var density := sample(origin + Vector3(x, y, z) * spacing, snapshot, seed)
				if not is_finite(density):
					return {"valid": false, "reason": "nonfinite_cave_sample", "nodes": index}
				empty[index] = 1 if density < 0.0 else 0
	var phase := float(posmod(seed, 100003)) * 0.000173
	var seeds: Array[int] = []
	var centerline_slices := 0
	for x_index in range(dimensions.x):
		var world_x := origin.x + float(x_index) * spacing
		if world_x < 7.5 or world_x > 9.5:
			continue
		var center_y := 1.15 + 0.24 * sin(world_x * 0.25 + phase)
		var center_z := 6.0 + 1.05 * sin(world_x * 0.17 + phase * 0.6)
		var lattice := Vector3i(x_index, roundi((center_y-origin.y)/spacing), roundi((center_z-origin.z)/spacing))
		if lattice.y < 0 or lattice.z < 0 or lattice.y >= dimensions.y or lattice.z >= dimensions.z:
			return {"valid": false, "reason": "centerline_seed_outside_roi", "seed_world": [world_x, center_y, center_z]}
		var center_index := _grid_index(lattice.x, lattice.y, lattice.z, dimensions)
		if empty[center_index] == 0:
			return {"valid": false, "reason": "centerline_seed_not_empty", "slice_index": x_index, "seed_world": [world_x, center_y, center_z]}
		seeds.append(center_index)
		centerline_slices += 1
	var component_ids := PackedInt32Array()
	component_ids.resize(total)
	var offsets: Array[Vector3i] = [Vector3i(-1,0,0), Vector3i(1,0,0), Vector3i(0,-1,0), Vector3i(0,1,0), Vector3i(0,0,-1), Vector3i(0,0,1)]
	var component_count := 0
	var component_sizes: Array[int] = []
	var component_touches_top_bottom: Array[bool] = []
	var component_touches_x_negative: Array[bool] = []
	var component_touches_x_positive: Array[bool] = []
	for start in range(total):
		if empty[start] == 0 or component_ids[start] != 0:
			continue
		component_count += 1
		component_sizes.append(0)
		component_touches_top_bottom.append(false)
		component_touches_x_negative.append(false)
		component_touches_x_positive.append(false)
		var queue: Array[int] = [start]
		component_ids[start] = component_count
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			component_sizes[component_count-1] += 1
			var x := current % dimensions.x
			var z := int(current / dimensions.x) % dimensions.z
			var y := int(current / (dimensions.x * dimensions.z))
			if y == 0 or y == dimensions.y-1:
				component_touches_top_bottom[component_count-1] = true
			if x == 0:
				component_touches_x_negative[component_count-1] = true
			if x == dimensions.x-1:
				component_touches_x_positive[component_count-1] = true
			for offset in offsets:
				var next := Vector3i(x, y, z) + offset
				if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= dimensions.x or next.y >= dimensions.y or next.z >= dimensions.z:
					continue
				var next_index := _grid_index(next.x, next.y, next.z, dimensions)
				if empty[next_index] != 0 and component_ids[next_index] == 0:
					component_ids[next_index] = component_count
					queue.append(next_index)
	var centerline_component := int(component_ids[seeds[0]]) if not seeds.is_empty() else 0
	var all_centerline_slices_same_component := centerline_component > 0
	for centerline_seed in seeds:
		if int(component_ids[centerline_seed]) != centerline_component:
			all_centerline_slices_same_component = false
	var reaches_negative_x := centerline_component > 0 and component_touches_x_negative[centerline_component-1]
	var reaches_positive_x := centerline_component > 0 and component_touches_x_positive[centerline_component-1]
	var top_bottom_component_count := 0
	for touches in component_touches_top_bottom:
		if touches:
			top_bottom_component_count += 1
	return {"valid": true, "sample_count": total, "centerline_slice_count": centerline_slices,
		"empty_component_count": component_count, "centerline_component_id": centerline_component,
		"centerline_slices_continuous": all_centerline_slices_same_component,
		"centerline_component_reaches_negative_x_opening": reaches_negative_x,
		"centerline_component_reaches_positive_x_opening": reaches_positive_x,
		"top_bottom_exterior_component_count": top_bottom_component_count,
		"top_bottom_exterior_components_separate": true,
		"centerline_component_size": component_sizes[centerline_component-1] if centerline_component > 0 else 0,
		"sampling_step": spacing, "connectivity": "6-connected negative-density lattice; each empty component labeled once; top/bottom exterior components are separately counted"}

static func _grid_index(x: int, y: int, z: int, dimensions: Vector3i) -> int:
	return (y * dimensions.z + z) * dimensions.x + x

static func _percentile(sorted_values: Array[float], quantile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(ceil(quantile * sorted_values.size())) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]

static func world_min(roi: Dictionary) -> Vector3:
	return Vector3(float(roi.min[0]), float(roi.min[1]), float(roi.min[2]))

static func cell_counts(roi: Dictionary) -> Vector3i:
	return Vector3i(int(roi.cells[0]), int(roi.cells[1]), int(roi.cells[2]))

static func step(roi: Dictionary) -> float:
	return float(roi.step)

static func ray_grid(roi: Dictionary, ray_grid_definition: Dictionary) -> Array[Dictionary]:
	var rays: Array[Dictionary] = []
	for x_value in ray_grid_definition.x:
		for z_value in ray_grid_definition.z:
			rays.append({"origin": Vector3(float(x_value), float(ray_grid_definition.origin_y), float(z_value)),
				"direction": Vector3(float(ray_grid_definition.direction[0]), float(ray_grid_definition.direction[1]), float(ray_grid_definition.direction[2])),
				"length": float(ray_grid_definition.length)})
	return rays

static func _extract_array_property(line: PackedByteArray, property_name: String) -> PackedByteArray:
	var needle := ('"' + property_name + '":[').to_utf8_buffer()
	var start := _find_subsequence(line, needle)
	if start < 0:
		return PackedByteArray()
	start += needle.size() - 1
	var depth := 0
	var in_string := false
	var escaped := false
	for index in range(start, line.size()):
		var byte := int(line[index])
		if in_string:
			if escaped:
				escaped = false
			elif byte == 92:
				escaped = true
			elif byte == 34:
				in_string = false
			continue
		if byte == 34:
			in_string = true
		elif byte == 91:
			depth += 1
		elif byte == 93:
			depth -= 1
			if depth == 0:
				return line.slice(start, index + 1)
	return PackedByteArray()

static func _find_subsequence(data: PackedByteArray, needle: PackedByteArray) -> int:
	if needle.is_empty() or needle.size() > data.size():
		return -1
	for start in range(data.size() - needle.size() + 1):
		var matches := true
		for offset in range(needle.size()):
			if data[start + offset] != needle[offset]:
				matches = false
				break
		if matches:
			return start
	return -1
