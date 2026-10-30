extends SceneTree

const SolverScript := preload("res://tests/prototypes/p3_1_r10_bx_conflict_solver.gd")
const B1RScript := preload("res://tests/prototypes/p3_1_r10_b1r_direct_triangulator.gd")
const HYPOTHESIS := "R10BX_CONFLICT_INDEXED_EXACT_ROOT_FEASIBILITY"
const GODOT_VERSION := "4.7.2.stable.official.ed1daf0bf"
const PAIR_LIMIT := 10000000
const GRAPH_BUILD_TIME_LIMIT_MS := 180000
const SEARCH_LIMITS: Dictionary = {
	"search_nodes": 500000,
	"recursion_depth": 110,
	"wall_milliseconds": 120000,
	"estimated_state_bytes": 536870912,
	"complete_solutions": 1
}
const PREREGISTRATION_SHA256 := "9ec0de228487722cb74f5ea78b33ebda5d5a0d78782edea1bad55cb4dbd4c460"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage: String = OS.get_environment("R10BX_STAGE")
	var artifact_root: String = OS.get_environment("R10BX_ARTIFACT_DIR")
	var graph_root: String = OS.get_environment("R10BX_GRAPH_DIR")
	var repo_root: String = OS.get_environment("R10BX_REPO_ROOT")
	var domain_path: String = OS.get_environment("R10BX_DOMAIN_PATH")
	var expected_domain_sha: String = OS.get_environment("R10BX_DOMAIN_SHA256")
	var source_sha: String = OS.get_environment("R10BX_SOURCE_SHA")
	var campaign_sha: String = _resource_sha("res://tests/prototypes/p3_1_r10_bx_campaign.gd")
	var solver_sha: String = _resource_sha("res://tests/prototypes/p3_1_r10_bx_conflict_solver.gd")
	var version_info: Dictionary = Engine.get_version_info()
	var observed_version: String = _canonical_engine_version(version_info)
	if stage not in ["check-only", "graph", "search"]:
		_blocked("stage_invalid", {"stage": stage})
		return
	if artifact_root.is_empty() or graph_root.is_empty() or repo_root.is_empty() or source_sha.length() != 40 or not source_sha.is_valid_hex_number():
		_blocked("run_identity_or_artifact_root_invalid", {})
		return
	if observed_version != GODOT_VERSION:
		_blocked("godot_version_mismatch", {"expected": GODOT_VERSION, "observed": observed_version})
		return
	if campaign_sha != OS.get_environment("R10BX_CAMPAIGN_SHA256") or solver_sha != OS.get_environment("R10BX_SOLVER_SHA256"):
		_blocked("experimental_source_hash_mismatch", {"campaign": campaign_sha, "solver": solver_sha})
		return
	print("R10BX_PREFLIGHT " + JSON.stringify({"hypothesis": HYPOTHESIS, "stage": stage, "source_sha": source_sha, "campaign_sha256": campaign_sha, "solver_sha256": solver_sha, "godot": observed_version, "godot_version_info": version_info, "domain_sha256": expected_domain_sha, "pair_limit": PAIR_LIMIT, "graph_build_time_limit_ms": GRAPH_BUILD_TIME_LIMIT_MS, "search_limits": SEARCH_LIMITS}))
	if stage == "check-only":
		print("R10BX_CHECK_COMPLETE " + JSON.stringify({"status": "PASS", "source_sha": source_sha, "campaign_sha256": campaign_sha, "solver_sha256": solver_sha}))
		quit(0)
		return
	var domain_bytes: PackedByteArray = FileAccess.get_file_as_bytes(domain_path)
	var solver: RefCounted = SolverScript.new()
	var loaded: Dictionary = solver.call("load_pinned_domain", domain_bytes, expected_domain_sha)
	if not bool(loaded.get("valid", false)):
		_blocked("candidate_domain_preflight_failed", {"detail": loaded})
		return
	loaded["bx_source_sha"] = source_sha
	loaded["bx_campaign_sha256"] = campaign_sha
	loaded["bx_solver_sha256"] = solver_sha
	if stage == "graph":
		_run_graph_preflight(solver, loaded, artifact_root, graph_root, source_sha, campaign_sha, solver_sha)
		return
	if stage == "search":
		_run_single_search(solver, loaded, artifact_root, graph_root, repo_root, source_sha, campaign_sha, solver_sha)
		return

func _run_graph_preflight(solver: RefCounted, loaded: Dictionary, artifact_root: String, graph_root: String, source_sha: String, campaign_sha: String, solver_sha: String) -> void:
	var domain_negative: Dictionary = solver.call("load_pinned_domain", FileAccess.get_file_as_bytes(OS.get_environment("R10BX_DOMAIN_PATH")), "0000000000000000000000000000000000000000000000000000000000000000")
	if bool(domain_negative.get("valid", true)) or String(domain_negative.get("reason", "")) != "candidate_domain_physical_hash_mismatch":
		_blocked("wrong_domain_pin_negative_failed", {"detail": domain_negative})
		return
	var damaged_bytes: PackedByteArray = FileAccess.get_file_as_bytes(OS.get_environment("R10BX_DOMAIN_PATH"))
	if damaged_bytes.is_empty():
		_blocked("pinned_domain_unexpectedly_empty", {})
		return
	damaged_bytes[damaged_bytes.size() - 1] = int(damaged_bytes[damaged_bytes.size() - 1]) ^ 1
	var damaged_negative: Dictionary = solver.call("load_pinned_domain", damaged_bytes, OS.get_environment("R10BX_DOMAIN_SHA256"))
	if bool(damaged_negative.get("valid", true)) or String(damaged_negative.get("reason", "")) != "candidate_domain_physical_hash_mismatch":
		_blocked("domain_byte_tamper_negative_failed", {"detail": damaged_negative})
		return
	var identity_tampered: Dictionary = loaded.domain.duplicate(true)
	identity_tampered.identity.revision = int(identity_tampered.identity.revision) + 1
	var b1r: RefCounted = B1RScript.new()
	var identity_negative: Dictionary = b1r.call("_load_solver_domain", identity_tampered, SolverScript.EXPECTED_IDENTITY)
	if bool(identity_negative.get("valid", true)) or String(identity_negative.get("reason", "")) != "candidate_domain_identity_mismatch":
		_blocked("domain_identity_tamper_negative_failed", {"detail": identity_negative})
		return
	var graph_started: int = Time.get_ticks_msec()
	var first: Dictionary = solver.call("build_graph", loaded, PAIR_LIMIT, GRAPH_BUILD_TIME_LIMIT_MS)
	var first_elapsed: int = Time.get_ticks_msec() - graph_started
	if not bool(first.get("valid", false)):
		_emit_graph_failure("first_graph_build_failed", first, source_sha)
		return
	var first_digest: String = String(solver.call("graph_digest", first))
	var write_result: Dictionary = solver.call("write_graph_artifacts", first, graph_root)
	if not bool(write_result.get("valid", false)):
		_emit_graph_failure("graph_serialization_failed", write_result, source_sha)
		return
	var first_stats: Dictionary = first.get("build_stats", {}).duplicate(true)
	first.clear()
	var second_started: int = Time.get_ticks_msec()
	var second: Dictionary = solver.call("build_graph", loaded, PAIR_LIMIT, GRAPH_BUILD_TIME_LIMIT_MS)
	var second_elapsed: int = Time.get_ticks_msec() - second_started
	if not bool(second.get("valid", false)):
		_emit_graph_failure("independent_graph_rebuild_failed", second, source_sha)
		return
	var second_digest: String = String(solver.call("graph_digest", second))
	var second_stats: Dictionary = second.get("build_stats", {}).duplicate(true)
	second.clear()
	if first_digest != second_digest or first_digest != String(write_result.get("graph_sha256", "")):
		_emit_graph_failure("independent_graph_build_digest_mismatch", {"first": first_digest, "second": second_digest, "artifact": write_result.get("graph_sha256", "")}, source_sha)
		return
	var index_path: String = graph_root.path_join("bx_conflict_index.json")
	var matrix_path: String = graph_root.path_join("bx_conflicts.bin")
	var receipt_path: String = graph_root.path_join("bx_conflict_index_receipt.json")
	var reload_result: Dictionary = solver.call("reload_and_validate_graph", loaded, index_path, matrix_path, receipt_path, first_digest)
	if not bool(reload_result.get("valid", false)):
		_emit_graph_failure("serialized_graph_reload_failed", reload_result, source_sha)
		return
	var summary: Dictionary = {
		"schema": "P3.1.R10BX.GraphPreflight.v1",
		"hypothesis": HYPOTHESIS,
		"status": "PASS",
		"source_sha": source_sha,
		"campaign_sha256": campaign_sha,
		"solver_sha256": solver_sha,
		"godot": Engine.get_version_info(),
		"domain_sha256": loaded.domain_sha256,
		"domain_identity_sha256": loaded.identity_sha256,
		"graph_sha256": first_digest,
		"graph_files": write_result,
		"first_build": first_stats,
		"second_build": second_stats,
		"first_total_elapsed_ms": first_elapsed,
		"second_total_elapsed_ms": second_elapsed,
		"reload": {"valid": true, "tamper_negative": reload_result.get("tamper_negative", {})},
		"negative_tests": {"wrong_domain_pin": domain_negative.reason, "domain_byte_tamper": damaged_negative.reason, "domain_identity_tamper": identity_negative.reason},
		"search_started": false,
		"search_limits_preregistered": true
	}
	var summary_path: String = artifact_root.path_join("bx_graph_preflight.json")
	var summary_write: Dictionary = _write_json_new(summary_path, summary)
	if not bool(summary_write.get("valid", false)):
		_emit_graph_failure("graph_summary_write_failed", summary_write, source_sha)
		return
	print("R10BX_GRAPH_COMPLETE " + JSON.stringify({"status": "PASS", "source_sha": source_sha, "domain_sha256": loaded.domain_sha256, "graph_sha256": first_digest, "candidate_count": 7608, "theoretical_pair_count": first_stats.get("theoretical_pair_count", -1), "x_sweep_pair_count": first_stats.get("x_sweep_pair_count", -1), "candidate_aabb_pair_tests": first_stats.get("candidate_aabb_pair_tests", -1), "candidate_axis_filter_pair_tests": first_stats.get("candidate_axis_filter_pair_tests", -1), "candidate_axis_rejected_pairs": first_stats.get("candidate_axis_rejected_pairs", -1), "edge_exact_pair_tests": first_stats.get("edge_exact_pair_tests", -1), "candidate_exact_pair_tests": first_stats.get("candidate_exact_pair_tests", -1), "exact_pair_tests": first_stats.get("exact_pair_tests", -1), "conflict_pairs": first_stats.get("unique_conflict_pairs", -1), "estimated_peak_bytes": first_stats.get("estimated_peak_bytes", -1), "first_build_elapsed_ms": first_stats.get("elapsed_ms", -1), "second_build_elapsed_ms": second_stats.get("elapsed_ms", -1), "search_started": false, "artifact": summary_path}))
	quit(0)

func _run_single_search(solver: RefCounted, loaded: Dictionary, artifact_root: String, graph_root: String, repo_root: String, source_sha: String, campaign_sha: String, solver_sha: String) -> void:
	var expected_graph_sha: String = OS.get_environment("R10BX_EXPECTED_GRAPH_SHA256")
	if expected_graph_sha.length() != 64 or not expected_graph_sha.is_valid_hex_number():
		_blocked("search_graph_hash_pin_invalid", {})
		return
	if PREREGISTRATION_SHA256 == "PENDING_FINAL_PREREGISTRATION_PIN":
		_blocked("search_preregistration_pin_not_finalized", {})
		return
	var prereg_path: String = repo_root.path_join("docs/reports/P3-1-R10-BX-CAMPAIGN/BX-PREREGISTRATION.md")
	var prereg_bytes: PackedByteArray = FileAccess.get_file_as_bytes(prereg_path)
	var prereg_sha: String = _sha256(prereg_bytes)
	if prereg_sha != PREREGISTRATION_SHA256 or prereg_sha != OS.get_environment("R10BX_PREREGISTRATION_SHA256"):
		_blocked("search_preregistration_hash_mismatch", {"expected": PREREGISTRATION_SHA256, "observed": prereg_sha})
		return
	var graph: Dictionary = solver.call("reload_and_validate_graph", loaded, graph_root.path_join("bx_conflict_index.json"), graph_root.path_join("bx_conflicts.bin"), graph_root.path_join("bx_conflict_index_receipt.json"), expected_graph_sha)
	if not bool(graph.get("valid", false)):
		_blocked("serialized_conflict_graph_preflight_failed", {"detail": graph})
		return
	var search_start_path: String = artifact_root.path_join("bx_search_started.json")
	var reservation_path: String = artifact_root.path_join("bx_search_reservation.json")
	if FileAccess.file_exists(search_start_path) or FileAccess.file_exists(reservation_path):
		_blocked("duplicate_search_reservation_refused", {"search_started": FileAccess.file_exists(search_start_path), "reservation": FileAccess.file_exists(reservation_path)})
		return
	var reservation: Dictionary = {"schema": "P3.1.R10BX.SearchReservation.v1", "hypothesis": HYPOTHESIS, "source_sha": source_sha, "domain_sha256": loaded.domain_sha256, "graph_sha256": expected_graph_sha, "preregistration_sha256": prereg_sha, "limits": SEARCH_LIMITS, "created_utc": Time.get_datetime_string_from_system(true, true)}
	var reservation_write: Dictionary = _write_json_new(reservation_path, reservation)
	if not bool(reservation_write.get("valid", false)):
		_blocked("search_reservation_write_failed", reservation_write)
		return
	var started: Dictionary = reservation.duplicate(true)
	started["schema"] = "P3.1.R10BX.SearchStarted.v1"
	started["started_utc"] = Time.get_datetime_string_from_system(true, true)
	var started_write: Dictionary = _write_json_new(search_start_path, started)
	if not bool(started_write.get("valid", false)):
		_blocked("search_start_record_write_failed", started_write)
		return
	print("R10BX_SEARCH_STARTED " + JSON.stringify({"hypothesis": HYPOTHESIS, "source_sha": source_sha, "domain_sha256": loaded.domain_sha256, "graph_sha256": expected_graph_sha, "preregistration_sha256": prereg_sha, "limits": SEARCH_LIMITS}))
	var search_started_usec: int = Time.get_ticks_usec()
	var result: Dictionary = solver.call("solve", graph, SEARCH_LIMITS)
	var search_elapsed_usec: int = Time.get_ticks_usec() - search_started_usec
	result["schema"] = "P3.1.R10BX.SearchResult.v1"
	result["hypothesis"] = HYPOTHESIS
	result["source_sha"] = source_sha
	result["campaign_sha256"] = campaign_sha
	result["solver_sha256"] = solver_sha
	result["godot"] = Engine.get_version_info()
	result["domain_sha256"] = loaded.domain_sha256
	result["domain_identity_sha256"] = loaded.identity_sha256
	result["graph_sha256"] = expected_graph_sha
	result["preregistration_sha256"] = prereg_sha
	result["search_elapsed_usec"] = search_elapsed_usec
	result["search_started"] = true
	var result_path: String = artifact_root.path_join("bx_search_result.json")
	var result_write: Dictionary = _write_json_new(result_path, result)
	if not bool(result_write.get("valid", false)):
		print("R10BX_SEARCH_COMPLETE " + JSON.stringify({"status": "BLOCKED_EVIDENCE_WRITE", "terminal_status": result.get("status", ""), "source_sha": source_sha, "artifact_error": result_write}))
		quit(3)
		return
	print("R10BX_SEARCH_COMPLETE " + JSON.stringify({"status": result.get("status", "BLOCKED"), "source_sha": source_sha, "domain_sha256": loaded.domain_sha256, "graph_sha256": expected_graph_sha, "nodes": result.get("nodes", -1), "branches": result.get("branches", -1), "elapsed_ms": result.get("elapsed_ms", -1), "stop_reason": result.get("stop_reason", ""), "result_artifact": result_path}))
	quit(0 if bool(result.get("valid", false)) else 4)

func _emit_graph_failure(reason: String, detail: Dictionary, source_sha: String) -> void:
	var result: Dictionary = {"schema": "P3.1.R10BX.GraphPreflight.v1", "status": "BLOCKED", "reason": reason, "detail": detail, "source_sha": source_sha, "search_started": false, "created_utc": Time.get_datetime_string_from_system(true, true)}
	var path: String = OS.get_environment("R10BX_ARTIFACT_DIR").path_join("bx_graph_preflight.json")
	_write_json_new(path, result)
	print("R10BX_GRAPH_COMPLETE " + JSON.stringify({"status": "BLOCKED", "reason": reason, "source_sha": source_sha, "search_started": false, "artifact": path}))
	quit(3)

func _blocked(reason: String, details: Dictionary) -> void:
	_failures.append(reason)
	var source_sha: String = OS.get_environment("R10BX_SOURCE_SHA")
	var result: Dictionary = {"schema": "P3.1.R10BX.Blocked.v1", "status": "BLOCKED", "reason": reason, "details": details, "source_sha": source_sha, "created_utc": Time.get_datetime_string_from_system(true, true)}
	var artifact_root: String = OS.get_environment("R10BX_ARTIFACT_DIR")
	if not artifact_root.is_empty(): _write_json_new(artifact_root.path_join("bx_blocked.json"), result)
	print("R10BX_BLOCKED " + JSON.stringify(result))
	quit(2)

func _write_json_new(path: String, value: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path): return {"valid": false, "reason": "overwrite_refused", "path": path}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"valid": false, "reason": "open_failed", "path": path, "error": error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(value))
	var error: Error = file.get_error()
	file.close()
	return {"valid": error == OK, "path": path, "error": error_string(error)}

func _resource_sha(path: String) -> String:
	return _sha256(FileAccess.get_file_as_bytes(path))

func _canonical_engine_version(info: Dictionary) -> String:
	var version_hash: String = String(info.get("hash", ""))
	if version_hash.length() < 9:
		return ""
	return "%d.%d.%d.%s.%s.%s" % [int(info.get("major", -1)), int(info.get("minor", -1)), int(info.get("patch", -1)), String(info.get("status", "")), String(info.get("build", "")), version_hash.substr(0, 9)]

func _sha256(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().to_lower()
