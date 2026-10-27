extends RefCounted

## Bounded, disposable mixed-resolution extraction fixture for P3.1 R7.
## The terrain edit ledger remains the sole authority; every fine node is
## sampled from the canonical SDF plus its ordered immutable snapshot.
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Transition := preload("res://scripts/experiments/lod01_transition_fixture.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")

const COARSE_STEP := 0.5
const FINE_STEP := 0.25
const REFINE_THRESHOLD := 0.02
const PATCH_MIN := Vector3(8.0, -2.0, 3.0)
const CELL_DIMS := Vector3i(8, 20, 12)
const MAX_PROPAGATION_RADIUS_CELLS := 64
const MAX_PROPAGATED_CELLS := 12000
const MAX_FINE_PAYLOAD_BYTES := 16 * 1024 * 1024
const MAX_MESH_TRIANGLES := 250000
const KEY_SCALE := 100000.0
const EQUALITY_EPSILON := 0.00001
const FACE_DIRECTIONS := [
	{"delta": Vector3i(-1, 0, 0), "face": 0}, {"delta": Vector3i(1, 0, 0), "face": 1},
	{"delta": Vector3i(0, -1, 0), "face": 2}, {"delta": Vector3i(0, 1, 0), "face": 3},
	{"delta": Vector3i(0, 0, -1), "face": 4}, {"delta": Vector3i(0, 0, 1), "face": 5},
]

var world_seed := 131102026
var brush_snapshot: Dictionary = {}
var coarse_nodes := PackedFloat32Array()
var refined_cells: Dictionary = {}
var refined_nodes_bytes := 0
var initial_refined_count := 0
var last_reason := ""
var last_build_stats: Dictionary = {}
var r71_interpolation_mode := "production"
var r71_drop_mode := "production"
var r71_tetra_mode := "production"
var r71_triangle_attempts := 0
var r71_triangle_dropped := 0


func configure_r71_polygonizer(interpolation_mode: String, drop_mode: String = "production",
		tetra_mode: String = "production") -> bool:
	if not ["production", "mirror_production", "exact_denominator"].has(interpolation_mode):
		return false
	if not ["production", "mirror_production", "reject_only_exact_zero"].has(drop_mode):
		return false
	if not ["production", "mirror_x_diagonal"].has(tetra_mode):
		return false
	r71_interpolation_mode = interpolation_mode
	r71_drop_mode = drop_mode
	r71_tetra_mode = tetra_mode
	r71_triangle_attempts = 0
	r71_triangle_dropped = 0
	return true


func configure(seed: int, snapshot: Dictionary) -> bool:
	last_reason = ""
	world_seed = seed
	brush_snapshot = snapshot.duplicate(true)
	if CELL_DIMS.x <= 0 or CELL_DIMS.y <= 0 or CELL_DIMS.z <= 0:
		last_reason = "invalid_patch_dimensions"
		return false
	coarse_nodes.resize((CELL_DIMS.x + 1) * (CELL_DIMS.y + 1) * (CELL_DIMS.z + 1))
	for y in range(CELL_DIMS.y + 1):
		for z in range(CELL_DIMS.z + 1):
			for x in range(CELL_DIMS.x + 1):
				var point := PATCH_MIN + Vector3(x, y, z) * COARSE_STEP
				var density := _canonical_sample(point)
				if not is_finite(density):
					last_reason = "non_finite_canonical_coarse_sample"
					return false
				coarse_nodes[_node_index(x, y, z)] = density
	var initial := _initial_refinement_mask()
	initial_refined_count = initial.size()
	if initial.is_empty():
		last_reason = "refinement_mask_empty"
		return false
	return true


func build_approach(approach: String) -> Dictionary:
	last_reason = ""
	refined_cells.clear()
	refined_nodes_bytes = 0
	var start_usec := Time.get_ticks_usec()
	var initial := _initial_refinement_mask()
	var propagation_radius := 0
	var final_mask: Dictionary
	match approach:
		"A_conforming_propagation":
			var propagation := _full_conforming_closure(initial)
			if not bool(propagation.get("valid", false)):
				return {"valid": false, "reason": propagation.get("reason", "propagation_failed"),
					"initial_refined_cells": initial.size(), "propagated_cell_count": propagation.get("cell_count", 0),
					"propagation_radius_cells": propagation.get("radius_cells", 0)}
			final_mask = propagation.mask
			propagation_radius = int(propagation.radius_cells)
		"B_shared_faces_transitions":
			final_mask = initial
		"C_hybrid_one_cell_halo":
			final_mask = _expand_mask(initial, 1)
		_:
			return {"valid": false, "reason": "unsupported_approach"}
	if final_mask.size() > MAX_PROPAGATED_CELLS:
		return {"valid": false, "reason": "propagation_cell_limit_exceeded",
			"initial_refined_cells": initial.size(), "propagated_cell_count": final_mask.size(),
			"propagation_radius_cells": propagation_radius}
	if not _materialize_fine_cells(final_mask):
		return {"valid": false, "reason": last_reason,
			"initial_refined_cells": initial.size(), "propagated_cell_count": final_mask.size(),
			"propagation_radius_cells": propagation_radius}
	if refined_nodes_bytes > MAX_FINE_PAYLOAD_BYTES:
		return {"valid": false, "reason": "fine_payload_limit_exceeded",
			"initial_refined_cells": initial.size(), "propagated_cell_count": final_mask.size(),
			"fine_payload_bytes": refined_nodes_bytes}
	var cells: Dictionary = {}
	var transition_cells := 0
	var coarse_cells := 0
	var fine_cell_count := 0
	var sample_started := Time.get_ticks_usec()
	for y in range(CELL_DIMS.y):
		for z in range(CELL_DIMS.z):
			for x in range(CELL_DIMS.x):
				var cell := Vector3i(x, y, z)
				var cell_id := _cell_id(cell)
				var geometry: Dictionary = {}
				if final_mask.has(cell_id):
					fine_cell_count += 1
					if not _fine_cell_has_surface(refined_cells[cell_id]):
						continue
					geometry = _build_fine_cell(cell, refined_cells[cell_id])
				else:
					var faces := _fine_neighbor_faces(cell, final_mask)
					if faces.is_empty() and not _coarse_cell_has_surface(cell):
						continue
					if faces.is_empty():
						geometry = _build_coarse_cell(cell)
						coarse_cells += 1
					else:
						geometry = _build_transition_cell(cell, faces, final_mask)
						transition_cells += 1
				if geometry.is_empty():
					return {"valid": false, "reason": last_reason if not last_reason.is_empty() else "cell_mesh_failed",
						"cell": [x, y, z]}
				if int(geometry.get("triangle_count", 0)) > 0:
					cells[cell_id] = geometry
	var build_usec := Time.get_ticks_usec() - start_usec
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var triangle_count := 0
	for cell_id in cells:
		var geometry: Dictionary = cells[cell_id]
		positions.append_array(geometry.vertices)
		normals.append_array(geometry.normals)
		triangle_count += int(geometry.triangle_count)
		if triangle_count > MAX_MESH_TRIANGLES:
			return {"valid": false, "reason": "mesh_triangle_limit_exceeded", "triangle_count": triangle_count}
	var topology := _topology_metrics(cells, positions)
	var seams := _interface_metrics(cells)
	var surface := _canonical_surface_metrics(positions, normals)
	last_build_stats = {
		"approach": approach,
		"valid": true,
		"cell_count": cells.size(),
		"coarse_cells_built": coarse_cells,
		"transition_cells_built": transition_cells,
		"fine_cells_considered": fine_cell_count,
		"initial_refined_cells": initial.size(),
		"propagated_cell_count": final_mask.size(),
		"propagation_radius_cells": propagation_radius,
		"fine_payload_bytes": refined_nodes_bytes,
		"coarse_node_bytes": coarse_nodes.size() * 4,
		"triangle_count": triangle_count,
		"r71_polygonizer": {"interpolation_mode": r71_interpolation_mode,
			"drop_mode": r71_drop_mode, "tetrahedron_mode": r71_tetra_mode,
			"candidate_triangle_count": r71_triangle_attempts,
			"dropped_triangle_count": r71_triangle_dropped},
		"vertex_count_triangle_soup": positions.size(),
		"build_usec_including_sampling_and_extraction": build_usec,
		"topology": topology,
		"actual_cell_interface_contours": seams,
		"canonical_surface": surface,
		"status_note": "test-only sampled mesh; no product tolerance or production collider is implied",
	}
	return {"valid": true, "cells": cells, "positions": positions, "normals": normals,
		"triangle_count": triangle_count, "stats": last_build_stats}


func sample_approach(point: Vector3, approach: String) -> float:
	if not point.is_finite():
		return NAN
	var coordinates := (point - PATCH_MIN) / COARSE_STEP
	if coordinates.x < 0.0 or coordinates.y < 0.0 or coordinates.z < 0.0 \
		or coordinates.x > CELL_DIMS.x or coordinates.y > CELL_DIMS.y or coordinates.z > CELL_DIMS.z:
		return _canonical_sample(point)
	var cell := Vector3i(mini(floori(coordinates.x), CELL_DIMS.x - 1),
		mini(floori(coordinates.y), CELL_DIMS.y - 1), mini(floori(coordinates.z), CELL_DIMS.z - 1))
	var use_fine := false
	match approach:
		"A_conforming_propagation": use_fine = true
		"B_shared_faces_transitions": use_fine = refined_cells.has(_cell_id(cell))
		"C_hybrid_one_cell_halo": use_fine = refined_cells.has(_cell_id(cell))
	if use_fine:
		var key := _cell_id(cell)
		if refined_cells.has(key):
			return _sample_fine_values(refined_cells[key], coordinates, cell)
		return _canonical_sample(point)
	return _sample_coarse(coordinates)


func _initial_refinement_mask() -> Dictionary:
	var mask: Dictionary = {}
	for y in range(CELL_DIMS.y):
		for z in range(CELL_DIMS.z):
			for x in range(CELL_DIMS.x):
				var minimum := INF
				var maximum := -INF
				for oy in range(2):
					for oz in range(2):
						for ox in range(2):
							var sample := float(coarse_nodes[_node_index(x + ox, y + oy, z + oz)])
							minimum = minf(minimum, sample)
							maximum = maxf(maximum, sample)
				var center := PATCH_MIN + (Vector3(x, y, z) + Vector3.ONE * 0.5) * COARSE_STEP
				var coarse_center := _sample_coarse(Vector3(x, y, z) + Vector3.ONE * 0.5)
				var exact_center := _canonical_sample(center)
				if (minimum <= 0.0 and maximum >= 0.0) or absf(exact_center - coarse_center) > REFINE_THRESHOLD:
					mask[_cell_id(Vector3i(x, y, z))] = true
	return mask


func _full_conforming_closure(initial: Dictionary) -> Dictionary:
	var total := CELL_DIMS.x * CELL_DIMS.y * CELL_DIMS.z
	if total > MAX_PROPAGATED_CELLS:
		return {"valid": false, "reason": "propagation_cell_limit_exceeded", "cell_count": total}
	if MAX_PROPAGATION_RADIUS_CELLS <= 0:
		return {"valid": false, "reason": "propagation_radius_limit_invalid"}
	# A pure no-transition strategy must make the connected experiment domain
	# uniformly fine. Any finer/coarser face inside that domain is nonconforming.
	# The BFS computes the maximum nearest-seed propagation distance for evidence.
	var distances: Dictionary = {}
	var queue: Array[Vector3i] = []
	for cell_id in initial:
		var cell := _cell_from_id(int(cell_id))
		distances[int(cell_id)] = 0
		queue.append(cell)
	var cursor := 0
	var maximum_radius := 0
	while cursor < queue.size():
		var cell: Vector3i = queue[cursor]
		cursor += 1
		var distance := int(distances[_cell_id(cell)])
		maximum_radius = maxi(maximum_radius, distance)
		for direction in FACE_DIRECTIONS:
			var delta: Vector3i = direction.delta
			var neighbor: Vector3i = cell + delta
			if not _cell_in_bounds(neighbor):
				continue
			var neighbor_id := _cell_id(neighbor)
			if distances.has(neighbor_id):
				continue
			distances[neighbor_id] = distance + 1
			queue.append(neighbor)
	if distances.size() != total:
		return {"valid": false, "reason": "propagation_domain_not_face_connected", "cell_count": distances.size()}
	if maximum_radius > MAX_PROPAGATION_RADIUS_CELLS:
		return {"valid": false, "reason": "propagation_radius_limit_exceeded", "cell_count": total,
			"radius_cells": maximum_radius}
	var mask: Dictionary = {}
	for cell_id in range(total):
		mask[cell_id] = true
	return {"valid": true, "mask": mask, "cell_count": total, "radius_cells": maximum_radius}


func _expand_mask(source: Dictionary, radius: int) -> Dictionary:
	var expanded: Dictionary = source.duplicate()
	var frontier: Dictionary = source.duplicate()
	for _layer in range(radius):
		var next_frontier: Dictionary = {}
		for cell_id in frontier:
			var cell := _cell_from_id(int(cell_id))
			for direction in FACE_DIRECTIONS:
				var delta: Vector3i = direction.delta
				var neighbor := cell + delta
				if not _cell_in_bounds(neighbor):
					continue
				var neighbor_id := _cell_id(neighbor)
				if expanded.has(neighbor_id):
					continue
				expanded[neighbor_id] = true
				next_frontier[neighbor_id] = true
		frontier = next_frontier
	return expanded


func _materialize_fine_cells(mask: Dictionary) -> bool:
	var side := 3
	for cell_id in mask:
		var cell := _cell_from_id(int(cell_id))
		var values := PackedFloat32Array()
		values.resize(side * side * side)
		for y in range(side):
			for z in range(side):
				for x in range(side):
					var grid_point := Vector3(cell) + Vector3(float(x), float(y), float(z)) * 0.5
					var world_point := PATCH_MIN + grid_point * COARSE_STEP
					var density := _canonical_sample(world_point)
					if not is_finite(density):
						last_reason = "fine_sample_non_finite"
						return false
					values[_fine_index(x, y, z)] = density
		refined_cells[int(cell_id)] = values
		refined_nodes_bytes += values.size() * 4
		if refined_nodes_bytes > MAX_FINE_PAYLOAD_BYTES:
			last_reason = "fine_payload_limit_exceeded"
			return false
	return true


func _build_fine_cell(cell: Vector3i, values: PackedFloat32Array) -> Dictionary:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for y in range(2):
		for z in range(2):
			for x in range(2):
				var cube_points: Array[Vector3] = []
				var cube_values: Array[float] = []
				for corner_value in Mesher.CORNERS:
					var corner: Vector3i = corner_value
					var subcell := Vector3i(x, y, z)
					var sample_index := subcell + corner
					cube_points.append(PATCH_MIN + Vector3(cell) * COARSE_STEP + Vector3(sample_index) * FINE_STEP)
					cube_values.append(_fine_value(values, sample_index.x, sample_index.y, sample_index.z))
				for tetra in Mesher.TETRAHEDRA:
					_polygonize_cell_tetra(tetra, cube_points, cube_values, positions, normals)
	return {"vertices": positions, "normals": normals, "triangle_count": positions.size() / 3}


func _build_coarse_cell(cell: Vector3i) -> Dictionary:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var cube_points: Array[Vector3] = []
	var cube_values: Array[float] = []
	for corner_value in Mesher.CORNERS:
		var corner: Vector3i = corner_value
		var sample_index := cell + corner
		cube_points.append(PATCH_MIN + Vector3(sample_index) * COARSE_STEP)
		cube_values.append(_node_value(sample_index.x, sample_index.y, sample_index.z))
	for tetra in Mesher.TETRAHEDRA:
		_polygonize_cell_tetra(tetra, cube_points, cube_values, positions, normals)
	return {"vertices": positions, "normals": normals, "triangle_count": positions.size() / 3}


func _polygonize_cell_tetra(tetra: Array, cube_points: Array[Vector3], cube_values: Array[float],
		positions: PackedVector3Array, normals: PackedVector3Array) -> int:
	if r71_interpolation_mode == "production" and r71_drop_mode == "production" and r71_tetra_mode == "production":
		return Mesher._polygonize_tetra(tetra, cube_points, cube_values, positions, normals)
	var effective_tetra := _r71_transform_tetra(tetra)
	var inside: Array[int] = []
	var outside: Array[int] = []
	for corner_value in effective_tetra:
		var corner := int(corner_value)
		if cube_values[corner] >= 0.0:
			inside.append(corner)
		else:
			outside.append(corner)
	if inside.is_empty() or outside.is_empty():
		return 0
	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	for corner in inside: inside_center += cube_points[corner]
	for corner in outside: outside_center += cube_points[corner]
	inside_center /= float(inside.size())
	outside_center /= float(outside.size())
	var toward_empty := outside_center - inside_center
	var made := 0
	if inside.size() == 1:
		made += _r71_add_interpolated_triangle(inside[0], outside[0], inside[0], outside[1], inside[0], outside[2],
			cube_points, cube_values, toward_empty, positions, normals)
	elif inside.size() == 3:
		made += _r71_add_interpolated_triangle(outside[0], inside[0], outside[0], inside[1], outside[0], inside[2],
			cube_points, cube_values, toward_empty, positions, normals)
	else:
		made += _r71_add_interpolated_triangle(inside[0], outside[0], inside[0], outside[1], inside[1], outside[1],
			cube_points, cube_values, toward_empty, positions, normals)
		made += _r71_add_interpolated_triangle(inside[0], outside[0], outside[1], inside[1], inside[1], outside[0],
			cube_points, cube_values, toward_empty, positions, normals)
	return made


func _r71_transform_tetra(tetra: Array) -> Array:
	if r71_tetra_mode == "production":
		return tetra
	# Mirror the globally consistent 0-6 body diagonal across X, yielding 1-7.
	const X_MIRROR_CORNER := [1, 0, 3, 2, 5, 4, 7, 6]
	var transformed: Array = []
	for corner_value in tetra:
		transformed.append(X_MIRROR_CORNER[int(corner_value)])
	return transformed


func _r71_add_interpolated_triangle(a0: int, a1: int, b0: int, b1: int, c0: int, c1: int,
		cube_points: Array[Vector3], cube_values: Array[float], toward_empty: Vector3,
		positions: PackedVector3Array, normals: PackedVector3Array) -> int:
	var a := _r71_interpolate(a0, a1, cube_points, cube_values)
	var b := _r71_interpolate(b0, b1, cube_points, cube_values)
	var c := _r71_interpolate(c0, c1, cube_points, cube_values)
	r71_triangle_attempts += 1
	var normal := (b - a).cross(c - a)
	var threshold := 0.000000000001 if r71_drop_mode != "reject_only_exact_zero" else 0.0
	if normal.length_squared() <= threshold:
		r71_triangle_dropped += 1
		return 0
	if normal.dot(toward_empty) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	positions.append(a)
	positions.append(b)
	positions.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	return 1


func _r71_interpolate(a_index: int, b_index: int, cube_points: Array[Vector3], cube_values: Array[float]) -> Vector3:
	var a_value := cube_values[a_index]
	var b_value := cube_values[b_index]
	var denominator := a_value - b_value
	var weight := 0.5
	if r71_interpolation_mode == "exact_denominator":
		if denominator != 0.0:
			weight = clampf(a_value / denominator, 0.0, 1.0)
	else:
		weight = 0.5 if is_zero_approx(denominator) else clampf(a_value / denominator, 0.0, 1.0)
	return cube_points[a_index].lerp(cube_points[b_index], weight)


func _build_transition_cell(cell: Vector3i, faces: Array[int], mask: Dictionary) -> Dictionary:
	var origin := PATCH_MIN + Vector3(cell) * COARSE_STEP
	var local_sampler: Callable = func(point: Vector3) -> float:
		var world_point := origin + point * COARSE_STEP
		for face in faces:
			var neighbor := _neighbor_for_face(cell, face)
			if _point_on_face(world_point, cell, face):
				if mask.has(_cell_id(neighbor)):
					return _sample_cell(neighbor, world_point, true)
		return _sample_cell(cell, world_point, false)
	# R7 deliberately exercises the existing boundary-fan/tetrahedron machinery
	# beyond the production fixture's one-to-three nonopposing-face API. This
	# wrapper is experimental and accepts a pattern only when full interface
	# contour/topology diagnostics subsequently confirm it.
	var built: Dictionary = _build_r7_transition_cell(faces, local_sampler)
	if not built.get("valid", false):
		last_reason = String(built.get("reason", "transition_cell_extract_failed"))
		return {}
	return _transform_geometry(built, origin, COARSE_STEP)


func _build_r7_transition_cell(faces: Array[int], sampler: Callable) -> Dictionary:
	if faces.is_empty() or faces.size() > 6:
		return {"valid": false, "reason": "transition_face_count_invalid"}
	var unique: Array[int] = []
	for face in faces:
		if face < 0 or face > 5 or unique.has(face):
			return {"valid": false, "reason": "transition_face_set_invalid"}
		unique.append(face)
	var builder: RefCounted = Transition.new()
	builder._center = Vector3.ONE * 0.5
	builder._sampler = sampler
	builder._world_seed = world_seed
	builder._brush_snapshot = {}
	var started_usec := Time.get_ticks_usec()
	var triangles: Array = Transition._boundary_triangles(Vector3i.ZERO, unique)
	var center_id: int = builder._add_sample_point(builder._center, world_seed, {})
	if center_id < 0:
		return builder._failure_result()
	for triangle in triangles:
		var a: int = builder._add_sample_point(triangle[0], world_seed, {})
		var b: int = builder._add_sample_point(triangle[1], world_seed, {})
		var c: int = builder._add_sample_point(triangle[2], world_seed, {})
		if a < 0 or b < 0 or c < 0:
			return builder._failure_result()
		var tetra_ids: Array[int] = [center_id, a, b, c]
		builder._polygonize_tetra(tetra_ids)
		if not builder._failure_reason.is_empty():
			return builder._failure_result()
	var no_coarse_faces: Array[int] = []
	return builder._make_result(world_seed, Vector3i.ZERO, unique,
		no_coarse_faces, 0, Time.get_ticks_usec() - started_usec, "r7_multi_face_transition")


func _transform_geometry(source: Dictionary, origin: Vector3, scale: float) -> Dictionary:
	var source_vertices: PackedVector3Array = source.get("vertices", PackedVector3Array())
	var source_normals: PackedVector3Array = source.get("normals", PackedVector3Array())
	if source_vertices.size() != source_normals.size() or source_vertices.size() % 3 != 0:
		last_reason = "mesh_attribute_count_invalid"
		return {}
	var vertices := PackedVector3Array()
	var normals := source_normals.duplicate()
	vertices.resize(source_vertices.size())
	for index in range(source_vertices.size()):
		vertices[index] = origin + source_vertices[index] * scale
		if not vertices[index].is_finite() or not normals[index].is_finite():
			last_reason = "mesh_output_non_finite"
			return {}
	return {"vertices": vertices, "normals": normals, "triangle_count": vertices.size() / 3}


func _fine_neighbor_faces(cell: Vector3i, mask: Dictionary) -> Array[int]:
	var faces: Array[int] = []
	for direction in FACE_DIRECTIONS:
		var delta: Vector3i = direction.delta
		var neighbor: Vector3i = cell + delta
		if _cell_in_bounds(neighbor) and mask.has(_cell_id(neighbor)):
			faces.append(int(direction.face))
	return faces


func _has_opposing_faces(faces: Array[int]) -> bool:
	for face in faces:
		if faces.has(face ^ 1):
			return true
	return false


func _neighbor_for_face(cell: Vector3i, face: int) -> Vector3i:
	return cell + FACE_DIRECTIONS[face].delta


func _point_on_face(point: Vector3, cell: Vector3i, face: int) -> bool:
	var origin := PATCH_MIN + Vector3(cell) * COARSE_STEP
	var axis := face >> 1
	var face_coordinate := origin[axis] + (COARSE_STEP if face % 2 == 1 else 0.0)
	return absf(point[axis] - face_coordinate) <= EQUALITY_EPSILON


func _sample_cell(cell: Vector3i, point: Vector3, force_fine: bool) -> float:
	var coordinates := (point - PATCH_MIN) / COARSE_STEP
	var key := _cell_id(cell)
	if force_fine or refined_cells.has(key):
		if refined_cells.has(key):
			return _sample_fine_values(refined_cells[key], coordinates, cell)
		return _canonical_sample(point)
	return _sample_coarse_cell(coordinates, cell)


func _sample_coarse(coordinates: Vector3) -> float:
	var cell := Vector3i(mini(floori(coordinates.x), CELL_DIMS.x - 1),
		mini(floori(coordinates.y), CELL_DIMS.y - 1), mini(floori(coordinates.z), CELL_DIMS.z - 1))
	return _sample_coarse_cell(coordinates, cell)


func _sample_coarse_cell(coordinates: Vector3, cell: Vector3i) -> float:
	var local := coordinates - Vector3(cell)
	var x := clampf(local.x, 0.0, 1.0)
	var y := clampf(local.y, 0.0, 1.0)
	var z := clampf(local.z, 0.0, 1.0)
	var c000 := _node_value(cell.x, cell.y, cell.z)
	var c100 := _node_value(cell.x + 1, cell.y, cell.z)
	var c010 := _node_value(cell.x, cell.y + 1, cell.z)
	var c110 := _node_value(cell.x + 1, cell.y + 1, cell.z)
	var c001 := _node_value(cell.x, cell.y, cell.z + 1)
	var c101 := _node_value(cell.x + 1, cell.y, cell.z + 1)
	var c011 := _node_value(cell.x, cell.y + 1, cell.z + 1)
	var c111 := _node_value(cell.x + 1, cell.y + 1, cell.z + 1)
	return lerpf(lerpf(lerpf(c000, c100, x), lerpf(c010, c110, x), y),
		lerpf(lerpf(c001, c101, x), lerpf(c011, c111, x), y), z)


func _sample_fine_values(values: PackedFloat32Array, coordinates: Vector3, cell: Vector3i) -> float:
	var local := (coordinates - Vector3(cell)) * 2.0
	var x0 := clampi(floori(local.x), 0, 1)
	var y0 := clampi(floori(local.y), 0, 1)
	var z0 := clampi(floori(local.z), 0, 1)
	var x := clampf(local.x - x0, 0.0, 1.0)
	var y := clampf(local.y - y0, 0.0, 1.0)
	var z := clampf(local.z - z0, 0.0, 1.0)
	var c000 := _fine_value(values, x0, y0, z0)
	var c100 := _fine_value(values, x0 + 1, y0, z0)
	var c010 := _fine_value(values, x0, y0 + 1, z0)
	var c110 := _fine_value(values, x0 + 1, y0 + 1, z0)
	var c001 := _fine_value(values, x0, y0, z0 + 1)
	var c101 := _fine_value(values, x0 + 1, y0, z0 + 1)
	var c011 := _fine_value(values, x0, y0 + 1, z0 + 1)
	var c111 := _fine_value(values, x0 + 1, y0 + 1, z0 + 1)
	return lerpf(lerpf(lerpf(c000, c100, x), lerpf(c010, c110, x), y),
		lerpf(lerpf(c001, c101, x), lerpf(c011, c111, x), y), z)


func _fine_cell_has_surface(values: PackedFloat32Array) -> bool:
	for y in range(2):
		for z in range(2):
			for x in range(2):
				var minimum := INF
				var maximum := -INF
				for oy in range(2):
					for oz in range(2):
						for ox in range(2):
							var value := _fine_value(values, x + ox, y + oy, z + oz)
							minimum = minf(minimum, value)
							maximum = maxf(maximum, value)
				if minimum <= 0.0 and maximum >= 0.0:
					return true
	return false


func _coarse_cell_has_surface(cell: Vector3i) -> bool:
	var minimum := INF
	var maximum := -INF
	for oy in range(2):
		for oz in range(2):
			for ox in range(2):
				var value := _node_value(cell.x + ox, cell.y + oy, cell.z + oz)
				minimum = minf(minimum, value)
				maximum = maxf(maximum, value)
	return minimum <= 0.0 and maximum >= 0.0


func _topology_metrics(cells: Dictionary, positions: PackedVector3Array) -> Dictionary:
	var edge_counts: Dictionary = {}
	var edge_geometry: Dictionary = {}
	var edge_cell_owners: Dictionary = {}
	var welded_positions: Array[Vector3] = []
	var weld_buckets: Dictionary = {}
	var degenerate := 0
	for cell_id_value in cells:
		var cell_id := int(cell_id_value)
		var cell_vertices: PackedVector3Array = cells[cell_id].vertices
		for index in range(0, cell_vertices.size(), 3):
			var a: Vector3 = cell_vertices[index]
			var b: Vector3 = cell_vertices[index + 1]
			var c: Vector3 = cell_vertices[index + 2]
			if (b - a).cross(c - a).length_squared() <= 1.0e-12:
				degenerate += 1
				continue
			for pair in [[a, b], [b, c], [c, a]]:
				var first := _weld_vertex_id(pair[0], welded_positions, weld_buckets)
				var second := _weld_vertex_id(pair[1], welded_positions, weld_buckets)
				var edge := _edge_id_key(first, second)
				edge_counts[edge] = int(edge_counts.get(edge, 0)) + 1
				if not edge_geometry.has(edge):
					edge_geometry[edge] = [mini(first, second), maxi(first, second)]
				var owners: Array = edge_cell_owners.get(edge, [])
				owners.append(cell_id)
				edge_cell_owners[edge] = owners
	var open_edges := 0
	var external_open_edges := 0
	var internal_open_edges := 0
	var nonmanifold_edges := 0
	var internal_open_examples: Array[Dictionary] = []
	var external_open_examples: Array[Dictionary] = []
	var nearby_internal_open_examples: Array[Dictionary] = []
	for edge in edge_counts:
		var count := int(edge_counts[edge])
		if count == 1:
			open_edges += 1
			var endpoints: Array = edge_geometry[edge]
			var point_a: Vector3 = welded_positions[int(endpoints[0])]
			var point_b: Vector3 = welded_positions[int(endpoints[1])]
			if _edge_on_patch_boundary_points(point_a, point_b):
				external_open_edges += 1
				if external_open_examples.size() < 12:
					external_open_examples.append({"quantized_edge_id": String(edge),
						"welded_vertex_ids": edge_geometry[edge], "a": point_a, "b": point_b,
						"observed_incidence": count, "expected_incidence_for_patch_boundary": 1,
						"owner_cells": edge_cell_owners.get(edge, [])})
			else:
				internal_open_edges += 1
				if internal_open_examples.size() < 20:
					internal_open_examples.append({"quantized_edge_id": String(edge),
						"welded_vertex_ids": edge_geometry[edge], "a": point_a, "b": point_b,
						"observed_incidence": count, "expected_incidence_for_internal_edge": 2,
						"canonical_density_a": _canonical_sample(point_a),
						"canonical_density_b": _canonical_sample(point_b),
						"owner_cells": edge_cell_owners.get(edge, [])})
					var nearest_distance := INF
					var nearest_edge := ""
					for candidate in edge_counts:
						if candidate == edge or int(edge_counts[candidate]) != 1:
							continue
						var candidate_endpoints: Array = edge_geometry[candidate]
						var candidate_a: Vector3 = welded_positions[int(candidate_endpoints[0])]
						var candidate_b: Vector3 = welded_positions[int(candidate_endpoints[1])]
						var direct_distance := maxf(point_a.distance_to(candidate_a), point_b.distance_to(candidate_b))
						var reverse_distance := maxf(point_a.distance_to(candidate_b), point_b.distance_to(candidate_a))
						var candidate_distance := minf(direct_distance, reverse_distance)
						if candidate_distance < nearest_distance:
							nearest_distance = candidate_distance
							nearest_edge = "%s|%s" % [str(candidate_a), str(candidate_b)]
					if nearest_distance <= EQUALITY_EPSILON * 2.0:
						nearby_internal_open_examples.append({"edge": String(edge),
							"nearest_open_edge": nearest_edge, "endpoint_max_distance_world": nearest_distance})
		elif count != 2:
			nonmanifold_edges += 1
	return {"triangle_count": positions.size() / 3, "unique_undirected_edges": edge_counts.size(),
		"open_edge_count": open_edges, "expected_open_edge_count_at_patch_boundary": external_open_edges,
		"internal_open_edge_crack_count": internal_open_edges, "nonmanifold_edge_count": nonmanifold_edges,
		"degenerate_triangle_count": degenerate, "internal_open_edge_examples": internal_open_examples,
		"external_open_edge_examples": external_open_examples,
		"nearby_internal_open_edge_pairs_within_2x_weld_tolerance": nearby_internal_open_examples,
		"interpretation": "triangle-soup vertices clustered by actual Euclidean distance <= 1e-5 world units using neighboring spatial-hash buckets; external fixture boundary edges are reported separately"}


func _weld_vertex_id(point: Vector3, welded_positions: Array[Vector3], buckets: Dictionary) -> int:
	var bucket := Vector3i(floori(point.x / EQUALITY_EPSILON), floori(point.y / EQUALITY_EPSILON),
		floori(point.z / EQUALITY_EPSILON))
	for y_offset in range(-1, 2):
		for z_offset in range(-1, 2):
			for x_offset in range(-1, 2):
				var neighbor := bucket + Vector3i(x_offset, y_offset, z_offset)
				for candidate_value in buckets.get(neighbor, []):
					var candidate := int(candidate_value)
					if welded_positions[candidate].distance_squared_to(point) <= EQUALITY_EPSILON * EQUALITY_EPSILON:
						return candidate
	var result := welded_positions.size()
	welded_positions.append(point)
	var bucket_values: Array = buckets.get(bucket, [])
	bucket_values.append(result)
	buckets[bucket] = bucket_values
	return result


func _edge_id_key(first: int, second: int) -> String:
	return "%d|%d" % [first, second] if first < second else "%d|%d" % [second, first]


func _edge_on_patch_boundary_points(a: Vector3, b: Vector3) -> bool:
	for axis in range(3):
		if absf(a[axis] - b[axis]) > EQUALITY_EPSILON: continue
		if absf(a[axis] - PATCH_MIN[axis]) <= EQUALITY_EPSILON: return true
		var maximum := PATCH_MIN[axis] + float(CELL_DIMS[axis]) * COARSE_STEP
		if absf(a[axis] - maximum) <= EQUALITY_EPSILON: return true
	return false


func _interface_metrics(cells: Dictionary) -> Dictionary:
	var interfaces := 0
	var segments_mismatched := 0
	var t_junctions := 0
	var compared_segments := 0
	var max_normal_angle := 0.0
	var coplanar_surface_owned_interfaces := 0
	var duplicated_coplanar_surface_interfaces := 0
	var mismatch_examples: Array[Dictionary] = []
	for y in range(CELL_DIMS.y):
		for z in range(CELL_DIMS.z):
			for x in range(CELL_DIMS.x):
				var cell := Vector3i(x, y, z)
				var first_id := _cell_id(cell)
				for direction_value in [Vector3i.RIGHT, Vector3i.UP, Vector3i.BACK]:
					var direction: Vector3i = direction_value
					var neighbor := cell + direction
					if not _cell_in_bounds(neighbor):
						continue
					var second_id := _cell_id(neighbor)
					if not cells.has(first_id) and not cells.has(second_id):
						continue
					var axis := 0 if direction.x != 0 else (1 if direction.y != 0 else 2)
					var plane := (PATCH_MIN + Vector3(cell + direction) * COARSE_STEP)[axis]
					var first_segments := _cell_face_segments(cells.get(first_id, {}), axis, plane)
					var second_segments := _cell_face_segments(cells.get(second_id, {}), axis, plane)
					interfaces += 1
					var canonical_zero_face := _canonical_face_is_zero(cell, axis, plane)
					if canonical_zero_face:
						var first_coplanar := int(first_segments.coplanar_triangles)
						var second_coplanar := int(second_segments.coplanar_triangles)
						if first_coplanar > 0 and second_coplanar == 0 and second_segments.segments.is_empty():
							coplanar_surface_owned_interfaces += 1
							continue
						if second_coplanar > 0 and first_coplanar == 0 and first_segments.segments.is_empty():
							coplanar_surface_owned_interfaces += 1
							continue
						if first_coplanar > 0 and second_coplanar > 0:
							duplicated_coplanar_surface_interfaces += 1
					var unmatched_first: Array[Dictionary] = []
					var unmatched_second: Array[Dictionary] = []
					var used_second: Dictionary = {}
					var matched_here := 0
					for first_segment_value in first_segments.raw:
						var first_segment: Dictionary = first_segment_value
						var best_index := -1
						var best_reversed := false
						var best_distance := INF
						for candidate_index in range(second_segments.raw.size()):
							if used_second.has(candidate_index): continue
							var candidate: Dictionary = second_segments.raw[candidate_index]
							var direct_distance := maxf(Vector3(first_segment.a).distance_to(candidate.a),
								Vector3(first_segment.b).distance_to(candidate.b))
							var reverse_distance := maxf(Vector3(first_segment.a).distance_to(candidate.b),
								Vector3(first_segment.b).distance_to(candidate.a))
							var candidate_reversed := reverse_distance < direct_distance
							var candidate_distance := minf(direct_distance, reverse_distance)
							if candidate_distance < best_distance:
								best_distance = candidate_distance
								best_index = candidate_index
								best_reversed = candidate_reversed
						if best_index < 0 or best_distance > EQUALITY_EPSILON:
							unmatched_first.append(first_segment)
							continue
						used_second[best_index] = true
						matched_here += 1
						var matched_segment: Dictionary = second_segments.raw[best_index]
						var first_keys: Array = [first_segment.a_key, first_segment.b_key]
						var second_keys: Array = [matched_segment.b_key, matched_segment.a_key] if best_reversed \
							else [matched_segment.a_key, matched_segment.b_key]
						for endpoint_index in range(2):
							var first_normal: Vector3 = first_segments.normals.get(first_keys[endpoint_index], Vector3.ZERO)
							var second_normal: Vector3 = second_segments.normals.get(second_keys[endpoint_index], Vector3.ZERO)
							if first_normal.length_squared() > 1.0e-10 and second_normal.length_squared() > 1.0e-10:
								max_normal_angle = maxf(max_normal_angle,
									rad_to_deg(first_normal.angle_to(second_normal)))
					for second_index in range(second_segments.raw.size()):
						if not used_second.has(second_index): unmatched_second.append(second_segments.raw[second_index])
					var mismatch := not unmatched_first.is_empty() or not unmatched_second.is_empty()
					if mismatch:
						segments_mismatched += 1
						if mismatch_examples.size() < 12:
							mismatch_examples.append({"cell_a": [cell.x, cell.y, cell.z],
								"cell_b": [neighbor.x, neighbor.y, neighbor.z], "axis": axis, "plane": plane,
								"segment_count_a": first_segments.raw.size(), "segment_count_b": second_segments.raw.size(),
								"matched_within_tolerance": matched_here,
								"first_only_sample": unmatched_first.slice(0, mini(4, unmatched_first.size())),
								"second_only_sample": unmatched_second.slice(0, mini(4, unmatched_second.size()))})
					var points: Dictionary = {}
					for key in first_segments.points: points[key] = first_segments.points[key]
					for key in second_segments.points: points[key] = second_segments.points[key]
					var segments: Array = []
					for segment in first_segments.raw: segments.append(segment)
					for segment in second_segments.raw: segments.append(segment)
					for segment in segments:
						for point_key in points:
							if point_key == segment.a_key or point_key == segment.b_key: continue
							if _point_strictly_inside_segment(points[point_key], segment.a, segment.b):
								t_junctions += 1
					compared_segments += matched_here
	return {"internal_cell_interfaces_checked": interfaces,
		"interfaces_with_nonmatching_extracted_contours": segments_mismatched,
		"exact_zero_face_surfaces_owned_once": coplanar_surface_owned_interfaces,
		"duplicate_coplanar_surface_interfaces": duplicated_coplanar_surface_interfaces,
		"strict_t_junction_vertex_on_contour_segment_count": t_junctions,
		"matching_contour_segments_compared": compared_segments,
		"maximum_shared_endpoint_normal_angle_degrees": max_normal_angle,
		"first_mismatch_examples": mismatch_examples,
		"oracle": "actual triangle-mesh contour segments matched by endpoint distance <= 1e-5 world units, with per-endpoint normals on each shared macro-cell face"}


func _cell_face_segments(geometry: Dictionary, axis: int, plane: float) -> Dictionary:
	var segments: Dictionary = {}
	var raw: Array[Dictionary] = []
	var points: Dictionary = {}
	var normals: Dictionary = {}
	var endpoints: Dictionary = {}
	var coplanar_triangles := 0
	if geometry.is_empty():
		return {"segments": segments, "raw": raw, "points": points, "normals": normals,
			"segment_endpoints": endpoints, "coplanar_triangles": 0}
	var vertices: PackedVector3Array = geometry.vertices
	var vertex_normals: PackedVector3Array = geometry.normals
	for index in range(0, vertices.size(), 3):
		var triangle_on_face := true
		for vertex_offset in range(3):
			if absf(vertices[index + vertex_offset][axis] - plane) > EQUALITY_EPSILON:
				triangle_on_face = false
				break
		if triangle_on_face:
			coplanar_triangles += 1
			continue
		for edge_index in range(3):
			var a: Vector3 = vertices[index + edge_index]
			var b: Vector3 = vertices[index + ((edge_index + 1) % 3)]
			if absf(a[axis] - plane) > EQUALITY_EPSILON or absf(b[axis] - plane) > EQUALITY_EPSILON:
				continue
			if a.distance_squared_to(b) <= 1.0e-14:
				continue
			var a_key := _point_key(a)
			var b_key := _point_key(b)
			var key := _edge_key(a_key, b_key)
			segments[key] = true
			points[a_key] = a
			points[b_key] = b
			normals[a_key] = (Vector3(normals.get(a_key, Vector3.ZERO)) + vertex_normals[index + edge_index]).normalized()
			normals[b_key] = (Vector3(normals.get(b_key, Vector3.ZERO)) + vertex_normals[index + ((edge_index + 1) % 3)]).normalized()
			endpoints[key] = [a_key, b_key]
			if raw.is_empty() or not _raw_segments_contains_key(raw, key):
				raw.append({"a": a, "b": b, "a_key": a_key, "b_key": b_key})
	return {"segments": segments, "raw": raw, "points": points, "normals": normals,
		"segment_endpoints": endpoints, "coplanar_triangles": coplanar_triangles}


func _raw_segments_contains_key(raw: Array[Dictionary], key: String) -> bool:
	for segment in raw:
		if _edge_key(String(segment.a_key), String(segment.b_key)) == key:
			return true
	return false


func _canonical_face_is_zero(cell: Vector3i, axis: int, plane: float) -> bool:
	var origin := PATCH_MIN + Vector3(cell) * COARSE_STEP
	var u_axis := (axis + 1) % 3
	var v_axis := (axis + 2) % 3
	for u in [0.0, 0.5, 1.0]:
		for v in [0.0, 0.5, 1.0]:
			var point := origin
			point[axis] = plane
			point[u_axis] += float(u) * COARSE_STEP
			point[v_axis] += float(v) * COARSE_STEP
			if absf(_canonical_sample(point)) > 1.0e-7:
				return false
	return true


func _canonical_surface_metrics(positions: PackedVector3Array, normals: PackedVector3Array) -> Dictionary:
	if positions.is_empty():
		return {"valid": false, "reason": "mesh_empty"}
	var distances := PackedFloat64Array()
	var angles := PackedFloat64Array()
	var stride := maxi(1, ceili(float(positions.size()) / 512.0))
	for index in range(0, positions.size(), stride):
		var point: Vector3 = positions[index]
		var density := _canonical_sample(point)
		var h := 0.03125
		var gradient := Vector3(
			_canonical_sample(point + Vector3.RIGHT * h) - _canonical_sample(point - Vector3.RIGHT * h),
			_canonical_sample(point + Vector3.UP * h) - _canonical_sample(point - Vector3.UP * h),
			_canonical_sample(point + Vector3.BACK * h) - _canonical_sample(point - Vector3.BACK * h))
		if not is_finite(density) or not gradient.is_finite():
			return {"valid": false, "reason": "canonical_surface_probe_non_finite"}
		distances.append(absf(density) / maxf(gradient.length(), 1.0e-8))
		var candidate_normal := normals[index].normalized()
		if candidate_normal.length_squared() > 0.0 and gradient.length_squared() > 1.0e-10:
			angles.append(rad_to_deg(candidate_normal.angle_to(-gradient.normalized())))
	return {"valid": true, "vertex_to_canonical_sdf_distance_proxy_world": _summary(distances),
		"mesh_normal_to_canonical_gradient_angle_degrees": _summary(angles),
		"sampled_vertices": distances.size(), "method": "abs(canonical SDF)/finite-difference gradient magnitude; exploratory proxy, not Hausdorff certification"}


func _point_strictly_inside_segment(point: Vector3, a: Vector3, b: Vector3) -> bool:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 1.0e-14:
		return false
	var t := (point - a).dot(ab) / length_squared
	if t <= 1.0e-5 or t >= 1.0 - 1.0e-5:
		return false
	var closest := a + ab * t
	return point.distance_squared_to(closest) <= EQUALITY_EPSILON * EQUALITY_EPSILON


func _edge_on_patch_boundary(first: String, second: String) -> bool:
	var a := _point_from_key(first)
	var b := _point_from_key(second)
	for axis in range(3):
		if absf(a[axis] - b[axis]) > EQUALITY_EPSILON: continue
		if absf(a[axis] - PATCH_MIN[axis]) <= EQUALITY_EPSILON: return true
		var maximum := PATCH_MIN[axis] + float(CELL_DIMS[axis]) * COARSE_STEP
		if absf(a[axis] - maximum) <= EQUALITY_EPSILON: return true
	return false


func _node_index(x: int, y: int, z: int) -> int:
	return (y * (CELL_DIMS.z + 1) + z) * (CELL_DIMS.x + 1) + x


func _node_value(x: int, y: int, z: int) -> float:
	return float(coarse_nodes[_node_index(clampi(x, 0, CELL_DIMS.x), clampi(y, 0, CELL_DIMS.y), clampi(z, 0, CELL_DIMS.z))])


func _cell_id(cell: Vector3i) -> int:
	return (cell.y * CELL_DIMS.z + cell.z) * CELL_DIMS.x + cell.x


func _cell_from_id(cell_id: int) -> Vector3i:
	var x := cell_id % CELL_DIMS.x
	var z := floori(float(cell_id) / float(CELL_DIMS.x)) % CELL_DIMS.z
	var y := floori(float(cell_id) / float(CELL_DIMS.x * CELL_DIMS.z))
	return Vector3i(x, y, z)


func _cell_in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.x < CELL_DIMS.x and cell.y >= 0 and cell.y < CELL_DIMS.y \
		and cell.z >= 0 and cell.z < CELL_DIMS.z


func _fine_index(x: int, y: int, z: int) -> int:
	return (y * 3 + z) * 3 + x


func _fine_value(values: PackedFloat32Array, x: int, y: int, z: int) -> float:
	return float(values[_fine_index(clampi(x, 0, 2), clampi(y, 0, 2), clampi(z, 0, 2))])


func _canonical_sample(point: Vector3) -> float:
	# The frozen fixture occupies region (0,0); use its canonical snapshot API.
	return Transition.sample_canonical(world_seed, point, brush_snapshot)


func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * KEY_SCALE), roundi(point.y * KEY_SCALE), roundi(point.z * KEY_SCALE)]


func _point_from_key(key: String) -> Vector3:
	var parts := key.split(",")
	return Vector3(float(parts[0].to_int()), float(parts[1].to_int()), float(parts[2].to_int())) / KEY_SCALE


func _edge_key(first: String, second: String) -> String:
	return first + "|" + second if first < second else second + "|" + first


func _summary(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty(): return {"count": 0, "p50": NAN, "p95": NAN, "max": NAN}
	var sorted: Array[float] = []
	for value in values: sorted.append(value)
	sorted.sort()
	return {"count": sorted.size(), "p50": _percentile(sorted, 0.5),
		"p95": _percentile(sorted, 0.95), "max": sorted.back()}


func _percentile(values: Array[float], q: float) -> float:
	if values.is_empty(): return NAN
	var index := clampi(ceili(q * values.size()) - 1, 0, values.size() - 1)
	return values[index]
