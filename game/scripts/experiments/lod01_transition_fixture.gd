class_name Lod01TransitionFixture
extends RefCounted

## CPU-only LOD 0/1 transition-cell construction. P1.1A introduced it as an
## isolated fixture; P1.1C reuses this data-only builder from worker jobs.
## It owns no scene nodes and does not mutate the canonical edit ledger.
const FIELD := preload("res://scripts/terrain/sdf_world.gd")
const BRUSH := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const SPATIAL := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const LOD0_STEP := 0.5
const LOD1_STEP := 1.0
const LOD1_IN_LOD0_STEPS := 2
const NORMAL_EPSILON := 0.25
const FACE_X_NEG := 0
const FACE_X_POS := 1
const FACE_Y_NEG := 2
const FACE_Y_POS := 3
const FACE_Z_NEG := 4
const FACE_Z_POS := 5
const FACE_AXES := [0, 0, 1, 1, 2, 2]
const FACE_SIGNS := [-1, 1, -1, 1, -1, 1]
const CUBE_CORNERS := [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1),
]
const CUBE_TETRAHEDRA := [
	[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
	[0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6],
]

var _center := Vector3.ZERO
var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
# P2: sample identity remains dictionary-indexed, but hot sample payloads live
# in packed typed buffers instead of one Dictionary per sample.
var _sample_ids: Dictionary = {}
var _sample_points := PackedVector3Array()
var _sample_densities := PackedFloat64Array()
var _sampler := Callable()
var _world_seed := 424242
var _brush_snapshot: Dictionary = {}
var _sampling_usec := 0
var _normal_usec := 0
var _failure_reason := ""


static func step_for_lod(lod: int) -> float:
	if lod < 0 or lod > 1:
		return -1.0
	return LOD0_STEP * float(1 << lod)


static func world_position_for_lattice(lattice_index: Vector3i, lod: int) -> Vector3:
	var step := step_for_lod(lod)
	if step < 0.0:
		return Vector3(NAN, NAN, NAN)
	return Vector3(lattice_index) * step


static func lattice_floor(world_position: Vector3, lod: int) -> Vector3i:
	var step := step_for_lod(lod)
	if step < 0.0 or not world_position.is_finite():
		return Vector3i.ZERO
	return Vector3i(floori(world_position.x / step), floori(world_position.y / step), floori(world_position.z / step))


static func is_lod1_aligned_origin(min_lod0_lattice: Vector3i) -> bool:
	return min_lod0_lattice.x % LOD1_IN_LOD0_STEPS == 0 \
		and min_lod0_lattice.y % LOD1_IN_LOD0_STEPS == 0 \
		and min_lod0_lattice.z % LOD1_IN_LOD0_STEPS == 0


static func transition_faces_for_chunk_cell(cell: Vector3i, extent: Vector3i) -> Array[int]:
	var faces: Array[int] = []
	if cell.x == 0:
		faces.append(FACE_X_NEG)
	if cell.x == extent.x - 1:
		faces.append(FACE_X_POS)
	if cell.z == 0:
		faces.append(FACE_Z_NEG)
	if cell.z == extent.z - 1:
		faces.append(FACE_Z_POS)
	return faces


static func sample_canonical(world_seed: int, world_position: Vector3, brush_snapshot: Dictionary = {}) -> float:
	if not _snapshot_compatible(world_seed, brush_snapshot):
		return NAN
	return _sample_canonical_validated(world_seed, world_position, brush_snapshot)


## Builder entrypoints validate the complete immutable snapshot once before
## geometry starts, so per-vertex and normal probes avoid rescanning the ledger.
static func _sample_canonical_validated(world_seed: int, world_position: Vector3, brush_snapshot: Dictionary) -> float:
	if not world_position.is_finite():
		return NAN
	var mapped: Dictionary = SPATIAL.world_to_region_local(world_position)
	if not mapped.get("valid", false):
		return NAN
	if not brush_snapshot.is_empty():
		return BRUSH.sample_density_snapshot(world_seed, mapped["region_key"], mapped["local_position"], false, brush_snapshot)
	return FIELD.sample_density(world_seed, mapped["region_key"], mapped["local_position"], false)


## selected_fine_faces contains one to three cell face ids in either direction,
## with no opposing pair. Each selected face is split into 2x2 LOD0 quads. Its
## opposite face remains a single LOD1 quad. Boundary polygons on the other sides include shared edge
## midpoints, so the tetrahedral fan is conforming around face/edge/corner
## junctions. A face-center fan on lateral exterior faces is allowed to remain
## open at the finite fixture boundary.
static func build_transition_cell(
	world_seed: int,
	min_lod0_lattice: Vector3i,
	selected_fine_faces: Array[int],
	brush_snapshot: Dictionary = {},
	density_override: Callable = Callable()
) -> Dictionary:
	if not is_lod1_aligned_origin(min_lod0_lattice):
		return {"valid": false, "reason": "misaligned_lod1_cell_origin"}
	var snapshot_failure := _snapshot_rejection_reason(world_seed, brush_snapshot)
	if not snapshot_failure.is_empty():
		return {"valid": false, "reason": snapshot_failure}
	var selected: Array[int] = []
	for face in selected_fine_faces:
		if face < FACE_X_NEG or face > FACE_Z_POS or selected.has(face):
			return {"valid": false, "reason": "unsupported_or_duplicate_transition_face"}
		if selected.has(face ^ 1):
			return {"valid": false, "reason": "opposing_fine_faces_not_supported_in_one_cell"}
		selected.append(face)
	if selected.is_empty() or selected.size() > 3:
		return {"valid": false, "reason": "transition_requires_one_to_three_nonopposing_fine_faces"}
	var builder := Lod01TransitionFixture.new()
	builder._center = Vector3(min_lod0_lattice) * LOD0_STEP
	builder._center += Vector3.ONE * (LOD1_STEP * 0.5)
	builder._sampler = density_override
	builder._world_seed = world_seed
	builder._brush_snapshot = brush_snapshot
	var geometry_started := Time.get_ticks_usec()
	var boundary_triangles := _boundary_triangles(min_lod0_lattice, selected)
	var geometry_usec := Time.get_ticks_usec() - geometry_started
	var triangulation_started := Time.get_ticks_usec()
	var center_id := builder._add_sample_point(builder._center, world_seed, brush_snapshot)
	if center_id < 0:
		return builder._failure_result()
	for triangle in boundary_triangles:
		var a: int = builder._add_sample_point(triangle[0], world_seed, brush_snapshot)
		if a < 0:
			return builder._failure_result()
		var b: int = builder._add_sample_point(triangle[1], world_seed, brush_snapshot)
		if b < 0:
			return builder._failure_result()
		var c: int = builder._add_sample_point(triangle[2], world_seed, brush_snapshot)
		if c < 0:
			return builder._failure_result()
		builder._polygonize_tetra4(center_id, a, b, c)
		if not builder._failure_reason.is_empty():
			return builder._failure_result()
	var polygonization_usec := Time.get_ticks_usec() - triangulation_started
	return builder._make_result(world_seed, min_lod0_lattice, selected, _opposite_faces(selected), geometry_usec, polygonization_usec, "transition")


## Production chunk assembly shares the per-cell sample cache across the chunk,
## avoiding 120 independent builder allocations for the current 4x3x10 LOD1 grid.
static func build_lod1_chunk(
	world_seed: int,
	min_lod0_lattice: Vector3i,
	cell_extent: Vector3i,
	brush_snapshot: Dictionary = {},
	density_override: Callable = Callable()
) -> Dictionary:
	if not is_lod1_aligned_origin(min_lod0_lattice):
		return {"valid": false, "reason": "misaligned_lod1_chunk_origin"}
	if cell_extent.x <= 0 or cell_extent.y <= 0 or cell_extent.z <= 0:
		return {"valid": false, "reason": "invalid_lod1_chunk_extent"}
	var snapshot_failure := _snapshot_rejection_reason(world_seed, brush_snapshot)
	if not snapshot_failure.is_empty():
		return {"valid": false, "reason": snapshot_failure}
	var builder := Lod01TransitionFixture.new()
	builder._sampler = density_override
	builder._world_seed = world_seed
	builder._brush_snapshot = brush_snapshot
	var min_world := Vector3(min_lod0_lattice) * LOD0_STEP
	var geometry_usec := 0
	var transition_count := 0
	# Reuse one typed 8-ID buffer for all uniform cells in this chunk.
	var ids := PackedInt32Array()
	ids.resize(8)
	var polygonization_started_usec := Time.get_ticks_usec()
	for y in range(cell_extent.y):
		for z in range(cell_extent.z):
			for x in range(cell_extent.x):
				var cell := Vector3i(x, y, z)
				var cell_lattice := min_lod0_lattice + cell * LOD1_IN_LOD0_STEPS
				var selected := transition_faces_for_chunk_cell(cell, cell_extent)
				if selected.is_empty():
					var origin := min_world + Vector3(cell) * LOD1_STEP
					for corner_index in range(CUBE_CORNERS.size()):
						var corner: Vector3i = CUBE_CORNERS[corner_index]
						var sample_id: int = builder._add_sample_point(origin + Vector3(corner) * LOD1_STEP, world_seed, brush_snapshot)
						if sample_id < 0:
							return builder._failure_result()
						ids[corner_index] = sample_id
					for tetra in CUBE_TETRAHEDRA:
						builder._polygonize_tetra4(ids[tetra[0]], ids[tetra[1]], ids[tetra[2]], ids[tetra[3]])
						if not builder._failure_reason.is_empty():
							return builder._failure_result()
					continue
				transition_count += 1
				var geometry_started_usec := Time.get_ticks_usec()
				var boundary_triangles := _boundary_triangles(cell_lattice, selected)
				geometry_usec += Time.get_ticks_usec() - geometry_started_usec
				var center := min_world + Vector3(cell) * LOD1_STEP + Vector3.ONE * (LOD1_STEP * 0.5)
				var center_id: int = builder._add_sample_point(center, world_seed, brush_snapshot)
				if center_id < 0:
					return builder._failure_result()
				for triangle in boundary_triangles:
					var a: int = builder._add_sample_point(triangle[0], world_seed, brush_snapshot)
					if a < 0:
						return builder._failure_result()
					var b: int = builder._add_sample_point(triangle[1], world_seed, brush_snapshot)
					if b < 0:
						return builder._failure_result()
					var c: int = builder._add_sample_point(triangle[2], world_seed, brush_snapshot)
					if c < 0:
						return builder._failure_result()
					builder._polygonize_tetra4(center_id, a, b, c)
					if not builder._failure_reason.is_empty():
						return builder._failure_result()
	var polygonization_usec := Time.get_ticks_usec() - polygonization_started_usec
	var result := builder._make_result(
		world_seed, min_lod0_lattice, [], [], geometry_usec, polygonization_usec, "lod1_chunk"
	)
	result["transition_cell_count"] = transition_count
	return result


static func build_uniform_reference_cell(
	world_seed: int,
	min_lod0_lattice: Vector3i,
	lod: int,
	brush_snapshot: Dictionary = {},
	density_override: Callable = Callable()
) -> Dictionary:
	if lod < 0 or lod > 1:
		return {"valid": false, "reason": "unsupported_lod"}
	if lod == 1 and not is_lod1_aligned_origin(min_lod0_lattice):
		return {"valid": false, "reason": "misaligned_lod1_cell_origin"}
	var snapshot_failure := _snapshot_rejection_reason(world_seed, brush_snapshot)
	if not snapshot_failure.is_empty():
		return {"valid": false, "reason": snapshot_failure}
	var builder := Lod01TransitionFixture.new()
	builder._world_seed = world_seed
	builder._brush_snapshot = brush_snapshot
	builder._sampler = density_override
	var step := step_for_lod(lod)
	var subcells := 2 if lod == 0 else 1
	var origin := Vector3(min_lod0_lattice) * LOD0_STEP
	var geometry_usec := 0
	var ids := PackedInt32Array()
	ids.resize(8)
	var triangulation_started := Time.get_ticks_usec()
	for y in range(subcells):
		for z in range(subcells):
			for x in range(subcells):
				for corner_index in range(CUBE_CORNERS.size()):
					var corner: Vector3i = CUBE_CORNERS[corner_index]
					var point := origin + Vector3(x, y, z) * step + Vector3(corner) * step
					var sample_id := builder._add_sample_point(point, world_seed, brush_snapshot)
					if sample_id < 0:
						return builder._failure_result()
					ids[corner_index] = sample_id
				for tetra in CUBE_TETRAHEDRA:
					builder._polygonize_tetra4(ids[tetra[0]], ids[tetra[1]], ids[tetra[2]], ids[tetra[3]])
					if not builder._failure_reason.is_empty():
						return builder._failure_result()
	var polygonization_usec := Time.get_ticks_usec() - triangulation_started
	return builder._make_result(world_seed, min_lod0_lattice, [], [], geometry_usec, polygonization_usec, "lod%d_reference" % lod)


func _make_result(
	world_seed: int,
	min_lod0_lattice: Vector3i,
	selected: Array[int],
	coarse_faces: Array[int],
	geometry_usec: int,
	polygonization_usec: int,
	kind: String
) -> Dictionary:
	if not _failure_reason.is_empty():
		return _failure_result()
	if _positions.size() != _normals.size() or not _packed_vectors_are_finite(_positions) or not _packed_vectors_are_finite(_normals):
		return {"valid": false, "reason": "non_finite_mesh_output"}
	var timing_values := [geometry_usec, _sampling_usec, maxi(0, polygonization_usec - _sampling_usec - _normal_usec), _normal_usec, 0]
	for timing in timing_values:
		if typeof(timing) != TYPE_INT or int(timing) < 0:
			return {"valid": false, "reason": "invalid_fixture_timing"}
	return {
		"valid": true,
		"vertices": _positions,
		"normals": _normals,
		"triangle_count": _positions.size() / 3,
		"sample_count": _sample_points.size(),
		"timings_usec": {
			"transition_geometry": geometry_usec,
			"sdf_ledger_sampling": _sampling_usec,
			"lod_mesh_triangulation": maxi(0, polygonization_usec - _sampling_usec - _normal_usec),
			"normal_computation": _normal_usec,
			"array_mesh_publication": 0,
		},
		"cpu_array_bytes": _positions.size() * 24 + _sample_points.size() * 32,
		"world_seed": world_seed,
		"generator_version": FIELD.GENERATOR_VERSION,
		"ledger_revision": int(_brush_snapshot.get("revision", 0)),
		"min_lod0_lattice": min_lod0_lattice,
		"selected_fine_faces": selected.duplicate(),
		"coarse_faces": coarse_faces.duplicate(),
		"fixture_kind": kind,
		"transition_method": "conforming_boundary_triangulation_with_center_fan_tetrahedra" if kind == "transition" else "reference_marching_tetrahedra",
	}


static func interface_triangles(
	min_lod0_lattice: Vector3i,
	face: int,
	resolution: int
) -> Array[Array]:
	## Returns globally positioned triangles on one face, in the exact boundary
	## triangulation used by the transition cell (resolution 2 fine or 1 coarse).
	## Coarse requests on an odd LOD0 lattice origin fail closed with an empty array.
	var result: Array[Array] = []
	if face < 0 or face > 5 or resolution not in [1, 2]:
		return result
	if resolution == 1 and not is_lod1_aligned_origin(min_lod0_lattice):
		return result
	var axis: int = FACE_AXES[face]
	var base := Vector3(min_lod0_lattice) * LOD0_STEP
	var low := face % 2 == 0
	var fixed := 0.0 if low else LOD1_STEP
	var u_axis := (axis + 1) % 3
	var v_axis := (axis + 2) % 3
	if resolution == 2:
		for v in range(2):
			for u in range(2):
				var p00 := _face_point(base, axis, fixed, u_axis, v_axis, float(u) * 0.5, float(v) * 0.5)
				var p10 := _face_point(base, axis, fixed, u_axis, v_axis, float(u + 1) * 0.5, float(v) * 0.5)
				var p11 := _face_point(base, axis, fixed, u_axis, v_axis, float(u + 1) * 0.5, float(v + 1) * 0.5)
				var p01 := _face_point(base, axis, fixed, u_axis, v_axis, float(u) * 0.5, float(v + 1) * 0.5)
				result.append([p00, p10, p11])
				result.append([p00, p11, p01])
	else:
		var p00 := _face_point(base, axis, fixed, u_axis, v_axis, 0.0, 0.0)
		var p10 := _face_point(base, axis, fixed, u_axis, v_axis, 1.0, 0.0)
		var p11 := _face_point(base, axis, fixed, u_axis, v_axis, 1.0, 1.0)
		var p01 := _face_point(base, axis, fixed, u_axis, v_axis, 0.0, 1.0)
		result.append([p00, p10, p11])
		result.append([p00, p11, p01])
	return result


static func _opposite_faces(selected: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for face in selected:
		result.append(face ^ 1)
	return result


static func _boundary_triangles(min_lattice: Vector3i, selected: Array[int]) -> Array[Array]:
	var result: Array[Array] = []
	for face in range(6):
		if selected.has(face):
			result.append_array(interface_triangles(min_lattice, face, 2))
		elif selected.has(face ^ 1):
			result.append_array(interface_triangles(min_lattice, face, 1))
		else:
			result.append_array(_lateral_face_triangles(min_lattice, face, selected))
	return result


static func _lateral_face_triangles(min_lattice: Vector3i, face: int, selected: Array[int]) -> Array[Array]:
	var axis: int = FACE_AXES[face]
	var fixed := 0.0 if FACE_SIGNS[face] < 0 else LOD1_STEP
	var base := Vector3(min_lattice) * LOD0_STEP
	var u_axis := (axis + 1) % 3
	var v_axis := (axis + 2) % 3
	var perimeter: Array[Vector3] = []
	var corners := [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]
	for edge in range(4):
		var a: Array = corners[edge]
		var b: Array = corners[(edge + 1) % 4]
		perimeter.append(_face_point(base, axis, fixed, u_axis, v_axis, a[0], a[1]))
		if _edge_is_split(face, edge, selected):
			perimeter.append(_face_point(base, axis, fixed, u_axis, v_axis, (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5))
	var face_center := _face_point(base, axis, fixed, u_axis, v_axis, 0.5, 0.5)
	var triangles: Array[Array] = []
	for index in range(perimeter.size()):
		triangles.append([face_center, perimeter[index], perimeter[(index + 1) % perimeter.size()]])
	return triangles


static func _edge_is_split(face: int, edge: int, selected: Array[int]) -> bool:
	var edge_faces: Array[int] = []
	match edge:
		0: edge_faces = [face, _face_id((FACE_AXES[face] + 2) % 3, -1)]
		1: edge_faces = [face, _face_id((FACE_AXES[face] + 1) % 3, 1)]
		2: edge_faces = [face, _face_id((FACE_AXES[face] + 2) % 3, 1)]
		3: edge_faces = [face, _face_id((FACE_AXES[face] + 1) % 3, -1)]
	for selected_face in selected:
		if edge_faces.has(selected_face):
			return true
	return false


static func _face_id(axis: int, sign: int) -> int:
	return axis * 2 + (0 if sign < 0 else 1)


static func _face_point(base: Vector3, axis: int, fixed: float, u_axis: int, v_axis: int, u: float, v: float) -> Vector3:
	var result := base
	result[axis] += fixed
	result[u_axis] += u
	result[v_axis] += v
	return result


func _add_sample_point(point: Vector3, world_seed: int, brush_snapshot: Dictionary) -> int:
	var key := "%d,%d,%d" % [roundi(point.x * 4000.0), roundi(point.y * 4000.0), roundi(point.z * 4000.0)]
	if _sample_ids.has(key):
		return int(_sample_ids[key])
	var density := NAN
	var sample_started := Time.get_ticks_usec()
	if _sampler.is_valid():
		density = float(_sampler.call(point))
	else:
		density = _sample_canonical_validated(world_seed, point, brush_snapshot)
	_sampling_usec += Time.get_ticks_usec() - sample_started
	if not is_finite(density):
		_failure_reason = "non_finite_sample_density"
		return -1
	var sample_id := _sample_points.size()
	_sample_ids[key] = sample_id
	_sample_points.append(point)
	_sample_densities.append(density)
	return sample_id


func _polygonize_tetra4(id0: int, id1: int, id2: int, id3: int) -> void:
	# Vector4i is a value type; unlike the previous Array[int], this creates no
	# per-tetra Variant container.
	var ids := Vector4i(id0, id1, id2, id3)
	var inside_count := 0
	var outside_count := 0
	var inside0 := -1
	var inside1 := -1
	var inside2 := -1
	var outside0 := -1
	var outside1 := -1
	var outside2 := -1
	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	for slot in range(4):
		var sample_id := ids[slot]
		if sample_id < 0 or sample_id >= _sample_points.size():
			_failure_reason = "invalid_sample_id"
			return
		if float(_sample_densities[sample_id]) >= 0.0:
			match inside_count:
				0: inside0 = sample_id
				1: inside1 = sample_id
				2: inside2 = sample_id
			inside_count += 1
			inside_center += _sample_points[sample_id]
		else:
			match outside_count:
				0: outside0 = sample_id
				1: outside1 = sample_id
				2: outside2 = sample_id
			outside_count += 1
			outside_center += _sample_points[sample_id]
	if inside_count == 0 or outside_count == 0:
		return
	inside_center /= float(inside_count)
	outside_center /= float(outside_count)
	var toward_empty := outside_center - inside_center
	if inside_count == 1 or outside_count == 1:
		var pivot := inside0 if inside_count == 1 else outside0
		var other0 := outside0 if inside_count == 1 else inside0
		var other1 := outside1 if inside_count == 1 else inside1
		var other2 := outside2 if inside_count == 1 else inside2
		_emit_triangle(
			_edge_point(pivot, other0),
			_edge_point(pivot, other1),
			_edge_point(pivot, other2),
			toward_empty
		)
	else:
		var a := _edge_point(inside0, outside0)
		var b := _edge_point(inside0, outside1)
		var c := _edge_point(inside1, outside0)
		var d := _edge_point(inside1, outside1)
		_emit_triangle(a, b, d, toward_empty)
		_emit_triangle(a, d, c, toward_empty)


func _edge_point(a_id: int, b_id: int) -> Vector3:
	if a_id < 0 or b_id < 0 or a_id >= _sample_points.size() or b_id >= _sample_points.size():
		_failure_reason = "invalid_sample_id"
		return Vector3(NAN, NAN, NAN)
	var a_point: Vector3 = _sample_points[a_id]
	var b_point: Vector3 = _sample_points[b_id]
	var av := float(_sample_densities[a_id])
	var bv := float(_sample_densities[b_id])
	# Adjacent tetrahedra can ask for the same crossed edge in opposite
	# directions. Canonicalize its endpoints before interpolation so the
	# resulting Vector3 bits do not depend on tetrahedron traversal order.
	if _point_precedes(b_point, a_point):
		var point_swap := a_point
		a_point = b_point
		b_point = point_swap
		var density_swap := av
		av = bv
		bv = density_swap
	var denominator := av - bv
	var t := 0.5 if is_zero_approx(denominator) else clampf(av / denominator, 0.0, 1.0)
	return a_point.lerp(b_point, t)


static func _point_precedes(a: Vector3, b: Vector3) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


func _emit_triangle(a: Vector3, b: Vector3, c: Vector3, toward_empty: Vector3) -> void:
	if not a.is_finite() or not b.is_finite() or not c.is_finite():
		_failure_reason = "non_finite_mesh_output"
		return
	var cross := (b - a).cross(c - a)
	if not cross.is_finite():
		_failure_reason = "non_finite_mesh_output"
		return
	if cross.length_squared() <= 1.0e-12:
		return
	if cross.dot(toward_empty) < 0.0:
		var swap := b
		b = c
		c = swap
		cross = -cross
	var normal_started := Time.get_ticks_usec()
	var normal_a := _normal_for_point(a, cross)
	if not _failure_reason.is_empty():
		return
	var normal_b := _normal_for_point(b, cross)
	if not _failure_reason.is_empty():
		return
	var normal_c := _normal_for_point(c, cross)
	if not _failure_reason.is_empty():
		return
	_normal_usec += Time.get_ticks_usec() - normal_started
	_positions.append(a)
	_positions.append(b)
	_positions.append(c)
	_normals.append(normal_a)
	_normals.append(normal_b)
	_normals.append(normal_c)


func _normal_for_point(point: Vector3, fallback_cross: Vector3) -> Vector3:
	var gradient := Vector3(
		_sample_density(point + Vector3.RIGHT * NORMAL_EPSILON) - _sample_density(point - Vector3.RIGHT * NORMAL_EPSILON),
		_sample_density(point + Vector3.UP * NORMAL_EPSILON) - _sample_density(point - Vector3.UP * NORMAL_EPSILON),
		_sample_density(point + Vector3.BACK * NORMAL_EPSILON) - _sample_density(point - Vector3.BACK * NORMAL_EPSILON)
	)
	if not _failure_reason.is_empty():
		return Vector3.ZERO
	var normal := -gradient.normalized() if gradient.length_squared() > 1.0e-12 else fallback_cross.normalized()
	if not gradient.is_finite() or not normal.is_finite():
		_failure_reason = "non_finite_normal_output"
		return Vector3.ZERO
	return normal


func _sample_density(point: Vector3) -> float:
	var density := NAN
	if _sampler.is_valid():
		density = float(_sampler.call(point))
	else:
		density = _sample_canonical_validated(_world_seed, point, _brush_snapshot)
	if not is_finite(density):
		_failure_reason = "non_finite_sample_density"
		return NAN
	return density


func _failure_result() -> Dictionary:
	return {"valid": false, "reason": _failure_reason if not _failure_reason.is_empty() else "fixture_build_failed"}


static func _packed_vectors_are_finite(values: PackedVector3Array) -> bool:
	for value in values:
		if not value.is_finite():
			return false
	return true


static func result_matches_request(
	result: Dictionary,
	world_seed: int,
	generator_version: int,
	ledger_revision: int,
	min_lod0_lattice: Vector3i,
	selected_fine_faces: Array[int]
) -> bool:
	return bool(result.get("valid", false)) \
		and int(result.get("world_seed", -1)) == world_seed \
		and int(result.get("generator_version", -1)) == generator_version \
		and int(result.get("ledger_revision", -1)) == ledger_revision \
		and result.get("min_lod0_lattice", Vector3i.ZERO) == min_lod0_lattice \
		and result.get("selected_fine_faces", []) == selected_fine_faces


static func canonical_outward_normal(world_seed: int, point: Vector3, brush_snapshot: Dictionary = {}) -> Vector3:
	var dx := sample_canonical(world_seed, point + Vector3.RIGHT * NORMAL_EPSILON, brush_snapshot) - sample_canonical(world_seed, point - Vector3.RIGHT * NORMAL_EPSILON, brush_snapshot)
	var dy := sample_canonical(world_seed, point + Vector3.UP * NORMAL_EPSILON, brush_snapshot) - sample_canonical(world_seed, point - Vector3.UP * NORMAL_EPSILON, brush_snapshot)
	var dz := sample_canonical(world_seed, point + Vector3.BACK * NORMAL_EPSILON, brush_snapshot) - sample_canonical(world_seed, point - Vector3.BACK * NORMAL_EPSILON, brush_snapshot)
	var gradient := Vector3(dx, dy, dz)
	return -gradient.normalized() if gradient.length_squared() > 1.0e-12 else Vector3.ZERO


static func _snapshot_compatible(world_seed: int, snapshot: Dictionary) -> bool:
	return _snapshot_rejection_reason(world_seed, snapshot).is_empty()


static func _snapshot_rejection_reason(world_seed: int, snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return ""
	if not snapshot.has("world_seed") or not snapshot.has("generator_version") or not snapshot.has("revision"):
		return "malformed_snapshot_metadata"
	if typeof(snapshot["world_seed"]) != TYPE_INT or typeof(snapshot["generator_version"]) != TYPE_INT or typeof(snapshot["revision"]) != TYPE_INT:
		return "malformed_snapshot_metadata"
	if int(snapshot["world_seed"]) != world_seed:
		return "snapshot_world_seed_mismatch"
	if int(snapshot["generator_version"]) != FIELD.GENERATOR_VERSION:
		return "unsupported_snapshot_generator_version"
	if int(snapshot["revision"]) < 0:
		return "invalid_snapshot_revision"
	if not snapshot.has("centers") or not snapshot.has("radii") or not snapshot.has("modes"):
		return "malformed_snapshot_arrays"
	if typeof(snapshot["centers"]) != TYPE_PACKED_VECTOR3_ARRAY \
			or typeof(snapshot["radii"]) != TYPE_PACKED_FLOAT64_ARRAY \
			or typeof(snapshot["modes"]) != TYPE_PACKED_BYTE_ARRAY:
		return "malformed_snapshot_arrays"
	var centers: PackedVector3Array = snapshot["centers"]
	var radii: PackedFloat64Array = snapshot["radii"]
	var modes: PackedByteArray = snapshot["modes"]
	if centers.size() > BRUSH.MAX_OPERATION_COUNT or centers.size() != radii.size() or centers.size() != modes.size():
		return "invalid_snapshot_command_count"
	if int(snapshot["revision"]) < centers.size():
		return "invalid_snapshot_revision"
	for index in range(centers.size()):
		var center: Vector3 = centers[index]
		var radius: float = radii[index]
		var mode: int = int(modes[index])
		if not center.is_finite() or maxf(absf(center.x), maxf(absf(center.y), absf(center.z))) > BRUSH.MAX_ABS_WORLD_COORDINATE:
			return "invalid_snapshot_center"
		if not is_finite(radius) or radius < BRUSH.MIN_RADIUS or radius > BRUSH.MAX_RADIUS:
			return "invalid_snapshot_radius"
		if mode != BRUSH.Mode.CARVE and mode != BRUSH.Mode.FILL:
			return "unsupported_snapshot_mode"
	return ""
