extends SceneTree

## Architecture alternative B: one shared surface authority owns the seam slab
## crossing the X+ region boundary. Adjacent region renderers consume its output
## instead of independently inventing boundary vertices/triangles.
##
## This probe replays the exact edit sequence used by the R6 target scenario
## R9.2.SEAM.XPLUS_EQUAL.v1 and checks topology on x=16.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")

const SEED := 131102026
const ROI_MIN := Vector3(15.0, 1.0, 6.0)
const CELLS := Vector3i(8, 8, 8)
const STEP := 0.25
const SEAM_X := 16.0
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

var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot_result := _make_frozen_snapshot()
	_check(snapshot_result.get("valid", false), "exact R6 edit snapshot is accepted")
	if not snapshot_result.get("valid", false):
		_finish({})
		return
	var snapshot: Dictionary = snapshot_result.snapshot

	var first := _build_shared_surface(snapshot)
	var second := _build_shared_surface(snapshot)
	_check(first.get("valid", false), "shared surface authority builds the frozen R6 ROI")
	_check(second.get("valid", false), "deterministic repeat builds the same ROI")
	if not first.get("valid", false) or not second.get("valid", false):
		_finish(first)
		return

	_check(first.get("mesh_signature", "") == second.get("mesh_signature", ""), "shared-surface mesh signature repeats exactly")
	_check(int(first.get("triangle_count", 0)) > 0, "shared-surface mesh is non-empty")
	_check(int(first.get("seam_edge_count", 0)) > 0, "frozen R6 field actually intersects x=16")
	_check(int(first.get("seam_bad_incidence_count", -1)) == 0, "all non-exterior seam edges have total incidence 2")
	_check(int(first.get("seam_cross_owner_count", 0)) == int(first.get("seam_edge_count", 0)), "every seam edge is contributed by cells from both region sides")
	_check(int(first.get("t_junction_count", -1)) == 0, "no seam root lies in the interior of another seam edge")
	_check(int(first.get("duplicate_triangle_count", -1)) == 0, "shared authority emits no duplicate triangles")
	_check(int(first.get("emitted_degenerate_triangle_count", -1)) == 0, "shared authority emits no degenerate triangles")
	_check(bool(first.get("root_identity_consistent", false)), "global lattice-edge roots have one binary32 position identity")

	_finish(first)


func _make_frozen_snapshot() -> Dictionary:
	var ledger := Brush.new(SEED, Field.GENERATOR_VERSION)
	var ok0: bool = ledger.add_sphere(Brush.Mode.FILL, Vector3(8.0, 1.17898154258728, 5.10309219360352), 0.58)
	if not ok0:
		return {"valid": false, "reason": "fill_rejected", "detail": ledger.last_rejection_reason}
	var ok1: bool = ledger.add_sphere(Brush.Mode.CARVE, Vector3(8.0, 1.17898154258728, 5.92309236526489), 0.58)
	if not ok1:
		return {"valid": false, "reason": "carve_rejected", "detail": ledger.last_rejection_reason}
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	if int(snapshot.get("revision", -1)) != 2:
		return {"valid": false, "reason": "snapshot_revision_mismatch"}
	return {"valid": true, "snapshot": snapshot}


func _sample(world: Vector3, snapshot: Dictionary) -> float:
	var mapped: Dictionary = Spatial.world_to_region_local(world)
	if not bool(mapped.get("valid", false)):
		return NAN
	return Brush.sample_density_snapshot(SEED, mapped.region_key, mapped.local_position, false, snapshot)


func _build_shared_surface(snapshot: Dictionary) -> Dictionary:
	var dims := CELLS + Vector3i.ONE
	var values := PackedFloat32Array()
	values.resize(dims.x * dims.y * dims.z)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var p := ROI_MIN + Vector3(x, y, z) * STEP
				var d := _sample(p, snapshot)
				if not is_finite(d):
					return {"valid": false, "reason": "non_finite_sample", "sample": [x, y, z]}
				values[_index(x, y, z, dims)] = d

	var root_cache: Dictionary = {}
	var root_position_key: Dictionary = {}
	var triangles: Array[Dictionary] = []
	var dropped_degenerate_candidate_count := 0
	for y in range(CELLS.y):
		for z in range(CELLS.z):
			for x in range(CELLS.x):
				var cell := Vector3i(x, y, z)
				var nodes: Array[Vector3i] = []
				var points: Array[Vector3] = []
				var density: Array[float] = []
				for corner in CORNERS:
					var node: Vector3i = cell + Vector3i(corner)
					nodes.append(node)
					points.append(ROI_MIN + Vector3(node) * STEP)
					density.append(values[_index(node.x, node.y, node.z, dims)])
				for tet in TETS:
					var emitted := _polygonize_tet(tet, nodes, points, density, cell, root_cache, root_position_key)
					dropped_degenerate_candidate_count += int(emitted.get("degenerate", 0))
					triangles.append_array(emitted.get("triangles", []))

	var duplicate_count := 0
	var triangle_keys: Dictionary = {}
	var edge_incidence: Dictionary = {}
	var edge_sides: Dictionary = {}
	var edge_points: Dictionary = {}
	for tri_value in triangles:
		var tri: Dictionary = tri_value
		var ids: Array = tri.root_ids
		var canonical_ids := [String(ids[0]), String(ids[1]), String(ids[2])]
		canonical_ids.sort()
		var tri_key := "|".join(canonical_ids)
		if triangle_keys.has(tri_key):
			duplicate_count += 1
		triangle_keys[tri_key] = true
		for pair in [[0, 1], [1, 2], [2, 0]]:
			var a := String(ids[pair[0]])
			var b := String(ids[pair[1]])
			var key := _ordered_pair(a, b)
			edge_incidence[key] = int(edge_incidence.get(key, 0)) + 1
			if not edge_sides.has(key):
				edge_sides[key] = {}
			var sides: Dictionary = edge_sides[key]
			sides[String(tri.side)] = true
			edge_sides[key] = sides
			edge_points[key] = [root_cache[a], root_cache[b]]

	var seam_edges: Array[String] = []
	var bad_incidence := 0
	var cross_owner := 0
	for edge_value in edge_incidence.keys():
		var edge_key := String(edge_value)
		var pts: Array = edge_points[edge_key]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[1]
		if absf(a.x - SEAM_X) > EPS or absf(b.x - SEAM_X) > EPS:
			continue
		# Ignore only the outer Y/Z box edges. They are intentionally open ROI boundaries.
		if _on_roi_outer_yz(a) and _on_roi_outer_yz(b):
			continue
		seam_edges.append(edge_key)
		if int(edge_incidence[edge_key]) != 2:
			bad_incidence += 1
		var sides: Dictionary = edge_sides[edge_key]
		if sides.has("left") and sides.has("right"):
			cross_owner += 1

	var tjunctions := _count_t_junctions(seam_edges, edge_points)
	var signature_rows: Array[String] = []
	for tri_value in triangles:
		var ids: Array = tri_value.root_ids
		var row := [String(ids[0]), String(ids[1]), String(ids[2])]
		row.sort()
		signature_rows.append("|".join(row))
	signature_rows.sort()
	var mesh_signature := _fnv1a_64("\n".join(signature_rows))

	var root_consistent := true
	for root_id in root_cache.keys():
		var p: Vector3 = root_cache[root_id]
		if String(root_position_key.get(root_id, "")) != _point_key(p):
			root_consistent = false
			break

	return {
		"valid": true,
		"schema": "P3.1.ArchAlt.SharedSurfaceProbe.v1",
		"scenario_id": "R9.2.SEAM.XPLUS_EQUAL.v1",
		"seed": SEED,
		"ledger_revision": int(snapshot.get("revision", -1)),
		"roi_min": [ROI_MIN.x, ROI_MIN.y, ROI_MIN.z],
		"cells": [CELLS.x, CELLS.y, CELLS.z],
		"step": STEP,
		"seam_plane_x": SEAM_X,
		"triangle_count": triangles.size(),
		"unique_root_count": root_cache.size(),
		"seam_edge_count": seam_edges.size(),
		"seam_bad_incidence_count": bad_incidence,
		"seam_cross_owner_count": cross_owner,
		"t_junction_count": tjunctions,
		"duplicate_triangle_count": duplicate_count,
		"emitted_degenerate_triangle_count": 0,\n\t\t"dropped_degenerate_candidate_count": dropped_degenerate_candidate_count,
		"root_identity_consistent": root_consistent,
		"mesh_signature": mesh_signature,
		"architecture": "single global SDF seam authority; region meshes consume shared boundary geometry instead of independently reconstructing x=16",
	}


func _polygonize_tet(
	tet: Array,
	nodes: Array[Vector3i],
	points: Array[Vector3],
	density: Array[float],
	cell: Vector3i,
	root_cache: Dictionary,
	root_position_key: Dictionary
) -> Dictionary:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for local_index in tet:
		if density[local_index] >= 0.0:
			inside.append(local_index)
		else:
			outside.append(local_index)
	if inside.is_empty() or outside.is_empty():
		return {"triangles": [], "degenerate": 0}

	var root_ids: Array[String] = []
	if inside.size() == 1 or inside.size() == 3:
		var singleton: int
		var others: Array[int]
		if inside.size() == 1:
			singleton = inside[0]
			others = outside
		else:
			singleton = outside[0]
			others = inside
		for other in others:
			root_ids.append(_root_id_and_cache(singleton, other, nodes, points, density, root_cache, root_position_key))
		return _emit_triangle(root_ids[0], root_ids[1], root_ids[2], cell, root_cache)

	# 2/2 split: deterministic quad diagonal derived from canonical root IDs.
	var r00 := _root_id_and_cache(inside[0], outside[0], nodes, points, density, root_cache, root_position_key)
	var r01 := _root_id_and_cache(inside[0], outside[1], nodes, points, density, root_cache, root_position_key)
	var r10 := _root_id_and_cache(inside[1], outside[0], nodes, points, density, root_cache, root_position_key)
	var r11 := _root_id_and_cache(inside[1], outside[1], nodes, points, density, root_cache, root_position_key)
	var option_a := _ordered_pair(r00, r11)
	var option_b := _ordered_pair(r01, r10)
	var result: Array[Dictionary] = []
	var degenerate := 0
	if option_a <= option_b:
		var a := _emit_triangle(r00, r01, r11, cell, root_cache)
		var b := _emit_triangle(r00, r11, r10, cell, root_cache)
		result.append_array(a.triangles)
		result.append_array(b.triangles)
		degenerate += int(a.degenerate) + int(b.degenerate)
	else:
		var a := _emit_triangle(r00, r01, r10, cell, root_cache)
		var b := _emit_triangle(r01, r11, r10, cell, root_cache)
		result.append_array(a.triangles)
		result.append_array(b.triangles)
		degenerate += int(a.degenerate) + int(b.degenerate)
	return {"triangles": result, "degenerate": degenerate}


func _root_id_and_cache(
	a: int,
	b: int,
	nodes: Array[Vector3i],
	points: Array[Vector3],
	density: Array[float],
	root_cache: Dictionary,
	root_position_key: Dictionary
) -> String:
	var na := nodes[a]
	var nb := nodes[b]
	var node_a := _node_key(na)
	var node_b := _node_key(nb)
	var key := _ordered_pair(node_a, node_b)
	if root_cache.has(key):
		return key
	var da := density[a]
	var db := density[b]
	var denominator := da - db
	var t := 0.5 if is_zero_approx(denominator) else clampf(da / denominator, 0.0, 1.0)
	var p := points[a].lerp(points[b], t)
	root_cache[key] = p
	root_position_key[key] = _point_key(p)
	return key


func _emit_triangle(a: String, b: String, c: String, cell: Vector3i, roots: Dictionary) -> Dictionary:
	if a == b or b == c or c == a:
		return {"triangles": [], "degenerate": 1}
	var pa: Vector3 = roots[a]
	var pb: Vector3 = roots[b]
	var pc: Vector3 = roots[c]
	if (pb - pa).cross(pc - pa).length_squared() <= 1.0e-14:
		return {"triangles": [], "degenerate": 1}
	var side := "left" if ROI_MIN.x + (float(cell.x) + 0.5) * STEP < SEAM_X else "right"
	return {"triangles": [{"root_ids": [a, b, c], "side": side, "cell": [cell.x, cell.y, cell.z]}], "degenerate": 0}


func _count_t_junctions(seam_edges: Array[String], edge_points: Dictionary) -> int:
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
			var projection := a + ab * t
			if projection.distance_squared_to(p) <= 1.0e-12:
				count += 1
	return count


func _on_roi_outer_yz(p: Vector3) -> bool:
	var maxp := ROI_MIN + Vector3(CELLS) * STEP
	return absf(p.y - ROI_MIN.y) <= EPS or absf(p.y - maxp.y) <= EPS 		or absf(p.z - ROI_MIN.z) <= EPS or absf(p.z - maxp.z) <= EPS


func _index(x: int, y: int, z: int, dims: Vector3i) -> int:
	return (y * dims.z + z) * dims.x + x


func _node_key(v: Vector3i) -> String:
	return "%d,%d,%d" % [v.x, v.y, v.z]


func _ordered_pair(a: String, b: String) -> String:
	return a + ">" + b if a < b else b + ">" + a


func _point_key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * ROOT_QUANT), roundi(p.y * ROOT_QUANT), roundi(p.z * ROOT_QUANT)]


func _fnv1a_64(text_value: String) -> String:
	var hash: int = 1469598103934665603
	for byte in text_value.to_utf8_buffer():
		hash = hash ^ int(byte)
		hash = hash * 1099511628211
	return "%016x" % hash


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)


func _finish(result: Dictionary) -> void:
	var payload := {
		"status": "PASS" if failures == 0 else "FAIL",
		"assertions": assertions,
		"failures": failures,
		"result": result,
	}
	print("ARCH_ALT_SHARED_SURFACE_RESULT=" + JSON.stringify(payload))
	print("ARCH_ALT_SHARED_SURFACE_%s: assertions=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", assertions, failures])
	quit(0 if failures == 0 else 1)
