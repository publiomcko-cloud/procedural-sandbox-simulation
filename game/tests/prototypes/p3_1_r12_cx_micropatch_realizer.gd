extends "res://tests/prototypes/p3_1_r12_c_c6_multiface_realizer.gd"

const EXPECTED_C6_MESH_SHA := "b5c0e7e44e9d28bc9d58f6982095f2e387d8155026e7f15662612b3176024ec8"
const EXPECTED_C6_VOLUME_SHA := "ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2"
const EXPECTED_RESIDUAL_FIXTURE_SHA := "ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23"
const FIXED_CUTOFF_SQUARED := 1.0e-12
const MAX_CAVITY_LEVEL := 3
const MAX_RESIDUAL_CAVITIES := 3
const MAX_PATCH_TRIANGLES := 64
const MAX_SEARCH_STATES := 4096
const MAX_RETAINED_SOLUTIONS := 32
const MAX_SEARCH_USEC := 10000000
const MAX_REALIZE_USEC := 30000000
const TRIANGLE_EPSILON := 1.0e-9
const MAX_SUPPORT_CANDIDATES := 0
const MAX_SELECTED_SUPPORTS := 0

var _search_started_usec: int = 0
var _search_state_count: int = 0
var _cavity_search_state_count: int = 0
var _locked_triplets: Dictionary = {}
var _required_arc_keys: Dictionary = {}
var _root_positions: Dictionary = {}

func realize_cx(graph: Dictionary, values: PackedFloat32Array, roi: Dictionary, expected_topology_sha: String, expected_graph_fingerprint_sha: String, residual_fixture: Dictionary, snapshot: Dictionary) -> Dictionary:
	var begin_usec: int = Time.get_ticks_usec()
	var result: Dictionary = super.realize(graph, values, roi, expected_topology_sha, expected_graph_fingerprint_sha)
	if not bool(result.get("valid", false)):
		return {"valid": false, "cx_algorithm_started": false, "reason": "cx_c6_base_realizer_invalid", "details": result}
	var fixture_error: String = _validate_residual_fixture(residual_fixture, result)
	if not fixture_error.is_empty():
		return {"valid": false, "cx_algorithm_started": false, "reason": fixture_error, "details": {"expected_fixture_sha256": EXPECTED_RESIDUAL_FIXTURE_SHA}}
	var residuals: Array = result.get("cutoff_rejections", [])
	if residuals.size() != 3:
		return {"valid": false, "cx_algorithm_started": false, "reason": "cx_unexpected_c6_cutoff_count", "details": {"count": residuals.size()}}
	var built: Dictionary = _build_triangles(result, residual_fixture)
	if not bool(built.get("valid", false)):
		return {"valid": false, "cx_algorithm_started": false, "reason": "cx_c6_triangle_reconstruction_failed", "details": built}
	var triangles: Array[Dictionary] = built.triangles
	_root_positions = built.root_positions
	var baseline_emitted: Array[Dictionary] = _accepted_triangle_rows(triangles)
	if _mesh_sha(_mesh_from_triangles(baseline_emitted)) != EXPECTED_C6_MESH_SHA or result.get("mesh_sha256", "") != EXPECTED_C6_MESH_SHA:
		return {"valid": false, "cx_algorithm_started": false, "reason": "cx_reconstructed_c6_mesh_hash_mismatch", "expected": EXPECTED_C6_MESH_SHA, "reconstructed": _mesh_sha(_mesh_from_triangles(baseline_emitted)), "realizer": result.get("mesh_sha256", "")}
	_required_arc_keys.clear()
	for arc_value in result.get("arc_map", []):
		var arc: Dictionary = arc_value
		var endpoints: Array = arc.get("root_ids", [])
		if endpoints.size() == 2:
			_required_arc_keys[_edge_key(String(endpoints[0]), String(endpoints[1]))] = true
	_locked_triplets = _derive_locked_triplets(result.get("applied_flips", []), _root_positions)
	var adjacency: Dictionary = _adjacency(triangles)
	_orient_rejected_triangles(triangles, adjacency)
	var original_triangles: Array[Dictionary] = triangles.duplicate(true)
	var groups: Array[Array] = _overlapping_defect_groups(residual_fixture.get("residuals", []), adjacency)
	if groups.is_empty():
		return {"valid": false, "cx_algorithm_started": false, "reason": "cx_residual_cavity_set_empty"}
	if groups.size() > MAX_RESIDUAL_CAVITIES:
		return {"valid": false, "cx_algorithm_started": false, "reason": "cx_residual_cavity_count_cap_exceeded", "cavity_count": groups.size(), "cap": MAX_RESIDUAL_CAVITIES, "limits": _limits()}
	_search_started_usec = Time.get_ticks_usec()
	_search_state_count = 0
	_cavity_search_state_count = 0
	var patches: Array[Dictionary] = []
	var replacements: Dictionary = {}
	var cx_algorithm_started: bool = false
	for group_index in range(groups.size()):
		var group: Array = groups[group_index]
		cx_algorithm_started = true
		if group_index == 0:
			print("R12CX_LOCAL_PATCH_SEARCH_BEGIN " + JSON.stringify({"residual_cavities": groups.size(), "limits": _limits(), "residual_fixture_sha256": EXPECTED_RESIDUAL_FIXTURE_SHA}))
		var level_result: Dictionary = _find_smallest_patch(group, triangles, adjacency, snapshot)
		if not bool(level_result.get("valid", false)):
			return {"valid": false, "cx_algorithm_started": true, "reason": "cx_bounded_patch_search_failed", "details": {"group_index": group_index, "group": group, "search": level_result, "limits": _limits()}}
		var patch_ids: Array = level_result.get("patch_triangle_ids", [])
		for triangle_id in patch_ids:
			replacements[String(triangle_id)] = true
		var patch_row: Dictionary = level_result.duplicate(true)
		patch_row["group_index"] = group_index
		patches.append(patch_row)
	var final_triangles: Array[Dictionary] = []
	for triangle in triangles:
		if not replacements.has(String(triangle.get("triangle_id", ""))):
			final_triangles.append(triangle)
	for patch in patches:
		for triangle_value in patch.get("replacement_triangles", []):
			final_triangles.append(triangle_value)
	var validation: Dictionary = _validate_final_mesh(final_triangles, triangles, patches, result, roi, snapshot)
	if not bool(validation.get("valid", false)):
		return {"valid": false, "cx_algorithm_started": true, "reason": "cx_final_geometry_validation_failed", "details": validation, "patches": patches, "limits": _limits()}
	var rebuilt_mesh: Dictionary = _mesh_from_triangles(final_triangles)
	var topology: Dictionary = Core.topology(rebuilt_mesh, Core.world_min(roi), Core.world_min(roi) + Vector3(Core.cell_counts(roi)) * Core.step(roi))
	var c6_paths: Dictionary = _validate_c6_paths(final_triangles, result.get("applied_flips", []))
	var obligations: Dictionary = _validate_required_arcs(final_triangles, result.get("arc_map", []), result.get("applied_flips", []))
	var root_integrity: bool = _root_coordinates_unchanged(original_triangles, final_triangles, _root_positions)
	var all_cutoffs: Array[Dictionary] = _cutoff_rows(final_triangles)
	var topology_complete: bool = all_cutoffs.is_empty() and int(obligations.get("missing", -1)) == 0 and int(obligations.get("nonmanifold", -1)) == 0 and bool(c6_paths.get("valid", false))
	var mesh_complete: bool = topology_complete and int(topology.get("internal_open_edges", -1)) == 0 and int(topology.get("nonmanifold_edges", -1)) == 0 and int(topology.get("winding_inconsistencies", -1)) == 0
	var local_search_complete: bool = true
	for patch in patches:
		if not bool(patch.get("search_complete", false)): local_search_complete = false
	result["hypothesis"] = "CX_BOUNDED_RESIDUAL_CAVITY_MICROPATCH"
	result["cx_algorithm_started"] = cx_algorithm_started
	result["mesh"] = rebuilt_mesh
	result["mesh_sha256"] = _mesh_sha(rebuilt_mesh)
	result["mesh_topology"] = topology
	result["emitted_triangles"] = _emitted_rows(final_triangles)
	result["cutoff_rejections"] = all_cutoffs
	result["unresolved_obligations"] = [] if topology_complete else result.get("unresolved_obligations", [])
	result["required_adjacency_missing_count"] = int(obligations.get("missing", -1))
	result["required_adjacency_nonmanifold_count"] = int(obligations.get("nonmanifold", -1))
	result["required_adjacency_obligations"] = obligations.get("rows", [])
	result["required_topology_complete"] = topology_complete
	result["geometry_realization_complete"] = mesh_complete
	result["winding_valid"] = int(topology.get("winding_inconsistencies", -1)) == 0
	result["cx_patch_records"] = patches
	result["cx_residual_fixture_sha256"] = EXPECTED_RESIDUAL_FIXTURE_SHA
	result["cx_local_search_limits"] = _limits()
	result["cx_local_search_nodes"] = _search_state_count
	result["cx_local_search_complete"] = local_search_complete
	result["cx_support_vertex_count"] = 0
	result["cx_support_candidate_count"] = 0
	result["cx_support_provenance"] = []
	result["cx_support_provenance_sha256"] = Core.sha256("[]".to_utf8_buffer())
	result["cx_changed_triangle_ids"] = _changed_triangle_ids(original_triangles, final_triangles)
	result["cx_triangle_count"] = final_triangles.size()
	result["geometry_triangle_count"] = final_triangles.size()
	result["geometry_vertex_count"] = final_triangles.size() * 3
	result["cx_field_diagnostics"] = _field_diagnostics(patches, snapshot)
	result["cx_preserved_c6_paths"] = c6_paths
	result["cx_preserved_topology_arcs"] = obligations
	result["cx_root_coordinates_unchanged"] = root_integrity
	result["cx_build_usec"] = Time.get_ticks_usec() - begin_usec
	result["geometry_complete"] = mesh_complete and root_integrity and local_search_complete
	result["topology_signature_match"] = topology_complete and bool(result.get("topology_signature_match", false))
	result["minimum_cross_squared"] = _minimum_cross_squared(final_triangles)
	if result.cx_build_usec > MAX_REALIZE_USEC:
		result["geometry_complete"] = false
		result["realizer_failure_reason"] = "cx_realize_time_cap_exceeded"
	return result

func search_patch_for_test(triangles: Array[Dictionary], locked_edges: Array[String] = [], max_states: int = MAX_SEARCH_STATES) -> Dictionary:
	_root_positions.clear()
	_required_arc_keys.clear()
	_locked_triplets.clear()
	_search_started_usec = Time.get_ticks_usec()
	_search_state_count = 0
	_cavity_search_state_count = 0
	for edge in locked_edges: _required_arc_keys[edge] = true
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		var points: Array = triangle.get("points", [])
		if ids.size() != 3 or points.size() != 3: return {"valid": false, "reason": "synthetic_triangle_arity_invalid"}
		for index in range(3): _root_positions[String(ids[index])] = points[index]
	return _search_patch(triangles, max_states)

func _validate_residual_fixture(fixture: Dictionary, base: Dictionary) -> String:
	if fixture.get("schema", "") != "P3.1.R12CX.ResidualCutoffFixture.v1": return "cx_residual_fixture_schema_invalid"
	if fixture.get("c6_artifact_sha256", "") != "0c6ae06d368f1a789ddc16fae429700c109d09fc019082fe6356c58fee12c6de": return "cx_residual_fixture_c6_pin_invalid"
	if fixture.get("c6_mesh_sha256", "") != EXPECTED_C6_MESH_SHA or base.get("mesh_sha256", "") != EXPECTED_C6_MESH_SHA: return "cx_c6_mesh_identity_mismatch"
	if fixture.get("volume_sha256", "") != EXPECTED_C6_VOLUME_SHA: return "cx_volume_pin_invalid"
	if fixture.get("residual_triangle_count", -1) != 3: return "cx_residual_count_invalid"
	if EXPECTED_RESIDUAL_FIXTURE_SHA == "PENDING_FIXTURE_SHA": return "cx_residual_fixture_pin_not_finalized"
	return ""

func _build_triangles(geometry: Dictionary, fixture: Dictionary) -> Dictionary:
	var root_positions: Dictionary = {}
	for root_value in geometry.get("root_map", []):
		var root: Dictionary = root_value
		var root_id: String = String(root.get("root_id", ""))
		var position_value: Variant = root.get("position", null)
		var position: Vector3
		if position_value is Vector3:
			position = position_value
		elif position_value is Array and (position_value as Array).size() == 3:
			position = _array_vec3(position_value)
		else:
			return {"valid": false, "reason": "cx_root_position_representation_invalid", "root_id": root_id}
		if root_id.is_empty() or not position.is_finite(): return {"valid": false, "reason": "cx_root_position_invalid", "root_id": root_id}
		root_positions[root_id] = position
	var triangles: Array[Dictionary] = []
	var ordinal_by_polygon: Dictionary = {}
	for emitted_value in geometry.get("emitted_triangles", []):
		var emitted: Dictionary = emitted_value
		var polygon_id: String = String(emitted.get("polygon_id", ""))
		var root_ids: Array = emitted.get("root_ids", [])
		var points: Array[Vector3] = _points_for_ids(root_ids, root_positions)
		if points.size() != 3: return {"valid": false, "reason": "cx_emitted_triangle_root_invalid", "polygon_id": polygon_id}
		var ordinal: int = int(ordinal_by_polygon.get(polygon_id, 0))
		ordinal_by_polygon[polygon_id] = ordinal + 1
		var triangle_id: String = "C6|" + polygon_id + "|" + str(ordinal) + "|" + _triplet_key(root_ids)
		triangles.append(_triangle(triangle_id, polygon_id, root_ids, points, String(emitted.get("construction", "C6")), false))
	var residual_rows: Array = fixture.get("residuals", [])
	var c6_rejections: Array = geometry.get("cutoff_rejections", [])
	if c6_rejections.size() != residual_rows.size(): return {"valid": false, "reason": "cx_base_residual_count_mismatch"}
	for residual_value in residual_rows:
		var residual: Dictionary = residual_value
		var reject: Dictionary = residual.get("rejection", {})
		var triangle_id: String = String(residual.get("triangle_id", ""))
		var polygon_id: String = String(residual.get("source_polygon_id", ""))
		var root_ids: Array = residual.get("triangle_root_ids", [])
		var points: Array[Vector3] = _points_for_ids(root_ids, root_positions)
		if triangle_id.is_empty() or polygon_id.is_empty() or points.size() != 3: return {"valid": false, "reason": "cx_fixture_residual_invalid", "triangle_id": triangle_id}
		var matched: bool = false
		for c6_reject_value in c6_rejections:
			var c6_reject: Dictionary = c6_reject_value
			if String(c6_reject.get("polygon_id", "")) == polygon_id and _same_id_set(c6_reject.get("triangle_root_ids", []), root_ids): matched = true
		if not matched: return {"valid": false, "reason": "cx_fixture_to_base_rejection_mismatch", "triangle_id": triangle_id}
		var residual_triangle: Dictionary = _triangle(triangle_id, polygon_id, root_ids, points, "C6_REJECTED_CUTOFF", true)
		var observed_cross: float = float(reject.get("cross_squared", -1.0))
		if observed_cross < 0.0 or absf(float(residual_triangle.cross_squared) - observed_cross) > maxf(1.0e-24, absf(observed_cross) * 1.0e-12):
			return {"valid": false, "reason": "cx_fixture_cutoff_area_mismatch", "triangle_id": triangle_id, "observed": observed_cross, "recomputed": residual_triangle.cross_squared}
		triangles.append(residual_triangle)
	return {"valid": true, "triangles": triangles, "root_positions": root_positions}

func _overlapping_defect_groups(residuals: Array, adjacency: Dictionary) -> Array[Array]:
	var groups: Array[Array] = []
	for residual_value in residuals:
		var residual: Dictionary = residual_value
		groups.append([String(residual.get("triangle_id", ""))])
	var changed: bool = true
	while changed:
		changed = false
		for i in range(groups.size()):
			for j in range(i + 1, groups.size()):
				var a: Dictionary = {}
				var b: Dictionary = {}
				for seed in groups[i]:
					for id in _radius_ids(String(seed), adjacency, 2): a[String(id)] = true
				for seed in groups[j]:
					for id in _radius_ids(String(seed), adjacency, 2): b[String(id)] = true
				var overlap: bool = false
				for id in a.keys():
					if b.has(id): overlap = true; break
				if overlap:
					groups[i].append_array(groups[j])
					groups.remove_at(j)
					changed = true
					break
			if changed: break
	for group in groups:
		group.sort()
	return groups

func _find_smallest_patch(seeds: Array, all_triangles: Array[Dictionary], adjacency: Dictionary, snapshot: Dictionary) -> Dictionary:
	_cavity_search_state_count = 0
	for level in range(MAX_CAVITY_LEVEL + 1):
		var patch_ids_map: Dictionary = {}
		for seed in seeds:
			for triangle_id in _radius_ids(String(seed), adjacency, level): patch_ids_map[String(triangle_id)] = true
		if patch_ids_map.size() > MAX_PATCH_TRIANGLES:
			return {"valid": false, "reason": "cx_patch_triangle_cap_exceeded", "level": level, "count": patch_ids_map.size()}
		var patch: Array[Dictionary] = []
		for triangle in all_triangles:
			if patch_ids_map.has(String(triangle.triangle_id)): patch.append(triangle)
		var boundary: Dictionary = _boundary_state(patch)
		if level == 0 or not bool(boundary.get("valid", false)): continue
		var search: Dictionary = _search_patch(patch, MAX_SEARCH_STATES)
		if bool(search.get("valid", false)):
			search["level"] = level
			search["patch_triangle_ids"] = _sorted_keys(patch_ids_map)
			search["boundary_signature"] = boundary.get("signature", "")
			search["support_count"] = 0
			search["source_triangle_count"] = patch.size()
			search["field_surface_diagnostics"] = _surface_diagnostics(search.get("replacement_triangles", []), snapshot)
			return search
		if not bool(search.get("complete", true)):
			search["reason"] = "cx_bounded_search_partial"
			search["level"] = level
			return search
	return {"valid": false, "reason": "cx_no_complete_patch_within_l3", "max_level": MAX_CAVITY_LEVEL, "search_nodes": _search_state_count, "limits": _limits()}

func _search_patch(input_patch: Array, max_states: int) -> Dictionary:
	if input_patch.size() > MAX_PATCH_TRIANGLES: return {"valid": false, "reason": "cx_patch_triangle_cap_exceeded", "complete": true, "count": input_patch.size(), "cap": MAX_PATCH_TRIANGLES}
	var initial: Array[Dictionary] = []
	for value in input_patch:
		if not value is Dictionary: return {"valid": false, "reason": "cx_patch_triangle_not_dictionary"}
		initial.append((value as Dictionary).duplicate(true))
	var initial_boundary: Dictionary = _boundary_state(initial)
	if not bool(initial_boundary.get("valid", false)): return {"valid": false, "reason": "cx_patch_boundary_invalid", "boundary": initial_boundary}
	var queue: Array[Dictionary] = [{"triangles": initial, "flips": []}]
	var cursor: int = 0
	var seen: Dictionary = {_state_key(initial): true}
	var solutions: Array[Dictionary] = []
	var solution_depth: int = -1
	while cursor < queue.size():
		if _cavity_search_state_count >= max_states or Time.get_ticks_usec() - _search_started_usec > MAX_SEARCH_USEC:
			return {"valid": false, "reason": "cx_search_bound_exhausted", "complete": false, "nodes": _search_state_count, "cavity_nodes": _cavity_search_state_count, "queue_count": queue.size() - cursor, "solutions_retained": solutions.size()}
		var state: Dictionary = queue[cursor]
		cursor += 1
		_search_state_count += 1
		_cavity_search_state_count += 1
		var current: Array = state.triangles
		var flips: Array = state.flips
		if _cutoff_triangles(current).is_empty():
			if solution_depth < 0: solution_depth = flips.size()
			if flips.size() == solution_depth:
				solutions.append({"triangles": current, "flips": flips})
				if solutions.size() >= MAX_RETAINED_SOLUTIONS: break
			continue
		if solution_depth >= 0 and flips.size() >= solution_depth: continue
		var edges: Array[Dictionary] = _candidate_edges(current)
		for edge in edges:
			if _required_arc_keys.has(String(edge.key)): continue
			var pair: Array = edge.triangle_indices
			if pair.size() != 2: continue
			var first: Dictionary = current[int(pair[0])]
			var second: Dictionary = current[int(pair[1])]
			if _locked_triplets.has(_triplet_key(first.root_ids)) or _locked_triplets.has(_triplet_key(second.root_ids)): continue
			if not _edge_touches_cutoff(edge, current): continue
			var proposal: Dictionary = _flip_pair(first, second, String(edge.key), current)
			if not bool(proposal.get("valid", false)): continue
			var next: Array[Dictionary] = current.duplicate(true)
			var index_a: int = int(proposal.get("index_a", -1))
			var index_b: int = int(proposal.get("index_b", -1))
			if index_a < 0 or index_b < 0: continue
			var high: int = maxi(index_a, index_b)
			var low: int = mini(index_a, index_b)
			next.remove_at(high)
			next.remove_at(low)
			var insert_index: int = mini(index_a, index_b)
			next.insert(insert_index, proposal.get("triangle_a", {}))
			next.insert(insert_index + 1, proposal.get("triangle_b", {}))
			var after_boundary: Dictionary = _boundary_state(next)
			if not bool(after_boundary.get("valid", false)) or String(after_boundary.get("signature", "")) != String(initial_boundary.get("signature", "")): continue
			var next_key: String = _state_key(next)
			if seen.has(next_key): continue
			seen[next_key] = true
			var next_flips: Array = flips.duplicate(true)
			next_flips.append({"removed_edge": edge.key, "new_edge": proposal.get("new_edge", ""), "parent_triangles": [first.triangle_id, second.triangle_id], "replacement_triangles": [proposal.triangle_a.triangle_id, proposal.triangle_b.triangle_id], "cross_squared": [proposal.triangle_a.cross_squared, proposal.triangle_b.cross_squared]})
			queue.append({"triangles": next, "flips": next_flips})
	if solutions.is_empty(): return {"valid": false, "reason": "cx_no_cutoff_free_state_within_bounds", "complete": cursor >= queue.size(), "nodes": _search_state_count, "seen_states": seen.size(), "max_states": max_states}
	var selected: Dictionary = _select_solution(solutions)
	var complete: bool = cursor >= queue.size() and solutions.size() < MAX_RETAINED_SOLUTIONS
	return {"valid": true, "complete": complete, "replacement_triangles": selected.triangles, "flips": selected.flips, "search_nodes": _search_state_count, "cavity_search_nodes": _cavity_search_state_count, "search_complete": complete, "candidate_solutions": solutions.size(), "retained_solution_cap_hit": solutions.size() >= MAX_RETAINED_SOLUTIONS, "boundary_preserved": true, "minimum_cross_squared": _minimum_cross_squared(selected.triangles), "search_usec": Time.get_ticks_usec() - _search_started_usec}

func _candidate_edges(triangles: Array) -> Array[Dictionary]:
	var owners: Dictionary = {}
	for index in range(triangles.size()):
		var triangle: Dictionary = triangles[index]
		var ids: Array = triangle.root_ids
		for edge_index in range(3):
			var a_id: String = String(ids[edge_index])
			var b_id: String = String(ids[(edge_index + 1) % 3])
			var key: String = _edge_key(a_id, b_id)
			if not owners.has(key): owners[key] = []
			owners[key].append({"triangle_index": index, "a": a_id, "b": b_id})
	var result: Array[Dictionary] = []
	var keys: Array[String] = _sorted_keys(owners)
	for key in keys:
		var rows: Array = owners[key]
		if rows.size() == 2:
			result.append({"key": key, "triangle_indices": [int(rows[0].triangle_index), int(rows[1].triangle_index)], "directions": [[rows[0].a, rows[0].b], [rows[1].a, rows[1].b]]})
	return result

func _edge_touches_cutoff(edge: Dictionary, triangles: Array) -> bool:
	for index in edge.triangle_indices:
		var triangle: Dictionary = triangles[int(index)]
		if bool(triangle.get("rejected", false)) or float(triangle.get("cross_squared", INF)) <= FIXED_CUTOFF_SQUARED: return true
	return false

func _flip_pair(first: Dictionary, second: Dictionary, shared_edge: String, triangles: Array) -> Dictionary:
	var ids_a: Array = first.root_ids
	var ids_b: Array = second.root_ids
	var shared_u: String = ""
	var shared_v: String = ""
	var opposite_a: String = ""
	var opposite_b: String = ""
	for index in range(3):
		var u_id: String = String(ids_a[index])
		var v_id: String = String(ids_a[(index + 1) % 3])
		if ids_b.has(v_id) and ids_b.has(u_id):
			var opposite_index: int = ids_a.find(u_id)
			for candidate in ids_a:
				if String(candidate) != u_id and String(candidate) != v_id: opposite_a = String(candidate)
			for candidate in ids_b:
				if String(candidate) != u_id and String(candidate) != v_id: opposite_b = String(candidate)
			if opposite_index >= 0: shared_u = u_id; shared_v = v_id
			break
	if shared_u.is_empty() or shared_v.is_empty() or opposite_a.is_empty() or opposite_b.is_empty(): return {"valid": false, "reason": "cx_shared_edge_orientation_invalid"}
	if shared_edge != _edge_key(shared_u, shared_v): return {"valid": false, "reason": "cx_shared_edge_identity_mismatch"}
	var p: Vector3 = _root_positions[opposite_a]
	var q: Vector3 = _root_positions[opposite_b]
	var u: Vector3 = _root_positions[shared_u]
	var v: Vector3 = _root_positions[shared_v]
	var normal_a: Vector3 = first.get("normal", Vector3.ZERO)
	var normal_b: Vector3 = second.get("normal", Vector3.ZERO)
	var reference_normal: Vector3 = normal_a + normal_b
	if not reference_normal.is_finite() or reference_normal.length_squared() <= 1.0e-20: return {"valid": false, "reason": "cx_reference_winding_invalid"}
	reference_normal = reference_normal.normalized()
	if not _convex_quad(u, v, p, q, reference_normal): return {"valid": false, "reason": "cx_quad_not_convex_in_local_surface"}
	var new_edge: String = _edge_key(opposite_a, opposite_b)
	if _required_arc_keys.has(new_edge): return {"valid": false, "reason": "cx_new_diagonal_is_topology_arc"}
	for triangle in triangles:
		if triangle == first or triangle == second: continue
		if _triangle_has_edge(triangle, opposite_a, opposite_b): return {"valid": false, "reason": "cx_new_diagonal_already_present"}
	var row_a: Dictionary = _triangle("CX|" + _triplet_key([opposite_a, shared_u, opposite_b]), String(first.get("polygon_id", "")) + "+" + String(second.get("polygon_id", "")), [opposite_a, shared_u, opposite_b], [p, u, q], "R12CX_LOCAL_FLIP", false)
	var row_b: Dictionary = _triangle("CX|" + _triplet_key([opposite_a, opposite_b, shared_v]), String(first.get("polygon_id", "")) + "+" + String(second.get("polygon_id", "")), [opposite_a, opposite_b, shared_v], [p, q, v], "R12CX_LOCAL_FLIP", false)
	if float(row_a.cross_squared) <= FIXED_CUTOFF_SQUARED or float(row_b.cross_squared) <= FIXED_CUTOFF_SQUARED: return {"valid": false, "reason": "cx_replacement_below_fixed_cutoff", "cross_squared": [row_a.cross_squared, row_b.cross_squared]}
	if not row_a.normal.is_finite() or not row_b.normal.is_finite() or row_a.normal.dot(reference_normal) <= 0.0 or row_b.normal.dot(reference_normal) <= 0.0: return {"valid": false, "reason": "cx_replacement_winding_invalid"}
	return {"valid": true, "index_a": triangles.find(first), "index_b": triangles.find(second), "triangle_a": row_a, "triangle_b": row_b, "new_edge": new_edge}

func _convex_quad(u: Vector3, v: Vector3, p: Vector3, q: Vector3, normal: Vector3) -> bool:
	var side_p: float = normal.dot((v - u).cross(p - u))
	var side_q: float = normal.dot((v - u).cross(q - u))
	var side_u: float = normal.dot((q - p).cross(u - p))
	var side_v: float = normal.dot((q - p).cross(v - p))
	return is_finite(side_p) and is_finite(side_q) and is_finite(side_u) and is_finite(side_v) and side_p * side_q < 0.0 and side_u * side_v < 0.0

func _boundary_state(triangles: Array) -> Dictionary:
	var edges: Dictionary = {}
	for triangle in triangles:
		if not triangle is Dictionary: return {"valid": false, "reason": "cx_boundary_triangle_invalid"}
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3: return {"valid": false, "reason": "cx_boundary_triangle_arity_invalid"}
		for index in range(3):
			var a_id: String = String(ids[index])
			var b_id: String = String(ids[(index + 1) % 3])
			var key: String = _edge_key(a_id, b_id)
			if not edges.has(key): edges[key] = []
			edges[key].append({"a": a_id, "b": b_id})
	var boundary: Array[String] = []
	var indegree: Dictionary = {}
	var outdegree: Dictionary = {}
	for key in edges.keys():
		var rows: Array = edges[key]
		if rows.size() > 2: return {"valid": false, "reason": "cx_patch_nonmanifold_edge", "edge": key, "incidence": rows.size()}
		if rows.size() == 1:
			var a_id: String = String(rows[0].a)
			var b_id: String = String(rows[0].b)
			boundary.append(a_id + "->" + b_id)
			outdegree[a_id] = int(outdegree.get(a_id, 0)) + 1
			indegree[b_id] = int(indegree.get(b_id, 0)) + 1
	if boundary.size() < 3: return {"valid": false, "reason": "cx_patch_boundary_too_small"}
	for vertex in outdegree.keys():
		if int(outdegree[vertex]) != 1 or int(indegree.get(vertex, 0)) != 1: return {"valid": false, "reason": "cx_patch_boundary_not_single_cycle", "vertex": vertex}
	if indegree.size() != outdegree.size(): return {"valid": false, "reason": "cx_patch_boundary_degree_mismatch"}
	var successor: Dictionary = {}
	for directed_edge in boundary:
		var split: PackedStringArray = directed_edge.split("->")
		if split.size() != 2: return {"valid": false, "reason": "cx_patch_boundary_edge_invalid"}
		successor[split[0]] = split[1]
	var visited: Dictionary = {}
	var start_vertex: String = String(outdegree.keys()[0])
	var cursor: String = start_vertex
	while not visited.has(cursor):
		visited[cursor] = true
		if not successor.has(cursor): return {"valid": false, "reason": "cx_patch_boundary_cycle_open"}
		cursor = String(successor[cursor])
	if cursor != start_vertex or visited.size() != outdegree.size(): return {"valid": false, "reason": "cx_patch_boundary_multiple_cycles"}
	boundary.sort()
	return {"valid": true, "signature": Core.sha256(JSON.stringify(boundary).to_utf8_buffer()), "directed_edges": boundary, "edge_count": boundary.size(), "vertex_count": outdegree.size()}

func _state_key(triangles: Array) -> String:
	var keys: Array[String] = []
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		keys.append(_oriented_triplet_key(ids))
	keys.sort()
	return "\n".join(keys)

func _oriented_triplet_key(ids: Array) -> String:
	if ids.size() != 3: return "INVALID"
	var a: String = String(ids[0]); var b: String = String(ids[1]); var c: String = String(ids[2])
	var rotations: Array[String] = [a + "|" + b + "|" + c, b + "|" + c + "|" + a, c + "|" + a + "|" + b]
	rotations.sort()
	return rotations[0]

func _triplet_key(ids: Array) -> String:
	var values: Array[String] = []
	for id in ids: values.append(String(id))
	values.sort()
	return "|".join(values)

func _adjacency(triangles: Array[Dictionary]) -> Dictionary:
	var edge_owners: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		for index in range(ids.size()):
			var edge: String = _edge_key(String(ids[index]), String(ids[(index + 1) % ids.size()]))
			if not edge_owners.has(edge): edge_owners[edge] = []
			edge_owners[edge].append(String(triangle.get("triangle_id", "")))
	var adjacency: Dictionary = {}
	for triangle in triangles: adjacency[String(triangle.triangle_id)] = {}
	for owners_value in edge_owners.values():
		var owners: Array = owners_value
		for i in range(owners.size()):
			for j in range(i + 1, owners.size()):
				adjacency[String(owners[i])][String(owners[j])] = true
				adjacency[String(owners[j])][String(owners[i])] = true
	return adjacency

func _orient_rejected_triangles(triangles: Array[Dictionary], adjacency: Dictionary) -> void:
	for triangle in triangles:
		if not bool(triangle.get("rejected", false)): continue
		var normal_sum: Vector3 = Vector3.ZERO
		for neighbor_id in adjacency.get(String(triangle.get("triangle_id", "")), {}).keys():
			var neighbor: Dictionary = _triangle_by_id(triangles, String(neighbor_id))
			if not neighbor.is_empty() and not bool(neighbor.get("rejected", false)): normal_sum += neighbor.get("normal", Vector3.ZERO)
		if normal_sum.length_squared() <= 1.0e-20: continue
		var normal: Vector3 = triangle.get("normal", Vector3.ZERO)
		if normal.dot(normal_sum) < 0.0:
			var ids: Array = triangle.root_ids
			var points: Array = triangle.points
			triangle.root_ids = [ids[0], ids[2], ids[1]]
			triangle.points = [points[0], points[2], points[1]]
			triangle.normal = -normal

func _radius_ids(seed_id: String, adjacency: Dictionary, radius: int) -> Array[String]:
	var distances: Dictionary = {seed_id: 0}
	var queue: Array[String] = [seed_id]
	var cursor: int = 0
	while cursor < queue.size():
		var current: String = queue[cursor]; cursor += 1
		var distance: int = int(distances[current])
		if distance >= radius: continue
		for neighbor in adjacency.get(current, {}).keys():
			var id: String = String(neighbor)
			if distances.has(id): continue
			distances[id] = distance + 1
			queue.append(id)
	var result: Array[String] = []
	for id in distances.keys(): result.append(String(id))
	result.sort()
	return result

func _cutoff_triangles(triangles: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for triangle in triangles:
		var cross_squared: float = float(triangle.get("cross_squared", INF))
		if not is_finite(cross_squared) or cross_squared <= FIXED_CUTOFF_SQUARED: rows.append(triangle)
	return rows

func _select_solution(solutions: Array[Dictionary]) -> Dictionary:
	var ordered: Array[Dictionary] = solutions.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_min: float = _minimum_cross_squared(a.triangles)
		var b_min: float = _minimum_cross_squared(b.triangles)
		if a_min != b_min: return a_min > b_min
		return _state_key(a.triangles) < _state_key(b.triangles)
	)
	return ordered[0]

func _triangle(triangle_id: String, polygon_id: String, root_ids: Array, points: Array, construction: String, rejected: bool, expected_cross: float = -1.0) -> Dictionary:
	var a: Vector3 = points[0]; var b: Vector3 = points[1]; var c: Vector3 = points[2]
	var cross: Vector3 = (b - a).cross(c - a)
	var cross_squared: float = cross.length_squared()
	return {"triangle_id": triangle_id, "polygon_id": polygon_id, "source_polygon_ids": [polygon_id], "root_ids": root_ids.duplicate(), "points": points.duplicate(), "normal": cross.normalized() if cross.length_squared() > 0.0 else Vector3.ZERO, "cross_squared": cross_squared, "expected_cross_squared": expected_cross, "rejected": rejected, "construction": construction}

func _points_for_ids(root_ids: Array, roots: Dictionary) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for value in root_ids:
		var id: String = String(value)
		if not roots.has(id): return []
		points.append(roots[id])
	return points

func _validate_final_mesh(final_triangles: Array[Dictionary], original_triangles: Array[Dictionary], patches: Array[Dictionary], geometry: Dictionary, roi: Dictionary, snapshot: Dictionary) -> Dictionary:
	var counts: Dictionary = _edge_incidence(final_triangles)
	for key in counts.keys():
		if int(counts[key]) > 2: return {"valid": false, "reason": "cx_final_nonmanifold_edge", "edge": key, "count": counts[key]}
	for patch in patches:
		var ids: Array = patch.get("patch_triangle_ids", [])
		var before: Array[Dictionary] = []
		for triangle in original_triangles:
			if ids.has(String(triangle.triangle_id)): before.append(triangle)
		var after: Array[Dictionary] = patch.get("replacement_triangles", [])
		var before_boundary: Dictionary = _boundary_state(before)
		var after_boundary: Dictionary = _boundary_state(after)
		if not bool(before_boundary.get("valid", false)) or not bool(after_boundary.get("valid", false)) or before_boundary.signature != after_boundary.signature:
			return {"valid": false, "reason": "cx_patch_boundary_changed", "before": before_boundary, "after": after_boundary}
		if not _self_intersections_clear(after, final_triangles): return {"valid": false, "reason": "cx_patch_self_intersection"}
		if _new_t_junction_count(after, final_triangles) > 0: return {"valid": false, "reason": "cx_patch_t_junction"}
		var changed_ids: Array = []
		for old_triangle in before: changed_ids.append(String(old_triangle.triangle_id))
		patch["changed_source_triangle_ids"] = changed_ids
		patch["surface_diagnostics"] = _surface_diagnostics(after, snapshot)
	var original_root_ids: Dictionary = {}
	for triangle in original_triangles:
		for id in triangle.root_ids: original_root_ids[String(id)] = true
	for triangle in final_triangles:
		for id in triangle.root_ids:
			if not original_root_ids.has(String(id)): return {"valid": false, "reason": "cx_new_topology_root_added", "root_id": id}
	return {"valid": true, "triangle_count": final_triangles.size(), "edge_incidence": counts, "source_root_count": original_root_ids.size(), "topology_obligation_count": geometry.get("arc_map", []).size(), "surface_diagnostics": _surface_diagnostics(final_triangles, snapshot), "roi": roi}

func _edge_incidence(triangles: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.root_ids
		for index in range(3):
			var key: String = _edge_key(String(ids[index]), String(ids[(index + 1) % 3]))
			counts[key] = int(counts.get(key, 0)) + 1
	return counts

func _validate_required_arcs(triangles: Array[Dictionary], arcs: Array, flips: Array) -> Dictionary:
	var incidence: Dictionary = _edge_incidence(triangles)
	var flip_paths: Dictionary = {}
	for flip_value in flips:
		var flip: Dictionary = flip_value
		var endpoints: Array = flip.get("removed_arc_endpoint_ids", [])
		if endpoints.size() == 2: flip_paths[_edge_key(String(endpoints[0]), String(endpoints[1]))] = flip.get("removed_arc_path_positions", [])
	var missing: Array[Dictionary] = []
	var nonmanifold: Array[Dictionary] = []
	var rows: Array[Dictionary] = []
	for arc_value in arcs:
		var arc: Dictionary = arc_value
		var ids: Array = arc.get("root_ids", [])
		if ids.size() != 2: continue
		var key: String = _edge_key(String(ids[0]), String(ids[1]))
		var expected: int = int(arc.get("expected_incidence", 0))
		var actual: int = int(incidence.get(key, 0))
		var path_valid: bool = false
		if actual != expected and flip_paths.has(key): path_valid = _path_is_on_mesh(flip_paths[key], triangles)
		var valid: bool = actual == expected or path_valid
		if actual > expected and not path_valid: nonmanifold.append({"arc_id": arc.get("arc_id", ""), "expected": expected, "actual": actual})
		if not valid: missing.append({"arc_id": arc.get("arc_id", ""), "root_ids": ids, "expected": expected, "actual": actual, "path_valid": path_valid})
		rows.append({"arc_id": arc.get("arc_id", ""), "expected": expected, "actual": actual, "path_valid": path_valid, "valid": valid})
	return {"valid": missing.is_empty() and nonmanifold.is_empty(), "missing": missing.size(), "nonmanifold": nonmanifold.size(), "rows": rows, "missing_rows": missing, "nonmanifold_rows": nonmanifold}

func _path_is_on_mesh(path_positions: Array, triangles: Array[Dictionary]) -> bool:
	if path_positions.size() != 3: return false
	var p0: Vector3 = _array_vec3(path_positions[0]); var p1: Vector3 = _array_vec3(path_positions[1]); var p2: Vector3 = _array_vec3(path_positions[2])
	return _segment_on_mesh(p0, p1, triangles) and _segment_on_mesh(p1, p2, triangles)

func _segment_on_mesh(a: Vector3, b: Vector3, triangles: Array[Dictionary]) -> bool:
	for triangle in triangles:
		var points: Array = triangle.points
		if _point_on_triangle(a, points[0], points[1], points[2]) and _point_on_triangle(b, points[0], points[1], points[2]): return true
	return false

func _point_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var n: Vector3 = (b - a).cross(c - a)
	var n2: float = n.length_squared()
	if n2 <= FIXED_CUTOFF_SQUARED: return false
	var plane_distance: float = absf(n.dot(p - a)) / sqrt(n2)
	if plane_distance > TRIANGLE_EPSILON: return false
	var v0: Vector3 = b - a; var v1: Vector3 = c - a; var v2: Vector3 = p - a
	var d00: float = v0.dot(v0); var d01: float = v0.dot(v1); var d11: float = v1.dot(v1); var d20: float = v2.dot(v0); var d21: float = v2.dot(v1)
	var denominator: float = d00 * d11 - d01 * d01
	if absf(denominator) <= 1.0e-30: return false
	var v: float = (d11 * d20 - d01 * d21) / denominator
	var w: float = (d00 * d21 - d01 * d20) / denominator
	var u: float = 1.0 - v - w
	return u >= -TRIANGLE_EPSILON and v >= -TRIANGLE_EPSILON and w >= -TRIANGLE_EPSILON

func _validate_c6_paths(triangles: Array[Dictionary], flips: Array) -> Dictionary:
	var checked: int = 0
	var failures: Array[Dictionary] = []
	for flip_value in flips:
		var flip: Dictionary = flip_value
		var path: Array = flip.get("removed_arc_path_positions", [])
		if path.size() != 3: continue
		checked += 1
		if not _path_is_on_mesh(path, triangles): failures.append({"flip_id": flip.get("flip_id", ""), "path": path})
	return {"valid": failures.is_empty(), "checked": checked, "failures": failures}

func _self_intersections_clear(patch: Array[Dictionary], all_triangles: Array[Dictionary]) -> bool:
	for a in patch:
		for b in all_triangles:
			if String(a.triangle_id) == String(b.triangle_id): continue
			if _shared_root_count(a.root_ids, b.root_ids) > 0: continue
			if _triangles_intersect(a.points, b.points): return false
	return true

func _triangles_intersect(a: Array, b: Array) -> bool:
	var amin: Vector3 = Vector3(minf(a[0].x, minf(a[1].x, a[2].x)), minf(a[0].y, minf(a[1].y, a[2].y)), minf(a[0].z, minf(a[1].z, a[2].z)))
	var amax: Vector3 = Vector3(maxf(a[0].x, maxf(a[1].x, a[2].x)), maxf(a[0].y, maxf(a[1].y, a[2].y)), maxf(a[0].z, maxf(a[1].z, a[2].z)))
	var bmin: Vector3 = Vector3(minf(b[0].x, minf(b[1].x, b[2].x)), minf(b[0].y, minf(b[1].y, b[2].y)), minf(b[0].z, minf(b[1].z, b[2].z)))
	var bmax: Vector3 = Vector3(maxf(b[0].x, maxf(b[1].x, b[2].x)), maxf(b[0].y, maxf(b[1].y, b[2].y)), maxf(b[0].z, maxf(b[1].z, b[2].z)))
	if amax.x < bmin.x or bmax.x < amin.x or amax.y < bmin.y or bmax.y < amin.y or amax.z < bmin.z or bmax.z < amin.z: return false
	var ea: Array[Vector3] = [a[1] - a[0], a[2] - a[1], a[0] - a[2]]
	var eb: Array[Vector3] = [b[1] - b[0], b[2] - b[1], b[0] - b[2]]
	var axes: Array[Vector3] = [(a[1] - a[0]).cross(a[2] - a[0]), (b[1] - b[0]).cross(b[2] - b[0])]
	for edge_a in ea:
		for edge_b in eb: axes.append(edge_a.cross(edge_b))
	var normal_a: Vector3 = axes[0]
	var normal_b: Vector3 = axes[1]
	for edge in ea: axes.append(normal_a.cross(edge))
	for edge in eb: axes.append(normal_b.cross(edge))
	for axis in axes:
		if axis.length_squared() <= 1.0e-24: continue
		var aminp: float = INF; var amaxp: float = -INF; var bminp: float = INF; var bmaxp: float = -INF
		for p in a: aminp = minf(aminp, p.dot(axis)); amaxp = maxf(amaxp, p.dot(axis))
		for p in b: bminp = minf(bminp, p.dot(axis)); bmaxp = maxf(bmaxp, p.dot(axis))
		if amaxp < bminp - TRIANGLE_EPSILON or bmaxp < aminp - TRIANGLE_EPSILON: return false
	return true

func _new_t_junction_count(patch: Array[Dictionary], all_triangles: Array[Dictionary]) -> int:
	var count: int = 0
	for triangle in patch:
		for vertex_index in range(3):
			var vertex_id: String = String(triangle.root_ids[vertex_index])
			var point: Vector3 = triangle.points[vertex_index]
			for edge_triangle in all_triangles:
				if edge_triangle == triangle: continue
				for edge_index in range(3):
					var a_id: String = String(edge_triangle.root_ids[edge_index]); var b_id: String = String(edge_triangle.root_ids[(edge_index + 1) % 3])
					if a_id == vertex_id or b_id == vertex_id: continue
					var a: Vector3 = edge_triangle.points[edge_index]; var b: Vector3 = edge_triangle.points[(edge_index + 1) % 3]
					var edge: Vector3 = b - a
					var length2: float = edge.length_squared()
					if length2 <= 0.0: continue
					var t: float = (point - a).dot(edge) / length2
					if t <= TRIANGLE_EPSILON or t >= 1.0 - TRIANGLE_EPSILON: continue
					if point.distance_to(a + edge * t) <= TRIANGLE_EPSILON: count += 1
	return count

func _surface_diagnostics(triangles: Array, snapshot: Dictionary) -> Dictionary:
	var residuals: Array[float] = []
	for triangle in triangles:
		if not triangle is Dictionary: continue
		var points: Array = triangle.get("points", [])
		if points.size() != 3: continue
		var centroid: Vector3 = (points[0] + points[1] + points[2]) / 3.0
		var density: float = Core.sample(centroid, snapshot)
		if is_finite(density): residuals.append(absf(density))
	residuals.sort()
	return {"sample_count": residuals.size(), "max_abs_canonical_sdf_at_triangle_centroid": residuals.max() if not residuals.is_empty() else 0.0, "p95_abs_canonical_sdf_at_triangle_centroid": residuals[mini(residuals.size() - 1, int(ceil(float(residuals.size()) * 0.95)) - 1)] if not residuals.is_empty() else 0.0, "contract": "DIAGNOSTIC_ONLY_NO_OWNER_APPROVED_SURFACE_TOLERANCE"}

func _field_diagnostics(patches: Array[Dictionary], snapshot: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	for patch in patches: rows.append({"group_index": patch.get("group_index", -1), "level": patch.get("level", -1), "search_nodes": patch.get("search_nodes", -1), "search_usec": patch.get("search_usec", -1), "field": patch.get("surface_diagnostics", {})})
	return {"patches": rows, "overall": _surface_diagnostics(_flatten_patch_triangles(patches), snapshot), "diagnostic_only": true}

func _flatten_patch_triangles(patches: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for patch in patches:
		for value in patch.get("replacement_triangles", []): result.append(value)
	return result

func _mesh_from_triangles(triangles: Array[Dictionary]) -> Dictionary:
	var mesh: Dictionary = Core.new_mesh()
	var positions: PackedVector3Array = mesh.positions
	var normals: PackedVector3Array = mesh.normals
	var indices: PackedInt32Array = mesh.indices
	for triangle in triangles:
		var points: Array = triangle.points
		var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
		var normal: Vector3 = cross.normalized()
		positions.append_array(PackedVector3Array([points[0], points[1], points[2]]))
		normals.append_array(PackedVector3Array([normal, normal, normal]))
		var start: int = positions.size() - 3
		indices.append_array(PackedInt32Array([start, start + 1, start + 2]))
	mesh.positions = positions; mesh.normals = normals; mesh.indices = indices
	return mesh

func _mesh_sha(mesh: Dictionary) -> String:
	var authority: RefCounted = Authority.new()
	return String(authority.call("_mesh_sha", mesh))

func _accepted_triangle_rows(triangles: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for triangle in triangles:
		if not bool(triangle.get("rejected", false)): result.append(triangle)
	return result

func _emitted_rows(triangles: Array[Dictionary]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for triangle in triangles:
		rows.append({"triangle_id": triangle.triangle_id, "polygon_id": triangle.polygon_id, "root_ids": triangle.root_ids, "normal": triangle.normal, "cross_squared": triangle.cross_squared, "construction": triangle.construction, "source_polygon_ids": triangle.get("source_polygon_ids", [])})
	return rows

func _cutoff_rows(triangles: Array[Dictionary]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for triangle in triangles:
		if float(triangle.cross_squared) <= FIXED_CUTOFF_SQUARED or not is_finite(float(triangle.cross_squared)):
			rows.append({"triangle_id": triangle.triangle_id, "polygon_id": triangle.polygon_id, "root_ids": triangle.root_ids, "cross_squared": triangle.cross_squared, "reason": "fixed_cross_squared_cutoff"})
	return rows

func _minimum_cross_squared(triangles: Array) -> float:
	var minimum: float = INF
	for triangle in triangles: minimum = minf(minimum, float(triangle.get("cross_squared", INF)))
	return minimum if is_finite(minimum) else 0.0

func _root_coordinates_unchanged(before: Array[Dictionary], after: Array[Dictionary], roots: Dictionary) -> bool:
	for triangle in before:
		for index in range(3):
			var id: String = String(triangle.root_ids[index])
			var point: Vector3 = triangle.points[index]
			if not roots.has(id) or roots[id] != point: return false
	for triangle in after:
		for index in range(3):
			var id: String = String(triangle.root_ids[index])
			if not roots.has(id) or roots[id] != triangle.points[index]: return false
	return true

func _changed_triangle_ids(before: Array[Dictionary], after: Array[Dictionary]) -> Array[String]:
	var before_map: Dictionary = {}
	var after_map: Dictionary = {}
	for triangle in before: before_map[String(triangle.triangle_id)] = _oriented_triplet_key(triangle.root_ids)
	for triangle in after: after_map[String(triangle.triangle_id)] = _oriented_triplet_key(triangle.root_ids)
	var changed: Array[String] = []
	for id in before_map.keys():
		if not after_map.has(id): changed.append(String(id))
	for id in after_map.keys():
		if not before_map.has(id): changed.append(String(id))
	changed.sort()
	return changed

func _derive_locked_triplets(flips: Array, roots: Dictionary) -> Dictionary:
	var locked: Dictionary = {}
	for flip_value in flips:
		var flip: Dictionary = flip_value
		var vertices: Dictionary = flip.get("vertices", {})
		if vertices.is_empty(): continue
		var u_id: String = _root_for_position(vertices.get("edge_u", []), roots)
		var v_id: String = _root_for_position(vertices.get("edge_v", []), roots)
		var p_id: String = _root_for_position(vertices.get("opposite_p", []), roots)
		var q_id: String = _root_for_position(vertices.get("opposite_q", []), roots)
		if u_id.is_empty() or v_id.is_empty() or p_id.is_empty() or q_id.is_empty(): continue
		locked[_triplet_key([p_id, q_id, u_id])] = true
		locked[_triplet_key([q_id, p_id, v_id])] = true
	return locked

func _root_for_position(position_value: Variant, roots: Dictionary) -> String:
	var target: Vector3 = _array_vec3(position_value)
	for root_id in roots.keys():
		if roots[root_id] == target: return String(root_id)
	return ""

func _same_id_set(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	var left: Array[String] = []; var right: Array[String] = []
	for value in a: left.append(String(value))
	for value in b: right.append(String(value))
	left.sort(); right.sort()
	return left == right

func _triangle_by_id(triangles: Array[Dictionary], triangle_id: String) -> Dictionary:
	for triangle in triangles:
		if String(triangle.get("triangle_id", "")) == triangle_id: return triangle
	return {}

func _triangle_has_edge(triangle: Dictionary, a_id: String, b_id: String) -> bool:
	var ids: Array = triangle.get("root_ids", [])
	for index in range(ids.size()):
		if _edge_key(String(ids[index]), String(ids[(index + 1) % ids.size()])) == _edge_key(a_id, b_id): return true
	return false

func _edge_key(a_id: String, b_id: String) -> String:
	return a_id + "\u001f" + b_id if a_id < b_id else b_id + "\u001f" + a_id

func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in values.keys(): result.append(String(value))
	result.sort()
	return result

func _shared_root_count(a: Array, b: Array) -> int:
	var count: int = 0
	for value in a:
		if b.has(value): count += 1
	return count

func _array_vec3(value: Variant) -> Vector3:
	if value is Vector3: return value
	var array: Array = value
	if array.size() < 3: return Vector3.ZERO
	return Vector3(float(array[0]), float(array[1]), float(array[2]))

func _limits() -> Dictionary:
	return {"max_cavity_level": MAX_CAVITY_LEVEL, "max_cavities": MAX_RESIDUAL_CAVITIES, "max_cavity_triangles": MAX_PATCH_TRIANGLES, "max_patch_triangles": MAX_PATCH_TRIANGLES, "max_search_states_per_cavity": MAX_SEARCH_STATES, "max_search_states": MAX_SEARCH_STATES, "max_total_search_states": MAX_SEARCH_STATES * MAX_RESIDUAL_CAVITIES, "search_state_scope": "PER_CAVITY_MAX_THREE_RESIDUAL_CAVITIES", "max_retained_solutions_per_cavity": MAX_RETAINED_SOLUTIONS, "max_retained_solutions": MAX_RETAINED_SOLUTIONS, "max_search_usec_total": MAX_SEARCH_USEC, "max_search_usec": MAX_SEARCH_USEC, "max_realize_usec": MAX_REALIZE_USEC, "max_support_candidates": MAX_SUPPORT_CANDIDATES, "max_support_vertices": MAX_SELECTED_SUPPORTS, "cutoff_squared": FIXED_CUTOFF_SQUARED}

func support_id(cavity_id: String, source_primitive: String, method: String, ordering_key: String) -> String:
	var stable_payload: Array[String] = ["R12CX_SUPPORT.v1", cavity_id, source_primitive, method, ordering_key]
	return "CX_SUPPORT_" + Core.sha256(JSON.stringify(stable_payload).to_utf8_buffer())

func validate_support_record(record: Dictionary) -> Dictionary:
	var required: Array[String] = ["support_id", "cavity_id", "parent_topology_face_or_path", "source_polygon_ids", "source_cell", "source_tetrahedron", "generation_method", "source_primitive", "interpolation_parameter", "world_position", "field_residual", "zero_set_residual", "inside_source_primitive", "neighboring_output_faces", "ordering_key"]
	for key in required:
		if not record.has(key): return {"valid": false, "reason": "support_provenance_field_missing", "field": key}
	var method: String = String(record.get("generation_method", ""))
	if not ["zero_crossing_frozen_source_edge", "tetrahedral_edge_interpolation", "cavity_segment_zero_set_intersection"].has(method): return {"valid": false, "reason": "support_generation_method_unapproved"}
	var position: Variant = record.get("world_position")
	if typeof(position) != TYPE_VECTOR3: return {"valid": false, "reason": "support_world_position_invalid"}
	var support_position: Vector3 = position
	if not support_position.is_finite(): return {"valid": false, "reason": "support_world_position_invalid"}
	var parameter: float = float(record.get("interpolation_parameter", -1.0))
	var field_residual: float = float(record.get("field_residual", INF))
	var zero_residual: float = float(record.get("zero_set_residual", INF))
	if not is_finite(parameter) or parameter < 0.0 or parameter > 1.0 or not is_finite(field_residual) or not is_finite(zero_residual): return {"valid": false, "reason": "support_numeric_provenance_invalid"}
	if not bool(record.get("inside_source_primitive", false)) or String(record.get("cavity_id", "")).is_empty() or String(record.get("source_primitive", "")).is_empty() or String(record.get("ordering_key", "")).is_empty(): return {"valid": false, "reason": "support_source_provenance_incomplete"}
	var expected: String = support_id(String(record.cavity_id), String(record.source_primitive), method, String(record.ordering_key))
	if String(record.get("support_id", "")) != expected: return {"valid": false, "reason": "support_id_mismatch", "expected": expected}
	return {"valid": true, "support_id": expected, "field_residual": field_residual, "zero_set_residual": zero_residual}

func validate_support_records(records: Array, topology_root_ids: Dictionary) -> Dictionary:
	if records.size() > MAX_SELECTED_SUPPORTS: return {"valid": false, "reason": "support_selection_cap_exceeded", "count": records.size(), "cap": MAX_SELECTED_SUPPORTS}
	var ids: Dictionary = {}
	for value in records:
		if not value is Dictionary: return {"valid": false, "reason": "support_record_not_dictionary"}
		var checked: Dictionary = validate_support_record(value)
		if not bool(checked.get("valid", false)): return checked
		var id: String = String(checked.support_id)
		if ids.has(id) or topology_root_ids.has(id): return {"valid": false, "reason": "support_id_duplicate_or_topology_collision", "support_id": id}
		ids[id] = true
	return {"valid": true, "count": records.size(), "ids": _sorted_keys(ids), "provenance_sha256": Core.sha256(JSON.stringify(records).to_utf8_buffer())}
