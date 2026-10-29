extends RefCounted
const EDGE_KEY_SEPARATOR: String = "\u001f"

## Test-only topology ledger for R9.6. It records required surface connectivity
## before a geometric quality test can omit a triangle. It is evidence tooling;
## it does not create or repair a production mesh.

var _roots: Dictionary = {}
var _triangles: Dictionary = {}

func add_root(root_id: String, point: Vector3, owner_id: String) -> Dictionary:
	if root_id.is_empty() or root_id.contains(EDGE_KEY_SEPARATOR) or owner_id.is_empty() or not point.is_finite():
		return {"valid": false, "reason": "root_identity_owner_or_point_invalid"}
	if _roots.has(root_id):
		var old: Dictionary = _roots[root_id]
		if old.point != point or String(old.owner_id) != owner_id:
			return {"valid": false, "reason": "root_identity_collision", "root_id": root_id}
		return {"valid": true, "duplicate": true}
	_roots[root_id] = {"point": point, "owner_id": owner_id}
	return {"valid": true, "duplicate": false}

func add_triangle(triangle_id: String, root_ids: Array[String], owner_id: String,
		cell_id: String, face_ids: Array[String]) -> Dictionary:
	if triangle_id.is_empty() or owner_id.is_empty() or cell_id.is_empty():
		return {"valid": false, "reason": "triangle_metadata_invalid"}
	if root_ids.size() != 3:
		return {"valid": false, "reason": "triangle_root_count_invalid"}
	if _triangles.has(triangle_id):
		return {"valid": false, "reason": "duplicate_triangle_id", "triangle_id": triangle_id}
	for root_id in root_ids:
		if not _roots.has(root_id):
			return {"valid": false, "reason": "triangle_references_unknown_root", "root_id": root_id}
	var sorted_faces: Array[String] = face_ids.duplicate()
	sorted_faces.sort()
	_triangles[triangle_id] = {
		"root_ids": root_ids.duplicate(),
		"owner_id": owner_id,
		"cell_id": cell_id,
		"face_ids": sorted_faces,
		"realization": "PENDING",
		"cross_squared": 0.0,
		"rejection_reason": ""
	}
	return {"valid": true}

func mark_realization(triangle_id: String, emitted: bool, cross_squared: float,
		rejection_reason: String = "") -> Dictionary:
	if not _triangles.has(triangle_id):
		return {"valid": false, "reason": "triangle_not_recorded"}
	if not is_finite(cross_squared) or cross_squared < 0.0:
		return {"valid": false, "reason": "triangle_measure_nonfinite_or_negative"}
	var triangle: Dictionary = _triangles[triangle_id]
	triangle.realization = "EMITTED" if emitted else "REJECTED"
	triangle.cross_squared = cross_squared
	triangle.rejection_reason = "" if emitted else rejection_reason
	_triangles[triangle_id] = triangle
	return {"valid": true}

func report(roi_min: Vector3, roi_max: Vector3) -> Dictionary:
	if not roi_min.is_finite() or not roi_max.is_finite() or roi_min.x >= roi_max.x or roi_min.y >= roi_max.y or roi_min.z >= roi_max.z:
		return {"valid": false, "reason": "roi_bounds_invalid"}
	var root_rows: Array = []
	var root_keys: Array = _roots.keys()
	root_keys.sort()
	for raw_id in root_keys:
		var root_id: String = String(raw_id)
		var root: Dictionary = _roots[root_id]
		var point: Vector3 = root.point
		root_rows.append([root_id, point.x, point.y, point.z, root.owner_id])
	var triangle_rows: Array = []
	var triangle_keys: Array = _triangles.keys()
	triangle_keys.sort()
	var required_incidence: Dictionary = {}
	var emitted_incidence: Dictionary = {}
	var edge_triangles: Dictionary = {}
	var emitted_edge_triangles: Dictionary = {}
	var rejected_triangles: Array[String] = []
	var pending_triangles: Array[String] = []
	var rejection_reasons: Dictionary = {}
	for raw_triangle_id in triangle_keys:
		var triangle_id: String = String(raw_triangle_id)
		var triangle: Dictionary = _triangles[triangle_id]
		var roots: Array = triangle.root_ids
		triangle_rows.append([triangle_id, roots[0], roots[1], roots[2], triangle.owner_id,
			triangle.cell_id, triangle.face_ids, triangle.realization, triangle.cross_squared,
			triangle.rejection_reason])
		if triangle.realization == "REJECTED":
			rejected_triangles.append(triangle_id)
			rejection_reasons[String(triangle.rejection_reason)] = int(rejection_reasons.get(String(triangle.rejection_reason), 0)) + 1
		elif triangle.realization == "PENDING":
			pending_triangles.append(triangle_id)
		for edge_index in range(3):
			var a: String = String(roots[edge_index])
			var b: String = String(roots[(edge_index + 1) % 3])
			var edge_key: String = _edge_key(a, b)
			required_incidence[edge_key] = int(required_incidence.get(edge_key, 0)) + 1
			if not edge_triangles.has(edge_key):
				edge_triangles[edge_key] = []
			edge_triangles[edge_key].append(triangle_id)
			if triangle.realization == "EMITTED":
				emitted_incidence[edge_key] = int(emitted_incidence.get(edge_key, 0)) + 1
				if not emitted_edge_triangles.has(edge_key):
					emitted_edge_triangles[edge_key] = []
				emitted_edge_triangles[edge_key].append(triangle_id)
	var missing_adjacency: Array = []
	var internal_open_edges: Array = []
	var boundary_open_edges: Array = []
	var nonmanifold_edges: Array = []
	for edge_key in required_incidence:
		var expected_count: int = int(required_incidence[edge_key])
		var actual_count: int = int(emitted_incidence.get(edge_key, 0))
		if actual_count != expected_count:
			missing_adjacency.append({"edge": edge_key, "required_incidence": expected_count, "emitted_incidence": actual_count})
		if actual_count > 2:
			nonmanifold_edges.append({"edge": edge_key, "incidence": actual_count})
		elif actual_count == 1:
			if _edge_on_roi_boundary(edge_key, roi_min, roi_max):
				boundary_open_edges.append(edge_key)
			else:
				internal_open_edges.append(edge_key)
	var arcs: Array = []
	for edge_key in required_incidence:
		var endpoints: Array = edge_key.split(EDGE_KEY_SEPARATOR)
		var p0: Vector3 = _roots[String(endpoints[0])].point
		var p1: Vector3 = _roots[String(endpoints[1])].point
		var incident_owners: Array[String] = []
		for incident_id in edge_triangles[edge_key]:
			var incident: Dictionary = _triangles[String(incident_id)]
			var incident_owner: String = String(incident.owner_id)
			if not incident_owners.has(incident_owner):
				incident_owners.append(incident_owner)
		incident_owners.sort()
		arcs.append({"edge": edge_key, "required_incidence": required_incidence[edge_key],
			"incident_triangles": edge_triangles[edge_key],
			"shared_face_key": _shared_face_owner(p0, p1, roi_min, roi_max),
			"canonical_owner": incident_owners[0] if not incident_owners.is_empty() else ""})
	var components: Array = _surface_components(triangle_keys, edge_triangles)
	var loops: Array = _open_edge_components(emitted_incidence, emitted_edge_triangles, roi_min, roi_max)
	var canonical: String = JSON.stringify({"roots": root_rows, "triangles": triangle_rows})
	return {
		"valid": pending_triangles.is_empty(),
		"geometry_realization_complete": rejected_triangles.is_empty() and missing_adjacency.is_empty() and internal_open_edges.is_empty() and nonmanifold_edges.is_empty(),
		"reason": "unresolved_triangle_realization" if not pending_triangles.is_empty() else "",
		"root_count": _roots.size(),
		"required_triangle_count": _triangles.size(),
		"emitted_triangle_count": _count_realized("EMITTED"),
		"rejected_triangle_count": rejected_triangles.size(),
		"rejected_triangle_ids": rejected_triangles,
		"pending_triangle_ids": pending_triangles,
		"rejection_reasons": rejection_reasons,
		"required_surface_arcs": arcs,
		"surface_components": components,
		"surface_loops": loops,
		"missing_required_adjacency": missing_adjacency,
		"internal_open_edges": internal_open_edges,
		"roi_boundary_open_edges": boundary_open_edges,
		"nonmanifold_edges": nonmanifold_edges,
		"topology_sha256": _sha256(canonical.to_utf8_buffer())
	}

func _count_realized(state: String) -> int:
	var count: int = 0
	for triangle in _triangles.values():
		if String(triangle.realization) == state:
			count += 1
	return count

func _surface_components(triangle_keys: Array, edge_triangles: Dictionary) -> Array:
	var adjacency: Dictionary = {}
	for raw_id in triangle_keys:
		adjacency[String(raw_id)] = []
	for incident_ids in edge_triangles.values():
		for i in range(incident_ids.size()):
			for j in range(i + 1, incident_ids.size()):
				var a: String = String(incident_ids[i])
				var b: String = String(incident_ids[j])
				if not adjacency[a].has(b):
					adjacency[a].append(b)
				if not adjacency[b].has(a):
					adjacency[b].append(a)
	var visited: Dictionary = {}
	var components: Array = []
	var ordered_ids: Array = triangle_keys.duplicate()
	ordered_ids.sort()
	for raw_start in ordered_ids:
		var start: String = String(raw_start)
		if visited.has(start):
			continue
		var queue: Array[String] = [start]
		visited[start] = true
		var members: Array[String] = []
		while not queue.is_empty():
			var current: String = queue.pop_front()
			members.append(current)
			var neighbors: Array = adjacency[current]
			neighbors.sort()
			for neighbor_value in neighbors:
				var neighbor: String = String(neighbor_value)
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		members.sort()
		components.append(members)
	return components

func _open_edge_components(emitted_incidence: Dictionary, emitted_edge_triangles: Dictionary,
		roi_min: Vector3, roi_max: Vector3) -> Array:
	var adjacency: Dictionary = {}
	var edge_records: Dictionary = {}
	for raw_edge in emitted_incidence:
		var edge_key: String = String(raw_edge)
		if int(emitted_incidence[edge_key]) != 1:
			continue
		var endpoints: Array = edge_key.split(EDGE_KEY_SEPARATOR)
		var a: String = String(endpoints[0])
		var b: String = String(endpoints[1])
		if not adjacency.has(a): adjacency[a] = []
		if not adjacency.has(b): adjacency[b] = []
		adjacency[a].append(b)
		adjacency[b].append(a)
		edge_records[edge_key] = {"edge": edge_key,
			"triangle": emitted_edge_triangles[edge_key][0],
			"roi_boundary": _edge_on_roi_boundary(edge_key, roi_min, roi_max)}
	var visited_vertices: Dictionary = {}
	var result: Array = []
	var vertices: Array = adjacency.keys()
	vertices.sort()
	for raw_start in vertices:
		var start: String = String(raw_start)
		if visited_vertices.has(start):
			continue
		var queue: Array[String] = [start]
		visited_vertices[start] = true
		var component_vertices: Array[String] = []
		var component_edges: Dictionary = {}
		var all_degree_two: bool = true
		var touches_roi_boundary: bool = false
		while not queue.is_empty():
			var current: String = queue.pop_front()
			component_vertices.append(current)
			if adjacency[current].size() != 2:
				all_degree_two = false
			for neighbor_value in adjacency[current]:
				var neighbor: String = String(neighbor_value)
				var edge_key: String = _edge_key(current, neighbor)
				component_edges[edge_key] = true
				if not visited_vertices.has(neighbor):
					visited_vertices[neighbor] = true
					queue.append(neighbor)
		for edge_key in component_edges:
			if bool(edge_records[edge_key].roi_boundary):
				touches_roi_boundary = true
		var sorted_edges: Array = component_edges.keys()
		var sorted_vertices: Array = component_vertices.duplicate()
		sorted_edges.sort()
		sorted_vertices.sort()
		result.append({"edge_keys": sorted_edges, "root_ids": sorted_vertices,
			"closed_loop": all_degree_two and not touches_roi_boundary,
			"touches_roi_boundary": touches_roi_boundary})
	return result

func _edge_on_roi_boundary(edge_key: String, roi_min: Vector3, roi_max: Vector3) -> bool:
	var endpoints: Array = edge_key.split(EDGE_KEY_SEPARATOR)
	var a: Vector3 = _roots[String(endpoints[0])].point
	var b: Vector3 = _roots[String(endpoints[1])].point
	for axis in range(3):
		if is_equal_approx(a[axis], b[axis]):
			if is_equal_approx(a[axis], roi_min[axis]) or is_equal_approx(a[axis], roi_max[axis]):
				return true
	return false

func _shared_face_owner(a: Vector3, b: Vector3, roi_min: Vector3, roi_max: Vector3) -> String:
	for axis in range(3):
		if is_equal_approx(a[axis], b[axis]):
			if is_equal_approx(a[axis], roi_min[axis]):
				return "ROI_MIN_AXIS_%d" % axis
			if is_equal_approx(a[axis], roi_max[axis]):
				return "ROI_MAX_AXIS_%d" % axis
	return "INTERIOR"

func _edge_key(a: String, b: String) -> String:
	return a + EDGE_KEY_SEPARATOR + b if a < b else b + EDGE_KEY_SEPARATOR + a

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "HASH_START_FAILED"
	context.update(bytes)
	return context.finish().hex_encode()
