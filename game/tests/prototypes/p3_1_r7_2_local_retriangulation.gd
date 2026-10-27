extends RefCounted

## Isolated R7.2 topology-repair experiments. This helper consumes only the
## disposable R7 fixture's sampled triangle soup; it is not used by production.
const AREA2_LIMIT_SQUARED := 1.0e-12
const WELD_EPSILON := 1.0e-5

func extract_local_mesh(fixture: RefCounted, cells: Dictionary, focus_ids: Array[int]) -> Dictionary:
	var selected: Dictionary = {}
	for value in focus_ids:
		selected[value] = true
		var cell: Vector3i = fixture._cell_from_id(value)
		for direction_value in fixture.FACE_DIRECTIONS:
			var direction: Dictionary = direction_value
			var neighbor: Vector3i = cell + Vector3i(direction.delta)
			if not fixture._cell_in_bounds(neighbor):
				continue
			selected[fixture._cell_id(neighbor)] = true
	var vertices: Array[Vector3] = []
	var buckets: Dictionary = {}
	var faces: Array[Dictionary] = []
	for cell_id_value in selected:
		var cell_id := int(cell_id_value)
		if not cells.has(cell_id):
			continue
		var positions: PackedVector3Array = cells[cell_id].vertices
		var normals: PackedVector3Array = cells[cell_id].get("normals", PackedVector3Array())
		for index in range(0, positions.size(), 3):
			var ids: Array[int] = []
			for offset in range(3):
				ids.append(_weld(positions[index + offset], vertices, buckets))
			if ids[0] != ids[1] and ids[1] != ids[2] and ids[2] != ids[0]:
				var face_normal: Vector3 = normals[index].normalized() if normals.size() == positions.size() else Vector3.ZERO
				faces.append({"v": ids, "cell": cell_id, "original_v": ids.duplicate(), "source_normal": face_normal})
	var original_vertices: Array[Vector3] = []
	for point in vertices: original_vertices.append(point)
	return {"vertices": vertices, "original_vertices": original_vertices, "faces": faces, "selected": selected}


func run_strategy(fixture: RefCounted, source: Dictionary, strategy: String) -> Dictionary:
	var mesh := _copy_mesh(source)
	var before: Dictionary = metrics(fixture, mesh)
	var changed_vertices: Array = []
	var strategy_data: Dictionary = {}
	match strategy:
		"A_edge_collapse":
			strategy_data = _edge_collapse(fixture, mesh, before)
		"B_constrained_cavity":
			strategy_data = _cavity_retriangulate(fixture, mesh, false)
		"C_boundary_patch_remesh":
			strategy_data = _cavity_retriangulate(fixture, mesh, true)
		_:
			return {"valid": false, "reason": "unknown_strategy", "strategy": strategy}
	if strategy_data.has("mesh"):
		mesh = strategy_data.mesh
	changed_vertices = strategy_data.get("changed_vertices", [])
	var after: Dictionary = metrics(fixture, mesh)
	var surface: Dictionary = _surface_metrics(fixture, mesh, changed_vertices)
	surface["normal_change"] = _normal_change_metrics(mesh)
	var boundary_unchanged: bool = before.boundary_signature == after.boundary_signature
	var geometry_ok: bool = bool(strategy_data.get("valid", false)) and boundary_unchanged \
		and int(after.internal_open_edges) == 0 and int(after.degenerate_triangles) == 0 \
		and int(after.nonmanifold_edges) == 0 and int(after.same_winding_edges) == 0 \
		and int(after.t_junctions) == 0 \
		and int(after.face_component_count) == int(before.face_component_count)
	return {"strategy": strategy, "valid": geometry_ok, "strategy_attempt": strategy_data,
		"before": before, "after": after, "external_boundary_unchanged": boundary_unchanged,
		"surface_metrics": surface,
		"disposition": "PASS_ALL_LOCAL_TOPOLOGY_INVARIANTS" if geometry_ok else "FAIL_LOCAL_TOPOLOGY_OR_GEOMETRY_INVARIANT"}


func metrics(fixture: RefCounted, mesh: Dictionary) -> Dictionary:
	var vertices: Array[Vector3] = mesh.vertices
	var faces: Array[Dictionary] = mesh.faces
	var edges: Dictionary = {}
	var degenerate := 0
	var exact_zero_area := 0
	for face_index in range(faces.size()):
		var face: Dictionary = faces[face_index]
		var ids: Array = face.v
		var a: Vector3 = vertices[int(ids[0])]
		var b: Vector3 = vertices[int(ids[1])]
		var c: Vector3 = vertices[int(ids[2])]
		var cross_squared := (b - a).cross(c - a).length_squared()
		if cross_squared == 0.0: exact_zero_area += 1
		if cross_squared <= AREA2_LIMIT_SQUARED:
			degenerate += 1
		for edge_offset in range(3):
			var first := int(ids[edge_offset])
			var second := int(ids[(edge_offset + 1) % 3])
			var key := _edge_key(first, second)
			var record: Dictionary = edges.get(key, {"count": 0, "orientation": 0, "owners": [], "a": mini(first, second), "b": maxi(first, second)})
			record.count = int(record.count) + 1
			record.orientation = int(record.orientation) + (1 if first < second else -1)
			var owners: Array = record.owners
			owners.append(int(face.cell))
			record.owners = owners
			edges[key] = record
	var internal_open := 0
	var external_open := 0
	var nonmanifold := 0
	var same_winding := 0
	var boundary: Array[String] = []
	var open_examples: Array[Dictionary] = []
	for key_value in edges:
		var key := String(key_value)
		var record: Dictionary = edges[key]
		var count := int(record.count)
		if count == 1:
			var p0: Vector3 = vertices[int(record.a)]
			var p1: Vector3 = vertices[int(record.b)]
			if _is_selection_boundary(fixture, p0, p1, record.owners, mesh.selected):
				external_open += 1
				boundary.append(_edge_coord_key(p0, p1))
			else:
				internal_open += 1
				if open_examples.size() < 24:
					open_examples.append({"key": key, "a": _v3(p0), "b": _v3(p1), "owners": record.owners})
		elif count > 2:
			nonmanifold += 1
		elif count == 2 and int(record.orientation) != 0:
			same_winding += 1
	var t_junctions := _count_t_junctions(vertices, edges)
	boundary.sort()
	return {"face_count": faces.size(), "edge_count": edges.size(), "internal_open_edges": internal_open,
		"external_open_edges": external_open, "degenerate_triangles": degenerate,
		"exact_zero_area_triangles": exact_zero_area, "nonzero_subthreshold_triangles": degenerate - exact_zero_area,
		"nonmanifold_edges": nonmanifold, "same_winding_edges": same_winding,
		"t_junctions": t_junctions, "face_component_count": _face_component_count(faces), "boundary_signature": boundary,
		"open_edge_examples": open_examples,
		"threshold_cross_squared": AREA2_LIMIT_SQUARED,
		"oracle": "welded Euclidean positions <=1e-5; exposed selected-cell face edges are expected boundary; all other incidence must be 2"}


func _edge_collapse(fixture: RefCounted, mesh: Dictionary, before: Dictionary) -> Dictionary:
	var faces: Array[Dictionary] = mesh.faces
	var vertices: Array[Vector3] = mesh.vertices
	var candidates: Array[Dictionary] = []
	for face_index in range(faces.size()):
		var ids: Array = faces[face_index].v
		var p0: Vector3 = vertices[int(ids[0])]
		var p1: Vector3 = vertices[int(ids[1])]
		var p2: Vector3 = vertices[int(ids[2])]
		if (p1 - p0).cross(p2 - p0).length_squared() <= AREA2_LIMIT_SQUARED:
			for i in range(3):
				var u := int(ids[i])
				var v := int(ids[(i + 1) % 3])
				candidates.append({"u": mini(u, v), "v": maxi(u, v), "length2": vertices[u].distance_squared_to(vertices[v])})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.length2) == float(b.length2): return _edge_key(int(a.u), int(a.v)) < _edge_key(int(b.u), int(b.v))
		return float(a.length2) < float(b.length2))
	var unique: Array[Dictionary] = []
	var seen: Dictionary = {}
	for candidate in candidates:
		var key := _edge_key(int(candidate.u), int(candidate.v))
		if not seen.has(key):
			seen[key] = true
			unique.append(candidate)
	var accepted := 0
	var rejected: Dictionary = {}
	var changed: Array[Vector3] = []
	var maximum_vertex_displacement := 0.0
	for candidate in unique:
		var attempt := _try_collapse(fixture, mesh, int(candidate.u), int(candidate.v))
		if bool(attempt.get("valid", false)):
			mesh = attempt.mesh
			accepted += 1
			changed.append_array(attempt.changed_vertices)
			maximum_vertex_displacement = maxf(maximum_vertex_displacement, float(attempt.max_vertex_displacement))
		else:
			var reason := String(attempt.get("reason", "rejected"))
			rejected[reason] = int(rejected.get(reason, 0)) + 1
		if _degenerate_face_count(mesh) == 0:
			break
	return {"valid": accepted > 0, "accepted_collapses": accepted,
		"candidate_edges": unique.size(), "rejected_reasons": rejected,
		"changed_vertices": changed, "max_vertex_displacement_world": maximum_vertex_displacement, "mesh": mesh,
		"note": "edge collapses require the manifold link condition, fixed selection boundary, no inverted or sub-threshold surviving face"}


func _try_collapse(fixture: RefCounted, mesh: Dictionary, u: int, v: int) -> Dictionary:
	var vertices: Array[Vector3] = mesh.vertices
	var faces: Array[Dictionary] = mesh.faces
	var edge_faces: Array[int] = []
	var neighbors_u: Dictionary = {}
	var neighbors_v: Dictionary = {}
	var common_expected: Dictionary = {}
	for i in range(faces.size()):
		var ids: Array = faces[i].v
		var has_u := ids.has(u)
		var has_v := ids.has(v)
		if has_u and has_v:
			edge_faces.append(i)
			for value in ids:
				if int(value) != u and int(value) != v: common_expected[int(value)] = true
		if has_u:
			for value in ids:
				if int(value) != u: neighbors_u[int(value)] = true
		if has_v:
			for value in ids:
				if int(value) != v: neighbors_v[int(value)] = true
	if edge_faces.size() != 2 or common_expected.size() != 2:
		return {"valid": false, "reason": "edge_not_two_manifold_faces"}
	var common_actual: Dictionary = {}
	for neighbor in neighbors_u:
		if int(neighbor) != v and neighbors_v.has(int(neighbor)): common_actual[int(neighbor)] = true
	if common_actual.size() != 2 or not common_actual.has(common_expected.keys()[0]) or not common_actual.has(common_expected.keys()[1]):
		return {"valid": false, "reason": "link_condition_failed"}
	if _vertex_on_selection_boundary(fixture, vertices[u], mesh.selected) or _vertex_on_selection_boundary(fixture, vertices[v], mesh.selected):
		return {"valid": false, "reason": "would_move_fixed_patch_boundary"}
	var original_metrics: Dictionary = metrics(fixture, mesh)
	var targets: Array[Vector3] = [(vertices[u] + vertices[v]) * 0.5, vertices[u], vertices[v]]
	var failures: Array[String] = []
	for target in targets:
		var result := _copy_mesh(mesh)
		var result_vertices: Array[Vector3] = result.vertices
		result_vertices[u] = target
		var kept: Array[Dictionary] = []
		var candidate_failed := false
		var failure_reason := ""
		for i in range(faces.size()):
			var old_face: Dictionary = faces[i]
			var old_ids: Array = old_face.v
			var ids: Array[int] = []
			for value in old_ids:
				var id := int(value)
				ids.append(u if id == v else id)
			if ids[0] == ids[1] or ids[1] == ids[2] or ids[2] == ids[0]:
				continue
			if ids != old_ids:
				var old_cross := (vertices[int(old_ids[1])] - vertices[int(old_ids[0])]).cross(vertices[int(old_ids[2])] - vertices[int(old_ids[0])])
				var new_cross := (result_vertices[ids[1]] - result_vertices[ids[0]]).cross(result_vertices[ids[2]] - result_vertices[ids[0]])
				if new_cross.length_squared() <= AREA2_LIMIT_SQUARED:
					candidate_failed = true; failure_reason = "collapse_creates_subthreshold_face"; break
				if old_cross.dot(new_cross) <= 0.0:
					candidate_failed = true; failure_reason = "collapse_inverts_winding"; break
			var new_face := old_face.duplicate(true)
			new_face.v = ids
			kept.append(new_face)
		if candidate_failed:
			failures.append(failure_reason)
			continue
		result.faces = kept
		result.vertices = result_vertices
		var candidate_metrics: Dictionary = metrics(fixture, result)
		if int(candidate_metrics.degenerate_triangles) >= int(original_metrics.degenerate_triangles):
			failures.append("collapse_did_not_remove_subthreshold_faces"); continue
		if int(candidate_metrics.internal_open_edges) > int(original_metrics.internal_open_edges):
			failures.append("collapse_adds_internal_open_edge"); continue
		if int(candidate_metrics.nonmanifold_edges) > int(original_metrics.nonmanifold_edges):
			failures.append("collapse_adds_nonmanifold_edge"); continue
		if int(candidate_metrics.same_winding_edges) > int(original_metrics.same_winding_edges):
			failures.append("collapse_adds_same_winding_edge"); continue
		if int(candidate_metrics.t_junctions) > int(original_metrics.t_junctions):
			failures.append("collapse_adds_t_junction"); continue
		if candidate_metrics.boundary_signature != original_metrics.boundary_signature:
			failures.append("collapse_changes_fixed_boundary"); continue
		var displacement := maxf(vertices[u].distance_to(target), vertices[v].distance_to(target))
		var moved: Array[Vector3] = []
		if vertices[u] != target: moved.append(vertices[u])
		if vertices[v] != target: moved.append(vertices[v])
		moved.append(target)
		return {"valid": true, "mesh": result, "changed_vertices": moved,
			"max_vertex_displacement": displacement, "target_policy": "midpoint" if target == targets[0] else ("keep_lower_id" if target == targets[1] else "keep_higher_id")}
	return {"valid": false, "reason": failures.back() if not failures.is_empty() else "no_collapse_candidate", "rejections": failures}


func _cavity_retriangulate(fixture: RefCounted, mesh: Dictionary, expand_one_ring: bool) -> Dictionary:
	var vertices: Array[Vector3] = mesh.vertices
	var faces: Array[Dictionary] = mesh.faces
	var remove: Dictionary = {}
	var involved_vertices: Dictionary = {}
	for i in range(faces.size()):
		var ids: Array = faces[i].v
		var a: Vector3 = vertices[int(ids[0])]
		var b: Vector3 = vertices[int(ids[1])]
		var c: Vector3 = vertices[int(ids[2])]
		if (b - a).cross(c - a).length_squared() <= AREA2_LIMIT_SQUARED:
			remove[i] = true
			for id in ids: involved_vertices[int(id)] = true
	if expand_one_ring:
		var core_vertices := involved_vertices.duplicate()
		for i in range(faces.size()):
			for id in faces[i].v:
				if core_vertices.has(int(id)):
					remove[i] = true
	var kept: Array[Dictionary] = []
	for i in range(faces.size()):
		if not remove.has(i): kept.append(faces[i])
	var boundary_data := _boundary_loops(fixture, mesh, kept)
	if not bool(boundary_data.valid):
		return {"valid": false, "reason": boundary_data.reason, "removed_faces": remove.size(),
			"boundary_degrees": boundary_data.get("degrees", {})}
	var loops: Array = boundary_data.loops
	var added := 0
	var max_center_deviation := 0.0
	var max_center_offset := 0.0
	var changed: Array[Vector3] = []
	for loop_value in loops:
		var loop: Array[int] = loop_value
		var center := Vector3.ZERO
		for id in loop: center += vertices[id]
		center /= float(loop.size())
		var loop_edges: Array[Dictionary] = []
		for edge in boundary_data.edges:
			if loop.has(int(edge.a)) and loop.has(int(edge.b)): loop_edges.append(edge)
		var placement := _find_fan_center(fixture, center, loop_edges, vertices)
		if not bool(placement.get("valid", false)):
			return {"valid": false, "reason": "no_non_degenerate_fan_center_within_bounded_search",
				"removed_faces": remove.size(), "loops": loops.size(), "maximum_search_offset_world": placement.get("maximum_search_offset_world", 0.0),
				"changed_vertices": changed}
		var placed_center: Vector3 = placement.center
		max_center_offset = maxf(max_center_offset, float(placement.offset))
		var center_id := vertices.size()
		vertices.append(placed_center)
		changed.append(placed_center)
		max_center_deviation = maxf(max_center_deviation, absf(float(fixture._canonical_sample(placed_center))))
		for edge in loop_edges:
			# The replacement face traverses the shared boundary edge opposite the kept face.
			var tri := {"v": [int(edge.b), int(edge.a), center_id], "cell": int(edge.cell), "original_v": [int(edge.b), int(edge.a), center_id]}
			var p0: Vector3 = vertices[int(tri.v[0])]
			var p1: Vector3 = vertices[int(tri.v[1])]
			var p2: Vector3 = vertices[int(tri.v[2])]
			if (p1 - p0).cross(p2 - p0).length_squared() <= AREA2_LIMIT_SQUARED:
				return {"valid": false, "reason": "fan_triangle_below_frozen_threshold", "removed_faces": remove.size(),
					"loops": loops.size(), "max_center_density_abs": max_center_deviation, "changed_vertices": changed}
			kept.append(tri)
			added += 1
	mesh.faces = kept
	mesh.vertices = vertices
	var after: Dictionary = metrics(fixture, mesh)
	return {"valid": true, "removed_faces": remove.size(), "boundary_loops": loops.size(),
		"added_faces": added, "max_center_density_abs": max_center_deviation, "max_center_offset_world": max_center_offset,
		"changed_vertices": changed, "mesh": mesh,
		"note": "center-fan constrained to the extracted cavity boundary; boundary vertices remain fixed"}


func _find_fan_center(fixture: RefCounted, center: Vector3, edges: Array[Dictionary], vertices: Array[Vector3]) -> Dictionary:
	var h := 0.01
	var gradient := Vector3(
		float(fixture._canonical_sample(center + Vector3.RIGHT * h)) - float(fixture._canonical_sample(center - Vector3.RIGHT * h)),
		float(fixture._canonical_sample(center + Vector3.UP * h)) - float(fixture._canonical_sample(center - Vector3.UP * h)),
		float(fixture._canonical_sample(center + Vector3.BACK * h)) - float(fixture._canonical_sample(center - Vector3.BACK * h)))
	if gradient.length_squared() <= 1.0e-16:
		return {"valid": false, "reason": "fan_center_gradient_unavailable", "maximum_search_offset_world": 0.0}
	var normal := gradient.normalized()
	var previous := 0.0
	var step := 1.0e-8
	const MAX_OFFSET := 0.05 # Search stop-loss only; not an accepted geometric tolerance.
	while step <= MAX_OFFSET:
		for sign in [1.0, -1.0]:
			var candidate := center + normal * (step * float(sign))
			if _fan_areas_valid(candidate, edges, vertices):
				var low := previous
				var high := step
				for _iteration in range(24):
					var middle := (low + high) * 0.5
					if _fan_areas_valid(center + normal * (middle * float(sign)), edges, vertices): high = middle
					else: low = middle
				return {"valid": true, "center": center + normal * (high * float(sign)),
					"offset": high, "sign": sign, "sampled_step": step}
		previous = step
		step *= 2.0
	return {"valid": false, "maximum_search_offset_world": MAX_OFFSET,
		"reason": "frozen_area_threshold_not_reached_within_stop_loss"}


func _fan_areas_valid(center: Vector3, edges: Array[Dictionary], vertices: Array[Vector3]) -> bool:
	for edge in edges:
		var a: Vector3 = vertices[int(edge.a)]
		var b: Vector3 = vertices[int(edge.b)]
		if (a - b).cross(center - b).length_squared() <= AREA2_LIMIT_SQUARED: return false
	return true


func _boundary_loops(fixture: RefCounted, mesh: Dictionary, faces: Array[Dictionary]) -> Dictionary:
	var edge_map: Dictionary = {}
	for face in faces:
		var ids: Array = face.v
		for i in range(3):
			var a := int(ids[i]); var b := int(ids[(i + 1) % 3])
			var key := _edge_key(a, b)
			var rec: Dictionary = edge_map.get(key, {"count": 0, "a": a, "b": b, "cell": int(face.cell)})
			rec.count = int(rec.count) + 1
			if int(rec.count) == 1:
				rec.a = a; rec.b = b; rec.cell = int(face.cell)
			edge_map[key] = rec
	var vertices: Array[Vector3] = mesh.vertices
	var selected: Dictionary = mesh.selected
	var cavity_edges: Array[Dictionary] = []
	var degree: Dictionary = {}
	var adjacency: Dictionary = {}
	for key in edge_map:
		var rec: Dictionary = edge_map[key]
		if int(rec.count) != 1: continue
		var a := int(rec.a); var b := int(rec.b)
		if _is_selection_boundary(fixture, vertices[a], vertices[b], [int(rec.cell)], selected): continue
		cavity_edges.append(rec)
		degree[a] = int(degree.get(a, 0)) + 1; degree[b] = int(degree.get(b, 0)) + 1
		var aa: Array = adjacency.get(a, []); aa.append(b); adjacency[a] = aa
		var bb: Array = adjacency.get(b, []); bb.append(a); adjacency[b] = bb
	if cavity_edges.is_empty(): return {"valid": false, "reason": "no_internal_cavity_boundary"}
	for id in degree:
		if int(degree[id]) != 2:
			return {"valid": false, "reason": "cavity_boundary_not_disjoint_loops", "degrees": degree}
	var remaining: Dictionary = {}
	for i in range(cavity_edges.size()): remaining[i] = true
	var loops: Array = []
	while not remaining.is_empty():
		var first_edge_index := int(remaining.keys()[0])
		var first_edge: Dictionary = cavity_edges[first_edge_index]
		var loop: Array[int] = [int(first_edge.a)]
		var prior := int(first_edge.a)
		var current := int(first_edge.b)
		var guard := 0
		while current != loop[0] and guard <= cavity_edges.size():
			loop.append(current)
			remaining.erase(first_edge_index if guard == 0 else -1)
			var options: Array = adjacency[current]
			var next := int(options[0]) if int(options[0]) != prior else int(options[1])
			prior = current; current = next; guard += 1
		# Consume every undirected boundary edge for this loop.
		for i in remaining.keys():
			var rec: Dictionary = cavity_edges[int(i)]
			if loop.has(int(rec.a)) and loop.has(int(rec.b)): remaining.erase(i)
		if guard > cavity_edges.size() or loop.size() < 3:
			return {"valid": false, "reason": "cavity_loop_walk_failed"}
		loops.append(loop)
	return {"valid": true, "loops": loops, "edges": cavity_edges, "degrees": degree}


func _surface_metrics(fixture: RefCounted, mesh: Dictionary, changed: Array) -> Dictionary:
	var density_proxy := PackedFloat64Array()
	var gradient_h := 0.01
	var max_nearest_original := 0.0
	for point in changed:
		var density := absf(float(fixture._canonical_sample(point)))
		var gradient := Vector3(
			float(fixture._canonical_sample(point + Vector3.RIGHT * gradient_h)) - float(fixture._canonical_sample(point - Vector3.RIGHT * gradient_h)),
			float(fixture._canonical_sample(point + Vector3.UP * gradient_h)) - float(fixture._canonical_sample(point - Vector3.UP * gradient_h)),
			float(fixture._canonical_sample(point + Vector3.BACK * gradient_h)) - float(fixture._canonical_sample(point - Vector3.BACK * gradient_h))) / (2.0 * gradient_h)
		if gradient.length() > 1.0e-10: density_proxy.append(density / gradient.length())
	return {"changed_point_count": changed.size(), "max_abs_canonical_density_at_changed_points": _max_abs(density_proxy),
		"canonical_zero_set_distance_proxy_world_max": _max_of(density_proxy),
		"note": "abs(SDF)/central-difference gradient magnitude at introduced/moved points; proxy only, not a Hausdorff bound"}


func _normal_change_metrics(mesh: Dictionary) -> Dictionary:
	var angles: PackedFloat64Array = []
	var vertices: Array[Vector3] = mesh.vertices
	var original_vertices: Array[Vector3] = mesh.original_vertices
	for face in mesh.faces:
		if bool(face.get("new_face", false)): continue
		var old_ids: Array = face.get("original_v", [])
		var new_ids: Array = face.v
		if old_ids.size() != 3 or new_ids.size() != 3 or old_ids == new_ids: continue
		var old_cross := (original_vertices[int(old_ids[1])] - original_vertices[int(old_ids[0])]).cross(original_vertices[int(old_ids[2])] - original_vertices[int(old_ids[0])])
		var new_cross := (vertices[int(new_ids[1])] - vertices[int(new_ids[0])]).cross(vertices[int(new_ids[2])] - vertices[int(new_ids[0])])
		if old_cross.length_squared() > 0.0 and new_cross.length_squared() > 0.0:
			angles.append(rad_to_deg(old_cross.normalized().angle_to(new_cross.normalized())))
	return {"changed_face_count": angles.size(), "maximum_triangle_normal_angle_degrees": _max_of(angles),
		"note": "normal-angle deltas for surviving faces whose vertex IDs changed; newly triangulated faces are checked by winding and canonical-gradient diagnostics"}


func _face_component_count(faces: Array[Dictionary]) -> int:
	if faces.is_empty(): return 0
	var edge_owners: Dictionary = {}
	for face_index in range(faces.size()):
		var ids: Array = faces[face_index].v
		for edge_index in range(3):
			var key := _edge_key(int(ids[edge_index]), int(ids[(edge_index + 1) % 3]))
			var owners: Array = edge_owners.get(key, [])
			owners.append(face_index)
			edge_owners[key] = owners
	var adjacency: Array[Array] = []
	adjacency.resize(faces.size())
	for index in range(faces.size()): adjacency[index] = []
	for owners_value in edge_owners.values():
		var owners: Array = owners_value
		if owners.size() < 2: continue
		for left_index in range(owners.size()):
			for right_index in range(left_index + 1, owners.size()):
				var left := int(owners[left_index]); var right := int(owners[right_index])
				adjacency[left].append(right); adjacency[right].append(left)
	var visited: Dictionary = {}
	var components := 0
	for start in range(faces.size()):
		if visited.has(start): continue
		components += 1
		var stack: Array[int] = [start]
		visited[start] = true
		while not stack.is_empty():
			var current: int = int(stack.pop_back())
			for neighbor_value in adjacency[current]:
				var neighbor := int(neighbor_value)
				if visited.has(neighbor): continue
				visited[neighbor] = true
				stack.append(neighbor)
	return components


func edge_orientation_metrics(mesh: Dictionary) -> Dictionary:
	var vertices: Array[Vector3] = mesh.vertices
	var faces: Array[Dictionary] = mesh.faces
	var counts: Dictionary = {}
	var directions: Dictionary = {}
	for face in faces:
		var ids: Array = face.v
		for edge_index in range(3):
			var a := int(ids[edge_index]); var b := int(ids[(edge_index + 1) % 3])
			var key := _edge_key(a, b)
			counts[key] = int(counts.get(key, 0)) + 1
			directions[key] = int(directions.get(key, 0)) + (1 if a < b else -1)
	var open_edges := 0
	var nonmanifold_edges := 0
	var same_winding_edges := 0
	for key in counts:
		var count := int(counts[key])
		if count == 1: open_edges += 1
		elif count > 2: nonmanifold_edges += 1
		elif int(directions[key]) != 0: same_winding_edges += 1
	return {"face_count": faces.size(), "edge_count": counts.size(), "open_edges": open_edges,
		"nonmanifold_edges": nonmanifold_edges, "same_winding_edges": same_winding_edges,
		"note": "edge identities use welded local mesh vertex ids; each two-face edge must have opposite directed incidence"}


func _count_t_junctions(vertices: Array[Vector3], edges: Dictionary) -> int:
	var count := 0
	for key in edges:
		var record: Dictionary = edges[key]
		var a: Vector3 = vertices[int(record.a)]
		var b: Vector3 = vertices[int(record.b)]
		var ab := b - a
		var length2 := ab.length_squared()
		if length2 <= 1.0e-16: continue
		for vertex_index in range(vertices.size()):
			if vertex_index == int(record.a) or vertex_index == int(record.b): continue
			var p := vertices[vertex_index]
			var t := (p - a).dot(ab) / length2
			if t > 1.0e-5 and t < 1.0 - 1.0e-5 and p.distance_squared_to(a + ab * t) <= WELD_EPSILON * WELD_EPSILON:
				count += 1
	return count


func _degenerate_face_count(mesh: Dictionary) -> int:
	var count := 0
	var vertices: Array[Vector3] = mesh.vertices
	for face in mesh.faces:
		var ids: Array = face.v
		var a: Vector3 = vertices[int(ids[0])]
		var b: Vector3 = vertices[int(ids[1])]
		var c: Vector3 = vertices[int(ids[2])]
		if (b - a).cross(c - a).length_squared() <= AREA2_LIMIT_SQUARED: count += 1
	return count


func _is_selection_boundary(fixture: RefCounted, a: Vector3, b: Vector3, owners: Array, selected: Dictionary) -> bool:
	for owner_value in owners:
		var cell: Vector3i = fixture._cell_from_id(int(owner_value))
		var origin: Vector3 = fixture.PATCH_MIN + Vector3(cell) * fixture.COARSE_STEP
		for direction_value in fixture.FACE_DIRECTIONS:
			var direction: Dictionary = direction_value
			var delta: Vector3i = direction.delta
			var neighbor: Vector3i = cell + delta
			if selected.has(fixture._cell_id(neighbor)) and fixture._cell_in_bounds(neighbor): continue
			var axis := 0 if delta.x != 0 else (1 if delta.y != 0 else 2)
			var plane: float = origin[axis] + (fixture.COARSE_STEP if delta[axis] > 0 else 0.0)
			if absf(a[axis] - plane) <= WELD_EPSILON and absf(b[axis] - plane) <= WELD_EPSILON:
				var other_axes: Array[int] = []
				for ax in range(3):
					if ax != axis: other_axes.append(ax)
				if a[other_axes[0]] >= origin[other_axes[0]] - WELD_EPSILON and a[other_axes[0]] <= origin[other_axes[0]] + fixture.COARSE_STEP + WELD_EPSILON \
					and b[other_axes[0]] >= origin[other_axes[0]] - WELD_EPSILON and b[other_axes[0]] <= origin[other_axes[0]] + fixture.COARSE_STEP + WELD_EPSILON \
					and a[other_axes[1]] >= origin[other_axes[1]] - WELD_EPSILON and a[other_axes[1]] <= origin[other_axes[1]] + fixture.COARSE_STEP + WELD_EPSILON \
					and b[other_axes[1]] >= origin[other_axes[1]] - WELD_EPSILON and b[other_axes[1]] <= origin[other_axes[1]] + fixture.COARSE_STEP + WELD_EPSILON:
					return true
	return false


func _vertex_on_selection_boundary(fixture: RefCounted, point: Vector3, selected: Dictionary) -> bool:
	for owner_value in selected:
		var cell: Vector3i = fixture._cell_from_id(int(owner_value))
		var origin: Vector3 = fixture.PATCH_MIN + Vector3(cell) * fixture.COARSE_STEP
		for direction_value in fixture.FACE_DIRECTIONS:
			var direction: Dictionary = direction_value
			var delta: Vector3i = direction.delta
			var neighbor: Vector3i = cell + delta
			if selected.has(fixture._cell_id(neighbor)) and fixture._cell_in_bounds(neighbor): continue
			var axis := 0 if delta.x != 0 else (1 if delta.y != 0 else 2)
			var plane: float = origin[axis] + (fixture.COARSE_STEP if delta[axis] > 0 else 0.0)
			if absf(point[axis] - plane) > WELD_EPSILON: continue
			var inside := true
			for ax in range(3):
				if ax == axis: continue
				inside = inside and point[ax] >= origin[ax] - WELD_EPSILON and point[ax] <= origin[ax] + fixture.COARSE_STEP + WELD_EPSILON
			if inside: return true
	return false


func _weld(point: Vector3, vertices: Array[Vector3], buckets: Dictionary) -> int:
	var bucket := Vector3i(floori(point.x / WELD_EPSILON), floori(point.y / WELD_EPSILON), floori(point.z / WELD_EPSILON))
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var key := bucket + Vector3i(dx, dy, dz)
				for value in buckets.get(key, []):
					var id := int(value)
					if vertices[id].distance_squared_to(point) <= WELD_EPSILON * WELD_EPSILON: return id
	var id := vertices.size()
	vertices.append(point)
	var ids: Array = buckets.get(bucket, []); ids.append(id); buckets[bucket] = ids
	return id


func _copy_mesh(source: Dictionary) -> Dictionary:
	var vertex_copy: Array[Vector3] = []
	for value in source.vertices: vertex_copy.append(value)
	var original_vertex_copy: Array[Vector3] = []
	for value in source.original_vertices: original_vertex_copy.append(value)
	var face_copy: Array[Dictionary] = []
	for value in source.faces: face_copy.append(value.duplicate(true))
	return {"vertices": vertex_copy, "original_vertices": original_vertex_copy,
		"faces": face_copy, "selected": source.selected.duplicate()}


func _edge_key(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]


func _edge_coord_key(a: Vector3, b: Vector3) -> String:
	var first := "%d,%d,%d" % [roundi(a.x * 100000.0), roundi(a.y * 100000.0), roundi(a.z * 100000.0)]
	var second := "%d,%d,%d" % [roundi(b.x * 100000.0), roundi(b.y * 100000.0), roundi(b.z * 100000.0)]
	return first + "|" + second if first < second else second + "|" + first


func _max_abs(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values: result = maxf(result, absf(value))
	return result


func _max_of(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values: result = maxf(result, value)
	return result


func _v3(point: Vector3) -> Array[float]:
	return [point.x, point.y, point.z]
