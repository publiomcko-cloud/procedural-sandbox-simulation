extends SceneTree

const Topology := preload("res://tests/prototypes/p3_1_r9_6_surface_topology.gd")
var assertions: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_adjacent_pair()
	_test_rejected_geometry_keeps_required_topology()
	_test_duplicate_and_unknown_id_fail_closed()
	_test_stable_hash_and_shared_owner()
	print("R96_TOPOLOGY_TESTS " + JSON.stringify({"assertions": assertions, "failures": failures.size(), "failure_reasons": failures}))
	print("R96_TOPOLOGY_TESTS_" + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _test_adjacent_pair() -> void:
	var topology: Variant = Topology.new()
	_add_root(topology, "a", Vector3(0, 0, 0))
	_add_root(topology, "b", Vector3(1, 0, 0))
	_add_root(topology, "c", Vector3(1, 1, 0))
	_add_root(topology, "d", Vector3(0, 1, 0))
	_check(topology.add_triangle("t0", _string_array(["a", "b", "c"]), "cell0", "0,0,0", _string_array(["X_MAX"])).valid, "first triangle recorded")
	_check(topology.add_triangle("t1", _string_array(["a", "c", "d"]), "cell1", "1,0,0", _string_array(["X_MAX"])).valid, "second triangle recorded")
	_check(topology.mark_realization("t0", true, 1.0).valid, "first triangle emitted")
	_check(topology.mark_realization("t1", true, 1.0).valid, "second triangle emitted")
	var report: Dictionary = topology.report(Vector3(0, 0, -1), Vector3(1, 1, 1))
	_check(report.valid and int(report.emitted_triangle_count) == 2, "closed pair summary valid")
	_check(report.internal_open_edges.is_empty(), "interior diagonal is manifold")
	_check(report.nonmanifold_edges.is_empty(), "closed pair has no nonmanifold edge")
	_check(report.surface_components.size() == 1, "adjacent triangles form one surface component")
	_check(report.roi_boundary_open_edges.size() == 4, "quad perimeter remains four explicit ROI boundary edges")
	var open_edge_components: Array = report.surface_loops
	_check(open_edge_components.size() == 1, "quad perimeter forms one connected open-edge component")
	if open_edge_components.size() == 1:
		var perimeter: Dictionary = open_edge_components[0]
		_check(not bool(perimeter.closed_loop) and bool(perimeter.touches_roi_boundary), "quad perimeter is a domain boundary, not an internal closed surface loop")
	else:
		_check(false, "quad perimeter component metadata unavailable")

func _test_rejected_geometry_keeps_required_topology() -> void:
	var topology: Variant = Topology.new()
	_add_root(topology, "a", Vector3(0, 0, 0))
	_add_root(topology, "b", Vector3(1, 0, 0))
	_add_root(topology, "c", Vector3(1, 1, 0))
	_add_root(topology, "d", Vector3(0, 1, 0))
	topology.add_triangle("t0", _string_array(["a", "b", "c"]), "cell0", "0,0,0", _string_array([]))
	topology.add_triangle("t1", _string_array(["a", "c", "d"]), "cell1", "1,0,0", _string_array([]))
	topology.mark_realization("t0", false, 0.0, "below_frozen_cutoff")
	topology.mark_realization("t1", true, 1.0)
	var report: Dictionary = topology.report(Vector3(0, 0, -1), Vector3(1, 1, 1))
	_check(int(report.required_triangle_count) == 2, "rejected triangle remains in topology graph")
	_check(int(report.rejected_triangle_count) == 1 and report.rejected_triangle_ids == ["t0"], "rejection is explicit")
	_check(report.valid and not report.geometry_realization_complete, "well-formed topology does not imply emitted-geometry acceptance")
	_check(not report.missing_required_adjacency.is_empty(), "missing realization is reported")
	_check(not report.internal_open_edges.is_empty(), "cutoff omission exposes internal opens")
	_check(report.rejection_reasons.get("below_frozen_cutoff", 0) == 1, "reason retained")
	_check(report.surface_components.size() == 1, "required topology remains one surface component")
	_check(not report.surface_loops.is_empty(), "partial realization is grouped into open-edge diagnostics")

func _test_duplicate_and_unknown_id_fail_closed() -> void:
	var topology: Variant = Topology.new()
	_check(topology.add_root("r", Vector3.ZERO, "owner").valid, "first root accepted")
	var collision: Dictionary = topology.add_root("r", Vector3.RIGHT, "owner")
	_check(not collision.valid and collision.reason == "root_identity_collision", "root identity collision rejected")
	var unknown: Dictionary = topology.add_triangle("bad", _string_array(["r", "x", "y"]), "cell", "0,0,0", _string_array([]))
	_check(not unknown.valid and unknown.reason == "triangle_references_unknown_root", "unknown root rejected")
	_check(topology.add_root("x", Vector3.UP, "owner").valid, "second root added")
	_check(topology.add_root("y", Vector3.BACK, "owner").valid, "third root added")
	_check(topology.add_triangle("ok", _string_array(["r", "x", "y"]), "cell", "0,0,0", _string_array([])).valid, "valid triangle added")
	var duplicate: Dictionary = topology.add_triangle("ok", _string_array(["r", "x", "y"]), "cell", "0,0,0", _string_array([]))
	_check(not duplicate.valid and duplicate.reason == "duplicate_triangle_id", "duplicate triangle identity rejected")

func _test_stable_hash_and_shared_owner() -> void:
	var forward: Variant = _make_owned_face_topology(false)
	var reverse: Variant = _make_owned_face_topology(true)
	var bounds_min := Vector3(-1, -1, -1)
	var bounds_max := Vector3(0, 1, 1)
	var a: Dictionary = forward.report(bounds_min, bounds_max)
	var b: Dictionary = reverse.report(bounds_min, bounds_max)
	_check(a.topology_sha256 == b.topology_sha256, "topology hash independent of insertion order")
	var owner_found := false
	for arc in a.required_surface_arcs:
		if String(arc.shared_face_key) == "ROI_MAX_AXIS_0" and String(arc.canonical_owner) == "x_face_owner":
			owner_found = true
	_check(owner_found, "shared ROI face ownership is recorded")

func _make_owned_face_topology(reverse: bool) -> Variant:
	var topology: Variant = Topology.new()
	var roots := [["a", Vector3(0, 0, 0)], ["b", Vector3(0, 1, 0)], ["c", Vector3(0, 1, 1)], ["d", Vector3(0, 0, 1)]]
	if reverse:
		roots.reverse()
	for row in roots:
		_check(topology.add_root(String(row[0]), row[1], "x_face_owner").valid, "face root inserted")
	var triangles: Array = [["t0", ["a", "b", "c"]], ["t1", ["a", "c", "d"]]]
	if reverse:
		triangles.reverse()
	for row in triangles:
		topology.add_triangle(String(row[0]), _string_array(row[1]), "x_face_owner", "face-cell", _string_array(["X_MAX"]))
		topology.mark_realization(String(row[0]), true, 1.0)
	return topology

func _add_root(topology: Variant, root_id: String, point: Vector3) -> void:
	_check(topology.add_root(root_id, point, "cell-owner").valid, "root " + root_id + " inserted")

func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if typeof(value) != TYPE_STRING:
			failures.append("topology test fixture contains a non-string identity")
			continue
		result.append(String(value))
	return result

func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
