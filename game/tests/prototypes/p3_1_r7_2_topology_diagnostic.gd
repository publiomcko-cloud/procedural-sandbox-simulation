extends SceneTree

## Reproduces the frozen R7.1 zero-edit defect and compares three bounded,
## test-only local mesh repair strategies. No production scene or save is used.
const Fixture := preload("res://tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd")
const Repair := preload("res://tests/prototypes/p3_1_r7_2_local_retriangulation.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")

const SEED := 131102026
const FOCUS_IDS: Array[int] = [1101, 1149, 1150, 1199]
const STRATEGIES := ["A_edge_collapse", "B_constrained_cavity", "C_boundary_patch_remesh"]
var _assertions := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture := Fixture.new()
	var repair := Repair.new()
	_check(fixture.configure(SEED, {}), "frozen_zero_snapshot_configures")
	if not _failures.is_empty():
		_finish({})
		return
	var selected := _selected_cells(fixture)
	_check(fixture._materialize_fine_cells(selected), "focus_and_neighbor_samples_materialize")
	var sample_count := 0
	var exact_zero_samples := 0
	for cell_id_value in selected:
		var sample_values: PackedFloat32Array = fixture.refined_cells[int(cell_id_value)]
		sample_count += sample_values.size()
		for sample_value in sample_values:
			if float(sample_value) == 0.0: exact_zero_samples += 1
	_check(sample_count == 621, "four_focus_cells_and_neighbors_reproduce_621_original_float32_samples")
	_check(exact_zero_samples == 0, "minimal_fixture_has_no_exact_zero_samples")
	_check(fixture.configure_r71_polygonizer("production", "production", "production"), "production_cutoff_mode_configures")
	var production_cells := _build_selected_cells(fixture, selected)
	_check(not production_cells.is_empty(), "production_cutoff_control_mesh_builds")
	var production_local: Dictionary = repair.extract_local_mesh(fixture, production_cells, FOCUS_IDS)
	var production_stats: Dictionary = repair.metrics(fixture, production_local)
	_check(int(production_stats.get("internal_open_edges", -1)) == 14, "production_cutoff_control_reproduces_14_internal_open_edges")
	_check(int(production_stats.get("degenerate_triangles", -1)) == 0, "production_cutoff_control_retains_degeneracy_filter")
	_check(fixture.configure_r71_polygonizer("mirror_production", "reject_only_exact_zero", "production"), "inclusive_nonzero_control_mode_configures")
	var inclusive_cells := _build_selected_cells(fixture, selected)
	_check(not inclusive_cells.is_empty(), "inclusive_microtriangle_mesh_builds")
	var local := repair.extract_local_mesh(fixture, inclusive_cells, FOCUS_IDS)
	var raw_stats: Dictionary = repair.metrics(fixture, local)
	var source_triangle_count := int(local.faces.size())
	_check(raw_stats.degenerate_triangles == 8 and raw_stats.nonzero_subthreshold_triangles == 8,
		"fixture_contains_exactly_8_nonzero_subthreshold_microtriangles")
	_check(raw_stats.internal_open_edges == 0, "retained_microtriangle_control_closes_internal_incidence")
	var local_subthreshold_by_owner := _subthreshold_counts(local)
	_check(int(local_subthreshold_by_owner.get("1101", 0)) == 3
		and int(local_subthreshold_by_owner.get("1149", 0)) == 2
		and int(local_subthreshold_by_owner.get("1150", 0)) == 1
		and int(local_subthreshold_by_owner.get("1199", 0)) == 2,
		"eight_nonzero_subthreshold_faces_match_frozen_cell_ownership")
	var strategy_results: Array[Dictionary] = []
	for strategy in STRATEGIES:
		var result: Dictionary = repair.run_strategy(fixture, local, String(strategy))
		strategy_results.append(result)
		print("R72_STRATEGY " + JSON.stringify(result))
	var result_by_name: Dictionary = {}
	for result in strategy_results: result_by_name[String(result.strategy)] = result
	var strategy_a: Dictionary = result_by_name.get("A_edge_collapse", {})
	var strategy_b: Dictionary = result_by_name.get("B_constrained_cavity", {})
	var strategy_c: Dictionary = result_by_name.get("C_boundary_patch_remesh", {})
	_check(bool(strategy_a.get("valid", false)), "strategy_a_preserves_all_local_topology_and_boundary_invariants")
	_check(bool(strategy_b.get("valid", false)), "strategy_b_preserves_all_local_topology_and_boundary_invariants")
	_check(not bool(strategy_c.get("valid", false))
		and String(strategy_c.get("strategy_attempt", {}).get("reason", "")) == "cavity_boundary_not_disjoint_loops",
		"strategy_c_is_rejected_for_non_loop_cavity_boundary")
	var fixture_payload := _frozen_fixture_payload(fixture, local, raw_stats, production_stats)
	print("R72_MINIMAL_FIXTURE " + JSON.stringify(fixture_payload))
	var at_least_one_valid := bool(strategy_a.get("valid", false)) or bool(strategy_b.get("valid", false))
	_check(at_least_one_valid, "at_least_one_local_repair_strategy_passes_all_mandatory_invariants")
	var summary := {"suite": "P3_1_R7_2_MINIMAL_TOPOLOGY_FIXTURE", "status": "PASS" if at_least_one_valid and _failures.is_empty() else "FAIL",
		"assertions": _assertions, "failures": _failures, "seed": SEED,
		"focus_cell_ids": FOCUS_IDS, "neighbor_cell_count": local.selected.size(),
		"production_cutoff_control": production_stats, "inclusive_microtriangle_control": raw_stats,
		"source_triangle_count": source_triangle_count,
		"strategy_results": _summaries(strategy_results),
		"threshold_cross_squared": 1.0e-12,
		"stop_gate": "STOP_IF_NO_STRATEGY_PASSES_ALL_TOPOLOGY_INVARIANTS",
		"strategy_policy": "each strategy is evaluated independently; rejected strategies remain visible; the fixture gate passes only when at least one candidate satisfies every mandatory invariant"}
	print("R72_RESULT " + JSON.stringify(summary))
	quit(0 if at_least_one_valid and _failures.is_empty() else 1)

func _frozen_fixture_payload(fixture: RefCounted, mesh: Dictionary, inclusive_stats: Dictionary, production_stats: Dictionary) -> Dictionary:
	var sample_records: Array[Dictionary] = []
	for cell_id_value in mesh.selected:
		var cell_id := int(cell_id_value)
		var values: PackedFloat32Array = fixture.refined_cells.get(cell_id, PackedFloat32Array())
		var cell: Vector3i = fixture._cell_from_id(cell_id)
		if values.size() != 27:
			continue
		for i in range(values.size()):
			var value: float = values[i]
			sample_records.append({"cell_id": cell_id, "cell": [cell.x, cell.y, cell.z], "sample_index": i,
				"binary32": value, "bits_le_hex": "0x%08x" % PackedFloat32Array([value]).to_byte_array().decode_u32(0)})
	var triangles: Array[Dictionary] = []
	for face in mesh.faces:
		var ids: Array = face.v
		var vertices: Array[Vector3] = mesh.vertices
		var a: Vector3 = vertices[int(ids[0])]
		var b: Vector3 = vertices[int(ids[1])]
		var c: Vector3 = vertices[int(ids[2])]
		var cross := (b - a).cross(c - a)
		triangles.append({"owner_cell_id": int(face.cell), "vertex_ids": ids,
			"world_vertices": [_v3(a), _v3(b), _v3(c)], "winding_cross": _v3(cross),
			"cross_length_squared": cross.length_squared()})
	var zero_triangle_count := 0
	for tetra in Mesher.TETRAHEDRA: zero_triangle_count += 0 if tetra.is_empty() else 1
	return {"fixture_id": "P3.1.R7.ZERO_EDIT.v1", "seed": SEED, "revision": 0, "commands": [],
		"canonical_opening_world": 1.75, "focus_cells": FOCUS_IDS,
		"selected_cells": mesh.selected.keys(), "selected_cell_count": mesh.selected.size(),
		"grid": {"patch_min": _v3(Fixture.PATCH_MIN), "coarse_step": Fixture.COARSE_STEP,
			"fine_step": Fixture.FINE_STEP, "cell_dims": [Fixture.CELL_DIMS.x, Fixture.CELL_DIMS.y, Fixture.CELL_DIMS.z]},
		"production_tetrahedra": Mesher.TETRAHEDRA, "production_corners": Mesher.CORNERS,
		"sample_count": sample_records.size(), "samples": sample_records,
		"production_cutoff_control": production_stats, "inclusive_control": inclusive_stats,
		"triangle_count": triangles.size(), "triangles": triangles,
		"sample_identity_note": "binary32 field samples from the frozen R7 fixture; each bits_le_hex records exact IEEE-754 encoding",
		"topology_note": "selected four focus cells plus their in-bounds six-face neighbors; exposed selected-domain boundary edges are classified separately"}

func _selected_cells(fixture: RefCounted) -> Dictionary:
	var selected: Dictionary = {}
	for id in FOCUS_IDS:
		selected[id] = true
		var cell: Vector3i = fixture._cell_from_id(id)
		for direction in fixture.FACE_DIRECTIONS:
			var neighbor: Vector3i = cell + Vector3i(direction.delta)
			if fixture._cell_in_bounds(neighbor): selected[fixture._cell_id(neighbor)] = true
	return selected

func _build_selected_cells(fixture: RefCounted, selected: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for id_value in selected:
		var id := int(id_value)
		var cell: Vector3i = fixture._cell_from_id(id)
		var geometry: Dictionary = fixture._build_fine_cell(cell, fixture.refined_cells[id])
		if int(geometry.get("triangle_count", 0)) > 0: output[id] = geometry
	return output

func _subthreshold_counts(mesh: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	var vertices: Array[Vector3] = mesh.vertices
	for face in mesh.faces:
		var ids: Array = face.v
		var a: Vector3 = vertices[int(ids[0])]
		var b: Vector3 = vertices[int(ids[1])]
		var c: Vector3 = vertices[int(ids[2])]
		var cross_squared := (b - a).cross(c - a).length_squared()
		if cross_squared > 0.0 and cross_squared <= 1.0e-12:
			var key := str(face.cell)
			counts[key] = int(counts.get(key, 0)) + 1
	return counts

func _summaries(results: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for result in results:
		output.append({"strategy": result["strategy"], "valid": result["valid"],
			"disposition": result["disposition"], "strategy_attempt": result["strategy_attempt"],
			"after": result["after"], "external_boundary_unchanged": result["external_boundary_unchanged"],
			"surface_metrics": result["surface_metrics"]})
	return output

func _v3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _check(condition: bool, name: String) -> void:
	_assertions += 1
	if not condition: _failures.append(name)

func _finish(data: Dictionary) -> void:
	print("R72_RESULT " + JSON.stringify({"suite": "P3_1_R7_2_MINIMAL_TOPOLOGY_FIXTURE",
		"status": "FAIL", "assertions": _assertions, "failures": _failures, "partial": data}))
	quit(1)
