extends RefCounted

## Test-only topology ledger for R9.6. It records required surface connectivity
## before a geometric quality test can omit a triangle. It is evidence tooling;
## it does not create or repair a production mesh.

var _roots: Dictionary = {}
var _triangles: Dictionary = {}

func add_root(root_id: String, point: Vector3, owner_id: String) -> Dictionary:
	if root_id.is_empty() or owner_id.is_empty() or not point.is_finite():
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
	if root_ids.size() != 3 or root_ids[0] == root_ids[1] or root_ids[1] == root_ids[2] or root_ids[2] == root_ids[0]:
		return {"valid": false, "reason": "triangle_root_count_or_identity_invalid"}
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
			if triangle.realization == "EMITTED":
				emitted_incidence[edge_key] = int(emitted_incidence.get(edge_key, 0)) + 1
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
		var endpoints: Array = edge_key.split("|")
		var p0: Vector3 = _roots[String(endpoints[0])].point
		var p1: Vector3 = _roots[String(endpoints[1])].point
		arcs.append({"edge": edge_key, "required_incidence": required_incidence[edge_key],
			"face_owner": _shared_face_owner(p0, p1, roi_min, roi_max)})
	var canonical: String = JSON.stringify({"roots": root_rows, "triangles": triangle_rows})
	return {
		"valid": pending_triangles.is_empty(),
		"reason": "unresolved_triangle_realization" if not pending_triangles.is_empty() else "",
		"root_count": _roots.size(),
		"required_triangle_count": _triangles.size(),
		"emitted_triangle_count": _count_realized("EMITTED"),
		"rejected_triangle_count": rejected_triangles.size(),
		"rejected_triangle_ids": rejected_triangles,
		"pending_triangle_ids": pending_triangles,
		"rejection_reasons": rejection_reasons,
		"required_surface_arcs": arcs,
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

func _edge_on_roi_boundary(edge_key: String, roi_min: Vector3, roi_max: Vector3) -> bool:
	var endpoints: Array = edge_key.split("|")
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
	return a + "|" + b if a < b else b + "|" + a

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "HASH_START_FAILED"
	context.update(bytes)
	return context.finish().hex_encode()
