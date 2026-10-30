extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Authority := preload("res://tests/prototypes/p3_1_r10_a_topology_authority.gd")
const EXPECTED_MANIFEST_SHA: String = "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const EXPECTED_CANDIDATE_D_SHA: String = "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"
const CONTROL_IDS: Array[String] = [
	"R9.2.GEO.ZERO.v1",
	"R9.2.GEO.CARVE.v1",
	"R9.2.GEO.FILL_CARVE.v1",
	"R9.2.CHUNK.NEIGHBOR_PAIR.v1",
	"R9.2.SEAM.NEGATIVE_REGIONS.v1"
]
const EQUAL_ID: String = "R9.2.SEAM.XPLUS_EQUAL.v1"
const MIXED_ID: String = "R9.2.SEAM.XPLUS_MIXED_LOD.v1"
const RAY_ID: String = "R9.2.RAY.CANONICAL_PICKER.v1"

var _failures: Array[String] = []
var _artifact_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var attempt_id: String = OS.get_environment("R10A_ATTEMPT")
	var hypothesis: String = OS.get_environment("R10A_HYPOTHESIS")
	var source_sha: String = OS.get_environment("R10A_SOURCE_SHA")
	var artifact_root: String = OS.get_environment("R10A_ARTIFACT_DIR")
	var candidate_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
	var manifest: Dictionary = Core.load_manifest()
	if not attempt_id.begins_with("R10-A") or hypothesis.is_empty() or source_sha.length() != 40 or not source_sha.is_valid_hex_number() or artifact_root.is_empty() or not DirAccess.dir_exists_absolute(artifact_root):
		print("R10A_BLOCKED " + JSON.stringify({"reason": "attempt_identity_or_artifact_root_invalid"}))
		quit(2)
		return
	if candidate_sha != EXPECTED_CANDIDATE_D_SHA:
		print("R10A_BLOCKED " + JSON.stringify({"reason": "candidate_d_source_pin_mismatch", "observed": candidate_sha, "expected": EXPECTED_CANDIDATE_D_SHA}))
		quit(2)
		return
	if not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != EXPECTED_MANIFEST_SHA:
		print("R10A_BLOCKED " + JSON.stringify({"reason": "frozen_manifest_verification_failed", "detail": manifest.get("reason", "hash_mismatch")}))
		quit(2)
		return
	print("R10A_PREFLIGHT " + JSON.stringify({"attempt_id": attempt_id, "hypothesis": hypothesis, "source_sha": source_sha, "candidate_d_sha256": candidate_sha, "manifest_sha256": manifest.sha256, "godot": Engine.get_version_info(), "cutoff_squared": 1.0e-12}))
	var candidate: RefCounted = CandidateD.new()
	var authority: RefCounted = Authority.new()
	var result_rows: Array[Dictionary] = []
	for control_id in CONTROL_IDS:
		var row: Dictionary = Core.case_by_id(manifest.rows, control_id)
		if row.is_empty():
			_failures.append("missing_control:" + control_id)
			continue
		var control_result: Dictionary = _run_case(candidate, authority, row, row.roi, hypothesis)
		control_result["scenario_id"] = control_id
		control_result["role"] = "frozen_control"
		result_rows.append(control_result)
		_emit_result(control_result, artifact_root)
	var equal_row: Dictionary = Core.case_by_id(manifest.rows, EQUAL_ID)
	var equal_result: Dictionary = _run_case(candidate, authority, equal_row, equal_row.roi, hypothesis)
	equal_result["scenario_id"] = EQUAL_ID
	equal_result["role"] = "required_equal_lod_gate_full_roi"
	result_rows.append(equal_result)
	_emit_result(equal_result, artifact_root)
	var mixed_row: Dictionary = Core.case_by_id(manifest.rows, MIXED_ID)
	var setup: Dictionary = Core.make_snapshot(mixed_row)
	var left_roi: Dictionary = {"id": "L", "min": [15.0, 1.0, 6.0], "cells": [2, 4, 4], "step": 0.5}
	var right_roi: Dictionary = {"id": "R", "min": [16.0, 1.0, 6.0], "cells": [4, 8, 8], "step": 0.25}
	var left_result: Dictionary = _run_case_from_setup(candidate, authority, setup.snapshot, mixed_row, left_roi, hypothesis)
	left_result["scenario_id"] = MIXED_ID
	left_result["role"] = "mixed_lod_left_lod1"
	var right_result: Dictionary = _run_case_from_setup(candidate, authority, setup.snapshot, mixed_row, right_roi, hypothesis)
	right_result["scenario_id"] = MIXED_ID
	right_result["role"] = "mixed_lod_right_lod0"
	var interface_diagnostic: Dictionary = _compare_interface(left_result, right_result)
	var mixed_result: Dictionary = {"scenario_id": MIXED_ID, "role": "required_mixed_lod_gate", "left": left_result, "right": right_result, "interface": interface_diagnostic}
	result_rows.append(mixed_result)
	_emit_result(mixed_result, artifact_root)
	var ray_row: Dictionary = Core.case_by_id(manifest.rows, RAY_ID)
	var ray_setup: Dictionary = Core.make_snapshot(ray_row)
	var ray_result: Dictionary = _run_case(candidate, authority, ray_row, ray_row.roi, hypothesis)
	var ray_geometry: Dictionary = ray_result.get("geometry", {})
	var rays: Array[Dictionary] = Core.ray_grid(ray_row.roi, ray_row.ray_grid)
	var ray_compare: Dictionary = Core.compare_mesh_rays(rays, ray_geometry.get("mesh", Core.new_mesh()), ray_setup.snapshot, int(ray_row.seed), 256)
	var ray_row_result: Dictionary = {"scenario_id": RAY_ID, "role": "frozen_roi_ray_oracle", "mesh_case": ray_result, "ray_comparison": ray_compare}
	result_rows.append(ray_row_result)
	_emit_result(ray_row_result, artifact_root)
	var controls_pass: int = 0
	for row in result_rows:
		if String(row.get("role", "")) == "frozen_control" and bool(row.get("valid", false)):
			controls_pass += 1
	var equal_gate: bool = bool(equal_result.get("geometry", {}).get("geometry_realization_complete", false))
	var mixed_gate: bool = bool(interface_diagnostic.get("conforming", false))
	var ray_mismatches: int = int(ray_compare.get("hit_miss_mismatches", -1))
	var volume_gate: bool = bool(equal_result.get("volume_identity_preserved", false)) and bool(left_result.get("volume_identity_preserved", false)) and bool(right_result.get("volume_identity_preserved", false))
	var target_pass: bool = equal_gate and mixed_gate and controls_pass == 5 and ray_mismatches == 0 and volume_gate and _failures.is_empty()
	var summary: Dictionary = {"schema": "P3.1.R10A.AttemptResult.v1", "attempt_id": attempt_id, "hypothesis": hypothesis, "source_sha": source_sha,
		"candidate_d_source_sha256": candidate_sha, "manifest_sha256": EXPECTED_MANIFEST_SHA, "result": "PASS" if target_pass else "FAILED_TARGET",
		"equal_lod": equal_result.get("geometry", {}).get("summary", {}), "equal_lod_complete": equal_gate,
		"mixed_lod": interface_diagnostic, "required_adjacency_unresolved": int(equal_result.get("geometry", {}).get("required_adjacency_missing_count", -1)),
		"internal_open_edges": int(equal_result.get("geometry", {}).get("mesh_topology", {}).get("internal_open_edges", -1)),
		"nonmanifold": int(equal_result.get("geometry", {}).get("mesh_topology", {}).get("nonmanifold_edges", -1)),
		"winding_valid": bool(equal_result.get("geometry", {}).get("winding_valid", false)), "controls_pass": "%d/5" % controls_pass,
		"ray": {"mismatches": ray_mismatches, "query_count": rays.size()}, "volume_identity_preserved": volume_gate, "failures": _failures,
		"case_count": result_rows.size(), "geometry_cutoff_squared": 1.0e-12}
	var summary_write: Dictionary = _write_json(artifact_root.path_join(attempt_id + "_summary.json"), summary)
	if not bool(summary_write.get("valid", false)):
		_failures.append(String(summary_write.get("reason", "summary_write_failed")))
	print("R10A_ATTEMPT_COMPLETE " + JSON.stringify(summary))
	print("R10A_ARTIFACTS " + JSON.stringify({"paths": _artifact_paths, "summary": summary_write.get("path", "")}))
	quit(0 if _failures.is_empty() else 3)

func _run_case(candidate: RefCounted, authority: RefCounted, row: Dictionary, roi: Dictionary, hypothesis: String) -> Dictionary:
	var setup: Dictionary = Core.make_snapshot(row)
	return _run_case_from_setup(candidate, authority, setup.snapshot, row, roi, hypothesis)

func _run_case_from_setup(candidate: RefCounted, authority: RefCounted, snapshot: Dictionary, row: Dictionary, roi: Dictionary, hypothesis: String) -> Dictionary:
	candidate.call("configure_roi", roi)
	var baseline: Dictionary = candidate.call("build", snapshot, row, {"id": "R10A_VOLUME", "roi": roi})
	if not bool(baseline.get("valid", false)):
		return {"valid": false, "reason": "candidate_d_volume_materialization_or_integrity_failed", "detail": baseline.get("reason", "unknown"), "geometry": {}}
	var volume: Dictionary = baseline.get("volume", {})
	var values: PackedFloat32Array = volume.get("values", PackedFloat32Array())
	authority.call("configure_roi", roi)
	var geometry: Dictionary = authority.call("realize_topology", values, hypothesis)
	var volume_metrics: Dictionary = baseline.get("metrics", {}).get("volume", {})
	var volume_identity: bool = String(volume.get("sha256", "")) == Core.sha256(volume.get("bytes", PackedByteArray())) and String(volume.get("sha256", "")) == String(baseline.get("metrics", {}).get("persisted_reloaded_volume_sha256", ""))
	return {"valid": bool(geometry.get("valid", false)) and volume_identity, "reason": String(geometry.get("reason", "")), "geometry": geometry,
		"volume_identity_preserved": volume_identity, "volume_sha256": String(volume.get("sha256", "")), "payload_sha256": String(volume_metrics.get("payload_sha256", "")),
		"materialized_bytes": int(volume.get("serialized_bytes", -1)), "volume_revision": int(volume.get("revision", -1))}

func _compare_interface(left: Dictionary, right: Dictionary) -> Dictionary:
	var left_mesh: Dictionary = left.get("geometry", {}).get("mesh", Core.new_mesh())
	var right_mesh: Dictionary = right.get("geometry", {}).get("mesh", Core.new_mesh())
	var left_segments: Dictionary = _plane_segments(left_mesh, 0, 16.0)
	var right_segments: Dictionary = _plane_segments(right_mesh, 0, 16.0)
	var left_keys: Array = left_segments.keys(); left_keys.sort()
	var right_keys: Array = right_segments.keys(); right_keys.sort()
	var unmatched: Array[String] = []
	for key in left_keys:
		if not right_segments.has(key): unmatched.append("L:" + String(key))
	for key in right_keys:
		if not left_segments.has(key): unmatched.append("R:" + String(key))
	return {"conforming": false, "realization": "NOT_GENERATED_BY_A1", "left_boundary_segment_count": left_keys.size(), "right_boundary_segment_count": right_keys.size(), "unmatched_segment_entries": unmatched.size(), "unmatched_examples": unmatched.slice(0, 12)}

func _plane_segments(mesh: Dictionary, axis: int, plane: float) -> Dictionary:
	var segments: Dictionary = {}
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	for index in range(0, positions.size(), 3):
		var points: Array[Vector3] = [positions[index], positions[index + 1], positions[index + 2]]
		var intersections: Array[Vector3] = []
		for edge in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = points[int(edge[0])]; var b: Vector3 = points[int(edge[1])]
			if absf(a[axis] - plane) <= 1.0e-6: intersections.append(a)
			if (a[axis] < plane and b[axis] > plane) or (a[axis] > plane and b[axis] < plane): intersections.append(a.lerp(b, (plane - a[axis]) / (b[axis] - a[axis])))
		var unique: Array[Vector3] = []
		for point in intersections:
			var found: bool = false
			for old in unique:
				if old.distance_squared_to(point) <= 1.0e-12: found = true; break
			if not found: unique.append(point)
		if unique.size() == 2:
			var akey: String = Core._point_key(unique[0]); var bkey: String = Core._point_key(unique[1])
			var key: String = akey + "|" + bkey if akey < bkey else bkey + "|" + akey
			segments[key] = true
	return segments

func _emit_result(result: Dictionary, root: String) -> void:
	var id: String = String(result.get("role", "case")) + "_" + String(result.get("scenario_id", "unknown")).replace("/", "_").replace(":", "_")
	var written: Dictionary = _write_json(root.path_join(id + ".json"), result)
	if not bool(written.get("valid", false)):
		_failures.append(String(written.get("reason", "case_artifact_write_failed")))
	else:
		_artifact_paths.append(String(written.path))

func _write_json(path: String, payload: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path):
		return {"valid": false, "reason": "artifact_overwrite_refused", "path": path}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"valid": false, "reason": "artifact_open_failed", "path": path}
	file.store_buffer(JSON.stringify(payload, "\t", false).to_utf8_buffer())
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return {"valid": error == OK, "reason": "artifact_write_failed" if error != OK else "", "path": path}

func _sha_res_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return Core.sha256(bytes)
