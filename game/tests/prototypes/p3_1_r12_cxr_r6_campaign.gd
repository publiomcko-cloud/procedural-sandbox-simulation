extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd")
const R6Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_r6_realizer.gd")
const Synthesizer := preload("res://tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd")
const Diagnostics := preload("res://tests/prototypes/p3_1_r12_cxr_r6_diagnostics.gd")
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
	if mode.is_empty(): mode = "freeze"
	if mode not in ["freeze", "synthesize"]:
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
		var zero_inventory: Dictionary = diagnostics.call("collect_zero_facet_inventory", r6_realizer, volume.get("values", PackedFloat32Array()), roi)
		if not bool(zero_inventory.get("valid", false)):
			_fail("r6_zero_facet_inventory_failed", zero_inventory)
			return
		var projection: Dictionary = {"origin": _vector3_array(Vector3(r4_context.get("projection_origin", Vector3.ZERO))), "axis_u": _vector3_array(Vector3(r4_context.get("projection_u", Vector3.ZERO))), "axis_v": _vector3_array(Vector3(r4_context.get("projection_v", Vector3.ZERO)))}
		var cavity_search: Dictionary = diagnostics.call("search_patch_cavities", r6_realizer, triangles, analysis_patch_ids, root_positions, projection, zero_inventory.get("facets", []), {"max_faces": 12, "max_states": 10000, "max_queue": 2000, "max_ms": 30000})
		if String(cavity_search.get("status", "")) != "FOUND":
			var pregeometry: Dictionary = {"schema": "P3.1.R12CXR.R6.CavitySearch.v1", "status": cavity_search.get("status", "UNKNOWN_NOT_CAPTURED"), "terminal_reason": cavity_search.get("terminal_reason", cavity_search.get("reason", "UNKNOWN_NOT_CAPTURED")), "source_sha": source_sha, "attempt_id": attempt_id, "target_attempt_consumed": false, "initial_patch_ids": analysis_patch_ids, "limits": {"max_faces": 12, "max_states": 10000, "max_queue": 2000, "max_ms": 30000}, "search": cavity_search}
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

func _run_constraint_synthesis(realizer: RefCounted, values: PackedFloat32Array, roi: Dictionary, base_context: Dictionary, patch: Array[Dictionary], patch_ids: Array, seed_triangles: Array[Dictionary], boundary: Dictionary, original_triangles: Array[Dictionary], residual_fixture: Dictionary, base: Dictionary, snapshot: Dictionary, support_fixture: Dictionary, residual_triangles: Array, output_path: String, cavity_search: Dictionary) -> Dictionary:
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
	var synthesis: Dictionary = synthesizer.call("synthesize", realizer, values, roi, base_context, residual_triangles, cavity_id, residual_fixture.get("arc_map", []))
	if not bool(synthesis.get("valid", false)):
		_fail("r6_constraint_synthesis_input_invalid", synthesis)
		return {}
	var support_rows: Array[Dictionary] = synthesis.get("supports", [])
	var result: Dictionary = {
		"schema": "P3.1.R12CXR.R6.Result.v1",
		"status": "R6_SUPPORT_SYNTHESIS_PARTIAL",
		"source_sha": OS.get_environment("R12CXR_SOURCE_SHA"),
		"attempt_id": OS.get_environment("R12CXR_R6_ATTEMPT_ID"),
		"target_attempt_consumed": true,
		"cavity_search": cavity_search,
		"selected_patch_triangle_ids": patch_ids.duplicate(),
		"r4_source_sha": R4SourceSha,
		"r4_d1_result_sha256": R4D1ResultSha,
		"frozen_cavity_sha256": R5CavitySha,
		"candidate_d_sha256": CandidateSha,
		"manifest_sha256": ManifestSha,
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
	var maximum_total: int = int(realizer.call("_cxr_limits").get("max_candidate_triangles_total", 0))
	var graph_probe_cap: int = mini(maximum_triangles, maximum_total)
	var possible_triangle_count: int = int(vertex_ids.size() * maxi(0, vertex_ids.size() - 1) * maxi(0, vertex_ids.size() - 2) / 6)
	result["graph_gate"]["possible_triplets"] = possible_triangle_count
	result["graph_gate"]["probe_cap"] = graph_probe_cap
	if graph_probe_cap <= 0 or possible_triangle_count > graph_probe_cap:
		result["graph_gate"]["complete"] = false
		result["graph_gate"]["reason"] = "PREREGISTERED_R2_CANDIDATE_TRIANGLE_CAP_EXCEEDED"
		result["terminal_reason"] = "FINITE_GRAPH_GATE_PARTIAL"
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var candidate_triangles: Array[Dictionary] = []
	var rejection_histogram: Dictionary = {}
	var graph_probe_rows: Array[String] = []
	var graph_limited: bool = false
	var graph_limit_reason: String = ""
	var graph_started_usec: int = Time.get_ticks_usec()
	realizer.set("_cxr_candidate_triangles_total", 0)
	realizer.set("_cxr_candidate_triangles_cavity", 0)
	realizer.set("_cxr_search_nodes_total", 0)
	realizer.set("_cxr_search_nodes_cavity", 0)
	realizer.set("_cxr_search_started_usec", graph_started_usec)
	realizer.set("_cxr_cavity_started_usec", graph_started_usec)
	for first_index in range(vertex_ids.size()):
		for second_index in range(first_index + 1, vertex_ids.size()):
			for third_index in range(second_index + 1, vertex_ids.size()):
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
				if graph_probe_rows.size() >= graph_probe_cap:
					result["graph_gate"]["complete"] = graph_probe_rows.size() == possible_triangle_count
					break
			if graph_limited or graph_probe_rows.size() >= graph_probe_cap: break
		if graph_limited or graph_probe_rows.size() >= graph_probe_cap: break
	var graph_complete: bool = graph_probe_rows.size() == possible_triangle_count and not graph_limited
	var graph_summary: Dictionary = synthesizer.call("_candidate_graph_summary", candidate_triangles, context.get("candidate_edges", {}), context.get("support_by_id", {}))
	result["graph_gate"] = {
		"started": true,
		"complete": graph_complete,
		"vertex_count": vertex_ids.size(),
		"support_count": support_rows.size(),
		"possible_triplets": possible_triangle_count,
		"probed_triplets": graph_probe_rows.size(),
		"legal_triangle_count": candidate_triangles.size(),
		"rejection_histogram": rejection_histogram,
		"limit_reason": graph_limit_reason,
		"audit_sha256": Synthesizer.new().call("_candidate_graph_sha256", graph_probe_rows),
		"candidate_graph_summary": graph_summary,
		"supports_retained": support_rows.size(),
		"in_domain_supports": support_rows.size(),
		"legal_candidate_triangles": candidate_triangles.size(),
		"graph_gate_usec": Time.get_ticks_usec() - graph_started_usec,
		"preregistered_probe_cap": graph_probe_cap
	}
	if not graph_complete or candidate_triangles.is_empty():
		result["terminal_reason"] = "NO_LEGAL_TRIANGLES_IN_COMPLETE_FINITE_GRAPH" if graph_complete else "FINITE_GRAPH_GATE_PARTIAL"
		result["continuum_domain_exhausted"] = false
		_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
		return result
	var d3: Dictionary = realizer.call("_r2_search_level", context)
	d3["started"] = true
	result["d3"] = d3
	if not bool(d3.get("valid", false)):
		result["status"] = "R6_TRIANGULATION_PARTIAL" if not bool(d3.get("search_complete", false)) else "R6_SUPPORT_SYNTHESIS_PARTIAL"
		result["terminal_reason"] = String(d3.get("terminal_reason", "R2_SEARCH_PARTIAL")) if not bool(d3.get("search_complete", false)) else "NO_SOLUTION_ON_FINITE_SYNTHESIZED_SUPPORT_GRAPH"
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
	result["downstream"] = {"started": true, "final_patch_validation": final_validation, "topology_roundtrip": topology_roundtrip, "topology_complete": topology_pass, "mesh_complete": mesh_pass, "mesh_sha256": String(realizer.call("_mesh_sha", mesh)), "mesh_topology": topology, "minimum_cross_squared": minimum_cross_squared, "cutoff_rows": cutoff_rows, "required_arcs": obligations, "preserved_c6_paths": paths, "triangle_count": final_triangles.size(), "support_count": selected_supports.size()}
	result["status"] = "R6_EQUAL_LOD_PASS_DOWNSTREAM_PENDING" if mesh_pass else "R6_EQUAL_LOD_GATE_FAIL"
	result["terminal_reason"] = "equal_lod_gates_passed_downstream_required" if mesh_pass else "existing_topology_or_mesh_gate_failed"
	result["downstream"]["started"] = false
	result["downstream"]["reason"] = "SEPARATE_R6_Q_REQUIRED_AFTER_EQUAL_LOD_PASS" if mesh_pass else "NOT_RUN_EQUAL_LOD_GATE_FAILED"
	_write_result(output_path, result, "R12CXR_R6_SUPPORT_SYNTHESIS_RESULT")
	return result

func _write_result(output_path: String, result: Dictionary, marker: String) -> bool:
	if output_path.is_empty() or FileAccess.file_exists(output_path):
		_fail("r6_result_output_path_invalid_or_exists", {"path": output_path})
		return false
	var bytes: PackedByteArray = JSON.stringify(_json_safe(result), "\t", false).to_utf8_buffer()
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

func _json_safe(value: Variant) -> Variant:
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
