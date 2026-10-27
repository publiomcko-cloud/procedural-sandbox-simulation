extends SceneTree

## Bounded R7.1 causal experiment over the exact frozen R7 zero-edit field.
## This script is test-only and never loads a playable scene or user save.
const Fixture := preload("res://tests/prototypes/p3_1_r7_conforming_mesh_fixture.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const FIELD := preload("res://scripts/terrain/sdf_world.gd")

const SEED := 131102026
const FOCUS_CELL_IDS := [1101, 1149, 1150, 1199]
const MODES := [
	{"interpolation": "production", "drop": "production", "tetra": "production"},
	{"interpolation": "mirror_production", "drop": "mirror_production", "tetra": "production"},
	{"interpolation": "exact_denominator", "drop": "mirror_production", "tetra": "production"},
	{"interpolation": "mirror_production", "drop": "reject_only_exact_zero", "tetra": "production"},
	{"interpolation": "exact_denominator", "drop": "reject_only_exact_zero", "tetra": "production"},
	{"interpolation": "exact_denominator", "drop": "mirror_production", "tetra": "mirror_x_diagonal"},
	{"interpolation": "exact_denominator", "drop": "reject_only_exact_zero", "tetra": "mirror_x_diagonal"},
]

var _failures: Array[String] = []
var _assertions := 0
var _baseline_positions := PackedVector3Array()
var _baseline_normals := PackedVector3Array()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture = Fixture.new()
	var configured: bool = fixture.configure(SEED, {})
	_check(configured, "frozen_zero_snapshot_configures")
	if not configured:
		_finish()
		return
	var trace_emitted := false
	for mode_value in MODES:
		var mode: Dictionary = mode_value
		var mode_ok: bool = fixture.configure_r71_polygonizer(String(mode.interpolation), String(mode.drop), String(mode.tetra))
		_check(mode_ok, "diagnostic_polygonizer_mode_supported_%s_%s_%s" % [mode.interpolation, mode.drop, mode.tetra])
		if not mode_ok:
			continue
		var started_usec := Time.get_ticks_usec()
		var built: Dictionary = fixture.build_approach("A_conforming_propagation")
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		_check(bool(built.get("valid", false)), "full_conforming_reference_mesh_built_%s_%s" % [mode.interpolation, mode.drop])
		if not bool(built.get("valid", false)):
			print("R71_VARIANT " + JSON.stringify({"mode": mode, "valid": false, "reason": built.get("reason", "unknown")}))
			continue
		var stats: Dictionary = built.get("stats", {})
		var topology: Dictionary = stats.get("topology", {})
		var positions: PackedVector3Array = built.get("positions", PackedVector3Array())
		var normals: PackedVector3Array = built.get("normals", PackedVector3Array())
		var report: Dictionary = {"scenario_id": "P3.1.R7.ZERO_EDIT.v1", "seed": SEED,
			"ledger_revision": 0, "input_sha256": "24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b",
			"mode": mode, "elapsed_usec": elapsed_usec, "mesh_sha256": _mesh_sha256(positions, normals),
			"triangle_count": int(stats.get("triangle_count", -1)),
			"topology": topology, "r71_polygonizer": stats.get("r71_polygonizer", {}), "valid": true}
		if mode.drop == "reject_only_exact_zero":
			report["inclusive_nonzero_triangle_incidence"] = _inclusive_nonzero_topology(fixture, positions)
		if mode.interpolation == "production":
			_baseline_positions = positions.duplicate()
			_baseline_normals = normals.duplicate()
		else:
			report["production_mesh_comparison"] = _compare_with_baseline(positions, normals)
		if not trace_emitted:
			report["focused_cell_trace"] = _focused_cell_trace(fixture)
			trace_emitted = true
		if mode.drop == "reject_only_exact_zero":
			report["focused_cell_trace_with_subthreshold_triangles"] = _focused_cell_trace(fixture)
		print("R71_VARIANT " + JSON.stringify(report))
	_finish()


func _focused_cell_trace(fixture) -> Dictionary:
	var focus: Dictionary = {}
	var wanted: Dictionary = {}
	for id_value in FOCUS_CELL_IDS:
		var id := int(id_value)
		var cell := _cell_from_id(id)
		wanted[id] = true
		for face_value in Fixture.FACE_DIRECTIONS:
			var face: Dictionary = face_value
			var neighbor: Vector3i = cell + Vector3i(face.delta)
			if neighbor.x < 0 or neighbor.x >= Fixture.CELL_DIMS.x \
				or neighbor.y < 0 or neighbor.y >= Fixture.CELL_DIMS.y \
				or neighbor.z < 0 or neighbor.z >= Fixture.CELL_DIMS.z:
				continue
			wanted[_cell_id(neighbor)] = true
	for id_value in wanted:
		var id := int(id_value)
		var cell := _cell_from_id(id)
		var values: PackedFloat32Array = fixture.refined_cells.get(id, PackedFloat32Array())
		if values.size() != 27:
			focus[str(id)] = {"cell": [cell.x, cell.y, cell.z], "sample_state": "NOT_REFINED"}
			continue
		var samples: Array[Dictionary] = []
		for sy in range(3):
			for sz in range(3):
				for sx in range(3):
					var sample_index := (sy * 3 + sz) * 3 + sx
					var density: float = values[sample_index]
					var world := Fixture.PATCH_MIN + Vector3(cell * 2 + Vector3i(sx, sy, sz)) * Fixture.FINE_STEP
					samples.append({"sample_index": sample_index, "fine_lattice": [cell.x * 2 + sx, cell.y * 2 + sy, cell.z * 2 + sz],
						"world": [world.x, world.y, world.z], "density_f32": density, "bits_le_hex": _float32_hex(density),
						"classification": "solid_ge_zero" if density >= 0.0 else "empty_negative",
						"exact_zero": density == 0.0, "near_zero_abs_le_1e-5": absf(density) <= 1.0e-5})
		var tetra_records: Array[Dictionary] = []
		for sy in range(2):
			for sz in range(2):
				for sx in range(2):
					var subcell := Vector3i(sx, sy, sz)
					var points: Array[Vector3] = []
					var densities: Array[float] = []
					for corner_value in Mesher.CORNERS:
						var corner: Vector3i = corner_value
						var sample_index := subcell + corner
						points.append(Fixture.PATCH_MIN + Vector3(cell * 2 + sample_index) * Fixture.FINE_STEP)
						densities.append(float(values[_fine_index(sample_index.x, sample_index.y, sample_index.z)]))
					for tetra_index in range(Mesher.TETRAHEDRA.size()):
						var tetra: Array = Mesher.TETRAHEDRA[tetra_index]
						var inside: Array[int] = []
						var outside: Array[int] = []
						var min_abs := INF
						var crossing: Array[Dictionary] = []
						for corner_value in tetra:
							var corner := int(corner_value)
							min_abs = minf(min_abs, absf(densities[corner]))
							if densities[corner] >= 0.0: inside.append(corner)
							else: outside.append(corner)
						for first in inside:
							for second in outside:
								var a_value: float = densities[first]
								var b_value: float = densities[second]
								var denominator := a_value - b_value
								var exact_t := a_value / denominator
								var production_t := 0.5 if is_zero_approx(denominator) else clampf(exact_t, 0.0, 1.0)
								var root_production := points[first].lerp(points[second], production_t)
								var root_exact := points[first].lerp(points[second], clampf(exact_t, 0.0, 1.0))
								crossing.append({"edge_corner_indices": [first, second], "endpoint_f32": [_float32_hex(a_value), _float32_hex(b_value)],
									"denominator": denominator, "godot_is_zero_approx_denominator": is_zero_approx(denominator),
									"production_weight": production_t, "exact_weight": exact_t,
									"production_point": [root_production.x, root_production.y, root_production.z],
									"exact_linear_root_point": [root_exact.x, root_exact.y, root_exact.z],
									"root_displacement_world": root_production.distance_to(root_exact)})
						var tet_positions := PackedVector3Array()
						var tet_normals := PackedVector3Array()
						fixture._polygonize_cell_tetra(tetra, points, densities, tet_positions, tet_normals)
						var triangles: Array[Dictionary] = []
						for index in range(0, tet_positions.size(), 3):
							var a: Vector3 = tet_positions[index]
							var b: Vector3 = tet_positions[index + 1]
							var c: Vector3 = tet_positions[index + 2]
							var normal := (b - a).cross(c - a)
							triangles.append({"vertices": [_v3(a), _v3(b), _v3(c)], "winding_cross": _v3(normal),
								"cross_length_squared": normal.length_squared(), "normal": _v3(tet_normals[index])})
						if not crossing.is_empty() or min_abs <= 1.0e-5:
							tetra_records.append({"coarse_cell_id": id, "subcell": [sx, sy, sz],
								"cube_tetrahedron_index": tetra_index, "tetra_corner_order": tetra.duplicate(),
								"tetra_world_vertices": [_v3(points[int(tetra[0])]), _v3(points[int(tetra[1])]), _v3(points[int(tetra[2])]), _v3(points[int(tetra[3])])],
								"tetra_density_f32": [densities[int(tetra[0])], densities[int(tetra[1])], densities[int(tetra[2])], densities[int(tetra[3])]],
								"tetra_density_bits": [_float32_hex(densities[int(tetra[0])]), _float32_hex(densities[int(tetra[1])]), _float32_hex(densities[int(tetra[2])]), _float32_hex(densities[int(tetra[3])])],
								"solid_corner_indices": inside, "empty_corner_indices": outside, "min_abs_density": min_abs,
								"crossing_edges": crossing, "emitted_triangles": triangles})
		var near_zero_count := 0
		var exact_zero_count := 0
		for sample in samples:
			if bool(sample.get("near_zero_abs_le_1e-5", false)): near_zero_count += 1
			if bool(sample.get("exact_zero", false)): exact_zero_count += 1
		focus[str(id)] = {"cell": [cell.x, cell.y, cell.z], "source": "PackedFloat32Array canonical samples used by frozen R7 fixture",
			"samples_27": samples, "near_zero_sample_count": near_zero_count,
			"exact_zero_sample_count": exact_zero_count,
			"tetrahedra_crossing_or_near_zero": tetra_records}
	return {"owner_cell_ids": FOCUS_CELL_IDS, "focus_and_6_neighbors_cell_ids": wanted.keys(), "detailed_cells": focus,
		"interpretation": "Exact uint32 bits are little-endian IEEE-754 binary32 samples; production interpolation is compared with the direct linear zero root. Tetra corner order is the production constant order."}


func _cell_from_id(cell_id: int) -> Vector3i:
	var x := cell_id % Fixture.CELL_DIMS.x
	var z := int(floor(float(cell_id) / float(Fixture.CELL_DIMS.x))) % Fixture.CELL_DIMS.z
	var y := int(floor(float(cell_id) / float(Fixture.CELL_DIMS.x * Fixture.CELL_DIMS.z)))
	return Vector3i(x, y, z)


func _cell_id(cell: Vector3i) -> int:
	return cell.x + cell.z * Fixture.CELL_DIMS.x + cell.y * Fixture.CELL_DIMS.x * Fixture.CELL_DIMS.z


func _fine_index(x: int, y: int, z: int) -> int:
	return (y * 3 + z) * 3 + x


func _float32_hex(value: float) -> String:
	var bytes := PackedFloat32Array([value]).to_byte_array()
	return "0x%08x" % bytes.decode_u32(0)


func _v3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _mesh_sha256(positions: PackedVector3Array, normals: PackedVector3Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(PackedInt32Array([positions.size(), normals.size()]).to_byte_array())
	context.update(positions.to_byte_array())
	context.update(normals.to_byte_array())
	return context.finish().hex_encode()


func _compare_with_baseline(positions: PackedVector3Array, normals: PackedVector3Array) -> Dictionary:
	var exact_positions := positions == _baseline_positions
	var exact_normals := normals == _baseline_normals
	var mismatch_count := 0
	var first_mismatch := -1
	var max_position_delta := 0.0
	var max_normal_delta := 0.0
	var shared_positions := mini(positions.size(), _baseline_positions.size())
	var shared_normals := mini(normals.size(), _baseline_normals.size())
	for index in range(shared_positions):
		var delta := positions[index].distance_to(_baseline_positions[index])
		if delta != 0.0:
			mismatch_count += 1
			if first_mismatch < 0: first_mismatch = index
			max_position_delta = maxf(max_position_delta, delta)
	for index in range(shared_normals):
		max_normal_delta = maxf(max_normal_delta, normals[index].distance_to(_baseline_normals[index]))
	return {"production_positions_count": _baseline_positions.size(), "candidate_positions_count": positions.size(),
		"production_normals_count": _baseline_normals.size(), "candidate_normals_count": normals.size(),
		"positions_byte_identical": exact_positions, "normals_byte_identical": exact_normals,
		"same_ordered_position_count": shared_positions, "position_vertex_mismatch_count": mismatch_count,
		"first_position_mismatch_index": first_mismatch, "maximum_position_delta_world": max_position_delta,
		"maximum_normal_delta": max_normal_delta}


func _inclusive_nonzero_topology(fixture, positions: PackedVector3Array) -> Dictionary:
	var welded: Array[Vector3] = []
	var buckets: Dictionary = {}
	var counts: Dictionary = {}
	var geometries: Dictionary = {}
	var degenerate_exact := 0
	var subthreshold_triangles: Array[Dictionary] = []
	for index in range(0, positions.size(), 3):
		var a: Vector3 = positions[index]
		var b: Vector3 = positions[index + 1]
		var c: Vector3 = positions[index + 2]
		var cross_squared := (b - a).cross(c - a).length_squared()
		if cross_squared == 0.0:
			degenerate_exact += 1
			continue
		if cross_squared <= 1.0e-12:
			var centroid := (a + b + c) / 3.0
			var owner_cell := Vector3i(floori((centroid.x - Fixture.PATCH_MIN.x) / Fixture.COARSE_STEP),
				floori((centroid.y - Fixture.PATCH_MIN.y) / Fixture.COARSE_STEP),
				floori((centroid.z - Fixture.PATCH_MIN.z) / Fixture.COARSE_STEP))
			subthreshold_triangles.append({"triangle_index": index / 3,
				"candidate_only_triangle": true, "cross_length_squared": cross_squared,
				"cross_vector": _v3((b - a).cross(c - a)), "centroid_world": _v3(centroid),
				"estimated_coarse_owner_cell": [owner_cell.x, owner_cell.y, owner_cell.z],
				"estimated_coarse_owner_cell_id": owner_cell.x + owner_cell.z * Fixture.CELL_DIMS.x
					+ owner_cell.y * Fixture.CELL_DIMS.x * Fixture.CELL_DIMS.z,
				"vertices_world": [_v3(a), _v3(b), _v3(c)]})
		for pair in [[a, b], [b, c], [c, a]]:
			var first: int = fixture._weld_vertex_id(pair[0], welded, buckets)
			var second: int = fixture._weld_vertex_id(pair[1], welded, buckets)
			var edge: String = fixture._edge_id_key(first, second)
			counts[edge] = int(counts.get(edge, 0)) + 1
			if not geometries.has(edge): geometries[edge] = [mini(first, second), maxi(first, second)]
	var open := 0
	var internal_open := 0
	var external_open := 0
	var over_incident := 0
	for edge in counts:
		var count := int(counts[edge])
		if count == 1:
			open += 1
			var endpoints: Array = geometries[edge]
			var point_a: Vector3 = welded[int(endpoints[0])]
			var point_b: Vector3 = welded[int(endpoints[1])]
			if fixture._edge_on_patch_boundary_points(point_a, point_b): external_open += 1
			else: internal_open += 1
		elif count > 2:
			over_incident += 1
	return {"open_edge_count_including_nonzero_subthreshold_triangles": open,
		"internal_open_edges": internal_open, "external_open_edges": external_open,
		"edge_incidence_gt_two": over_incident, "exact_zero_area_triangles_excluded": degenerate_exact,
		"nonzero_triangles_below_frozen_cross_squared_cutoff": subthreshold_triangles,
		"interpretation": "Diagnostic only; counts nonzero triangles below the frozen 1e-12 cross-length-squared cutoff. Does not replace the acceptance topology gate."}


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	var result := {"suite": "P3_1_R7_1_CAUSAL_DIAGNOSTIC", "assertions": _assertions,
		"failures": _failures, "status": "FAIL" if not _failures.is_empty() else "PASS",
		"scope": "single frozen zero-edit input; test-only interpolation and degenerate-triangle variants"}
	print("R71_RESULT " + JSON.stringify(result))
	quit(1 if not _failures.is_empty() else 0)
