extends "res://tests/prototypes/p3_1_r7_2_zero_edit_gate.gd"

## R8 is an isolated measurement harness. It reuses only the frozen R7.3 test
## fixture and disposable collision oracle; it never instantiates production
## terrain nodes or writes user saves.
const SpatialR8 := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const GridR8 := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const LodMesherR8 := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const MesherR8 := preload("res://scripts/terrain/marching_tetrahedra.gd")
const RepairR8 := preload("res://tests/prototypes/p3_1_r7_2_local_retriangulation.gd")
const FLOOD_DIRECTIONS_R8: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT,
	Vector3i.DOWN, Vector3i.UP, Vector3i(0, 0, -1), Vector3i(0, 0, 1)]
const INPUT_SHA_ZERO := "24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b"
const INPUT_SHA_CARVE := "47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411"
const INPUT_SHA_FILL_CARVE := "55d45d387bd19829bb38c4e988da25a886765f26cc34e19dd07ed808faa1bd46"
const R8_MAX_SECONDS := 900.0
const FIELD_BOX_MIN := Vector3(7.5, -2.0, 3.5)
const FIELD_BOX_MAX := Vector3(12.5, 8.0, 8.5)
const FIELD_STEP := 0.125
const NORMAL_EPSILON := 0.01
const SEAM_EPSILON := 0.00001

var _r8_started_usec := 0
var _r8_assertions := 0
var _r8_failures: Array[String] = []
var _r8_phase_records: Array[Dictionary] = []
var _r8_fill_snapshot: Dictionary = {}
var _r8_fill_mesh: Dictionary = {}
var _r8_fill_fixture: RefCounted
var _r8_approach_meshes: Dictionary = {}
var _r8_evidence_dir := ""


func _run() -> void:
	_r8_started_usec = Time.get_ticks_usec()
	_r8_evidence_dir = OS.get_environment("P31_R8_EVIDENCE_DIR")
	var preflight := _r8_preflight()
	_r8_emit("preflight", preflight)
	if not bool(preflight.get("valid", false)):
		_r8_finish("BLOCKED", "frozen_source_or_input_identity_failed")
		return
	var cave := _r8_cave_connectivity()
	_r8_emit("cave_connectivity", cave)
	if not bool(cave.get("valid", false)):
		_r8_finish("BLOCKED", "canonical_connectivity_diagnostic_incomplete")
		return
	var normals := _r8_normal_quality()
	_r8_emit("normal_quality", normals)
	if not bool(normals.get("valid", false)):
		_r8_finish("BLOCKED", "normal_diagnostic_incomplete")
		return
	var chunks: Dictionary = _r8_chunk_conformance()
	_r8_emit("chunk_conformance", chunks)
	if not bool(chunks.get("valid", false)):
		_r8_finish("BLOCKED", "chunk_diagnostic_incomplete")
		return
	var resolution := _r8_resolution_sweep()
	_r8_emit("resolution_sweep", resolution)
	if not bool(resolution.get("valid", false)):
		_r8_finish("BLOCKED", "resolution_diagnostic_incomplete")
		return
	var collision: Dictionary = _r8_collision_consistency()
	_r8_emit("collision_consistency", collision)
	if not bool(collision.get("valid", false)):
		_r8_finish("BLOCKED", "collision_diagnostic_incomplete")
		return
	_r8_finish("DIAGNOSTIC_COMPLETE", "exploratory_geometry_only_no_tolerance_adopted")


func _r8_preflight() -> Dictionary:
	var expected := {"zero_edit": INPUT_SHA_ZERO, "cave_wall_carve": INPUT_SHA_CARVE,
		"center_fill_then_wall_carve": INPUT_SHA_FILL_CARVE}
	var records: Array[Dictionary] = []
	for scenario in ["zero_edit", "cave_wall_carve", "center_fill_then_wall_carve"]:
		var snapshot_result: Dictionary = _make_snapshot(String(scenario))
		if not bool(snapshot_result.get("valid", false)):
			return {"valid": false, "reason": "frozen_snapshot_invalid:%s" % scenario}
		var snapshot: Dictionary = snapshot_result.snapshot
		var payload: Dictionary = _scenario_input_payload(String(scenario), snapshot)
		var canonical_json := JSON.stringify(payload)
		var digest := _sha256(canonical_json.to_utf8_buffer())
		var record := {"scenario": scenario, "input_sha256": digest,
			"expected_input_sha256": expected[String(scenario)], "canonical_json": canonical_json,
			"revision": int(snapshot.get("revision", -1)),
			"operation_count": snapshot.get("centers", PackedVector3Array()).size()}
		record["pin_match"] = digest == expected[String(scenario)]
		records.append(record)
		if digest != expected[String(scenario)]:
			return {"valid": false, "reason": "frozen_manifest_digest_mismatch:%s" % scenario, "records": records}
		if scenario == "center_fill_then_wall_carve":
			_r8_fill_snapshot = snapshot
	var source_paths := [
		"res://tests/prototypes/p3_1_r7_conforming_adaptive_diagnostic.gd",
		"res://tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd",
		"res://tests/prototypes/p3_1_r7_2_zero_edit_gate.gd",
		"res://tests/prototypes/p3_1_r7_2_local_retriangulation.gd",
		"res://tests/prototypes/p3_1_r7_3_minimal_carve_repair.gd",
		"res://scripts/experiments/lod01_transition_fixture.gd",
		"res://scripts/terrain/sdf_world.gd",
		"res://scripts/terrain/sdf_brush_edit_state.gd",
		"res://scripts/terrain/marching_tetrahedra.gd",
		"res://scripts/terrain/lod01_chunk_mesher.gd",
		"res://scripts/terrain/terrain_chunk_grid.gd",
		"res://scripts/terrain/terrain_spatial_ownership.gd"]
	var source_hashes: Dictionary = {}
	for path in source_paths:
		source_hashes[String(path)] = _sha256(FileAccess.get_file_as_bytes(String(path)))
	return {"valid": true, "scenario_manifests": records,
		"source_sha256_by_path": source_hashes,
		"source_contract": "R7.3_tested_source_7ad45d8c817ecb0f54a8eec058babce65af287db",
		"godot_version": Engine.get_version_info(), "assertions": _r8_assertions,
		"note": "Frozen input digests are recomputed from the R7.3 snapshot builder; source identity is additionally pinned by Git at the evidence level."}


func _r8_cave_connectivity() -> Dictionary:
	var fixture := Fixture.new()
	if not fixture.configure(SEED, _r8_fill_snapshot):
		return {"valid": false, "reason": "adaptive_fixture_configuration_failed"}
	if not fixture.configure_r71_polygonizer("production", "reject_only_exact_zero", "production"):
		return {"valid": false, "reason": "frozen_polygonizer_configuration_failed"}
	var approaches: Dictionary = {}
	var approach_records: Array[Dictionary] = []
	for name in APPROACHES:
		var begin := Time.get_ticks_usec()
		var built: Dictionary = fixture.build_approach(String(name))
		var elapsed := Time.get_ticks_usec() - begin
		if not bool(built.get("valid", false)):
			return {"valid": false, "reason": "approach_build_failed:%s:%s" % [name, built.get("reason", "unknown")]}
		approaches[String(name)] = built
		_r8_approach_meshes[String(name)] = {"positions": built.positions, "normals": built.normals,
			"triangle_count": built.triangle_count, "stats": built.get("stats", {})}
		approach_records.append({"approach": name, "elapsed_usec": elapsed,
			"triangle_count": int(built.get("triangle_count", 0)),
			"mesh_sha256": _mesh_sha256(built.positions, built.normals),
			"topology": built.get("stats", {}).get("topology", {})})
	_r8_fill_fixture = fixture
	var centerline: Array[Dictionary] = []
	var field_open_indices: Dictionary = {"canonical": [], "A_conforming_propagation": [],
		"B_shared_faces_transitions": [], "C_hybrid_one_cell_halo": []}
	var radial_diameters: Dictionary = {"canonical": PackedFloat64Array(),
		"A_conforming_propagation": PackedFloat64Array(), "B_shared_faces_transitions": PackedFloat64Array(),
		"C_hybrid_one_cell_halo": PackedFloat64Array()}
	var radial_minimum_diameters: Dictionary = {"canonical": PackedFloat64Array(),
		"A_conforming_propagation": PackedFloat64Array(), "B_shared_faces_transitions": PackedFloat64Array(),
		"C_hybrid_one_cell_halo": PackedFloat64Array()}
	for index in range(1, 32):
		var world_x := 8.0 + float(index) * 0.125
		var point := _cave_center(world_x)
		var exact := Transition.sample_canonical(SEED, point, _r8_fill_snapshot)
		var record := {"slice_index": index, "world_position": point,
			"canonical_density": exact, "canonical_open": exact < 0.0,
			"canonical_solid": exact >= 0.0}
		if exact < 0.0: field_open_indices.canonical.append(index)
		var diameter_metrics := _r8_radial_diameter(point, func(p: Vector3) -> float:
			return Transition.sample_canonical(SEED, p, _r8_fill_snapshot))
		if bool(diameter_metrics.get("valid", false)):
			radial_diameters.canonical.append(float(diameter_metrics.median_diameter))
			radial_minimum_diameters.canonical.append(float(diameter_metrics.minimum_ray_diameter))
		var candidate_values: Dictionary = {}
		for approach in APPROACHES:
			var candidate := fixture.sample_approach(point, String(approach))
			candidate_values[String(approach)] = {"density": candidate, "open": candidate < 0.0,
				"solid": candidate >= 0.0}
			if candidate < 0.0: field_open_indices[String(approach)].append(index)
			var candidate_diameter_metrics := _r8_radial_diameter(point, func(p: Vector3) -> float:
				return fixture.sample_approach(p, String(approach)))
			if bool(candidate_diameter_metrics.get("valid", false)):
				radial_diameters[String(approach)].append(float(candidate_diameter_metrics.median_diameter))
				radial_minimum_diameters[String(approach)].append(float(candidate_diameter_metrics.minimum_ray_diameter))
		record["candidate_fields"] = candidate_values
		centerline.append(record)
	var connectivity: Dictionary = {}
	for field_name in ["canonical", APPROACHES[0], APPROACHES[1], APPROACHES[2]]:
		var sampler: Callable = func(p: Vector3) -> float:
			if String(field_name) == "canonical": return Transition.sample_canonical(SEED, p, _r8_fill_snapshot)
			return fixture.sample_approach(p, String(field_name))
		var flood := _r8_flood_components(sampler, FIELD_BOX_MIN, FIELD_BOX_MAX, FIELD_STEP)
		if not bool(flood.get("valid", false)):
			return {"valid": false, "reason": "connectivity_grid_failed:%s" % String(field_name)}
		var open_indices: Array = field_open_indices.get(String(field_name), [])
		if open_indices.is_empty():
			return {"valid": false, "reason": "no_open_centerline_samples:%s" % String(field_name)}
		var first_open_index := int(open_indices[0])
		var last_open_index := int(open_indices[open_indices.size() - 1])
		var left := _cave_center(8.0 + float(first_open_index) * 0.125)
		var right := _cave_center(8.0 + float(last_open_index) * 0.125)
		var exterior := Vector3(10.0, 7.875, _cave_center(10.0).z)
		var left_id: int = _r8_component_at(flood, left)
		var right_id: int = _r8_component_at(flood, right)
		var exterior_id: int = _r8_component_at(flood, exterior)
		var seed_point := _cave_center(10.0)
		var seed_id: int = _r8_component_at(flood, seed_point)
		var negative_x_boundary := _cave_center(FIELD_BOX_MIN.x)
		var positive_x_boundary := _cave_center(FIELD_BOX_MAX.x)
		var negative_x_density: float = sampler.call(negative_x_boundary)
		var positive_x_density: float = sampler.call(positive_x_boundary)
		var negative_x_component := _r8_component_at(flood, negative_x_boundary) if negative_x_density < 0.0 else -2
		var positive_x_component := _r8_component_at(flood, positive_x_boundary) if positive_x_density < 0.0 else -2
		var open_component_ids: Dictionary = {}
		for open_index_value in open_indices:
			var open_index := int(open_index_value)
			var open_point := _cave_center(8.0 + float(open_index) * 0.125)
			var open_component: int = _r8_component_at(flood, open_point)
			if open_component >= 0:
				open_component_ids[open_component] = true
		connectivity[String(field_name)] = {"grid": flood.get("grid"),
			"component_count": flood.get("component_count"), "empty_sample_count": flood.get("empty_sample_count"),
			"left_centerline_component": left_id, "right_centerline_component": right_id,
			"exterior_air_component": exterior_id,
			"left_open_centerline_index": first_open_index, "right_open_centerline_index": last_open_index,
			"left_endpoint_open": left_id >= 0, "right_endpoint_open": right_id >= 0,
			"open_centerline_sample_component_count": open_component_ids.size(),
			"open_centerline_samples_connected_in_voxel_oracle": open_component_ids.size() == 1 and left_id >= 0 and left_id == right_id,
			"seeded_tunnel_point": seed_point, "seeded_tunnel_component": seed_id,
			"negative_x_boundary": {"point": negative_x_boundary, "density": negative_x_density,
				"empty_component": negative_x_component, "connected_to_seeded_tunnel": seed_id >= 0 and seed_id == negative_x_component},
			"positive_x_boundary": {"point": positive_x_boundary, "density": positive_x_density,
				"empty_component": positive_x_component, "connected_to_seeded_tunnel": seed_id >= 0 and seed_id == positive_x_component},
			"centerline_endpoints_connected": left_id >= 0 and left_id == right_id,
			"cave_component_connected_to_exterior": seed_id >= 0 and seed_id == exterior_id,
			"resolution_world_units": FIELD_STEP,
			"connectivity_uncertainty": "voxel-center six-neighbor connectivity; centerline endpoints refer to the first and last canonical-open centerline samples, while signed-X boundary probes are separate; features narrower than sampling spacing or diagonal-only contacts are unresolved"}
	var repaired_mesh := _r8_build_repaired_mesh(fixture, approaches[APPROACHES[2]])
	if not bool(repaired_mesh.get("valid", false)):
		return {"valid": false, "reason": "fill_carve_mesh_repair_setup_failed:%s" % String(repaired_mesh.get("reason", "unknown"))}
	_r8_fill_mesh = repaired_mesh
	_r8_approach_meshes[APPROACHES[2]] = {"positions": repaired_mesh.positions, "normals": repaired_mesh.normals,
		"triangle_count": repaired_mesh.positions.size() / 3, "stats": approaches[APPROACHES[2]].get("stats", {})}
	var mesh_slices: Array[Dictionary] = []
	var mesh_open_indices: Array[int] = []
	var mesh_positions: PackedVector3Array = repaired_mesh.positions
	for index in range(1, 32):
		var point := _cave_center(8.0 + float(index) * 0.125)
		var section := _r8_mesh_centerline_state(mesh_positions, point)
		section["slice_index"] = index
		mesh_slices.append(section)
		if bool(section.get("open", false)): mesh_open_indices.append(index)
	return {"valid": true, "canonical_centerline_open_indices": field_open_indices.canonical,
		"candidate_centerline_open_indices": field_open_indices,
		"canonical_centerline_open_count": field_open_indices.canonical.size(),
		"experimental_centerline_open_count": field_open_indices.get("C_hybrid_one_cell_halo", []).size(),
		"centerline_samples": centerline,
		"radial_cross_section_diameter_summary": _r8_packed_summaries(radial_diameters),
		"radial_cross_section_minimum_ray_diameter_summary": _r8_packed_summaries(radial_minimum_diameters),
		"three_dimensional_voxel_connectivity": connectivity,
		"extracted_mesh_centerline_open_indices": mesh_open_indices,
		"extracted_mesh_centerline_sections": mesh_slices,
		"extracted_mesh_topology": fixture._topology_metrics(repaired_mesh.cells, repaired_mesh.positions),
		"approaches": approach_records,
		"input_sha256": INPUT_SHA_FILL_CARVE,
		"classification": "canonical ordered field is the reference; 6-neighbor voxel components and mesh cross-sections are separate observations, not a tunnel acceptance threshold"}


func _r8_build_repaired_mesh(fixture: RefCounted, built: Dictionary) -> Dictionary:
	var repair := RepairR8.new()
	var focus_ids: Array[int] = _subthreshold_cell_ids(built.cells)
	if focus_ids.is_empty():
		return {"valid": true, "cells": built.cells, "positions": built.positions,
			"normals": built.normals, "repair": {"disposition": "NO_SUBTHRESHOLD_FACES_FOUND"}}
	if focus_ids.size() > MAX_EDITED_FOCUS_CELLS_R72:
		return {"valid": false, "reason": "focus_cell_limit_exceeded"}
	var before: Dictionary = repair.extract_local_mesh(fixture, built.cells, focus_ids)
	var strategy: Dictionary = repair.run_strategy(fixture, before, "A_edge_collapse")
	if not bool(strategy.get("valid", false)):
		return {"valid": false, "reason": "frozen_strategy_A_rejected", "diagnostic": strategy.get("diagnostic", {})}
	var replaced: Dictionary = _replace_local_cells(built.cells, strategy, repair)
	if not bool(replaced.get("valid", false)):
		return {"valid": false, "reason": String(replaced.get("reason", "replace_local_cells_failed"))}
	var flat: Dictionary = _flatten_cells(replaced.cells)
	return {"valid": true, "cells": replaced.cells, "positions": flat.positions,
		"normals": flat.normals, "repair": strategy.get("diagnostic", {}),
		"focus_cell_ids": focus_ids}


func _r8_radial_diameter(center: Vector3, sampler: Callable) -> Dictionary:
	if sampler.call(center) >= 0.0: return {"valid": false, "reason": "center_not_open"}
	var radii := PackedFloat64Array()
	for angle_index in range(32):
		var angle := TAU * float(angle_index) / 32.0
		var direction := Vector3(0.0, sin(angle), cos(angle))
		var previous := 0.0
		var found := -1.0
		for step_index in range(1, 49):
			var distance := float(step_index) * 0.0625
			if sampler.call(center + direction * distance) >= 0.0:
				found = _r8_bisect_surface(center, direction, previous, distance, sampler)
				break
			previous = distance
		if found >= 0.0: radii.append(found)
	if radii.size() < 16: return {"valid": false, "reason": "insufficient_radial_hits", "ray_count": radii.size()}
	radii.sort()
	return {"valid": true, "ray_count": radii.size(),
		"median_diameter": radii[radii.size() / 2] * 2.0,
		"minimum_ray_diameter": radii[0] * 2.0}


func _r8_bisect_surface(origin: Vector3, direction: Vector3, empty_distance: float,
		solid_distance: float, sampler: Callable) -> float:
	var low := empty_distance
	var high := solid_distance
	for _i in range(18):
		var middle := (low + high) * 0.5
		if sampler.call(origin + direction * middle) >= 0.0: high = middle
		else: low = middle
	return (low + high) * 0.5


func _r8_flood_components(sampler: Callable, box_min: Vector3, box_max: Vector3, step: float) -> Dictionary:
	var nx := roundi((box_max.x - box_min.x) / step) + 1
	var ny := roundi((box_max.y - box_min.y) / step) + 1
	var nz := roundi((box_max.z - box_min.z) / step) + 1
	var total := nx * ny * nz
	if total <= 0 or total > 300000:
		return {"valid": false, "reason": "voxel_grid_stop_loss", "node_count": total}
	var labels := PackedInt32Array()
	labels.resize(total)
	labels.fill(-2)
	var empty_count := 0
	for y in range(ny):
		for z in range(nz):
			for x in range(nx):
				var point := box_min + Vector3(x, y, z) * step
				if sampler.call(point) < 0.0:
					labels[_r8_linear(x, y, z, nx, nz)] = -1
					empty_count += 1
	var component_count := 0
	var queue := PackedInt32Array()
	for start in range(total):
		if labels[start] != -1: continue
		var component_id := component_count
		component_count += 1
		labels[start] = component_id
		queue.clear()
		queue.append(start)
		var cursor := 0
		while cursor < queue.size():
			var node := queue[cursor]
			cursor += 1
			var y := floori(float(node) / float(nx * nz))
			var rem := node - y * nx * nz
			var z := floori(float(rem) / float(nx))
			var x := rem - z * nx
			for delta in FLOOD_DIRECTIONS_R8:
				var xx := x + delta.x; var yy := y + delta.y; var zz := z + delta.z
				if xx < 0 or xx >= nx or yy < 0 or yy >= ny or zz < 0 or zz >= nz: continue
				var neighbor := _r8_linear(xx, yy, zz, nx, nz)
				if labels[neighbor] != -1: continue
				labels[neighbor] = component_id
				queue.append(neighbor)
	return {"valid": true, "grid": {"minimum": box_min, "maximum": box_max,
		"spacing": step, "dimensions": [nx, ny, nz], "node_count": total},
		"component_count": component_count, "empty_sample_count": empty_count,
		"labels": labels}


func _r8_linear(x: int, y: int, z: int, nx: int, nz: int) -> int:
	return x + z * nx + y * nx * nz


func _r8_component_at(flood: Dictionary, point: Vector3) -> int:
	var grid: Dictionary = flood.grid
	var minimum: Vector3 = grid.minimum
	var step: float = grid.spacing
	var dims: Array = grid.dimensions
	var x := clampi(roundi((point.x - minimum.x) / step), 0, int(dims[0]) - 1)
	var y := clampi(roundi((point.y - minimum.y) / step), 0, int(dims[1]) - 1)
	var z := clampi(roundi((point.z - minimum.z) / step), 0, int(dims[2]) - 1)
	return int(flood.labels[_r8_linear(x, y, z, int(dims[0]), int(dims[2]))])


func _r8_mesh_centerline_state(positions: PackedVector3Array, point: Vector3) -> Dictionary:
	var crossings: Array[float] = []
	var coplanar_count := 0
	for index in range(0, positions.size(), 3):
		var triangle := [positions[index], positions[index + 1], positions[index + 2]]
		var intersections: Array[Vector3] = []
		var fully_on_plane := true
		for vertex in triangle:
			if absf(vertex.x - point.x) > 1.0e-6: fully_on_plane = false
		for edge in [[0,1],[1,2],[2,0]]:
			var a: Vector3 = triangle[edge[0]]; var b: Vector3 = triangle[edge[1]]
			var da := a.x - point.x; var db := b.x - point.x
			if absf(da) <= 1.0e-6: intersections.append(a)
			if da * db < -1.0e-12: intersections.append(a.lerp(b, da / (da - db)))
		if fully_on_plane:
			coplanar_count += 1
			continue
		var unique: Array[Vector3] = []
		for p in intersections:
			var duplicate := false
			for q in unique:
				if p.distance_squared_to(q) <= 1.0e-12: duplicate = true; break
			if not duplicate: unique.append(p)
		if unique.size() < 2: continue
		var a: Vector3 = unique[0]; var b: Vector3 = unique[1]
		if absf(a.z - point.z) <= 1.0e-6 and absf(a.y - b.y) > 1.0e-6:
			crossings.append(a.y)
		if absf(b.z - point.z) <= 1.0e-6 and absf(a.y - b.y) > 1.0e-6:
			crossings.append(b.y)
		if (a.z - point.z) * (b.z - point.z) < -1.0e-12:
			var t := (point.z - a.z) / (b.z - a.z)
			crossings.append(lerpf(a.y, b.y, t))
	var unique_crossings: Array[float] = []
	for value in crossings:
		var seen := false
		for existing in unique_crossings:
			if absf(value - existing) <= 1.0e-5: seen = true; break
		if not seen: unique_crossings.append(value)
	var above := 0
	for value in unique_crossings:
		if value > point.y + 1.0e-5: above += 1
	return {"open": above % 2 == 0, "vertical_surface_crossings": unique_crossings.size(),
		"crossings_above_center": above, "coplanar_triangles_skipped": coplanar_count,
		"oracle": "even-odd vertical ray in extracted x-slice contour; crop/open boundary and exact-coplanar cases are reported, not treated as watertight proof"}


func _r8_normal_quality() -> Dictionary:
	var scenarios: Dictionary = {}
	for scenario in ["cave_wall_carve", "center_fill_then_wall_carve"]:
		var snapshot_result: Dictionary = _make_snapshot(String(scenario))
		if not bool(snapshot_result.get("valid", false)):
			return {"valid": false, "reason": "normal_snapshot_invalid:%s" % scenario}
		var measured: Dictionary = _r8_normal_quality_case(String(scenario), snapshot_result.snapshot)
		if not bool(measured.get("valid", false)):
			return {"valid": false, "reason": "normal_case_invalid:%s:%s" % [scenario, measured.get("reason", "unknown")],
				"completed_scenarios": scenarios}
		scenarios[String(scenario)] = measured
	return {"valid": true, "scenarios": scenarios,
		"interpretation": "both frozen CARVE and FILL/CARVE histories are measured; no normal-angle tolerance is adopted"}


func _r8_normal_quality_case(scenario: String, snapshot: Dictionary) -> Dictionary:
	var fixture := Fixture.new()
	if not fixture.configure(SEED, snapshot): return {"valid": false, "reason": "normal_fixture_configuration_failed"}
	if not fixture.configure_r71_polygonizer("production", "reject_only_exact_zero", "production"):
		return {"valid": false, "reason": "normal_polygonizer_configuration_failed"}
	var built: Dictionary = fixture.build_approach("A_conforming_propagation")
	if not bool(built.get("valid", false)): return {"valid": false, "reason": "normal_mesh_build_failed"}
	var repaired := _r8_build_repaired_mesh(fixture, built)
	if not bool(repaired.get("valid", false)): return {"valid": false, "reason": "normal_mesh_repair_failed"}
	var focus: Array[int] = repaired.get("focus_cell_ids", [])
	var original_pairs := _r8_collect_normal_pairs(fixture, built.cells, [], snapshot)
	if not bool(original_pairs.get("valid", false)): return {"valid": false, "reason": "original_normal_pair_collection_failed"}
	var pairs := _r8_collect_normal_pairs(fixture, repaired.cells, focus, snapshot)
	if not bool(pairs.get("valid", false)): return {"valid": false, "reason": "normal_pair_collection_failed"}
	var original_winding := _r8_winding_metrics(built.positions, built.normals, snapshot, fixture)
	var repaired_winding := _r8_winding_metrics(repaired.positions, repaired.normals, snapshot, fixture)
	var canonical_stats: Dictionary = fixture._interface_metrics(repaired.cells)
	var input_digest := INPUT_SHA_CARVE if scenario == "cave_wall_carve" else INPUT_SHA_FILL_CARVE
	return {"valid": true, "input_sha256": input_digest, "scenario": scenario,
		"source_shared_endpoint_normal_angle_summary": pairs.get("all_summary", {}),
		"normal_angle_by_repair_status": pairs.get("by_repair_status", {}),
		"worst_normal_pairs": pairs.get("worst_pairs", []),
		"normal_vs_canonical_gradient": pairs.get("gradient_summary", {}),
		"local_gradient_turn_curvature_proxy": pairs.get("curvature_summary", {}),
		"original_shared_endpoint_normal_angle_summary": original_pairs.get("all_summary", {}),
		"original_winding_metrics": original_winding,"repaired_winding_metrics": repaired_winding,
		"winding_metrics": repaired_winding, "R7_interface_oracle_summary": canonical_stats,
		"repaired_focus_cell_count": focus.size(), "repair_diagnostic": repaired.get("repair", {}),
		"interpretation": "angles are localized by cell and endpoint; no angle threshold is adopted; gradient-turn value is a sampled curvature proxy, not differential-geometric curvature"}


func _r8_collect_normal_pairs(fixture: RefCounted, cells: Dictionary, focus_ids: Array[int], snapshot: Dictionary) -> Dictionary:
	var focus: Dictionary = {}; for id in focus_ids: focus[int(id)] = true
	var angles := PackedFloat64Array(); var grad_angles := PackedFloat64Array(); var curvature := PackedFloat64Array()
	var repaired_angles := PackedFloat64Array(); var untouched_angles := PackedFloat64Array()
	var records: Array[Dictionary] = []
	for y in range(Fixture.CELL_DIMS.y):
		for z in range(Fixture.CELL_DIMS.z):
			for x in range(Fixture.CELL_DIMS.x):
				var cell: Vector3i = Vector3i(x,y,z)
				var id: int = int(fixture._cell_id(cell))
				for delta_value in [Vector3i.RIGHT,Vector3i.UP,Vector3i(0,0,1)]:
					var delta: Vector3i = delta_value
					var neighbor: Vector3i = cell + delta
					if not fixture._cell_in_bounds(neighbor): continue
					var other_id: int = int(fixture._cell_id(neighbor))
					var axis := 0 if delta.x != 0 else (1 if delta.y != 0 else 2)
					var plane := (Fixture.PATCH_MIN + Vector3(cell + delta) * Fixture.COARSE_STEP)[axis]
					var side_a: Dictionary = fixture._cell_face_segments(cells.get(id, {}), axis, plane)
					var side_b: Dictionary = fixture._cell_face_segments(cells.get(other_id, {}), axis, plane)
					if side_a.raw.size() != side_b.raw.size(): continue
					var used: Dictionary = {}
					for seg_a_value in side_a.raw:
						var seg_a: Dictionary = seg_a_value; var match_index := -1; var best := INF; var reverse := false
						for j in range(side_b.raw.size()):
							if used.has(j): continue
							var seg_b: Dictionary = side_b.raw[j]
							var direct := maxf(Vector3(seg_a.a).distance_to(seg_b.a), Vector3(seg_a.b).distance_to(seg_b.b))
							var rev := maxf(Vector3(seg_a.a).distance_to(seg_b.b), Vector3(seg_a.b).distance_to(seg_b.a))
							if minf(direct,rev) < best: best=minf(direct,rev); match_index=j; reverse=rev<direct
						if match_index < 0 or best > SEAM_EPSILON: continue
						used[match_index]=true; var seg_b: Dictionary=side_b.raw[match_index]
						var a_keys: Array=[seg_a.a_key,seg_a.b_key]
						var b_keys: Array=[seg_b.b_key,seg_b.a_key] if reverse else [seg_b.a_key,seg_b.b_key]
						for endpoint in range(2):
							var point: Vector3=side_a.points[a_keys[endpoint]]
							var na: Vector3=side_a.normals.get(a_keys[endpoint],Vector3.ZERO)
							var nb: Vector3=side_b.normals.get(b_keys[endpoint],Vector3.ZERO)
							if na.length_squared()<1.0e-8 or nb.length_squared()<1.0e-8: continue
							var angle := rad_to_deg(na.angle_to(nb)); angles.append(angle)
							var gradient := _r8_gradient(point,snapshot); var outward := -gradient.normalized()
							var ga := rad_to_deg(na.angle_to(outward)); var gb := rad_to_deg(nb.angle_to(outward))
							grad_angles.append(maxf(ga,gb))
							var curvature_value := (_r8_gradient(point + outward * 0.1,snapshot) - _r8_gradient(point - outward * 0.1,snapshot)).length() / 0.2
							curvature.append(curvature_value)
							var repaired_a := focus.has(id); var repaired_b := focus.has(other_id)
							if repaired_a or repaired_b: repaired_angles.append(angle)
							else: untouched_angles.append(angle)
							if records.size()<5000 or angle>85.0:
								records.append({"world_position":point,"cell_a":[cell.x,cell.y,cell.z],
								"cell_b":[neighbor.x,neighbor.y,neighbor.z],"cell_id_a":id,"cell_id_b":other_id,
								"endpoint_normal_angle_degrees":angle,"normal_a":na,"normal_b":nb,
								"max_angle_to_canonical_outward_gradient_degrees":maxf(ga,gb),
								"gradient_curvature_proxy":curvature_value,"repaired_cell_a":repaired_a,"repaired_cell_b":repaired_b})
	records.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return float(a.endpoint_normal_angle_degrees)>float(b.endpoint_normal_angle_degrees))
	return {"valid": not angles.is_empty(), "all_summary": _r8_summary(angles),
		"by_repair_status":{"touches_repaired_cell":_r8_summary(repaired_angles),"untouched_pair":_r8_summary(untouched_angles)},
		"gradient_summary":_r8_summary(grad_angles),"curvature_summary":_r8_summary(curvature),
		"worst_pairs":records.slice(0,mini(30,records.size()))}


func _r8_gradient(point: Vector3, snapshot: Dictionary) -> Vector3:
	var e := NORMAL_EPSILON
	var dx := Transition.sample_canonical(SEED, point+Vector3.RIGHT*e,snapshot)-Transition.sample_canonical(SEED,point-Vector3.RIGHT*e,snapshot)
	var dy := Transition.sample_canonical(SEED, point+Vector3.UP*e,snapshot)-Transition.sample_canonical(SEED,point-Vector3.UP*e,snapshot)
	var dz := Transition.sample_canonical(SEED, point+Vector3.BACK*e,snapshot)-Transition.sample_canonical(SEED,point-Vector3.BACK*e,snapshot)
	return Vector3(dx,dy,dz).normalized()


func _r8_winding_metrics(positions: PackedVector3Array, normals: PackedVector3Array, snapshot: Dictionary,
		fixture: RefCounted = null) -> Dictionary:
	var dots := PackedFloat64Array(); var normal_dots := PackedFloat64Array()
	var reversed := 0; var normal_mismatch := 0; var zero_area := 0
	var reversed_examples: Array[Dictionary] = []; var normal_mismatch_examples: Array[Dictionary] = []
	for i in range(0,positions.size(),3):
		var a:Vector3=positions[i]; var b:Vector3=positions[i+1]; var c:Vector3=positions[i+2]
		var cross:Vector3=(b-a).cross(c-a)
		if cross.length_squared()<=1.0e-12: zero_area+=1; continue
		var geometric:=cross.normalized(); var outward:Vector3=-_r8_gradient((a+b+c)/3.0,snapshot)
		var centroid:Vector3=(a+b+c)/3.0
		var owner_cell_id:=-1
		var owner_cell_coordinate:=Vector3i(-1,-1,-1)
		if fixture!=null:
			var local:Vector3=(centroid-Fixture.PATCH_MIN)/Fixture.COARSE_STEP
			owner_cell_coordinate=Vector3i(clampi(floori(local.x),0,Fixture.CELL_DIMS.x-1),
				clampi(floori(local.y),0,Fixture.CELL_DIMS.y-1),clampi(floori(local.z),0,Fixture.CELL_DIMS.z-1))
			owner_cell_id=int(fixture._cell_id(owner_cell_coordinate))
		var dot:=geometric.dot(outward); dots.append(dot)
		if dot<0.0:
			reversed+=1
			if reversed_examples.size()<16:reversed_examples.append({"triangle_index":i/3,"owner_cell_id":owner_cell_id,
				"owner_cell_coordinate":owner_cell_coordinate,"centroid":centroid,
				"geometric_face_normal":geometric,"canonical_outward_gradient":outward,"dot":dot,
				"vertices":[a,b,c]})
		var averaged:Vector3=(normals[i]+normals[i+1]+normals[i+2]).normalized()
		if averaged.length_squared()>1.0e-10:
			var normal_dot:=geometric.dot(averaged);normal_dots.append(normal_dot)
			if normal_dot<0.0:
				normal_mismatch+=1
				if normal_mismatch_examples.size()<16:normal_mismatch_examples.append({"triangle_index":i/3,
					"owner_cell_id":owner_cell_id,"owner_cell_coordinate":owner_cell_coordinate,
					"centroid":centroid,"geometric_face_normal":geometric,"averaged_vertex_normal":averaged,"dot":normal_dot})
	return {"geometric_winding_dot_outward_gradient":_r8_summary(dots),
		"geometric_face_vs_interpolated_vertex_normal_dot":_r8_summary(normal_dots),
		"triangles_opposite_to_outward_gradient":reversed,"triangles_with_vertex_normal_opposing_face":normal_mismatch,
		"opposite_winding_examples":reversed_examples,"vertex_normal_mismatch_examples":normal_mismatch_examples,
		"degenerate_at_unchanged_squared_cross_threshold_1e-12":zero_area,"triangle_count":positions.size()/3}


func _r8_chunk_conformance() -> Dictionary:
	var orientation_specs := [
		{"id":"X_POS","axis":0,"plane":16.0,"region_a":Vector2i(0,0),"chunk_a":Vector2i(3,2),"region_b":Vector2i(1,0),"chunk_b":Vector2i(0,2)},
		{"id":"X_NEG","axis":0,"plane":0.0,"region_a":Vector2i(-1,0),"chunk_a":Vector2i(3,2),"region_b":Vector2i(0,0),"chunk_b":Vector2i(0,2)},
		{"id":"Z_POS","axis":2,"plane":12.0,"region_a":Vector2i(0,0),"chunk_a":Vector2i(2,3),"region_b":Vector2i(0,1),"chunk_b":Vector2i(2,0)},
		{"id":"Z_NEG","axis":2,"plane":0.0,"region_a":Vector2i(0,-1),"chunk_a":Vector2i(2,3),"region_b":Vector2i(0,0),"chunk_b":Vector2i(2,0)}]
	var cases: Array[Dictionary]=[]
	for spec_value in orientation_specs:
		var spec:Dictionary=spec_value
		for pair in [[0,0],[1,1],[0,1],[1,0]]:
			if pair[0]!=pair[1] and not ["X_POS","Z_NEG"].has(String(spec.id)): continue
			var record:Dictionary = _r8_measure_chunk_pair(spec,int(pair[0]),int(pair[1]),_r8_fill_snapshot,"fill_carve")
			if not bool(record.get("valid",false)): return {"valid":false,"reason":"chunk_pair_failed:%s"%String(record.get("reason","unknown")),"records":cases}
			cases.append(record)
	var seam_ledger := Brush.new(SEED, Field.GENERATOR_VERSION)
	for i in range(_r8_fill_snapshot.centers.size()):
		var mode:=int(_r8_fill_snapshot.modes[i])
		if not seam_ledger.add_sphere(mode,Vector3(_r8_fill_snapshot.centers[i]),float(_r8_fill_snapshot.radii[i])):
			return {"valid":false,"reason":"seam_ledger_reconstruction_failed"}
	var boundary_center := _cave_center(16.0)
	if not seam_ledger.add_sphere(Brush.Mode.CARVE,boundary_center,0.58):
		return {"valid":false,"reason":"boundary_edit_rejected"}
	var seam_snapshot:Dictionary=seam_ledger.get_meshing_snapshot()
	var edit_cases:Array[Dictionary]=[]
	for pair in [[0,0],[1,1],[0,1],[1,0]]:
		var spec:Dictionary=orientation_specs[0]
		var measured:Dictionary=_r8_measure_chunk_pair(spec,int(pair[0]),int(pair[1]),seam_snapshot,"boundary_edit")
		if not bool(measured.get("valid",false)): return {"valid":false,"reason":"edited_chunk_pair_failed","records":cases,"edited":edit_cases}
		edit_cases.append(measured)
	return {"valid":true,"same_and_mixed_lod_pairs":cases,"boundary_edit_pairs":edit_cases,
		"fixture_scope":"real production LOD0/LOD1 CPU chunk builders with disposable ordered snapshot; meshes remain test-only arrays",
		"cross_adaptive_cell_vs_chunk_note":"R7 fixture reports internal macro-cell interfaces separately from this actual chunk-boundary table"}


func _r8_measure_chunk_pair(spec:Dictionary,lod_a:int,lod_b:int,snapshot:Dictionary,label:String) -> Dictionary:
	var begin:=Time.get_ticks_usec()
	var mesh_a:Dictionary=_r8_build_chunk(int(lod_a),spec.region_a,spec.chunk_a,snapshot)
	var mesh_b:Dictionary=_r8_build_chunk(int(lod_b),spec.region_b,spec.chunk_b,snapshot)
	if not bool(mesh_a.get("valid",false)) or not bool(mesh_b.get("valid",false)):
		return {"valid":false,"reason":"chunk_build_invalid","a":mesh_a.get("reason",""),"b":mesh_b.get("reason","")}
	var world_a:Dictionary=_r8_chunk_world_mesh(mesh_a,spec.region_a,spec.chunk_a,snapshot)
	var world_b:Dictionary=_r8_chunk_world_mesh(mesh_b,spec.region_b,spec.chunk_b,snapshot)
	var contour_a:=_r8_plane_contour(world_a.positions,world_a.normals,int(spec.axis),float(spec.plane))
	var contour_b:=_r8_plane_contour(world_b.positions,world_b.normals,int(spec.axis),float(spec.plane))
	var compare:=_r8_compare_contours(contour_a,contour_b)
	var field_compare:=_r8_compare_face_samples(spec,snapshot)
	var picking:=_r8_chunk_picker_probe(spec,world_a.positions,world_b.positions,snapshot)
	return {"valid":true,"scenario":label,"boundary":String(spec.id),"lod_a":lod_a,"lod_b":lod_b,
		"region_a":spec.region_a,"chunk_a":spec.chunk_a,"region_b":spec.region_b,"chunk_b":spec.chunk_b,
		"world_plane":float(spec.plane),"mesh_a":{"triangle_count":mesh_a.triangle_count,"sample_count":mesh_a.sample_count,
			"build_usec":int(mesh_a.get("elapsed_usec",0)),"sha256":_mesh_sha256(world_a.positions,world_a.normals),"winding":world_a.winding},
		"mesh_b":{"triangle_count":mesh_b.triangle_count,"sample_count":mesh_b.sample_count,
			"build_usec":int(mesh_b.get("elapsed_usec",0)),"sha256":_mesh_sha256(world_b.positions,world_b.normals),"winding":world_b.winding},
		"contour_comparison":compare,"canonical_shared_face_samples":field_compare,"picking_probe":picking,
		"pair_total_usec":Time.get_ticks_usec()-begin,
		"note":"contours are extracted from actual triangle-plane intersections; equality and topology observations are not an owner-approved geometric tolerance"}


func _r8_build_chunk(lod:int,region:Vector2i,chunk:Vector2i,snapshot:Dictionary)->Dictionary:
	if lod==0:return MesherR8.build_chunk_cpu_data(SEED,region,chunk,false,snapshot)
	return LodMesherR8.build_chunk_cpu_data(SEED,region,chunk,snapshot)


func _r8_chunk_picker_probe(spec:Dictionary,positions_a:PackedVector3Array,positions_b:PackedVector3Array,snapshot:Dictionary)->Dictionary:
	var x:=10.0;var z:=6.0
	if int(spec.axis)==0:x=float(spec.plane)
	else:z=float(spec.plane)
	var origin:=Vector3(x,8.0,z);var direction:=Vector3.DOWN
	var sampler:Callable=func(point:Vector3)->float:
		return Transition.sample_canonical(SEED,point,snapshot)
	var picked:Dictionary=Picker.pick_sdf_v1_surface(origin,direction,sampler)
	var combined:=PackedVector3Array();combined.append_array(positions_a);combined.append_array(positions_b)
	var triangle:Dictionary=_ray_mesh_reference(combined,origin,origin+direction*12.0)
	var triangle_hit:=bool(triangle.get("two_sided_hit",false));var picked_hit:=bool(picked.get("hit",false))
	var mesh_position:=origin+direction*float(triangle.get("two_sided_distance_world",0.0)) if triangle_hit else origin
	var error:=Vector3(picked.position).distance_to(mesh_position) if picked_hit and triangle_hit else INF
	return {"world_ray_origin":origin,"world_ray_direction":direction,"sdf_picker_hit":picked_hit,
		"triangle_mesh_hit":triangle_hit,"hit_outcomes_match":picked_hit==triangle_hit,
		"sdf_picker_position":picked.get("position",Vector3.ZERO),"triangle_mesh_position":mesh_position,
		"hit_position_error_world":error,"triangle_nearest_face":triangle.get("two_sided_face","NONE"),
		"oracle":"canonical SDF v1 picker compared with independent two-sided triangle intersection across adjoining chunks"}


func _r8_chunk_world_mesh(data:Dictionary,region:Vector2i,chunk:Vector2i,snapshot:Dictionary)->Dictionary:
	var origin:Vector3=SpatialR8.region_origin_world(region)+GridR8.origin_for(chunk)
	var positions:PackedVector3Array=data.positions.duplicate(); var normals:PackedVector3Array=data.normals.duplicate()
	for i in range(positions.size()):positions[i]+=origin
	var winding:=_r8_winding_metrics(positions,normals,snapshot)
	return {"positions":positions,"normals":normals,"winding":winding}


func _r8_plane_contour(positions:PackedVector3Array,normals:PackedVector3Array,axis:int,plane:float)->Dictionary:
	var segments:Array[Dictionary]=[];var points:Dictionary={};var coplanar:=0
	for i in range(0,positions.size(),3):
		var tri:Array[Vector3]=[positions[i],positions[i+1],positions[i+2]]
		var tri_normals:Array[Vector3]=[normals[i],normals[i+1],normals[i+2]]
		var hits:Array[Dictionary]=[];var on_plane:=true
		for p in tri:
			if absf(p[axis]-plane)>1.0e-6:on_plane=false
		if on_plane:coplanar+=1;continue
		for edge in [[0,1],[1,2],[2,0]]:
			var ia:int=edge[0];var ib:int=edge[1]
			var a:Vector3=tri[ia];var b:Vector3=tri[ib]
			var na:Vector3=tri_normals[ia];var nb:Vector3=tri_normals[ib]
			var da:=a[axis]-plane;var db:=b[axis]-plane
			if absf(da)<=1.0e-6:hits.append({"point":a,"normal":na})
			if da*db< -1.0e-12:
				var t:float=da/(da-db)
				hits.append({"point":a.lerp(b,t),"normal":na.lerp(nb,t).normalized()})
		var unique:Array[Dictionary]=[]
		for hit in hits:
			var duplicate:=false
			for prior in unique:
				if Vector3(hit.point).distance_squared_to(Vector3(prior.point))<=1.0e-12:duplicate=true;break
			if not duplicate:unique.append(hit)
		if unique.size()<2:continue
		var first:Dictionary=unique[0];var second:Dictionary=unique[1]
		var a:Vector3=first.point;var b:Vector3=second.point
		if a.distance_squared_to(b)<=1.0e-12:continue
		var ak:=_r8_point_key(a);var bk:=_r8_point_key(b)
		segments.append({"a":a,"b":b,"a_key":ak,"b_key":bk,"normal_a":first.normal,
			"normal_b":second.normal,"key":_r8_edge_key(ak,bk)})
		points[ak]=a;points[bk]=b
	return {"segments":segments,"points":points,"coplanar_triangle_count":coplanar}


func _r8_compare_contours(a:Dictionary,b:Dictionary)->Dictionary:
	var map_a:Dictionary={};var map_b:Dictionary={}
	for s in a.segments:map_a[s.key]=s
	for s in b.segments:map_b[s.key]=s
	var only_a:Array=[];var only_b:Array=[]
	for k in map_a:if not map_b.has(k):only_a.append(map_a[k])
	for k in map_b:if not map_a.has(k):only_b.append(map_b[k])
	var t_junctions:=0
	for point_key in a.points:
		var point:Vector3=a.points[point_key]
		for seg in b.segments:if point_key!=seg.a_key and point_key!=seg.b_key and _r8_strict_on_segment(point,seg.a,seg.b):t_junctions+=1
	for point_key in b.points:
		var point:Vector3=b.points[point_key]
		for seg in a.segments:if point_key!=seg.a_key and point_key!=seg.b_key and _r8_strict_on_segment(point,seg.a,seg.b):t_junctions+=1
	var angle_values:=PackedFloat64Array();var unmatched_normals:=0
	var normal_map_a:=_r8_boundary_normal_map(a.segments);var normal_map_b:=_r8_boundary_normal_map(b.segments)
	for key in normal_map_a:
		if not normal_map_b.has(key):unmatched_normals+=1;continue
		var na:Vector3=normal_map_a[key];var nb:Vector3=normal_map_b[key]
		if na.length_squared()>1.0e-8 and nb.length_squared()>1.0e-8:angle_values.append(rad_to_deg(na.angle_to(nb)))
	var same_direction:=0;var reverse_direction:=0
	for key in map_a:
		if not map_b.has(key):continue
		var sa:Dictionary=map_a[key];var sb:Dictionary=map_b[key]
		if sa.a_key==sb.a_key:same_direction+=1
		else:reverse_direction+=1
	return {"segment_count_a":a.segments.size(),"segment_count_b":b.segments.size(),
		"matched_segment_count":mini(a.segments.size(),b.segments.size())-only_a.size(),
		"unmatched_a_count":only_a.size(),"unmatched_b_count":only_b.size(),
		"unmatched_a_examples":only_a.slice(0,mini(8,only_a.size())),"unmatched_b_examples":only_b.slice(0,mini(8,only_b.size())),
		"t_junction_vertex_count":t_junctions,"shared_endpoint_normal_angle_degrees":_r8_summary(angle_values),
		"vertices_without_counterpart_normal":unmatched_normals,"same_directed_contour_edges":same_direction,
		"oppositely_directed_contour_edges":reverse_direction,
		"coplanar_triangle_count_a":a.coplanar_triangle_count,"coplanar_triangle_count_b":b.coplanar_triangle_count,
		"contour_segments_match":only_a.is_empty() and only_b.is_empty() and t_junctions==0}


func _r8_boundary_normal_map(segments:Array[Dictionary])->Dictionary:
	var result:Dictionary={}
	for s in segments:
		result[s.a_key]=Vector3(result.get(s.a_key,Vector3.ZERO))+Vector3(s.normal_a)
		result[s.b_key]=Vector3(result.get(s.b_key,Vector3.ZERO))+Vector3(s.normal_b)
	for key in result:result[key]=Vector3(result[key]).normalized()
	return result


func _r8_strict_on_segment(p:Vector3,a:Vector3,b:Vector3)->bool:
	var ab:=b-a;var length2:=ab.length_squared()
	if length2<=1.0e-12:return false
	var t:float=(p-a).dot(ab)/length2
	if t<=1.0e-5 or t>=1.0-1.0e-5:return false
	return (a+ab*t).distance_to(p)<=SEAM_EPSILON


func _r8_point_key(p:Vector3)->String:
	return "%d,%d,%d"%[roundi(p.x*100000.0),roundi(p.y*100000.0),roundi(p.z*100000.0)]


func _r8_edge_key(a:String,b:String)->String:return a+"|"+b if a<b else b+"|"+a


func _r8_compare_face_samples(spec:Dictionary,snapshot:Dictionary)->Dictionary:
	var axis:=int(spec.axis)
	var others:Array[int]=[]
	if axis==0:others=[1,2]
	elif axis==1:others=[0,2]
	else:others=[0,1]
	var min_a:Vector3=SpatialR8.region_origin_world(spec.region_a)+GridR8.origin_for(spec.chunk_a)
	var min_b:Vector3=SpatialR8.region_origin_world(spec.region_b)+GridR8.origin_for(spec.chunk_b)
	var size_a:Vector3=GridR8.size_for(spec.chunk_a);var size_b:Vector3=GridR8.size_for(spec.chunk_b)
	var start_a:=min_a;var start_b:=min_b;var end_a:=min_a+size_a;var end_b:=min_b+size_b
	var lo0:=maxf(start_a[others[0]],start_b[others[0]]);var hi0:=minf(end_a[others[0]],end_b[others[0]])
	var lo1:=maxf(start_a[others[1]],start_b[others[1]]);var hi1:=minf(end_a[others[1]],end_b[others[1]])
	var max_difference:=0.0;var differing:=0;var count:=0
	for v in range(0,roundi((hi1-lo1)/0.25)+1):
		for u in range(0,roundi((hi0-lo0)/0.25)+1):
			var p:=Vector3.ZERO;p[axis]=float(spec.plane);p[others[0]]=lo0+float(u)*0.25;p[others[1]]=lo1+float(v)*0.25
			var local_a:=p-SpatialR8.region_origin_world(spec.region_a);var local_b:=p-SpatialR8.region_origin_world(spec.region_b)
			var da:=Brush.sample_density_snapshot(SEED,spec.region_a,local_a,false,snapshot)
			var db:=Brush.sample_density_snapshot(SEED,spec.region_b,local_b,false,snapshot)
			var diff:=absf(float(da)-float(db));max_difference=maxf(max_difference,diff)
			if diff>0.0:differing+=1
			count+=1
	return {"sample_count":count,"non_bitwise_equal_count":differing,"max_absolute_density_difference":max_difference,
		"shared_face_world_bounds":[lo0,hi0,lo1,hi1],"sample_spacing_world":0.25}


func _r8_resolution_sweep()->Dictionary:
	var cases:Array[Dictionary]=[]
	for scenario in ["zero_edit","center_fill_then_wall_carve"]:
		var sr:Dictionary=_make_snapshot(String(scenario));if not bool(sr.get("valid",false)):return {"valid":false,"reason":"resolution_snapshot_failed"}
		var snapshot:Dictionary=sr.snapshot
		for step in [0.5,0.25,0.125]:
			if Time.get_ticks_usec()-_r8_started_usec>int(R8_MAX_SECONDS*1000000.0):return {"valid":false,"reason":"R8_stop_loss_runtime"}
			var began:=Time.get_ticks_usec()
			_r8_write_evidence("resolution-call-start.json",{"scenario":scenario,"spacing":step})
			var mesh:Dictionary=_r8_uniform_mesh(snapshot,float(step))
			_r8_write_evidence("resolution-call-returned.json",{"scenario":scenario,"spacing":step,
				"valid":mesh.get("valid",false),"triangle_count":mesh.get("triangle_count",0),
				"sample_count":mesh.get("sample_count",0),"reason":mesh.get("reason","")})
			if not bool(mesh.get("valid",false)):return {"valid":false,"reason":"uniform_mesh_failed:%s"%String(mesh.get("reason","unknown"))}
			cases.append({"scenario":scenario,"sample_spacing_world":step,"sample_count":mesh.sample_count,
				"sample_bytes":mesh.sample_count*4,"triangle_count":mesh.triangle_count,
				"mesh_attribute_bytes":mesh.vertex_count*24,"mesh_sha256":mesh.mesh_sha256,
				"build_usec":Time.get_ticks_usec()-began,
				"surface_displacement_proxy_world":mesh.displacement,"normal_angle_degrees":mesh.normal_angles,
				"topology":mesh.topology,"canonical_centerline_open_indices":mesh.centerline_open_indices,
				"mesh_centerline_open_indices":mesh.mesh_centerline_open_indices,
				"note":"uniform-grid exploratory comparison; displacement uses canonical SDF residual, not a product geometry tolerance"})
			_r8_write_evidence("resolution-%s-h%s.json" % [String(scenario), str(step).replace(".", "p")], cases.back())
	return {"valid":true,"domain_min":Vector3(7.5,-1.0,4.0),"domain_max":Vector3(12.5,5.5,9.0),
		"cases":cases,"resolution_values_are_exploratory":true}


func _r8_uniform_mesh(snapshot:Dictionary,step:float)->Dictionary:
	var domain_min:=Vector3(7.5,-1.0,4.0);var domain_max:=Vector3(12.5,5.5,9.0)
	var nx:=roundi((domain_max.x-domain_min.x)/step);var ny:=roundi((domain_max.y-domain_min.y)/step);var nz:=roundi((domain_max.z-domain_min.z)/step)
	var sample_count:Variant=(nx+1)*(ny+1)*(nz+1)
	if int(sample_count)>300000:return {"valid":false,"reason":"uniform_sample_stop_loss"}
	var values:=PackedFloat32Array();values.resize(int(sample_count))
	for y in range(ny+1):
		for z in range(nz+1):
			for x in range(nx+1):
				var p:=domain_min+Vector3(x,y,z)*step
				values[_r8_linear(x,y,z,nx+1,nz+1)]=Transition.sample_canonical(SEED,p,snapshot)
		if step<=0.125 and y%4==0:
			_r8_write_evidence("progress-resolution-sampling.json",{"spacing":step,"y_index":y,
				"y_total":ny+1,"completed_sample_rows":(y+1)*(nz+1)})
	_r8_write_evidence("progress-resolution-sampling-complete.json",{"spacing":step,"sample_count":sample_count})
	var positions:=PackedVector3Array();var normals:=PackedVector3Array()
	var corners:Array=MesherR8.CORNERS;var tetrahedra:Array=MesherR8.TETRAHEDRA
	for y in range(ny):
		for z in range(nz):
			for x in range(nx):
				var points:Array[Vector3]=[];var vals:Array[float]=[];var solid:=false;var empty:=false
				for corner in corners:
					var c:Vector3i=corner;var value:=float(values[_r8_linear(x+c.x,y+c.y,z+c.z,nx+1,nz+1)])
					points.append(domain_min+Vector3(x+c.x,y+c.y,z+c.z)*step);vals.append(value);solid=solid or value>=0.0;empty=empty or value<0.0
				if not solid or not empty:continue
				for tet in tetrahedra:MesherR8._polygonize_tetra(tet,points,vals,positions,normals)
	_r8_write_evidence("progress-resolution-polygonization-complete.json",{"spacing":step,"triangle_count":positions.size()/3})
	var residuals:=PackedFloat64Array();var normal_angles:=PackedFloat64Array();var degenerate:=0
	for i in range(0,positions.size(),3):
		var a:Vector3=positions[i];var b:Vector3=positions[i+1];var c:Vector3=positions[i+2];var cross:Vector3=(b-a).cross(c-a)
		if cross.length_squared()<=1.0e-12:degenerate+=1;continue
		var center:Vector3=(a+b+c)/3.0;residuals.append(absf(Transition.sample_canonical(SEED,center,snapshot)))
		var outward:= -_r8_gradient(center,snapshot);normal_angles.append(rad_to_deg(cross.normalized().angle_to(outward)))
	var topology:=_r8_triangle_topology(positions)
	_r8_write_evidence("progress-resolution-surface-metrics-complete.json",{"spacing":step,"triangle_count":positions.size()/3})
	var center_open:Array[int]=[];var center_mesh:Array[int]=[]
	for idx in [1,4,8,12,16,20,24,28,31]:
		var p:=_cave_center(8.0+float(idx)*0.125)
		if Transition.sample_canonical(SEED,p,snapshot)<0.0:center_open.append(idx)
		var state:=_r8_mesh_centerline_state(positions,p);if bool(state.open):center_mesh.append(idx)
	_r8_write_evidence("progress-resolution-connectivity-complete.json",{"spacing":step,"tested_slices":[1,4,8,12,16,20,24,28,31]})
	var mesh_digest:=_mesh_sha256(positions,normals)
	_r8_write_evidence("progress-resolution-hash-complete.json",{"spacing":step,"mesh_sha256":mesh_digest,"vertex_count":positions.size()})
	var displacement_result:=_r8_checked_summary(residuals)
	_r8_write_evidence("progress-resolution-displacement-summary.json",{"spacing":step,"valid":displacement_result.valid,
		"count":displacement_result.get("count",0),"nonfinite_count":displacement_result.get("nonfinite_count",0)})
	if not bool(displacement_result.valid):return {"valid":false,"reason":"nonfinite_or_empty_displacement_samples",
		"displacement_summary":displacement_result}
	var angle_result:=_r8_checked_summary(normal_angles)
	_r8_write_evidence("progress-resolution-normal-summary.json",{"spacing":step,"valid":angle_result.valid,
		"count":angle_result.get("count",0),"nonfinite_count":angle_result.get("nonfinite_count",0)})
	if not bool(angle_result.valid):return {"valid":false,"reason":"nonfinite_or_empty_normal_samples",
		"normal_summary":angle_result}
	return {"valid":not positions.is_empty(),"mesh_sha256":mesh_digest,"vertex_count":positions.size(),
		"triangle_count":positions.size()/3,"sample_count":int(sample_count),
		"displacement":displacement_result.summary,"normal_angles":angle_result.summary,
		"topology":{"degenerate_triangle_count_at_1e-12":degenerate}.merged(topology,true),
		"centerline_open_indices":center_open,"mesh_centerline_open_indices":center_mesh}


func _r8_checked_summary(values:PackedFloat64Array)->Dictionary:
	var sorted:Array[float]=[]
	var nonfinite_count:=0
	for value in values:
		if is_finite(value):sorted.append(value)
		else:nonfinite_count+=1
	if nonfinite_count>0:return {"valid":false,"reason":"nonfinite_values","count":values.size(),"nonfinite_count":nonfinite_count}
	if sorted.is_empty():return {"valid":false,"reason":"empty_values","count":0,"nonfinite_count":0}
	sorted.sort()
	return {"valid":true,"count":sorted.size(),"nonfinite_count":0,
		"summary":{"count":sorted.size(),"p50":_r8_percentile(sorted,0.5),
			"p95":_r8_percentile(sorted,0.95),"max":sorted.back()}}


func _r8_triangle_topology(positions:PackedVector3Array)->Dictionary:
	var counts:Dictionary={};var owners:Dictionary={};var tri:=0
	for i in range(0,positions.size(),3):
		var keys:Array[String]=[_r8_point_key(positions[i]),_r8_point_key(positions[i+1]),_r8_point_key(positions[i+2])]
		for e in [[0,1],[1,2],[2,0]]:
			var key:=_r8_edge_key(keys[e[0]],keys[e[1]]);counts[key]=int(counts.get(key,0))+1
			var item:Array=owners.get(key,[]);item.append(tri);owners[key]=item
		tri+=1
	var open:=0;var nonmanifold:=0
	for key in counts:
		if int(counts[key])==1:open+=1
		elif int(counts[key])!=2:nonmanifold+=1
	return {"open_edges_in_finite_crop":open,"nonmanifold_edges":nonmanifold,"unique_edges":counts.size(),
		"note":"finite crop boundary edges are expected; count is not a watertightness claim"}


func _r8_collision_consistency()->Dictionary:
	if _r8_fill_mesh.is_empty() or _r8_approach_meshes.size()!=APPROACHES.size():
		return {"valid":false,"reason":"frozen_meshes_missing_for_collision_oracle"}
	var center:=_cave_center(10.0)
	var ray_records:Array[Dictionary]=[];var sphere_records:Array[Dictionary]=[]
	for approach in APPROACHES:
		var mesh:Dictionary=_r8_approach_meshes[String(approach)]
		var vertices:PackedVector3Array=mesh.positions
		var index:Dictionary=_build_triangle_spatial_index(vertices,Fixture.PATCH_MIN,Fixture.CELL_DIMS,Fixture.COARSE_STEP)
		for angle_index in range(12):
			var angle:=TAU*float(angle_index)/12.0
			var direction:=Vector3(0.0,sin(angle),cos(angle))
			var surface_distance:=_r8_first_surface_distance(center,direction,_r8_fill_snapshot,2.5)
			var ray_pairs:Array[Dictionary]=[]
			for reverse in [false,true]:
				var ray_from:=center+direction*2.5 if reverse else center
				var ray_direction:Vector3=-direction if reverse else direction
				var ray_to:=ray_from+ray_direction*2.5
				var ref:=_ray_mesh_reference(vertices,ray_from,ray_to)
				var sdf_distance:float=_r8_first_surface_distance(ray_from,ray_direction,_r8_fill_snapshot,2.5)
				var mesh_distance:float=ref.get("two_sided_distance_world",INF)
				var has_sdf_hit:=sdf_distance>=0.0 and sdf_distance<=2.5
				var has_mesh_hit:=bool(ref.get("two_sided_hit",false))
				var canonical_point:=ray_from+ray_direction*sdf_distance if has_sdf_hit else ray_from
				var rec:Dictionary={"approach":String(approach),"angle_index":angle_index,
					"direction":"outside_to_cave" if reverse else "cave_to_outside",
					"sdf_hit":has_sdf_hit,"triangle_hit":has_mesh_hit,
					"sdf_distance_world":sdf_distance,"triangle_distance_world":mesh_distance,
					"absolute_distance_error_world":absf(mesh_distance-sdf_distance) if has_mesh_hit and has_sdf_hit else INF,
					"nearest_triangle_face":ref.get("two_sided_face","NONE"),
					"triangle_intersection_count":ref.get("triangle_intersection_count",0),
					"canonical_surface_world":canonical_point}
				ray_records.append(rec);ray_pairs.append(rec)
			var expected_contact:=maxf(0.0,surface_distance-0.10) if surface_distance>=0.0 else INF
			var mesh_contact:=_mesh_sphere_contact_distance(index,center,direction,0.10,2.5)
			sphere_records.append({"approach":String(approach),"angle_index":angle_index,
				"sphere_radius_world":0.10,"canonical_contact_center_distance_world":expected_contact,
				"triangle_mesh_contact_center_distance_world":mesh_contact,
				"absolute_contact_error_world":absf(mesh_contact-expected_contact) if is_finite(mesh_contact) and is_finite(expected_contact) else INF,
				"sweep_step_world":0.01,"triangle_contact_oracle":"point-to-triangle distance with binary refinement after 0.01-unit bracket scan"})
	var ray_errors:=PackedFloat64Array();var sphere_errors:=PackedFloat64Array();var ray_outcome_mismatches:=0
	for item in ray_records:
		if bool(item.sdf_hit)!=bool(item.triangle_hit):ray_outcome_mismatches+=1
		if is_finite(float(item.absolute_distance_error_world)):ray_errors.append(float(item.absolute_distance_error_world))
	for item in sphere_records:
		if is_finite(float(item.absolute_contact_error_world)):sphere_errors.append(float(item.absolute_contact_error_world))
	return {"valid":true,"status":"COMPUTATIONAL_TRIANGLE_AND_CANONICAL_SDF_ORACLE_ONLY",
		"ray_query_count":ray_records.size(),"expected_ray_count":72,"ray_outcome_mismatches":ray_outcome_mismatches,
		"ray_surface_distance_error_world":_r8_summary(ray_errors),"ray_records":ray_records,
		"sphere_probe_count":sphere_records.size(),"expected_sphere_probe_count":36,
		"sphere_contact_error_world":_r8_summary(sphere_errors),"sphere_records":sphere_records,
		"godot_physics_proxy":"NOT_MEASURED_IN_R8; prior experimental harness waits on a headless physics-frame signal and did not provide a bounded completion in run-002",
		"limitations":"two-sided Moller-Trumbore and point-to-triangle tests describe the emitted triangle geometry; they do not establish Godot PhysicsServer behavior, production colliders, continuous collision or a product tolerance"}


func _r8_first_surface_distance(origin:Vector3,direction:Vector3,snapshot:Dictionary,max_distance:float)->float:
	var previous:float=Transition.sample_canonical(SEED,origin,snapshot)
	if absf(previous)<=1.0e-12:return 0.0
	var previous_positive:=previous>0.0
	var prior_distance:=0.0
	var steps:=ceili(max_distance/0.025)
	for i in range(1,steps+1):
		var distance:=minf(float(i)*0.025,max_distance)
		var value:float=Transition.sample_canonical(SEED,origin+direction*distance,snapshot)
		if (previous_positive and value<=0.0) or (not previous_positive and value>=0.0):
			var low:=prior_distance;var high:=distance
			for _iteration in range(24):
				var middle:float=(low+high)*0.5
				var middle_value:float=Transition.sample_canonical(SEED,origin+direction*middle,snapshot)
				if (previous_positive and middle_value>0.0) or (not previous_positive and middle_value<0.0):low=middle
				else:high=middle
			return (low+high)*0.5
		prior_distance=distance;previous=value;previous_positive=previous>0.0
	return -1.0


func _r8_write_evidence(file_name:String,record:Dictionary)->void:
	if _r8_evidence_dir.is_empty():return
	var path:=_r8_evidence_dir.path_join(file_name)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return
	file.store_string(JSON.stringify(record)+"\n")
	file.flush()


func _r8_packed_summaries(values:Dictionary)->Dictionary:
	var result:Dictionary={}
	for key in values:result[String(key)]=_r8_summary(values[key])
	return result


func _r8_summary(values:PackedFloat64Array)->Dictionary:
	if values.is_empty():return {"count":0,"min":NAN,"p50":NAN,"p95":NAN,"max":NAN}
	var sorted:Array[float]=[];for value in values:sorted.append(value);sorted.sort()
	return {"count":sorted.size(),"min":sorted.front(),"p50":_r8_percentile(sorted,0.5),"p95":_r8_percentile(sorted,0.95),"max":sorted.back()}


func _r8_percentile(sorted:Array[float],q:float)->float:
	return sorted[clampi(ceili(q*sorted.size())-1,0,sorted.size()-1)]


func _r8_emit(name:String,record:Dictionary)->void:
	_r8_phase_records.append({"phase":name,"record":record})
	var payload:Dictionary={"phase":name,"record":record}
	_r8_write_evidence("phase-%02d-%s.json" % [_r8_phase_records.size(),name],payload)
	print("P3_1_R8_JSON "+JSON.stringify(payload))


func _r8_finish(status:String,reason:String)->void:
	var result:Dictionary={"suite":"P3_1_R8_GEOMETRY_QUALITY_DIAGNOSTIC","status":status,
		"reason":reason,"assertions":_r8_assertions,"failures":_r8_failures,
		"elapsed_usec":Time.get_ticks_usec()-_r8_started_usec,"phase_count":_r8_phase_records.size(),
		"phases":_r8_phase_records,"owner_geometry_tolerances":"NONE_APPROVED",
		"production_change":false,"production_read":false,"save_access":false}
	print("P3_1_R8_RESULT "+JSON.stringify(result))
	quit(0 if status=="DIAGNOSTIC_COMPLETE" else 1)
