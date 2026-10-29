extends RefCounted

## Independent experimental extractor for Candidate D. It reads only the
## supplied reloaded float32 lattice, uses a separately enumerated tetrahedral
## decomposition, canonical node-edge identity, and polygon-angle ordering.
const CORNERS: Array[Vector3i] = [Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(1,1,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(1,1,1),Vector3i(0,1,1)]
const TETRAHEDRA: Array[Array] = [[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]]
const TETRA_EDGES: Array[Vector2i] = [Vector2i(0,1),Vector2i(0,2),Vector2i(0,3),Vector2i(1,2),Vector2i(1,3),Vector2i(2,3)]
const DEGENERACY_CROSS_SQUARED: float = 1.0e-12
const MAX_TRIANGLES: int = 20000
const MAX_USEC: int = 60000000

func extract(values: PackedFloat32Array, dims: Vector3i, cells: Vector3i, origin: Vector3, step: float) -> Dictionary:
	var total: int = dims.x * dims.y * dims.z
	if dims != cells + Vector3i.ONE or values.size() != total or not origin.is_finite() or not is_finite(step) or step <= 0.0:
		return {"valid": false, "reason": "reference_volume_dimensions_invalid"}
	if total > 10000:
		return {"valid": false, "reason": "reference_node_stop_loss", "nodes": total}
	for value in values:
		if not is_finite(value): return {"valid": false, "reason": "reference_nonfinite_density"}
	var started: int = Time.get_ticks_usec()
	var root_cache: Dictionary = {}
	var mesh: Dictionary = {"positions": PackedVector3Array(), "normals": PackedVector3Array()}
	var active_tets: int = 0
	var dropped: int = 0
	for y in range(cells.y):
		for z in range(cells.z):
			for x in range(cells.x):
				var node_points: Array[Vector3] = []
				var node_values: Array[float] = []
				for corner in CORNERS:
					var node: Vector3i = Vector3i(x,y,z) + corner
					node_points.append(origin + Vector3(node) * step)
					node_values.append(float(values[_index(node,dims)]))
				var positive_centroid: Vector3 = Vector3.ZERO
				var negative_centroid: Vector3 = Vector3.ZERO
				var positive_count: int = 0
				var negative_count: int = 0
				for i in range(8):
					if node_values[i] >= 0.0:
						positive_centroid += node_points[i]; positive_count += 1
					else:
						negative_centroid += node_points[i]; negative_count += 1
				if positive_count == 0 or negative_count == 0: continue
				var toward_empty: Vector3 = negative_centroid / float(negative_count) - positive_centroid / float(positive_count)
				for tet in TETRAHEDRA:
					var polygon: Array[Vector3] = []
					var seen_edges: Dictionary = {}
					var seen_points: Dictionary = {}
					for local_edge in TETRA_EDGES:
						var ia: int = int(tet[local_edge.x]); var ib: int = int(tet[local_edge.y])
						var da: float = node_values[ia]; var db: float = node_values[ib]
						if (da >= 0.0) == (db >= 0.0): continue
						var na: Vector3i = Vector3i(x,y,z) + CORNERS[ia]
						var nb: Vector3i = Vector3i(x,y,z) + CORNERS[ib]
						var root: Dictionary = _root_for_lattice_edge(root_cache, na, nb, da, db, node_points[ia], node_points[ib])
						if not root.get("valid", false): return {"valid": false, "reason": "reference_edge_root_invalid"}
						var edge_key: String = String(root.key)
						if not seen_edges.has(edge_key):
							seen_edges[edge_key] = true
							var point_key: Vector3 = root.point
							if not seen_points.has(point_key): seen_points[point_key] = true; polygon.append(root.point)
					if polygon.size() < 3: continue
					active_tets += 1
					var tet_toward_empty: Vector3 = _tetra_toward_empty(node_points, node_values, tet)
					if tet_toward_empty.length_squared() < 1.0e-16 or not tet_toward_empty.is_finite():
						return {"valid": false, "reason": "reference_tetra_gradient_invalid", "cell": [x,y,z]}
					var ordered: Array[Vector3] = _order_polygon(polygon, tet_toward_empty)
					if ordered.size() < 3: return {"valid": false, "reason": "reference_polygon_order_failed"}
					for fan in range(1, ordered.size() - 1):
						if not _append_triangle(mesh, ordered[0], ordered[fan], ordered[fan+1], tet_toward_empty): dropped += 1
					if mesh.positions.size() / 3 > MAX_TRIANGLES:
						return {"valid": false, "reason": "reference_triangle_stop_loss", "triangles": mesh.positions.size() / 3}
					if Time.get_ticks_usec() - started > MAX_USEC:
						return {"valid": false, "reason": "reference_time_stop_loss"}
	return {"valid": true, "mesh": mesh, "mesh_sha256": _mesh_sha(mesh),
		"metrics": {"triangles": mesh.positions.size() / 3, "active_tetrahedra": active_tets,
			"degeneracy_drops": dropped, "unique_lattice_roots": root_cache.size(),
			"extract_usec": Time.get_ticks_usec() - started, "source": "independent angle-ordered tetrahedral extractor over exact reloaded float32 volume"}}

func _root_for_lattice_edge(cache: Dictionary, a: Vector3i, b: Vector3i, da: float, db: float, pa: Vector3, pb: Vector3) -> Dictionary:
	if _node_key(a) > _node_key(b):
		var node_swap: Vector3i = a; a = b; b = node_swap
		var value_swap: float = da; da = db; db = value_swap
		var point_swap: Vector3 = pa; pa = pb; pb = point_swap
	var key: String = "%s|%s" % [_node_key(a), _node_key(b)]
	if cache.has(key): return {"valid": true, "key": key, "point": cache[key]}
	var denominator: float = da - db
	if denominator == 0.0 or not is_finite(denominator): return {"valid": false}
	var t: float = clampf(da / denominator, 0.0, 1.0)
	var point: Vector3 = pa.lerp(pb,t)
	if not point.is_finite(): return {"valid": false}
	var canonical_key: String = key
	if da == 0.0: canonical_key = "node|" + _node_key(a)
	elif db == 0.0: canonical_key = "node|" + _node_key(b)
	if cache.has(canonical_key): point = cache[canonical_key]
	else: cache[canonical_key] = point
	return {"valid": true, "key": canonical_key, "point": point}

func _order_polygon(points: Array[Vector3], toward_empty: Vector3) -> Array[Vector3]:
	var center: Vector3 = Vector3.ZERO
	for point in points: center += point
	center /= float(points.size())
	var normal: Vector3 = toward_empty.normalized()
	if normal.length_squared() < 0.5: return []
	var tangent: Vector3 = (points[0] - center).normalized()
	if tangent.length_squared() < 0.5: return []
	var bitangent: Vector3 = normal.cross(tangent).normalized()
	if bitangent.length_squared() < 0.5: return []
	var records: Array[Dictionary] = []
	for point in points:
		var delta: Vector3 = point - center
		records.append({"angle": atan2(delta.dot(bitangent), delta.dot(tangent)), "point": point})
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return float(left.angle) < float(right.angle))
	var ordered: Array[Vector3] = []
	for record in records: ordered.append(record.point)
	return ordered

func _tetra_toward_empty(points: Array[Vector3], values: Array[float], tet: Array) -> Vector3:
	var p0: Vector3 = points[int(tet[0])]
	var e1: Vector3 = points[int(tet[1])] - p0
	var e2: Vector3 = points[int(tet[2])] - p0
	var e3: Vector3 = points[int(tet[3])] - p0
	var d1: float = values[int(tet[1])] - values[int(tet[0])]
	var d2: float = values[int(tet[2])] - values[int(tet[0])]
	var d3: float = values[int(tet[3])] - values[int(tet[0])]
	var determinant: float = e1.dot(e2.cross(e3))
	if not is_finite(determinant) or absf(determinant) < 1.0e-12: return Vector3.ZERO
	var gradient: Vector3 = (d1 * e2.cross(e3) + d2 * e3.cross(e1) + d3 * e1.cross(e2)) / determinant
	return -gradient

func _append_triangle(mesh: Dictionary, a: Vector3, b: Vector3, c: Vector3, toward_empty: Vector3) -> bool:
	var cross: Vector3 = (b-a).cross(c-a)
	if not cross.is_finite() or cross.length_squared() <= DEGENERACY_CROSS_SQUARED: return false
	if cross.dot(toward_empty) < 0.0:
		var swap: Vector3 = b; b = c; c = swap
		cross = (b-a).cross(c-a)
	var normal: Vector3 = cross.normalized()
	for point in [a,b,c]:
		mesh.positions.append(point)
		mesh.normals.append(normal)
	return true

func _index(node: Vector3i, dims: Vector3i) -> int:
	return (node.y * dims.z + node.z) * dims.x + node.x

func _node_key(node: Vector3i) -> String:
	return "%d,%d,%d" % [node.x,node.y,node.z]

func _mesh_sha(mesh: Dictionary) -> String:
	var position_bytes: PackedByteArray = mesh.positions.to_byte_array()
	var normal_bytes: PackedByteArray = mesh.normals.to_byte_array()
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK: return "HASH_START_FAILED"
	context.update(("%d:%d:" % [position_bytes.size(),normal_bytes.size()]).to_utf8_buffer())
	if not position_bytes.is_empty(): context.update(position_bytes)
	if not normal_bytes.is_empty(): context.update(normal_bytes)
	return context.finish().hex_encode()
