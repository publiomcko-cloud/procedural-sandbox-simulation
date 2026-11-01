extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const R6Realizer := preload("res://tests/prototypes/p3_1_r12_cxr_r6_realizer.gd")
const Diagnostics := preload("res://tests/prototypes/p3_1_r12_cxr_r6_diagnostics.gd")

const TARGET_ID: String = "R9.2.SEAM.XPLUS_EQUAL.v1"
const MANIFEST_SHA: String = "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const STAGE0_SHA: String = "33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d"
const RESIDUAL_SHA: String = "ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23"
const CANDIDATE_SHA: String = "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"
const TOPOLOGY_SHA: String = "4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95"
const GRAPH_SHA: String = "a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9"
const VOLUME_SHA: String = "ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2"
const PAYLOAD_SHA: String = "2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0"
const CAVITY_SHA: String = "a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6"
const D0_RESIDUAL_OVER_EPSILON: int = 570
const D0_VERTEX_OCCURRENCES: int = 1666

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var mode: String = OS.get_environment("R12CXR_R6_A_MODE")
	if mode == "check-only":
		print("R6_A_CHECK_ONLY=PASS")
		quit(0)
		return
	if mode != "audit":
		_fail("r6_a_mode_invalid", {"mode": mode})
		return
	var output_path: String = OS.get_environment("R12CXR_R6_A_OUTPUT")
	var source_sha: String = OS.get_environment("R12CXR_R6_A_SOURCE_SHA")
	if output_path.is_empty() or source_sha.is_empty() or FileAccess.file_exists(output_path):
		_fail("r6_a_output_or_source_identity_invalid", {"output_path": output_path, "source_sha": source_sha, "already_exists": FileAccess.file_exists(output_path)})
		return
	var manifest: Dictionary = Core.load_manifest()
	if not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != MANIFEST_SHA:
		_fail("r6_a_manifest_identity_mismatch", {"valid": manifest.get("valid", false), "sha256": manifest.get("sha256", "")})
		return
	var row: Dictionary = Core.case_by_id(manifest.get("rows", []), TARGET_ID)
	if row.is_empty():
		_fail("r6_a_target_missing", {"target_id": TARGET_ID})
		return
	var snapshot_result: Dictionary = Core.make_snapshot(row)
	if not bool(snapshot_result.get("valid", false)):
		_fail("r6_a_snapshot_invalid", snapshot_result)
		return
	var stage0_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/stage0-topology.json")
	var residual_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r4/residual-c6.json")
	var cavity_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/fixtures/r12_cxr_r5/frozen-cavity.json")
	var candidate_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
	if Core.sha256(stage0_bytes) != STAGE0_SHA or Core.sha256(residual_bytes) != RESIDUAL_SHA or Core.sha256(candidate_bytes) != CANDIDATE_SHA or Core.sha256(cavity_bytes) != CAVITY_SHA:
		_fail("r6_a_frozen_input_hash_mismatch", {"stage0": Core.sha256(stage0_bytes), "residual": Core.sha256(residual_bytes), "candidate": Core.sha256(candidate_bytes), "cavity": Core.sha256(cavity_bytes)})
		return
	var stage0_value: Variant = JSON.parse_string(stage0_bytes.get_string_from_utf8())
	if typeof(stage0_value) != TYPE_DICTIONARY:
		_fail("r6_a_topology_fixture_schema_invalid", {})
		return
	var stage0: Dictionary = stage0_value
	var topology: Dictionary = stage0.get("topology_authority", {})
	if Core.sha256(JSON.stringify(topology).to_utf8_buffer()) != GRAPH_SHA or String(stage0.get("source_topology_sha256", "")) != TOPOLOGY_SHA:
		_fail("r6_a_topology_identity_mismatch", {"graph_sha256": Core.sha256(JSON.stringify(topology).to_utf8_buffer()), "topology_sha256": stage0.get("source_topology_sha256", "")})
		return
	var candidate: RefCounted = CandidateD.new()
	var roi: Dictionary = row.get("roi", {})
	candidate.call("configure_roi", roi)
	var volume_case: Dictionary = candidate.call("build", snapshot_result.get("snapshot", {}), row, {"id": "R12CXR_R6_A_AUDIT"})
	if not bool(volume_case.get("valid", false)):
		_fail("r6_a_volume_build_failed", {"reason": volume_case.get("reason", ""), "detail": volume_case})
		return
	var volume: Dictionary = volume_case.get("volume", {})
	var metrics: Dictionary = volume_case.get("metrics", {}).get("volume", {})
	if String(volume.get("sha256", "")) != VOLUME_SHA or String(metrics.get("payload_sha256", "")) != PAYLOAD_SHA or int(volume.get("revision", -1)) != 2 or not bool(volume_case.get("metrics", {}).get("materialized_volume_identity_preserved", false)):
		_fail("r6_a_volume_identity_mismatch", {"volume_sha256": volume.get("sha256", ""), "payload_sha256": metrics.get("payload_sha256", ""), "revision": volume.get("revision", -1)})
		return
	var realizer: RefCounted = R6Realizer.new()
	var diagnostics: RefCounted = Diagnostics.new()
	var audit: Dictionary = diagnostics.call("audit_r6a_representability", realizer, volume.get("values", PackedFloat32Array()), roi)
	if not bool(audit.get("valid", false)):
		_fail("r6_a_representability_audit_failed", audit)
		return
	var terminal: String = "R6_A_REPRESENTABILITY_PASS" if int(audit.get("unresolved_occurrence_count", -1)) == 0 and int(audit.get("corrected_residual_over_epsilon_count", -1)) == 0 and int(audit.get("corrected_barycentric_gate_failure_count", -1)) == 0 and int(audit.get("zero_vertex_occurrences", -1)) == D0_VERTEX_OCCURRENCES and int(audit.get("original_residual_over_epsilon_count", -1)) == D0_RESIDUAL_OVER_EPSILON else "R6_A_REPRESENTABILITY_PARTIAL"
	var result: Dictionary = {"schema": "P3.1.R12CXR.R6.Audit.v1", "campaign": "R12-CXR R6-A binary32 zero-set representability correction", "source_sha": source_sha, "target_id": TARGET_ID, "target_attempt_consumed": false, "terminal": terminal, "frozen_input_identities": {"manifest_sha256": manifest.sha256, "candidate_d_source_sha256": CANDIDATE_SHA, "topology_fixture_sha256": STAGE0_SHA, "topology_authority_sha256": TOPOLOGY_SHA, "topology_graph_sha256": GRAPH_SHA, "residual_fixture_sha256": RESIDUAL_SHA, "materialized_volume_sha256": VOLUME_SHA, "materialized_payload_sha256": PAYLOAD_SHA, "materialized_volume_revision": 2, "frozen_cavity_sha256": CAVITY_SHA}, "invariants": {"initial_search_ulp_bound_per_coordinate": 2, "field_residual_epsilon": 1.0e-7, "barycentric_epsilon": 1.0e-7, "arbitrary_projection": false, "epsilon_relaxed": false}, "R6_A": audit, "global_infeasibility_claimed": false}
	var result_bytes: PackedByteArray = JSON.stringify(diagnostics.call("json_safe", result), "\t", false).to_utf8_buffer()
	var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		_fail("r6_a_output_open_failed", {"path": output_path, "error": FileAccess.get_open_error()})
		return
	output.store_buffer(result_bytes)
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK:
		_fail("r6_a_output_write_failed", {"error": write_error})
		return
	print("R12CXR_R6_A_AUDIT_COMPLETE " + JSON.stringify({"source_sha": source_sha, "terminal": terminal, "occurrences": audit.get("zero_vertex_occurrences", -1), "corrected": audit.get("corrected_occurrence_count", -1), "changed": audit.get("changed_occurrence_count", -1), "unresolved": audit.get("unresolved_occurrence_count", -1), "result_sha256": Core.sha256(result_bytes), "target_attempt_consumed": false}))
	quit(0)

func _fail(reason: String, detail: Dictionary) -> void:
	printerr("R12CXR_R6_A_AUDIT_FAIL " + JSON.stringify({"reason": reason, "detail": detail}))
	quit(2)
