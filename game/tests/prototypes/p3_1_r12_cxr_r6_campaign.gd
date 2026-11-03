extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd")
const R6Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_r6_realizer.gd")
const R6FrozenSolver := preload("res://tests/prototypes/p3_1_r12_cxr_r6_frozen_solver.gd")
const Synthesizer := preload("res://tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd")
const Diagnostics := preload("res://tests/prototypes/p3_1_r12_cxr_r6_diagnostics.gd")
const CXRDownstream := preload("res://tests/prototypes/p3_1_r12_cxr_campaign.gd")
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
const R4SourceSha := "f48990e25ffb1d377e02a9182240cabe35c815eb"
const R4D1ResultSha := "927ec58f8f4e7821d9acb27a46068a4fa5fccf4f354f22b24be9cf88f90970c4"
const R4CavitySignature := "90be2d27d3c08ccb2fe93ebf6b8a0da0d8955d3c4d533a4496809b4d07bd363b"
const R5CavitySha := "a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6"
const FrozenSupportSetSha := "499292cff4e6f6904fed4bb5b44d0828f82b81fbf4c7846d4680bff412fd23ea"
const FrozenCandidateGraphSha := "de2f1121c60052324717c8d326536fc63890aacd5cc39f9a192a5f4ec4382e87"
const FrozenCandidateGraphAuditSha := "3fd0cd4db9c8ec088857c73c54475313c06ea549f2fef8ea83b0ccb7df294afd"
const FrozenCandidateTriangleCount: int = 1058
const FROZEN_CROSS_SQUARED_CUTOFF: float = 1.0e-12

var _terminal_failure_requested: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output_path: String = OS.get_environment("R12CXR_R6_OUTPUT")
	var mode: String = OS.get_environment("R12CXR_R6_MODE")
	if mode == "check-only":
		print("R6_CAMPAIGN_CHECK_ONLY=PASS")
		quit(0)
		return
	if mode == "writer-check":
		_run_evidence_writer_check()
		return
	if mode == "y1-resume-check":
		_run_y1_resume_check()
		return
	if mode.is_empty(): mode = "freeze"
	if mode not in ["freeze", "boundary-audit", "cavity-audit", "x3-cavity-search", "x3-cavity-realize", "x4-joint-support", "x4-targeted-evidence", "x6-representability", "x6-representability-evidence", "y1-complete-support", "y1-graph-partial", "synthesize", "resume-r6-06", "resume-x2-graph"]:
		_fail("r6_mode_invalid", {"mode": mode})
		return
	if output_path.is_empty() or FileAccess.file_exists(output_path):
		_fail("r6_output_path_invalid_or_exists", {})
		return
	var r4_result_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r5/r4-d1-result.json")
	if Core.sha256(r4_result_bytes) != R4D1ResultSha:
		_fail("r6_frozen_r4_d1_result_hash_mismatch", {"observed": Core.sha256(r4_result_bytes), "expected": R4D1ResultSha})
		return
	var r4_result_value: Variant = JSON.parse_string(r4_result_bytes.get_string_from_utf8())
	if typeof(r4_result_value) != TYPE_DICTIONARY or String(r4_result_value.get("source_sha", "")) != R4SourceSha:
		_fail("r6_frozen_r4_d1_result_identity_invalid", {})
		return
	var frozen_r4_result: Dictionary = r4_result_value
	var stage0_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/stage0-topology.json")
	var residual_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/residual-c6.json")
	var pool_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/support-pool-attempt07.json")
	var candidate_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
	if Core.sha256(stage0_bytes) != Stage0Sha or Core.sha256(residual_bytes) != ResidualSha or Core.sha256(pool_bytes) != SupportPoolSha:
		_fail("r4_d1_frozen_fixture_hash_mismatch", {"stage0": Core.sha256(stage0_bytes), "residual": Core.sha256(residual_bytes), "support_pool": Core.sha256(pool_bytes)})
		return
	if Core.sha256(candidate_bytes) != CandidateSha:
		_fail("r4_d1_candidate_d_source_hash_mismatch", {"observed": Core.sha256(candidate_bytes), "expected": CandidateSha})
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
	print("R6_R5_POOL_BASELINE_COMPARISON " + JSON.stringify({"r5_fixture_exact_match": pool_match.get("valid", false), "r5_regenerated_count": regenerated_rows.size(), "r5_fixture_count": stored_rows.size(), "candidate_attempt_count": candidate_attempt_count, "difference_reason": pool_match.get("reason", "") }))
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
	var frozen_d2: Dictionary = frozen_r4_result.get("boundary_first_d2", {})
	var frozen_patch_ids: Array[String] = _string_array(frozen_d2.get("patch_triangle_ids", []))
	var derived_patch_ids: Array[String] = _string_array(analysis_patch_ids)
	if frozen_patch_ids != derived_patch_ids or String(frozen_d2.get("boundary", {}).get("signature", "")) != R4CavitySignature or String(r4_context.get("boundary_signature", "")) != R4CavitySignature:
		_fail("r6_r4_cavity_reconstruction_mismatch", {"frozen_patch_ids": frozen_patch_ids, "derived_patch_ids": derived_patch_ids, "frozen_signature": frozen_d2.get("boundary", {}).get("signature", ""), "derived_signature": r4_context.get("boundary_signature", "")})
		return
	if mode == "resume-x2-graph":
		var prior_path: String = OS.get_environment("R12CXR_R6_RESUME_INPUT")
		var prior_sha: String = OS.get_environment("R12CXR_R6_RESUME_SHA256")
		var prior_bytes: PackedByteArray = FileAccess.get_file_as_bytes(prior_path) if FileAccess.file_exists(prior_path) else PackedByteArray()
		if prior_bytes.is_empty() or Core.sha256(prior_bytes) != prior_sha or prior_sha != "0228d8706b3f953053ef56da9ca6ea149e265e66811499ce2f7e30e7637aabae":
			_fail("r6_x2_graph_resume_raw_result_identity_invalid", {"path": prior_path, "observed_sha256": Core.sha256(prior_bytes), "expected_sha256": prior_sha})
			return
		var prior_value: Variant = JSON.parse_string(prior_bytes.get_string_from_utf8())
		if typeof(prior_value) != TYPE_DICTIONARY:
			_fail("r6_x2_graph_resume_raw_result_schema_invalid", {})
			return
		var prior_result: Dictionary = prior_value
		var prior_synthesis: Dictionary = prior_result.get("synthesis", {})
		var prior_completion: Dictionary = prior_result.get("r6_x2_support_completion", {})
		if String(prior_result.get("attempt_id", "")) != "R6-X2-20261102-02" or String(prior_result.get("source_sha", "")) != "9f581bb54aac8e204817f004de4e8cf8584225e9" or String(prior_result.get("status", "")) != "R6_X2_EXTENDED_GRAPH_PARTIAL" or not bool(prior_result.get("target_attempt_consumed", false)) or not bool(prior_synthesis.get("valid", false)) or not bool(prior_completion.get("support_domain_complete", false)) or not bool(prior_completion.get("deterministic_repeat_pass", false)) or int(prior_completion.get("support_count_added", 0)) != 3:
			_fail("r6_x2_graph_resume_source_stage_invalid", {"attempt_id": prior_result.get("attempt_id", ""), "source_sha": prior_result.get("source_sha", ""), "status": prior_result.get("status", ""), "target_attempt_consumed": prior_result.get("target_attempt_consumed", false), "synthesis_valid": prior_synthesis.get("valid", false), "support_domain_complete": prior_completion.get("support_domain_complete", false), "deterministic_repeat_pass": prior_completion.get("deterministic_repeat_pass", false), "support_count_added": prior_completion.get("support_count_added", 0)})
			return
		var resumed_realizer: RefCounted = R6Realizer.new()
		resumed_realizer.set("_root_positions", root_positions)
		resumed_realizer.set("_required_arc_keys", required_arc_keys)
		resumed_realizer.set("_locked_triplets", realizer.get("_locked_triplets"))
		resumed_realizer.set("_cxr_active_phase", "r6")
		resumed_realizer.set("_cxr_active_snapshot", snapshot)
		var resumed_pool_result: Dictionary = _r6_regenerate_support_rows(resumed_realizer, seed_triangles, analysis_patch, volume.get("values", PackedFloat32Array()), roi, support_fixture, seed_by_id)
		if not bool(resumed_pool_result.get("valid", false)):
			_fail("r6_x2_graph_resume_support_pool_regeneration_failed", resumed_pool_result)
			return
		var prior_cavity: Dictionary = prior_result.get("cavity_search", {})
		var prior_selected_ids: Array = prior_cavity.get("selected", {}).get("face_ids", [])
		var prior_selected_boundary: Dictionary = prior_cavity.get("selected", {}).get("audit", {}).get("boundary", {})
		if prior_selected_ids.size() != 6 or String(prior_cavity.get("status", "")) != "FOUND" or not bool(prior_cavity.get("deterministic_repeat", {}).get("pass", false)):
			_fail("r6_x2_graph_resume_cavity_identity_invalid", {"status": prior_cavity.get("status", ""), "selected_face_count": prior_selected_ids.size(), "deterministic_repeat": prior_cavity.get("deterministic_repeat", {})})
			return
		var prior_selected_patch: Array[Dictionary] = resumed_realizer.call("_r3_patch_rows_for_ids", triangles, prior_selected_ids)
		var resume_search_fixture: Dictionary = search_residual_fixture.duplicate(true)
		resume_search_fixture["applied_flips"] = base.get("applied_flips", []).duplicate(true)
		var baseline_context_result: Dictionary = resumed_realizer.call("_r3_make_expanded_patch_context", prior_selected_patch, prior_selected_ids, seed_triangles, resumed_pool_result.get("rows", []), prior_selected_boundary, triangles, resume_search_fixture, 2, false)
		if not bool(baseline_context_result.get("valid", false)) or baseline_context_result.get("context", {}).is_empty():
			_fail("r6_x2_graph_resume_baseline_context_rebuild_failed", baseline_context_result)
			return
		var baseline_context: Dictionary = baseline_context_result.get("context", {})
		var baseline_synthesis: Dictionary = Synthesizer.new().call("synthesize", resumed_realizer, volume.get("values", PackedFloat32Array()), roi, baseline_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []))
		var expected_baseline_support_sha: String = String(prior_completion.get("baseline_support_set_sha256", ""))
		if not bool(baseline_synthesis.get("valid", false)) or _support_synthesis_fingerprint(baseline_synthesis) != expected_baseline_support_sha:
			_fail("r6_x2_graph_resume_baseline_support_identity_mismatch", {"valid": baseline_synthesis.get("valid", false), "observed": _support_synthesis_fingerprint(baseline_synthesis), "expected": expected_baseline_support_sha})
			return
		var merged_supports: Array[Dictionary] = baseline_synthesis.get("supports", []).duplicate(true)
		for support_value in prior_completion.get("supports", []):
			if typeof(support_value) != TYPE_DICTIONARY:
				_fail("r6_x2_graph_resume_extension_support_row_invalid", {})
				return
			var restored_support: Dictionary = support_value.duplicate(true)
			var restored_position: Variant = restored_support.get("world_position", null)
			if restored_position is Array and restored_position.size() == 3:
				restored_support["world_position"] = Vector3(float(restored_position[0]), float(restored_position[1]), float(restored_position[2]))
			if not (restored_support.get("world_position", null) is Vector3):
				_fail("r6_x2_graph_resume_extension_support_position_invalid", {"support_id": restored_support.get("support_id", ""), "world_position": restored_position})
				return
			merged_supports.append(restored_support)
		merged_supports.sort_custom(Callable(resumed_realizer, "_candidate_less"))
		var resumed_synthesis: Dictionary = baseline_synthesis.duplicate(true)
		resumed_synthesis["supports"] = merged_supports
		resumed_synthesis["retained_support_count"] = merged_supports.size()
		resumed_synthesis["raw_unique_support_count"] = int(baseline_synthesis.get("raw_unique_support_count", 0)) + prior_completion.get("supports", []).size()
		if prior_completion.get("supports", []).size() != 3 or String(prior_completion.get("support_fingerprint_sha256", "")) != String(prior_completion.get("repeat_fingerprint_sha256", "")):
			_fail("r6_x2_graph_resume_extension_support_evidence_invalid", {"support_count": prior_completion.get("supports", []).size(), "first_fingerprint": prior_completion.get("support_fingerprint_sha256", ""), "repeat_fingerprint": prior_completion.get("repeat_fingerprint_sha256", "")})
			return
		var resumed_context_result: Dictionary = resumed_realizer.call("_r3_make_expanded_patch_context", prior_selected_patch, prior_selected_ids, seed_triangles, merged_supports, prior_selected_boundary, triangles, resume_search_fixture, 2, false)
		if not bool(resumed_context_result.get("valid", false)) or resumed_context_result.get("context", {}).is_empty():
			_fail("r6_x2_graph_resume_context_rebuild_failed", resumed_context_result)
			return
		var resumed_context: Dictionary = resumed_context_result.get("context", {})
		var resumed_support_sha: String = _support_synthesis_fingerprint(resumed_synthesis)
		if resumed_support_sha != "a6c9ea20d53a1cd49c5bf0c0ac86fcb63a6163dd4e3aefba146dadd6b4ecedc5" or String(prior_completion.get("baseline_candidate_graph_sha256", "")) != "a975ef820773f09106c9adafb2186345d41d7ea8955a60dcf92a235bdbfa9363" or String(prior_completion.get("baseline_solver_status", "")) != "UNSAT_COMPLETE":
			_fail("r6_x2_graph_resume_completed_extension_identity_invalid", {"support_set_sha256": resumed_support_sha, "baseline_candidate_graph_sha256": prior_completion.get("baseline_candidate_graph_sha256", ""), "baseline_solver_status": prior_completion.get("baseline_solver_status", "")})
			return
		var completed_extension_summary: Dictionary = {"support_domain_complete": bool(prior_completion.get("support_domain_complete", false)), "deterministic_repeat_pass": bool(prior_completion.get("deterministic_repeat_pass", false)), "baseline_solver_status": String(prior_completion.get("baseline_solver_status", "")), "support_set_sha256": resumed_support_sha}
		var resume_metadata: Dictionary = {"is_continuation": true, "same_attempt_id": String(prior_result.get("attempt_id", "")), "domain_extension": "R6-X2", "resume_completed_extension": true, "completed_extension_summary": completed_extension_summary, "expected_support_count": 26, "expected_support_set_sha256": resumed_support_sha, "expected_candidate_triangle_count": 1261, "expected_candidate_graph_sha256": "a975ef820773f09106c9adafb2186345d41d7ea8955a60dcf92a235bdbfa9363", "expected_candidate_graph_audit_sha256": "cc76ced73db084674837980792a67b95bbc1cdcba0a07ab2da6b6866e8748aa2", "original_target_source_sha": String(prior_result.get("source_sha", "")), "continuation_source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "original_target_result_sha256": prior_sha, "original_target_attempt_consumed": true, "additional_target_attempts_consumed": 0, "reason": "resume the same consumed R6-X2 geometry from its preserved complete support-domain and deterministic-repeat evidence; prior graph gate used a stale per-cavity clock after the baseline graph pass and its complete graph identity matches the already complete R6-X1 graph", "support_set_identical": true, "support_set_sha256": resumed_support_sha}
		var resumed_result: Dictionary = _run_constraint_synthesis(resumed_realizer, volume.get("values", PackedFloat32Array()), roi, resumed_context, prior_selected_patch, prior_selected_ids, seed_triangles, prior_selected_boundary, triangles, resume_search_fixture, base, snapshot, support_fixture, residual_fixture.get("residuals", []), output_path, prior_cavity, resumed_synthesis, resume_metadata)
		if resumed_result.is_empty() or _terminal_failure_requested: return
		var resumed_completion: Dictionary = prior_completion.duplicate(true)
		resumed_completion["extended_graph"] = {"complete": bool(resumed_result.get("graph_gate", {}).get("complete", false)), "vertex_count": resumed_result.get("graph_gate", {}).get("vertex_count", -1), "possible_triplets": resumed_result.get("graph_gate", {}).get("possible_triplets", -1), "probed_triplets": resumed_result.get("graph_gate", {}).get("probed_triplets", -1), "legal_triangle_count": resumed_result.get("graph_gate", {}).get("legal_triangle_count", -1), "candidate_graph_sha256": resumed_result.get("d3", {}).get("candidate_graph_sha256", resumed_result.get("frozen_graph_identity_check", {}).get("observed_candidate_graph_sha256", "")), "audit_sha256": resumed_result.get("graph_gate", {}).get("audit_sha256", ""), "limit_reason": resumed_result.get("graph_gate", {}).get("limit_reason", ""), "graph_gate_usec": resumed_result.get("graph_gate", {}).get("graph_gate_usec", -1), "resumed_from_same_attempt": true, "additional_target_attempts_consumed": 0}
		resumed_completion["extended_candidate_triangle_rows"] = resumed_result.get("candidate_triangle_rows", []).duplicate(true)
		resumed_result["r6_x2_support_completion"] = resumed_completion
		resumed_result["r6_x2_graph_resume"] = {"started": true, "same_attempt_continuation": true, "original_target_source_sha": prior_result.get("source_sha", ""), "original_target_result_sha256": prior_sha, "continuation_source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "reused_support_set_sha256": resume_metadata.support_set_sha256, "stale_timer_diagnosis": "the baseline candidate-graph enumeration left the original per-cavity clock expired; the X2 extension graph scan inherited that clock and stopped on its first triplet", "geometry_domain_changed": false}
		resumed_result["attempt_accounting"] = {"baseline_r6_06_attempts_consumed": 1, "r6_x1_attempts_consumed": 1, "r6_x2_attempts_consumed": 1, "cumulative_valid_scientific_target_attempts": 3, "unconsumed_tooling_failures_preserved": 3, "attempt_id": String(prior_result.get("attempt_id", "")), "continuation_additional_attempts_consumed": 0}
		var resumed_bytes: PackedByteArray = _json_evidence_bytes(resumed_result)
		var resumed_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if resumed_file == null:
			_fail("r6_x2_graph_resume_final_write_failed", {"path": output_path, "error": FileAccess.get_open_error()})
			return
		resumed_file.store_buffer(resumed_bytes)
		resumed_file.close()
		if FileAccess.get_open_error() != OK:
			_fail("r6_x2_graph_resume_final_close_failed", {"path": output_path})
			return
		var resume_result_sha: String = Core.sha256(resumed_bytes)
		print("R12CXR_R6_X2_GRAPH_RESUMED " + JSON.stringify({"attempt_id": prior_result.get("attempt_id", ""), "source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "original_result_sha256": prior_sha, "result_sha256": resume_result_sha, "status": resumed_result.get("status", ""), "terminal_reason": resumed_result.get("terminal_reason", ""), "additional_target_attempts_consumed": 0}))
		quit(0)
		return
	var fixture_result: Dictionary = _build_frozen_cavity_fixture(realizer, r4_context, analysis_patch, analysis_patch_ids, analysis_boundary, cycle, boundary_first_result, root_positions, frozen_r4_result)
	if not bool(fixture_result.get("valid", false)):
		_fail("r6_frozen_cavity_fixture_build_failed", fixture_result)
		return
	var fixture_bytes: PackedByteArray = JSON.stringify(fixture_result.get("fixture", {}), "\t", false).to_utf8_buffer()
	var pinned_cavity_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r5/frozen-cavity.json")
	if Core.sha256(pinned_cavity_bytes) != R5CavitySha or pinned_cavity_bytes != fixture_bytes:
		_fail("r6_frozen_cavity_geometry_reconstruction_mismatch", {"observed_sha256": Core.sha256(pinned_cavity_bytes), "expected_sha256": R5CavitySha, "reconstructed_sha256": Core.sha256(fixture_bytes), "exact_bytes_match": pinned_cavity_bytes == fixture_bytes})
		return
	print("R6_FROZEN_CAVITY_RECONSTRUCTED " + JSON.stringify({"fixture_sha256": Core.sha256(pinned_cavity_bytes), "exact_bytes_match": pinned_cavity_bytes == fixture_bytes}))
	if mode == "boundary-audit":
		var source_sha: String = OS.get_environment("R12CXR_SOURCE_SHA")
		if source_sha.length() != 40 or not source_sha.is_valid_hex_number():
			_fail("r6_boundary_audit_source_identity_invalid", {"source_sha": source_sha})
			return
		var boundary_diagnostics: RefCounted = Diagnostics.new()
		var boundary_realizer: RefCounted = R6Realizer.new()
		boundary_realizer.set("_root_positions", root_positions)
		boundary_realizer.set("_required_arc_keys", required_arc_keys)
		boundary_realizer.set("_locked_triplets", realizer.get("_locked_triplets"))
		boundary_realizer.set("_cxr_active_snapshot", snapshot)
		var zero_inventory: Dictionary = boundary_diagnostics.call("collect_zero_facet_inventory", realizer, volume.get("values", PackedFloat32Array()), roi)
		if not bool(zero_inventory.get("valid", false)):
			_fail("r6_boundary_audit_zero_inventory_invalid", zero_inventory)
			return
		var zero_facets: Array[Dictionary] = zero_inventory.get("facets", [])
		var projection: Dictionary = {"origin": _vector3_array(Vector3(r4_context.get("projection_origin", Vector3.ZERO))), "axis_u": _vector3_array(Vector3(r4_context.get("projection_u", Vector3.ZERO))), "axis_v": _vector3_array(Vector3(r4_context.get("projection_v", Vector3.ZERO)))}
		var audit: Dictionary = boundary_diagnostics.call("analyze_patch_boundary", boundary_realizer, analysis_patch, cycle, root_positions, projection, zero_facets)
		var result: Dictionary = {"schema": "P3.1.R12CXR.R6.D0BoundaryWitnessAudit.v1", "status": "DIAGNOSTIC_COMPLETE" if bool(audit.get("valid", false)) else "DIAGNOSTIC_FAILED", "source_sha": source_sha, "target_id": TargetId, "target_attempt_consumed": false, "target_attempt_phase": "R6-D0", "frozen_cavity_sha256": Core.sha256(pinned_cavity_bytes), "frozen_volume_sha256": VolumeSha, "frozen_payload_sha256": PayloadSha, "topology_sha256": TopologySha, "graph_sha256": GraphSha, "boundary_cycle": cycle.duplicate(), "patch_face_ids": analysis_patch_ids.duplicate(), "zero_facet_count": zero_facets.size(), "zero_facet_inventory_sha256": boundary_diagnostics.call("_r6_facets_signature", zero_facets), "boundary_audit": audit}
		var audit_written: bool = _write_result(output_path, result, "R12CXR_R6_D0_BOUNDARY_WITNESS_AUDIT")
		quit(0 if bool(audit.get("valid", false)) and audit_written else 3)
		return
	if mode in ["cavity-audit", "x3-cavity-search"]:
		var source_sha: String = OS.get_environment("R12CXR_SOURCE_SHA")
		if source_sha.length() != 40 or not source_sha.is_valid_hex_number():
			_fail("r6_cavity_audit_source_identity_invalid", {"source_sha": source_sha})
			return
		var cavity_diagnostics: RefCounted = Diagnostics.new()
		var cavity_realizer: RefCounted = R6Realizer.new()
		cavity_realizer.set("_root_positions", root_positions)
		cavity_realizer.set("_required_arc_keys", required_arc_keys)
		cavity_realizer.set("_locked_triplets", realizer.get("_locked_triplets"))
		cavity_realizer.set("_cxr_active_phase", "r6")
		cavity_realizer.set("_cxr_active_snapshot", snapshot)
		var pool_result: Dictionary = _r6_regenerate_support_rows(cavity_realizer, seed_triangles, analysis_patch, volume.get("values", PackedFloat32Array()), roi, support_fixture, seed_by_id)
		if not bool(pool_result.get("valid", false)):
			_fail("r6_cavity_audit_support_regeneration_failed", pool_result)
			return
		var zero_inventory: Dictionary = cavity_diagnostics.call("collect_zero_facet_inventory", realizer, volume.get("values", PackedFloat32Array()), roi)
		if not bool(zero_inventory.get("valid", false)):
			_fail("r6_cavity_audit_zero_inventory_invalid", zero_inventory)
			return
		var projection: Dictionary = {"origin": _vector3_array(Vector3(r4_context.get("projection_origin", Vector3.ZERO))), "axis_u": _vector3_array(Vector3(r4_context.get("projection_u", Vector3.ZERO))), "axis_v": _vector3_array(Vector3(r4_context.get("projection_v", Vector3.ZERO)))}
		var x3_search: bool = mode == "x3-cavity-search"
		var search_limits: Dictionary = {"max_faces": 12, "max_states": 10000, "max_queue": 2000, "max_ms": 30000}
		if x3_search:
			search_limits["enumerate_alternatives"] = true
			search_limits["max_atomic_faces"] = 4
			search_limits["max_bundles_per_state"] = 4096
			search_limits["max_bundles_total"] = 16384
		var cavity_search: Dictionary = cavity_diagnostics.call("search_patch_cavities", cavity_realizer, triangles, analysis_patch_ids, root_positions, projection, zero_inventory.get("facets", []), search_limits)
		var result: Dictionary = {"schema": "P3.1.R12CXR.R6.CavityDiagnostic.v1", "status": cavity_search.get("status", "UNKNOWN_NOT_CAPTURED"), "terminal_reason": cavity_search.get("terminal_reason", cavity_search.get("reason", "UNKNOWN_NOT_CAPTURED")), "source_sha": source_sha, "target_id": TargetId, "target_attempt_consumed": false, "target_attempt_phase": "R6-X3-ALTERNATIVE-CAVITY-DIAGNOSTIC" if x3_search else "R6-D-DIAGNOSTIC", "frozen_cavity_sha256": Core.sha256(pinned_cavity_bytes), "frozen_volume_sha256": VolumeSha, "frozen_payload_sha256": PayloadSha, "topology_sha256": TopologySha, "graph_sha256": GraphSha, "zero_facet_count": zero_inventory.get("facets", []).size(), "support_regeneration": {"valid": pool_result.get("valid", false), "candidate_attempt_count": pool_result.get("candidate_attempt_count", -1), "row_count": pool_result.get("rows", []).size(), "r5_fixture_exact_match": pool_match.get("valid", false)}, "limits": search_limits, "topology_path_policy": "DIRECT_ARC_BARRIERS_NOT_IMPOSED; PIECEWISE_PATH_FEASIBILITY_REMAINS_A_R6-C/E/F-GATE", "search": cavity_search}
		var cavity_written: bool = _write_result(output_path, result, "R12CXR_R6_X3_ALTERNATIVE_CAVITY" if x3_search else "R12CXR_R6_CAVITY_DIAGNOSTIC")
		quit(0 if cavity_written else 3)
		return
	if mode == "x3-cavity-realize":
		var source_sha: String = OS.get_environment("R12CXR_SOURCE_SHA")
		var attempt_id: String = OS.get_environment("R12CXR_R6_ATTEMPT_ID")
		var x3_search_path: String = OS.get_environment("R12CXR_R6_X3_SEARCH_INPUT")
		var x3_search_sha: String = OS.get_environment("R12CXR_R6_X3_SEARCH_SHA256")
		var x3_search_bytes: PackedByteArray = FileAccess.get_file_as_bytes(x3_search_path) if FileAccess.file_exists(x3_search_path) else PackedByteArray()
		if source_sha.length() != 40 or attempt_id != "R6-X3-20261102-01" or x3_search_bytes.is_empty() or Core.sha256(x3_search_bytes) != x3_search_sha or x3_search_sha != "ec8cd49e5a7855c7fe24b47cfd87e5572038fea4a52ff54c82c76c001bba61db":
			_fail("r6_x3_alternative_search_identity_invalid", {"source_sha": source_sha, "attempt_id": attempt_id, "search_sha256": Core.sha256(x3_search_bytes), "expected_search_sha256": x3_search_sha})
			return
		var x3_search_value: Variant = JSON.parse_string(x3_search_bytes.get_string_from_utf8())
		if typeof(x3_search_value) != TYPE_DICTIONARY:
			_fail("r6_x3_alternative_search_schema_invalid", {})
			return
		var x3_diagnostic: Dictionary = x3_search_value
		var x3_search: Dictionary = x3_diagnostic.get("search", {})
		var selected_alternative: Dictionary = x3_search.get("selected", {})
		var selected_audit: Dictionary = selected_alternative.get("audit", {})
		var selected_ids: Array = selected_alternative.get("face_ids", [])
		if String(x3_diagnostic.get("status", "")) != "PARTIAL" or String(x3_diagnostic.get("terminal_reason", "")) != "WALL_TIME_CAP" or selected_ids.size() != 7 or selected_ids == analysis_patch_ids or not bool(selected_audit.get("manifold", false)) or int(selected_audit.get("boundary_components", 0)) != 1 or not selected_audit.get("unrealizable_edges", []).is_empty() or not selected_audit.get("unresolved_edges", []).is_empty():
			_fail("r6_x3_alternative_cavity_candidate_invalid", {"search_status": x3_diagnostic.get("status", ""), "terminal_reason": x3_diagnostic.get("terminal_reason", ""), "selected_face_count": selected_ids.size(), "selected_is_initial": selected_ids == analysis_patch_ids, "audit": {"manifold": selected_audit.get("manifold", false), "boundary_components": selected_audit.get("boundary_components", -1), "unrealizable_edges": selected_audit.get("unrealizable_edges", []), "unresolved_edges": selected_audit.get("unresolved_edges", [])}})
			return
		var x3_realizer: RefCounted = R6Realizer.new()
		x3_realizer.set("_root_positions", root_positions)
		x3_realizer.set("_required_arc_keys", required_arc_keys)
		x3_realizer.set("_locked_triplets", realizer.get("_locked_triplets"))
		x3_realizer.set("_cxr_active_phase", "r6")
		x3_realizer.set("_cxr_active_snapshot", snapshot)
		var x3_patch: Array[Dictionary] = x3_realizer.call("_r3_patch_rows_for_ids", triangles, selected_ids)
		var x3_boundary: Dictionary = x3_realizer.call("_r3_derive_remaining_boundary", triangles, selected_ids)
		var x3_connectivity: Dictionary = x3_realizer.call("_r3_patch_connectivity", x3_patch)
		if x3_patch.size() != selected_ids.size() or not bool(x3_boundary.get("valid", false)) or not bool(x3_connectivity.get("valid", false)) or String(x3_boundary.get("signature", "")) != String(selected_audit.get("boundary", {}).get("signature", "")):
			_fail("r6_x3_alternative_cavity_rebuild_invalid", {"patch_count": x3_patch.size(), "expected_face_count": selected_ids.size(), "boundary": x3_boundary, "connectivity": x3_connectivity, "diagnostic_boundary_signature": selected_audit.get("boundary", {}).get("signature", "")})
			return
		var x3_pool: Dictionary = _r6_regenerate_support_rows(x3_realizer, seed_triangles, x3_patch, volume.get("values", PackedFloat32Array()), roi, support_fixture, seed_by_id)
		if not bool(x3_pool.get("valid", false)):
			_fail("r6_x3_support_pool_regeneration_invalid", x3_pool)
			return
		var x3_search_fixture: Dictionary = search_residual_fixture.duplicate(true)
		x3_search_fixture["applied_flips"] = base.get("applied_flips", []).duplicate(true)
		var x3_context_preflight: Dictionary = x3_realizer.call("_r3_make_expanded_patch_context", x3_patch, selected_ids, seed_triangles, x3_pool.get("rows", []), x3_boundary, triangles, x3_search_fixture, 2, true)
		if not bool(x3_context_preflight.get("valid", false)):
			_fail("r6_x3_candidate_support_context_preflight_failed", {"search_sha256": x3_search_sha, "face_ids": selected_ids, "context": x3_context_preflight})
			return
		var x3_context_full: Dictionary = x3_realizer.call("_r3_make_expanded_patch_context", x3_patch, selected_ids, seed_triangles, x3_pool.get("rows", []), x3_boundary, triangles, x3_search_fixture, 2, false)
		if not bool(x3_context_full.get("valid", false)) or x3_context_full.get("context", {}).is_empty():
			_fail("r6_x3_candidate_support_context_invalid", x3_context_full)
			return
		var x3_context: Dictionary = x3_context_full.get("context", {})
		var x3_synthesis: Dictionary = Synthesizer.new().call("synthesize", x3_realizer, volume.get("values", PackedFloat32Array()), roi, x3_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []), [], false, Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS)
		if not bool(x3_synthesis.get("valid", false)):
			_fail("r6_x3_support_synthesis_invalid", x3_synthesis)
			return
		var x3_projection: Dictionary = {"origin": _vector3_array(Vector3(r4_context.get("projection_origin", Vector3.ZERO))), "axis_u": _vector3_array(Vector3(r4_context.get("projection_u", Vector3.ZERO))), "axis_v": _vector3_array(Vector3(r4_context.get("projection_v", Vector3.ZERO)))}
		var x3_diagnostics: RefCounted = Diagnostics.new()
		var x3_zero_inventory: Dictionary = x3_diagnostics.call("collect_zero_facet_inventory", realizer, volume.get("values", PackedFloat32Array()), roi)
		if not bool(x3_zero_inventory.get("valid", false)):
			_fail("r6_x3_zero_facet_inventory_invalid", x3_zero_inventory)
			return
		var x3_cycles: Dictionary = x3_realizer.call("_r4_boundary_cycle_set", x3_boundary)
		var x3_cycle: Array = x3_cycles.get("cycles", [{}])[0].get("root_ids", [])
		var x3_boundary_first: Dictionary = x3_diagnostics.call("analyze_patch_boundary", x3_realizer, x3_patch, x3_cycle, root_positions, x3_projection, x3_zero_inventory.get("facets", []))
		var x3_diagnostics_repeat: RefCounted = Diagnostics.new()
		var x3_boundary_repeat: Dictionary = x3_diagnostics_repeat.call("analyze_patch_boundary", x3_realizer, x3_patch, x3_cycle, root_positions, x3_projection, x3_zero_inventory.get("facets", []))
		var x3_boundary_first_sha: String = _stable_evidence_sha({"valid": x3_boundary_first.get("valid", false), "boundary_edges": x3_boundary_first.get("boundary_edges", [])})
		var x3_boundary_repeat_sha: String = _stable_evidence_sha({"valid": x3_boundary_repeat.get("valid", false), "boundary_edges": x3_boundary_repeat.get("boundary_edges", [])})
		var x3_cavity_search: Dictionary = x3_search.duplicate(true)
		x3_cavity_search["deterministic_repeat"] = {"started": true, "pass": bool(x3_boundary_first.get("valid", false)) and bool(x3_boundary_repeat.get("valid", false)) and x3_boundary_first_sha == x3_boundary_repeat_sha, "method": "INDEPENDENT_ANALYTIC_BOUNDARY_REAUDIT", "first_fingerprint_sha256": x3_boundary_first_sha, "repeat_fingerprint_sha256": x3_boundary_repeat_sha, "selected_boundary_signature": x3_boundary.get("signature", ""), "repeat_boundary_signature": x3_boundary.get("signature", ""), "boundary_analysis_valid": x3_boundary_first.get("valid", false) and x3_boundary_repeat.get("valid", false)}
		if not bool(x3_cavity_search.deterministic_repeat.pass):
			_fail("r6_x3_selected_boundary_reaudit_failed", {"first": x3_boundary_first, "repeat": x3_boundary_repeat})
			return
		var x3_support_sha: String = _support_synthesis_fingerprint(x3_synthesis)
		var x3_metadata: Dictionary = {"domain_extension": "R6-X3", "x3_alternative_cavity": true, "expected_support_count": x3_synthesis.get("supports", []).size(), "expected_support_set_sha256": x3_support_sha, "resume_completed_extension": true, "completed_extension_summary": {"support_domain_complete": bool(x3_synthesis.get("finite_candidate_enumeration_complete", false)), "deterministic_repeat_pass": true, "support_set_sha256": x3_support_sha}, "original_target_source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "additional_target_attempts_consumed": 1, "reason": "test the highest-ranked manifold alternative cavity found by the bounded X3 search after X2 complete finite-graph UNSAT; the 30-second alternative search itself remains PARTIAL", "alternative_search_sha256": x3_search_sha, "alternative_search_terminal_reason": String(x3_diagnostic.get("terminal_reason", "")), "candidate_face_ids": selected_ids.duplicate(), "support_set_sha256": x3_support_sha}
		var x3_result: Dictionary = _run_constraint_synthesis(x3_realizer, volume.get("values", PackedFloat32Array()), roi, x3_context, x3_patch, selected_ids, seed_triangles, x3_boundary, triangles, x3_search_fixture, base, snapshot, support_fixture, residual_fixture.get("residuals", []), output_path, x3_cavity_search, x3_synthesis, x3_metadata)
		if x3_result.is_empty() or _terminal_failure_requested: return
		x3_result["r6_x3_alternative_cavity"] = {"started": true, "attempt_id": attempt_id, "search_source_sha": x3_diagnostic.get("source_sha", ""), "search_result_sha256": x3_search_sha, "search_status": x3_diagnostic.get("status", ""), "search_terminal_reason": x3_diagnostic.get("terminal_reason", ""), "search_finite_domain_exhausted": x3_search.get("finite_domain_exhausted", false), "search_examined_states": x3_search.get("examined_states", -1), "search_generated_states": x3_search.get("generated_states", -1), "search_queue_depth": x3_search.get("queue_depth", -1), "search_limits": x3_diagnostic.get("limits", {}), "selected_face_ids": selected_ids.duplicate(), "selected_face_count": selected_ids.size(), "selected_cavity_boundary_signature": x3_boundary.get("signature", ""), "selected_cavity_audit": selected_audit, "support_pool_exact_match": pool_match.get("valid", false), "attempt_domain_changed": true, "attempt_target_consumed": true}
		x3_result["attempt_accounting"] = {"baseline_r6_06_attempts_consumed": 1, "r6_x1_attempts_consumed": 1, "r6_x2_attempts_consumed": 1, "r6_x3_attempts_consumed": 1, "cumulative_valid_scientific_target_attempts": 4, "unconsumed_tooling_failures_preserved": 3, "attempt_id": attempt_id}
		var x3_result_bytes: PackedByteArray = _json_evidence_bytes(x3_result)
		var x3_result_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if x3_result_file == null:
			_fail("r6_x3_result_final_write_failed", {"error": FileAccess.get_open_error()})
			return
		x3_result_file.store_buffer(x3_result_bytes)
		x3_result_file.close()
		print("R12CXR_R6_X3_ALTERNATIVE_REALIZED " + JSON.stringify({"attempt_id": attempt_id, "status": x3_result.get("status", ""), "terminal_reason": x3_result.get("terminal_reason", ""), "result_sha256": Core.sha256(x3_result_bytes), "target_attempt_consumed": true}))
		quit(0)
		return
	if mode in ["x4-joint-support", "x4-targeted-evidence", "x6-representability", "x6-representability-evidence", "y1-complete-support", "y1-graph-partial"]:
		var x6_representability: bool = mode in ["x6-representability", "x6-representability-evidence"]
		var y1_complete_support: bool = mode in ["y1-complete-support", "y1-graph-partial"]
		var y1_graph_partial: bool = mode == "y1-graph-partial"
		var x4_evidence_only: bool = mode in ["x4-targeted-evidence", "x6-representability-evidence"]
		var directed_axis_bracket: bool = x6_representability
		var x4_source_sha: String = OS.get_environment("R12CXR_SOURCE_SHA")
		var x4_attempt_id: String = OS.get_environment("R12CXR_R6_ATTEMPT_ID")
		var x4_previous_path: String = OS.get_environment("R12CXR_R6_X4_PREVIOUS_INPUT")
		var x4_previous_sha: String = OS.get_environment("R12CXR_R6_X4_PREVIOUS_SHA256")
		var x4_previous_bytes: PackedByteArray = FileAccess.get_file_as_bytes(x4_previous_path) if FileAccess.file_exists(x4_previous_path) else PackedByteArray()
		var expected_x4_run_id: String = "R6-Y1-COMPLETE-SUPPORT-20261102-01" if y1_complete_support else "R6-X6-REPRESENTABILITY-EVIDENCE-20261102-01" if mode == "x6-representability-evidence" else "R6-X6-REPRESENTABILITY-20261102-01" if x6_representability else "R6-X4-EVIDENCE-20261102-01" if x4_evidence_only else "R6-X4-20261102-01"
		if x4_source_sha.length() != 40 or not x4_source_sha.is_valid_hex_number() or x4_attempt_id != expected_x4_run_id or x4_previous_sha != "f7fd6ba64df9fb2b515930c245b2c59c50a24e7fa77fcc835bd83d38ce8b2661" or Core.sha256(x4_previous_bytes) != x4_previous_sha:
			_fail("r6_x4_previous_x3_result_identity_invalid", {"source_sha": x4_source_sha, "attempt_id": x4_attempt_id, "previous_sha256": Core.sha256(x4_previous_bytes), "expected_previous_sha256": x4_previous_sha})
			return
		var x4_previous_value: Variant = JSON.parse_string(x4_previous_bytes.get_string_from_utf8())
		if typeof(x4_previous_value) != TYPE_DICTIONARY:
			_fail("r6_x4_previous_x3_result_schema_invalid", {})
			return
		var x4_previous: Dictionary = x4_previous_value
		var x4_previous_synthesis: Dictionary = x4_previous.get("synthesis", {})
		var x4_previous_d3: Dictionary = x4_previous.get("d3", {})
		var x4_previous_graph: Dictionary = x4_previous.get("graph_gate", {})
		if String(x4_previous.get("attempt_id", "")) != "R6-X3-20261102-01" or not bool(x4_previous.get("target_attempt_consumed", false)) or String(x4_previous.get("status", "")) != "R6_X3_TRIANGULATION_PARTIAL" or not bool(x4_previous_graph.get("complete", false)) or String(x4_previous_d3.get("status", "")) != "UNSAT_COMPLETE" or String(x4_previous_synthesis.get("cap_reason", "")) != "R5_MAX_CRITICAL_CANDIDATES_TOTAL":
			_fail("r6_x4_x3_obstruction_not_qualified", {"prior_status": x4_previous.get("status", ""), "prior_target_consumed": x4_previous.get("target_attempt_consumed", false), "graph_complete": x4_previous_graph.get("complete", false), "solver_status": x4_previous_d3.get("status", ""), "support_cap_reason": x4_previous_synthesis.get("cap_reason", "")})
			return
		var x4_obligations: Dictionary = _r6_x4_zero_boundary_targets(x4_previous_d3.get("boundary_edge_candidate_counts", {}))
		if not bool(x4_obligations.get("valid", false)):
			_fail("r6_x4_no_obligation_directed_targets", x4_obligations)
			return
		var x4_selected_ids: Array = x4_previous.get("selected_patch_triangle_ids", []).duplicate()
		var x4_cavity_meta: Dictionary = x4_previous.get("r6_x3_alternative_cavity", {})
		var x4_selected_audit: Dictionary = x4_cavity_meta.get("selected_cavity_audit", {})
		if x4_selected_ids.size() != 7 or not bool(x4_selected_audit.get("valid", false)) or not bool(x4_selected_audit.get("manifold", false)) or int(x4_selected_audit.get("boundary_components", 0)) != 1 or not x4_selected_audit.get("unrealizable_edges", []).is_empty() or not x4_selected_audit.get("unresolved_edges", []).is_empty():
			_fail("r6_x4_prior_alternative_cavity_audit_invalid", {"face_count": x4_selected_ids.size(), "audit": x4_selected_audit})
			return
		var x4_realizer: RefCounted = R6Realizer.new()
		x4_realizer.set("_root_positions", root_positions)
		x4_realizer.set("_required_arc_keys", required_arc_keys)
		x4_realizer.set("_locked_triplets", realizer.get("_locked_triplets"))
		x4_realizer.set("_cxr_active_phase", "r6")
		x4_realizer.set("_cxr_active_snapshot", snapshot)
		var x4_patch: Array[Dictionary] = x4_realizer.call("_r3_patch_rows_for_ids", triangles, x4_selected_ids)
		var x4_boundary: Dictionary = x4_realizer.call("_r3_derive_remaining_boundary", triangles, x4_selected_ids)
		var x4_connectivity: Dictionary = x4_realizer.call("_r3_patch_connectivity", x4_patch)
		if x4_patch.size() != x4_selected_ids.size() or not bool(x4_boundary.get("valid", false)) or not bool(x4_connectivity.get("valid", false)) or String(x4_boundary.get("signature", "")) != String(x4_cavity_meta.get("selected_cavity_boundary_signature", "")):
			_fail("r6_x4_alternative_cavity_rebuild_invalid", {"patch_count": x4_patch.size(), "boundary": x4_boundary, "connectivity": x4_connectivity})
			return
		var x4_support_pool: Dictionary = _r6_regenerate_support_rows(x4_realizer, seed_triangles, x4_patch, volume.get("values", PackedFloat32Array()), roi, support_fixture, seed_by_id)
		var x4_support_pool_repeat: Dictionary = _r6_regenerate_support_rows(x4_realizer, seed_triangles, x4_patch, volume.get("values", PackedFloat32Array()), roi, support_fixture, seed_by_id)
		var x4_support_pool_sha: String = _stable_evidence_sha(x4_support_pool.get("rows", []))
		var x4_support_pool_repeat_sha: String = _stable_evidence_sha(x4_support_pool_repeat.get("rows", []))
		if not bool(x4_support_pool.get("valid", false)) or not bool(x4_support_pool_repeat.get("valid", false)) or int(x4_support_pool.get("candidate_attempt_count", -1)) != 8192 or int(x4_support_pool_repeat.get("candidate_attempt_count", -1)) != 8192 or x4_support_pool_sha != x4_support_pool_repeat_sha or x4_support_pool.get("rows", []).is_empty():
			_fail("r6_x4_alternative_support_pool_rebuild_invalid", {"first_valid": x4_support_pool.get("valid", false), "repeat_valid": x4_support_pool_repeat.get("valid", false), "candidate_attempt_count": x4_support_pool.get("candidate_attempt_count", -1), "repeat_candidate_attempt_count": x4_support_pool_repeat.get("candidate_attempt_count", -1), "support_count": x4_support_pool.get("rows", []).size(), "first_sha256": x4_support_pool_sha, "repeat_sha256": x4_support_pool_repeat_sha})
			return
		var x4_search_fixture: Dictionary = search_residual_fixture.duplicate(true)
		x4_search_fixture["applied_flips"] = base.get("applied_flips", []).duplicate(true)
		var x4_preflight: Dictionary = x4_realizer.call("_r3_make_expanded_patch_context", x4_patch, x4_selected_ids, seed_triangles, x4_support_pool.get("rows", []), x4_boundary, triangles, x4_search_fixture, 2, true)
		if not bool(x4_preflight.get("valid", false)):
			_fail("r6_x4_support_context_preflight_failed", x4_preflight)
			return
		var x4_context_result: Dictionary = x4_realizer.call("_r3_make_expanded_patch_context", x4_patch, x4_selected_ids, seed_triangles, x4_support_pool.get("rows", []), x4_boundary, triangles, x4_search_fixture, 2, false)
		if not bool(x4_context_result.get("valid", false)) or x4_context_result.get("context", {}).is_empty():
			_fail("r6_x4_support_context_invalid", x4_context_result)
			return
		var x4_context: Dictionary = x4_context_result.get("context", {})
		for pair_value in x4_obligations.get("target_pairs", []):
			var pair: Array = pair_value
			var edge_key: String = String(x4_realizer.call("_edge_key", String(pair[0]), String(pair[1])))
			if not x4_context.get("boundary_edge_map", {}).has(edge_key):
				_fail("r6_x4_target_is_not_cavity_boundary", {"pair": pair, "edge_key": edge_key})
				return
		var x4_base_synthesis: Dictionary = Synthesizer.new().call("synthesize", x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []), [], false, Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS)
		var x4_base_synthesis_repeat: Dictionary = Synthesizer.new().call("synthesize", x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []), [], false, Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS)
		var x4_base_sha: String = _support_synthesis_fingerprint(x4_base_synthesis)
		var x4_base_repeat_sha: String = _support_synthesis_fingerprint(x4_base_synthesis_repeat)
		if not bool(x4_base_synthesis.get("valid", false)) or not bool(x4_base_synthesis_repeat.get("valid", false)) or x4_base_sha != String(x4_previous.get("continuation", {}).get("expected_support_set_sha256", "")) or x4_base_sha != x4_base_repeat_sha:
			_fail("r6_x4_x3_base_support_repeat_mismatch", {"valid": x4_base_synthesis.get("valid", false), "repeat_valid": x4_base_synthesis_repeat.get("valid", false), "support_sha256": x4_base_sha, "repeat_sha256": x4_base_repeat_sha, "expected_sha256": x4_previous.get("continuation", {}).get("expected_support_set_sha256", "")})
			return
		if y1_complete_support:
			var y_boundary_cycle: Dictionary = x4_realizer.call("_r4_boundary_cycle_set", x4_boundary)
			var y_cycle_rows: Array = y_boundary_cycle.get("cycles", [])
			if not bool(y_boundary_cycle.get("valid", false)) or y_cycle_rows.size() != 1:
				_fail("r6_y1_single_boundary_cycle_preflight_failed", y_boundary_cycle)
				return
			var y_boundary_ids: Array[String] = []
			for root_id_value in y_cycle_rows[0].get("root_ids", []): y_boundary_ids.append(String(root_id_value))
			var y_pairs: Array = []
			var y_pair_seen: Dictionary = {}
			for pair_value in x4_obligations.get("target_pairs", []):
				var pair: Array = [String(pair_value[0]), String(pair_value[1])]
				pair.sort()
				var key: String = "|".join(pair)
				if not y_pair_seen.has(key): y_pair_seen[key] = true; y_pairs.append(pair)
			for first_index in range(y_boundary_ids.size()):
				for second_index in range(first_index + 1, y_boundary_ids.size()):
					var pair: Array = [y_boundary_ids[first_index], y_boundary_ids[second_index]]
					pair.sort()
					var key: String = "|".join(pair)
					if not y_pair_seen.has(key): y_pair_seen[key] = true; y_pairs.append(pair)
			if y_pairs.size() != y_boundary_ids.size() * (y_boundary_ids.size() - 1) / 2:
				_fail("r6_y1_boundary_pair_domain_incomplete", {"boundary_ids": y_boundary_ids, "pair_count": y_pairs.size(), "zero_obligations": x4_obligations.get("target_pairs", [])})
				return
			if y1_graph_partial:
				var partial_input_path: String = OS.get_environment("R12CXR_R6_Y1_PARTIAL_INPUT")
				var partial_input_sha: String = OS.get_environment("R12CXR_R6_Y1_PARTIAL_SHA256")
				var partial_input_bytes: PackedByteArray = FileAccess.get_file_as_bytes(partial_input_path) if FileAccess.file_exists(partial_input_path) else PackedByteArray()
				if partial_input_sha.length() != 64 or Core.sha256(partial_input_bytes) != partial_input_sha:
					_fail("r6_y1_partial_support_input_hash_mismatch", {"path": partial_input_path, "observed_sha256": Core.sha256(partial_input_bytes), "expected_sha256": partial_input_sha})
					return
				var partial_input_value: Variant = JSON.parse_string(partial_input_bytes.get_string_from_utf8())
				if typeof(partial_input_value) != TYPE_DICTIONARY:
					_fail("r6_y1_partial_support_input_schema_invalid", {})
					return
				var partial_input: Dictionary = partial_input_value
				var partial_synthesis: Dictionary = partial_input.get("support_synthesis", {})
				var partial_stream: Dictionary = partial_synthesis.get("continuous_region_stream", {})
				var partial_stream_path: String = String(partial_stream.get("path", ""))
				var observed_partial_stream_sha: String = Core.sha256(FileAccess.get_file_as_bytes(partial_stream_path)) if FileAccess.file_exists(partial_stream_path) else ""
				if String(partial_input.get("attempt_id", "")) != x4_attempt_id or not bool(partial_input.get("target_attempt_consumed", false)) or not bool(partial_synthesis.get("valid", false)) or bool(partial_synthesis.get("finite_candidate_enumeration_complete", false)) or partial_synthesis.get("supports", []).is_empty() or String(partial_stream.get("sha256", "")) != observed_partial_stream_sha:
					_fail("r6_y1_partial_support_input_not_qualified", {"attempt_id": partial_input.get("attempt_id", ""), "target_attempt_consumed": partial_input.get("target_attempt_consumed", false), "synthesis_valid": partial_synthesis.get("valid", false), "support_domain_complete": partial_synthesis.get("finite_candidate_enumeration_complete", false), "support_count": partial_synthesis.get("supports", []).size(), "stream_sha256": partial_stream.get("sha256", ""), "observed_stream_sha256": observed_partial_stream_sha})
					return
				var partial_support_merge: Dictionary = _merge_y1_support_domain_supports(partial_synthesis, x4_previous_synthesis.get("supports", []), x4_realizer)
				if not bool(partial_support_merge.get("valid", false)):
					_fail("r6_y1_partial_support_union_invalid", partial_support_merge)
					return
				partial_synthesis = partial_support_merge.get("synthesis", {})
				var partial_synthesis_sha: String = _support_synthesis_fingerprint(partial_synthesis)
				var graph_output_path: String = output_path + ".finite-graph.json"
				var graph_continuation_metadata: Dictionary = {"domain_extension": "R6-Y1", "complete_support_domain": false, "full_candidate_graph_required": true, "support_domain_complete": false, "skip_support_repeat": true, "resume_completed_extension": true, "expected_support_count": partial_synthesis.get("supports", []).size(), "expected_support_set_sha256": partial_synthesis_sha, "generated_support_count": partial_support_merge.get("generated_support_count", -1), "carried_forward_support_count": partial_support_merge.get("carried_forward_support_count", -1), "source_partial_result_sha256": partial_input_sha, "source_partial_support_stream_sha256": observed_partial_stream_sha, "original_target_source_sha": String(x4_previous.get("source_sha", "")), "original_target_result_sha256": x4_previous_sha, "original_target_attempt_consumed": true, "additional_target_attempts_consumed": 0, "reason": "regenerate the complete finite graph and run the uncapped solver over the union of newly generated and previously accepted supports while preserving the incomplete support-domain classification", "zero_option_target_pairs": x4_obligations.get("target_pairs", []), "all_boundary_pairs": y_pairs}
				var partial_graph_result: Dictionary = _run_constraint_synthesis(x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, x4_patch, x4_selected_ids, seed_triangles, x4_boundary, triangles, x4_search_fixture, base, snapshot, support_fixture, residual_fixture.get("residuals", []), graph_output_path, x4_previous.get("cavity_search", {}), partial_synthesis, graph_continuation_metadata, x4_previous, realizer)
				if partial_graph_result.is_empty() or _terminal_failure_requested: return
				var partial_graph_sha: String = Core.sha256(FileAccess.get_file_as_bytes(graph_output_path)) if FileAccess.file_exists(graph_output_path) else ""
				var partial_d3_status: String = String(partial_graph_result.get("d3", {}).get("status", "UNKNOWN_NOT_CAPTURED"))
				var partial_graph_gate: Dictionary = partial_graph_result.get("graph_gate", {})
				var partial_d3: Dictionary = partial_graph_result.get("d3", {})
				var partial_d3_complete: bool = partial_d3_status == "SAT" and bool(partial_d3.get("valid", false)) or partial_d3_status == "UNSAT_COMPLETE" and bool(partial_d3.get("search_complete", partial_d3.get("complete", false))) and bool(partial_d3.get("search_exhaustive", false))
				var partial_graph_incomplete: bool = not bool(partial_graph_gate.get("complete", false)) or not partial_d3_complete
				var partial_graph_status: String = "R6_ARCHITECTURE_QUALIFIED" if String(partial_graph_result.get("status", "")) == "R6_ARCHITECTURE_QUALIFIED" else "R6_Y1_PARTIAL_SUPPORT_GRAPH_LIMIT" if partial_graph_incomplete else "R6_Y1_PARTIAL_SUPPORT_GRAPH_SAT" if partial_d3_status == "SAT" else "R6_Y1_PARTIAL_SUPPORT_GRAPH_UNSAT" if partial_d3_status == "UNSAT_COMPLETE" else "R6_Y1_PARTIAL_SUPPORT_GRAPH_LIMIT"
				var partial_graph_reason: String = "graph or solver computation is incomplete; preserved frontier is not infeasibility evidence" if partial_graph_incomplete else "graph and solver completed for the captured partial support set; support-domain resolution remains incomplete and must continue"
				var partial_graph_wrapper: Dictionary = {"schema": "P3.1.R12CXR.R6.Y1PartialGraph.v1", "campaign_id": "P3.1.R12CXR.R6Y.COMPLETE_SUPPORT_DOMAIN", "status": partial_graph_status, "terminal_reason": partial_graph_reason, "source_sha": x4_source_sha, "attempt_id": x4_attempt_id, "attempt_segment": 4, "target_attempt_consumed": true, "additional_target_attempts_consumed": 0, "prior_x3_result_sha256": x4_previous_sha, "prior_y1_partial_result_sha256": partial_input_sha, "prior_y1_support_stream_sha256": observed_partial_stream_sha, "selected_cavity_face_ids": x4_selected_ids, "zero_option_boundary_obligations": x4_obligations, "boundary_pair_domain": y_pairs, "partial_support_domain_complete": false, "partial_support_count": partial_synthesis.get("supports", []).size(), "partial_support_set_sha256": partial_synthesis_sha, "complete_graph_gate": partial_graph_result.get("graph_gate", {}), "d3": partial_graph_result.get("d3", {}), "downstream": partial_graph_result.get("downstream", {}), "nested_graph_result_path": graph_output_path, "nested_graph_result_sha256": partial_graph_sha, "attempt_accounting": {"previous_valid_attempts_consumed": 6, "r6_y1_attempts_consumed": 1, "cumulative_valid_scientific_target_attempts": 7, "attempt_id": x4_attempt_id}}
				_write_result(output_path, partial_graph_wrapper, "R12CXR_R6_Y1_PARTIAL_SUPPORT_GRAPH")
				quit(0)
				return
			var y_resume: Dictionary = {"valid": true, "region_states": {}, "supports": [], "metadata": {"resumed_region_count": 0, "resumed_support_count": 0, "source_result_sha256": "", "source_stream_sha256": ""}}
			var y_resume_input_path: String = OS.get_environment("R12CXR_R6_Y1_RESUME_INPUT")
			if not y_resume_input_path.is_empty():
				y_resume = _load_y1_resume_state(y_resume_input_path, OS.get_environment("R12CXR_R6_Y1_RESUME_SHA256"), OS.get_environment("R12CXR_R6_Y1_RESUME_STREAM_SHA256"), x4_attempt_id, y_pairs)
				if not bool(y_resume.get("valid", false)):
					_fail("r6_y1_resume_input_not_qualified", y_resume)
					return
			var y_stream_path: String = output_path + ".support-domain.jsonl"
			var y_synthesis: Dictionary = Synthesizer.new().call("synthesize", x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []), y_pairs, true, Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS, false, true, y_stream_path, y_resume.get("region_states", {}), y_resume.get("numeric_frontiers", {}))
			var y_prior_supports: Array = x4_previous_synthesis.get("supports", []).duplicate(true)
			for resume_support in y_resume.get("supports", []): y_prior_supports.append(resume_support)
			var y_support_merge: Dictionary = _merge_y1_support_domain_supports(y_synthesis, y_prior_supports, x4_realizer)
			if not bool(y_support_merge.get("valid", false)):
				_fail("r6_y1_support_union_invalid", y_support_merge)
				return
			y_synthesis = y_support_merge.get("synthesis", {})
			var y_synthesis_sha: String = _support_synthesis_fingerprint(y_synthesis)
			var y_support_domain_complete: bool = bool(y_synthesis.get("finite_candidate_enumeration_complete", false)) and bool(y_synthesis.get("continuous_region_resolution_complete", false)) and bool(y_synthesis.get("valid", false))
			if not y_support_domain_complete:
				var y_partial_reason: String = String(y_synthesis.get("cap_reason", ""))
				if y_partial_reason.is_empty(): y_partial_reason = "CONTINUOUS_REGIONS_WITHOUT_VALID_WITNESS_OR_ANALYTIC_CUTOFF_PROOF"
				var y_partial: Dictionary = {"schema": "P3.1.R12CXR.R6.Y1Result.v1", "campaign_id": "P3.1.R12CXR.R6Y.COMPLETE_SUPPORT_DOMAIN", "status": "R6_Y1_SUPPORT_DOMAIN_PARTIAL_LIMIT" if not String(y_synthesis.get("cap_reason", "")).is_empty() else "R6_Y1_CONTINUOUS_REGION_FEASIBILITY_UNKNOWN", "terminal_reason": y_partial_reason, "source_sha": x4_source_sha, "parent_sha": OS.get_environment("R12CXR_PARENT_SHA"), "attempt_id": x4_attempt_id, "target_attempt_consumed": true, "target_attempt_phase": "R6-Y1-COMPLETE-SUPPORT-DOMAIN", "prior_x3_result_sha256": x4_previous_sha, "prior_x3_attempt_id": x4_previous.get("attempt_id", ""), "selected_cavity_face_ids": x4_selected_ids, "selected_cavity_boundary_signature": x4_boundary.get("signature", ""), "zero_option_boundary_obligations": x4_obligations, "boundary_pair_domain": y_pairs, "resume_metadata": y_resume.get("metadata", {}), "support_synthesis": y_synthesis, "support_synthesis_fingerprint_sha256": y_synthesis_sha, "support_domain_complete": false, "continuous_region_resolution": "PARTIAL_LIMIT_OR_UNKNOWN; region-by-region analytic bounds and witness outcomes are retained; no sampling-based infeasibility claim", "attempt_accounting": {"previous_valid_attempts_consumed": 6, "r6_y1_attempts_consumed": 1, "cumulative_valid_scientific_target_attempts": 7, "attempt_id": x4_attempt_id}}
				_write_result(output_path, y_partial, "R12CXR_R6_Y1_SUPPORT_DOMAIN_PARTIAL_LIMIT")
				quit(0)
				return
			var y_repeat_stream_path: String = output_path + ".support-domain.repeat.jsonl"
			var y_synthesis_repeat: Dictionary = Synthesizer.new().call("synthesize", x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []), y_pairs, true, Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS, false, true, y_repeat_stream_path, y_resume.get("region_states", {}))
			var y_repeat_support_merge: Dictionary = _merge_y1_support_domain_supports(y_synthesis_repeat, y_prior_supports, x4_realizer)
			if not bool(y_repeat_support_merge.get("valid", false)):
				_fail("r6_y1_repeat_support_union_invalid", y_repeat_support_merge)
				return
			y_synthesis_repeat = y_repeat_support_merge.get("synthesis", {})
			var y_repeat_sha: String = _support_synthesis_fingerprint(y_synthesis_repeat)
			if not bool(y_synthesis_repeat.get("finite_candidate_enumeration_complete", false)) or not bool(y_synthesis_repeat.get("continuous_region_resolution_complete", false)) or y_synthesis_sha != y_repeat_sha:
				var y_repeat_partial: Dictionary = {"schema": "P3.1.R12CXR.R6.Y1Result.v1", "campaign_id": "P3.1.R12CXR.R6Y.COMPLETE_SUPPORT_DOMAIN", "status": "R6_Y1_SUPPORT_REPEAT_PARTIAL_LIMIT", "terminal_reason": "complete support synthesis repeat did not finish identically", "source_sha": x4_source_sha, "attempt_id": x4_attempt_id, "target_attempt_consumed": true, "selected_cavity_face_ids": x4_selected_ids, "zero_option_boundary_obligations": x4_obligations, "boundary_pair_domain": y_pairs, "first_support_synthesis": y_synthesis, "repeat_support_synthesis": y_synthesis_repeat, "first_fingerprint_sha256": y_synthesis_sha, "repeat_fingerprint_sha256": y_repeat_sha, "support_domain_complete": false, "attempt_accounting": {"previous_valid_attempts_consumed": 6, "r6_y1_attempts_consumed": 1, "cumulative_valid_scientific_target_attempts": 7, "attempt_id": x4_attempt_id}}
				_write_result(output_path, y_repeat_partial, "R12CXR_R6_Y1_SUPPORT_REPEAT_PARTIAL_LIMIT")
				quit(0)
				return
			var y_metadata: Dictionary = {"domain_extension": "R6-Y1", "complete_support_domain": true, "resume_completed_extension": true, "expected_support_count": y_synthesis.get("supports", []).size(), "expected_support_set_sha256": y_synthesis_sha, "completed_extension_summary": {"support_domain_complete": true, "deterministic_repeat_pass": true, "support_set_sha256": y_synthesis_sha}, "original_target_source_sha": String(x4_previous.get("source_sha", "")), "original_target_result_sha256": x4_previous_sha, "original_target_attempt_consumed": true, "additional_target_attempts_consumed": 1, "resume_metadata": y_resume.get("metadata", {}), "reason": "enumerate the complete deterministic critical candidate domain for every boundary root pair of the seven-face cavity; resolve each continuous region by a representable witness or complete finite/analytic proof while preserving every frozen gate", "zero_option_target_pairs": x4_obligations.get("target_pairs", []), "all_boundary_pairs": y_pairs, "support_domain_fingerprint_sha256": y_synthesis_sha}
			var y_result: Dictionary = _run_constraint_synthesis(x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, x4_patch, x4_selected_ids, seed_triangles, x4_boundary, triangles, x4_search_fixture, base, snapshot, support_fixture, residual_fixture.get("residuals", []), output_path, x4_previous.get("cavity_search", {}), y_synthesis, y_metadata, x4_previous, realizer, y_synthesis_repeat)
			if y_result.is_empty() or _terminal_failure_requested: return
			y_result["r6_y1_complete_support_domain"] = {"started": true, "prior_x3_result_sha256": x4_previous_sha, "selected_cavity_face_ids": x4_selected_ids, "selected_cavity_boundary_signature": x4_boundary.get("signature", ""), "zero_option_boundary_obligations": x4_obligations, "all_boundary_pairs": y_pairs, "resume_metadata": y_resume.get("metadata", {}), "first_support_synthesis_sha256": y_synthesis_sha, "repeat_support_synthesis_sha256": y_repeat_sha, "support_domain_complete": true, "deterministic_repeat_pass": true, "attempt_domain_changed": true, "attempt_target_consumed": true}
			y_result["attempt_accounting"] = {"previous_valid_attempts_consumed": 6, "r6_y1_attempts_consumed": 1, "cumulative_valid_scientific_target_attempts": 7, "attempt_id": x4_attempt_id}
			var y_result_bytes: PackedByteArray = _json_evidence_bytes(y_result)
			var y_result_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
			if y_result_file == null:
				_fail("r6_y1_result_final_write_failed", {"error": FileAccess.get_open_error()})
				return
			y_result_file.store_buffer(y_result_bytes)
			y_result_file.close()
			print("R12CXR_R6_Y1_COMPLETE_SUPPORT_DOMAIN " + JSON.stringify({"attempt_id": x4_attempt_id, "status": y_result.get("status", ""), "terminal_reason": y_result.get("terminal_reason", ""), "support_count": y_synthesis.get("supports", []).size(), "support_domain_complete": y_synthesis.get("finite_candidate_enumeration_complete", false), "result_sha256": Core.sha256(y_result_bytes), "target_attempt_consumed": true}))
			quit(0)
			return
		var x4_targeted: Dictionary = Synthesizer.new().call("synthesize", x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []), x4_obligations.get("target_pairs", []), true, Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS, directed_axis_bracket)
		var x4_targeted_repeat: Dictionary = Synthesizer.new().call("synthesize", x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []), x4_obligations.get("target_pairs", []), true, Synthesizer.MAX_R6X3_BOUNDARY_SOURCE_PAIRS, directed_axis_bracket)
		if x4_evidence_only:
			var targeted_evidence: Dictionary = {"schema": "P3.1.R12CXR.R6.X6RepresentabilityEvidence.v1" if x6_representability else "P3.1.R12CXR.R6.X4TargetedSupportEvidence.v1", "campaign_id": "P3.1.R12CXR.R6X.AUTONOMOUS_E2E", "status": "DIAGNOSTIC_COMPLETE" if bool(x4_targeted.get("valid", false)) and bool(x4_targeted_repeat.get("valid", false)) else "DIAGNOSTIC_FAILED", "target_attempt_consumed": false, "evidence_only": true, "evidence_run_id": x4_attempt_id, "scientific_attempt_id": "R6-X6-REPRESENTABILITY-20261102-01" if x6_representability else "R6-X4-20261102-01", "representation_strategy": "FULL_SAME_TETRA_AXIS_BRACKET" if x6_representability else "BOUNDED_PLUS_MINUS_2_ULP_CUBE", "source_sha": x4_source_sha, "parent_sha": OS.get_environment("R12CXR_PARENT_SHA"), "prior_x3_result_sha256": x4_previous_sha, "target_pairs": x4_obligations.get("target_pairs", []), "zero_boundary_edge_keys": x4_obligations.get("zero_edge_keys", []), "base_x3_support_set_sha256": x4_base_sha, "first_targeted_synthesis": x4_targeted, "repeat_targeted_synthesis": x4_targeted_repeat, "first_fingerprint_sha256": _support_synthesis_fingerprint(x4_targeted), "repeat_fingerprint_sha256": _support_synthesis_fingerprint(x4_targeted_repeat), "deterministic_repeat_pass": _support_synthesis_fingerprint(x4_targeted) == _support_synthesis_fingerprint(x4_targeted_repeat)}
			var evidence_written: bool = _write_result(output_path, targeted_evidence, "R12CXR_R6_X4_TARGETED_SUPPORT_EVIDENCE")
			quit(0 if evidence_written and String(targeted_evidence.get("status", "")) == "DIAGNOSTIC_COMPLETE" and bool(targeted_evidence.get("deterministic_repeat_pass", false)) else 3)
			return
		if not bool(x4_targeted.get("valid", false)) or not bool(x4_targeted_repeat.get("valid", false)):
			var incomplete_result: Dictionary = {"schema": "P3.1.R12CXR.R6.X4Result.v1", "campaign_id": "P3.1.R12CXR.R6X.AUTONOMOUS_E2E", "status": "R6_X4_SUPPORT_GENERATION_PARTIAL", "source_sha": x4_source_sha, "parent_sha": OS.get_environment("R12CXR_PARENT_SHA"), "attempt_id": x4_attempt_id, "target_attempt_consumed": true, "target_attempt_phase": "R6-X4-JOINT-SUPPORT", "prior_x3_result_sha256": x4_previous_sha, "zero_boundary_obligations": x4_obligations, "targeted_synthesis": x4_targeted, "repeat_synthesis": x4_targeted_repeat, "attempt_accounting": {"baseline_r6_06_attempts_consumed": 1, "r6_x1_attempts_consumed": 1, "r6_x2_attempts_consumed": 1, "r6_x3_attempts_consumed": 1, "r6_x4_attempts_consumed": 1, "cumulative_valid_scientific_target_attempts": 5, "unconsumed_tooling_failures_preserved": 5, "attempt_id": x4_attempt_id}}
			_write_result(output_path, incomplete_result, "R12CXR_R6_X4_SUPPORT_GENERATION_PARTIAL")
			quit(0)
			return
		var x4_targeted_sha: String = _support_synthesis_fingerprint(x4_targeted)
		var x4_targeted_repeat_sha: String = _support_synthesis_fingerprint(x4_targeted_repeat)
		var x4_base_supports: Array[Dictionary] = x4_base_synthesis.get("supports", [])
		var x4_targeted_supports: Array[Dictionary] = x4_targeted.get("supports", [])
		var x4_merged: Dictionary = _r6_x4_merge_support_rows(x4_base_supports, x4_targeted_supports, x4_obligations.get("target_pairs", []), Synthesizer.MAX_SUPPORTS)
		var x4_merged_repeat: Dictionary = _r6_x4_merge_support_rows(x4_base_supports, x4_targeted_repeat.get("supports", []), x4_obligations.get("target_pairs", []), Synthesizer.MAX_SUPPORTS)
		if not bool(x4_merged.get("valid", false)) or not bool(x4_merged_repeat.get("valid", false)):
			_fail("r6_x4_support_merge_invalid", {"first": x4_merged, "repeat": x4_merged_repeat})
			return
		var x4_support_repeat_pass: bool = x4_targeted_sha == x4_targeted_repeat_sha and _support_synthesis_fingerprint({"valid": true, "supports": x4_merged.supports, "retained_support_count": x4_merged.support_count, "raw_unique_support_count": x4_merged.support_count, "support_cap_hit": x4_merged.candidate_cap_or_selection_loss, "finite_candidate_enumeration_complete": false}) == _support_synthesis_fingerprint({"valid": true, "supports": x4_merged_repeat.supports, "retained_support_count": x4_merged_repeat.support_count, "raw_unique_support_count": x4_merged_repeat.support_count, "support_cap_hit": x4_merged_repeat.candidate_cap_or_selection_loss, "finite_candidate_enumeration_complete": false})
		var x4_synthesis: Dictionary = x4_base_synthesis.duplicate(true)
		x4_synthesis["supports"] = x4_merged.get("supports", [])
		x4_synthesis["retained_support_count"] = int(x4_merged.get("support_count", 0))
		x4_synthesis["raw_unique_support_count"] = int(x4_base_synthesis.get("raw_unique_support_count", 0)) + int(x4_merged.get("generated_unique_new_support_count", 0))
		x4_synthesis["support_cap_hit"] = bool(x4_base_synthesis.get("support_cap_hit", false)) or bool(x4_targeted.get("support_cap_hit", false)) or bool(x4_merged.get("candidate_cap_or_selection_loss", false))
		x4_synthesis["finite_candidate_enumeration_complete"] = bool(x4_base_synthesis.get("finite_candidate_enumeration_complete", false)) and bool(x4_targeted.get("finite_candidate_enumeration_complete", false)) and not bool(x4_merged.get("candidate_cap_or_selection_loss", false))
		x4_synthesis["x4_joint_support_completion"] = {"target_pairs": x4_obligations.get("target_pairs", []), "zero_boundary_edge_keys": x4_obligations.get("zero_edge_keys", []), "targeted_domain_complete": bool(x4_targeted.get("finite_candidate_enumeration_complete", false)), "targeted_deterministic_repeat": x4_targeted_sha == x4_targeted_repeat_sha, "targeted_synthesis_sha256": x4_targeted_sha, "merged_support_count": x4_merged.get("support_count", 0), "generated_new_support_count": x4_merged.get("generated_unique_new_support_count", 0), "selected_new_support_count": x4_merged.get("selected_new_support_count", 0), "candidate_cap_or_selection_loss": x4_merged.get("candidate_cap_or_selection_loss", false), "base_x3_domain_was_incomplete": not bool(x4_base_synthesis.get("finite_candidate_enumeration_complete", false)), "support_domain_complete": bool(x4_synthesis.get("finite_candidate_enumeration_complete", false))}
		var x4_support_sha: String = _support_synthesis_fingerprint(x4_synthesis)
		var x4_repeat_synthesis: Dictionary = x4_base_synthesis_repeat.duplicate(true)
		x4_repeat_synthesis["supports"] = x4_merged_repeat.get("supports", [])
		x4_repeat_synthesis["retained_support_count"] = int(x4_merged_repeat.get("support_count", 0))
		x4_repeat_synthesis["raw_unique_support_count"] = int(x4_base_synthesis_repeat.get("raw_unique_support_count", 0)) + int(x4_merged_repeat.get("generated_unique_new_support_count", 0))
		x4_repeat_synthesis["support_cap_hit"] = bool(x4_base_synthesis_repeat.get("support_cap_hit", false)) or bool(x4_targeted_repeat.get("support_cap_hit", false)) or bool(x4_merged_repeat.get("candidate_cap_or_selection_loss", false))
		x4_repeat_synthesis["finite_candidate_enumeration_complete"] = bool(x4_base_synthesis_repeat.get("finite_candidate_enumeration_complete", false)) and bool(x4_targeted_repeat.get("finite_candidate_enumeration_complete", false)) and not bool(x4_merged_repeat.get("candidate_cap_or_selection_loss", false))
		var x4_metadata: Dictionary = {"domain_extension": "R6-X6" if x6_representability else "R6-X4", "resume_completed_extension": true, "expected_support_count": x4_merged.get("support_count", 0), "expected_support_set_sha256": x4_support_sha, "completed_extension_summary": {"support_domain_complete": x4_synthesis.get("finite_candidate_enumeration_complete", false), "deterministic_repeat_pass": x4_support_repeat_pass, "support_set_sha256": x4_support_sha}, "original_target_source_sha": String(x4_previous.get("source_sha", "")), "original_target_result_sha256": x4_previous_sha, "original_target_attempt_consumed": true, "additional_target_attempts_consumed": 1, "reason": "R6-X6 applies a deterministic same-tetra axis interval bracket to the 72 X4 field-residual failures, searching every representable binary32 coordinate between the original point and that tetrahedron's bounds along each axis while preserving the field and barycentric epsilons; topology, Candidate-D, roots, arcs, cutoff, ROI, and cavity stay fixed", "target_pairs": x4_obligations.get("target_pairs", []), "zero_boundary_edge_keys": x4_obligations.get("zero_edge_keys", []), "targeted_generation_sha256": x4_targeted_sha, "targeted_generation_repeat_sha256": x4_targeted_repeat_sha, "targeted_generation_complete": x4_targeted.get("finite_candidate_enumeration_complete", false), "representation_strategy": "FULL_SAME_TETRA_AXIS_BRACKET" if x6_representability else "BOUNDED_PLUS_MINUS_2_ULP_CUBE", "candidate_cap_or_selection_loss": x4_merged.get("candidate_cap_or_selection_loss", false)}
		var x4_result: Dictionary = _run_constraint_synthesis(x4_realizer, volume.get("values", PackedFloat32Array()), roi, x4_context, x4_patch, x4_selected_ids, seed_triangles, x4_boundary, triangles, x4_search_fixture, base, snapshot, support_fixture, residual_fixture.get("residuals", []), output_path, x4_previous.get("cavity_search", {}), x4_synthesis, x4_metadata, x4_previous, realizer, x4_repeat_synthesis)
		if x4_result.is_empty() or _terminal_failure_requested:
			return
		x4_result["r6_x6_representability_completion" if x6_representability else "r6_x4_joint_support_completion"] = {"started": true, "prior_attempt_id": x4_previous.get("attempt_id", ""), "prior_result_sha256": x4_previous_sha, "baseline_x3_support_sha256": x4_base_sha, "alternative_support_pool_candidate_count": x4_support_pool.get("candidate_attempt_count", -1), "alternative_support_pool_rows": x4_support_pool.get("rows", []).size(), "alternative_support_pool_repeat_sha256": x4_support_pool_repeat_sha, "baseline_fixture_exact_match_applicable": false, "zero_boundary_obligations": x4_obligations, "targeted_support_generation_sha256": x4_targeted_sha, "targeted_support_generation_repeat_sha256": x4_targeted_repeat_sha, "targeted_candidate_domain_complete": x4_targeted.get("finite_candidate_enumeration_complete", false), "targeted_support_candidate_count": x4_targeted_supports.size(), "selected_new_supports": x4_merged.get("selected_new_supports", []), "merged_support_count": x4_merged.get("support_count", 0), "support_domain_complete": x4_synthesis.get("finite_candidate_enumeration_complete", false), "deterministic_repeat_pass": x4_support_repeat_pass, "representation_strategy": "FULL_SAME_TETRA_AXIS_BRACKET" if x6_representability else "BOUNDED_PLUS_MINUS_2_ULP_CUBE", "attempt_domain_changed": true, "attempt_target_consumed": true, "additional_target_attempts_consumed": 1}
		x4_result["attempt_accounting"] = {"baseline_r6_06_attempts_consumed": 1, "r6_x1_attempts_consumed": 1, "r6_x2_attempts_consumed": 1, "r6_x3_attempts_consumed": 1, "r6_x4_attempts_consumed": 1, "r6_x6_attempts_consumed": 1 if x6_representability else 0, "cumulative_valid_scientific_target_attempts": 6 if x6_representability else 5, "unconsumed_tooling_failures_preserved": 5, "attempt_id": x4_attempt_id}
		var x4_result_bytes: PackedByteArray = _json_evidence_bytes(x4_result)
		var x4_result_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if x4_result_file == null:
			_fail("r6_x4_result_final_write_failed", {"error": FileAccess.get_open_error()})
			return
		x4_result_file.store_buffer(x4_result_bytes)
		x4_result_file.close()
		print("R12CXR_R6_X4_JOINT_SUPPORT " + JSON.stringify({"attempt_id": x4_attempt_id, "status": x4_result.get("status", ""), "terminal_reason": x4_result.get("terminal_reason", ""), "result_sha256": Core.sha256(x4_result_bytes), "target_attempt_consumed": true, "support_domain_complete": x4_synthesis.get("finite_candidate_enumeration_complete", false)}))
		quit(0)
		return
	if mode == "resume-r6-06":
		var continuation_source_sha: String = OS.get_environment("R12CXR_SOURCE_SHA")
		var attempt_id: String = OS.get_environment("R12CXR_R6_ATTEMPT_ID")
		var previous_path: String = OS.get_environment("R12CXR_R6_RESUME_INPUT")
		var previous_sha: String = OS.get_environment("R12CXR_R6_RESUME_SHA256")
		var x1_extension: bool = OS.get_environment("R12CXR_R6_EXTENSION") == "R6-X1"
		var x2_extension: bool = OS.get_environment("R12CXR_R6_EXTENSION") == "R6-X2"
		var domain_extension: bool = x1_extension or x2_extension
		var expected_attempt_id: String = attempt_id if x2_extension and attempt_id in ["R6-X2-20261102-01", "R6-X2-20261102-02"] else "R6-X1-20261102-01" if x1_extension else "R6-06-20261101-aa16d87"
		if continuation_source_sha.length() != 40 or attempt_id != expected_attempt_id or previous_path.is_empty() or not FileAccess.file_exists(previous_path):
			_fail("r6_continuation_identity_invalid", {"source_sha": continuation_source_sha, "attempt_id": attempt_id, "expected_attempt_id": expected_attempt_id, "previous_path": previous_path, "x1_extension": x1_extension, "x2_extension": x2_extension})
			return
		var previous_bytes: PackedByteArray = FileAccess.get_file_as_bytes(previous_path)
		if Core.sha256(previous_bytes) != previous_sha:
			_fail("r6_continuation_previous_result_hash_mismatch", {"observed": Core.sha256(previous_bytes), "expected": previous_sha})
			return
		var previous_value: Variant = JSON.parse_string(previous_bytes.get_string_from_utf8())
		if typeof(previous_value) != TYPE_DICTIONARY:
			_fail("r6_continuation_previous_result_schema_invalid", {})
			return
		var previous: Dictionary = previous_value
		var previous_graph: Dictionary = previous.get("graph_gate", {})
		if x1_extension:
			var previous_d3: Dictionary = previous.get("d3", {})
			var previous_identity: Dictionary = previous.get("frozen_graph_identity_check", {})
			if previous_sha != "d3ba58abd7c1ae13edd035084c03e0203e127811bb849570e1b9f1ee064cfa90" or String(previous.get("attempt_id", "")) != "R6-06-20261101-aa16d87" or not bool(previous.get("target_attempt_consumed", false)) or String(previous.get("source_sha", "")) != "4cd0f3ce8699ebf7464e0dcf8f30e8372c823d4b" or String(previous_d3.get("status", "")) != "UNSAT_COMPLETE" or not bool(previous_d3.get("search_complete", false)) or not bool(previous_d3.get("search_exhaustive", false)) or int(previous_graph.get("legal_triangle_count", -1)) != FrozenCandidateTriangleCount or String(previous_d3.get("candidate_graph_sha256", "")) != FrozenCandidateGraphSha or String(previous_d3.get("support_set_sha256", "")) != FrozenSupportSetSha or String(previous_identity.get("observed_candidate_graph_audit_sha256", "")) != FrozenCandidateGraphAuditSha:
				_fail("r6_x1_previous_f1_result_identity_invalid", {"attempt_id": previous.get("attempt_id", ""), "source_sha": previous.get("source_sha", ""), "status": previous.get("status", ""), "d3": {"status": previous_d3.get("status", ""), "search_complete": previous_d3.get("search_complete", false), "search_exhaustive": previous_d3.get("search_exhaustive", false), "candidate_graph_sha256": previous_d3.get("candidate_graph_sha256", ""), "support_set_sha256": previous_d3.get("support_set_sha256", "")}, "graph_gate": previous_graph, "frozen_graph_identity_check": previous_identity, "input_sha256": previous_sha})
				return
		elif x2_extension:
			var previous_x1: Dictionary = previous.get("r6_x1_support_completion", {})
			var previous_x1_graph: Dictionary = previous_x1.get("extended_graph", {})
			var previous_x1_d3: Dictionary = previous.get("d3", {})
			if previous_sha != "c51a27c11a0023792966eb6178b90380d4021818b679538ff08a9c9cc591c4e7" or String(previous.get("attempt_id", "")) != "R6-X1-20261102-01" or String(previous.get("source_sha", "")) != "bfcbd2a75d23735e929908db8e31011589cad81d" or String(previous.get("status", "")) != "R6_X1_FROZEN_GRAPH_UNSAT_COMPLETE" or not bool(previous.get("target_attempt_consumed", false)) or not bool(previous_x1_graph.get("complete", false)) or not bool(previous_x1_d3.get("search_exhaustive", false)) or String(previous_x1_d3.get("status", "")) != "UNSAT_COMPLETE" or int(previous_x1_d3.get("support_count", -1)) != 26:
				_fail("r6_x2_previous_x1_result_identity_invalid", {"attempt_id": previous.get("attempt_id", ""), "source_sha": previous.get("source_sha", ""), "status": previous.get("status", ""), "d3": {"status": previous_x1_d3.get("status", ""), "search_exhaustive": previous_x1_d3.get("search_exhaustive", false), "support_count": previous_x1_d3.get("support_count", -1)}, "extended_graph": previous_x1_graph, "input_sha256": previous_sha})
				return
		else:
			if String(previous.get("attempt_id", "")) != attempt_id or not bool(previous.get("target_attempt_consumed", false)) or String(previous.get("source_sha", "")) != "aa16d87d674e2af35a1b445203a82497ab049831" or String(previous.get("terminal_reason", "")) != "FINITE_GRAPH_GATE_PARTIAL" or int(previous_graph.get("possible_triplets", -1)) != 3654 or int(previous_graph.get("probe_cap", -1)) != 0 or int(previous_graph.get("support_count", -1)) != 23:
				_fail("r6_continuation_previous_result_not_expected_graph_cap_blocker", {"attempt_id": previous.get("attempt_id", ""), "source_sha": previous.get("source_sha", ""), "terminal_reason": previous.get("terminal_reason", ""), "graph_gate": previous_graph})
				return
		var cavity_search: Dictionary = previous.get("cavity_search", {})
		var selected_ids: Array = cavity_search.get("selected", {}).get("face_ids", [])
		var selected_boundary: Dictionary = cavity_search.get("selected", {}).get("audit", {}).get("boundary", {})
		if String(cavity_search.get("status", "")) != "FOUND" or not bool(cavity_search.get("deterministic_repeat", {}).get("pass", false)) or selected_ids.size() != 6:
			_fail("r6_continuation_d_cavity_identity_invalid", {"status": cavity_search.get("status", ""), "repeat": cavity_search.get("deterministic_repeat", {}), "selected_ids": selected_ids})
			return
		var continuation_realizer: RefCounted = R6Realizer.new()
		continuation_realizer.set("_root_positions", root_positions)
		continuation_realizer.set("_required_arc_keys", required_arc_keys)
		continuation_realizer.set("_locked_triplets", realizer.get("_locked_triplets"))
		continuation_realizer.set("_cxr_active_phase", "r6")
		continuation_realizer.set("_cxr_active_snapshot", snapshot)
		var pool_result: Dictionary = _r6_regenerate_support_rows(continuation_realizer, seed_triangles, analysis_patch, volume.get("values", PackedFloat32Array()), roi, support_fixture, seed_by_id)
		if not bool(pool_result.get("valid", false)):
			_fail("r6_continuation_support_pool_regeneration_failed", pool_result)
			return
		var selected_patch: Array[Dictionary] = continuation_realizer.call("_r3_patch_rows_for_ids", triangles, selected_ids)
		var search_fixture: Dictionary = search_residual_fixture.duplicate(true)
		search_fixture["applied_flips"] = base.get("applied_flips", []).duplicate(true)
		var selected_full: Dictionary = continuation_realizer.call("_r3_make_expanded_patch_context", selected_patch, selected_ids, seed_triangles, pool_result.get("rows", []), selected_boundary, triangles, search_fixture, 2, false)
		if not bool(selected_full.get("valid", false)):
			_fail("r6_continuation_selected_context_reconstruction_failed", selected_full)
			return
		var selected_context: Dictionary = selected_full.get("context", {})
		var continued_synthesis: Dictionary = Synthesizer.new().call("synthesize", continuation_realizer, volume.get("values", PackedFloat32Array()), roi, selected_context, residual_fixture.get("residuals", []), String(support_fixture.get("cavity_id", "")), residual_fixture.get("arc_map", []))
		var previous_synthesis: Dictionary = previous.get("synthesis", {})
		var previous_synthesis_sha: String = _support_synthesis_fingerprint(previous_synthesis)
		var continued_synthesis_sha: String = _support_synthesis_fingerprint(continued_synthesis)
		var expected_continued_synthesis_sha: String = String(previous.get("r6_x1_support_completion", {}).get("baseline_support_set_sha256", previous_synthesis_sha)) if x2_extension else previous_synthesis_sha
		if not bool(continued_synthesis.get("valid", false)) or expected_continued_synthesis_sha != continued_synthesis_sha:
			_fail("r6_continuation_support_set_changed", {"previous_fingerprint_sha256": previous_synthesis_sha, "continued_fingerprint_sha256": continued_synthesis_sha, "continued_valid": continued_synthesis.get("valid", false), "previous_support_summary": _support_summary_for_diagnostic(previous_synthesis), "continued_support_summary": _support_summary_for_diagnostic(continued_synthesis), "support_differences": _support_row_differences(previous_synthesis.get("supports", []), continued_synthesis.get("supports", []), 12)})
			return
		var continuation_metadata: Dictionary
		if domain_extension:
			var domain_name: String = "R6-X2" if x2_extension else "R6-X1"
			continuation_metadata = {"is_continuation": false, "domain_extension": "R6-X1", "attempt_id": attempt_id, "parent_f1_source_sha": previous.get("source_sha", ""), "parent_f1_result_sha256": Core.sha256(previous_bytes), "parent_f1_attempt_id": previous.get("attempt_id", ""), "parent_f1_attempt_consumed": true, "additional_target_attempts_consumed": 1, "reason": "add deterministic exact piecewise-linear zero-set witnesses only for boundary obligations with zero candidate options in the complete frozen graph", "baseline_support_set_sha256": continued_synthesis_sha}
			continuation_metadata["domain_extension"] = domain_name
			continuation_metadata["reason"] = "enumerate every active arrangement vertex and deterministic interior critical witness for each unsatisfied directed boundary obligation, with the frozen topology-arc and geometry gates unchanged" if x2_extension else "add deterministic exact piecewise-linear zero-set witnesses only for boundary obligations with zero candidate options in the complete frozen graph"
			continuation_metadata["parent_attempt_id"] = previous.get("attempt_id", "")
			continuation_metadata["parent_result_sha256"] = Core.sha256(previous_bytes)
			continuation_metadata["baseline_support_set_sha256"] = String(previous.get("r6_x1_support_completion", {}).get("baseline_support_set_sha256", previous.get("d3", {}).get("support_set_sha256", continued_synthesis_sha))) if x2_extension else String(previous.get("d3", {}).get("support_set_sha256", continued_synthesis_sha))
		else:
			continuation_metadata = {"is_continuation": true, "same_attempt_id": attempt_id, "original_target_source_sha": previous.get("source_sha", ""), "continuation_source_sha": continuation_source_sha, "original_target_result_sha256": Core.sha256(previous_bytes), "original_target_attempt_consumed": true, "additional_target_attempts_consumed": 0, "reason": "continuation from the already-consumed R6-06 target; preserve the exact support identities and cavity, complete the finite 1058-triangle graph audit, and capture the required bounded legacy F0 telemetry before corrected F1", "support_set_identical": true, "support_set_sha256": continued_synthesis_sha}
		var continuation_result: Dictionary = _run_constraint_synthesis(continuation_realizer, volume.get("values", PackedFloat32Array()), roi, selected_context, selected_patch, selected_ids, seed_triangles, selected_boundary, triangles, search_fixture, base, snapshot, support_fixture, residual_fixture.get("residuals", []), output_path, cavity_search, continued_synthesis, continuation_metadata, previous if domain_extension else {}, realizer if domain_extension else null)
		if continuation_result.is_empty() or _terminal_failure_requested: return
		quit(0)
		return
	if mode == "synthesize":
		var attempt_id: String = OS.get_environment("R12CXR_R6_ATTEMPT_ID")
		var source_sha: String = OS.get_environment("R12CXR_SOURCE_SHA")
		if attempt_id.is_empty() or source_sha.is_empty():
			_fail("r6_target_attempt_identity_missing", {"attempt_id": attempt_id, "source_sha": source_sha})
			return
		var diagnostics: RefCounted = Diagnostics.new()
		var r6_realizer: RefCounted = R6Realizer.new()
		r6_realizer.set("_root_positions", root_positions)
		r6_realizer.set("_required_arc_keys", required_arc_keys)
		r6_realizer.set("_locked_triplets", realizer.get("_locked_triplets"))
		r6_realizer.set("_cxr_active_phase", "r6")
		r6_realizer.set("_cxr_active_snapshot", snapshot)
		var r6_pool_result: Dictionary = _r6_regenerate_support_rows(r6_realizer, seed_triangles, analysis_patch, volume.get("values", PackedFloat32Array()), roi, support_fixture, seed_by_id)
		if not bool(r6_pool_result.get("valid", false)):
			_fail("r6_support_pool_regeneration_failed", r6_pool_result)
			return
		var r6_regenerated_rows: Array[Dictionary] = r6_pool_result.get("rows", [])
		print("R6_A_REGENERATED_SUPPORT_POOL " + JSON.stringify({"r5_fixture_exact_match": pool_match.get("valid", false), "r6_regenerated_count": r6_regenerated_rows.size(), "r5_fixture_count": stored_rows.size(), "candidate_attempt_count": r6_pool_result.get("candidate_attempt_count", 0), "difference_reason": pool_match.get("reason", ""), "source": "R6_A_CORRECTED_REGENERATION"}))
		# R6-D bounds the continuous zero surface from raw tetrahedral interpolation;
		# R6-E separately consumes only accepted, corrected binary32 support roots.
		var zero_inventory: Dictionary = diagnostics.call("collect_zero_facet_inventory", realizer, volume.get("values", PackedFloat32Array()), roi)
		if not bool(zero_inventory.get("valid", false)):
			_fail("r6_zero_facet_inventory_failed", zero_inventory)
			return
		var projection: Dictionary = {"origin": _vector3_array(Vector3(r4_context.get("projection_origin", Vector3.ZERO))), "axis_u": _vector3_array(Vector3(r4_context.get("projection_u", Vector3.ZERO))), "axis_v": _vector3_array(Vector3(r4_context.get("projection_v", Vector3.ZERO)))}
		var cavity_search: Dictionary = diagnostics.call("search_patch_cavities", r6_realizer, triangles, analysis_patch_ids, root_positions, projection, zero_inventory.get("facets", []), {"max_faces": 12, "max_states": 10000, "max_queue": 2000, "max_ms": 30000})
		var cavity_search_repeat: Dictionary = Diagnostics.new().call("search_patch_cavities", r6_realizer, triangles, analysis_patch_ids, root_positions, projection, zero_inventory.get("facets", []), {"max_faces": 12, "max_states": 10000, "max_queue": 2000, "max_ms": 30000})
		var first_cavity_fingerprint: String = _stable_evidence_sha({"status": cavity_search.get("status", ""), "selected_face_ids": cavity_search.get("selected", {}).get("face_ids", []), "selected_boundary_edges": cavity_search.get("selected", {}).get("audit", {}).get("edge_audits", [])})
		var repeat_cavity_fingerprint: String = _stable_evidence_sha({"status": cavity_search_repeat.get("status", ""), "selected_face_ids": cavity_search_repeat.get("selected", {}).get("face_ids", []), "selected_boundary_edges": cavity_search_repeat.get("selected", {}).get("audit", {}).get("edge_audits", [])})
		cavity_search["deterministic_repeat"] = {"started": true, "pass": first_cavity_fingerprint == repeat_cavity_fingerprint, "first_fingerprint_sha256": first_cavity_fingerprint, "repeat_fingerprint_sha256": repeat_cavity_fingerprint, "repeat_status": cavity_search_repeat.get("status", "UNKNOWN_NOT_CAPTURED"), "repeat_selected_face_ids": cavity_search_repeat.get("selected", {}).get("face_ids", [])}
		if String(cavity_search.get("status", "")) != "FOUND":
			var pregeometry: Dictionary = {"schema": "P3.1.R12CXR.R6.CavitySearch.v1", "status": cavity_search.get("status", "UNKNOWN_NOT_CAPTURED"), "terminal_reason": cavity_search.get("terminal_reason", cavity_search.get("reason", "UNKNOWN_NOT_CAPTURED")), "source_sha": source_sha, "attempt_id": attempt_id, "target_attempt_consumed": true, "target_attempt_phase": "R6-D", "initial_patch_ids": analysis_patch_ids, "limits": {"max_faces": 12, "max_states": 10000, "max_queue": 2000, "max_ms": 30000}, "search": cavity_search}
			_write_result(output_path, pregeometry, "R12CXR_R6_CAVITY_SEARCH_RESULT")
			quit(0)
			return
		var selected_ids: Array = cavity_search.get("selected", {}).get("face_ids", []).duplicate()
		var selected_patch: Array[Dictionary] = r6_realizer.call("_r3_patch_rows_for_ids", triangles, selected_ids)
		var selected_boundary: Dictionary = cavity_search.get("selected", {}).get("audit", {}).get("boundary", {})
		var search_fixture: Dictionary = search_residual_fixture.duplicate(true)
		search_fixture["applied_flips"] = base.get("applied_flips", []).duplicate(true)
		var selected_preflight: Dictionary = r6_realizer.call("_r3_make_expanded_patch_context", selected_patch, selected_ids, seed_triangles, r6_regenerated_rows, selected_boundary, triangles, search_fixture, 2, true)
		if not bool(selected_preflight.get("valid", false)):
			_fail("r6_selected_cavity_context_preflight_failed", {"search": cavity_search, "preflight": selected_preflight})
			return
		var selected_full: Dictionary = r6_realizer.call("_r3_make_expanded_patch_context", selected_patch, selected_ids, seed_triangles, r6_regenerated_rows, selected_boundary, triangles, search_fixture, 2, false)
		if not bool(selected_full.get("valid", false)):
			_fail("r6_selected_cavity_full_context_failed", {"search": cavity_search, "context": selected_full})
			return
		var selected_context: Dictionary = selected_full.get("context", {})
		var synthesis_result: Dictionary = _run_constraint_synthesis(r6_realizer, volume.get("values", PackedFloat32Array()), roi, selected_context, selected_patch, selected_ids, seed_triangles, selected_boundary, triangles, search_fixture, base, snapshot, support_fixture, residual_fixture.get("residuals", []), output_path, cavity_search)
		if synthesis_result.is_empty() or _terminal_failure_requested: return
		quit(0)
		return
	var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		_fail("r6_frozen_cavity_output_open_failed", {"error": FileAccess.get_open_error()})
		return
	output_file.store_buffer(fixture_bytes)
	output_file.flush()
	var output_error: Error = output_file.get_error()
	output_file.close()
	if output_error != OK:
		_fail("r6_frozen_cavity_output_write_failed", {"error": output_error})
		return
	print("R12CXR_R6_CAVITY_FROZEN " + JSON.stringify({"source_sha": OS.get_environment("R12CXR_SOURCE_SHA"), "r4_source_sha": R4SourceSha, "cavity_sha256": Core.sha256(fixture_bytes), "boundary_signature": R4CavitySignature, "patch_faces": analysis_patch_ids.size(), "boundary_edges": analysis_boundary.get("boundary_edge_count", -1), "local_required_arcs": r4_context.get("local_required_arc_count", -1), "output_path": output_path}))
	quit(0)
	return

func _run_constraint_synthesis(realizer: RefCounted, values: PackedFloat32Array, roi: Dictionary, base_context: Dictionary, patch: Array[Dictionary], patch_ids: Array, seed_triangles: Array[Dictionary], boundary: Dictionary, original_triangles: Array[Dictionary], residual_fixture: Dictionary, base: Dictionary, snapshot: Dictionary, support_fixture: Dictionary, residual_triangles: Array, output_path: String, cavity_search: Dictionary, synthesis_override: Dictionary = {}, continuation_metadata: Dictionary = {}, previous_result: Dictionary = {}, inventory_realizer: RefCounted = null, synthesis_repeat_override: Dictionary = {}) -> Dictionary:
	var complete_y_domain: bool = bool(continuation_metadata.get("full_candidate_graph_required", continuation_metadata.get("complete_support_domain", false))) and String(continuation_metadata.get("domain_extension", "")) == "R6-Y1"
	var cavity_id: String = String(support_fixture.get("cavity_id", ""))
	if cavity_id.is_empty():
		_fail("r6_cavity_identity_missing", {})
		return {}
	var boundary_cycle: Array[String] = []
	for root_id_value in base_context.get("boundary_cycle", []): boundary_cycle.append(String(root_id_value))
	var boundary_edges: Array = []
	for edge_key_value in base_context.get("boundary_edge_map", {}).keys():
		var edge_key: String = String(edge_key_value)
		boundary_edges.append(base_context.boundary_edge_map[edge_key].duplicate(true))
	boundary_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("edge_key", "")) < String(b.get("edge_key", "")))
	var eligible_pairs: Array = []
	var sorted_boundary_ids: Array[String] = boundary_cycle.duplicate()
	sorted_boundary_ids.sort()
	for first_index in range(sorted_boundary_ids.size()):
		for second_index in range(first_index + 1, sorted_boundary_ids.size()):
			var pair: Array[String] = [sorted_boundary_ids[first_index], sorted_boundary_ids[second_index]]
			eligible_pairs.append({"root_ids": pair, "edge_key": String(realizer.call("_edge_key", pair[0], pair[1])), "is_boundary_edge": base_context.get("boundary_edge_map", {}).has(String(realizer.call("_edge_key", pair[0], pair[1])))})
	var required_roots: Array = base_context.get("required_topology_root_ids", {}).keys()
	required_roots.sort()
	var r6a_analysis: Dictionary = {
		"cavity_id": cavity_id,
		"frozen_boundary_cycle": boundary_cycle,
		"frozen_directed_boundary_edges": boundary_edges,
		"required_topology_root_ids": required_roots,
		"required_topology_arcs": residual_fixture.get("arc_map", []).duplicate(true),
		"projection_origin": base_context.get("projection_origin", Vector3.ZERO),
		"projection_u": base_context.get("projection_u", Vector3.ZERO),
		"projection_v": base_context.get("projection_v", Vector3.ZERO),
		"projected_cavity_polygon": base_context.get("polygon", []).duplicate(),
		"eligible_boundary_root_pairs": eligible_pairs,
		"eligible_boundary_root_pair_count": eligible_pairs.size(),
		"r4_d1_reference": {"retained_supports": 115, "legal_candidate_edges": 18, "supports_with_one_or_more_legal_edges": 5, "supports_with_two_or_more_legal_edges": 5, "legal_candidate_triangles": 0, "d3_candidate_rows": 329, "d3_branches": 5, "d3_complete": true, "d3_solution_count": 0},
		"support_need": "R6-D freezes the bounded boundary-realizable cavity before R6-E support synthesis. R6-E partitions each clipped field-zero facet by bounded root-pair, cavity and localized required-arc constraints, then validates deterministic critical points through the unchanged triangle gates. Finite witnesses do not prove continuum infeasibility."
	}
	var synthesizer: RefCounted = Synthesizer.new()
	var synthesis: Dictionary = synthesis_override if not synthesis_override.is_empty() else synthesizer.call("synthesize", realizer, values, roi, base_context, residual_triangles, cavity_id, residual_fixture.get("arc_map", []))
	if not bool(synthesis.get("valid", false)):
		_fail("r6_constraint_synthesis_input_invalid", synthesis)
		return {}
	var skip_support_repeat: bool = bool(continuation_metadata.get("skip_support_repeat", false))
	var synthesis_repeat: Dictionary = synthesis_repeat_override if not synthesis_repeat_override.is_empty() else {} if skip_support_repeat else Synthesizer.new().call("synthesize", realizer, values, roi, base_context, residual_triangles, cavity_id, residual_fixture.get("arc_map", []))
	var synthesis_fingerprint: String = _support_synthesis_fingerprint(synthesis)
	var synthesis_repeat_fingerprint: String = "NOT_RUN_PARTIAL_SUPPORT_GRAPH_RESUME" if skip_support_repeat else _support_synthesis_fingerprint(synthesis_repeat)
	var support_rows: Array[Dictionary] = synthesis.get("supports", [])
	var result: Dictionary = {
		"schema": "P3.1.R12CXR.R6.Result.v1",
		"campaign_id": "P3.1.R12CXR.R6X.AUTONOMOUS_E2E",
		"status": "R6_SUPPORT_SYNTHESIS_PARTIAL",
		"source_sha": OS.get_environment("R12CXR_SOURCE_SHA"),
		"parent_sha": OS.get_environment("R12CXR_PARENT_SHA") if not OS.get_environment("R12CXR_PARENT_SHA").is_empty() else "UNKNOWN_NOT_CAPTURED",
		"attempt_id": OS.get_environment("R12CXR_R6_ATTEMPT_ID"),
		"target_attempt_consumed": true,
		"continuation": continuation_metadata,
		"cavity_search": cavity_search,
		"r6_e_deterministic_repeat": {"started": not skip_support_repeat, "pass": synthesis_fingerprint == synthesis_repeat_fingerprint if not skip_support_repeat else false, "first_fingerprint_sha256": synthesis_fingerprint, "repeat_fingerprint_sha256": synthesis_repeat_fingerprint, "repeat_valid": synthesis_repeat.get("valid", false), "reason": "same partial support stream is not re-enumerated during graph-only continuation" if skip_support_repeat else ""},
		"selected_patch_triangle_ids": patch_ids.duplicate(),
		"r4_source_sha": R4SourceSha,
		"r4_d1_result_sha256": R4D1ResultSha,
		"frozen_cavity_sha256": R5CavitySha,
		"candidate_d_sha256": CandidateSha,
		"manifest_sha256": ManifestSha,
		"frozen_hashes": {"cavity": R5CavitySha, "candidate_d": CandidateSha, "manifest": ManifestSha, "support_pool": SupportPoolSha, "topology": TopologySha, "topology_graph_roundtrip": GraphSha, "volume": VolumeSha, "payload": PayloadSha, "r4_d1_result": R4D1ResultSha},
		"scenario_id": TargetId,
		"cavity_id": cavity_id,
		"r6a_constraint_analysis": r6a_analysis,
		"d2_signature": R4CavitySignature,
		"cross_squared_cutoff": FROZEN_CROSS_SQUARED_CUTOFF,
		"synthesis": synthesis,
		"feasible_region_count": "UNKNOWN_NOT_CAPTURED_FINITE_WITNESS_MODEL_DOES_NOT_ENUMERATE_ALL_REGIONS",
		"empty_feasible_region_count": "UNKNOWN_NOT_CAPTURED_FINITE_WITNESS_MODEL_DOES_NOT_ENUMERATE_ALL_REGIONS",
		"graph_gate": {"started": false, "reason": "NOT_RUN_NO_SYNTHESIZED_SUPPORTS"},
		"d3": {"started": false, "reason": "NOT_RUN_NO_LEGAL_TRIANGLES"},
		"downstream": {
			"started": false,
			"reason": "NOT_RUN_NO_VALID_D3_SOLUTION",
			"controls": "NOT_RUN_PENDING_EQUAL_LOD_PASS",
			"roi_rays": "NOT_RUN_PENDING_EQUAL_LOD_PASS",
			"volume_reconfirmation": "NOT_RUN_PENDING_EQUAL_LOD_PASS",
			"mixed_lod": "NOT_RUN_PENDING_EQUAL_LOD_PASS",
			"deterministic_repeat": "NOT_RUN_PENDING_EQUAL_LOD_PASS",
			"full_e2e": "NOT_RUN_PENDING_EQUAL_LOD_PASS",
			"full_validation": "NOT_RUN_PENDING_EQUAL_LOD_PASS"
		},
		"continuum_domain_exhausted": false,
		"global_impossibility_claim": false,
		"baseline_comparison": {"status": "NOT_RUN_EQUAL_LOD_NOT_REACHED"},
		"validation": {"status": "NOT_RUN_EQUAL_LOD_NOT_REACHED"},
		"timing_classification": "UNSCORED_EXPERIMENTAL_CPU_TIME_ONLY"
	}
	if support_rows.is_empty():
		result["terminal_reason"] = "NO_SUPPORTS_WITHIN_FROZEN_FIELD_DOMAIN_AND_EXISTING_CAPS"
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var context_result: Dictionary = realizer.call("_r3_make_expanded_patch_context", patch, patch_ids, seed_triangles, support_rows, boundary, original_triangles, residual_fixture, 2, false)
	if not bool(context_result.get("valid", false)):
		result["terminal_reason"] = "SYNTHESIZED_SUPPORT_CONTEXT_REJECTED"
		result["context_rejection"] = context_result
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var context: Dictionary = context_result.get("context", {})
	if context.is_empty():
		_fail("r6_synthesized_context_missing", {})
		return {}
	result["graph_gate"] = {"started": true, "context_valid": true, "vertex_count": context.get("vertex_ids", []).size(), "support_count": support_rows.size()}
	var vertex_ids: Array = context.get("vertex_ids", []).duplicate()
	vertex_ids.sort()
	var maximum_triangles: int = int(realizer.call("_cxr_limits").get("max_candidate_triangles_per_cavity", 0))
	var possible_triangle_count: int = int(vertex_ids.size() * maxi(0, vertex_ids.size() - 1) * maxi(0, vertex_ids.size() - 2) / 6)
	var graph_candidate_cap: int = possible_triangle_count if complete_y_domain else maximum_triangles
	result["graph_gate"]["possible_triplets"] = possible_triangle_count
	result["graph_gate"]["legal_candidate_triangle_cap"] = graph_candidate_cap
	result["graph_gate"]["triplet_scan_domain"] = "COMPLETE_LEXICOGRAPHIC_VERTEX_TRIPLETS_WITH_EXECUTION_RESOURCE_FRONTIER" if complete_y_domain else "COMPLETE_LEXICOGRAPHIC_VERTEX_TRIPLETS_SUBJECT_TO_PREREGISTERED_CANDIDATE_CAP"
	if graph_candidate_cap <= 0:
		result["graph_gate"]["complete"] = false
		result["graph_gate"]["reason"] = "PREREGISTERED_R2_CANDIDATE_TRIANGLE_CAP_INVALID"
		result["terminal_reason"] = "FINITE_GRAPH_GATE_PARTIAL"
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var candidate_triangles: Array[Dictionary] = []
	var rejection_histogram: Dictionary = {}
	var graph_probe_rows: Array[String] = []
	var graph_limited: bool = false
	var graph_limit_reason: String = ""
	var graph_started_usec: int = Time.get_ticks_usec()
	var graph_budget_raw: String = OS.get_environment("R12CXR_R6_GRAPH_BUDGET_SECONDS")
	var graph_budget_seconds: int = (maxi(1, graph_budget_raw.to_int()) if not graph_budget_raw.is_empty() else 28800) if complete_y_domain else 0
	var graph_budget_usec: int = graph_budget_seconds * 1000000
	var graph_memory_setting: String = OS.get_environment("R12CXR_R6_MEMORY_BUDGET_BYTES")
	var graph_memory_budget: int = (2147483648 if graph_memory_setting.is_empty() else maxi(268435456, graph_memory_setting.to_int())) if complete_y_domain else 0
	if complete_y_domain: realizer.set("_cxr_full_finite_graph_mode", true)
	realizer.set("_cxr_candidate_triangles_total", 0)
	realizer.set("_cxr_candidate_triangles_cavity", 0)
	realizer.set("_cxr_search_nodes_total", 0)
	realizer.set("_cxr_search_nodes_cavity", 0)
	realizer.set("_cxr_search_started_usec", graph_started_usec)
	realizer.set("_cxr_cavity_started_usec", graph_started_usec)
	for first_index in range(vertex_ids.size()):
		for second_index in range(first_index + 1, vertex_ids.size()):
			for third_index in range(second_index + 1, vertex_ids.size()):
				if complete_y_domain and Time.get_ticks_usec() - graph_started_usec >= graph_budget_usec:
					graph_limited = true
					graph_limit_reason = "PARTIAL_LIMIT_COMPLETE_FINITE_GRAPH_TIME"
					break
				if complete_y_domain and Performance.get_monitor(Performance.MEMORY_STATIC) >= graph_memory_budget:
					graph_limited = true
					graph_limit_reason = "PARTIAL_LIMIT_COMPLETE_FINITE_GRAPH_MEMORY"
					break
				var ids: Array = [String(vertex_ids[first_index]), String(vertex_ids[second_index]), String(vertex_ids[third_index])]
				var triangle_result: Dictionary = realizer.call("_r2_get_candidate_triangle", ids, context)
				var row_key: String = "|".join(ids)
				if bool(triangle_result.get("limit", false)):
					graph_limited = true
					graph_limit_reason = String(triangle_result.get("reason", "R2_CANDIDATE_GATE_LIMIT"))
					graph_probe_rows.append("%s|LIMIT|%s" % [row_key, graph_limit_reason])
					break
				if bool(triangle_result.get("valid", false)):
					var triangle: Dictionary = triangle_result.get("triangle", {})
					candidate_triangles.append(triangle)
					graph_probe_rows.append("%s|PASS|%s" % [row_key, String(triangle.get("triangle_id", ""))])
				else:
					var reason: String = String(triangle_result.get("reason", "UNKNOWN_NOT_CAPTURED"))
					rejection_histogram[reason] = int(rejection_histogram.get(reason, 0)) + 1
					graph_probe_rows.append("%s|REJECT|%s" % [row_key, reason])
				if graph_probe_rows.size() >= possible_triangle_count:
					result["graph_gate"]["complete"] = true
					break
			if graph_limited or graph_probe_rows.size() >= possible_triangle_count: break
		if graph_limited or graph_probe_rows.size() >= possible_triangle_count: break
	var graph_complete: bool = graph_probe_rows.size() == possible_triangle_count and not graph_limited
	var graph_summary: Dictionary = synthesizer.call("_candidate_graph_summary", candidate_triangles, context.get("candidate_edges", {}), context.get("support_by_id", {}))
	result["graph_gate"] = {
		"started": true,
		"complete": graph_complete,
		"vertex_count": vertex_ids.size(),
		"support_count": support_rows.size(),
		"possible_triplets": possible_triangle_count,
		"probed_triplets": graph_probe_rows.size(),
		"triplet_scan_complete": graph_probe_rows.size() == possible_triangle_count and not graph_limited,
		"legal_triangle_count": candidate_triangles.size(),
		"rejection_histogram": rejection_histogram,
		"limit_reason": graph_limit_reason,
		"audit_sha256": Synthesizer.new().call("_candidate_graph_sha256", graph_probe_rows),
		"candidate_graph_summary": graph_summary,
		"supports_retained": support_rows.size(),
		"in_domain_supports": support_rows.size(),
		"legal_candidate_triangles": candidate_triangles.size(),
		"graph_gate_usec": Time.get_ticks_usec() - graph_started_usec,
		"preregistered_legal_candidate_triangle_cap": graph_candidate_cap
	}
	result["candidate_triangle_rows"] = candidate_triangles.duplicate(true)
	result["candidate_triangle_rows_sha256"] = _stable_evidence_sha(candidate_triangles)
	if candidate_triangles.is_empty():
		result["terminal_reason"] = "NO_LEGAL_TRIANGLES_IN_COMPLETE_FINITE_GRAPH" if graph_complete else "FINITE_GRAPH_GATE_PARTIAL"
		result["continuum_domain_exhausted"] = false
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var observed_support_set_sha: String = _support_synthesis_fingerprint(synthesis)
	var observed_candidate_graph_sha: String = String(graph_summary.get("candidate_graph_sha256", ""))
	var observed_graph_audit_sha: String = String(result.graph_gate.get("audit_sha256", ""))
	var y1_extension: bool = String(continuation_metadata.get("domain_extension", "")) == "R6-Y1"
	var x1_extension: bool = String(continuation_metadata.get("domain_extension", "")) == "R6-X1"
	var x2_extension: bool = String(continuation_metadata.get("domain_extension", "")) == "R6-X2"
	var x3_extension: bool = String(continuation_metadata.get("domain_extension", "")) == "R6-X3"
	var x4_extension: bool = String(continuation_metadata.get("domain_extension", "")) == "R6-X4"
	var x6_extension: bool = String(continuation_metadata.get("domain_extension", "")) == "R6-X6"
	var alternative_graph_extension: bool = x3_extension or x4_extension or x6_extension or y1_extension
	var support_extension: bool = x1_extension or x2_extension
	var resume_completed_extension: bool = bool(continuation_metadata.get("resume_completed_extension", false))
	var expected_support_count: int = int(continuation_metadata.get("expected_support_count", 23)) if resume_completed_extension else 23
	var expected_support_sha: String = String(continuation_metadata.get("expected_support_set_sha256", FrozenSupportSetSha)) if resume_completed_extension else FrozenSupportSetSha
	var expected_triangle_count: int = int(continuation_metadata.get("expected_candidate_triangle_count", FrozenCandidateTriangleCount)) if resume_completed_extension else FrozenCandidateTriangleCount
	var expected_graph_sha: String = String(continuation_metadata.get("expected_candidate_graph_sha256", FrozenCandidateGraphSha)) if resume_completed_extension else FrozenCandidateGraphSha
	var expected_graph_audit_sha: String = String(continuation_metadata.get("expected_candidate_graph_audit_sha256", FrozenCandidateGraphAuditSha)) if resume_completed_extension else FrozenCandidateGraphAuditSha
	var identity_scope: String = "R6_Y1_COMPLETE_SUPPORT_GRAPH" if y1_extension else "R6_X3_CAVITY_GRAPH" if x3_extension else "R6_X4_JOINT_SUPPORT_GRAPH" if x4_extension else "R6_X6_REPRESENTABILITY_GRAPH" if x6_extension else "RESUMED_COMPLETED_EXTENSION" if resume_completed_extension else "FROZEN_R6_GRAPH"
	var frozen_identity_check: Dictionary = {"expected_support_count": expected_support_count, "observed_support_count": support_rows.size(), "expected_support_set_sha256": expected_support_sha, "observed_support_set_sha256": observed_support_set_sha, "expected_candidate_triangle_count": expected_triangle_count if not alternative_graph_extension else "GENERATED_IN_COMPLETE_GRAPH_AUDIT", "observed_candidate_triangle_count": candidate_triangles.size(), "expected_candidate_graph_sha256": expected_graph_sha if not alternative_graph_extension else "GENERATED_IN_COMPLETE_GRAPH_AUDIT", "observed_candidate_graph_sha256": observed_candidate_graph_sha, "expected_candidate_graph_audit_sha256": expected_graph_audit_sha if not alternative_graph_extension else "GENERATED_IN_COMPLETE_GRAPH_AUDIT", "observed_candidate_graph_audit_sha256": observed_graph_audit_sha, "identity_scope": identity_scope}
	var frozen_identity_matches: bool = false
	if alternative_graph_extension:
		frozen_identity_matches = graph_complete and support_rows.size() == expected_support_count and observed_support_set_sha == expected_support_sha and observed_candidate_graph_sha.length() == 64 and observed_graph_audit_sha.length() == 64
	else:
		frozen_identity_matches = support_rows.size() == expected_support_count and observed_support_set_sha == expected_support_sha and candidate_triangles.size() == expected_triangle_count and observed_candidate_graph_sha == expected_graph_sha and observed_graph_audit_sha == expected_graph_audit_sha
	result["frozen_graph_identity_check"] = frozen_identity_check
	if not graph_complete or not frozen_identity_matches:
		result["status"] = ("R6_Y1_GRAPH_PARTIAL_LIMIT" if y1_extension else "R6_X3_GRAPH_PARTIAL" if x3_extension else "R6_X4_GRAPH_PARTIAL" if x4_extension else "R6_X6_GRAPH_PARTIAL" if x6_extension else "R6_FROZEN_GRAPH_PARTIAL") if not graph_complete else ("R6_Y1_GRAPH_IDENTITY_INVALID" if y1_extension else "R6_X3_GRAPH_IDENTITY_INVALID" if x3_extension else "R6_X4_GRAPH_IDENTITY_INVALID" if x4_extension else "R6_X6_GRAPH_IDENTITY_INVALID" if x6_extension else "R6_FROZEN_GRAPH_IDENTITY_MISMATCH")
		result["terminal_reason"] = "candidate graph scan incomplete before solver" if not graph_complete else "candidate graph or support identity did not match the selected extension scope"
		result["d3"] = {"started": false, "reason": "NOT_RUN_FROZEN_GRAPH_GATE_FAILED"}
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var baseline_candidate_triangle_rows: Array[Dictionary] = candidate_triangles.duplicate(true)
	var baseline_vertex_ids: Array = context.get("vertex_ids", []).duplicate()
	var baseline_graph_row_export_sha: String = _stable_evidence_sha(baseline_candidate_triangle_rows)
	var x1_support_completion: Dictionary = continuation_metadata.get("completed_extension_summary", {}).duplicate(true) if resume_completed_extension else {}
	if support_extension and not resume_completed_extension:
		var previous_d3: Dictionary = previous_result.get("d3", {})
		var zero_set_realizer: RefCounted = inventory_realizer if inventory_realizer != null else realizer
		var first_completion: Dictionary
		var repeated_completion: Dictionary
		if x2_extension:
			first_completion = _r6_x2_critical_support_completion(realizer, zero_set_realizer, values, roi, base_context, patch, support_rows, previous_result)
			repeated_completion = _r6_x2_critical_support_completion(realizer, zero_set_realizer, values, roi, base_context, patch, support_rows, previous_result)
		else:
			first_completion = _r6_x1_boundary_support_completion(realizer, zero_set_realizer, values, roi, base_context, patch, support_rows, previous_d3.get("boundary_edge_candidate_counts", {}))
			repeated_completion = _r6_x1_boundary_support_completion(realizer, zero_set_realizer, values, roi, base_context, patch, support_rows, previous_d3.get("boundary_edge_candidate_counts", {}))
		var first_support_fingerprint: String = _stable_evidence_sha(first_completion.get("supports", []))
		var repeat_support_fingerprint: String = _stable_evidence_sha(repeated_completion.get("supports", []))
		x1_support_completion = {"started": true, "domain_extension": "R6-X2" if x2_extension else "R6-X1", "hypothesis": "enumerate all arrangement vertices and deterministic interior critical witnesses on clipped exact zero facets for the unsatisfied directed boundary pairs; preserve arc, cutoff, field, ownership and topology gates", "changed_domain": "support_vertex_set_only; frozen six-face cavity, topology arcs and authority, Candidate-D field, volume, roots, cutoff, epsilons, ROI oracle and controls remain fixed", "baseline_attempt_id": previous_result.get("attempt_id", ""), "baseline_result_sha256": continuation_metadata.get("parent_result_sha256", continuation_metadata.get("parent_f1_result_sha256", "UNKNOWN_NOT_CAPTURED")), "baseline_solver_status": previous_d3.get("status", "UNKNOWN_NOT_CAPTURED"), "baseline_candidate_graph_sha256": previous_d3.get("candidate_graph_sha256", "UNKNOWN_NOT_CAPTURED"), "baseline_support_set_sha256": continuation_metadata.get("baseline_support_set_sha256", previous_d3.get("support_set_sha256", "UNKNOWN_NOT_CAPTURED")), "baseline_graph_rows_sha256": baseline_graph_row_export_sha, "baseline_vertex_ids": baseline_vertex_ids.duplicate(), "baseline_graph_rows": baseline_candidate_triangle_rows, "boundary_audit": first_completion.get("boundary_audit", {}), "zero_option_edges": first_completion.get("zero_option_edges", []), "supports": first_completion.get("supports", []), "support_count_before": support_rows.size(), "support_count_added": first_completion.get("supports", []).size(), "support_fingerprint_sha256": first_support_fingerprint, "repeat_fingerprint_sha256": repeat_support_fingerprint, "deterministic_repeat_pass": bool(first_completion.get("valid", false)) and bool(repeated_completion.get("valid", false)) and first_support_fingerprint == repeat_support_fingerprint, "first_completion_reason": first_completion.get("reason", ""), "first_completion_diagnostics": first_completion.get("x2_continuous_domain", first_completion.get("inventory", first_completion.get("boundary_audit", {}))), "support_domain_complete": bool(first_completion.get("support_domain_complete", x1_extension)), "additional_target_attempts_consumed": 1}
		var extension_result_key: String = "r6_x2_support_completion" if x2_extension else "r6_x1_support_completion"
		if not bool(first_completion.get("valid", false)) or not bool(repeated_completion.get("valid", false)) or first_support_fingerprint != repeat_support_fingerprint or (first_completion.get("supports", []).is_empty() and x1_extension):
			result[extension_result_key] = x1_support_completion
			result["status"] = "R6_X2_PREREQUISITE_OR_DETERMINISM_BLOCKED" if x2_extension else "R6_X1_PREREQUISITE_OR_DETERMINISM_BLOCKED"
			result["terminal_reason"] = String(first_completion.get("reason", "R6 support completion or deterministic repeat failed"))
			result["target_attempt_consumed"] = false
			result["continuation"]["additional_target_attempts_consumed"] = 0
			result["continuation"]["target_attempt_consumed"] = false
			_write_result(output_path, result, "R12CXR_R6_SUPPORT_COMPLETION")
			return result
		var all_support_ids: Dictionary = {}
		for support_value in support_rows: all_support_ids[String(support_value.get("support_id", ""))] = true
		for support_value in first_completion.get("supports", []):
			var support: Dictionary = support_value
			if all_support_ids.has(String(support.get("support_id", ""))):
				result[extension_result_key] = x1_support_completion
				result["status"] = "R6_X2_SUPPORT_IDENTITY_COLLISION" if x2_extension else "R6_X1_SUPPORT_IDENTITY_COLLISION"
				result["terminal_reason"] = "critical support duplicates an existing support identity; no new geometric domain was exercised"
				result["target_attempt_consumed"] = false
				result["continuation"]["additional_target_attempts_consumed"] = 0
				result["continuation"]["target_attempt_consumed"] = false
				_write_result(output_path, result, "R12CXR_R6_SUPPORT_COMPLETION")
				return result
			all_support_ids[String(support.get("support_id", ""))] = true
			support_rows.append(support.duplicate(true))
		support_rows.sort_custom(Callable(realizer, "_candidate_less"))
		synthesis["supports"] = support_rows.duplicate(true)
		synthesis["retained_support_count"] = support_rows.size()
		synthesis["raw_unique_support_count"] = int(synthesis.get("raw_unique_support_count", 0)) + first_completion.get("supports", []).size()
		result["synthesis"] = synthesis
		var extended_context_result: Dictionary = realizer.call("_r3_make_expanded_patch_context", patch, patch_ids, seed_triangles, support_rows, boundary, original_triangles, residual_fixture, 2, false)
		if not bool(extended_context_result.get("valid", false)):
			result[extension_result_key] = x1_support_completion
			result["status"] = "R6_X2_SUPPORT_CONTEXT_REJECTED" if x2_extension else "R6_X1_SUPPORT_CONTEXT_REJECTED"
			result["terminal_reason"] = String(extended_context_result.get("reason", "extended support context rejected"))
			result["context_rejection"] = extended_context_result
			result["target_attempt_consumed"] = false
			result["continuation"]["additional_target_attempts_consumed"] = 0
			result["continuation"]["target_attempt_consumed"] = false
			_write_result(output_path, result, "R12CXR_R6_SUPPORT_COMPLETION")
			return result
		context = extended_context_result.get("context", {})
		if context.is_empty():
			result[extension_result_key] = x1_support_completion
			result["status"] = "R6_X2_SUPPORT_CONTEXT_MISSING" if x2_extension else "R6_X1_SUPPORT_CONTEXT_MISSING"
			result["terminal_reason"] = "extended support context missing after successful preflight"
			result["target_attempt_consumed"] = false
			result["continuation"]["additional_target_attempts_consumed"] = 0
			result["continuation"]["target_attempt_consumed"] = false
			_write_result(output_path, result, "R12CXR_R6_SUPPORT_COMPLETION")
			return result
		var x1_vertex_ids: Array = context.get("vertex_ids", []).duplicate()
		x1_vertex_ids.sort()
		var x1_possible_triplets: int = int(x1_vertex_ids.size() * maxi(0, x1_vertex_ids.size() - 1) * maxi(0, x1_vertex_ids.size() - 2) / 6)
		var x1_graph_cap: int = int(realizer.call("_cxr_limits").get("max_candidate_triangles_per_cavity", 0))
		var x1_triangles: Array[Dictionary] = []
		var x1_rejections: Dictionary = {}
		var x1_probe_rows: Array[String] = []
		var x1_limited: bool = false
		var x1_limit_reason: String = ""
		var x1_started_usec: int = Time.get_ticks_usec()
		result["target_attempt_consumed"] = true
		result["continuation"]["target_attempt_consumed"] = true
		result["continuation"]["additional_target_attempts_consumed"] = 1
		result["attempt_accounting"] = {"baseline_r6_06_attempts_consumed": 1, "r6_x1_attempts_consumed": 1, "r6_x2_attempts_consumed": 1 if x2_extension else 0, "unconsumed_tooling_failures_preserved": 3, "cumulative_valid_scientific_target_attempts": 3 if x2_extension else 2, "attempt_id": continuation_metadata.get("attempt_id", "")}
		for first_index in range(x1_vertex_ids.size()):
			for second_index in range(first_index + 1, x1_vertex_ids.size()):
				for third_index in range(second_index + 1, x1_vertex_ids.size()):
					var ids: Array = [String(x1_vertex_ids[first_index]), String(x1_vertex_ids[second_index]), String(x1_vertex_ids[third_index])]
					var triangle_result: Dictionary = realizer.call("_r2_get_candidate_triangle", ids, context)
					var row_key: String = "|".join(ids)
					if bool(triangle_result.get("limit", false)):
						x1_limited = true
						x1_limit_reason = String(triangle_result.get("reason", "R2_CANDIDATE_GATE_LIMIT"))
						x1_probe_rows.append("%s|LIMIT|%s" % [row_key, x1_limit_reason])
						break
					if bool(triangle_result.get("valid", false)):
						var triangle: Dictionary = triangle_result.get("triangle", {})
						x1_triangles.append(triangle)
						x1_probe_rows.append("%s|PASS|%s" % [row_key, String(triangle.get("triangle_id", ""))])
					else:
						var reason: String = String(triangle_result.get("reason", "UNKNOWN_NOT_CAPTURED"))
						x1_rejections[reason] = int(x1_rejections.get(reason, 0)) + 1
						x1_probe_rows.append("%s|REJECT|%s" % [row_key, reason])
					if x1_probe_rows.size() >= x1_possible_triplets: break
				if x1_limited or x1_probe_rows.size() >= x1_possible_triplets: break
			if x1_limited or x1_probe_rows.size() >= x1_possible_triplets: break
		var x1_graph_complete: bool = x1_probe_rows.size() == x1_possible_triplets and not x1_limited
		var x1_summary: Dictionary = Synthesizer.new().call("_candidate_graph_summary", x1_triangles, context.get("candidate_edges", {}), context.get("support_by_id", {}))
		var baseline_vertex_set: Dictionary = {}
		for vertex_id in baseline_vertex_ids: baseline_vertex_set[String(vertex_id)] = true
		var base_rows_from_extended: Array[Dictionary] = []
		var added_triangle_rows: Array[Dictionary] = []
		for triangle in x1_triangles:
			var old_only: bool = true
			for root_value in triangle.get("root_ids", []):
				if not baseline_vertex_set.has(String(root_value)): old_only = false
			if old_only: base_rows_from_extended.append(triangle)
			else: added_triangle_rows.append(triangle)
		var baseline_rows_repeat_sha: String = _stable_evidence_sha(base_rows_from_extended)
		var baseline_rows_match: bool = base_rows_from_extended.size() == baseline_candidate_triangle_rows.size() and baseline_rows_repeat_sha == baseline_graph_row_export_sha
		x1_support_completion["extended_graph"] = {"complete": x1_graph_complete, "vertex_count": x1_vertex_ids.size(), "possible_triplets": x1_possible_triplets, "probed_triplets": x1_probe_rows.size(), "legal_triangle_count": x1_triangles.size(), "candidate_graph_sha256": x1_summary.get("candidate_graph_sha256", ""), "audit_sha256": Synthesizer.new().call("_candidate_graph_sha256", x1_probe_rows), "baseline_triangle_rows_recovered": base_rows_from_extended.size(), "baseline_triangle_rows_sha256": baseline_rows_repeat_sha, "baseline_triangle_rows_match_pre_extension": baseline_rows_match, "new_triangle_count": added_triangle_rows.size(), "new_triangle_rows_sha256": _stable_evidence_sha(added_triangle_rows), "rejection_histogram": x1_rejections.duplicate(true), "limit_reason": x1_limit_reason, "graph_gate_usec": Time.get_ticks_usec() - x1_started_usec}
		x1_support_completion["extended_candidate_triangle_rows"] = x1_triangles.duplicate(true)
		x1_support_completion["new_candidate_triangle_rows"] = added_triangle_rows.duplicate(true)
		result[extension_result_key] = x1_support_completion
		candidate_triangles = x1_triangles
		graph_complete = x1_graph_complete
		graph_summary = x1_summary
		result["graph_gate"] = {"started": true, "complete": x1_graph_complete, "vertex_count": x1_vertex_ids.size(), "support_count": support_rows.size(), "possible_triplets": x1_possible_triplets, "probed_triplets": x1_probe_rows.size(), "triplet_scan_complete": x1_graph_complete, "legal_triangle_count": x1_triangles.size(), "rejection_histogram": x1_rejections, "limit_reason": x1_limit_reason, "audit_sha256": x1_support_completion.extended_graph.audit_sha256, "candidate_graph_summary": x1_summary, "supports_retained": support_rows.size(), "in_domain_supports": support_rows.size(), "legal_candidate_triangles": x1_triangles.size(), "graph_gate_usec": x1_support_completion.extended_graph.graph_gate_usec, "preregistered_legal_candidate_triangle_cap": x1_graph_cap}
		if not graph_complete or not baseline_rows_match:
			result["status"] = ("R6_X2_EXTENDED_GRAPH_PARTIAL" if x2_extension else "R6_X1_EXTENDED_GRAPH_PARTIAL") if not graph_complete else ("R6_X2_BASELINE_GRAPH_ROWS_CHANGED" if x2_extension else "R6_X1_BASELINE_GRAPH_ROWS_CHANGED")
			result["terminal_reason"] = x1_limit_reason if not graph_complete else "baseline candidate triangle rows changed after adding new support vertices"
			_write_result(output_path, result, "R12CXR_R6_SUPPORT_COMPLETION")
			return result
		observed_support_set_sha = _support_synthesis_fingerprint(synthesis)
		observed_candidate_graph_sha = String(x1_summary.get("candidate_graph_sha256", ""))
		observed_graph_audit_sha = String(x1_support_completion.extended_graph.get("audit_sha256", ""))
		frozen_identity_check["extended_support_count"] = support_rows.size()
		frozen_identity_check["extended_support_set_sha256"] = observed_support_set_sha
		frozen_identity_check["extended_candidate_triangle_count"] = candidate_triangles.size()
		frozen_identity_check["extended_candidate_graph_sha256"] = observed_candidate_graph_sha
		frozen_identity_check["extended_graph_audit_sha256"] = observed_graph_audit_sha
		frozen_identity_check["baseline_triangle_rows_match_pre_extension"] = baseline_rows_match
		result["frozen_graph_identity_check"] = frozen_identity_check
	var frozen_solver: RefCounted = R6FrozenSolver.new()
	var y_solver_time_raw: String = OS.get_environment("R12CXR_R6_SOLVER_BUDGET_SECONDS")
	var y_solver_time_seconds: int = maxi(1, y_solver_time_raw.to_int()) if not y_solver_time_raw.is_empty() else 28800
	var y_solver_memory_raw: String = OS.get_environment("R12CXR_R6_SOLVER_MEMORY_BUDGET_BYTES")
	var y_solver_memory_bytes: int = maxi(268435456, y_solver_memory_raw.to_int()) if not y_solver_memory_raw.is_empty() else 17179869184
	var y_solver_node_raw: String = OS.get_environment("R12CXR_R6_SOLVER_MAX_NODES")
	var y_solver_max_nodes: int = maxi(1, y_solver_node_raw.to_int()) if not y_solver_node_raw.is_empty() else 0
	var frozen_solver_limits: Dictionary = {"candidate_graph_sha256": observed_candidate_graph_sha, "support_set_sha256": observed_support_set_sha, "expected_candidate_triangles": candidate_triangles.size(), "max_search_states_per_cavity": y_solver_max_nodes if y1_extension else 16384, "max_search_usec_per_cavity": y_solver_time_seconds * 1000000 if y1_extension else 10000000, "max_memory_bytes": y_solver_memory_bytes if y1_extension else 0, "max_patch_triangles": 64}
	var solver_mode: String = OS.get_environment("R12CXR_R6_SOLVER_MODE")
	var d3: Dictionary
	if solver_mode == "legacy-f0":
		d3 = realizer.call("_r2_search_level", context)
		d3["solver_type"] = "R6_F0_LEGACY_FOUR_SUPPORT_CAPTURE"
		d3["support_cardinality_bound"] = "0..4"
	else:
		d3 = frozen_solver.call("solve", context, candidate_triangles, realizer, frozen_solver_limits)
		d3["solver_type"] = "R6_F_FROZEN_GRAPH_MRV_EDGE_COMPLETION_V1"
	d3["solver_mode"] = "legacy-f0" if solver_mode == "legacy-f0" else "corrected-f1"
	d3["started"] = true
	result["d3"] = d3
	var coverage_audit: Dictionary = d3.get("best_solution", {}).get("coverage_area_audit", {})
	result["coverage_area_audit"] = coverage_audit
	if not bool(d3.get("valid", false)):
		var triangulation_complete: bool = bool(d3.get("search_complete", false)) and graph_complete
		if solver_mode == "legacy-f0" and triangulation_complete:
			result["status"] = "R6_F0_REPRODUCED_NO_SOLUTION"
			result["terminal_reason"] = "legacy solver exhaustively searched support cardinalities 0..4 with no solution"
		elif solver_mode == "legacy-f0":
			result["status"] = "R6_F0_REPRODUCTION_PARTIAL"
			result["terminal_reason"] = "legacy bounded solver did not complete its 0..4 support search"
		elif y1_extension and triangulation_complete and bool(synthesis.get("finite_candidate_enumeration_complete", false)):
			result["status"] = "R6_Y1_COMPLETE_SUPPORT_GRAPH_UNSAT_COMPLETE"
			result["terminal_reason"] = "the complete deterministic critical-support domain for every selected-cavity boundary pair and its complete finite triangle graph were UNSAT; continuous regions without representable witnesses remain unresolved unless their analytic bounds prove infeasibility"
		elif y1_extension:
			result["status"] = "R6_Y1_COMPUTATION_PARTIAL_LIMIT"
			result["terminal_reason"] = "support, graph, or solver execution reached a declared resource limit; preserved frontier is not infeasibility evidence"
		elif x3_extension and triangulation_complete and bool(x1_support_completion.get("support_domain_complete", false)):
			result["status"] = "R6_X3_FROZEN_GRAPH_UNSAT_COMPLETE"
			result["terminal_reason"] = "R6-X3 alternative cavity completed its support, graph, and triangulation audits and the selected finite graph is UNSAT; this is bounded to the selected alternative cavity and does not imply continuum or global impossibility"
		elif x3_extension:
			result["status"] = "R6_X3_TRIANGULATION_PARTIAL"
			result["terminal_reason"] = "R6-X3 selected alternative cavity graph or solver did not complete under unchanged preregistered limits"
		elif x4_extension and triangulation_complete and bool(x1_support_completion.get("support_domain_complete", false)):
			result["status"] = "R6_X4_JOINT_GRAPH_UNSAT_COMPLETE"
			result["terminal_reason"] = "R6-X4 complete targeted support generation and complete joint finite graph are UNSAT for the selected alternative cavity; this is bounded to the recorded support domain and does not imply continuum or global impossibility"
		elif x4_extension:
			result["status"] = "R6_X4_JOINT_SUPPORT_PARTIAL"
			result["terminal_reason"] = "R6-X4 solver completed only the recorded joint finite graph; the support domain or support-selection cap remains incomplete"
		elif x6_extension and triangulation_complete and bool(x1_support_completion.get("support_domain_complete", false)):
			result["status"] = "R6_X6_REPRESENTABILITY_GRAPH_UNSAT_COMPLETE"
			result["terminal_reason"] = "R6-X6 completed the bounded binary32 representability neighborhood and the complete finite graph is UNSAT for the selected alternative cavity; this is bounded to the recorded numeric witness domain and does not imply continuous or global impossibility"
		elif x6_extension:
			result["status"] = "R6_X6_REPRESENTABILITY_PARTIAL"
			result["terminal_reason"] = "R6-X6 candidate graph or solver completed only within the recorded bounded representability neighborhood; unsearched numeric neighborhoods and the continuum remain unproven"
		elif x2_extension and triangulation_complete and bool(x1_support_completion.get("support_domain_complete", false)):
			result["status"] = "R6_X2_FROZEN_GRAPH_UNSAT_COMPLETE"
			result["terminal_reason"] = "R6-X2 continuously enumerated all bounded critical arrangement witnesses for the unsatisfied boundary obligations and the complete finite graph is UNSAT; no continuum or global impossibility claim"
		elif x2_extension:
			result["status"] = "R6_X2_SUPPORT_DOMAIN_PARTIAL"
			result["terminal_reason"] = "R6-X2 critical support enumeration or complete triangulation did not complete under unchanged preregistered limits"
		elif x1_extension and triangulation_complete:
			result["status"] = "R6_X1_FROZEN_GRAPH_UNSAT_COMPLETE"
			result["terminal_reason"] = "R6-X1 support-completed finite candidate graph has no valid triangulation; this does not prove continuum, cavity, support, architecture, or Candidate-D impossibility"
		elif x1_extension:
			result["status"] = "R6_X1_TRIANGULATION_PARTIAL"
			result["terminal_reason"] = "R6-X1 graph or corrected triangulation did not complete under unchanged preregistered limits"
		else:
			result["status"] = "R6_TRIANGULATION_PARTIAL" if not triangulation_complete else "R6_SUPPORT_SYNTHESIS_PARTIAL"
			result["terminal_reason"] = "NO_SOLUTION_ON_FINITE_SYNTHESIZED_SUPPORT_GRAPH" if triangulation_complete else "FINITE_GRAPH_OR_TRIANGULATION_GATE_PARTIAL"
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var d3_repeat: Dictionary = frozen_solver.call("solve", context, candidate_triangles, realizer, frozen_solver_limits)
	var d3_first_fingerprint: String = _stable_evidence_sha({"valid": d3.get("valid", false), "best_solution": d3.get("best_solution", {}), "solution_count": d3.get("solution_count", -1), "search_complete": d3.get("search_complete", false)})
	var d3_repeat_fingerprint: String = _stable_evidence_sha({"valid": d3_repeat.get("valid", false), "best_solution": d3_repeat.get("best_solution", {}), "solution_count": d3_repeat.get("solution_count", -1), "search_complete": d3_repeat.get("search_complete", false)})
	result["r6_f_deterministic_repeat"] = {"started": true, "pass": d3_first_fingerprint == d3_repeat_fingerprint, "first_fingerprint_sha256": d3_first_fingerprint, "repeat_fingerprint_sha256": d3_repeat_fingerprint, "repeat_valid": d3_repeat.get("valid", false), "repeat_search_complete": d3_repeat.get("search_complete", false)}
	if not bool(result.get("r6_f_deterministic_repeat", {}).get("pass", false)):
		result["status"] = "R6_F_DETERMINISTIC_REPEAT_FAILED"
		result["terminal_reason"] = "corrected frozen graph solver did not reproduce its first terminal result"
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	if not bool(coverage_audit.get("applicable", false)) or not bool(coverage_audit.get("within_tolerance", false)):
		result["status"] = "R6_COVERAGE_AUDIT_BLOCKED"
		result["terminal_reason"] = "topology-valid triangulation lacks a passing projected-area coverage audit; topology status remains unchanged"
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var solution: Dictionary = d3.get("best_solution", {})
	var replacement_value: Variant = solution.get("final_replacement_triangles", null)
	if typeof(replacement_value) != TYPE_ARRAY:
		result["terminal_reason"] = "D3_SOLUTION_REPLACEMENT_MISSING"
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var replacement: Array[Dictionary] = []
	for triangle_value in replacement_value:
		if typeof(triangle_value) != TYPE_DICTIONARY:
			result["terminal_reason"] = "D3_REPLACEMENT_TRIANGLE_INVALID"
			_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
			return result
		replacement.append(triangle_value)
	var selected_supports: Array = solution.get("selected_supports", [])
	var allowed_support_ids: Dictionary = realizer.get("_cxr_allowed_support_ids")
	for support_value in selected_supports:
		var support: Dictionary = support_value
		allowed_support_ids[String(support.get("support_id", ""))] = true
	realizer.set("_cxr_allowed_support_ids", allowed_support_ids)
	var replacement_ids: Dictionary = {}
	for id_value in patch_ids: replacement_ids[String(id_value)] = true
	var final_triangles: Array[Dictionary] = []
	for triangle in original_triangles:
		if not replacement_ids.has(String(triangle.get("triangle_id", ""))): final_triangles.append(triangle)
	final_triangles.append_array(replacement)
	var patch_record: Dictionary = {"patch_triangle_ids": patch_ids.duplicate(), "replacement_triangles": replacement.duplicate(true), "residual_triangle_ids": residual_fixture.get("residuals", []).map(func(row: Dictionary) -> String: return String(row.get("triangle_id", ""))), "selected_supports": selected_supports.duplicate(true), "level": 2}
	var final_validation: Dictionary = realizer.call("_validate_final_mesh", final_triangles, original_triangles, [patch_record], base, roi, snapshot)
	result["downstream"] = {"started": true, "final_patch_validation": final_validation}
	if not bool(final_validation.get("valid", false)):
		result["terminal_reason"] = String(final_validation.get("reason", "FINAL_PATCH_VALIDATION_FAILED"))
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var mesh: Dictionary = realizer.call("_mesh_from_triangles", final_triangles)
	var topology: Dictionary = Core.topology(mesh, Core.world_min(roi), Core.world_min(roi) + Vector3(Core.cell_counts(roi)) * Core.step(roi))
	var paths: Dictionary = realizer.call("_validate_c6_paths", final_triangles, base.get("applied_flips", []))
	var obligations: Dictionary = realizer.call("_validate_required_arcs", final_triangles, base.get("arc_map", []), base.get("applied_flips", []))
	var cutoff_rows: Array = realizer.call("_cutoff_rows", final_triangles)
	var minimum_cross_squared: float = float(realizer.call("_minimum_cross_squared", final_triangles))
	var topology_roundtrip: bool = bool(base.get("topology_signature_match", false)) and not String(base.get("topology_roundtrip_sha256", "")).is_empty()
	var topology_pass: bool = topology_roundtrip and cutoff_rows.is_empty() and int(obligations.get("missing", -1)) == 0 and int(obligations.get("nonmanifold", -1)) == 0 and bool(paths.get("valid", false))
	var mesh_pass: bool = topology_pass and int(topology.get("internal_open_edges", -1)) == 0 and int(topology.get("nonmanifold_edges", -1)) == 0 and int(topology.get("winding_inconsistencies", -1)) == 0 and int(topology.get("degenerate_triangles", -1)) == 0 and minimum_cross_squared > FROZEN_CROSS_SQUARED_CUTOFF
	var equal_lod: Dictionary = {"started": true, "final_patch_validation": final_validation, "topology_roundtrip": topology_roundtrip, "topology_complete": topology_pass, "mesh_complete": mesh_pass, "mesh_sha256": String(realizer.call("_mesh_sha", mesh)), "mesh_topology": topology, "minimum_cross_squared": minimum_cross_squared, "cutoff_rows": cutoff_rows, "required_arcs": obligations, "preserved_c6_paths": paths, "triangle_count": final_triangles.size(), "support_count": selected_supports.size()}
	result["equal_lod"] = equal_lod
	if mesh_pass:
		var r6_determinism: Dictionary = {"r6_d_cavity": cavity_search.get("deterministic_repeat", {}), "r6_e_supports": result.get("r6_e_deterministic_repeat", {}), "r6_f_solver": result.get("r6_f_deterministic_repeat", {})}
		for extension_key in ["r6_x1_support_completion", "r6_x2_support_completion"]:
			if result.has(extension_key):
				r6_determinism[extension_key] = {"pass": result[extension_key].get("deterministic_repeat_pass", false), "first_fingerprint_sha256": result[extension_key].get("support_fingerprint_sha256", ""), "repeat_fingerprint_sha256": result[extension_key].get("repeat_fingerprint_sha256", "")}
		var rematerialized_mesh: Dictionary = realizer.call("_mesh_from_triangles", final_triangles)
		var rematerialized_mesh_sha: String = String(realizer.call("_mesh_sha", rematerialized_mesh))
		r6_determinism["equal_lod_mesh"] = {"started": true, "pass": rematerialized_mesh_sha == String(realizer.call("_mesh_sha", mesh)), "first_mesh_sha256": String(realizer.call("_mesh_sha", mesh)), "repeat_mesh_sha256": rematerialized_mesh_sha}
		var downstream: Dictionary = _run_r6_downstream_gates(r6_determinism)
		result["downstream"] = downstream
		if bool(downstream.get("all_gates_pass", false)):
			result["status"] = "R12_CXR_R6_EQUAL_LOD_DOWNSTREAM_PASS_VALIDATE_PENDING"
			result["terminal_reason"] = "all_equal_lod_and_downstream_gates_passed_scripts_validate_ps1_pending"
		else:
			var mixed_status: String = String(downstream.get("mixed_lod", {}).get("status", "UNKNOWN_NOT_CAPTURED"))
			result["status"] = "R12_CXR_R6_EQUAL_LOD_QUALIFIED_INTERFACE_BLOCKED_WITH_EVIDENCE" if mixed_status == "FAIL" else "R12_CXR_R6_REALIZATION_PARTIAL_WITH_EVIDENCE"
			result["terminal_reason"] = String(downstream.get("terminal_reason", "downstream_gate_failed_with_evidence"))
	else:
		result["downstream"] = {"started": false, "reason": "NOT_RUN_EQUAL_LOD_GATE_FAILED", "all_gates_pass": false}
		result["status"] = "R6_EQUAL_LOD_GATE_FAIL"
		result["terminal_reason"] = "existing_topology_or_mesh_gate_failed"
	_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
	return result

func _r6_x1_boundary_support_completion(realizer: RefCounted, inventory_realizer: RefCounted, values: PackedFloat32Array, roi: Dictionary, context: Dictionary, patch: Array[Dictionary], existing_supports: Array[Dictionary], boundary_candidate_counts: Dictionary) -> Dictionary:
	var zero_option_edges: Array[String] = []
	var count_keys: Array = boundary_candidate_counts.keys()
	count_keys.sort()
	for key_value in count_keys:
		var edge_key: String = String(key_value)
		if int(boundary_candidate_counts[edge_key]) == 0: zero_option_edges.append(edge_key)
	if zero_option_edges.is_empty(): return {"valid": false, "reason": "R6_X1_HAS_NO_ZERO_OPTION_BOUNDARY_OBLIGATION"}
	var diagnostics: RefCounted = Diagnostics.new()
	var inventory: Dictionary = diagnostics.call("collect_zero_facet_inventory", inventory_realizer, values, roi)
	if not bool(inventory.get("valid", false)): return {"valid": false, "reason": "R6_X1_ZERO_FACET_INVENTORY_INVALID", "inventory": inventory}
	var projection: Dictionary = {"origin": _vector3_array(Vector3(context.get("projection_origin", Vector3.ZERO))), "axis_u": _vector3_array(Vector3(context.get("projection_u", Vector3.ZERO))), "axis_v": _vector3_array(Vector3(context.get("projection_v", Vector3.ZERO)))}
	var root_positions: Dictionary = context.get("vertex_positions", {})
	var boundary_audit: Dictionary = diagnostics.call("analyze_patch_boundary", realizer, patch, context.get("boundary_cycle", []), root_positions, projection, inventory.get("facets", []))
	if not bool(boundary_audit.get("valid", false)): return {"valid": false, "reason": "R6_X1_CONTINUOUS_BOUNDARY_AUDIT_INVALID", "boundary_audit": boundary_audit}
	var audit_by_edge: Dictionary = {}
	for row_value in boundary_audit.get("boundary_edges", []):
		var row: Dictionary = row_value
		audit_by_edge[String(row.get("edge_id", ""))] = row
	var facet_by_key: Dictionary = {}
	for facet_value in inventory.get("facets", []):
		var facet: Dictionary = facet_value
		facet_by_key[String(facet.get("tetrahedron_id", "")) + "|" + str(int(facet.get("facet_index", -1)))] = facet
	var existing_position_ids: Dictionary = {}
	for support in existing_supports: existing_position_ids[String(support.get("binary32_position_identity", ""))] = true
	var generated_by_position: Dictionary = {}
	var generated: Array[Dictionary] = []
	var boundary_edge_map: Dictionary = context.get("boundary_edge_map", {})
	var synthesizer: RefCounted = Synthesizer.new()
	var cutoff: float = FROZEN_CROSS_SQUARED_CUTOFF
	var frozen_residual_epsilon: float = float(realizer.call("_cxr_limits").get("field_residual_epsilon", -1.0))
	for edge_key in zero_option_edges:
		if not audit_by_edge.has(edge_key): return {"valid": false, "reason": "R6_X1_ZERO_OPTION_EDGE_MISSING_CONTINUOUS_AUDIT", "edge_key": edge_key}
		var audit_row: Dictionary = audit_by_edge[edge_key]
		var witness: Dictionary = audit_row.get("feasible_incident_triangle_witness", {})
		if not bool(witness.get("valid", false)) or float(witness.get("cross_squared", -INF)) <= cutoff:
			return {"valid": false, "reason": "R6_X1_ZERO_OPTION_EDGE_HAS_NO_VALID_ANALYTIC_WITNESS", "edge_key": edge_key, "audit_row": audit_row}
		var tetrahedron_id: String = String(witness.get("tetrahedron_id", ""))
		var facet_index: int = int(witness.get("facet_index", -1))
		var facet_key: String = tetrahedron_id + "|" + str(facet_index)
		if not facet_by_key.has(facet_key): return {"valid": false, "reason": "R6_X1_WITNESS_SOURCE_FACET_MISSING", "edge_key": edge_key, "facet_key": facet_key}
		var facet: Dictionary = facet_by_key[facet_key]
		var point_array: Array = witness.get("world_position", [])
		if point_array.size() != 3: return {"valid": false, "reason": "R6_X1_WITNESS_POSITION_INVALID", "edge_key": edge_key}
		var point: Vector3 = Vector3(float(point_array[0]), float(point_array[1]), float(point_array[2]))
		if not point.is_finite(): return {"valid": false, "reason": "R6_X1_WITNESS_POSITION_NONFINITE", "edge_key": edge_key}
		var position_identity: String = String(synthesizer.call("_binary32_position_identity", point))
		if existing_position_ids.has(position_identity): return {"valid": false, "reason": "R6_X1_WITNESS_DUPLICATES_EXISTING_SUPPORT_POSITION", "edge_key": edge_key, "position_identity": position_identity}
		var edge: Dictionary = boundary_edge_map.get(edge_key, {})
		if edge.is_empty(): return {"valid": false, "reason": "R6_X1_BOUNDARY_EDGE_MAP_ENTRY_MISSING", "edge_key": edge_key}
		var source_key: String = "R6-X1|%s|%s|%d|%s" % [edge_key, tetrahedron_id, facet_index, position_identity]
		var support_id: String = String(synthesizer.call("_support_id", point))
		if generated_by_position.has(position_identity):
			var prior: Dictionary = generated_by_position[position_identity]
			var required_edges: Array = prior.get("x1_required_boundary_edges", [])
			if not required_edges.has(edge_key): required_edges.append(edge_key)
			required_edges.sort()
			prior["x1_required_boundary_edges"] = required_edges
			generated_by_position[position_identity] = prior
			continue
		var global_cell_values: Array = facet.get("cell_global", [])
		var local_cell_values: Array = facet.get("cell_local", [])
		if global_cell_values.size() != 3 or local_cell_values.size() != 3: return {"valid": false, "reason": "R6_X1_SOURCE_CELL_PROVENANCE_INVALID", "edge_key": edge_key, "facet_key": facet_key}
		var nearest_centroid_distance: float = INF
		for triangle in patch:
			var points: Array = triangle.get("points", [])
			if points.size() != 3: continue
			var centroid: Vector3 = (Vector3(points[0]) + Vector3(points[1]) + Vector3(points[2])) / 3.0
			nearest_centroid_distance = minf(nearest_centroid_distance, point.distance_to(centroid))
		var constraint_pair: Array[String] = [String(edge.get("a", "")), String(edge.get("b", ""))]
		var support: Dictionary = {"candidate_id": "R6X1C_" + Core.sha256(source_key.to_utf8_buffer()).substr(0, 24), "support_id": support_id, "cavity_id": String(context.get("cavity_id", "")), "residual_triangle_id": "R6X1_ZERO_FACET:%s|facet:%d" % [tetrahedron_id, facet_index], "accepted": true, "supported": true, "rejection_reason": "", "method": "R6_X1_CONTINUOUS_BOUNDARY_WITNESS", "level": 2, "source_cell_local": local_cell_values.duplicate(), "source_cell_global_lattice": global_cell_values.duplicate(), "source_tetrahedron": int(facet.get("tetrahedron_index", -1)), "tetrahedron_sample_values": facet.get("tetrahedron_samples", []).duplicate(), "tetrahedron_corner_world": facet.get("tetrahedron_positions", []).duplicate(), "zero_primitive_id": "%s|facet:%d" % [tetrahedron_id, facet_index], "constraint_boundary_pair": constraint_pair, "constraint_arrangement_region_id": "R6X1REG_" + Core.sha256((edge_key + "|" + facet_key).to_utf8_buffer()).substr(0, 20), "constraint_clearance": float(witness.get("cross_squared", 0.0)) - cutoff, "barycentric_weights": witness.get("tetra_barycentric_weights", []).duplicate(), "frozen_field_interpolated_residual": float(witness.get("continuous_field_residual", INF)), "world_position": point, "distance_to_face_centroid": nearest_centroid_distance, "binary32_position_identity": position_identity, "max_constraint_cross_squared": float(witness.get("cross_squared", 0.0)), "critical_candidate_method": String(witness.get("witness_construction", "R6_D0_ANALYTIC_WITNESS")), "x1_required_boundary_edges": [edge_key]}
		if frozen_residual_epsilon <= 0.0 or absf(float(support.frozen_field_interpolated_residual)) > frozen_residual_epsilon: return {"valid": false, "reason": "R6_X1_WITNESS_FIELD_RESIDUAL_OUTSIDE_FROZEN_EPSILON", "edge_key": edge_key, "residual": support.frozen_field_interpolated_residual, "frozen_epsilon": frozen_residual_epsilon}
		generated_by_position[position_identity] = support
	for support_value in generated_by_position.values(): generated.append(support_value)
	generated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("support_id", "")) < String(b.get("support_id", "")))
	if generated.is_empty(): return {"valid": false, "reason": "R6_X1_NO_NEW_SUPPORTS_GENERATED", "zero_option_edges": zero_option_edges, "boundary_audit": boundary_audit}
	return {"valid": true, "zero_option_edges": zero_option_edges, "boundary_audit": boundary_audit, "supports": generated, "support_count": generated.size(), "candidate_domain": "analytic continuous maxima with validated binary32 witnesses on clipped frozen Candidate-D zero facets; no sampling or parameter relaxation", "field_residual_epsilon": frozen_residual_epsilon, "cross_squared_cutoff": cutoff}

func _r6_x2_critical_support_completion(realizer: RefCounted, zero_set_realizer: RefCounted, values: PackedFloat32Array, roi: Dictionary, context: Dictionary, patch: Array[Dictionary], base_supports: Array[Dictionary], previous_x1_result: Dictionary) -> Dictionary:
	var prior_x1: Dictionary = previous_x1_result.get("r6_x1_support_completion", {})
	var prior_d3: Dictionary = previous_x1_result.get("d3", {})
	var zero_option_edges: Array = prior_x1.get("zero_option_edges", [])
	if zero_option_edges.is_empty(): return {"valid": false, "reason": "R6_X2_NO_UNSAT_BOUNDARY_OBLIGATIONS"}
	var x1_completion: Dictionary = _r6_x1_boundary_support_completion(realizer, zero_set_realizer, values, roi, context, patch, base_supports, prior_d3.get("boundary_edge_candidate_counts", {}))
	if not bool(x1_completion.get("valid", false)): return {"valid": false, "reason": "R6_X2_X1_BASELINE_RECONSTRUCTION_FAILED", "detail": x1_completion}
	var x1_fingerprint: String = _stable_evidence_sha(x1_completion.get("supports", []))
	if x1_fingerprint != String(prior_x1.get("support_fingerprint_sha256", "")):
		return {"valid": false, "reason": "R6_X2_X1_BASELINE_SUPPORT_REPRODUCTION_MISMATCH", "observed": x1_fingerprint, "expected": prior_x1.get("support_fingerprint_sha256", "")}
	var target_pairs: Array = []
	for edge_value in zero_option_edges:
		var halves: PackedStringArray = String(edge_value).split("\u001f")
		if halves.size() != 2: return {"valid": false, "reason": "R6_X2_ZERO_OPTION_EDGE_KEY_INVALID", "edge_key": edge_value}
		target_pairs.append([String(halves[0]), String(halves[1])])
	var synthesizer: RefCounted = Synthesizer.new()
	var cavity_id: String = String(context.get("cavity_id", ""))
	var generated: Dictionary = synthesizer.call("synthesize", realizer, values, roi, context, context.get("residual_triangles", []), cavity_id, context.get("residual_fixture", {}).get("arc_map", []), target_pairs, true)
	if not bool(generated.get("valid", false)):
		return {"valid": false, "reason": "R6_X2_CONTINUOUS_CRITICAL_SYNTHESIS_INVALID", "x1_supports": x1_completion.get("supports", []), "zero_option_edges": zero_option_edges, "x2_continuous_domain": generated}
	var generated_again: Dictionary = Synthesizer.new().call("synthesize", realizer, values, roi, context, context.get("residual_triangles", []), cavity_id, context.get("residual_fixture", {}).get("arc_map", []), target_pairs, true)
	if not bool(generated_again.get("valid", false)):
		return {"valid": false, "reason": "R6_X2_CONTINUOUS_CRITICAL_REPEAT_INVALID", "x2_continuous_domain": generated, "repeat": generated_again}
	var first_generation_fingerprint: String = _support_synthesis_fingerprint(generated)
	var repeat_generation_fingerprint: String = _support_synthesis_fingerprint(generated_again)
	if first_generation_fingerprint != repeat_generation_fingerprint:
		return {"valid": false, "reason": "R6_X2_CONTINUOUS_CRITICAL_REPEAT_MISMATCH", "first_fingerprint_sha256": first_generation_fingerprint, "repeat_fingerprint_sha256": repeat_generation_fingerprint}
	var selected_new: Array[Dictionary] = []
	var already: Dictionary = {}
	for row in base_supports + x1_completion.get("supports", []): already[String(row.get("support_id", ""))] = true
	var per_pair: Dictionary = {}
	for candidate_value in generated.get("supports", []):
		var candidate: Dictionary = candidate_value
		var pair: Array = candidate.get("constraint_boundary_pair", [])
		if pair.size() != 2: continue
		var pair_key: String = String(pair[0]) + "\u001f" + String(pair[1])
		if not per_pair.has(pair_key): per_pair[pair_key] = []
		per_pair[pair_key].append(candidate)
	for pair_key in per_pair:
		per_pair[pair_key].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var cross_a: float = float(a.get("max_constraint_cross_squared", -INF))
			var cross_b: float = float(b.get("max_constraint_cross_squared", -INF))
			if cross_a != cross_b: return cross_a > cross_b
			return String(a.get("support_id", "")) < String(b.get("support_id", ""))
		)
	var per_edge_cursor: Dictionary = {}
	var edge_keys: Array = zero_option_edges.duplicate()
	edge_keys.sort()
	while selected_new.size() < 38:
		var made_progress: bool = false
		for edge_key_value in edge_keys:
			var halves: PackedStringArray = String(edge_key_value).split("\u001f")
			var pair_key: String = String(halves[0]) + "\u001f" + String(halves[1])
			var candidates: Array = per_pair.get(pair_key, [])
			var cursor: int = int(per_edge_cursor.get(pair_key, 0))
			while cursor < candidates.size() and already.has(String(candidates[cursor].get("support_id", ""))): cursor += 1
			if cursor >= candidates.size(): per_edge_cursor[pair_key] = cursor; continue
			var selected_candidate: Dictionary = candidates[cursor]
			per_edge_cursor[pair_key] = cursor + 1
			var support_id: String = String(selected_candidate.get("support_id", ""))
			already[support_id] = true
			selected_new.append(selected_candidate.duplicate(true))
			made_progress = true
			if selected_new.size() >= 38: break
		if not made_progress: break
	var all_supports: Array[Dictionary] = []
	for row in x1_completion.get("supports", []): all_supports.append(row.duplicate(true))
	for row in selected_new: all_supports.append(row.duplicate(true))
	var generated_support_ids: Dictionary = {}
	for row in generated.get("supports", []): generated_support_ids[String(row.get("support_id", ""))] = true
	var generated_new_count: int = 0
	for support_id in generated_support_ids:
		if not already.has(String(support_id)): generated_new_count += 1
	var support_domain_complete: bool = bool(generated.get("finite_candidate_enumeration_complete", false)) and not bool(generated.get("support_cap_hit", false)) and generated_new_count <= 38 and selected_new.size() == generated_new_count and int(base_supports.size()) + all_supports.size() <= 64
	return {"valid": true, "zero_option_edges": zero_option_edges, "boundary_audit": x1_completion.get("boundary_audit", {}), "supports": all_supports, "support_count": all_supports.size(), "x1_supports_reconstructed": x1_completion.get("supports", []), "x1_support_fingerprint_sha256": x1_fingerprint, "x2_selected_supports": selected_new, "x2_continuous_domain": {"target_pairs": target_pairs, "candidate_model": "COMPLETE_CONSTRAINT_ARRANGEMENT_VERTICES_PLUS_DETERMINISTIC_INTERIOR_WITNESSES", "generated": generated, "repeat_fingerprint_sha256": repeat_generation_fingerprint, "deterministic_repeat_pass": first_generation_fingerprint == repeat_generation_fingerprint, "max_new_supports": 38, "generated_new_support_count": generated_new_count, "selected_new_support_count": selected_new.size()}, "support_domain_complete": support_domain_complete, "candidate_domain": "all active arrangement vertices plus deterministic strict-interior transition witnesses for each zero-option root pair, under unchanged direct topology-arc checks; convex cross-squared maximum is checked at every arrangement vertex; no dense sampling", "field_residual_epsilon": 1.0e-7, "cross_squared_cutoff": FROZEN_CROSS_SQUARED_CUTOFF}

static func _r6_x4_zero_boundary_targets(boundary_edge_candidate_counts: Dictionary) -> Dictionary:
	var zero_edge_keys: Array[String] = []
	for edge_value in boundary_edge_candidate_counts:
		if int(boundary_edge_candidate_counts[edge_value]) == 0:
			zero_edge_keys.append(String(edge_value))
	zero_edge_keys.sort()
	var target_pairs: Array = []
	for edge_key in zero_edge_keys:
		var halves: PackedStringArray = edge_key.split("\u001f")
		if halves.size() != 2 or halves[0].is_empty() or halves[1].is_empty():
			return {"valid": false, "reason": "R6_X4_ZERO_BOUNDARY_EDGE_KEY_INVALID", "edge_key": edge_key, "zero_edge_keys": zero_edge_keys}
		var pair: Array[String] = [String(halves[0]), String(halves[1])]
		target_pairs.append(pair)
	return {"valid": not target_pairs.is_empty(), "reason": "" if not target_pairs.is_empty() else "R6_X4_NO_ZERO_BOUNDARY_OBLIGATIONS", "zero_edge_keys": zero_edge_keys, "target_pairs": target_pairs}

static func _r6_x4_merge_support_rows(base_supports: Array[Dictionary], generated_supports: Array[Dictionary], target_pairs: Array, max_total_supports: int) -> Dictionary:
	var base_ids: Dictionary = {}
	var base_positions: Dictionary = {}
	for support in base_supports:
		base_ids[String(support.get("support_id", ""))] = true
		base_positions[String(support.get("binary32_position_identity", ""))] = true
	var pair_keys: Array[String] = []
	var by_pair: Dictionary = {}
	for pair_value in target_pairs:
		var pair: Array = pair_value
		if pair.size() != 2:
			return {"valid": false, "reason": "R6_X4_TARGET_PAIR_ARITY_INVALID"}
		var ids: Array[String] = [String(pair[0]), String(pair[1])]
		ids.sort()
		var key: String = ids[0] + "\u001f" + ids[1]
		if not by_pair.has(key):
			by_pair[key] = []
			pair_keys.append(key)
	pair_keys.sort()
	var duplicates: int = 0
	for candidate in generated_supports:
		var pair: Array = candidate.get("constraint_boundary_pair", [])
		if pair.size() != 2:
			continue
		var ids: Array[String] = [String(pair[0]), String(pair[1])]
		ids.sort()
		var key: String = ids[0] + "\u001f" + ids[1]
		if not by_pair.has(key):
			continue
		by_pair[key].append(candidate.duplicate(true))
	for key in pair_keys:
		by_pair[key].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var margin_a: float = float(a.get("max_constraint_cross_squared", -INF))
			var margin_b: float = float(b.get("max_constraint_cross_squared", -INF))
			if margin_a != margin_b:
				return margin_a > margin_b
			return String(a.get("support_id", "")) < String(b.get("support_id", ""))
		)
	var selected: Array[Dictionary] = []
	var selected_ids: Dictionary = base_ids.duplicate()
	var selected_positions: Dictionary = base_positions.duplicate()
	var cursors: Dictionary = {}
	while base_supports.size() + selected.size() < max_total_supports:
		var made_progress: bool = false
		for key in pair_keys:
			var rows: Array = by_pair.get(key, [])
			var cursor: int = int(cursors.get(key, 0))
			while cursor < rows.size():
				var row: Dictionary = rows[cursor]
				cursor += 1
				var support_id: String = String(row.get("support_id", ""))
				var position_id: String = String(row.get("binary32_position_identity", ""))
				if support_id.is_empty() or position_id.is_empty() or selected_ids.has(support_id) or selected_positions.has(position_id):
					duplicates += 1
					continue
				selected_ids[support_id] = true
				selected_positions[position_id] = true
				selected.append(row)
				made_progress = true
				break
			cursors[key] = cursor
		if not made_progress:
			break
	var generated_unique: Dictionary = {}
	for candidate in generated_supports:
		generated_unique[String(candidate.get("support_id", ""))] = true
	var generated_new_count: int = 0
	for support_id in generated_unique:
		if not base_ids.has(String(support_id)):
			generated_new_count += 1
	return {"valid": true, "supports": base_supports.duplicate(true) + selected, "selected_new_supports": selected, "support_count": base_supports.size() + selected.size(), "generated_unique_new_support_count": generated_new_count, "selected_new_support_count": selected.size(), "candidate_cap_or_selection_loss": selected.size() != generated_new_count, "duplicate_support_rejections": duplicates, "target_pair_order": pair_keys}

func _run_r6_downstream_gates(r6_determinism: Dictionary) -> Dictionary:
	var manifest: Dictionary = Core.load_manifest()
	if not bool(manifest.get("valid", false)): return {"started": false, "all_gates_pass": false, "terminal_reason": "frozen_manifest_invalid", "manifest": manifest}
	var rows: Array = manifest.get("rows", [])
	var target_row: Dictionary = Core.case_by_id(rows, TargetId)
	var snapshot_result: Dictionary = Core.make_snapshot(target_row)
	if target_row.is_empty() or not bool(snapshot_result.get("valid", false)): return {"started": false, "all_gates_pass": false, "terminal_reason": "target_snapshot_reconfirmation_failed", "snapshot": snapshot_result}
	var controls_first: Dictionary = CXRDownstream._run_controls(rows)
	var rays_first: Dictionary = CXRDownstream._run_ray_gate(rows)
	var mixed_first: Dictionary = CXRDownstream._run_mixed_lod_gate(rows)
	var volume_first: Dictionary = _reconfirm_r6_volume(target_row, snapshot_result.get("snapshot", {}))
	var controls_repeat: Dictionary = CXRDownstream._run_controls(rows)
	var rays_repeat: Dictionary = CXRDownstream._run_ray_gate(rows)
	var mixed_repeat: Dictionary = CXRDownstream._run_mixed_lod_gate(rows)
	var volume_repeat: Dictionary = _reconfirm_r6_volume(target_row, snapshot_result.get("snapshot", {}))
	var first_hashes: Dictionary = {"controls": _stable_evidence_sha(controls_first), "roi_rays": _stable_evidence_sha(rays_first), "mixed_lod": _stable_evidence_sha(mixed_first), "volume": _stable_evidence_sha(volume_first)}
	var repeat_hashes: Dictionary = {"controls": _stable_evidence_sha(controls_repeat), "roi_rays": _stable_evidence_sha(rays_repeat), "mixed_lod": _stable_evidence_sha(mixed_repeat), "volume": _stable_evidence_sha(volume_repeat)}
	var r6_repeat_pass: bool = true
	for phase in ["r6_d_cavity", "r6_e_supports", "r6_f_solver", "equal_lod_mesh"]:
		if not bool(r6_determinism.get(phase, {}).get("pass", false)): r6_repeat_pass = false
	if r6_determinism.has("r6_x1_supports") and not bool(r6_determinism.get("r6_x1_supports", {}).get("pass", false)): r6_repeat_pass = false
	var deterministic: bool = first_hashes == repeat_hashes and r6_repeat_pass
	var controls_pass: bool = bool(controls_first.get("valid", false)) and int(controls_first.get("passed", -1)) == 6 and int(controls_first.get("count", -1)) == 6
	var rays_pass: bool = bool(rays_first.get("valid", false)) and int(rays_first.get("ray_count", -1)) == 25 and int(rays_first.get("roi_scoped_hit_miss_disagreements", -1)) == 0
	var volume_pass: bool = bool(volume_first.get("valid", false))
	var mixed_pass: bool = String(mixed_first.get("status", "")) == "PASS"
	var all_pass: bool = controls_pass and rays_pass and volume_pass and mixed_pass and deterministic
	var terminal: String = "all_controls_rays_volume_mixed_lod_and_repeat_gates_passed" if all_pass else "mixed_lod_interface_gate_failed" if not mixed_pass else "downstream_control_ray_volume_or_repeat_gate_failed"
	return {"started": true, "controls": controls_first, "roi_rays": rays_first, "volume_reconfirmation": volume_first, "mixed_lod": mixed_first, "deterministic_repeat": {"pass": deterministic, "first_sha256": first_hashes, "repeat_sha256": repeat_hashes, "r6_realization_repeats": r6_determinism, "controls": controls_repeat, "roi_rays": rays_repeat, "volume_reconfirmation": volume_repeat, "mixed_lod": mixed_repeat}, "full_e2e": {"started": true, "equal_lod_mesh_sha256": r6_determinism.get("equal_lod_mesh", {}).get("first_mesh_sha256", "UNKNOWN_NOT_CAPTURED"), "controls_6_of_6": controls_pass, "roi_rays_0_of_25": rays_pass, "volume_identity": volume_pass, "mixed_lod": mixed_pass, "deterministic_repeat": deterministic, "pass": all_pass}, "full_validation": "PENDING_EXTERNAL_SCRIPTS_VALIDATE_PS1", "controls_pass": controls_pass, "roi_rays_pass": rays_pass, "volume_pass": volume_pass, "mixed_lod_pass": mixed_pass, "determinism_pass": deterministic, "all_gates_pass": all_pass, "terminal_reason": terminal}

func _reconfirm_r6_volume(row: Dictionary, snapshot: Dictionary) -> Dictionary:
	var candidate: RefCounted = CandidateD.new()
	var roi: Dictionary = row.get("roi", {})
	candidate.call("configure_roi", roi)
	var rebuilt: Dictionary = candidate.call("build", snapshot, row, {"id": "R12CXR_R6_VOLUME_RECONFIRM"})
	if not bool(rebuilt.get("valid", false)): return {"valid": false, "reason": "volume_rebuild_invalid", "detail": rebuilt}
	var volume: Dictionary = rebuilt.get("volume", {})
	var metrics: Dictionary = rebuilt.get("metrics", {}).get("volume", {})
	var values: PackedFloat32Array = volume.get("values", PackedFloat32Array())
	var expected_revision: int = int(volume.get("revision", -1))
	var identity: bool = String(volume.get("sha256", "")) == VolumeSha and String(metrics.get("payload_sha256", "")) == PayloadSha and expected_revision == 2 and bool(rebuilt.get("metrics", {}).get("materialized_volume_identity_preserved", false))
	return {"valid": identity, "reason": "" if identity else "frozen_volume_or_payload_identity_mismatch", "volume_sha256": volume.get("sha256", "UNKNOWN_NOT_CAPTURED"), "payload_sha256": metrics.get("payload_sha256", "UNKNOWN_NOT_CAPTURED"), "revision": expected_revision, "value_count": values.size(), "value_bytes_sha256": Core.sha256(values.to_byte_array()), "materialized_volume_identity_preserved": rebuilt.get("metrics", {}).get("materialized_volume_identity_preserved", false)}

static func _stable_evidence_sha(value: Variant) -> String:
	return Core.sha256(JSON.stringify(_json_safe(value)).to_utf8_buffer())

static func _support_synthesis_fingerprint(synthesis: Dictionary) -> String:
	var canonical_supports: Array[Dictionary] = []
	for support_value in synthesis.get("supports", []):
		var support: Dictionary = support_value
		canonical_supports.append({"candidate_id": String(support.get("candidate_id", "")), "support_id": String(support.get("support_id", "")), "binary32_position_identity": String(support.get("binary32_position_identity", "")), "residual_triangle_id": String(support.get("residual_triangle_id", "")), "source_cell_global_lattice": _normalize_lattice(support.get("source_cell_global_lattice", null)), "source_cell_local": _normalize_lattice(support.get("source_cell_local", null)), "source_tetrahedron": int(support.get("source_tetrahedron", -1)), "method": String(support.get("method", "")), "level": int(support.get("level", -1)), "frozen_field_interpolated_residual": _round_report_number(support.get("frozen_field_interpolated_residual", INF)), "barycentric_weights": _round_report_array(support.get("barycentric_weights", [])), "tetrahedron_sample_values": _round_report_array(support.get("tetrahedron_sample_values", [])), "constraint_clearance": _round_report_number(support.get("constraint_clearance", INF)), "max_constraint_cross_squared": _round_report_number(support.get("max_constraint_cross_squared", INF))})
	return _stable_evidence_sha({"valid": synthesis.get("valid", false), "supports": canonical_supports, "retained_support_count": int(synthesis.get("retained_support_count", -1)), "raw_unique_support_count": int(synthesis.get("raw_unique_support_count", -1)), "support_cap_hit": synthesis.get("support_cap_hit", false), "finite_candidate_enumeration_complete": synthesis.get("finite_candidate_enumeration_complete", false)})

func _merge_y1_support_domain_supports(synthesis_value: Dictionary, prior_support_values: Array, realizer: RefCounted) -> Dictionary:
	if not bool(synthesis_value.get("valid", false)):
		return {"valid": false, "reason": "R6_Y1_SUPPORT_SYNTHESIS_INVALID_BEFORE_PRIOR_SUPPORT_UNION"}
	var synthesis: Dictionary = synthesis_value.duplicate(true)
	var supports: Array[Dictionary] = []
	var seen_positions: Dictionary = {}
	var seen_ids: Dictionary = {}
	for support_value in synthesis.get("supports", []):
		var support: Dictionary = support_value
		var position_identity: String = String(support.get("binary32_position_identity", ""))
		var support_id: String = String(support.get("support_id", ""))
		if position_identity.is_empty() or support_id.is_empty():
			return {"valid": false, "reason": "R6_Y1_GENERATED_SUPPORT_IDENTITY_MISSING", "support": support}
		if seen_positions.has(position_identity) or seen_ids.has(support_id):
			return {"valid": false, "reason": "R6_Y1_GENERATED_SUPPORT_DOMAIN_DUPLICATE_IDENTITY", "support_id": support_id, "position_identity": position_identity}
		var generated_geometry: Dictionary = _r6_rehydrate_support_geometry(support)
		if not bool(generated_geometry.get("valid", false)):
			return {"valid": false, "reason": "R6_Y1_GENERATED_SUPPORT_GEOMETRY_REHYDRATION_FAILED", "support_id": support_id, "geometry": generated_geometry}
		seen_positions[position_identity] = true
		seen_ids[support_id] = true
		supports.append(generated_geometry.get("support", {}))
	var generated_support_count: int = supports.size()
	var carried_forward_count: int = 0
	for prior_value in prior_support_values:
		var prior_support: Dictionary = prior_value
		var prior_position_identity: String = String(prior_support.get("binary32_position_identity", ""))
		var prior_support_id: String = String(prior_support.get("support_id", ""))
		if prior_position_identity.is_empty() or prior_support_id.is_empty():
			return {"valid": false, "reason": "R6_Y1_PRIOR_SUPPORT_IDENTITY_MISSING", "support": prior_support}
		if seen_positions.has(prior_position_identity):
			continue
		if seen_ids.has(prior_support_id):
			return {"valid": false, "reason": "R6_Y1_PRIOR_SUPPORT_ID_COLLIDES_AT_DISTINCT_POSITION", "support_id": prior_support_id, "position_identity": prior_position_identity}
		seen_positions[prior_position_identity] = true
		seen_ids[prior_support_id] = true
		var prior_geometry: Dictionary = _r6_rehydrate_support_geometry(prior_support)
		if not bool(prior_geometry.get("valid", false)):
			return {"valid": false, "reason": "R6_Y1_PRIOR_SUPPORT_GEOMETRY_REHYDRATION_FAILED", "support_id": prior_support_id, "geometry": prior_geometry}
		var carried: Dictionary = prior_geometry.get("support", {})
		carried["carried_forward_from_accepted_prior_domain"] = true
		supports.append(carried)
		carried_forward_count += 1
	supports.sort_custom(Callable(realizer, "_candidate_less"))
	synthesis["support_generation_retained_count"] = generated_support_count
	synthesis["carried_forward_prior_support_count"] = carried_forward_count
	synthesis["supports"] = supports
	synthesis["retained_support_count"] = supports.size()
	synthesis["raw_unique_support_count"] = maxi(int(synthesis.get("raw_unique_support_count", generated_support_count)), supports.size())
	synthesis["support_cap_hit"] = false
	return {"valid": true, "synthesis": synthesis, "generated_support_count": generated_support_count, "carried_forward_support_count": carried_forward_count, "merged_support_count": supports.size(), "deduplication_key": "BINARY32_POSITION_IDENTITY", "prior_support_domain_preserved": true}

func _r6_rehydrate_support_geometry(source_support: Dictionary) -> Dictionary:
	var support: Dictionary = source_support.duplicate(true)
	var global_cell_value: Dictionary = _r6_parse_vector3(support.get("source_cell_global_lattice", null))
	var local_cell_value: Dictionary = _r6_parse_vector3(support.get("source_cell_local", null))
	var world_position_value: Dictionary = _r6_parse_vector3(support.get("world_position", null))
	if not bool(global_cell_value.get("valid", false)) or not bool(local_cell_value.get("valid", false)) or not bool(world_position_value.get("valid", false)):
		return {"valid": false, "reason": "support_cell_or_position_invalid", "global_cell": global_cell_value, "local_cell": local_cell_value, "world_position": world_position_value}
	support["source_cell_global_lattice"] = Vector3i(roundi(float(global_cell_value.point.x)), roundi(float(global_cell_value.point.y)), roundi(float(global_cell_value.point.z)))
	support["source_cell_local"] = Vector3i(roundi(float(local_cell_value.point.x)), roundi(float(local_cell_value.point.y)), roundi(float(local_cell_value.point.z)))
	support["world_position"] = Vector3(world_position_value.point)
	var corners: Array[Vector3] = []
	for corner_value in support.get("tetrahedron_corner_world", []):
		var corner_result: Dictionary = _r6_parse_vector3(corner_value)
		if not bool(corner_result.get("valid", false)):
			return {"valid": false, "reason": "tetra_corner_invalid", "corner": corner_value}
		corners.append(Vector3(corner_result.point))
	support["tetrahedron_corner_world"] = corners
	return {"valid": true, "support": support}

func _load_y1_resume_state(result_path: String, expected_result_sha256: String, expected_stream_sha256: String, attempt_id: String, expected_boundary_pairs: Array) -> Dictionary:
	var merged_region_states: Dictionary = {}
	var merged_numeric_frontiers: Dictionary = {}
	var merged_supports: Dictionary = {}
	var resolution_counts: Dictionary = {}
	var seen_paths: Dictionary = {}
	var current_path: String = result_path
	var current_result_sha: String = expected_result_sha256
	var current_stream_sha: String = expected_stream_sha256
	var latest_metadata: Dictionary = {}
	var first_ancestor_path: String = ""
	while not current_path.is_empty():
		if seen_paths.has(current_path):
			return {"valid": false, "reason": "RESUME_CHAIN_CYCLE", "path": current_path}
		seen_paths[current_path] = true
		var current_state: Dictionary = _load_y1_resume_state_single(current_path, current_result_sha, current_stream_sha, attempt_id, expected_boundary_pairs)
		if not bool(current_state.get("valid", false)):
			return {"valid": false, "reason": "RESUME_CHAIN_SOURCE_INVALID", "prior_result_path": current_path, "prior_resume": current_state}
		var current_metadata: Dictionary = current_state.get("metadata", {})
		if latest_metadata.is_empty(): latest_metadata = current_metadata.duplicate(true)
		for region_key in current_state.get("region_states", {}).keys():
			if not merged_region_states.has(region_key): merged_region_states[region_key] = current_state.region_states[region_key]
		for frontier_key in current_state.get("numeric_frontiers", {}).keys():
			var candidate_frontier: Dictionary = current_state.numeric_frontiers[frontier_key]
			var existing_frontier: Dictionary = merged_numeric_frontiers.get(frontier_key, {})
			if not merged_numeric_frontiers.has(frontier_key) or int(candidate_frontier.get("tested_triples", 0)) > int(existing_frontier.get("tested_triples", -1)):
				merged_numeric_frontiers[frontier_key] = candidate_frontier
		for support in current_state.get("supports", []):
			var support_identity: String = String(support.get("binary32_position_identity", support.get("support_id", "")))
			if not support_identity.is_empty() and not merged_supports.has(support_identity): merged_supports[support_identity] = support
		var node_bytes: PackedByteArray = FileAccess.get_file_as_bytes(current_path)
		var node_value: Variant = JSON.parse_string(node_bytes.get_string_from_utf8().replace(String.chr(31), "\\u001f").replace(String.chr(30), "\\u001e"))
		if typeof(node_value) != TYPE_DICTIONARY:
			return {"valid": false, "reason": "RESUME_CHAIN_SOURCE_SCHEMA_INVALID", "path": current_path}
		var node_result: Dictionary = node_value
		var node_synthesis: Dictionary = node_result.get("support_synthesis", {})
		var node_resume: Dictionary = node_result.get("resume_metadata", node_synthesis.get("resume_metadata", {}))
		var prior_path: String = String(node_resume.get("source_result_path", ""))
		if prior_path.is_empty() or prior_path == current_path or not FileAccess.file_exists(prior_path): break
		if first_ancestor_path.is_empty(): first_ancestor_path = prior_path
		current_path = prior_path
		current_result_sha = String(node_resume.get("source_result_sha256", ""))
		current_stream_sha = String(node_resume.get("source_stream_sha256", ""))
	var merged_support_array: Array = []
	for support in merged_supports.values(): merged_support_array.append(support)
	for region in merged_region_states.values():
		var resolution: String = String(region.get("resolution", ""))
		resolution_counts[resolution] = int(resolution_counts.get(resolution, 0)) + 1
	latest_metadata["merged_prior_source_result_path"] = first_ancestor_path
	latest_metadata["resumed_region_count"] = merged_region_states.size()
	latest_metadata["resumed_resolution_histogram"] = resolution_counts
	latest_metadata["resumed_numeric_frontier_count"] = merged_numeric_frontiers.size()
	latest_metadata["resumed_numeric_tested_triples"] = merged_numeric_frontiers.values().reduce(func(total: int, frontier: Dictionary) -> int: return total + int(frontier.get("tested_triples", 0)), 0)
	latest_metadata["resumed_support_count"] = merged_support_array.size()
	return {"valid": true, "region_states": merged_region_states, "numeric_frontiers": merged_numeric_frontiers, "supports": merged_support_array, "metadata": latest_metadata}

func _load_y1_resume_state_single(result_path: String, expected_result_sha256: String, expected_stream_sha256: String, attempt_id: String, expected_boundary_pairs: Array) -> Dictionary:
	var result_bytes: PackedByteArray = FileAccess.get_file_as_bytes(result_path) if FileAccess.file_exists(result_path) else PackedByteArray()
	var observed_result_sha256: String = Core.sha256(result_bytes)
	if expected_result_sha256.length() != 64 or observed_result_sha256 != expected_result_sha256:
		return {"valid": false, "reason": "RESUME_RESULT_SHA256_MISMATCH", "path": result_path, "observed_sha256": observed_result_sha256, "expected_sha256": expected_result_sha256}
	var result_text: String = result_bytes.get_string_from_utf8().replace(String.chr(31), "\\u001f").replace(String.chr(30), "\\u001e")
	var result_value: Variant = JSON.parse_string(result_text)
	if typeof(result_value) != TYPE_DICTIONARY:
		return {"valid": false, "reason": "RESUME_RESULT_SCHEMA_INVALID", "path": result_path}
	var result: Dictionary = result_value
	var synthesis: Dictionary = result.get("support_synthesis", {})
	var stream: Dictionary = synthesis.get("continuous_region_stream", {})
	var stream_path: String = String(stream.get("path", ""))
	var observed_stream_sha256: String = Core.sha256(FileAccess.get_file_as_bytes(stream_path)) if FileAccess.file_exists(stream_path) else ""
	if String(result.get("attempt_id", "")) != attempt_id or not bool(result.get("target_attempt_consumed", false)) or bool(result.get("support_domain_complete", false)) or String(result.get("status", "")) not in ["R6_Y1_SUPPORT_DOMAIN_PARTIAL_LIMIT", "R6_Y1_CONTINUOUS_REGION_FEASIBILITY_UNKNOWN"] or String(stream.get("sha256", "")) != expected_stream_sha256 or observed_stream_sha256 != expected_stream_sha256:
		return {"valid": false, "reason": "RESUME_RESULT_OR_STREAM_IDENTITY_INVALID", "attempt_id": result.get("attempt_id", ""), "status": result.get("status", ""), "target_attempt_consumed": result.get("target_attempt_consumed", false), "support_domain_complete": result.get("support_domain_complete", false), "stream_path": stream_path, "stream_sha256": stream.get("sha256", ""), "observed_stream_sha256": observed_stream_sha256, "expected_stream_sha256": expected_stream_sha256}
	var prior_pairs: Array = result.get("boundary_pair_domain", [])
	if JSON.stringify(prior_pairs) != JSON.stringify(expected_boundary_pairs):
		return {"valid": false, "reason": "RESUME_BOUNDARY_PAIR_DOMAIN_MISMATCH", "prior_pair_count": prior_pairs.size(), "current_pair_count": expected_boundary_pairs.size()}
	var region_states: Dictionary = {}
	var resolution_counts: Dictionary = {}
	var numeric_frontiers: Dictionary = {}
	var stream_text: String = FileAccess.get_file_as_string(stream_path)
	for line_value in stream_text.split("\n", false):
		var row_value: Variant = JSON.parse_string(line_value.replace(String.chr(31), "\\u001f").replace(String.chr(30), "\\u001e"))
		if typeof(row_value) != TYPE_DICTIONARY: continue
		var row: Dictionary = row_value
		var record_value: Variant = row.get("record", {})
		if typeof(record_value) != TYPE_DICTIONARY: continue
		var record: Dictionary = record_value
		if String(row.get("record_type", "")) == "critical_candidate_gate_audit":
			var correction: Dictionary = record.get("binary32_representability_correction", {})
			var region_id: String = String(record.get("arrangement_region_id", ""))
			if String(correction.get("search_state", "")) == "PARTIAL_LIMIT" and not region_id.is_empty():
				var frontier: Dictionary = correction.get("search_frontier", {})
				var pair: Array = record.get("boundary_pair", [])
				var cell: Array = record.get("source_cell_global_lattice", [])
				var projected: Array = record.get("projected_position", [])
				if not frontier.is_empty() and pair.size() == 2 and cell.size() == 3 and projected.size() == 2:
					frontier["arrangement_region_id"] = region_id
					frontier["boundary_pair"] = record.get("boundary_pair", [])
					frontier["source_cell_global_lattice"] = record.get("source_cell_global_lattice", [])
					frontier["source_tetrahedron"] = record.get("source_tetrahedron", -1)
					frontier["source_facet"] = record.get("source_facet", -1)
					frontier["critical_candidate_method"] = record.get("critical_candidate_method", "UNKNOWN_NOT_CAPTURED")
					frontier["seed_projected_position"] = record.get("projected_position", [])
					var resume_key: String = JSON.stringify([region_id, String(pair[0]), String(pair[1]), cell, int(record.get("source_tetrahedron", -1)), int(record.get("source_facet", -1)), String(record.get("critical_candidate_method", "UNKNOWN_NOT_CAPTURED")), projected])
					frontier["resume_key"] = resume_key
					var prior_frontier: Dictionary = numeric_frontiers.get(resume_key, {})
					if int(frontier.get("tested_triples", 0)) > int(prior_frontier.get("tested_triples", -1)):
						numeric_frontiers[resume_key] = frontier
			continue
		if String(row.get("record_type", "")) != "continuous_zero_set_region_resolution": continue
		var resolution: String = String(record.get("resolution", ""))
		if resolution not in ["ANALYTIC_UPPER_BOUND_AT_OR_BELOW_FROZEN_CUTOFF", "ANALYTIC_NO_STRICT_REGION_CAVITY_INTERSECTION", "VALID_REPRESENTABLE_SUPPORT_WITNESS", "EXHAUSTIVE_NO_VALID_REPRESENTABLE_SUPPORT_IN_TETRA_DOMAIN"]: continue
		var region_id: String = String(record.get("region_id", ""))
		var pair: Array = record.get("source_pair", [])
		var cell: Array = record.get("source_cell_global_lattice", [])
		if region_id.is_empty() or pair.size() != 2 or cell.size() != 3: continue
		var region_key: String = JSON.stringify([region_id, String(pair[0]), String(pair[1]), cell, int(record.get("source_tetrahedron", -1)), int(record.get("source_facet", -1))])
		region_states[region_key] = record
		resolution_counts[resolution] = int(resolution_counts.get(resolution, 0)) + 1
	var resume_support_by_identity: Dictionary = {}
	for support_value in synthesis.get("supports", []):
		if typeof(support_value) != TYPE_DICTIONARY: continue
		var support: Dictionary = support_value
		if bool(support.get("accepted", false)) and bool(support.get("supported", false)):
			var support_identity: String = String(support.get("binary32_position_identity", support.get("support_id", "")))
			if not support_identity.is_empty(): resume_support_by_identity[support_identity] = support
	var resume_supports: Array = []
	for support_identity in resume_support_by_identity.keys(): resume_supports.append(resume_support_by_identity[support_identity])
	var resume_metadata: Dictionary = result.get("resume_metadata", synthesis.get("resume_metadata", {}))
	return {"valid": true, "region_states": region_states, "numeric_frontiers": numeric_frontiers, "supports": resume_supports, "metadata": {"source_result_path": result_path, "source_result_sha256": observed_result_sha256, "source_stream_path": stream_path, "source_stream_sha256": observed_stream_sha256, "prior_result_path": resume_metadata.get("source_result_path", ""), "prior_result_sha256": resume_metadata.get("source_result_sha256", ""), "prior_stream_sha256": resume_metadata.get("source_stream_sha256", ""), "resumed_region_count": region_states.size(), "resumed_resolution_histogram": resolution_counts, "resumed_numeric_frontier_count": numeric_frontiers.size(), "resumed_numeric_tested_triples": numeric_frontiers.values().reduce(func(total: int, frontier: Dictionary) -> int: return total + int(frontier.get("tested_triples", 0)), 0), "resumed_support_count": resume_supports.size(), "prior_attempt_id": result.get("attempt_id", ""), "same_scientific_attempt": true}}

func _run_y1_resume_check() -> void:
	var result_path: String = OS.get_environment("R12CXR_R6_Y1_RESUME_INPUT")
	var result_bytes: PackedByteArray = FileAccess.get_file_as_bytes(result_path) if FileAccess.file_exists(result_path) else PackedByteArray()
	var result_text: String = result_bytes.get_string_from_utf8().replace(String.chr(31), "\\u001f").replace(String.chr(30), "\\u001e")
	var result_value: Variant = JSON.parse_string(result_text)
	if typeof(result_value) != TYPE_DICTIONARY:
		printerr("R6_Y1_RESUME_CHECK=FAIL invalid source result")
		quit(1)
		return
	var source_result: Dictionary = result_value
	var resumed: Dictionary = _load_y1_resume_state(result_path, OS.get_environment("R12CXR_R6_Y1_RESUME_SHA256"), OS.get_environment("R12CXR_R6_Y1_RESUME_STREAM_SHA256"), OS.get_environment("R12CXR_R6_ATTEMPT_ID"), source_result.get("boundary_pair_domain", []))
	var valid: bool = bool(resumed.get("valid", false)) and int(resumed.get("metadata", {}).get("resumed_region_count", 0)) > 0 and int(resumed.get("metadata", {}).get("resumed_support_count", 0)) > 0
	var resume_report: Dictionary = resumed.get("metadata", resumed).duplicate(true)
	var diagnostic_region: String = OS.get_environment("R12CXR_R6_Y1_DIAGNOSTIC_REGION")
	if bool(resumed.get("valid", false)) and not diagnostic_region.is_empty():
		var diagnostic_frontiers: Array = []
		for frontier_value in resumed.get("numeric_frontiers", {}).values():
			if String(frontier_value.get("arrangement_region_id", "")) == diagnostic_region:
				diagnostic_frontiers.append(frontier_value)
		resume_report["diagnostic_region_frontiers"] = diagnostic_frontiers
	print("R6_Y1_RESUME_CHECK=" + ("PASS" if valid else "FAIL") + " " + JSON.stringify(resume_report))
	quit(0 if valid else 1)

func _r6_parse_vector3(value: Variant) -> Dictionary:
	if value is Vector3: return {"valid": true, "point": Vector3(value)}
	if value is Vector3i: return {"valid": true, "point": Vector3(value)}
	var coordinates: Array = []
	if value is Array:
		coordinates = value.duplicate()
	elif typeof(value) == TYPE_STRING:
		var source: String = String(value).strip_edges()
		if source.begins_with("(") and source.ends_with(")"): source = source.substr(1, source.length() - 2)
		coordinates = source.split(",")
	if coordinates.size() != 3: return {"valid": false, "reason": "vector3_evidence_shape_invalid", "value": value}
	var parsed: Array[float] = []
	for coordinate in coordinates:
		var numeric: float = float(String(coordinate).strip_edges()) if typeof(coordinate) == TYPE_STRING else float(coordinate)
		if not is_finite(numeric): return {"valid": false, "reason": "vector3_evidence_nonfinite", "value": value}
		parsed.append(numeric)
	return {"valid": true, "point": Vector3(parsed[0], parsed[1], parsed[2])}

static func _round_report_number(value: Variant) -> Variant:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)): return value
	return roundf(float(value) * 1.0e12) / 1.0e12

static func _round_report_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array or value is PackedFloat32Array or value is PackedFloat64Array:
		for item in value: result.append(_round_report_number(item))
	return result

func _support_summary_for_diagnostic(synthesis: Dictionary) -> Dictionary:
	var supports: Array = synthesis.get("supports", [])
	var ids: Array[String] = []
	for row_value in supports:
		var row: Dictionary = row_value
		ids.append(String(row.get("support_id", "UNKNOWN_NOT_CAPTURED")))
	return {"valid": synthesis.get("valid", false), "support_count": supports.size(), "retained_support_count": synthesis.get("retained_support_count", "UNKNOWN_NOT_CAPTURED"), "raw_unique_support_count": synthesis.get("raw_unique_support_count", "UNKNOWN_NOT_CAPTURED"), "candidate_model": synthesis.get("candidate_model", "UNKNOWN_NOT_CAPTURED"), "support_ids": ids, "support_ids_sha256": _stable_evidence_sha(ids)}

func _support_row_differences(previous_rows: Array, continued_rows: Array, limit: int) -> Array[Dictionary]:
	var differences: Array[Dictionary] = []
	var shared_count: int = mini(previous_rows.size(), continued_rows.size())
	for index in range(shared_count):
		var previous_row: Dictionary = previous_rows[index]
		var continued_row: Dictionary = continued_rows[index]
		var keys: Array = previous_row.keys()
		for key in continued_row.keys():
			if not keys.has(key): keys.append(key)
		keys.sort()
		for key in keys:
			var previous_value: Variant = previous_row.get(key, "MISSING")
			var continued_value: Variant = continued_row.get(key, "MISSING")
			if JSON.stringify(_json_safe(previous_value)) != JSON.stringify(_json_safe(continued_value)):
				differences.append({"row_index": index, "support_id": previous_row.get("support_id", "UNKNOWN_NOT_CAPTURED"), "key": String(key), "previous": _json_safe(previous_value), "continued": _json_safe(continued_value)})
				if differences.size() >= limit: return differences
	if previous_rows.size() != continued_rows.size(): differences.append({"previous_count": previous_rows.size(), "continued_count": continued_rows.size()})
	return differences

func _run_evidence_writer_check() -> void:
	var output_path: String = OS.get_environment("TEMP").path_join("R6-evidence-writer-%d.json" % Time.get_ticks_usec())
	var test_result: Dictionary = {"schema": "R6.EvidenceWriterCheck.v1", "status": "WRITER_TEST", "vector": Vector3(1.0, 2.0, 3.0), "edge_key": "edge|left" + String.chr(31) + "edge|right"}
	if not _write_result(output_path, test_result, "R6_EVIDENCE_WRITER_CHECK"):
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(output_path))
	var passed: bool = typeof(parsed) == TYPE_DICTIONARY and parsed.get("schema", "") == "R6.EvidenceWriterCheck.v1" and parsed.get("vector", []) == [1.0, 2.0, 3.0] and String(parsed.get("edge_key", "")) == String(test_result.edge_key)
	var output_sha256: String = Core.sha256(FileAccess.get_file_as_bytes(output_path))
	DirAccess.remove_absolute(output_path)
	if not passed:
		printerr("R6_EVIDENCE_WRITER_CHECK=FAIL " + JSON.stringify({"sha256": output_sha256}))
		quit(1)
		return
	print("R6_EVIDENCE_WRITER_CHECK=PASS sha256=%s" % output_sha256)
	quit(0)

func _json_evidence_bytes(value: Variant) -> PackedByteArray:
	var serialized: String = JSON.stringify(_json_safe(value), "\t", false)
	serialized = serialized.replace(String.chr(31), "\\u001f").replace(String.chr(30), "\\u001e")
	return serialized.to_utf8_buffer()

func _write_result(output_path: String, result: Dictionary, marker: String) -> bool:
	if output_path.is_empty() or FileAccess.file_exists(output_path):
		_fail("r6_result_output_path_invalid_or_exists", {"path": output_path})
		return false
	var bytes: PackedByteArray = _json_evidence_bytes(result)
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("r6_result_output_open_failed", {"error": FileAccess.get_open_error()})
		return false
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_fail("r6_result_output_write_failed", {"error": write_error})
		return false
	print(marker + " " + JSON.stringify({"status": result.get("status", "UNKNOWN_NOT_CAPTURED"), "terminal_reason": result.get("terminal_reason", "UNKNOWN_NOT_CAPTURED"), "supports": result.get("synthesis", {}).get("retained_support_count", "UNKNOWN_NOT_CAPTURED"), "legal_triangles": result.get("graph_gate", {}).get("legal_triangle_count", "NOT_RUN"), "d3_started": result.get("d3", {}).get("started", false), "result_sha256": Core.sha256(bytes), "output_path": output_path}))
	return true

static func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			var point: Vector2 = value
			return [point.x, point.y]
		TYPE_VECTOR3:
			var point3: Vector3 = value
			return [point3.x, point3.y, point3.z]
		TYPE_VECTOR3I:
			var cell: Vector3i = value
			return [cell.x, cell.y, cell.z]
		TYPE_PACKED_FLOAT32_ARRAY:
			var floats: Array = []
			for number in value: floats.append(number)
			return floats
		TYPE_PACKED_BYTE_ARRAY:
			return (value as PackedByteArray).hex_encode()
		TYPE_ARRAY:
			var rows: Array = []
			for item in value: rows.append(_json_safe(item))
			return rows
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			var keys: Array = value.keys()
			keys.sort()
			for key in keys: out[key] = _json_safe(value[key])
			return out
		_:
			return value

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

static func _normalize_lattice(value: Variant) -> Variant:
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

func _r6_regenerate_support_rows(realizer: RefCounted, seed_triangles: Array[Dictionary], patch: Array[Dictionary], values: PackedFloat32Array, roi: Dictionary, support_fixture: Dictionary, seed_by_id: Dictionary) -> Dictionary:
	if seed_triangles.is_empty(): return {"valid": false, "reason": "r6_seed_triangles_missing"}
	var by_position: Dictionary = {}; var attempts: int = 0; var max_per_seed: int = maxi(1, int(floor(256.0 / float(seed_triangles.size()))))
	for seed_triangle in seed_triangles:
		var seed_id: String = String(seed_triangle.get("triangle_id", "")); var remaining: int = int(support_fixture.get("support_candidate_attempt_count", 0)) - attempts
		var generated: Dictionary = realizer.call("_generate_field_candidates", seed_triangle, patch, values, roi, 2, max_per_seed, remaining, String(support_fixture.get("cavity_id", "")), seed_by_id.get(seed_id, {}))
		if not bool(generated.get("source_valid", false)): return {"valid": false, "reason": "r6_support_generation_source_invalid", "seed_id": seed_id, "detail": generated}
		attempts += generated.get("attempts", []).size()
		for support_value in generated.get("candidate_pool", []):
			var support: Dictionary = support_value; var identity: String = String(support.get("binary32_position_identity", ""))
			if not by_position.has(identity): by_position[identity] = support.duplicate(true)
			else:
				var prior: Dictionary = by_position[identity]; var provenance: Array = prior.get("coalesced_candidate_ids", []); var candidate_id: String = String(support.get("candidate_id", ""))
				if not provenance.has(candidate_id): provenance.append(candidate_id)
				provenance.sort()
				if bool(realizer.call("_candidate_less", support, prior)): support["coalesced_candidate_ids"] = provenance; by_position[identity] = support.duplicate(true)
				else: prior["coalesced_candidate_ids"] = provenance; by_position[identity] = prior
	var rows: Array[Dictionary] = []; for value in by_position.values(): rows.append(value)
	rows.sort_custom(Callable(realizer, "_candidate_less"))
	return {"valid": attempts <= int(support_fixture.get("support_candidate_attempt_count", 0)), "rows": rows, "candidate_attempt_count": attempts, "support_count": rows.size(), "candidate_attempt_budget": support_fixture.get("support_candidate_attempt_count", 0)}

func _fail(reason: String, details: Dictionary) -> void:
	_terminal_failure_requested = true
	printerr("R6_CAMPAIGN_FAIL " + JSON.stringify({"reason": reason, "details": details}))
	quit(2)

func _build_frozen_cavity_fixture(realizer: RefCounted, context: Dictionary, patch: Array[Dictionary], patch_ids: Array, boundary: Dictionary, cycle: Array, d2: Dictionary, root_positions: Dictionary, r4_result: Dictionary) -> Dictionary:
	var projection: Dictionary = _projection_context(realizer, patch, root_positions, cycle)
	if not bool(projection.get("valid", false)):
		return {"valid": false, "reason": "r6_projection_reconstruction_invalid", "detail": projection}
	var bounds: Dictionary = realizer.call("_patch_world_bounds", patch)
	if not bool(bounds.get("valid", true)) or not (bounds.get("min", null) is Vector3) or not (bounds.get("max", null) is Vector3):
		return {"valid": false, "reason": "r6_patch_world_bounds_invalid", "detail": bounds}
	var vertex_positions: Dictionary = context.get("vertex_positions", {})
	var projected_positions: Dictionary = context.get("projected_positions", {})
	var vertex_ids: Array[String] = _sorted_keys(vertex_positions)
	var root_rows: Array[Dictionary] = []
	for vertex_id in vertex_ids:
		var point_value: Variant = vertex_positions[vertex_id]
		if not (point_value is Vector3) or not Vector3(point_value).is_finite():
			return {"valid": false, "reason": "r6_vertex_position_missing_or_nonfinite", "vertex_id": vertex_id}
		var projected: Vector2 = Vector2.ZERO
		if projected_positions.has(vertex_id):
			projected = Vector2(projected_positions[vertex_id])
		else:
			var delta: Vector3 = Vector3(point_value) - Vector3(projection.origin)
			projected = Vector2(delta.dot(Vector3(projection.axis_u)), delta.dot(Vector3(projection.axis_v)))
		root_rows.append({"root_id": vertex_id, "world": _vector3_array(Vector3(point_value)), "projected": _vector2_array(projected)})
	var patch_rows: Array[Dictionary] = []
	var sorted_patch: Array[Dictionary] = patch.duplicate(true)
	sorted_patch.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("triangle_id", "")) < String(b.get("triangle_id", "")))
	for triangle in sorted_patch:
		var points: Array = triangle.get("points", [])
		var ids: Array = triangle.get("root_ids", [])
		if points.size() != 3 or ids.size() != 3:
			return {"valid": false, "reason": "r6_patch_triangle_geometry_invalid", "triangle_id": triangle.get("triangle_id", "")}
		patch_rows.append({"triangle_id": String(triangle.get("triangle_id", "")), "root_ids": ids.duplicate(), "points": [_vector3_array(Vector3(points[0])), _vector3_array(Vector3(points[1])), _vector3_array(Vector3(points[2]))], "polygon_id": String(triangle.get("polygon_id", "")), "source_polygon_ids": triangle.get("source_polygon_ids", []).duplicate()})
	var owner_rows: Array[Dictionary] = []
	for owner_triangle_value in context.get("residual_triangles", []):
		var owner_triangle: Dictionary = owner_triangle_value
		var owner_points: Array = owner_triangle.get("points", [])
		var owner_ids: Array = owner_triangle.get("root_ids", [])
		if owner_points.size() != 3 or owner_ids.size() != 3:
			return {"valid": false, "reason": "r6_owner_triangle_geometry_invalid", "triangle_id": owner_triangle.get("triangle_id", "")}
		var projected_owner: Array = []
		for root_id_value in owner_ids:
			var root_id: String = String(root_id_value)
			if not projected_positions.has(root_id):
				return {"valid": false, "reason": "r6_owner_projection_missing", "root_id": root_id}
			projected_owner.append(_vector2_array(Vector2(projected_positions[root_id])))
		owner_rows.append({"triangle_id": String(owner_triangle.get("triangle_id", "")), "root_ids": owner_ids.duplicate(), "points": [_vector3_array(Vector3(owner_points[0])), _vector3_array(Vector3(owner_points[1])), _vector3_array(Vector3(owner_points[2]))], "projected": projected_owner, "polygon_id": String(owner_triangle.get("polygon_id", "")), "source_polygon_ids": owner_triangle.get("source_polygon_ids", []).duplicate()})
	owner_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("triangle_id", "")) < String(b.get("triangle_id", "")))
	var d2_boundary: Dictionary = d2.get("boundary", {})
	var local_fixture: Dictionary = context.get("residual_fixture", {})
	var local_arcs: Array = local_fixture.get("arc_map", []).duplicate(true)
	var global_arcs: Array = context.get("global_arc_map", []).duplicate(true)
	var topology_ids: Array[String] = _sorted_keys(context.get("required_topology_root_ids", {}))
	var polygon_points: Array = []
	for point_value in projection.get("polygon", []): polygon_points.append(_vector2_array(Vector2(point_value)))
	var fixture: Dictionary = {
		"schema": "P3.1.R12CXR.R5FrozenCavity.v1",
		"target_id": TargetId,
		"r4_source_sha": R4SourceSha,
		"r4_d1_result_sha256": R4D1ResultSha,
		"candidate_d_sha256": CandidateSha,
		"manifest_sha256": ManifestSha,
		"stage0_sha256": Stage0Sha,
		"topology_sha256": TopologySha,
		"graph_fingerprint_sha256": GraphSha,
		"residual_fixture_sha256": ResidualSha,
		"support_pool_fixture_sha256": SupportPoolSha,
		"volume_sha256": VolumeSha,
		"payload_sha256": PayloadSha,
		"revision": 2,
		"cavity_id": String(r4_result.get("cavity_id", "")),
		"seed_triangle_ids": _string_array(r4_result.get("seed_triangle_ids", [])),
		"removed_patch_triangle_ids": _string_array(patch_ids),
		"boundary_signature": String(boundary.get("signature", "")),
		"boundary_directed_edges": boundary.get("directed_edges", []).duplicate(),
		"boundary_cycle": cycle.duplicate(),
		"boundary_cycles": d2.get("boundary_cycles", []).duplicate(true),
		"boundary_component_count": int(boundary.get("boundary_component_count", 0)),
		"boundary_edge_count": int(boundary.get("boundary_edge_count", 0)),
		"local_topology_obligations": local_arcs,
		"global_topology_arcs": global_arcs,
		"required_topology_root_ids": topology_ids,
		"source_owner_boundary_arc_count": int(context.get("source_owner_boundary_arc_count", -1)),
		"patch_bounds_world": {"min": _vector3_array(Vector3(bounds.min)), "max": _vector3_array(Vector3(bounds.max))},
		"projection": {"origin": _vector3_array(Vector3(projection.origin)), "axis_u": _vector3_array(Vector3(projection.axis_u)), "axis_v": _vector3_array(Vector3(projection.axis_v)), "normal": _vector3_array(Vector3(context.get("reference_normal", Vector3.ZERO))), "polygon": polygon_points, "signed_area": float(realizer.call("_r2_polygon_signed_area", projection.polygon))},
		"patch_triangles": patch_rows,
		"owner_triangles": owner_rows,
		"root_positions": root_rows,
		"fixed_geometry_contract": {"cross_squared_strictly_greater_than": 1.0e-12, "topology_authority_unchanged": true, "zero_set_source": "R4_Candidate_D_materialized_binary32_volume"}
	}
	if String(fixture.boundary_signature) != R4CavitySignature or int(fixture.boundary_component_count) != 1 or fixture.boundary_cycles.size() != 1:
		return {"valid": false, "reason": "r6_frozen_cavity_signature_or_cycle_mismatch", "signature": fixture.boundary_signature, "components": fixture.boundary_component_count, "cycles": fixture.boundary_cycles.size()}
	return {"valid": true, "fixture": fixture}

func _sorted_keys(dictionary_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (dictionary_value is Dictionary): return result
	for key in dictionary_value.keys(): result.append(String(key))
	result.sort()
	return result

func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _vector2_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]
