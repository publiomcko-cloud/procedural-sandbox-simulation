extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Authority := preload("res://tests/prototypes/p3_1_r10_a_topology_authority.gd")
const B1Realizer := preload("res://tests/prototypes/p3_1_r10_b_realizer.gd")
const B6Realizer := preload("res://tests/prototypes/p3_1_r10_b6_area_guided_realizer.gd")
const B1RRealizer := preload("res://tests/prototypes/p3_1_r10_b1r_direct_triangulator.gd")
const B2Realizer := preload("res://tests/prototypes/p3_1_r10_b2_realizer.gd")
const B3Realizer := preload("res://tests/prototypes/p3_1_r10_b3_realizer.gd")
const MANIFEST_SHA := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const CANDIDATE_D_SHA := "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"
const RAY_FIXTURE_SHA := "9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7"
const A6_COMPONENT := "60,8,25|tet:0"
const A6_VOLUME_SHA := "ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2"
const A6_PAYLOAD_SHA := "2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0"
const CUTOFF_SQUARED: float = 1.0e-12
const CONTROL_IDS: Array[String] = ["R9.2.GEO.ZERO.v1", "R9.2.GEO.CARVE.v1", "R9.2.GEO.FILL_CARVE.v1", "R9.2.CHUNK.NEIGHBOR_PAIR.v1"]
const NEGATIVE_ID := "R9.2.SEAM.NEGATIVE_REGIONS.v1"
const EQUAL_ID := "R9.2.SEAM.XPLUS_EQUAL.v1"
const RAY_ID := "R9.2.RAY.CANONICAL_PICKER.v1"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var attempt_id: String = OS.get_environment("R10B_ATTEMPT")
	var hypothesis: String = OS.get_environment("R10B_HYPOTHESIS")
	var source_sha: String = OS.get_environment("R10B_SOURCE_SHA")
	var artifact_root: String = OS.get_environment("R10B_ARTIFACT_DIR")
	var repo_root: String = OS.get_environment("R10B_REPO_ROOT")
	var campaign_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r10_b_campaign.gd")
	var realizer_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r10_b_realizer.gd")
	var b1r_realizer_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r10_b1r_direct_triangulator.gd")
	var ray_source_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r10_b_ray_causality.gd")
	var manifest: Dictionary = Core.load_manifest()
	var candidate_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
	var ray_fixture_sha: String = _sha_absolute(repo_root.path_join("docs/reports/P3-1-R10-B-CAMPAIGN/fixtures/ray_reference_fixture_r2.json")) if not repo_root.is_empty() else ""
	if attempt_id.is_empty() or hypothesis.is_empty() or source_sha.length() != 40 or not source_sha.is_valid_hex_number() or not DirAccess.dir_exists_absolute(artifact_root):
		_blocked("attempt_identity_or_artifact_root_invalid", {})
		return
	if campaign_sha != OS.get_environment("R10B_CAMPAIGN_SOURCE_SHA256") or realizer_sha != OS.get_environment("R10B_REALIZER_SOURCE_SHA256") or b1r_realizer_sha != OS.get_environment("R10B_B1R_REALIZER_SOURCE_SHA256") or ray_source_sha != OS.get_environment("R10B_RAY_SOURCE_SHA256"):
		_blocked("experimental_source_physical_hash_mismatch", {"campaign": campaign_sha, "realizer": realizer_sha, "b1r_realizer": b1r_realizer_sha, "ray": ray_source_sha})
		return
	if not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != MANIFEST_SHA or candidate_sha != CANDIDATE_D_SHA or ray_fixture_sha != RAY_FIXTURE_SHA:
		_blocked("frozen_input_identity_invalid", {"manifest": manifest.get("sha256", ""), "candidate_d": candidate_sha, "ray_fixture": ray_fixture_sha})
		return
	var authority_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r10_a_topology_authority.gd")
	if authority_sha != "feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216":
		_blocked("r10a_authority_physical_hash_mismatch", {"authority": authority_sha})
		return
	print("R10B_PREFLIGHT " + JSON.stringify({"attempt_id": attempt_id, "hypothesis": hypothesis, "source_sha": source_sha, "campaign_sha256": campaign_sha, "realizer_sha256": realizer_sha, "b1r_realizer_sha256": b1r_realizer_sha, "ray_source_sha256": ray_source_sha, "candidate_d_sha256": candidate_sha, "manifest_sha256": manifest.sha256, "ray_fixture_sha256": ray_fixture_sha, "r10a_authority_sha256": authority_sha, "godot": Engine.get_version_info(), "cutoff_squared": 1.0e-12}))
	var row: Dictionary = Core.case_by_id(manifest.get("rows", []), EQUAL_ID)
	if row.is_empty():
		_blocked("frozen_equal_lod_case_missing", {})
		return
	var setup: Dictionary = Core.make_snapshot(row)
	if not bool(setup.get("valid", false)):
		_blocked("frozen_equal_lod_snapshot_invalid", {"detail": setup})
		return
	var volume_case: Dictionary = _build_volume(row, row.roi, setup.snapshot)
	if not bool(volume_case.get("valid", false)):
		_blocked("candidate_d_volume_preflight_failed", {"detail": volume_case})
		return
	var values: PackedFloat32Array = volume_case.volume.values
	var authority: RefCounted = Authority.new()
	authority.call("configure_roi", row.roi)
	var graph_result: Dictionary = authority.call("realize_topology", values, "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION", setup.snapshot, int(row.get("seed", 131102026)))
	if not bool(graph_result.get("source_topology_graph_proof", {}).get("valid", false)) or int(graph_result.get("source_topology_graph_proof", {}).get("root_count", -1)) != 369 or int(graph_result.get("source_topology_graph_proof", {}).get("polygon_count", -1)) != 502 or int(graph_result.get("source_topology_graph_proof", {}).get("arc_count", -1)) != 870:
		_blocked("stage0_source_topology_graph_mismatch", {"proof": graph_result.get("source_topology_graph_proof", {})})
		return
	if OS.get_environment("R10B_GRAPH_ONLY") == "1":
		print("R10B_GRAPH_CONTRACT_COMPLETE " + JSON.stringify({"status": "PASS", "attempt_id": attempt_id, "source_sha": source_sha, "source_topology_graph_proof": graph_result.source_topology_graph_proof, "geometry_topology": graph_result.mesh_topology, "volume_identity_preserved": volume_case.volume_identity_preserved}))
		quit(0)
		return
	if OS.get_environment("R10B_B1R_DOMAIN_ONLY") == "1":
		if hypothesis != "R10B1R_DIRECT_CONSTRAINED_TRIANGULATION":
			_blocked("candidate_domain_stage_requires_b1r", {"hypothesis": hypothesis})
			return
		var domain_builder: RefCounted = B1RRealizer.new()
		var domain_result: Dictionary = domain_builder.call("build_candidate_domain", graph_result, _b1r_identity(source_sha, b1r_realizer_sha, volume_case, graph_result, row.roi), row.roi)
		if not bool(domain_result.get("valid", false)):
			_blocked("b1r_candidate_domain_audit_failed", domain_result)
			return
		var domain_self_test: Dictionary = _audit_b1r_domain(domain_result.domain, _b1r_identity(source_sha, b1r_realizer_sha, volume_case, graph_result, row.roi))
		if not bool(domain_self_test.get("valid", false)):
			_blocked("b1r_candidate_domain_self_test_failed", domain_self_test)
			return
		var domain_path: String = artifact_root.path_join("b1r_candidate_domain.json")
		if FileAccess.file_exists(domain_path):
			_blocked("b1r_candidate_domain_would_overwrite", {"path": domain_path})
			return
		var domain_file: FileAccess = FileAccess.open(domain_path, FileAccess.WRITE)
		if domain_file == null:
			_blocked("b1r_candidate_domain_open_failed", {"path": domain_path, "error": FileAccess.get_open_error()})
			return
		domain_file.store_buffer(domain_result.domain_bytes)
		domain_file.flush()
		var domain_error: Error = domain_file.get_error()
		domain_file.close()
		if domain_error != OK or _sha_absolute(domain_path) != String(domain_result.domain_sha256):
			_blocked("b1r_candidate_domain_write_integrity_failed", {"path": domain_path, "error": domain_error})
			return
		print("R10B_B1R_DOMAIN_COMPLETE " + JSON.stringify({"status": "PASS", "attempt_id": attempt_id, "source_sha": source_sha, "domain_artifact": domain_path, "domain_sha256": domain_result.domain_sha256, "domain_identity_sha256": domain_result.identity_sha256, "self_test": domain_self_test, "metrics": domain_result.metrics, "source_topology_graph_proof": graph_result.source_topology_graph_proof}))
		quit(0)
		return
	if hypothesis not in ["R10B1_NONMONOTONIC_CONSTRAINED_FLIP_BFS", "R10B1R_DIRECT_CONSTRAINED_TRIANGULATION", "R10B2_EXPANDING_LOCAL_CAVITY_EXACT_RETRIANGULATION", "R10B3_CONSTRAINED_DELAUNAY_LAWSON_FLIPS", "R10B4_CANONICAL_FIELD_STEINER_SUBDIVISION", "R10B5_NESTED_LOCAL_FIELD_REFINEMENT", "R10B6_CUTOFF_DIRECTED_BOUNDED_BEAM"]:
		_blocked("unimplemented_geometry_hypothesis", {"hypothesis": hypothesis})
		return
	var solve_started: int = Time.get_ticks_usec()
	var realization_mode: String = _realization_mode(hypothesis)
	var refinement_result: Dictionary = {}
	var b1r_result: Dictionary = {}
	var geometry: Dictionary = {}
	if hypothesis == "R10B1R_DIRECT_CONSTRAINED_TRIANGULATION":
		var domain_loaded: Dictionary = _load_b1r_domain(volume_case, graph_result, source_sha, b1r_realizer_sha, row.roi)
		if not bool(domain_loaded.get("valid", false)):
			_blocked("b1r_domain_integrity_or_identity_failed", domain_loaded)
			return
		var direct_solver: RefCounted = B1RRealizer.new()
		b1r_result = direct_solver.call("solve_domain", domain_loaded.domain, _b1r_identity(source_sha, b1r_realizer_sha, volume_case, graph_result, row.roi))
		b1r_result["candidate_domain"] = {"path": domain_loaded.path, "sha256": domain_loaded.sha256, "identity_sha256": domain_loaded.identity_sha256}
		if bool(b1r_result.get("valid", false)):
			var repeated_solver: RefCounted = B1RRealizer.new()
			var repeated: Dictionary = repeated_solver.call("solve_domain", domain_loaded.domain, _b1r_identity(source_sha, b1r_realizer_sha, volume_case, graph_result, row.roi))
			b1r_result["deterministic_repeat"] = bool(repeated.get("valid", false)) and JSON.stringify(repeated.get("triangles", [])) == JSON.stringify(b1r_result.get("triangles", []))
			b1r_result["repeat_nodes"] = repeated.get("nodes", -1)
			b1r_result["repeat_elapsed_milliseconds"] = repeated.get("elapsed_milliseconds", -1)
			var replacement: Dictionary = _replace_target_patch_geometry(graph_result, domain_loaded.domain, b1r_result, row.roi)
			if bool(replacement.get("valid", false)):
				geometry = replacement
			else:
				geometry = graph_result.duplicate(true)
				geometry["geometry_realization_complete"] = false
				b1r_result["geometry_assembly_failure"] = replacement
		else:
			geometry = graph_result.duplicate(true)
			geometry["geometry_realization_complete"] = false
			geometry["b1r_direct"] = b1r_result
	else:
		if hypothesis == "R10B5_NESTED_LOCAL_FIELD_REFINEMENT":
			refinement_result = _run_b5_nested_field_refinement(row, setup.snapshot, volume_case, graph_result)
			if not bool(refinement_result.get("valid", false)):
				_blocked("b5_derived_field_precondition_failed", refinement_result)
				return
			geometry = refinement_result.geometry
		else:
			var hypothesis_realizer: RefCounted = _new_hypothesis_realizer(hypothesis)
			hypothesis_realizer.call("configure_roi", row.roi)
			geometry = hypothesis_realizer.call("realize_topology", values, realization_mode, setup.snapshot, int(row.get("seed", 131102026)))
	var solve_usec: int = Time.get_ticks_usec() - solve_started
	var patch: Dictionary = _find_patch(geometry)
	if patch.is_empty() and hypothesis not in ["R10B4_CANONICAL_FIELD_STEINER_SUBDIVISION", "R10B5_NESTED_LOCAL_FIELD_REFINEMENT"]:
		_blocked("b1_target_component_record_missing", {"component_reconstruction": geometry.get("component_reconstruction", {})})
		return
	var search: Dictionary = b1r_result if hypothesis == "R10B1R_DIRECT_CONSTRAINED_TRIANGULATION" else (patch.get("triangulation", {}).get("search", {}) if not patch.is_empty() else ({"status": "NESTED_FIELD_REFINEMENT_WITHOUT_ROOT_FLIP_SEARCH", "search_exhausted": false} if hypothesis == "R10B5_NESTED_LOCAL_FIELD_REFINEMENT" else {"status": "FIELD_STEINER_EVIDENCE_ONLY", "search_exhausted": false}))
	var target_topology: Dictionary = geometry.get("mesh_topology", {})
	var ray_case: Dictionary = _run_frozen_ray_case(manifest.get("rows", []))
	var ray_result: Dictionary = ray_case.get("rays", {})
	ray_result["candidate_geometry_complete"] = bool(ray_case.get("geometry_complete", false))
	ray_result["candidate_mesh_sha256"] = String(ray_case.get("mesh_sha256", ""))
	ray_result["candidate_volume_sha256"] = String(ray_case.get("volume_sha256", ""))
	var controls: Dictionary = _run_controls(manifest.get("rows", []), setup.snapshot)
	var volume_gate: bool = bool(volume_case.volume_identity_preserved) and String(volume_case.volume.sha256) == A6_VOLUME_SHA and String(volume_case.volume.metrics.payload_sha256) == A6_PAYLOAD_SHA and int(volume_case.volume.revision) == 2
	if hypothesis == "R10B5_NESTED_LOCAL_FIELD_REFINEMENT": volume_gate = volume_gate and bool(refinement_result.get("derived_volume_integrity_preserved", false))
	var equal_gate: bool = bool(geometry.get("geometry_realization_complete", false)) and int(target_topology.get("internal_open_edges", -1)) == 0 and int(target_topology.get("nonmanifold_edges", -1)) == 0 and int(target_topology.get("degenerate_triangles", -1)) == 0 and int(target_topology.get("winding_inconsistencies", -1)) == 0 and int(geometry.get("required_adjacency_missing_count", -1)) == 0 and int(geometry.get("required_adjacency_nonmanifold_count", -1)) == 0 and geometry.get("cutoff_rejections", []).is_empty()
	if hypothesis == "R10B1R_DIRECT_CONSTRAINED_TRIANGULATION": equal_gate = equal_gate and bool(b1r_result.get("valid", false)) and bool(b1r_result.get("deterministic_repeat", false))
	if hypothesis == "R10B5_NESTED_LOCAL_FIELD_REFINEMENT": equal_gate = equal_gate and bool(refinement_result.get("valid", false)) and bool(refinement_result.get("nested_sample_values_bitwise_equal", false)) and bool(refinement_result.get("all_six_outer_contours_match", false))
	var ray_gate: bool = bool(ray_case.get("valid", false)) and bool(ray_result.get("valid", false)) and bool(ray_case.get("geometry_complete", false)) and int(ray_result.get("roi_scoped_hit_miss_disagreements", -1)) == 0
	var mixed_gate: Dictionary = {"status": "SKIPPED_EQUAL_LOD_OR_RAY_GATE_FAILED", "conforming": false}
	if equal_gate and ray_gate:
		mixed_gate = _run_mixed_lod_gate(manifest.get("rows", []), hypothesis)
	var controls_pass: int = int(controls.get("passed", 0))
	var search_status: String = String(search.get("status", ""))
	var incomplete_search: bool = search_status in ["EXACT_ROOT_REALIZATION_INCONCLUSIVE", "INCOMPLETE_LIMIT"]
	var status: String = "PASS" if equal_gate and ray_gate and bool(mixed_gate.get("conforming", false)) and controls_pass == 6 and volume_gate else ("PARTIAL" if incomplete_search else ("FAILED_WITH_REGRESSION" if ray_result.get("roi_scoped_hit_miss_disagreements", 0) > 0 and ray_result.get("ray_count", 0) == 25 else "FAILED_TARGET"))
	var result: Dictionary = {
		"schema": "P3.1.R10B.GeometryAttempt.v1", "attempt_id": attempt_id, "hypothesis": hypothesis, "source_sha": source_sha,
		"source_physical_sha256": {"campaign": campaign_sha, "realizer": realizer_sha, "b1r_realizer": b1r_realizer_sha, "r10a_authority": authority_sha, "candidate_d": candidate_sha, "manifest": MANIFEST_SHA, "ray_fixture": ray_fixture_sha},
		"godot": Engine.get_version_info(), "cutoff_squared": 1.0e-12,
		"target": {"scenario_id": EQUAL_ID, "volume_sha256": volume_case.volume.sha256, "payload_sha256": volume_case.volume.metrics.payload_sha256, "revision": volume_case.volume.revision, "volume_identity_preserved": volume_gate},
		"source_topology": geometry.get("source_topology_graph_proof", {}),
		"b1_search": search, "realization_search": search, "b1r_candidate_domain": b1r_result.get("candidate_domain", {}), "b1r_direct": b1r_result, "field_steiner_evidence": geometry.get("local_refinement", []), "nested_field_refinement": refinement_result, "equal_lod": {"complete": equal_gate, "realization_complete": geometry.get("geometry_realization_complete", false), "mesh_sha256": geometry.get("mesh_sha256", ""), "metrics": target_topology, "required_adjacency_missing_count": geometry.get("required_adjacency_missing_count", -1), "required_adjacency_nonmanifold_count": geometry.get("required_adjacency_nonmanifold_count", -1), "cutoff_rejection_count": geometry.get("cutoff_rejections", []).size(), "unresolved_obligations": geometry.get("unresolved_obligations", []), "patch": patch},
		"ray_gate": ray_result, "controls": controls, "mixed_lod": mixed_gate,
		"ray_candidate": ray_case,
		"volume_gate": volume_gate, "solver_elapsed_usec": solve_usec, "failures": _failures, "result": status
	}
	var write: Dictionary = _write_json(artifact_root.path_join(attempt_id + "_attempt.json"), result)
	if not bool(write.get("valid", false)):
		_failures.append("attempt_artifact_write_failed:" + String(write.get("reason", "unknown")))
		result.result = "FAILED_EVIDENCE"
	print("R10B_ATTEMPT_COMPLETE " + JSON.stringify({"attempt_id": attempt_id, "hypothesis": hypothesis, "source_sha": source_sha, "result": result.result, "equal_lod_complete": equal_gate, "internal_open_edges": target_topology.get("internal_open_edges", -1), "missing_adjacencies": geometry.get("required_adjacency_missing_count", -1), "nonmanifold": target_topology.get("nonmanifold_edges", -1), "winding_inconsistencies": target_topology.get("winding_inconsistencies", -1), "cutoff_rejections": geometry.get("cutoff_rejections", []).size(), "ray_roi_disagreements": ray_result.get("roi_scoped_hit_miss_disagreements", -1), "ray_roi_count": ray_result.get("ray_count", -1), "controls": "%d/6" % controls_pass, "volume_identity_preserved": volume_gate, "artifact": write.get("path", ""), "failures": _failures}))
	quit(0 if _failures.is_empty() else 3)

func _new_hypothesis_realizer(hypothesis: String) -> RefCounted:
	if hypothesis == "R10B2_EXPANDING_LOCAL_CAVITY_EXACT_RETRIANGULATION": return B2Realizer.new()
	if hypothesis == "R10B3_CONSTRAINED_DELAUNAY_LAWSON_FLIPS": return B3Realizer.new()
	if hypothesis == "R10B6_CUTOFF_DIRECTED_BOUNDED_BEAM": return B6Realizer.new()
	if hypothesis == "R10B4_CANONICAL_FIELD_STEINER_SUBDIVISION": return Authority.new()
	return B1Realizer.new()

func _realization_mode(hypothesis: String) -> String:
	if hypothesis == "R10B4_CANONICAL_FIELD_STEINER_SUBDIVISION": return "R10A3_CANONICAL_FIELD_STEINER"
	return "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"

func _run_frozen_ray_case(rows: Array) -> Dictionary:
	var ray_row: Dictionary = Core.case_by_id(rows, RAY_ID)
	if ray_row.is_empty(): return {"valid": false, "reason": "frozen_ray_scenario_missing", "rays": {"valid": false, "reason": "frozen_ray_scenario_missing"}}
	var setup: Dictionary = Core.make_snapshot(ray_row)
	if not bool(setup.get("valid", false)): return {"valid": false, "reason": "frozen_ray_snapshot_invalid", "rays": {"valid": false, "reason": "frozen_ray_snapshot_invalid"}}
	var volume_case: Dictionary = _build_volume(ray_row, ray_row.roi, setup.snapshot)
	if not bool(volume_case.get("valid", false)): return {"valid": false, "reason": "frozen_ray_volume_invalid", "volume_reason": volume_case.get("reason", ""), "rays": {"valid": false, "reason": "frozen_ray_volume_invalid"}}
	var authority: RefCounted = Authority.new()
	authority.call("configure_roi", ray_row.roi)
	var geometry: Dictionary = authority.call("realize_topology", volume_case.volume.values, "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION", setup.snapshot, int(ray_row.get("seed", 131102026)))
	var rays: Dictionary = _run_roi_rays(ray_row, setup.snapshot, geometry.get("mesh", Core.new_mesh()), geometry.get("emitted_triangles", []))
	return {"valid": bool(volume_case.get("volume_identity_preserved", false)) and bool(geometry.get("valid", false)), "reason": "" if bool(geometry.get("valid", false)) else String(geometry.get("reason", "ray_candidate_mesh_invalid")), "scenario_id": RAY_ID, "mesh_sha256": geometry.get("mesh_sha256", ""), "volume_sha256": volume_case.volume.sha256, "geometry_complete": geometry.get("geometry_realization_complete", false), "mesh_topology": geometry.get("mesh_topology", {}), "volume_identity_preserved": volume_case.volume_identity_preserved, "rays": rays}

func _build_volume(row: Dictionary, roi: Dictionary, snapshot: Dictionary) -> Dictionary:
	var candidate: RefCounted = CandidateD.new()
	candidate.call("configure_roi", roi)
	var built: Dictionary = candidate.call("build", snapshot, row, {"id": "R10B_FROZEN_VOLUME", "roi": roi})
	if not bool(built.get("valid", false)): return {"valid": false, "reason": "candidate_d_build_failed", "detail": built.get("reason", "unknown")}
	var volume: Dictionary = built.get("volume", {})
	var metrics: Dictionary = built.get("metrics", {}).get("volume", {})
	var integrity: bool = String(volume.get("sha256", "")) == Core.sha256(volume.get("bytes", PackedByteArray())) and String(volume.get("sha256", "")) == String(built.get("metrics", {}).get("persisted_reloaded_volume_sha256", ""))
	return {"valid": integrity, "reason": "" if integrity else "volume_reload_integrity_failed", "volume": volume, "metrics": metrics, "volume_identity_preserved": integrity}

func _find_patch(geometry: Dictionary) -> Dictionary:
	for raw_patch in geometry.get("component_reconstruction", {}).get("patches", []):
		var patch: Dictionary = raw_patch
		if String(patch.get("component_id", "")) == A6_COMPONENT: return patch
	return {}

func _b1r_identity(source_sha: String, b1r_realizer_sha: String, volume_case: Dictionary, geometry: Dictionary, roi: Dictionary) -> Dictionary:
	var config: RefCounted = CandidateD.new()
	config.call("configure_roi", roi)
	var roi_min: Vector3 = config.get("ROI_MIN")
	var cells: Vector3i = config.get("CELLS")
	var grid_step: float = float(config.get("STEP"))
	return {
		"source_sha": source_sha,
		"b1r_realizer_sha256": b1r_realizer_sha,
		"candidate_d_sha256": CANDIDATE_D_SHA,
		"manifest_sha256": MANIFEST_SHA,
		"volume_sha256": String(volume_case.get("volume", {}).get("sha256", "")),
		"payload_sha256": String(volume_case.get("volume", {}).get("metrics", {}).get("payload_sha256", "")),
		"revision": int(volume_case.get("volume", {}).get("revision", -1)),
		"source_topology_sha256": String(geometry.get("source_topology_graph_proof", {}).get("topology_sha256", "")),
		"component_id": A6_COMPONENT,
		"cross_squared_cutoff": CUTOFF_SQUARED,
		"roi_id": String(roi.get("id", "")),
		"roi_min": [roi_min.x, roi_min.y, roi_min.z],
		"roi_cells": [cells.x, cells.y, cells.z],
		"grid_step": grid_step
	}

func _load_b1r_domain(volume_case: Dictionary, geometry: Dictionary, source_sha: String, b1r_realizer_sha: String, roi: Dictionary) -> Dictionary:
	var path: String = OS.get_environment("R10B_B1R_DOMAIN_PATH")
	var expected_sha: String = OS.get_environment("R10B_B1R_DOMAIN_SHA256")
	if path.is_empty() or expected_sha.length() != 64 or not FileAccess.file_exists(path):
		return {"valid": false, "reason": "candidate_domain_path_or_pin_missing"}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var actual_sha: String = Core.sha256(bytes)
	if actual_sha != expected_sha: return {"valid": false, "reason": "candidate_domain_physical_hash_mismatch", "expected": expected_sha, "actual": actual_sha}
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(bytes.get_string_from_utf8())
	if parse_error != OK or not parser.data is Dictionary: return {"valid": false, "reason": "candidate_domain_json_invalid", "line": parser.get_error_line(), "message": parser.get_error_message()}
	var domain: Dictionary = parser.data
	var identity: Dictionary = _b1r_identity(source_sha, b1r_realizer_sha, volume_case, geometry, roi)
	if domain.get("identity", {}) != identity: return {"valid": false, "reason": "candidate_domain_identity_not_bound_to_current_run", "expected": identity, "observed": domain.get("identity", {})}
	return {"valid": true, "domain": domain, "path": path, "sha256": actual_sha, "identity_sha256": String(B1RRealizer.new().call("_domain_identity_sha", domain))}

func _audit_b1r_domain(domain: Dictionary, identity: Dictionary) -> Dictionary:
	var verifier: RefCounted = B1RRealizer.new()
	var positive: Dictionary = verifier.call("_load_solver_domain", domain, identity)
	if not bool(positive.get("valid", false)):
		return {"valid": false, "reason": "valid_domain_rejected", "detail": positive}
	var candidate_owner_cells: Variant = domain.get("candidate_owner_cells", [])
	if not candidate_owner_cells is Array or candidate_owner_cells.is_empty():
		return {"valid": false, "reason": "candidate_owner_rows_missing"}
	var tampered: Dictionary = domain.duplicate(true)
	tampered.candidate_owner_cells[0][0] = int(tampered.candidate_owner_cells[0][0]) + 1000
	var negative_verifier: RefCounted = B1RRealizer.new()
	var negative: Dictionary = negative_verifier.call("_load_solver_domain", tampered, identity)
	if bool(negative.get("valid", true)) or String(negative.get("reason", "")) != "candidate_domain_half_open_owner_mismatch":
		return {"valid": false, "reason": "tampered_owner_not_rejected", "detail": negative}
	return {"valid": true, "positive": positive, "negative_reason": negative.reason, "validated_candidates": positive.candidate_count}

func _replace_target_patch_geometry(base: Dictionary, domain: Dictionary, solve: Dictionary, roi: Dictionary) -> Dictionary:
	if not bool(solve.get("valid", false)) or solve.get("triangles", []).size() != 110:
		return {"valid": false, "reason": "b1r_solution_shape_invalid", "geometry_realization_complete": false}
	var root_rows: Array = domain.get("root_rows", [])
	var orientation_raw: Array = domain.get("orientation_toward_empty", [])
	if root_rows.size() != 73 or orientation_raw.size() != 3: return {"valid": false, "reason": "b1r_domain_root_or_orientation_invalid"}
	var orientation: Vector3 = Vector3(float(orientation_raw[0]), float(orientation_raw[1]), float(orientation_raw[2])).normalized()
	var target_roots: Dictionary = {}
	for row in root_rows:
		var p_raw: Array = row.get("xyz", [])
		if p_raw.size() != 3: return {"valid": false, "reason": "b1r_domain_root_coordinate_invalid"}
		target_roots[int(row.index)] = Vector3(float(p_raw[0]), float(p_raw[1]), float(p_raw[2]))
	var base_mesh: Dictionary = base.get("mesh", {})
	var source_positions: PackedVector3Array = base_mesh.get("positions", PackedVector3Array())
	var source_normals: PackedVector3Array = base_mesh.get("normals", PackedVector3Array())
	var source_emitted: Array = base.get("emitted_triangles", [])
	if source_positions.size() != source_emitted.size() * 3 or source_normals.size() != source_positions.size():
		return {"valid": false, "reason": "base_mesh_emitted_triangle_alignment_invalid", "position_count": source_positions.size(), "normal_count": source_normals.size(), "emitted_count": source_emitted.size()}
	var output_mesh: Dictionary = Core.new_mesh()
	var output_emitted: Array[Dictionary] = []
	var target_inserted: bool = false
	var replaced_count: int = 0
	var source_polygon_ids: Array = domain.get("source_polygon_ids", [])
	for triangle_index in range(source_emitted.size()):
		var source_row: Dictionary = source_emitted[triangle_index]
		if String(source_row.get("patch_id", "")) == A6_COMPONENT:
			if not target_inserted:
				for direct_row in solve.triangles:
					var ids: Array = direct_row.get("root_indices", [])
					if ids.size() != 3: return {"valid": false, "reason": "b1r_output_triangle_arity_invalid"}
					var points: Array[Vector3] = [target_roots[int(ids[0])], target_roots[int(ids[1])], target_roots[int(ids[2])]]
					var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
					var cross_squared: float = cross.length_squared()
					if not is_finite(cross_squared) or cross_squared <= CUTOFF_SQUARED or cross.dot(orientation) <= 0.0:
						return {"valid": false, "reason": "b1r_output_triangle_failed_cutoff_or_winding", "candidate_id": direct_row.get("candidate_id", ""), "cross_squared": cross_squared}
					var normal: Vector3 = cross.normalized()
					output_mesh.positions.append_array(PackedVector3Array(points))
					output_mesh.normals.append_array(PackedVector3Array([normal, normal, normal]))
					output_emitted.append({"polygon_id": "b1r-direct|" + A6_COMPONENT + "|" + String(direct_row.candidate_id), "source_polygon_ids": source_polygon_ids, "patch_id": A6_COMPONENT, "root_ids": direct_row.root_ids, "normal": normal, "cross_squared": cross_squared, "construction": "B1R_DIRECT_CONSTRAINED_TRIANGULATION"})
				target_inserted = true
			replaced_count += 1
			continue
		for vertex_index in range(3):
			output_mesh.positions.append(source_positions[triangle_index * 3 + vertex_index])
			output_mesh.normals.append(source_normals[triangle_index * 3 + vertex_index])
		output_emitted.append(source_row)
	if not target_inserted or replaced_count != 110: return {"valid": false, "reason": "b1r_target_patch_replacement_count_invalid", "target_inserted": target_inserted, "replaced_count": replaced_count}
	var candidate: RefCounted = CandidateD.new()
	candidate.call("configure_roi", roi)
	var roi_min: Vector3 = candidate.get("ROI_MIN")
	var cells: Vector3i = candidate.get("CELLS")
	var step: float = float(candidate.get("STEP"))
	var roi_max: Vector3 = roi_min + Vector3(cells) * step
	var topology: Dictionary = Core.topology(output_mesh, roi_min, roi_max)
	var mesh_sha: String = String(Authority.new().call("_mesh_sha", output_mesh))
	var unresolved: Array = _filter_target_obligations(base.get("unresolved_obligations", []), source_polygon_ids)
	var cutoff_rejections: Array = _filter_target_obligations(base.get("cutoff_rejections", []), source_polygon_ids)
	var complete: bool = unresolved.is_empty() and cutoff_rejections.is_empty() and int(topology.get("internal_open_edges", -1)) == 0 and int(topology.get("nonmanifold_edges", -1)) == 0 and int(topology.get("degenerate_triangles", -1)) == 0 and int(topology.get("winding_inconsistencies", -1)) == 0
	var edge_summary: Dictionary = _actual_mesh_edge_summary(output_emitted, topology)
	var out: Dictionary = base.duplicate(true)
	out["mesh"] = output_mesh
	out["mesh_sha256"] = mesh_sha
	out["emitted_triangles"] = output_emitted
	out["mesh_topology"] = topology
	out["geometry_realization_complete"] = complete
	out["required_topology_complete"] = complete
	out["winding_valid"] = int(topology.get("winding_inconsistencies", -1)) == 0
	out["required_adjacency_missing_count"] = int(topology.get("internal_open_edges", -1))
	out["required_adjacency_nonmanifold_count"] = int(topology.get("nonmanifold_edges", -1))
	out["unresolved_obligations"] = unresolved
	out["cutoff_rejections"] = cutoff_rejections
	out["topology_graph"] = {"schema": "P3.1.R10B.B1R.ActualMeshEdgeIncidence.v1", "source": "recomputed from emitted root-edge IDs after direct replacement", "edge_incidence": edge_summary}
	out["b1r_direct"] = solve.duplicate(true)
	var patches: Array = out.get("component_reconstruction", {}).get("patches", [])
	for patch_index in range(patches.size()):
		var patch: Dictionary = patches[patch_index]
		if String(patch.get("component_id", "")) == A6_COMPONENT:
			patch["status"] = "DIRECT_CONSTRAINED_TRIANGULATION"
			patch["triangulation"] = {"valid": true, "construction": "B1R_DIRECT_CONSTRAINED_TRIANGULATION", "triangles": solve.triangles, "search": solve}
			patches[patch_index] = patch
	out.component_reconstruction.patches = patches
	return out

func _filter_target_obligations(rows: Array, target_source_polygon_ids: Array) -> Array:
	var target_set: Dictionary = {}
	for polygon_id in target_source_polygon_ids: target_set[String(polygon_id)] = true
	var kept: Array = []
	for raw in rows:
		if raw is Dictionary and target_set.has(String(raw.get("polygon_id", ""))): continue
		kept.append(raw)
	return kept

func _actual_mesh_edge_summary(emitted: Array, topology: Dictionary) -> Dictionary:
	var incidence: Dictionary = {}
	for row in emitted:
		var ids: Array = row.get("root_ids", [])
		if ids.size() != 3: return {"valid": false, "reason": "emitted_triangle_root_arity_invalid"}
		for edge_index in range(3):
			var a: String = String(ids[edge_index]); var b: String = String(ids[(edge_index + 1) % 3])
			var key: String = a + "|" + b if a < b else b + "|" + a
			incidence[key] = int(incidence.get(key, 0)) + 1
	var open_count: int = 0
	var nonmanifold_count: int = 0
	for value in incidence.values():
		if int(value) == 1: open_count += 1
		elif int(value) > 2: nonmanifold_count += 1
	return {"valid": true, "edge_count": incidence.size(), "open_edge_count_including_roi_boundary": open_count, "nonmanifold_edge_count": nonmanifold_count, "mesh_topology": topology}

func _run_controls(rows: Array, target_snapshot: Dictionary) -> Dictionary:
	var authority: RefCounted = Authority.new()
	var out: Array[Dictionary] = []
	for scenario_id in CONTROL_IDS:
		var row: Dictionary = Core.case_by_id(rows, scenario_id)
		if row.is_empty():
			out.append({"scenario_id": scenario_id, "pass": false, "reason": "frozen_control_missing"})
			continue
		out.append(_run_control_case(authority, row, row.roi, null, scenario_id))
	var negative: Dictionary = Core.case_by_id(rows, NEGATIVE_ID)
	var negative_setup: Dictionary = Core.make_snapshot(negative)
	for variant in negative.get("variants", []):
		out.append(_run_control_case(authority, negative, variant.get("roi", {}), negative_setup.get("snapshot", {}), NEGATIVE_ID + "." + String(variant.get("id", ""))))
	var passed: int = 0
	for result in out:
		if bool(result.get("pass", false)): passed += 1
	return {"passed": passed, "count": out.size(), "rows": out}

func _run_control_case(authority: RefCounted, row: Dictionary, roi: Dictionary, reused_snapshot: Variant, label: String) -> Dictionary:
	var snapshot: Dictionary
	if reused_snapshot is Dictionary and not reused_snapshot.is_empty(): snapshot = reused_snapshot
	else:
		var setup: Dictionary = Core.make_snapshot(row)
		if not bool(setup.get("valid", false)): return {"scenario_id": label, "pass": false, "reason": "snapshot_creation_failed"}
		snapshot = setup.snapshot
	var volume_case: Dictionary = _build_volume(row, roi, snapshot)
	if not bool(volume_case.get("valid", false)): return {"scenario_id": label, "pass": false, "reason": volume_case.get("reason", "volume_failed")}
	authority.call("configure_roi", roi)
	var geometry: Dictionary = authority.call("realize_topology", volume_case.volume.values, "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION", snapshot, int(row.get("seed", 131102026)))
	var topology: Dictionary = geometry.get("mesh_topology", {})
	var control_passed: bool = bool(geometry.get("valid", false)) and bool(geometry.get("geometry_realization_complete", false)) and bool(volume_case.get("volume_identity_preserved", false)) and int(topology.get("internal_open_edges", -1)) == 0 and int(topology.get("nonmanifold_edges", -1)) == 0 and int(topology.get("winding_inconsistencies", -1)) == 0 and int(geometry.get("required_adjacency_missing_count", -1)) == 0
	return {"scenario_id": label, "pass": control_passed, "geometry_complete": geometry.get("geometry_realization_complete", false), "mesh_sha256": geometry.get("mesh_sha256", ""), "mesh_topology": topology, "missing_adjacencies": geometry.get("required_adjacency_missing_count", -1), "volume_sha256": volume_case.volume.sha256, "volume_identity_preserved": volume_case.volume_identity_preserved}

func _run_roi_rays(row: Dictionary, snapshot: Dictionary, mesh: Dictionary, emitted: Array) -> Dictionary:
	var rays: Array[Dictionary] = Core.ray_grid(row.roi, row.ray_grid)
	var mismatches: int = 0
	var rows: Array[Dictionary] = []
	var ray_seed: int = int(row.get("seed", 131102026))
	var roi_min: Vector3 = Core.world_min(row.roi)
	var roi_max: Vector3 = roi_min + Vector3(Core.cell_counts(row.roi)) * Core.step(row.roi)
	var position_errors: Array[float] = []
	for index in range(rays.size()):
		var ray: Dictionary = rays[index]
		var roots: Dictionary = Core.canonical_ray_roots(ray.origin, ray.direction, float(ray.length), snapshot, ray_seed, 256, 32)
		if not bool(roots.get("valid", false)): return {"valid": false, "reason": "canonical_ray_roots_failed", "ray_index": index, "rows": rows}
		var roi_roots: Array[Dictionary] = []
		for raw_root in roots.get("roots", []):
			var root: Dictionary = raw_root
			var point: Vector3 = root.get("position", Vector3.INF)
			var inside: bool = point.x >= roi_min.x - 1.0e-6 and point.x <= roi_max.x + 1.0e-6 and point.y >= roi_min.y - 1.0e-6 and point.y <= roi_max.y + 1.0e-6 and point.z >= roi_min.z - 1.0e-6 and point.z <= roi_max.z + 1.0e-6
			if inside and absf(point.y - roi_min.y) > 1.0e-6 and absf(point.y - roi_max.y) > 1.0e-6: roi_roots.append(root)
		var hit: Dictionary = _first_mesh_hit(ray.origin, ray.direction, float(ray.length), mesh, emitted)
		var canonical_hit: bool = not roi_roots.is_empty()
		var mesh_hit: bool = bool(hit.get("hit", false))
		var disagreement: bool = canonical_hit != mesh_hit
		if disagreement: mismatches += 1
		var nearest_delta: Variant = null
		if canonical_hit and mesh_hit:
			var distance_delta: float = INF
			for root in roi_roots: distance_delta = minf(distance_delta, absf(float(hit.distance) - float(root.distance)))
			nearest_delta = distance_delta
			position_errors.append(distance_delta)
		var density: Variant = Core.sample(hit.position, snapshot, ray_seed) if mesh_hit else null
		var triangle: Dictionary = emitted[int(hit.get("triangle_index", -1))] if mesh_hit and int(hit.get("triangle_index", -1)) >= 0 and int(hit.get("triangle_index", -1)) < emitted.size() else {}
		rows.append({"ray_index": index, "origin": [ray.origin.x, ray.origin.y, ray.origin.z], "direction": [ray.direction.x, ray.direction.y, ray.direction.z], "canonical_global_roots": roots.roots, "canonical_roi_root_count": roi_roots.size(), "canonical_roi_hit": canonical_hit, "mesh_hit": mesh_hit, "mesh_hit_distance": hit.get("distance", null), "mesh_hit_position": hit.get("position_array", []), "first_hit_triangle": hit.get("triangle_index", -1), "triangle_component_id": triangle.get("patch_id", ""), "triangle_source_polygons": triangle.get("source_polygon_ids", []), "density_at_hit": density, "distance_to_nearest_roi_root": nearest_delta, "roi_scoped_hit_miss_disagreement": disagreement})
	position_errors.sort()
	return {"valid": rays.size() == 25, "ray_count": rays.size(), "roi_scoped_hit_miss_disagreements": mismatches, "root_scope": "closed ROI with 1e-6 bounds tolerance; cropped Y end-face roots excluded", "completeness": "finite 256-step sign-change scan plus 32 bisections; tangent and sub-step roots may be missed", "position_error_p50": _percentile(position_errors, 0.50), "position_error_p95": _percentile(position_errors, 0.95), "position_error_max": position_errors.back() if not position_errors.is_empty() else null, "rays": rows}

func _run_b5_nested_field_refinement(row: Dictionary, snapshot: Dictionary, coarse_volume: Dictionary, coarse_geometry: Dictionary) -> Dictionary:
	var coarse_roi: Dictionary = row.roi.duplicate(true)
	var fine_roi: Dictionary = coarse_roi.duplicate(true)
	fine_roi.id = "R10B5_DERIVED_LOCAL_FINE_0_125"
	fine_roi.cells = [int(coarse_roi.cells[0]) * 2, int(coarse_roi.cells[1]) * 2, int(coarse_roi.cells[2]) * 2]
	fine_roi.step = float(coarse_roi.step) * 0.5
	var fine_volume_case: Dictionary = _build_volume(row, fine_roi, snapshot)
	if not bool(fine_volume_case.get("valid", false)): return {"valid": false, "reason": "fine_derived_volume_integrity_failed", "detail": fine_volume_case}
	var authority: RefCounted = Authority.new()
	authority.call("configure_roi", fine_roi)
	var geometry: Dictionary = authority.call("realize_topology", fine_volume_case.volume.values, "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION", snapshot, int(row.get("seed", 131102026)))
	var coarse_dims: Vector3i = Vector3i(coarse_roi.cells[0], coarse_roi.cells[1], coarse_roi.cells[2]) + Vector3i.ONE
	var fine_dims: Vector3i = Vector3i(fine_roi.cells[0], fine_roi.cells[1], fine_roi.cells[2]) + Vector3i.ONE
	var coarse_values: PackedFloat32Array = coarse_volume.volume.values
	var fine_values: PackedFloat32Array = fine_volume_case.volume.values
	var nested_samples_equal: bool = true
	var nested_samples_checked: int = 0
	var first_sample_mismatch: Dictionary = {}
	for y in range(coarse_dims.y):
		for z in range(coarse_dims.z):
			for x in range(coarse_dims.x):
				var coarse_index: int = (y * coarse_dims.z + z) * coarse_dims.x + x
				var fine_index: int = ((y * 2) * fine_dims.z + z * 2) * fine_dims.x + x * 2
				nested_samples_checked += 1
				if coarse_values[coarse_index] != fine_values[fine_index]:
					nested_samples_equal = false
					if first_sample_mismatch.is_empty(): first_sample_mismatch = {"coarse_lattice": [x, y, z], "coarse_value": coarse_values[coarse_index], "fine_value": fine_values[fine_index]}
	var face_rows: Array[Dictionary] = []
	var all_faces_match: bool = true
	var minimum: Vector3 = Core.world_min(coarse_roi)
	var maximum: Vector3 = minimum + Vector3(coarse_dims - Vector3i.ONE) * float(coarse_roi.step)
	for axis in range(3):
		for positive in [false, true]:
			var plane: float = maximum[axis] if positive else minimum[axis]
			var coarse_segments: Dictionary = _plane_segments(coarse_geometry.get("mesh", Core.new_mesh()), axis, plane)
			var fine_segments: Dictionary = _plane_segments(geometry.get("mesh", Core.new_mesh()), axis, plane)
			var unmatched: Array[String] = []
			for key in coarse_segments.keys():
				if not fine_segments.has(key): unmatched.append("coarse:" + String(key))
			for key in fine_segments.keys():
				if not coarse_segments.has(key): unmatched.append("fine:" + String(key))
			var match: bool = unmatched.is_empty() and coarse_segments.size() == fine_segments.size()
			all_faces_match = all_faces_match and match
			face_rows.append({"axis": ["X", "Y", "Z"][axis], "orientation": "POS" if positive else "NEG", "plane": plane, "coarse_segment_count": coarse_segments.size(), "fine_segment_count": fine_segments.size(), "unmatched_count": unmatched.size(), "unmatched_examples": unmatched.slice(0, 12), "exact_segment_match": match})
	return {"valid": bool(fine_volume_case.get("volume_identity_preserved", false)) and bool(geometry.get("valid", false)), "reason": "" if bool(geometry.get("valid", false)) else String(geometry.get("reason", "fine_realization_invalid")), "geometry": geometry, "derived_volume_integrity_preserved": fine_volume_case.get("volume_identity_preserved", false), "derived_volume": {"sha256": fine_volume_case.volume.sha256, "payload_sha256": fine_volume_case.volume.metrics.payload_sha256, "revision": fine_volume_case.volume.revision, "step": fine_roi.step, "cells": fine_roi.cells, "sample_count": fine_values.size()}, "source_volume": {"sha256": coarse_volume.volume.sha256, "payload_sha256": coarse_volume.volume.metrics.payload_sha256, "revision": coarse_volume.volume.revision, "step": coarse_roi.step, "cells": coarse_roi.cells}, "nested_sample_values_bitwise_equal": nested_samples_equal, "nested_sample_count": nested_samples_checked, "first_nested_sample_mismatch": first_sample_mismatch, "outer_face_interfaces": face_rows, "all_six_outer_contours_match": all_faces_match, "outer_contour_oracle": "independent coarse-vs-fine mesh plane segments, endpoint quantization 1e-6 world units; not a product tolerance", "canonical_source_mapping": "every coarse grid node maps to fine index 2x,2y,2z; compare float32 samples exactly"}

func _run_mixed_lod_gate(rows: Array, hypothesis: String) -> Dictionary:
	if hypothesis == "R10B1R_DIRECT_CONSTRAINED_TRIANGULATION":
		return {"status": "NOT_GENERALIZED_TO_MIXED_LOD_INPUT_DOMAIN", "conforming": false, "boundary": "B1R frozen candidate domain covers only the equal-LOD A6 component; no transition interface was silently synthesized"}
	var row: Dictionary = Core.case_by_id(rows, "R9.2.SEAM.XPLUS_MIXED_LOD.v1")
	var setup: Dictionary = Core.make_snapshot(row)
	if row.is_empty() or not bool(setup.get("valid", false)): return {"status": "FAILED_MIXED_INPUT_PRECONDITION", "conforming": false}
	var coarse_roi: Dictionary = {"id": "R10B_MIXED_COARSE", "min": [15.0, 1.0, 6.0], "cells": [2, 4, 4], "step": 0.5}
	var fine_roi: Dictionary = {"id": "R10B_MIXED_FINE", "min": [16.0, 1.0, 6.0], "cells": [4, 8, 8], "step": 0.25}
	var coarse_volume: Dictionary = _build_volume(row, coarse_roi, setup.snapshot)
	var fine_volume: Dictionary = _build_volume(row, fine_roi, setup.snapshot)
	if not bool(coarse_volume.get("valid", false)) or not bool(fine_volume.get("valid", false)):
		return {"status": "FAILED_MIXED_VOLUME_PRECONDITION", "conforming": false, "coarse_volume": coarse_volume.get("reason", ""), "fine_volume": fine_volume.get("reason", "")}
	var authority: RefCounted = _new_hypothesis_realizer(hypothesis)
	authority.call("configure_roi", coarse_roi)
	var coarse_geometry: Dictionary = authority.call("realize_topology", coarse_volume.volume.values, _realization_mode(hypothesis), setup.snapshot, int(row.get("seed", 131102026)))
	authority.call("configure_roi", fine_roi)
	var fine_geometry: Dictionary = authority.call("realize_topology", fine_volume.volume.values, _realization_mode(hypothesis), setup.snapshot, int(row.get("seed", 131102026)))
	var plane: float = 16.0
	var coarse_segments: Dictionary = _plane_segments(coarse_geometry.get("mesh", Core.new_mesh()), 0, plane)
	var fine_segments: Dictionary = _plane_segments(fine_geometry.get("mesh", Core.new_mesh()), 0, plane)
	var unmatched: Array[String] = []
	for key in coarse_segments.keys():
		if not fine_segments.has(key): unmatched.append("coarse:" + String(key))
	for key in fine_segments.keys():
		if not coarse_segments.has(key): unmatched.append("fine:" + String(key))
	return {"status": "FAILED_NO_FACE_OWNED_TRANSITION_GENERATOR", "conforming": false, "left_lod1": {"valid": coarse_geometry.get("geometry_realization_complete", false), "mesh_sha256": coarse_geometry.get("mesh_sha256", ""), "volume_sha256": coarse_volume.volume.sha256, "boundary_segment_count": coarse_segments.size(), "internal_open_edges": coarse_geometry.get("mesh_topology", {}).get("internal_open_edges", -1)}, "right_lod0": {"valid": fine_geometry.get("geometry_realization_complete", false), "mesh_sha256": fine_geometry.get("mesh_sha256", ""), "volume_sha256": fine_volume.volume.sha256, "boundary_segment_count": fine_segments.size(), "internal_open_edges": fine_geometry.get("mesh_topology", {}).get("internal_open_edges", -1)}, "unmatched_independent_segments": unmatched.size(), "unmatched_examples": unmatched.slice(0, 16), "historical_expected_boundary_segments": {"coarse_lod1": 10, "fine_lod0": 22}, "face_owned_interface": "NOT_IMPLEMENTED_BY_B1_EQUAL_LOD_REALIZER", "hypothesis": hypothesis, "cutoff_squared": 1.0e-12}

func _plane_segments(mesh: Dictionary, axis: int, plane: float) -> Dictionary:
	var output: Dictionary = {}
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	for index in range(0, positions.size(), 3):
		var points: Array[Vector3] = [positions[index], positions[index + 1], positions[index + 2]]
		var intersections: Array[Vector3] = []
		for edge in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = points[int(edge[0])]
			var b: Vector3 = points[int(edge[1])]
			if absf(a[axis] - plane) <= 1.0e-6: intersections.append(a)
			if (a[axis] < plane and b[axis] > plane) or (a[axis] > plane and b[axis] < plane): intersections.append(a.lerp(b, (plane - a[axis]) / (b[axis] - a[axis])))
		var unique: Array[Vector3] = []
		for point in intersections:
			var found: bool = false
			for existing in unique:
				if point.distance_squared_to(existing) <= 1.0e-12: found = true; break
			if not found: unique.append(point)
		if unique.size() != 2: continue
		var first_key: String = _quantized_point_key(unique[0], axis)
		var second_key: String = _quantized_point_key(unique[1], axis)
		var key: String = first_key + "|" + second_key if first_key < second_key else second_key + "|" + first_key
		output[key] = true
	return output

func _quantized_point_key(point: Vector3, plane_axis: int) -> String:
	var coordinates: Array[int] = []
	for axis in range(3):
		if axis == plane_axis: continue
		coordinates.append(roundi(point[axis] * 1000000.0))
	return "%d,%d" % [coordinates[0], coordinates[1]]

func _first_mesh_hit(origin: Vector3, direction: Vector3, max_distance: float, mesh: Dictionary, emitted: Array) -> Dictionary:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var best: float = INF
	var best_triangle: int = -1
	for index in range(0, positions.size(), 3):
		var distance: float = _ray_triangle(origin, direction, positions[index], positions[index + 1], positions[index + 2])
		if distance < 0.0 or distance > max_distance: continue
		if distance < best:
			best = distance
			best_triangle = int(index / 3)
	if best_triangle < 0: return {"hit": false}
	var point: Vector3 = origin + direction * best
	return {"hit": true, "distance": best, "position": point, "position_array": [point.x, point.y, point.z], "triangle_index": best_triangle}

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

func _percentile(values: Array[float], q: float) -> Variant:
	if values.is_empty(): return null
	var rank: int = clampi(ceili(q * values.size()) - 1, 0, values.size() - 1)
	return values[rank]

func _write_json(path: String, value: Dictionary) -> Dictionary:
	var encoded: PackedByteArray = (JSON.stringify(value, "\t", false) + "\n").to_utf8_buffer()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"valid": false, "reason": "artifact_open_failed", "path": path}
	file.store_buffer(encoded)
	file.flush()
	file.close()
	return {"valid": true, "path": path, "sha256": Core.sha256(encoded), "bytes": encoded.size()}

func _sha_res_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return Core.sha256(bytes)

func _sha_absolute(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return Core.sha256(bytes)

func _blocked(reason: String, detail: Dictionary) -> void:
	print("R10B_BLOCKED " + JSON.stringify({"reason": reason, "detail": detail}))
	quit(3)
