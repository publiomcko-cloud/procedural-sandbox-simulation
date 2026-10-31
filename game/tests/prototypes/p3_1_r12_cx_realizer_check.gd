extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_cx_micropatch_realizer.gd")

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r12_cx_micropatch_realizer.gd")
	var observed_sha: String = Core.sha256(bytes)
	_check(not bytes.is_empty() and observed_sha == OS.get_environment("R12CX_EXPECTED_REALIZER_SHA256"), "physical realizer SHA pin")
	_check(Realizer.EXPECTED_RESIDUAL_FIXTURE_SHA == OS.get_environment("R12CX_EXPECTED_RESIDUAL_FIXTURE_SHA256"), "realizer and runner agree on immutable residual fixture digest")
	var realizer: RefCounted = Realizer.new()
	var limits: Dictionary = realizer.call("_limits")
	_check(int(limits.get("max_cavity_level", -1)) == 3, "cavity expansion is bounded at L3")
	_check(int(limits.get("max_cavities", -1)) == 3, "residual cavity count is bounded by residual face count")
	_check(int(limits.get("max_patch_triangles", -1)) == 64, "replacement triangle cap")
	_check(int(limits.get("max_search_states", -1)) == 4096, "search state cap")
	_check(int(limits.get("max_total_search_states", -1)) == 12288 and String(limits.get("search_state_scope", "")) == "PER_CAVITY_MAX_THREE_RESIDUAL_CAVITIES", "aggregate search state budget is explicit")
	_check(int(limits.get("max_retained_solutions", -1)) == 32, "retained solution cap")
	_check(int(limits.get("max_search_usec", -1)) == 10000000, "search wall-time cap")
	_check(int(limits.get("max_realize_usec", -1)) == 30000000, "realization wall-time cap")
	_check(int(limits.get("max_support_candidates", -1)) == 0, "support-candidate search disabled in edge-flip-only profile")
	_check(int(limits.get("max_support_vertices", -1)) == 0, "this bounded profile does not select support vertices")
	_check(float(limits.get("cutoff_squared", -1.0)) == 1.0e-12, "strict frozen cutoff unchanged")
	_check(Realizer.EXPECTED_RESIDUAL_FIXTURE_SHA != "PENDING_FIXTURE_SHA", "residual fixture pin finalized before geometry execution")
	var synthetic: Dictionary = _synthetic_sliver(realizer)
	_check(bool(synthetic.get("valid", false)) and bool(synthetic.get("search_complete", false)), "bounded synthetic local repair preflight")
	if failures.is_empty():
		print("R12CX_REALIZER_CHECK_ONLY_PASS " + JSON.stringify({"checks": checks, "failures": 0, "source_sha256": observed_sha, "limits": limits, "synthetic_repair": synthetic}))
		quit(0)
	else:
		printerr("R12CX_REALIZER_CHECK_ONLY_FAIL " + JSON.stringify({"checks": checks, "failures": failures, "source_sha256": observed_sha, "limits": limits, "synthetic_repair": synthetic}))
		quit(1)

func _synthetic_sliver(realizer: RefCounted) -> Dictionary:
	var points: Dictionary = {"a":Vector3.ZERO,"b":Vector3(1,0,0),"c":Vector3(2,1.0e-7,0),"d":Vector3(0,1,0)}
	var rows: Array[Dictionary] = [_triangle("abc",["a","b","c"],points,true),_triangle("acd",["a","c","d"],points,false)]
	var no_locked_edges: Array[String] = []
	return realizer.call("search_patch_for_test", rows, no_locked_edges, 4096)

func _triangle(id: String, ids: Array, positions: Dictionary, rejected: bool) -> Dictionary:
	var points: Array[Vector3] = [positions[ids[0]],positions[ids[1]],positions[ids[2]]]
	var cross: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	return {"triangle_id":id,"polygon_id":id,"root_ids":ids.duplicate(),"points":points,"normal":cross.normalized() if cross.length_squared()>0.0 else Vector3.ZERO,"cross_squared":cross.length_squared(),"rejected":rejected}

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
