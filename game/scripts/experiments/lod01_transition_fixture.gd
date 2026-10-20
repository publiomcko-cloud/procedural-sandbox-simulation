class_name Lod01TransitionFixture
extends RefCounted

## Experimental CPU-only LOD 0/1 transition cell. It does not participate in
## the playable terrain, streaming scheduler, or canonical edit ledger.
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
var _samples: Dictionary = {}
var _sample_list: Array[Dictionary] = []
var _sampler := Callable()
var _world_seed := 424242
var _brush_snapshot: Dictionary = {}
var _sampling_usec := 0
var _normal_usec := 0


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


static func sample_canonical(world_seed: int, world_position: Vector3, brush_snapshot: Dictionary = {}) -> float:
	if not _snapshot_compatible(world_seed, brush_snapshot):
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
	if not _snapshot_compatible(world_seed, brush_snapshot):
		return {"valid": false, "reason": "incompatible_or_unbounded_ledger_snapshot"}
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
	for triangle in boundary_triangles:
		var a: int = builder._add_sample_point(triangle[0], world_seed, brush_snapshot)
		var b: int = builder._add_sample_point(triangle[1], world_seed, brush_snapshot)
		var c: int = builder._add_sample_point(triangle[2], world_seed, brush_snapshot)
		builder._polygonize_tetra([center_id, a, b, c])
	var polygonization_usec := Time.get_ticks_usec() - triangulation_started
	return builder._make_result(world_seed, min_lod0_lattice, selected, _opposite_faces(selected), geometry_usec, polygonization_usec, "transition")


static func build_uniform_reference_cell(
	world_seed: int,
	min_lod0_lattice: Vector3i,
	lod: int,
	brush_snapshot: Dictionary = {},
	density_override: Callable = Callable()
) -> Dictionary:
	if lod < 0 or lod > 1:
		return {"valid": false, "reason": "unsupported_lod"}
	if not _snapshot_compatible(world_seed, brush_snapshot):
		return {"valid": false, "reason": "incompatible_or_unbounded_ledger_snapshot"}
	var builder := Lod01TransitionFixture.new()
	builder._world_seed = world_seed
	builder._brush_snapshot = brush_snapshot
	builder._sampler = density_override
	var step := step_for_lod(lod)
	var subcells := 2 if lod == 0 else 1
	var origin := Vector3(min_lod0_lattice) * LOD0_STEP
	var geometry_usec := 0
	var triangulation_started := Time.get_ticks_usec()
	for y in range(subcells):
		for z in range(subcells):
			for x in range(subcells):
				var ids: Array[int] = []
				for corner in CUBE_CORNERS:
					var point := origin + Vector3(x, y, z) * step + Vector3(corner) * step
					ids.append(builder._add_sample_point(point, world_seed, brush_snapshot))
				for tetra in CUBE_TETRAHEDRA:
					builder._polygonize_tetra([ids[tetra[0]], ids[tetra[1]], ids[tetra[2]], ids[tetra[3]]])
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
	return {
		"valid": true,
		"vertices": _positions,
		"normals": _normals,
		"triangle_count": _positions.size() / 3,
		"sample_count": _samples.size(),
		"timings_usec": {
			"transition_geometry": geometry_usec,
			"sdf_ledger_sampling": _sampling_usec,
			"lod_mesh_triangulation": maxi(0, polygonization_usec - _sampling_usec - _normal_usec),
			"normal_computation": _normal_usec,
			"array_mesh_publication": 0,
		},
		"cpu_array_bytes": _positions.size() * 24 + _samples.size() * 32,
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
	var result: Array[Array] = []
	if face < 0 or face > 5 or resolution not in [1, 2]:
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
	if _samples.has(key):
		return int(_samples[key]["id"])
	var density := NAN
	var sample_started := Time.get_ticks_usec()
	if _sampler.is_valid():
		density = float(_sampler.call(point))
	else:
		density = sample_canonical(world_seed, point, brush_snapshot)
	_sampling_usec += Time.get_ticks_usec() - sample_started
	var sample := {"id": _samples.size(), "point": point, "density": density}
	_samples[key] = sample
	_sample_list.append(sample)
	return int(sample["id"])


func _polygonize_tetra(ids: Array[int]) -> void:
	var inside: Array[int] = []
	var outside: Array[int] = []
	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	for id in ids:
		var sample: Dictionary = _sample_by_id(id)
		if float(sample["density"]) >= 0.0:
			inside.append(id)
			inside_center += sample["point"]
		else:
			outside.append(id)
			outside_center += sample["point"]
	if inside.is_empty() or outside.is_empty():
		return
	inside_center /= float(inside.size())
	outside_center /= float(outside.size())
	var toward_empty := outside_center - inside_center
	if inside.size() == 1 or outside.size() == 1:
		var pivot := inside[0] if inside.size() == 1 else outside[0]
		var others := outside if inside.size() == 1 else inside
		_emit_triangle(_edge_point(pivot, others[0]), _edge_point(pivot, others[1]), _edge_point(pivot, others[2]), toward_empty)
	else:
		var a := _edge_point(inside[0], outside[0])
		var b := _edge_point(inside[0], outside[1])
		var c := _edge_point(inside[1], outside[0])
		var d := _edge_point(inside[1], outside[1])
		_emit_triangle(a, b, d, toward_empty)
		_emit_triangle(a, d, c, toward_empty)


func _sample_by_id(id: int) -> Dictionary:
	return _sample_list[id] if id >= 0 and id < _sample_list.size() else {}


func _edge_point(a_id: int, b_id: int) -> Vector3:
	var a: Dictionary = _sample_by_id(a_id)
	var b: Dictionary = _sample_by_id(b_id)
	var av := float(a["density"])
	var bv := float(b["density"])
	var denominator := av - bv
	var t := 0.5 if is_zero_approx(denominator) else clampf(av / denominator, 0.0, 1.0)
	return (a["point"] as Vector3).lerp(b["point"], t)


func _emit_triangle(a: Vector3, b: Vector3, c: Vector3, toward_empty: Vector3) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length_squared() <= 1.0e-12:
		return
	if cross.dot(toward_empty) < 0.0:
		var swap := b
		b = c
		c = swap
		cross = -cross
	_positions.append_array([a, b, c])
	var normal := Vector3.ZERO
	var normal_started := Time.get_ticks_usec()
	for point in [a, b, c]:
		var gradient := Vector3(
			_sample_density(point + Vector3.RIGHT * NORMAL_EPSILON) - _sample_density(point - Vector3.RIGHT * NORMAL_EPSILON),
			_sample_density(point + Vector3.UP * NORMAL_EPSILON) - _sample_density(point - Vector3.UP * NORMAL_EPSILON),
			_sample_density(point + Vector3.BACK * NORMAL_EPSILON) - _sample_density(point - Vector3.BACK * NORMAL_EPSILON)
		)
		normal = -gradient.normalized() if gradient.length_squared() > 1.0e-12 else cross.normalized()
		_normals.append(normal)
	_normal_usec += Time.get_ticks_usec() - normal_started


func _sample_density(point: Vector3) -> float:
	if _sampler.is_valid():
		return float(_sampler.call(point))
	return sample_canonical(_world_seed, point, _brush_snapshot)


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
	if snapshot.is_empty():
		return true
	if not snapshot.has("world_seed") or not snapshot.has("generator_version") or not snapshot.has("revision"):
		return false
	if int(snapshot["world_seed"]) != world_seed or int(snapshot["generator_version"]) != FIELD.GENERATOR_VERSION:
		return false
	if not snapshot.has("centers") or not snapshot.has("radii") or not snapshot.has("modes"):
		return false
	if typeof(snapshot["centers"]) != TYPE_PACKED_VECTOR3_ARRAY \
			or typeof(snapshot["radii"]) != TYPE_PACKED_FLOAT64_ARRAY \
			or typeof(snapshot["modes"]) != TYPE_PACKED_BYTE_ARRAY:
		return false
	var centers: PackedVector3Array = snapshot["centers"]
	var radii: PackedFloat64Array = snapshot["radii"]
	var modes: PackedByteArray = snapshot["modes"]
	return centers.size() <= BRUSH.MAX_EDITS \
		and centers.size() == radii.size() \
		and centers.size() == modes.size()
