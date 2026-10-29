extends SceneTree

const Topology := preload("res://tests/prototypes/p3_1_r9_6_surface_topology.gd")
var assertions: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_closed_pair()
	_test_rejected_geometry_keeps_required_topology()
	_test_duplicate_and_unknown_id_fail_closed()
	_test_stable_hash_and_shared_owner()
	print("R96_TOPOLOGY_TESTS " + JSON.stringify({"assertions": assertions, "failures": failures.size(), "failure_reasons": failures}))
	print("R96_TOPOLOGY_TESTS_" + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _test_closed_pair() -> void:
	var topology: RefCounted = Topology.new()
	_add_root(topology, "a", Vector3(0, 0, 0))
	_add_root(topology, "b", Vector3(1, 0, 0))
	_add_root(topology, "c", Vector3(1, 1, 0))
	_add_root(topology, "d", Vector3(0, 1, 0))
	_check(topology.add_triangle("t0", ["a", "b", "c"], "cell0", "0,0,0", ["X_MAX"]), "first triangle recorded")
	_check(topology.add_triangle("t1", ["a", "c", "d"], "cell1", "1,0,0", ["X_MAX"]), "second triangle recorded")
	_check(topology.mark_realization("t0", true, 1.0).valid, "first triangle emitted")
	_check(topology.mark_realization("t1", true, 1.0).valid, "second triangle emitted")
	var report: Dictionary = topology.report(Vector3(0, 0, -1), Vector3(1, 1, 1))
	_check(report.valid and int(report.emitted_triangle_count) == 2, "closed pair summary valid")
	_check(report.internal_open_edges.is_empty(), "interior diagonal is manifold")
	_check(report.nonmanifold_edges.is_empty(), "closed pair has no nonmanifold edge")

func _test_rejected_geometry_keeps_required_topology() -> void:
	var topology: RefCounted = Topology.new()
	_add_root(topology, "a", Vector3(0, 0, 0))
	_add_root(topology, "b", Vector3(1, 0, 0))
	_add_root(topology, "c", Vector3(1, 1, 0))
	_add_root(topology, "d", Vector3(0, 1, 0))
	topology.add_triangle("t0", ["a", "b", "c"], "cell0", "0,0,0", [])
	topology.add_triangle("t1", ["a", "c", "d"], "cell1", "1,0,0", [])
	topology.mark_realization("t0", false, 0.0, "below_frozen_cutoff")
	topology.mark_realization("t1", true, 1.0)
	var report: Dictionary = topology.report(Vector3(0, 0, -1), Vector3(1, 1, 1))
	_check(int(report.required_triangle_count) == 2, "rejected triangle remains in topology graph")
	_check(int(report.rejected_triangle_count) == 1 and report.rejected_triangle_ids == ["t0"], "rejection is explicit")
	_check(not report.missing_required_adjacency.is_empty(), "missing realization is reported")
	_check(not report.internal_open_edges.is_empty(), "cutoff omission exposes internal opens")
	_check(report.rejection_reasons.get("below_frozen_cutoff", 0) == 1, "reason retained")

func _test_duplicate_and_unknown_id_fail_closed() -> void:
	var topology: RefCounted = Topology.new()
	_check(topology.add_root("r", Vector3.ZERO, "owner").valid, "first root accepted")
	var collision: Dictionary = topology.add_root("r", Vector3.RIGHT, "owner")
	_check(not collision.valid and collision.reason == "root_identity_collision", "root identity collision rejected")
	var unknown: Dictionary = topology.add_triangle("bad", ["r", "x", "y"], "cell", "0,0,0", [])
	_check(not unknown.valid and unknown.reason == "triangle_references_unknown_root", "unknown root rejected")
	_check(topology.add_root("x", Vector3.UP, "owner").valid, "second root added")
	_check(topology.add_root("y", Vector3.BACK, "owner").valid, "third root added")
	_check(topology.add_triangle("ok", ["r", "x", "y"], "cell", "0,0,0", []).valid, "valid triangle added")
	var duplicate: Dictionary = topology.add_triangle("ok", ["r", "x", "y"], "cell", "0,0,0", [])
	_check(not duplicate.valid and duplicate.reason == "duplicate_triangle_id", "duplicate triangle identity rejected")

func _test_stable_hash_and_shared_owner() -> void:
	var forward: RefCounted = _make_owned_face_topology(false)
	var reverse: RefCounted = _make_owned_face_topology(true)
	var bounds_min := Vector3(-1, -1, -1)
	var bounds_max := Vector3(0, 1, 1)
	var a: Dictionary = forward.report(bounds_min, bounds_max)
	var b: Dictionary = reverse.report(bounds_min, bounds_max)
	_check(a.topology_sha256 == b.topology_sha256, "topology hash independent of insertion order")
	var owner_found := false
	for arc in a.required_surface_arcs:
		if String(arc.face_owner) == "ROI_MAX_AXIS_0":
			owner_found = true
	_check(owner_found, "shared ROI face ownership is recorded")

func _make_owned_face_topology(reverse: bool) -> RefCounted:
	var topology: RefCounted = Topology.new()
	var roots := [["a", Vector3(0, 0, 0)], ["b", Vector3(0, 1, 0)], ["c", Vector3(0, 1, 1)], ["d", Vector3(0, 0, 1)]]
	if reverse:
		roots.reverse()
	for row in roots:
		_check(topology.add_root(String(row[0]), row[1], "x_face_owner").valid, "face root inserted")
	var triangles: Array = [["t0", ["a", "b", "c"]], ["t1", ["a", "c", "d"]]]
	if reverse:
		triangles.reverse()
	for row in triangles:
		topology.add_triangle(String(row[0]), row[1], "x_face_owner", "face-cell", ["X_MAX"])
		topology.mark_realization(String(row[0]), true, 1.0)
	return topology

func _add_root(topology: RefCounted, root_id: String, point: Vector3) -> void:
	_check(topology.add_root(root_id, point, "cell-owner").valid, "root " + root_id + " inserted")

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
