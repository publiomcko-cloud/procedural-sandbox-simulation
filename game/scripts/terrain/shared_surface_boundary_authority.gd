class_name SharedSurfaceBoundaryAuthority
extends RefCounted

## Experimental production candidate for region-boundary ownership.
## A pair of adjacent edge chunks is polygonized from one canonical world-space
## SDF sample volume and one global lattice-edge root cache, then partitioned
## back into the two existing region/chunk publication units.
##
## The service owns no scene nodes and mutates no ledger state.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")

const EPS := 0.000001
const ROOT_QUANT := 1000000.0

const CORNERS := [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1),
]
const TETS := [
	[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
	[0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6],
]


static func make_x_pair_snapshot(
	ledger: RefCounted,
	left_region_key: Vector2i,
	z_chunk: int
) -> Dictionary:
	if ledger == null or z_chunk < 0 or z_chunk >= Grid.CHUNK_COUNT_Z:
		return {"valid": false, "reason": "invalid_pair_snapshot_request"}
	var left_coordinate := Vector2i(Grid.CHUNK_COUNT_X - 1, z_chunk)
	var right_region_key := left_region_key + Vector2i.RIGHT
	var right_coordinate := Vector2i(0, z_chunk)
	var left_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(left_region_key, left_coordinate)
	var right_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(right_region_key, right_coordinate)
	if not bool(left_snapshot.get("valid", false)):
		return {"valid": false, "reason": "left_snapshot_failed", "detail": left_snapshot}
	if not bool(right_snapshot.get("valid", false)):
		return {"valid": false, "reason": "right_snapshot_failed", "detail": right_snapshot}

	var by_sequence: Dictionary = {}
	var materialized_by_id: Dictionary = {}
	for snapshot_value in [left_snapshot, right_snapshot]:
		var snapshot: Dictionary = snapshot_value
		var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
		var radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
		var modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
		var sequences_value: Variant = snapshot.get("sequences", PackedInt32Array())
		if typeof(sequences_value) != TYPE_PACKED_INT32_ARRAY 			and typeof(sequences_value) != TYPE_PACKED_INT64_ARRAY:
			return {"valid": false, "reason": "pair_snapshot_sequence_type_invalid"}
		if centers.size() != radii.size() or centers.size() != modes.size() 			or centers.size() != sequences_value.size():
			return {"valid": false, "reason": "pair_snapshot_attribute_mismatch"}
		for index in range(centers.size()):
			var sequence := int(sequences_value[index])
			var row := {
				"center": centers[index],
				"radius": float(radii[index]),
				"mode": int(modes[index]),
			}
			if by_sequence.has(sequence):
				var existing: Dictionary = by_sequence[sequence]
				if existing["center"] != row["center"] 					or float(existing["radius"]) != float(row["radius"]) 					or int(existing["mode"]) != int(row["mode"]):
					return {
						"valid": false,
						"reason": "pair_snapshot_sequence_conflict",
						"sequence": sequence,
					}
			else:
				by_sequence[sequence] = row
		var tiles_value: Variant = snapshot.get("materialized_tiles", [])
		if typeof(tiles_value) == TYPE_ARRAY:
			for tile_value in tiles_value:
				if typeof(tile_value) != TYPE_DICTIONARY:
					continue
				var tile: Dictionary = tile_value
				var tile_id := String(tile.get("tile_id", ""))
				if tile_id.is_empty():
					continue
				if not materialized_by_id.has(tile_id):
					materialized_by_id[tile_id] = tile

	var ordered_sequences: Array[int] = []
	for sequence_value in by_sequence.keys():
		ordered_sequences.append(int(sequence_value))
	ordered_sequences.sort()
	var centers := PackedVector3Array()
	var radii := PackedFloat64Array()
	var modes := PackedByteArray()
	var sequences := PackedInt64Array()
	for sequence in ordered_sequences:
		var row: Dictionary = by_sequence[sequence]
		centers.append(row["center"])
		radii.append(float(row["radius"]))
		modes.append(int(row["mode"]))
		sequences.append(sequence)
	var tile_ids: Array[String] = []
	for tile_id_value in materialized_by_id.keys():
		tile_ids.append(String(tile_id_value))
	tile_ids.sort()
	var materialized_tiles: Array[Dictionary] = []
	for tile_id in tile_ids:
		materialized_tiles.append(materialized_by_id[tile_id])
	return {
		"valid": true,
		"revision": int(ledger.revision),
		"world_seed": int(ledger.world_seed),
		"generator_version": int(ledger.generator_version),
		"centers": centers,
		"radii": radii,
		"modes": modes,
		"sequences": sequences,
		"materialized_tiles": materialized_tiles,
		"candidate_operation_count": centers.size(),
		"ledger_operation_count": int(ledger.get_edit_count()),
	}


static func build_x_region_boundary_pair(
	world_seed: int,
	left_region_key: Vector2i,
	z_chunk: int,
	brush_snapshot: Dictionary
) -> Dictionary:
	if z_chunk < 0 or z_chunk >= Grid.CHUNK_COUNT_Z:
		return {"valid": false, "reason": "invalid_z_chunk"}
	var right_region_key := left_region_key + Vector2i.RIGHT
	var left_coordinate := Vector2i(Grid.CHUNK_COUNT_X - 1, z_chunk)
	var right_coordinate := Vector2i(0, z_chunk)
	var left_origin := Spatial.region_origin_world(left_region_key) + Grid.origin_for(left_coordinate)
	var right_origin := Spatial.region_origin_world(right_region_key) + Grid.origin_for(right_coordinate)
	var seam_x := right_origin.x
	var cells := Vector3i(Grid.CELLS_PER_CHUNK_X * 2, Grid.CELL_COUNT_Y, Grid.CELLS_PER_CHUNK_Z)
	var roi_min := Vector3(left_origin.x, Grid.MIN_BOUND.y, left_origin.z)
	var built := build_x_shared_volume(world_seed, brush_snapshot, roi_min, cells, Grid.SAMPLE_STEP, seam_x)
	if not built.get("valid", false):
		return built

	var left_positions := PackedVector3Array()
	var left_normals := PackedVector3Array()
	var right_positions := PackedVector3Array()
	var right_normals := PackedVector3Array()
	for triangle_value in built.get("triangles", []):
		var triangle: Dictionary = triangle_value
		var points: Array = triangle["points"]
		var normal: Vector3 = triangle["normal"]
		var side := String(triangle["side"])
		for point_value in points:
			var point: Vector3 = point_value
			if side == "left":
				left_positions.append(point - left_origin)
				left_normals.append(normal)
			else:
				right_positions.append(point - right_origin)
				right_normals.append(normal)

	var common := {
		"ledger_revision": int(brush_snapshot.get("revision", 0)),
		"world_seed": world_seed,
		"generator_version": Field.GENERATOR_VERSION,
		"lod_level": 0,
		"boundary_authority": "shared_surface_x_pair_v1",
		"seam_x": seam_x,
		"shared_mesh_signature": String(built.get("mesh_signature", "")),
	}
	var left_cpu := common.duplicate(true)
	left_cpu.merge({
		"valid": true,
		"region_key": left_region_key,
		"coordinate": left_coordinate,
		"positions": left_positions,
		"normals": left_normals,
		"vertex_count": left_positions.size(),
		"triangle_count": left_positions.size() / 3,
		"sample_count": int(built.get("sample_count", 0)),
	}, true)
	var right_cpu := common.duplicate(true)
	right_cpu.merge({
		"valid": true,
		"region_key": right_region_key,
		"coordinate": right_coordinate,
		"positions": right_positions,
		"normals": right_normals,
		"vertex_count": right_positions.size(),
		"triangle_count": right_positions.size() / 3,
		"sample_count": int(built.get("sample_count", 0)),
	}, true)
	return {
		"valid": true,
		"left": left_cpu,
		"right": right_cpu,
		"diagnostics": built.get("diagnostics", {}),
		"mesh_signature": built.get("mesh_signature", ""),
		"seam_x": seam_x,
		"z_chunk": z_chunk,
	}


static func build_x_shared_volume(
	world_seed: int,
	brush_snapshot: Dictionary,
	roi_min: Vector3,
	cells: Vector3i,
	step: float,
	seam_x: float
) -> Dictionary:
	if cells.x <= 0 or cells.y <= 0 or cells.z <= 0 or not is_finite(step) or step <= 0.0:
		return {"valid": false, "reason": "invalid_volume_shape"}
	var roi_max := roi_min + Vector3(cells) * step
	if seam_x <= roi_min.x + EPS or seam_x >= roi_max.x - EPS:
		return {"valid": false, "reason": "seam_outside_volume"}
	var dims := cells + Vector3i.ONE
	var values := PackedFloat32Array()
	values.resize(dims.x * dims.y * dims.z)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var p := roi_min + Vector3(x, y, z) * step
				var d := _sample_density(world_seed, p, brush_snapshot)
				if not is_finite(d):
					return {"valid": false, "reason": "non_finite_sample", "sample": [x, y, z]}
				values[_index(x, y, z, dims)] = d

	var root_cache: Dictionary = {}
	var root_position_keys: Dictionary = {}
	var triangles: Array[Dictionary] = []
	var dropped_degenerate_candidates := 0
	for y in range(cells.y):
		for z in range(cells.z):
			for x in range(cells.x):
				var cell := Vector3i(x, y, z)
				var nodes: Array[Vector3i] = []
				var points: Array[Vector3] = []
				var density: Array[float] = []
				for corner_value in CORNERS:
					var corner: Vector3i = corner_value
					var node := cell + corner
					nodes.append(node)
					points.append(roi_min + Vector3(node) * step)
					density.append(values[_index(node.x, node.y, node.z, dims)])
				for tet in TETS:
					var emitted := _polygonize_tet(
						tet, nodes, points, density, roi_min, step, seam_x,
						root_cache, root_position_keys
					)
					dropped_degenerate_candidates += int(emitted.get("dropped_degenerate", 0))
					triangles.append_array(emitted.get("triangles", []))

	var deduplicated := _deduplicate_triangles(triangles)
	var dropped_duplicate_candidates := triangles.size() - deduplicated.size()
	triangles = deduplicated
	var diagnostics := analyze_world_triangles(triangles, seam_x, roi_min, roi_max)
	var signature_rows: Array[String] = []
	for triangle_value in triangles:
		var ids: Array = triangle_value["root_ids"]
		var sorted_ids := [String(ids[0]), String(ids[1]), String(ids[2])]
		sorted_ids.sort()
		signature_rows.append("%s:%s" % [String(triangle_value["side"]), "|".join(sorted_ids)])
	signature_rows.sort()

	var root_identity_consistent := true
	for root_id in root_cache.keys():
		var point: Vector3 = root_cache[root_id]
		if String(root_position_keys.get(root_id, "")) != _point_key(point):
			root_identity_consistent = false
			break
	diagnostics["root_identity_consistent"] = root_identity_consistent
	diagnostics["dropped_degenerate_candidate_count"] = dropped_degenerate_candidates
	diagnostics["dropped_duplicate_candidate_count"] = dropped_duplicate_candidates
	diagnostics["emitted_degenerate_triangle_count"] = 0

	return {
		"valid": true,
		"triangles": triangles,
		"diagnostics": diagnostics,
		"mesh_signature": _fnv1a_64("\n".join(signature_rows)),
		"unique_root_count": root_cache.size(),
		"triangle_count": triangles.size(),
		"sample_count": values.size(),
		"roi_min": roi_min,
		"roi_max": roi_max,
		"step": step,
		"seam_x": seam_x,
	}


static func _deduplicate_triangles(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for triangle in source:
		var ids: Array = triangle.get("root_ids", [])
		if ids.size() != 3:
			continue
		var canonical := [String(ids[0]), String(ids[1]), String(ids[2])]
		canonical.sort()
		var key := "|".join(canonical)
		if seen.has(key):
			continue
		seen[key] = true
		result.append(triangle)
	return result


static func analyze_cpu_pair_plane(
	left_cpu: Dictionary,
	left_world_origin: Vector3,
	right_cpu: Dictionary,
	right_world_origin: Vector3,
	seam_x: float,
	y_min: float,
	y_max: float,
	z_min: float,
	z_max: float
) -> Dictionary:
	var triangles: Array[Dictionary] = []
	_append_cpu_triangles(triangles, left_cpu, left_world_origin, "left")
	_append_cpu_triangles(triangles, right_cpu, right_world_origin, "right")
	return analyze_world_triangles(
		triangles, seam_x,
		Vector3(seam_x - 1.0, y_min, z_min),
		Vector3(seam_x + 1.0, y_max, z_max)
	)


static func analyze_world_triangles(
	triangles: Array,
	seam_x: float,
	roi_min: Vector3,
	roi_max: Vector3
) -> Dictionary:
	var edge_incidence: Dictionary = {}
	var edge_sides: Dictionary = {}
	var edge_points: Dictionary = {}
	var duplicate_triangles := 0
	var triangle_keys: Dictionary = {}
	for triangle_value in triangles:
		var triangle: Dictionary = triangle_value
		var points: Array = triangle["points"]
		if points.size() != 3:
			continue
		var point_keys := [_point_key(points[0]), _point_key(points[1]), _point_key(points[2])]
		var canonical_triangle := point_keys.duplicate()
		canonical_triangle.sort()
		var triangle_key := "|".join(canonical_triangle)
		if triangle_keys.has(triangle_key):
			duplicate_triangles += 1
		triangle_keys[triangle_key] = true
		for pair in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = points[pair[0]]
			var b: Vector3 = points[pair[1]]
			var key := _ordered_pair(_point_key(a), _point_key(b))
			edge_incidence[key] = int(edge_incidence.get(key, 0)) + 1
			if not edge_sides.has(key):
				edge_sides[key] = {}
			var sides: Dictionary = edge_sides[key]
			sides[String(triangle.get("side", "unknown"))] = true
			edge_sides[key] = sides
			edge_points[key] = [a, b]

	var seam_edges: Array[String] = []
	var bad_incidence := 0
	var cross_owner := 0
	var bad_edges: Array[Dictionary] = []
	var non_cross_owned_edges: Array[Dictionary] = []
	for edge_value in edge_incidence.keys():
		var edge_key := String(edge_value)
		var pts: Array = edge_points[edge_key]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[1]
		if absf(a.x - seam_x) > EPS or absf(b.x - seam_x) > EPS:
			continue
		if _on_outer_yz(a, roi_min, roi_max) and _on_outer_yz(b, roi_min, roi_max):
			continue
		seam_edges.append(edge_key)
		var incidence := int(edge_incidence[edge_key])
		var sides: Dictionary = edge_sides[edge_key]
		if incidence != 2:
			bad_incidence += 1
			if bad_edges.size() < 32:
				bad_edges.append({"edge": edge_key, "incidence": incidence, "sides": sides.keys(), "points": [a, b]})
		if sides.has("left") and sides.has("right"):
			cross_owner += 1
		elif non_cross_owned_edges.size() < 32:
			non_cross_owned_edges.append({"edge": edge_key, "incidence": incidence, "sides": sides.keys(), "points": [a, b]})

	return {
		"seam_edge_count": seam_edges.size(),
		"seam_bad_incidence_count": bad_incidence,
		"seam_cross_owner_count": cross_owner,
		"t_junction_count": _count_t_junctions(seam_edges, edge_points),
		"duplicate_triangle_count": duplicate_triangles,
		"bad_edges": bad_edges,
		"non_cross_owned_edges": non_cross_owned_edges,
	}


static func _append_cpu_triangles(
	target: Array[Dictionary],
	cpu: Dictionary,
	world_origin: Vector3,
	side: String
) -> void:
	var positions: PackedVector3Array = cpu.get("positions", PackedVector3Array())
	for i in range(0, positions.size() - 2, 3):
		var a := positions[i] + world_origin
		var b := positions[i + 1] + world_origin
		var c := positions[i + 2] + world_origin
		target.append({
			"points": [a, b, c],
			"side": side,
			"root_ids": [_point_key(a), _point_key(b), _point_key(c)],
			"normal": (b - a).cross(c - a).normalized(),
		})


static func _sample_density(world_seed: int, world: Vector3, snapshot: Dictionary) -> float:
	var mapped: Dictionary = Spatial.world_to_region_local(world)
	if not bool(mapped.get("valid", false)):
		return NAN
	if snapshot.is_empty():
		return Field.sample_density(world_seed, mapped["region_key"], mapped["local_position"], false)
	return Brush.sample_density_snapshot(
		world_seed, mapped["region_key"], mapped["local_position"], false, snapshot
	)


static func _polygonize_tet(
	tet: Array,
	nodes: Array[Vector3i],
	points: Array[Vector3],
	density: Array[float],
	roi_min: Vector3,
	step: float,
	seam_x: float,
	root_cache: Dictionary,
	root_position_keys: Dictionary
) -> Dictionary:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for local_index in tet:
		if density[local_index] >= 0.0:
			inside.append(local_index)
		else:
			outside.append(local_index)
	if inside.is_empty() or outside.is_empty():
		return {"triangles": [], "dropped_degenerate": 0}

	var inside_center := Vector3.ZERO
	var outside_center := Vector3.ZERO
	for i in inside:
		inside_center += points[i]
	for i in outside:
		outside_center += points[i]
	inside_center /= float(inside.size())
	outside_center /= float(outside.size())
	var toward_empty := outside_center - inside_center

	if inside.size() == 1 or inside.size() == 3:
		var singleton: int
		var others: Array[int]
		if inside.size() == 1:
			singleton = inside[0]
			others = outside
		else:
			singleton = outside[0]
			others = inside
		var roots: Array[String] = []
		for other in others:
			roots.append(_root_id_and_cache(
				singleton, other, nodes, points, density, roi_min, step,
				root_cache, root_position_keys
			))
		return _emit_triangle(roots[0], roots[1], roots[2], toward_empty, seam_x, root_cache)

	var r00 := _root_id_and_cache(inside[0], outside[0], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r01 := _root_id_and_cache(inside[0], outside[1], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r10 := _root_id_and_cache(inside[1], outside[0], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	var r11 := _root_id_and_cache(inside[1], outside[1], nodes, points, density, roi_min, step, root_cache, root_position_keys)
	# Match MarchingTetrahedra and Lod01TransitionFixture exactly for 2/2
	# tetrahedra: both use the a-d diagonal. Root interpolation remains globally
	# canonical, but topology must share the production diagonal convention.
	var result: Array[Dictionary] = []
	var first := _emit_triangle(r00, r01, r11, toward_empty, seam_x, root_cache)
	var second := _emit_triangle(r00, r11, r10, toward_empty, seam_x, root_cache)
	result.append_array(first["triangles"])
	result.append_array(second["triangles"])
	var dropped := int(first["dropped_degenerate"]) + int(second["dropped_degenerate"])
	return {"triangles": result, "dropped_degenerate": dropped}


static func _root_id_and_cache(
	a: int,
	b: int,
	nodes: Array[Vector3i],
	points: Array[Vector3],
	density: Array[float],
	roi_min: Vector3,
	step: float,
	root_cache: Dictionary,
	root_position_keys: Dictionary
) -> String:
	var wa := roi_min + Vector3(nodes[a]) * step
	var wb := roi_min + Vector3(nodes[b]) * step
	var node_a := _lattice_key(wa, step)
	var node_b := _lattice_key(wb, step)
	var key := _ordered_pair(node_a, node_b)
	if root_cache.has(key):
		return key
	var point_a: Vector3 = points[a]
	var point_b: Vector3 = points[b]
	var da := density[a]
	var db := density[b]
	# Match Lod01TransitionFixture bit-for-bit: shared crossed edges may be
	# traversed in opposite directions by different mesh owners, so canonicalize
	# endpoint order before the floating-point interpolation.
	if _point_precedes(point_b, point_a):
		var point_swap := point_a
		point_a = point_b
		point_b = point_swap
		var density_swap := da
		da = db
		db = density_swap
	var denominator := da - db
	var t := 0.5 if is_zero_approx(denominator) else clampf(da / denominator, 0.0, 1.0)
	var point := point_a.lerp(point_b, t)
	root_cache[key] = point
	root_position_keys[key] = _point_key(point)
	return key


static func _emit_triangle(
	a: String,
	b: String,
	c: String,
	toward_empty: Vector3,
	seam_x: float,
	roots: Dictionary
) -> Dictionary:
	if a == b or b == c or c == a:
		return {"triangles": [], "dropped_degenerate": 1}
	var pa: Vector3 = roots[a]
	var pb: Vector3 = roots[b]
	var pc: Vector3 = roots[c]
	var normal := (pb - pa).cross(pc - pa)
	if normal.length_squared() <= 1.0e-14:
		return {"triangles": [], "dropped_degenerate": 1}
	if normal.dot(toward_empty) < 0.0:
		var swap := pb
		pb = pc
		pc = swap
		var swap_id := b
		b = c
		c = swap_id
		normal = -normal
	normal = normal.normalized()
	var center_x := (pa.x + pb.x + pc.x) / 3.0
	var side := "left" if center_x < seam_x else "right"
	return {
		"triangles": [{
			"root_ids": [a, b, c],
			"points": [pa, pb, pc],
			"normal": normal,
			"side": side,
		}],
		"dropped_degenerate": 0,
	}


static func _count_t_junctions(seam_edges: Array[String], edge_points: Dictionary) -> int:
	var unique_points: Dictionary = {}
	for edge_key in seam_edges:
		var pts: Array = edge_points[edge_key]
		unique_points[_point_key(pts[0])] = pts[0]
		unique_points[_point_key(pts[1])] = pts[1]
	var count := 0
	for edge_key in seam_edges:
		var pts: Array = edge_points[edge_key]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[1]
		var ab := b - a
		var len2 := ab.length_squared()
		if len2 <= 1.0e-14:
			continue
		for point_value in unique_points.values():
			var p: Vector3 = point_value
			if p.distance_squared_to(a) <= 1.0e-12 or p.distance_squared_to(b) <= 1.0e-12:
				continue
			var t := (p - a).dot(ab) / len2
			if t <= EPS or t >= 1.0 - EPS:
				continue
			if (a + ab * t).distance_squared_to(p) <= 1.0e-12:
				count += 1
	return count


static func _on_outer_yz(p: Vector3, roi_min: Vector3, roi_max: Vector3) -> bool:
	return absf(p.y - roi_min.y) <= EPS or absf(p.y - roi_max.y) <= EPS 		or absf(p.z - roi_min.z) <= EPS or absf(p.z - roi_max.z) <= EPS


static func _index(x: int, y: int, z: int, dims: Vector3i) -> int:
	return (y * dims.z + z) * dims.x + x


static func _point_precedes(a: Vector3, b: Vector3) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


static func _lattice_key(p: Vector3, step: float) -> String:
	return "%d,%d,%d@%d" % [
		roundi(p.x / step), roundi(p.y / step), roundi(p.z / step), roundi(step * ROOT_QUANT)
	]


static func _ordered_pair(a: String, b: String) -> String:
	return a + ">" + b if a < b else b + ">" + a


static func _point_key(p: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(p.x * ROOT_QUANT), roundi(p.y * ROOT_QUANT), roundi(p.z * ROOT_QUANT)
	]


static func _fnv1a_64(text_value: String) -> String:
	var hash: int = 1469598103934665603
	for byte in text_value.to_utf8_buffer():
		hash = hash ^ int(byte)
		hash = hash * 1099511628211
	return "%016x" % hash
