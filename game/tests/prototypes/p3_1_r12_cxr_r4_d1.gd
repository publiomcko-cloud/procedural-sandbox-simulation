extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd")
const ManifestSha := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const Stage0Sha := "33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d"
const ResidualSha := "ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23"
const SupportPoolSha := "fe876d0d8a469b5f972c507cf17d9198d26432f9973a41f0d082a6f806f8ddd8"
const CandidateSha := "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"
const TopologySha := "4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95"
const GraphSha := "a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9"
const VolumeSha := "ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2"
const PayloadSha := "2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0"
const C6MeshSha := "b5c0e7e44e9d28bc9d58f6982095f2e387d8155026e7f15662612b3176024ec8"
const TargetId := "R9.2.SEAM.XPLUS_EQUAL.v1"
const D1_MAX_TRIANGLE_PROBES := 8192

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output_path: String = OS.get_environment("R12CXR_R4_OUTPUT")
	if output_path.is_empty() or FileAccess.file_exists(output_path):
		_fail("r4_d1_output_path_invalid_or_exists", {})
		return
	var stage0_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/stage0-topology.json")
	var residual_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/residual-c6.json")
	var pool_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/support-pool-attempt07.json")
	if Core.sha256(stage0_bytes) != Stage0Sha or Core.sha256(residual_bytes) != ResidualSha or Core.sha256(pool_bytes) != SupportPoolSha:
		_fail("r4_d1_frozen_fixture_hash_mismatch", {"stage0": Core.sha256(stage0_bytes), "residual": Core.sha256(residual_bytes), "support_pool": Core.sha256(pool_bytes)})
		return
	var stage0_value: Variant = JSON.parse_string(stage0_bytes.get_string_from_utf8())
	var residual_value: Variant = JSON.parse_string(residual_bytes.get_string_from_utf8())
	var pool_value: Variant = JSON.parse_string(pool_bytes.get_string_from_utf8())
	if typeof(stage0_value) != TYPE_DICTIONARY or typeof(residual_value) != TYPE_DICTIONARY or typeof(pool_value) != TYPE_DICTIONARY:
		_fail("r4_d1_frozen_fixture_schema_invalid", {})
		return
	var stage0: Dictionary = stage0_value
	var residual_fixture: Dictionary = residual_value
	var support_fixture: Dictionary = pool_value
	if String(stage0.get("schema", "")) != "P3.1.R12C.TopologyRealizationFixture.v1" or String(support_fixture.get("schema", "")) != "P3.1.R12CXR.R4D1SupportPool.v1" or String(support_fixture.get("original_source_sha", "")) != "2f6967a46cce2e8d7eef39cb452c2285419d1d61" or String(support_fixture.get("scenario_id", "")) != TargetId:
		_fail("r4_d1_frozen_identity_invalid", {})
		return
	var manifest: Dictionary = Core.load_manifest()
	if not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != ManifestSha:
		_fail("r4_d1_manifest_invalid", {"reason": manifest.get("reason", ""), "sha256": manifest.get("sha256", "")})
		return
	var row: Dictionary = Core.case_by_id(manifest.get("rows", []), TargetId)
	if row.is_empty():
		_fail("r4_d1_target_missing", {})
		return
	var snapshot_result: Dictionary = Core.make_snapshot(row)
	if not bool(snapshot_result.get("valid", false)):
		_fail("r4_d1_snapshot_invalid", snapshot_result)
		return
	var snapshot: Dictionary = snapshot_result.get("snapshot", {})
	var candidate: RefCounted = CandidateD.new()
	var roi: Dictionary = row.get("roi", {})
	candidate.call("configure_roi", roi)
	var volume_case: Dictionary = candidate.call("build", snapshot, row, {"id": "R12CXR_R4_D1"})
	if not bool(volume_case.get("valid", false)):
		_fail("r4_d1_volume_build_failed", {"reason": volume_case.get("reason", ""), "detail": volume_case})
		return
	var volume: Dictionary = volume_case.get("volume", {})
	var volume_metrics: Dictionary = volume_case.get("metrics", {}).get("volume", {})
	if String(volume.get("sha256", "")) != VolumeSha or String(volume_metrics.get("payload_sha256", "")) != PayloadSha or int(volume.get("revision", -1)) != 2 or not bool(volume_case.get("metrics", {}).get("materialized_volume_identity_preserved", false)):
		_fail("r4_d1_volume_identity_mismatch", {"volume_sha256": volume.get("sha256", ""), "payload_sha256": volume_metrics.get("payload_sha256", ""), "revision": volume.get("revision", -1)})
		return
	var graph: Dictionary = stage0.get("topology_authority", {})
	if graph.is_empty() or Core.sha256(JSON.stringify(graph).to_utf8_buffer()) != GraphSha or String(stage0.get("source_topology_sha256", "")) != TopologySha:
		_fail("r4_d1_topology_graph_identity_mismatch", {"graph_sha256": Core.sha256(JSON.stringify(graph).to_utf8_buffer()), "topology_sha256": stage0.get("source_topology_sha256", "")})
		return
	var realizer: RefCounted = Realizer.new()
	realizer.set("_cxr_active_phase", "r3")
	realizer.set("_cxr_active_snapshot", snapshot)
	realizer.set("_cxr_search_started_usec", Time.get_ticks_usec())
	realizer.set("_cxr_cavity_started_usec", Time.get_ticks_usec())
	realizer.set("_cxr_search_nodes_total", 0)
	realizer.set("_cxr_search_nodes_cavity", 0)
	realizer.set("_cxr_candidate_attempts_total", 0)
	realizer.set("_cxr_candidate_triangles_total", 0)
	realizer.set("_cxr_local_search_marker_emitted", true)
	var base: Dictionary = realizer.call("realize", graph, volume.get("values", PackedFloat32Array()), roi, TopologySha, GraphSha)
	if not bool(base.get("valid", false)) or String(base.get("mesh_sha256", "")) != C6MeshSha:
		_fail("r4_d1_c6_base_identity_mismatch", {"reason": base.get("reason", ""), "mesh_sha256": base.get("mesh_sha256", "")})
		return
	var fixture_error: String = String(realizer.call("_validate_residual_fixture", residual_fixture, base))
	if not fixture_error.is_empty():
		_fail("r4_d1_residual_fixture_invalid", {"reason": fixture_error})
		return
	var built: Dictionary = realizer.call("_build_triangles", base, residual_fixture)
	if not bool(built.get("valid", false)):
		_fail("r4_d1_c6_reconstruction_failed", built)
		return
	var triangles: Array[Dictionary] = built.get("triangles", [])
	var root_positions: Dictionary = built.get("root_positions", {})
	realizer.set("_root_positions", root_positions)
	var accepted_c6: Array[Dictionary] = realizer.call("_accepted_triangle_rows", triangles)
	var reconstructed_c6_sha: String = String(realizer.call("_mesh_sha", realizer.call("_mesh_from_triangles", accepted_c6)))
	if reconstructed_c6_sha != C6MeshSha:
		_fail("r4_d1_reconstructed_c6_mesh_mismatch", {"observed": reconstructed_c6_sha, "expected": C6MeshSha})
		return
	var required_arc_keys: Dictionary = {}
	for arc_value in base.get("arc_map", []):
		var arc: Dictionary = arc_value
		var endpoints: Array = arc.get("root_ids", [])
		if endpoints.size() == 2:
			required_arc_keys[String(realizer.call("_edge_key", String(endpoints[0]), String(endpoints[1])))] = true
	realizer.set("_required_arc_keys", required_arc_keys)
	realizer.set("_locked_triplets", realizer.call("_derive_locked_triplets", base.get("applied_flips", []), root_positions))
	var adjacency: Dictionary = realizer.call("_adjacency", triangles)
	realizer.call("_orient_rejected_triangles", triangles, adjacency)
	var defect_groups: Array = realizer.call("_canonicalize_defect_groups", realizer.call("_overlapping_defect_groups", residual_fixture.get("residuals", []), adjacency))
	var seed_ids: Array = support_fixture.get("seed_triangle_ids", [])
	seed_ids.sort()
	if defect_groups.is_empty() or _string_array(defect_groups[0]) != _string_array(seed_ids):
		_fail("r4_d1_seed_cavity_reconstruction_mismatch", {"expected_seed_ids": seed_ids, "observed_groups": defect_groups})
		return
	var patch_ids: Array = support_fixture.get("patch_triangle_ids", [])
	patch_ids.sort()
	var patch: Array[Dictionary] = realizer.call("_r3_patch_rows_for_ids", triangles, patch_ids)
	if patch.size() != patch_ids.size():
		_fail("r4_d1_patch_reconstruction_mismatch", {"expected": patch_ids.size(), "observed": patch.size()})
		return
	var connectivity: Dictionary = realizer.call("_r3_patch_connectivity", patch)
	var boundary: Dictionary = realizer.call("_r3_derive_remaining_boundary", triangles, patch_ids)
	var observed_boundary_signature: String = String(boundary.get("signature", ""))
	if not bool(connectivity.get("valid", false)) or not bool(boundary.get("valid", false)) or observed_boundary_signature != String(support_fixture.get("boundary_signature", "")):
		_fail("r4_d1_patch_boundary_identity_mismatch", {"connectivity": connectivity, "boundary_valid": boundary.get("valid", false), "boundary_reason": boundary.get("reason", ""), "observed_signature": observed_boundary_signature, "expected_signature": support_fixture.get("boundary_signature", "")})
		return
	var seed_by_id: Dictionary = {}
	for residual_value_row in residual_fixture.get("residuals", []):
		var residual_row: Dictionary = residual_value_row
		seed_by_id[String(residual_row.get("triangle_id", ""))] = residual_row
	var seed_triangles: Array[Dictionary] = realizer.call("_r3_patch_rows_for_ids", triangles, seed_ids)
	seed_triangles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("triangle_id", "")) < String(b.get("triangle_id", "")))
	var regenerated_by_position: Dictionary = {}
	var candidate_attempt_count: int = 0
	var candidate_unique_per_seed: Dictionary = {}
	var candidate_attempt_per_seed: Dictionary = {}
	var max_per_seed: int = maxi(1, int(floor(256.0 / float(seed_triangles.size()))))
	for seed_triangle in seed_triangles:
		var seed_id: String = String(seed_triangle.get("triangle_id", ""))
		var remaining_attempts: int = int(support_fixture.get("support_candidate_attempt_count", 0)) - candidate_attempt_count
		var generated: Dictionary = realizer.call("_generate_field_candidates", seed_triangle, patch, volume.get("values", PackedFloat32Array()), roi, 2, max_per_seed, remaining_attempts, String(support_fixture.get("cavity_id", "")), seed_by_id.get(seed_id, {}))
		if not bool(generated.get("source_valid", false)):
			_fail("r4_d1_support_regeneration_source_invalid", {"seed_id": seed_id, "reason": generated.get("source_failure_reason", ""), "detail": generated})
			return
		var generated_attempts: Array = generated.get("attempts", [])
		candidate_attempt_count += generated_attempts.size()
		candidate_attempt_per_seed[seed_id] = generated_attempts.size()
		var generated_pool: Array = generated.get("candidate_pool", [])
		candidate_unique_per_seed[seed_id] = generated_pool.size()
		for support_value in generated_pool:
			var support: Dictionary = support_value
			var position_identity: String = String(support.get("binary32_position_identity", ""))
			if not regenerated_by_position.has(position_identity):
				regenerated_by_position[position_identity] = support.duplicate(true)
			else:
				var prior: Dictionary = regenerated_by_position[position_identity]
				var provenance: Array = prior.get("coalesced_candidate_ids", [])
				var candidate_id: String = String(support.get("candidate_id", ""))
				if not provenance.has(candidate_id): provenance.append(candidate_id)
				provenance.sort()
				if bool(realizer.call("_candidate_less", support, prior)):
					support["coalesced_candidate_ids"] = provenance
					regenerated_by_position[position_identity] = support.duplicate(true)
				else:
					prior["coalesced_candidate_ids"] = provenance
					regenerated_by_position[position_identity] = prior
	var regenerated_rows: Array[Dictionary] = []
	for support_value in regenerated_by_position.values(): regenerated_rows.append(support_value)
	regenerated_rows.sort_custom(Callable(realizer, "_candidate_less"))
	var stored_rows: Array[Dictionary] = []
	for support_value in support_fixture.get("support_rows", []):
		if typeof(support_value) != TYPE_DICTIONARY:
			_fail("r4_d1_stored_support_row_invalid", {})
			return
		stored_rows.append(support_value)
	var pool_match: Dictionary = _compare_support_rows(regenerated_rows, stored_rows)
	if not bool(pool_match.get("valid", false)):
		_fail("r4_d1_support_pool_regeneration_mismatch", {"detail": pool_match, "regenerated_count": regenerated_rows.size(), "stored_count": stored_rows.size(), "candidate_attempt_count": candidate_attempt_count})
		return
	var search_residual_fixture: Dictionary = residual_fixture.duplicate(true)
	search_residual_fixture["arc_map"] = base.get("arc_map", []).duplicate(true)
	search_residual_fixture["applied_flips"] = base.get("applied_flips", []).duplicate(true)
	var preflight: Dictionary = realizer.call("_r3_make_expanded_patch_context", patch, patch_ids, seed_triangles, regenerated_rows, boundary, triangles, search_residual_fixture, 2, true)
	var blocked_reason: String = String(preflight.get("reason", ""))
	if bool(preflight.get("valid", false)):
		_fail("r4_d1_expected_context_blocker_not_reproduced", {"preflight": preflight})
		return
	var blocked_arc: Dictionary = preflight.get("arc_diagnostics", {})
	realizer.set("_cxr_active_phase", "r4")
	var all_triangle_ids: Array = realizer.call("_r3_sorted_triangle_ids", triangles)
	var boundary_first_result: Dictionary = realizer.call("_r4_select_boundary_first_patch", seed_ids, all_triangle_ids, triangles, adjacency, seed_triangles, regenerated_rows, search_residual_fixture, 2)
	if not bool(boundary_first_result.get("valid", false)):
		_fail("r4_d1_boundary_first_patch_not_found", {"reason": boundary_first_result.get("reason", "UNKNOWN_NOT_CAPTURED"), "result": boundary_first_result})
		return
	var analysis_patch_ids: Array = boundary_first_result.get("patch_triangle_ids", []).duplicate()
	var analysis_patch: Array[Dictionary] = boundary_first_result.get("patch_triangles", []).duplicate(true)
	var analysis_boundary: Dictionary = boundary_first_result.get("boundary", {}).duplicate(true)
	var cycle_set: Dictionary = realizer.call("_r4_boundary_cycle_set", analysis_boundary)
	if not bool(cycle_set.get("valid", false)) or int(cycle_set.get("component_count", 0)) != 1:
		_fail("r4_d1_single_loop_support_diagnostic_not_available", {"cycle_set": cycle_set})
		return
	var cycle_rows: Array = cycle_set.get("cycles", [])
	if cycle_rows.size() != 1:
		_fail("r4_d1_boundary_cycle_set_cardinality_invalid", {"cycle_count": cycle_rows.size()})
		return
	var cycle: Array = cycle_rows[0].get("root_ids", [])
	var r4_preflight: Dictionary = realizer.call("_r3_make_expanded_patch_context", analysis_patch, analysis_patch_ids, seed_triangles, regenerated_rows, analysis_boundary, triangles, search_residual_fixture, 2, true)
	if not bool(r4_preflight.get("valid", false)):
		_fail("r4_d1_boundary_first_context_preflight_failed", {"preflight": r4_preflight})
		return
	var full_context_result: Dictionary = realizer.call("_r3_make_expanded_patch_context", analysis_patch, analysis_patch_ids, seed_triangles, regenerated_rows, analysis_boundary, triangles, search_residual_fixture, 2, false)
	if not bool(full_context_result.get("valid", false)):
		_fail("r4_d1_full_candidate_context_failed", {"context": full_context_result})
		return
	var r4_context: Dictionary = full_context_result.get("context", {})
	var support_records: Array[Dictionary] = []
	var blocked_connections: int = 0
	var legal_edge_union: Dictionary = {}
	var aggregate_edge_rejection_histogram: Dictionary = {}
	var eligible_vertex_ids: Dictionary = {}
	var projection_context: Dictionary = _projection_context(realizer, analysis_patch, root_positions, cycle)
	if not bool(projection_context.get("valid", false)):
		_fail("r4_d1_projection_context_invalid", projection_context)
		return
	var eligible_vertex_list: Array = r4_context.get("vertex_ids", []).duplicate()
	eligible_vertex_list.sort()
	for vertex_id_value in eligible_vertex_list:
		var vertex_id: String = String(vertex_id_value)
		if not r4_context.projected_positions.has(vertex_id): continue
		if bool(realizer.call("_r2_point_in_polygon", r4_context.projected_positions[vertex_id], r4_context.polygon)):
			eligible_vertex_ids[vertex_id] = true
	var support_projection_by_id: Dictionary = {}
	for support in regenerated_rows:
		var support_id: String = String(support.get("support_id", ""))
		var projection: Dictionary = _project_support_position(support.get("world_position", null), projection_context, realizer)
		support_projection_by_id[support_id] = projection
		if bool(projection.get("inside_domain", false)): eligible_vertex_ids[support_id] = true
	for support in regenerated_rows:
		var support_id: String = String(support.get("support_id", ""))
		var support_projection: Dictionary = support_projection_by_id.get(support_id, {})
		var edge_diagnostics: Array[Dictionary] = []
		var legal_edges: Dictionary = {}
		var edge_rejection_histogram: Dictionary = {}
		for other_id_value in eligible_vertex_list:
			var other_id: String = String(other_id_value)
			if other_id == support_id or not eligible_vertex_ids.has(other_id): continue
			var edge_probe: Dictionary = realizer.call("_r4_probe_support_edge", support_id, other_id, r4_context)
			edge_diagnostics.append(edge_probe)
			if bool(edge_probe.get("valid", false)):
				legal_edges[String(edge_probe.get("edge_key", ""))] = true
			else:
				var edge_reason: String = String(edge_probe.get("reason", "UNKNOWN_NOT_CAPTURED"))
				edge_rejection_histogram[edge_reason] = int(edge_rejection_histogram.get(edge_reason, 0)) + 1
		for reason_value in edge_rejection_histogram.keys():
			var reason_key: String = String(reason_value)
			aggregate_edge_rejection_histogram[reason_key] = int(aggregate_edge_rejection_histogram.get(reason_key, 0)) + int(edge_rejection_histogram[reason_key])
		for legal_edge_value in legal_edges.keys(): legal_edge_union[String(legal_edge_value)] = true
		var candidate_vertex_count: int = edge_diagnostics.size()
		var records_for_support: Dictionary = {
			"support_id": String(support.get("support_id", "")), "candidate_id": String(support.get("candidate_id", "")),
			"world_position": _position_array(support.get("world_position", null)), "binary32_position_identity": String(support.get("binary32_position_identity", "")),
			"field_residual": support.get("frozen_field_interpolated_residual", "UNKNOWN_NOT_CAPTURED"),
			"source_cell_global_lattice": support.get("source_cell_global_lattice", []), "source_tetrahedron": support.get("source_tetrahedron", -1),
			"source_residual_triangle_id": String(support.get("residual_triangle_id", "")), "cavity_id": String(support_fixture.get("cavity_id", "")),
			"projected_position": support_projection.get("projected_position", "UNKNOWN_NOT_COMPUTED"), "inside_domain": support_projection.get("inside_domain", "UNKNOWN_NOT_COMPUTED"),
			"on_domain_boundary": support_projection.get("on_boundary", "UNKNOWN_NOT_COMPUTED"), "eligible_vertex_count": eligible_vertex_ids.size(),
			"candidate_edge_pair_count": candidate_vertex_count, "legal_edge_count": legal_edges.size(), "edge_diagnostics": edge_diagnostics,
			"edge_rejection_histogram": edge_rejection_histogram, "legal_triangle_count": "NOT_EVALUATED_YET",
			"edge_decision": "R2_PROJECTED_DOMAIN_TOPOLOGY_AND_T_JUNCTION_PREFLIGHT"
		}
		support_records.append(records_for_support)
		blocked_connections += candidate_vertex_count
	var support_id_set: Dictionary = {}
	for support in regenerated_rows: support_id_set[String(support.get("support_id", ""))] = true
	var eligible_tri_vertices: Array[String] = []
	for vertex_id_value in eligible_vertex_ids.keys(): eligible_tri_vertices.append(String(vertex_id_value))
	eligible_tri_vertices.sort()
	var triangle_probe_count: int = 0
	var triangle_probe_exhaustive: bool = true
	var legal_triangle_ids: Dictionary = {}
	var triangle_rejection_histogram: Dictionary = {}
	var support_triangle_counts: Dictionary = {}
	var support_minimum_cross_squared: Dictionary = {}
	var triangle_probe_keys: Dictionary = {}
	for first_index in range(eligible_tri_vertices.size()):
		for second_index in range(first_index + 1, eligible_tri_vertices.size()):
			for third_index in range(second_index + 1, eligible_tri_vertices.size()):
				var ids: Array[String] = [eligible_tri_vertices[first_index], eligible_tri_vertices[second_index], eligible_tri_vertices[third_index]]
				var incident_supports: Array[String] = []
				for vertex_id in ids:
					if support_id_set.has(vertex_id): incident_supports.append(vertex_id)
				var probe_key: String = String(realizer.call("_triplet_key", ids))
				if triangle_probe_keys.has(probe_key): continue
				triangle_probe_keys[probe_key] = true
				if triangle_probe_count >= D1_MAX_TRIANGLE_PROBES:
					triangle_probe_exhaustive = false
					break
				triangle_probe_count += 1
				var triangle_result: Dictionary = realizer.call("_r2_get_candidate_triangle", ids, r4_context)
				if bool(triangle_result.get("valid", false)):
					var triangle: Dictionary = triangle_result.get("triangle", {})
					var triangle_id: String = String(triangle_result.get("candidate_id", ""))
					legal_triangle_ids[triangle_id] = true
					var cross_squared: float = float(triangle.get("cross_squared", 0.0))
					for support_id in incident_supports:
						support_triangle_counts[support_id] = int(support_triangle_counts.get(support_id, 0)) + 1
						support_minimum_cross_squared[support_id] = minf(float(support_minimum_cross_squared.get(support_id, INF)), cross_squared)
				else:
					var triangle_reason: String = String(triangle_result.get("reason", "UNKNOWN_NOT_CAPTURED"))
					triangle_rejection_histogram[triangle_reason] = int(triangle_rejection_histogram.get(triangle_reason, 0)) + 1
			if not triangle_probe_exhaustive: break
		if not triangle_probe_exhaustive: break
	for record in support_records:
		var support_id: String = String(record.get("support_id", ""))
		record["legal_triangle_count"] = int(support_triangle_counts.get(support_id, 0))
		record["minimum_legal_triangle_cross_squared"] = support_minimum_cross_squared.get(support_id, "UNKNOWN_NO_LEGAL_TRIANGLE")
		record["triangle_rejection_histogram"] = triangle_rejection_histogram.duplicate()
	var d3_search_result: Dictionary = realizer.call("_r2_search_level", r4_context)
	var d3_search_summary: Dictionary = {}
	for key in ["valid", "search_complete", "search_exhaustive", "terminal_reason", "solution_count", "branches", "search_usec", "candidate_triangle_count", "branch_counts", "prune_counts", "best_solution"]:
		if d3_search_result.has(key): d3_search_summary[key] = d3_search_result[key]
	var all_triangle_rows: Array = r4_context.get("candidate_triangle_rows", [])
	var full_triangle_rejection_histogram: Dictionary = {}
	var accepted_candidate_triangle_count: int = 0
	var supports_with_accepted_candidate_triangles: Dictionary = {}
	for triangle_row_value in all_triangle_rows:
		if typeof(triangle_row_value) != TYPE_DICTIONARY: continue
		var triangle_row: Dictionary = triangle_row_value
		if bool(triangle_row.get("valid", false)):
			accepted_candidate_triangle_count += 1
			for vertex_id_value in triangle_row.get("vertex_ids", []):
				var vertex_id: String = String(vertex_id_value)
				if support_id_set.has(vertex_id):
					supports_with_accepted_candidate_triangles[vertex_id] = true
					support_triangle_counts[vertex_id] = int(support_triangle_counts.get(vertex_id, 0)) + 1
					support_minimum_cross_squared[vertex_id] = minf(float(support_minimum_cross_squared.get(vertex_id, INF)), float(triangle_row.get("cross_squared", INF)))
		else:
			var triangle_reject_reason: String = String(triangle_row.get("rejection_reason", "UNKNOWN_NOT_CAPTURED"))
			full_triangle_rejection_histogram[triangle_reject_reason] = int(full_triangle_rejection_histogram.get(triangle_reject_reason, 0)) + 1
	for record in support_records:
		var support_id: String = String(record.get("support_id", ""))
		record["legal_triangle_count"] = int(support_triangle_counts.get(support_id, 0))
		record["candidate_triangle_rejection_histogram_global"] = full_triangle_rejection_histogram.duplicate()
	var d1_status: String = "D1_A_LEGAL_TRIANGLES_FOUND" if accepted_candidate_triangle_count > 0 else "D1_B_LEGAL_EDGES_NO_LEGAL_TRIANGLES" if legal_edge_union.size() > 0 and triangle_probe_exhaustive and bool(d3_search_result.get("search_complete", false)) else "D1_C_NO_LEGAL_EDGES" if legal_edge_union.is_empty() and triangle_probe_exhaustive else "D1_PARTIAL_CANDIDATE_GRAPH"
	var boundary_first_summary: Dictionary = {}
	for key in ["valid", "complete", "reason", "search_nodes", "queue_peak", "rejection_counts", "expansion_log", "patch_triangle_ids", "boundary_cycles", "triangulation_supported", "context_preflight", "boundary", "expansion_causes"]:
		if boundary_first_result.has(key): boundary_first_summary[key] = boundary_first_result[key]
	var result: Dictionary = {
		"schema": "P3.1.R12CXR.R4D1SupportViability.v1", "status": d1_status,
		"source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "scenario_id": TargetId,
		"frozen_source_sha": String(support_fixture.get("original_source_sha", "")), "frozen_target_result_sha256": String(support_fixture.get("target_result_sha256", "")),
		"stage0_sha256": Stage0Sha, "residual_fixture_sha256": ResidualSha, "support_pool_fixture_sha256": SupportPoolSha,
		"manifest_sha256": ManifestSha, "topology_sha256": TopologySha, "graph_fingerprint_sha256": GraphSha,
		"volume_sha256": VolumeSha, "payload_sha256": PayloadSha, "revision": 2,
		"c6_mesh_sha256": C6MeshSha, "cavity_id": String(support_fixture.get("cavity_id", "")),
		"seed_triangle_ids": seed_ids, "selected_patch_triangle_ids": patch_ids, "patch_connectivity": connectivity,
		"boundary_signature": observed_boundary_signature, "boundary_edge_count": boundary.get("boundary_edge_count", -1),
		"retained_support_count": regenerated_rows.size(), "support_pool_reproduced_exactly": true,
		"support_attempt_count": candidate_attempt_count, "candidate_unique_per_seed": candidate_unique_per_seed, "candidate_attempts_per_seed": candidate_attempt_per_seed,
		"support_records": support_records, "candidate_pair_count_tested": blocked_connections,
		"legacy_four_face_context_preflight_valid": false, "legacy_four_face_context_failure_reason": blocked_reason,
		"boundary_first_d2": boundary_first_summary, "blocking_arc_diagnostics": blocked_arc,
		"r4_context_preflight_valid": true, "r4_context_valid": true, "r4_context_boundary_signature": r4_context.get("boundary_signature", ""),
		"r4_boundary_first_patch_triangle_ids": analysis_patch_ids, "edge_probe_rejection_scope": "domain_boundary_required_arcs_duplicate_geometry_and_t_junction",
		"legal_supports_with_edges": support_records.filter(func(row: Dictionary) -> bool: return int(row.get("legal_edge_count", 0)) > 0).size(),
		"supports_with_two_or_more_legal_edges": support_records.filter(func(row: Dictionary) -> bool: return int(row.get("legal_edge_count", 0)) >= 2).size(),
		"legal_candidate_edges": legal_edge_union.size(), "edge_rejection_histogram": aggregate_edge_rejection_histogram,
		"triangle_probe_count": triangle_probe_count, "triangle_probe_exhaustive": triangle_probe_exhaustive,
		"legal_candidate_triangles": accepted_candidate_triangle_count, "triangle_rejection_histogram": full_triangle_rejection_histogram,
		"candidate_triangle_rows_count": all_triangle_rows.size(), "candidate_triangle_rows": all_triangle_rows.duplicate(true),
		"supports_with_legal_triangles": supports_with_accepted_candidate_triangles.size(), "candidate_graph_created": true,
		"d3_constrained_search": d3_search_summary,
		"classification": "The initial four-face context is blocked by a required topology arc. Boundary-first expansion found a six-face one-cycle context; candidate edges and a bounded support-incident triangle graph are evaluated on that context."
	}
	var output_bytes: PackedByteArray = JSON.stringify(result, "\t", false).to_utf8_buffer()
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("r4_d1_result_open_failed", {"path": output_path, "error": FileAccess.get_open_error()})
		return
	file.store_buffer(output_bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		printerr("R4_D1_RESULT_WRITE_FAIL " + str(write_error))
		quit(2)
		return
	print("R4_D1_SUPPORT_VIABILITY_RESULT " + JSON.stringify({"status": result.get("status", "UNKNOWN_NOT_CAPTURED"), "support_count": result.get("retained_support_count", -1), "support_pool_reproduced_exactly": result.get("support_pool_reproduced_exactly", false), "legacy_context_failure_reason": result.get("legacy_four_face_context_failure_reason", ""), "arc_diagnostics": result.get("blocking_arc_diagnostics", {}), "result_path": output_path, "result_sha256": Core.sha256(output_bytes)}))
	quit(0)

func _compare_support_rows(regenerated: Array[Dictionary], stored: Array[Dictionary]) -> Dictionary:
	if regenerated.size() != stored.size(): return {"valid": false, "reason": "support_count_mismatch", "regenerated": regenerated.size(), "stored": stored.size()}
	for index in range(regenerated.size()):
		var current: Dictionary = regenerated[index]
		var frozen: Dictionary = stored[index]
		for key in ["candidate_id", "support_id", "binary32_position_identity", "residual_triangle_id", "source_cell_global_lattice", "source_tetrahedron", "method", "level", "frozen_field_interpolated_residual"]:
			if not frozen.has(key):
				return {"valid": false, "reason": "support_provenance_field_missing", "index": index, "key": key}
			var current_value: Variant = current.get(key, null)
			var frozen_value: Variant = frozen.get(key, null)
			if key == "source_cell_global_lattice":
				current_value = _normalize_lattice(current_value)
				frozen_value = _normalize_lattice(frozen_value)
				if current_value == null or frozen_value == null:
					return {"valid": false, "reason": "support_lattice_encoding_invalid", "index": index}
			var values_match: bool = JSON.stringify(current_value) == JSON.stringify(frozen_value)
			if key in ["source_tetrahedron", "level"] and current_value is int and frozen_value is float:
				values_match = is_finite(float(frozen_value)) and floorf(float(frozen_value)) == float(frozen_value) and int(frozen_value) == int(current_value)
			if not values_match:
				return {"valid": false, "reason": "support_provenance_field_mismatch", "index": index, "key": key, "regenerated": current_value, "frozen": frozen_value}
		var frozen_position_value: Variant = frozen.get("world_position", null)
		var frozen_position: Vector3 = Vector3.ZERO
		if frozen_position_value is String:
			var position_parts: PackedStringArray = String(frozen_position_value).trim_prefix("(").trim_suffix(")").split(",")
			if position_parts.size() != 3:
				return {"valid": false, "reason": "stored_support_position_invalid", "index": index}
			frozen_position = Vector3(float(position_parts[0].strip_edges()), float(position_parts[1].strip_edges()), float(position_parts[2].strip_edges()))
		elif frozen_position_value is Array and frozen_position_value.size() == 3:
			frozen_position = Vector3(float(frozen_position_value[0]), float(frozen_position_value[1]), float(frozen_position_value[2]))
		else:
			return {"valid": false, "reason": "stored_support_position_invalid", "index": index}
		var current_position_value: Variant = current.get("world_position", null)
		var frozen_identity: String = String(frozen.get("binary32_position_identity", ""))
		if not frozen_position.is_finite() or not (current_position_value is Vector3) or not Vector3(current_position_value).is_finite() or frozen_identity.is_empty() or frozen_position.distance_to(Vector3(current_position_value)) > 0.0001:
			return {"valid": false, "reason": "support_position_bitwise_mismatch", "index": index, "support_id": current.get("support_id", "")}
	return {"valid": true, "count": regenerated.size()}

func _normalize_lattice(value: Variant) -> Variant:
	if value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Array and value.size() == 3:
		return [int(value[0]), int(value[1]), int(value[2])]
	if value is String:
		var raw: String = String(value)
		if raw.length() < 5 or raw[0] != "(" or raw[raw.length() - 1] != ")":
			return null
		var parts: PackedStringArray = raw.substr(1, raw.length() - 2).split(",")
		if parts.size() != 3:
			return null
		var parsed: Vector3i = Vector3i(int(parts[0].strip_edges()), int(parts[1].strip_edges()), int(parts[2].strip_edges()))
		if str(parsed) != raw:
			return null
		return [parsed.x, parsed.y, parsed.z]
	return null
func _projection_context(realizer: RefCounted, patch: Array[Dictionary], root_positions: Dictionary, cycle: Array) -> Dictionary:
	if cycle.size() < 3: return {"valid": false, "reason": "boundary_cycle_too_small"}
	var normal: Vector3 = Vector3.ZERO
	for triangle in patch:
		var normal_value: Variant = triangle.get("normal", null)
		if normal_value is Vector3: normal += Vector3(normal_value)
	if normal.length_squared() <= 1e-20: return {"valid": false, "reason": "patch_normal_unavailable"}
	normal = normal.normalized()
	var origin_id: String = String(cycle[0])
	if not root_positions.has(origin_id): return {"valid": false, "reason": "boundary_root_position_missing", "root_id": origin_id}
	var origin: Vector3 = Vector3(root_positions[origin_id])
	var axis_u: Vector3 = Vector3.ZERO
	for index in range(1, cycle.size()):
		var root_id: String = String(cycle[index])
		if not root_positions.has(root_id): return {"valid": false, "reason": "boundary_root_position_missing", "root_id": root_id}
		var candidate: Vector3 = Vector3(root_positions[root_id]) - origin
		candidate -= normal * candidate.dot(normal)
		if candidate.length_squared() > 1e-20:
			axis_u = candidate.normalized()
			break
	if axis_u.length_squared() <= 1e-20: return {"valid": false, "reason": "projection_axis_unavailable"}
	var axis_v: Vector3 = normal.cross(axis_u).normalized()
	if axis_v.length_squared() <= 1e-20: return {"valid": false, "reason": "projection_basis_invalid"}
	var polygon: Array[Vector2] = []
	for vertex_id_value in cycle:
		var vertex: Vector3 = Vector3(root_positions[String(vertex_id_value)])
		var delta: Vector3 = vertex - origin
		polygon.append(Vector2(delta.dot(axis_u), delta.dot(axis_v)))
	return {"valid": true, "origin": origin, "axis_u": axis_u, "axis_v": axis_v, "polygon": polygon}

func _project_support_position(position_value: Variant, context: Dictionary, realizer: RefCounted) -> Dictionary:
	if not bool(context.get("valid", false)) or not (position_value is Vector3) or not Vector3(position_value).is_finite():
		return {"valid": false, "inside_domain": false, "reason": "position_or_projection_context_invalid"}
	var delta: Vector3 = Vector3(position_value) - Vector3(context.origin)
	var projected: Vector2 = Vector2(delta.dot(Vector3(context.axis_u)), delta.dot(Vector3(context.axis_v)))
	var polygon: Array[Vector2] = context.get("polygon", [])
	var inside: bool = bool(realizer.call("_r2_point_in_polygon", projected, polygon))
	var on_boundary: bool = bool(realizer.call("_r2_point_on_polygon_boundary", projected, polygon))
	return {"valid": true, "projected_position": [projected.x, projected.y], "inside_domain": inside, "on_boundary": on_boundary}

func _position_array(value: Variant) -> Variant:
	if value is Vector3: return [value.x, value.y, value.z]
	return value

func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value: result.append(String(item))
	result.sort()
	return result

func _fail(reason: String, details: Dictionary) -> void:
	printerr("R4_D1_SUPPORT_VIABILITY_FAIL " + JSON.stringify({"reason": reason, "details": details}))
	quit(2)
