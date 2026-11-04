extends RefCounted

const CERT_SIGN_MARGIN: float = 1.0e-7
const CERT_CUTOFF_MARGIN: float = 1.0e-18
const CUTOFF_SQUARED: float = 1.0e-12

static func geometry_sha(region: Dictionary) -> String:
	var payload: Dictionary = {"region_id": region.get("region_id", ""), "patch_face_id": region.get("patch_face_id", ""), "tetrahedron_id": region.get("tetrahedron_id", ""), "facet_index": region.get("facet_index", -1), "clipped_world_polygon": region.get("clipped_world_polygon", []), "clipped_projected_polygon": region.get("clipped_projected_polygon", [])}
	return _sha256(JSON.stringify(payload, "", false).to_utf8_buffer())

static func initial_cells(region: Dictionary) -> Array[Dictionary]:
	var projected: Array = region.get("clipped_projected_polygon", [])
	var world: Array = region.get("clipped_world_polygon", [])
	var cells: Array[Dictionary] = []
	if projected.size() != world.size() or projected.size() < 3:
		return cells
	for index in range(1, projected.size() - 1):
		cells.append({"projected": [projected[0], projected[index], projected[index + 1]], "world": [world[0], world[index], world[index + 1]]})
	return cells

static func advance_frontier(queue_value: Array, proof_value: Array, edge_a: Vector2, edge_b: Vector2, root_ids: Array, arcs: Array, projected_positions: Dictionary, node_cap: int) -> Dictionary:
	var queue: Array = queue_value.duplicate(true)
	var proof_leaves: Array = proof_value.duplicate(true)
	var processed: int = 0
	while not queue.is_empty() and processed < maxi(node_cap, 0):
		var cell: Dictionary = queue.pop_front()
		var classified: Dictionary = classify_cell(cell, edge_a, edge_b, root_ids, arcs, projected_positions)
		processed += 1
		if bool(classified.get("rejected", false)):
			classified["cell_key"] = _sha256(JSON.stringify(cell, "", false).to_utf8_buffer())
			proof_leaves.append(classified)
		else:
			var children: Array[Dictionary] = subdivide(cell)
			if children.size() == 2:
				queue.append_array(children)
			else:
				queue.append(cell)
	return {"frontier_cells": queue, "proof_leaf_certificates": proof_leaves, "processed_cells": processed, "continuous_domain_empty": queue.is_empty() and not proof_leaves.is_empty()}

static func classify_cell(cell: Dictionary, edge_a: Vector2, edge_b: Vector2, root_ids: Array, arcs: Array, projected_positions: Dictionary) -> Dictionary:
	var p2: Array = cell.get("projected", [])
	var p3: Array = cell.get("world", [])
	if p2.size() != 3 or p3.size() != 3:
		return {"rejected": false, "reason": "cell_geometry_malformed"}
	var a_id: String = String(root_ids[0]) if root_ids.size() == 2 else ""
	var b_id: String = String(root_ids[1]) if root_ids.size() == 2 else ""
	if a_id.is_empty() or b_id.is_empty():
		return {"rejected": false, "reason": "obligation_roots_invalid"}
	var world_a: Vector3 = Vector3(projected_positions.get("__world__" + a_id, Vector3.ZERO))
	var world_b: Vector3 = Vector3(projected_positions.get("__world__" + b_id, Vector3.ZERO))
	var cutoff_max: float = -INF
	for point_value in p3:
		var point: Vector3 = Vector3(float(point_value[0]), float(point_value[1]), float(point_value[2]))
		cutoff_max = maxf(cutoff_max, (world_b - world_a).cross(point - world_a).length_squared())
	if cutoff_max <= CUTOFF_SQUARED - CERT_CUTOFF_MARGIN:
		return {"rejected": true, "gate": "FROZEN_CUTOFF", "reason": "convex_cross_squared_upper_bound_at_vertices", "upper_bound": cutoff_max, "margin_to_cutoff": CUTOFF_SQUARED - cutoff_max, "cell": cell}
	for arc_value in arcs:
		var arc: Dictionary = arc_value
		var ids: Array = arc.get("root_ids", [])
		if ids.size() != 2:
			continue
		var u_id: String = String(ids[0])
		var v_id: String = String(ids[1])
		if _edge_key(u_id, v_id) == _edge_key(a_id, b_id):
			continue
		if not projected_positions.has(u_id) or not projected_positions.has(v_id):
			continue
		var u: Vector2 = Vector2(projected_positions[u_id])
		var v: Vector2 = Vector2(projected_positions[v_id])
		var fixed_cross: Dictionary = _proper_cross_fixed(edge_a, edge_b, u, v)
		if bool(fixed_cross.get("proved", false)):
			return {"rejected": true, "gate": "REQUIRED_ARC", "reason": "required_arc_crosses_fixed_obligation_edge", "arc_id": arc.get("arc_id", ""), "bound": fixed_cross, "cell": cell}
		if u_id != a_id and u_id != b_id:
			var inside_u: Dictionary = _endpoint_inside_triangle_for_all(edge_a, edge_b, u, p2)
			if bool(inside_u.get("proved", false)):
				return {"rejected": true, "gate": "REQUIRED_ARC", "reason": "required_arc_endpoint_inside_every_candidate_triangle", "arc_id": arc.get("arc_id", ""), "root_id": u_id, "bound": inside_u, "cell": cell}
		if v_id != a_id and v_id != b_id:
			var inside_v: Dictionary = _endpoint_inside_triangle_for_all(edge_a, edge_b, v, p2)
			if bool(inside_v.get("proved", false)):
				return {"rejected": true, "gate": "REQUIRED_ARC", "reason": "required_arc_endpoint_inside_every_candidate_triangle", "arc_id": arc.get("arc_id", ""), "root_id": v_id, "bound": inside_v, "cell": cell}
		if u_id != a_id and u_id != b_id and v_id != a_id and v_id != b_id:
			var cross_a: Dictionary = _moving_edge_crosses_arc_for_all(edge_a, u, v, p2)
			if bool(cross_a.get("proved", false)):
				return {"rejected": true, "gate": "REQUIRED_ARC", "reason": "candidate_edge_crosses_required_arc_for_all_points", "arc_id": arc.get("arc_id", ""), "triangle_edge": [a_id, "SUPPORT"], "bound": cross_a, "cell": cell}
			var cross_b: Dictionary = _moving_edge_crosses_arc_for_all(edge_b, u, v, p2)
			if bool(cross_b.get("proved", false)):
				return {"rejected": true, "gate": "REQUIRED_ARC", "reason": "candidate_edge_crosses_required_arc_for_all_points", "arc_id": arc.get("arc_id", ""), "triangle_edge": [b_id, "SUPPORT"], "bound": cross_b, "cell": cell}
	return {"rejected": false, "reason": "conservative_interval_tests_not_decisive"}

static func subdivide(cell: Dictionary) -> Array[Dictionary]:
	var projected: Array = cell.get("projected", [])
	var world: Array = cell.get("world", [])
	if projected.size() != 3 or world.size() != 3:
		return []
	var edge_index: int = 0
	var longest: float = -1.0
	for index in range(3):
		var next: int = (index + 1) % 3
		var a: Vector2 = Vector2(float(projected[index][0]), float(projected[index][1]))
		var b: Vector2 = Vector2(float(projected[next][0]), float(projected[next][1]))
		var length: float = a.distance_squared_to(b)
		if length > longest:
			longest = length
			edge_index = index
	var i: int = edge_index
	var j: int = (edge_index + 1) % 3
	var k: int = (edge_index + 2) % 3
	var midpoint2: Vector2 = (Vector2(projected[i][0], projected[i][1]) + Vector2(projected[j][0], projected[j][1])) * 0.5
	var midpoint3: Vector3 = (Vector3(float(world[i][0]), float(world[i][1]), float(world[i][2])) + Vector3(float(world[j][0]), float(world[j][1]), float(world[j][2]))) * 0.5
	var p_mid: Array[float] = [midpoint2.x, midpoint2.y]
	var w_mid: Array[float] = [midpoint3.x, midpoint3.y, midpoint3.z]
	return [
		{"projected": [projected[i], p_mid, projected[k]], "world": [world[i], w_mid, world[k]]},
		{"projected": [p_mid, projected[j], projected[k]], "world": [w_mid, world[j], world[k]]}
	]

static func _endpoint_inside_triangle_for_all(a: Vector2, b: Vector2, endpoint: Vector2, cell_points: Array) -> Dictionary:
	var fixed: float = _orient(a, b, endpoint)
	if absf(fixed) <= CERT_SIGN_MARGIN:
		return {"proved": false, "reason": "fixed_triangle_edge_near_endpoint"}
	var sign_value: float = 1.0 if fixed > 0.0 else -1.0
	var first: Dictionary = _linear_orientation_bound(b, endpoint, cell_points, true)
	var second: Dictionary = _linear_orientation_bound(a, endpoint, cell_points, false)
	var signed_min: float = minf(sign_value * float(first.minimum), sign_value * float(second.minimum)) if sign_value > 0.0 else minf(sign_value * float(first.maximum), sign_value * float(second.maximum))
	# The two varying orientations must have the same sign as orient(A,B,X).
	var first_min: float = float(first.minimum) if sign_value > 0.0 else -float(first.maximum)
	var second_min: float = float(second.minimum) if sign_value > 0.0 else -float(second.maximum)
	if first_min > CERT_SIGN_MARGIN and second_min > CERT_SIGN_MARGIN:
		return {"proved": true, "fixed_orientation": fixed, "orientation_min_abs": minf(first_min, second_min), "rounding_guard": CERT_SIGN_MARGIN}
	return {"proved": false, "signed_min": signed_min, "first": first, "second": second}

static func _moving_edge_crosses_arc_for_all(fixed_endpoint: Vector2, arc_a: Vector2, arc_b: Vector2, cell_points: Array) -> Dictionary:
	var o3: float = _orient(arc_a, arc_b, fixed_endpoint)
	if absf(o3) <= CERT_SIGN_MARGIN:
		return {"proved": false, "reason": "fixed_endpoint_near_arc_line"}
	var o1: Dictionary = _linear_orientation_bound(fixed_endpoint, arc_a, cell_points, false)
	var o2: Dictionary = _linear_orientation_bound(fixed_endpoint, arc_b, cell_points, false)
	var o4: Dictionary = _linear_orientation_bound(arc_a, arc_b, cell_points, false)
	var o1_sign: int = _uniform_sign(o1)
	var o2_sign: int = _uniform_sign(o2)
	var o4_sign: int = _uniform_sign(o4)
	var o3_sign: int = 1 if o3 > 0.0 else -1
	if o1_sign != 0 and o2_sign != 0 and o1_sign != o2_sign and o4_sign != 0 and o4_sign != o3_sign:
		var min_product: float = minf(absf(float(o1.minimum)), absf(float(o1.maximum))) * minf(absf(float(o2.minimum)), absf(float(o2.maximum)))
		var arc_product: float = absf(o3) * minf(absf(float(o4.minimum)), absf(float(o4.maximum)))
		if min_product > 1.0e-20 and arc_product > 1.0e-20:
			return {"proved": true, "orientation_bounds": {"o1": o1, "o2": o2, "o3": o3, "o4": o4}, "minimum_intersection_products": [min_product, arc_product], "rounding_guard": CERT_SIGN_MARGIN}
	return {"proved": false, "orientation_bounds": {"o1": o1, "o2": o2, "o3": o3, "o4": o4}}

static func _proper_cross_fixed(a: Vector2, b: Vector2, u: Vector2, v: Vector2) -> Dictionary:
	var o1: float = _orient(a, b, u)
	var o2: float = _orient(a, b, v)
	var o3: float = _orient(u, v, a)
	var o4: float = _orient(u, v, b)
	if absf(o1) > CERT_SIGN_MARGIN and absf(o2) > CERT_SIGN_MARGIN and absf(o3) > CERT_SIGN_MARGIN and absf(o4) > CERT_SIGN_MARGIN and (o1 > 0.0) != (o2 > 0.0) and (o3 > 0.0) != (o4 > 0.0):
		var products: Array[float] = [absf(o1 * o2), absf(o3 * o4)]
		if products[0] > 1.0e-20 and products[1] > 1.0e-20:
			return {"proved": true, "orientations": [o1, o2, o3, o4], "minimum_products": products, "rounding_guard": CERT_SIGN_MARGIN}
	return {"proved": false, "orientations": [o1, o2, o3, o4]}

static func _linear_orientation_bound(a: Vector2, b: Vector2, points: Array, variable_first: bool) -> Dictionary:
	var values: Array[float] = []
	for point_value in points:
		var p: Vector2 = Vector2(float(point_value[0]), float(point_value[1]))
		values.append(_orient(a, p, b) if variable_first else _orient(a, b, p))
	return {"minimum": values.min() if not values.is_empty() else INF, "maximum": values.max() if not values.is_empty() else -INF, "values": values}

static func _uniform_sign(bounds: Dictionary) -> int:
	if float(bounds.get("minimum", -INF)) > CERT_SIGN_MARGIN:
		return 1
	if float(bounds.get("maximum", INF)) < -CERT_SIGN_MARGIN:
		return -1
	return 0

static func _orient(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)

static func _edge_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

static func _sha256(bytes: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
