extends SceneTree

const SolverScript := preload("res://tests/prototypes/p3_1_r10_bx_conflict_solver.gd")

var _assertions: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var solver: RefCounted = SolverScript.new()
	_test_pairwise_geometry(solver)
	_test_conflict_bitset(solver)
	if _failures.is_empty():
		print("R10BX_UNIT_TESTS_PASS " + JSON.stringify({"assertions": _assertions, "failures": 0}))
		quit(0)
	else:
		printerr("R10BX_UNIT_TESTS_FAIL " + JSON.stringify({"assertions": _assertions, "failures": _failures}))
		quit(1)

func _test_pairwise_geometry(solver: RefCounted) -> void:
	var points: Array = [
		Vector2(0.0, 0.0), Vector2(2.0, 0.0), Vector2(0.0, 2.0),
		Vector2(1.0, -1.0), Vector2(3.0, 1.0), Vector2(1.0, 1.0),
		Vector2(0.2, 0.2), Vector2(0.6, 0.2), Vector2(0.2, 0.6),
		Vector2(-2.0, 0.0), Vector2(0.0, -2.0),
		Vector2(4.0, 4.0), Vector2(5.0, 4.0), Vector2(4.0, 5.0), Vector2(1.0, 0.0),
		Vector2(1.6, 1.6), Vector2(2.0, 2.0), Vector2(1.6, 2.0)
	]
	var crossing: int = int(solver.call("_geometry_conflict_flags", [0, 1, 2], [3, 4, 5], points))
	_assert((crossing & int(SolverScript.CATEGORY_CROSSING)) != 0, "proper projected edge crossing classified")
	var containment: int = int(solver.call("_geometry_conflict_flags", [0, 1, 2], [6, 7, 8], points))
	_assert((containment & int(SolverScript.CATEGORY_CONTAINMENT)) != 0, "strict triangle containment classified")
	var shared_edge_opposite: int = int(solver.call("_geometry_conflict_flags", [0, 1, 2], [1, 0, 10], points))
	_assert(shared_edge_opposite == 0, "oppositely directed legal shared edge remains geometrically compatible")
	var shared_vertex_only: int = int(solver.call("_geometry_conflict_flags", [0, 1, 2], [0, 9, 10], points))
	_assert(shared_vertex_only == 0, "vertex-only contact is not a geometric conflict")
	var shared_root_overlap: int = int(solver.call("_geometry_conflict_flags", [0, 1, 2], [0, 14, 10], points))
	_assert((shared_root_overlap & int(SolverScript.CATEGORY_CROSSING)) != 0, "same-ray collinear overlap through a shared root is a T-junction conflict")
	var distinct_root_t_junction: int = int(solver.call("_geometry_conflict_flags", [0, 1, 2], [14, 3, 10], points))
	_assert((distinct_root_t_junction & int(SolverScript.CATEGORY_CROSSING)) != 0, "distinct root endpoint on an edge is a T-junction conflict")
	_assert(bool(solver.call("_edge_geometry_conflict", 0, 1, 0, 14, points)), "unique-edge index detects shared-root same-ray overlap")
	_assert(not bool(solver.call("_edge_geometry_conflict", 0, 1, 0, 9, points)), "unique-edge index allows opposite rays meeting only at shared root")
	var indexed_matrix: PackedByteArray = PackedByteArray(); indexed_matrix.resize(36)
	var edges: Array = [[0, 1], [1, 2], [2, 0], [3, 4], [4, 5], [5, 3]]
	for edge_a in range(3):
		for edge_b in range(3, 6):
			if bool(solver.call("_edge_geometry_conflict", edges[edge_a][0], edges[edge_a][1], edges[edge_b][0], edges[edge_b][1], points)):
				indexed_matrix[edge_a * 6 + edge_b] = 1
				indexed_matrix[edge_b * 6 + edge_a] = 1
	var center_a: Vector2 = (points[0] + points[1] + points[2]) / 3.0
	var center_b: Vector2 = (points[3] + points[4] + points[5]) / 3.0
	var indexed_flags: int = int(solver.call("_indexed_pair_flags", [0, 1, 2], [3, 4, 5], [0, 1, 2], [3, 4, 5], indexed_matrix, 6, points, center_a, center_b))
	_assert(indexed_flags == crossing, "indexed unique-edge matrix reproduces candidate-pair conflict categories")
	var disjoint: int = int(solver.call("_geometry_conflict_flags", [0, 1, 2], [11, 12, 13], points))
	_assert(disjoint == 0, "disjoint candidate triangles remain compatible")
	var center_disjoint_a: Vector2 = (points[0] + points[1] + points[2]) / 3.0
	var center_disjoint_b: Vector2 = (points[15] + points[16] + points[17]) / 3.0
	_assert(not bool(solver.call("_triangle_pair_may_overlap_axis", [0, 1, 2], [15, 16, 17], points, center_disjoint_a, center_disjoint_b)), "centroid-axis filter rejects closed-disjoint triangles with overlapping AABBs")
	_assert(bool(solver.call("_triangle_pair_may_overlap_axis", [0, 1, 2], [3, 4, 5], points, center_a, center_b)), "centroid-axis filter retains a crossing triangle pair")
	var center_shared: Vector2 = (points[1] + points[0] + points[10]) / 3.0
	_assert(bool(solver.call("_triangle_pair_may_overlap_axis", [0, 1, 2], [1, 0, 10], points, center_a, center_shared)), "centroid-axis filter retains exact shared-edge contact")
	_assert(bool(solver.call("_segments_intersect", Vector2(0, 0), Vector2(2, 0), Vector2(1, -1), Vector2(1, 1))), "segment oracle detects proper crossing")
	_assert(bool(solver.call("_segments_intersect", Vector2(0, 0), Vector2(2, 0), Vector2(2, 0), Vector2(3, 1))), "inclusive segment primitive reports endpoint contact for caller-level ownership classification")

func _test_conflict_bitset(solver: RefCounted) -> void:
	var count: int = 17
	var stride: int = (count + 7) >> 3
	var mask: PackedByteArray = PackedByteArray(); mask.resize(count * stride)
	var categories: PackedByteArray = PackedByteArray(); categories.resize(count * count)
	var crossing: int = int(SolverScript.CATEGORY_CROSSING)
	solver.call("_set_conflict", 1, 16, crossing, mask, categories, stride, count)
	_assert(bool(solver.call("_bit_is_set", mask, stride, 16)), "forward conflict bit is set")
	_assert(bool(solver.call("_bit_is_set", mask, 16 * stride, 1)), "reverse conflict bit is symmetric")
	_assert(not bool(solver.call("_bit_is_set", mask, stride, 1)), "self-conflict bit remains clear")
	_assert(int(categories[1 * count + 16]) == crossing and int(categories[16 * count + 1]) == crossing, "category matrix is symmetric")
	var popcounts: PackedInt32Array = solver.get("_popcount")
	_assert(int(popcounts[0]) == 0 and int(popcounts[255]) == 8 and int(popcounts[0b10100101]) == 4, "byte popcount table exact")

func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition: _failures.append(label)
