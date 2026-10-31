extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Authority := preload("res://tests/prototypes/p3_1_r10_a_topology_authority.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_c_c5_face_owned_realizer.gd")
const ManifestSha := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const CandidateSha := "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"
const FixtureSha := "33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d"
const TopologySha := "4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95"
const FixtureGraphFingerprintSha := "a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9"
const VolumeSha := "ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2"
const PayloadSha := "2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0"
const TARGET_ID := "R9.2.SEAM.XPLUS_EQUAL.v1"
const RAY_ID := "R9.2.RAY.CANONICAL_PICKER.v1"
const CONTROL_IDS: Array[String] = ["R9.2.GEO.ZERO.v1", "R9.2.GEO.CARVE.v1", "R9.2.GEO.FILL_CARVE.v1", "R9.2.CHUNK.NEIGHBOR_PAIR.v1"]
const NEGATIVE_ID := "R9.2.SEAM.NEGATIVE_REGIONS.v1"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var attempt_id: String = OS.get_environment("R12C_ATTEMPT_ID")
	var source_sha: String = OS.get_environment("R12C_SOURCE_SHA")
	var root: String = OS.get_environment("R12C_ARTIFACT_DIR")
	var fixture_path: String = OS.get_environment("R12C_FIXTURE_PATH")
	var expected_source: String = OS.get_environment("R12C_EXPECTED_CAMPAIGN_SHA256")
	var expected_realizer: String = OS.get_environment("R12C_EXPECTED_REALIZER_SHA256")
	if attempt_id.is_empty() or source_sha.length() != 40 or root.is_empty() or not DirAccess.dir_exists_absolute(root) or fixture_path.is_empty() or not FileAccess.file_exists(fixture_path):
		_fail("c5_preflight_environment_invalid", attempt_id, source_sha)
		return
	var fixture_bytes: PackedByteArray = FileAccess.get_file_as_bytes(fixture_path)
	var fixture_hash: String = Core.sha256(fixture_bytes)
	if fixture_hash != FixtureSha:
		_fail("c5_stage0_fixture_hash_mismatch", attempt_id, source_sha, {"observed": fixture_hash})
		return
	var campaign_file_sha: String = Core.sha256(FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r12_c_c5_campaign.gd"))
	var realizer_file_sha: String = Core.sha256(FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r12_c_c5_face_owned_realizer.gd"))
	if expected_source.is_empty() or expected_realizer.is_empty() or campaign_file_sha != expected_source or realizer_file_sha != expected_realizer:
		_fail("c5_executable_source_hash_mismatch", attempt_id, source_sha, {"campaign": campaign_file_sha, "realizer": realizer_file_sha})
		return
	var parsed_fixture: Variant = JSON.parse_string(fixture_bytes.get_string_from_utf8())
	if typeof(parsed_fixture) != TYPE_DICTIONARY:
		_fail("c5_fixture_json_invalid", attempt_id, source_sha)
		return
	var fixture: Dictionary = parsed_fixture
	if String(fixture.get("source_topology_sha256", "")) != TopologySha or String(fixture.get("schema", "")) != "P3.1.R12C.TopologyRealizationFixture.v1":
		_fail("c5_fixture_identity_invalid", attempt_id, source_sha)
		return
	var source_graph: Dictionary = fixture.get("topology_authority", {})
	var source_identity: Dictionary = Realizer.new().call("validate_topology_identity", source_graph, FixtureGraphFingerprintSha)
	if not bool(source_identity.get("valid", false)):
		_fail("c5_fixture_graph_fingerprint_mismatch", attempt_id, source_sha, source_identity)
		return
	var manifest: Dictionary = Core.load_manifest()
	if not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != ManifestSha:
		_fail("c5_manifest_invalid", attempt_id, source_sha, {"reason": manifest.get("reason", ""), "sha256": manifest.get("sha256", "")})
		return
	var target_row: Dictionary = Core.case_by_id(manifest.get("rows", []), TARGET_ID)
	if target_row.is_empty():
		_fail("c5_frozen_target_missing", attempt_id, source_sha)
		return
	if not _run_contract_preflight(source_graph, target_row.get("roi", {})):
		_fail("c5_realization_contract_preflight_failed", attempt_id, source_sha)
		return
	var target_prepared: Dictionary = _prepare_volume(target_row, null, target_row.get("roi", {}))
	if not bool(target_prepared.get("valid", false)):
		_fail("c5_target_volume_preflight_failed", attempt_id, source_sha, target_prepared)
		return
	var target_volume_gate: bool = bool(target_prepared.get("volume_identity_preserved", false)) and String(target_prepared.get("volume_sha256", "")) == VolumeSha and String(target_prepared.get("payload_sha256", "")) == PayloadSha and int(target_prepared.get("revision", -1)) == 2
	if not target_volume_gate:
		_fail("c5_target_volume_identity_preflight_failed", attempt_id, source_sha, {"volume_sha256": target_prepared.get("volume_sha256", ""), "payload_sha256": target_prepared.get("payload_sha256", ""), "revision": target_prepared.get("revision", -1), "volume_identity_preserved": target_prepared.get("volume_identity_preserved", false)})
		return
	var authority_graph_identity: Dictionary = _verify_reference_graph(target_row, target_prepared, source_graph)
	if not bool(authority_graph_identity.get("valid", false)):
		_fail("c5_reference_authority_reproduction_failed", attempt_id, source_sha, authority_graph_identity)
		return
	print("R12C_GEOMETRY_BEGIN " + JSON.stringify({"attempt_id": attempt_id, "source_sha": source_sha, "hypothesis": "C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH", "scenario_id": TARGET_ID, "fixture_sha256": fixture_hash}))
	var target_case: Dictionary = _build_case(target_row, target_row.get("roi", {}), null, source_graph, TopologySha, target_prepared, FixtureGraphFingerprintSha)
	var target_geometry: Dictionary = target_case.get("geometry", {})
	if not bool(target_case.get("valid", false)):
		target_geometry = target_case.get("detail", {"reason": target_case.get("reason", "target_geometry_unavailable")}).duplicate(true)
		target_geometry["geometry_complete"] = false
		target_geometry["topology_signature_match"] = false
		target_geometry["realizer_failure_reason"] = target_case.get("reason", "target_geometry_unavailable")
	var controls: Dictionary = _run_controls(manifest.get("rows", []))
	var ray_result: Dictionary = _run_ray_gate(manifest.get("rows", []))
	var volume_gate: bool = target_volume_gate
	var target_complete: bool = bool(target_geometry.get("geometry_complete", false)) and bool(target_geometry.get("topology_signature_match", false))
	var controls_pass: bool = bool(controls.get("valid", false)) and int(controls.get("passed", 0)) == 6 and int(controls.get("count", 0)) == 6
	var ray_pass: bool = bool(ray_result.get("valid", false)) and int(ray_result.get("roi_scoped_hit_miss_disagreements", -1)) == 0
	var status: String = "PASS" if target_complete and controls_pass and ray_pass and volume_gate else "FAILED_TARGET"
	var equal_lod_gates_pass: bool = target_complete and controls_pass and ray_pass and volume_gate
	var downstream_gate_state: String = "PENDING_SEPARATE_GATE" if equal_lod_gates_pass else "NOT_RUN_EQUAL_LOD_GATE_FAILED"
	var result: Dictionary = {
		"schema": "P3.1.R12C.C5GeometryAttempt.v1", "attempt_id": attempt_id, "source_sha": source_sha,
		"parent_sha": OS.get_environment("R12C_PARENT_SHA"), "tree_sha": OS.get_environment("R12C_TREE_SHA"),
		"hypothesis": "C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH", "result_class": status,
		"fixture_sha256": fixture_hash, "manifest_sha256": ManifestSha, "candidate_d_sha256": CandidateSha,
		"realizer_sha256": realizer_file_sha, "campaign_sha256": campaign_file_sha, "topology_sha256": TopologySha,
		"fixture_graph_fingerprint_sha256": FixtureGraphFingerprintSha, "reference_authority_reproduction": authority_graph_identity,
		"target": {"scenario_id": TARGET_ID, "volume_sha256": target_prepared.volume_sha256, "payload_sha256": target_prepared.payload_sha256, "revision": target_prepared.revision, "volume_identity_preserved": target_prepared.volume_identity_preserved, "volume_build_usec": target_prepared.volume_build_usec, "geometry_realizer_valid": target_case.get("valid", false)},
		"realization_map": {"root_count": target_geometry.get("anchor_root_count", -1), "arc_count": target_geometry.get("arc_map", []).size(), "face_count": target_geometry.get("face_map", []).size(), "anchor_count": target_geometry.get("anchor_root_count", -1), "path_event_count": target_geometry.get("path_event_root_count", -1), "support_vertex_count": target_geometry.get("support_vertex_count", -1), "path_count": target_geometry.get("realization_path_count", -1), "sha256": target_geometry.get("realization_map_sha256", ""), "topology_roundtrip_sha256": target_geometry.get("topology_roundtrip_sha256", ""), "topology_signature_match": target_geometry.get("topology_signature_match", false)},
		"geometry": {"error_contract": target_geometry.get("geometry_error_contract", "NOT_FULLY_MEASURED_NO_APPROVED_TOLERANCE"), "canonical_surface_deviation_measured": target_geometry.get("canonical_surface_deviation_measured", false), "maximum_diagonal_midpoint_displacement": target_geometry.get("maximum_diagonal_midpoint_displacement", null), "complete": target_geometry.get("geometry_complete", false), "mesh_sha256": target_geometry.get("mesh_sha256", ""), "vertex_count": target_geometry.get("geometry_vertex_count", -1), "triangle_count": target_geometry.get("geometry_triangle_count", -1), "initial_triangle_count": target_geometry.get("initial_triangle_count", -1), "initial_cutoff_rejections": target_geometry.get("initial_cutoff_rejections", []), "minimum_cross_squared": target_geometry.get("minimum_cross_squared", null), "cutoff_rejections": target_geometry.get("cutoff_rejections", []), "applied_flips": target_geometry.get("applied_flips", []), "rejected_flip_candidates": target_geometry.get("rejected_flip_candidates", []), "flip_cap": target_geometry.get("flip_cap", -1), "flip_cap_exhausted": target_geometry.get("flip_cap_exhausted", false), "missing_topology_obligations": target_geometry.get("missing_topology_obligations", []), "mesh_topology": target_geometry.get("mesh_topology", {}), "build_usec": target_geometry.get("build_usec", -1)},
		"scope": "EQUAL_LOD_EXPERIMENT_ONLY", "equal_lod_gates_pass": equal_lod_gates_pass,
		"controls": controls, "ray_roi": ray_result, "volume_gate": volume_gate, "mixed_lod": downstream_gate_state, "determinism": downstream_gate_state, "full_e2e": "NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE", "full_validation": "NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE",
		"failed_invariant": String(target_geometry.get("realizer_failure_reason", _first_failed_invariant(target_geometry, controls, ray_result, volume_gate))),
		"topology_map": {"roots": target_geometry.get("root_map", []), "arcs": target_geometry.get("arc_map", []), "faces": target_geometry.get("face_map", []), "supports": [], "flips": target_geometry.get("applied_flips", [])}
	}
	var output_path: String = root.path_join("r12c_C5_" + attempt_id + ".json")
	if FileAccess.file_exists(output_path):
		_fail("c5_output_overwrite_refused", attempt_id, source_sha, {"path": output_path})
		return
	var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		_fail("c5_output_open_failed", attempt_id, source_sha, {"path": output_path})
		return
	var output_bytes: PackedByteArray = JSON.stringify(result, "\t", false).to_utf8_buffer()
	output_file.store_buffer(output_bytes)
	output_file.flush()
	var write_error: Error = output_file.get_error()
	output_file.close()
	if write_error != OK:
		_fail("c5_output_write_failed", attempt_id, source_sha, {"error": write_error})
		return
	print("R12C_GEOMETRY_COMPLETE " + JSON.stringify({"attempt_id": attempt_id, "source_sha": source_sha, "hypothesis": "C5_FACE_OWNED_NONCOPLANAR_LOCAL_PATCH", "status": status, "fixture_sha256": fixture_hash, "result_sha256": Core.sha256(output_bytes), "result_path": output_path, "root_count": target_geometry.get("anchor_root_count", -1), "arc_count": target_geometry.get("arc_map", []).size(), "face_count": target_geometry.get("face_map", []).size(), "support_count": target_geometry.get("support_vertex_count", -1), "triangle_count": target_geometry.get("geometry_triangle_count", -1), "cutoff_rejections": target_geometry.get("cutoff_rejections", []).size(), "internal_open_edges": target_geometry.get("mesh_topology", {}).get("internal_open_edges", -1), "controls": controls_pass, "roi_ray_disagreements": ray_result.get("roi_scoped_hit_miss_disagreements", -1), "global_ray_disagreements_diagnostic": ray_result.get("global_diagnostic", {}).get("disagreements", -1), "volume": volume_gate, "failed_invariant": result.failed_invariant}))
	quit(0)

func _prepare_volume(row: Dictionary, snapshot_override: Variant, roi_override: Dictionary) -> Dictionary:
	var snapshot: Dictionary
	if snapshot_override is Dictionary and not snapshot_override.is_empty():
		snapshot = snapshot_override
	else:
		var snapshot_result: Dictionary = Core.make_snapshot(row)
		if not bool(snapshot_result.get("valid", false)): return {"valid": false, "reason": "snapshot_invalid", "detail": snapshot_result}
		snapshot = snapshot_result.snapshot
	var candidate: RefCounted = CandidateD.new()
	var roi: Dictionary = roi_override if not roi_override.is_empty() else row.get("roi", {})
	candidate.call("configure_roi", roi)
	var volume_case: Dictionary = candidate.call("build", snapshot, row, {"id": "R12C_C5"})
	if not bool(volume_case.get("valid", false)): return {"valid": false, "reason": "candidate_volume_invalid", "detail": volume_case}
	var volume: Dictionary = volume_case.get("volume", {})
	var values: PackedFloat32Array = volume.get("values", PackedFloat32Array())
	var metrics: Dictionary = volume_case.get("metrics", {})
	var volume_metrics: Dictionary = metrics.get("volume", {})
	return {"valid": true, "snapshot": snapshot, "values": values, "volume": volume, "volume_sha256": volume.get("sha256", ""), "payload_sha256": volume_metrics.get("payload_sha256", ""), "revision": volume.get("revision", -1), "volume_identity_preserved": bool(metrics.get("materialized_volume_identity_preserved", false)), "row": row, "roi": roi, "volume_build_usec": volume_metrics.get("materialize_usec", -1)}

func _build_case(row: Dictionary, roi: Dictionary, snapshot_override: Variant, supplied_graph: Dictionary = {}, expected_sha: String = "", prepared_override: Dictionary = {}, expected_graph_fingerprint_sha: String = "") -> Dictionary:
	var prepared: Dictionary = prepared_override if not prepared_override.is_empty() else _prepare_volume(row, snapshot_override, roi)
	if not bool(prepared.get("valid", false)): return prepared
	var volume: Dictionary = prepared.get("volume", {})
	var values: PackedFloat32Array = prepared.get("values", PackedFloat32Array())
	var graph: Dictionary = supplied_graph
	if graph.is_empty():
		var authority: RefCounted = Authority.new()
		authority.call("configure_roi", roi)
		var graph_result: Dictionary = authority.call("realize_topology", values, "R10A1_ALT_DIAGONAL_MAX_MIN_AREA", prepared.get("snapshot", {}), int(row.get("seed", 131102026)))
		var graph_wrapper: Dictionary = graph_result.get("topology_graph", {})
		graph = graph_wrapper.get("canonical", {})
		expected_sha = String(graph_wrapper.get("topology_sha256", ""))
		expected_graph_fingerprint_sha = Core.sha256(JSON.stringify(graph).to_utf8_buffer())
	if graph.is_empty() or expected_sha.is_empty(): return {"valid": false, "reason": "topology_graph_missing"}
	var geometry: Dictionary = Realizer.new().call("realize", graph, values, roi, expected_sha, expected_graph_fingerprint_sha)
	if not bool(geometry.get("valid", false)): return {"valid": false, "reason": "realizer_invalid", "detail": geometry}
	return {"valid": true, "geometry": geometry, "volume_sha256": prepared.get("volume_sha256", ""), "payload_sha256": prepared.get("payload_sha256", ""), "revision": prepared.get("revision", -1), "volume_identity_preserved": prepared.get("volume_identity_preserved", false), "snapshot": prepared.get("snapshot", {}), "values": values, "row": row, "roi": roi, "volume_build_usec": prepared.get("volume_build_usec", -1)}

func _run_contract_preflight(source_graph: Dictionary, roi: Dictionary) -> bool:
	var realizer: RefCounted = Realizer.new()
	if source_graph.get("roots", []).size() != 369 or source_graph.get("arcs", []).size() != 870 or source_graph.get("polygons", []).size() != 502: return false
	var mutated_graph: Dictionary = source_graph.duplicate(true)
	var roots: Array = mutated_graph.get("roots", [])
	if roots.is_empty(): return false
	roots[0][1] = float(roots[0][1]) + 0.125
	var mutated_identity: Dictionary = realizer.call("validate_topology_identity", mutated_graph, FixtureGraphFingerprintSha)
	if bool(mutated_identity.get("valid", true)) or String(mutated_identity.get("observed_sha256", "")) == FixtureGraphFingerprintSha: return false
	var test_values: PackedFloat32Array = PackedFloat32Array()
	var dims: Vector3i = Core.cell_counts(roi) + Vector3i.ONE
	test_values.resize(dims.x * dims.y * dims.z)
	var duplicate_root_graph: Dictionary = source_graph.duplicate(true)
	var duplicate_roots: Array = duplicate_root_graph.get("roots", [])
	duplicate_roots.append(duplicate_roots[0].duplicate(true))
	var duplicate_sha: String = Core.sha256(JSON.stringify(duplicate_root_graph).to_utf8_buffer())
	var duplicate_result: Dictionary = realizer.call("realize", duplicate_root_graph, test_values, roi, "R12C_TEST_TOPOLOGY_AUTHORITY", duplicate_sha)
	if bool(duplicate_result.get("valid", true)) or String(duplicate_result.get("reason", "")) != "c5_root_identity_or_coordinate_invalid": return false
	var malformed_arc_graph: Dictionary = source_graph.duplicate(true)
	var arcs: Array = malformed_arc_graph.get("arcs", [])
	if arcs.is_empty(): return false
	arcs[0][1][0] = "R12C_TEST_MISSING_ROOT"
	var malformed_sha: String = Core.sha256(JSON.stringify(malformed_arc_graph).to_utf8_buffer())
	var malformed_result: Dictionary = realizer.call("realize", malformed_arc_graph, test_values, roi, "R12C_TEST_TOPOLOGY_AUTHORITY", malformed_sha)
	if bool(malformed_result.get("valid", true)) or String(malformed_result.get("reason", "")) != "c5_arc_identity_or_endpoint_invalid": return false
	print("R12C_GEOMETRY_PREFLIGHT_PASS " + JSON.stringify({"source_graph_fingerprint_revalidated": true, "mutated_graph_rejected": true, "duplicate_root_rejected": true, "malformed_arc_endpoint_rejected": true}))
	return true

func _verify_reference_graph(row: Dictionary, prepared: Dictionary, fixture_graph: Dictionary) -> Dictionary:
	var authority: RefCounted = Authority.new()
	authority.call("configure_roi", row.get("roi", {}))
	var result: Dictionary = authority.call("realize_topology", prepared.get("values", PackedFloat32Array()), "R10A1_ALT_DIAGONAL_MAX_MIN_AREA", prepared.get("snapshot", {}), int(row.get("seed", 131102026)))
	var wrapper: Dictionary = result.get("topology_graph", {})
	var canonical: Dictionary = wrapper.get("canonical", {})
	var normalized_variant: Variant = JSON.parse_string(JSON.stringify(canonical))
	if typeof(normalized_variant) != TYPE_DICTIONARY: return {"valid": false, "reason": "authority_graph_json_roundtrip_invalid"}
	var normalized_graph: Dictionary = normalized_variant
	var same_graph: bool = _semantic_json_equal(normalized_graph, fixture_graph)
	var valid: bool = bool(result.get("valid", false)) and String(wrapper.get("topology_sha256", "")) == TopologySha and same_graph
	return {"valid": valid, "authority_valid": result.get("valid", false), "authority_topology_sha256": wrapper.get("topology_sha256", ""), "expected_topology_sha256": TopologySha, "fixture_graph_fingerprint_sha256": FixtureGraphFingerprintSha, "reproduced_authority_topology_sha256": Core.sha256(JSON.stringify(canonical).to_utf8_buffer()), "reproduced_parsed_graph_fingerprint_sha256": Core.sha256(JSON.stringify(normalized_graph).to_utf8_buffer()), "graph_semantic_match": same_graph, "first_graph_difference": {} if same_graph else _first_semantic_difference(normalized_graph, fixture_graph, "$"), "root_count": canonical.get("roots", []).size(), "arc_count": canonical.get("arcs", []).size(), "polygon_count": canonical.get("polygons", []).size()}

func _semantic_json_equal(left: Variant, right: Variant) -> bool:
	var left_type: int = typeof(left)
	var right_type: int = typeof(right)
	if left_type in [TYPE_INT, TYPE_FLOAT] and right_type in [TYPE_INT, TYPE_FLOAT]: return float(left) == float(right)
	if left_type != right_type: return false
	if left is Dictionary:
		if left.size() != right.size(): return false
		for key in left.keys():
			if not right.has(key) or not _semantic_json_equal(left[key], right[key]): return false
		return true
	if left is Array:
		if left.size() != right.size(): return false
		for index in range(left.size()):
			if not _semantic_json_equal(left[index], right[index]): return false
		return true
	return left == right

func _first_semantic_difference(left: Variant, right: Variant, path: String) -> Dictionary:
	var left_type: int = typeof(left)
	var right_type: int = typeof(right)
	if left_type in [TYPE_INT, TYPE_FLOAT] and right_type in [TYPE_INT, TYPE_FLOAT]:
		if float(left) == float(right): return {}
		return {"path": path, "left": left, "right": right, "left_type": left_type, "right_type": right_type}
	if left_type != right_type: return {"path": path, "left": left, "right": right, "left_type": left_type, "right_type": right_type}
	if left is Dictionary:
		if left.size() != right.size(): return {"path": path, "left_size": left.size(), "right_size": right.size()}
		for key in left.keys():
			if not right.has(key): return {"path": path + "." + String(key), "reason": "missing_right_key"}
			var difference: Dictionary = _first_semantic_difference(left[key], right[key], path + "." + String(key))
			if not difference.is_empty(): return difference
		for key in right.keys():
			if not left.has(key): return {"path": path + "." + String(key), "reason": "extra_right_key"}
		return {}
	if left is Array:
		if left.size() != right.size(): return {"path": path, "left_size": left.size(), "right_size": right.size()}
		for index in range(left.size()):
			var difference: Dictionary = _first_semantic_difference(left[index], right[index], path + "[" + str(index) + "]")
			if not difference.is_empty(): return difference
		return {}
	if left != right: return {"path": path, "left": left, "right": right, "left_type": left_type, "right_type": right_type}
	return {}

func _run_controls(rows: Array) -> Dictionary:
	var results: Array[Dictionary] = []
	for scenario_id in CONTROL_IDS:
		var row: Dictionary = Core.case_by_id(rows, scenario_id)
		if row.is_empty():
			results.append({"scenario_id": scenario_id, "pass": false, "reason": "frozen_control_missing"})
			continue
		var outcome: Dictionary = _build_case(row, row.get("roi", {}), null)
		results.append({"scenario_id": scenario_id, "pass": _case_geometry_pass(outcome), "result_class": "PASS" if _case_geometry_pass(outcome) else "FAIL", "reason": outcome.get("reason", ""), "failure_detail": outcome.get("detail", {}), "geometry": _geometry_summary(outcome.get("geometry", {})), "volume_identity_preserved": outcome.get("volume_identity_preserved", false)})
	var negative: Dictionary = Core.case_by_id(rows, NEGATIVE_ID)
	if negative.is_empty(): return {"passed": 0, "count": 6, "rows": results, "valid": false, "reason": "negative_roi_scenario_missing"}
	var negative_snapshot_result: Dictionary = Core.make_snapshot(negative)
	if not bool(negative_snapshot_result.get("valid", false)): return {"passed": 0, "count": 6, "rows": results, "valid": false, "reason": "negative_roi_snapshot_invalid", "detail": negative_snapshot_result}
	var variants: Array = negative.get("variants", [])
	if variants.size() != 2: return {"passed": 0, "count": 6, "rows": results, "valid": false, "reason": "negative_roi_variants_invalid", "variant_count": variants.size()}
	for variant in variants:
		var variant_roi: Dictionary = variant.get("roi", {})
		var outcome: Dictionary = _build_case(negative, variant_roi, negative_snapshot_result.get("snapshot", {}))
		var label: String = NEGATIVE_ID + "." + String(variant.get("id", ""))
		results.append({"scenario_id": label, "pass": _case_geometry_pass(outcome), "result_class": "PASS" if _case_geometry_pass(outcome) else "FAIL", "reason": outcome.get("reason", ""), "failure_detail": outcome.get("detail", {}), "geometry": _geometry_summary(outcome.get("geometry", {})), "volume_identity_preserved": outcome.get("volume_identity_preserved", false)})
	var passed: int = 0
	for row in results:
		if bool(row.get("pass", false)): passed += 1
	return {"valid": results.size() == 6, "passed": passed, "count": results.size(), "rows": results}

func _case_geometry_pass(outcome: Dictionary) -> bool:
	if not bool(outcome.get("valid", false)): return false
	var geometry: Dictionary = outcome.get("geometry", {})
	return bool(geometry.get("geometry_complete", false)) and bool(geometry.get("topology_signature_match", false)) and bool(outcome.get("volume_identity_preserved", false))

func _geometry_summary(geometry: Dictionary) -> Dictionary:
	return {"topology_signature_match": geometry.get("topology_signature_match", false), "geometry_complete": geometry.get("geometry_complete", false), "mesh_sha256": geometry.get("mesh_sha256", ""), "triangle_count": geometry.get("geometry_triangle_count", -1), "cutoff_rejections": geometry.get("cutoff_rejections", []).size(), "missing_obligations": geometry.get("missing_topology_obligations", []).size(), "mesh_topology": geometry.get("mesh_topology", {})}

func _run_ray_gate(rows: Array) -> Dictionary:
	var ray_row: Dictionary = Core.case_by_id(rows, RAY_ID)
	if ray_row.is_empty(): return {"valid": false, "reason": "frozen_ray_case_missing", "ray_count": 0, "roi_scoped_hit_miss_disagreements": -1}
	var built: Dictionary = _build_case(ray_row, ray_row.get("roi", {}), null)
	if not bool(built.get("valid", false)): return {"valid": false, "reason": "ray_candidate_setup_failed", "detail": built, "ray_count": 0, "roi_scoped_hit_miss_disagreements": -1}
	var snapshot: Dictionary = built.snapshot
	var geometry: Dictionary = built.geometry
	var rays: Array[Dictionary] = Core.ray_grid(ray_row.roi, ray_row.ray_grid)
	var roi_min: Vector3 = Core.world_min(ray_row.roi)
	var roi_max: Vector3 = roi_min + Vector3(Core.cell_counts(ray_row.roi)) * Core.step(ray_row.roi)
	var disagreements: int = 0
	var global_disagreements: int = 0
	var records: Array[Dictionary] = []
	for index in range(rays.size()):
		var ray: Dictionary = rays[index]
		var roots_result: Dictionary = Core.canonical_ray_roots(ray.origin, ray.direction, float(ray.length), snapshot, int(ray_row.get("seed", 131102026)), 256, 32)
		if not bool(roots_result.get("valid", false)): return {"valid": false, "reason": "canonical_ray_oracle_failed", "ray_index": index, "ray_count": rays.size(), "roi_scoped_hit_miss_disagreements": disagreements, "rays": records}
		var canonical_roi_hit: bool = false
		var canonical_global_hit: bool = not roots_result.get("roots", []).is_empty()
		for root in roots_result.get("roots", []):
			var point: Vector3 = root.get("position", Vector3.INF)
			if point.x >= roi_min.x - 1.0e-6 and point.x <= roi_max.x + 1.0e-6 and point.y >= roi_min.y - 1.0e-6 and point.y <= roi_max.y + 1.0e-6 and point.z >= roi_min.z - 1.0e-6 and point.z <= roi_max.z + 1.0e-6 and absf(point.y - roi_min.y) > 1.0e-6 and absf(point.y - roi_max.y) > 1.0e-6:
				canonical_roi_hit = true
		var hit: Dictionary = _first_mesh_hit(ray.origin, ray.direction, float(ray.length), geometry.get("mesh", Core.new_mesh()))
		var mesh_hit: bool = bool(hit.get("hit", false))
		var mismatch: bool = canonical_roi_hit != mesh_hit
		if mismatch: disagreements += 1
		if canonical_global_hit != mesh_hit: global_disagreements += 1
		records.append({"ray_index": index, "origin": [ray.origin.x, ray.origin.y, ray.origin.z], "direction": [ray.direction.x, ray.direction.y, ray.direction.z], "canonical_roi_hit": canonical_roi_hit, "canonical_global_hit_diagnostic": canonical_global_hit, "mesh_hit": mesh_hit, "mesh_hit_distance": hit.get("distance", null), "mesh_hit_position": hit.get("position", []), "triangle_index": hit.get("triangle_index", -1), "roi_disagreement": mismatch, "global_disagreement_diagnostic": canonical_global_hit != mesh_hit})
	return {"valid": rays.size() == 25, "ray_count": rays.size(), "roi_scoped_hit_miss_disagreements": disagreements, "global_diagnostic": {"disagreements": global_disagreements, "meaning": "diagnostic only; full-field canonical hit compared with ROI mesh hit"}, "scope": "closed ROI with 1e-6 bounds tolerance; cropped Y face roots excluded", "completeness": "finite 256-step sign-change scan plus 32 bisections; tangent roots can be missed", "rays": records}

func _first_mesh_hit(origin: Vector3, direction: Vector3, max_distance: float, mesh: Dictionary) -> Dictionary:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var best: float = INF
	var best_index: int = -1
	for index in range(0, positions.size(), 3):
		var distance: float = _ray_triangle(origin, direction, positions[index], positions[index + 1], positions[index + 2])
		if distance >= 0.0 and distance <= max_distance and distance < best:
			best = distance
			best_index = int(index / 3)
	if best_index < 0: return {"hit": false}
	var point: Vector3 = origin + direction * best
	return {"hit": true, "distance": best, "position": [point.x, point.y, point.z], "triangle_index": best_index}

func _ray_triangle(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var edge1: Vector3 = b - a
	var edge2: Vector3 = c - a
	var h: Vector3 = direction.cross(edge2)
	var determinant: float = edge1.dot(h)
	if absf(determinant) < 1.0e-10: return -1.0
	var inverse: float = 1.0 / determinant
	var s: Vector3 = origin - a
	var u: float = inverse * s.dot(h)
	if u < 0.0 or u > 1.0: return -1.0
	var q: Vector3 = s.cross(edge1)
	var v: float = inverse * direction.dot(q)
	if v < 0.0 or u + v > 1.0: return -1.0
	var distance: float = inverse * edge2.dot(q)
	return distance if distance >= 0.0 else -1.0

func _first_failed_invariant(geometry: Dictionary, controls: Dictionary, rays: Dictionary, volume_gate: bool) -> String:
	if not bool(geometry.get("topology_signature_match", false)): return "topology_roundtrip"
	if not bool(geometry.get("finite_geometry", false)): return "finite_geometry"
	if bool(geometry.get("flip_cap_exhausted", false)): return "bounded_flip_cap"
	if not geometry.get("cutoff_rejections", []).is_empty(): return "fixed_cutoff"
	if not geometry.get("missing_topology_obligations", []).is_empty(): return "required_arc_incidence"
	if int(geometry.get("mesh_topology", {}).get("internal_open_edges", -1)) != 0: return "internal_open_edges"
	if int(geometry.get("mesh_topology", {}).get("nonmanifold_edges", -1)) != 0: return "nonmanifold"
	if int(geometry.get("mesh_topology", {}).get("winding_inconsistencies", -1)) != 0: return "winding"
	if int(controls.get("passed", -1)) != 6: return "controls"
	if int(rays.get("roi_scoped_hit_miss_disagreements", -1)) != 0: return "roi_ray_parity"
	if not volume_gate: return "volume_identity"
	return ""

func _fail(reason: String, attempt_id: String, source_sha: String, details: Dictionary = {}) -> void:
	print("R12C_GEOMETRY_COMPLETE " + JSON.stringify({"attempt_id": attempt_id, "source_sha": source_sha, "status": "BLOCKED", "reason": reason, "details": details}))
	quit(2)
