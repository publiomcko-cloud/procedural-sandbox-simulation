extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Realizer := preload("res://tests/prototypes/p3_1_r12_c_c6_multiface_realizer.gd")
const EXPECTED_MANIFEST_SHA := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const EXPECTED_CANDIDATE_SHA := "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"
const EXPECTED_AUTHORITY_SHA := "feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216"
const EXPECTED_C6_CAMPAIGN_SHA := "9a695705c47ad6473b773bbfaeaf35d88306cee6804113a0b1a71c6faca2f348"
const EXPECTED_C6_REALIZER_SHA := "31947e1944a017442ad14cc4f098e67db800d4f5e196d07e047b93dc0fe9d2ac"
const EXPECTED_C6_SOURCE_SHA := "4535f4c965db67adab7c93e448492c54be916c92"
const EXPECTED_FIXTURE_SHA := "33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d"
const EXPECTED_GRAPH_SHA := "a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9"
const EXPECTED_TOPOLOGY_SHA := "4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95"
const EXPECTED_VOLUME_SHA := "ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2"
const EXPECTED_PAYLOAD_SHA := "2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0"
const EXPECTED_C6_ARTIFACT_SHA := "0c6ae06d368f1a789ddc16fae429700c109d09fc019082fe6356c58fee12c6de"
const TARGET_ID := "R9.2.SEAM.XPLUS_EQUAL.v1"
const CUTOFF_SQUARED := 1.0e-12

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var c6_path: String = OS.get_environment("R12CX_C6_ARTIFACT_PATH")
	var candidate_domain_path: String = OS.get_environment("R12CX_CANDIDATE_DOMAIN_PATH")
	var fixture_path: String = OS.get_environment("R12CX_TOPOLOGY_FIXTURE_PATH")
	var output_path: String = OS.get_environment("R12CX_RESIDUAL_FIXTURE_PATH")
	if c6_path.is_empty() or candidate_domain_path.is_empty() or fixture_path.is_empty() or output_path.is_empty():
		_exit_failure("fixture_builder_paths_missing")
		return
	if FileAccess.file_exists(output_path):
		_exit_failure("fixture_output_overwrite_refused")
		return
	var c6_bytes: PackedByteArray = FileAccess.get_file_as_bytes(c6_path)
	var domain_bytes: PackedByteArray = FileAccess.get_file_as_bytes(candidate_domain_path)
	var topology_bytes: PackedByteArray = FileAccess.get_file_as_bytes(fixture_path)
	if c6_bytes.is_empty() or domain_bytes.is_empty() or topology_bytes.is_empty():
		_exit_failure("fixture_input_unreadable")
		return
	var c6_sha: String = Core.sha256(c6_bytes)
	if c6_sha != EXPECTED_C6_ARTIFACT_SHA:
		_exit_failure("c6_artifact_sha_mismatch", {"observed": c6_sha})
		return
	if Core.sha256(domain_bytes) != "30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22":
		_exit_failure("candidate_domain_sha_mismatch")
		return
	if Core.sha256(topology_bytes) != EXPECTED_FIXTURE_SHA:
		_exit_failure("topology_fixture_sha_mismatch")
		return
	var c6_variant: Variant = JSON.parse_string(c6_bytes.get_string_from_utf8())
	var topology_variant: Variant = JSON.parse_string(topology_bytes.get_string_from_utf8())
	if not c6_variant is Dictionary or not topology_variant is Dictionary:
		_exit_failure("fixture_input_json_invalid")
		return
	var c6: Dictionary = c6_variant
	var topology_fixture: Dictionary = topology_variant
	if String(c6.get("source_sha", "")) != EXPECTED_C6_SOURCE_SHA or String(c6.get("hypothesis", "")) != "C6_MULTI_FACE_NONCOPLANAR_PATCH":
		_exit_failure("c6_source_identity_mismatch")
		return
	if String(topology_fixture.get("source_topology_sha256", "")) != EXPECTED_TOPOLOGY_SHA:
		_exit_failure("topology_identity_mismatch")
		return
	var manifest: Dictionary = Core.load_manifest()
	if not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != EXPECTED_MANIFEST_SHA:
		_exit_failure("manifest_invalid", {"reason": manifest.get("reason", "")})
		return
	var candidate_source_sha: String = Core.sha256(FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd"))
	var authority_source_sha: String = Core.sha256(FileAccess.get_file_as_bytes("res://tests/prototypes/p3_1_r10_a_topology_authority.gd"))
	if candidate_source_sha != EXPECTED_CANDIDATE_SHA or authority_source_sha != EXPECTED_AUTHORITY_SHA:
		_exit_failure("pinned_materialization_source_mismatch", {"candidate_d_sha256": candidate_source_sha, "candidate_expected": EXPECTED_CANDIDATE_SHA, "candidate_match": candidate_source_sha == EXPECTED_CANDIDATE_SHA, "authority_sha256": authority_source_sha, "authority_expected": EXPECTED_AUTHORITY_SHA, "authority_match": authority_source_sha == EXPECTED_AUTHORITY_SHA})
		return
	var row: Dictionary = Core.case_by_id(manifest.get("rows", []), TARGET_ID)
	if row.is_empty():
		_exit_failure("frozen_target_missing")
		return
	var snapshot_result: Dictionary = Core.make_snapshot(row)
	if not bool(snapshot_result.get("valid", false)):
		_exit_failure("snapshot_invalid", {"reason": snapshot_result.get("reason", "")})
		return
	var roi: Dictionary = row.get("roi", {})
	var candidate: RefCounted = CandidateD.new()
	candidate.call("configure_roi", roi)
	var volume: Dictionary = candidate.call("_materialize", snapshot_result.get("snapshot", {}), int(snapshot_result.get("revision", -1)))
	if not bool(volume.get("valid", false)):
		_exit_failure("canonical_volume_rebuild_failed", {"reason": volume.get("reason", "")})
		return
	var materialized_values: PackedFloat32Array = volume.get("values", PackedFloat32Array())
	if String(volume.get("sha256", "")) != EXPECTED_VOLUME_SHA or Core.sha256(materialized_values.to_byte_array()) != EXPECTED_PAYLOAD_SHA:
		_exit_failure("canonical_volume_identity_mismatch", {"volume_sha256": volume.get("sha256", ""), "payload_sha256": Core.sha256(materialized_values.to_byte_array())})
		return
	var graph: Dictionary = topology_fixture.get("topology_authority", {})
	var realizer: RefCounted = Realizer.new()
	var identity: Dictionary = realizer.call("validate_topology_identity", graph, EXPECTED_GRAPH_SHA)
	if not bool(identity.get("valid", false)):
		_exit_failure("topology_graph_identity_invalid", identity)
		return
	var geometry: Dictionary = realizer.call("realize", graph, materialized_values, roi, EXPECTED_TOPOLOGY_SHA, EXPECTED_GRAPH_SHA)
	if not bool(geometry.get("valid", false)):
		_exit_failure("c6_geometry_rebuild_failed", {"reason": geometry.get("reason", "")})
		return
	var original_geometry: Dictionary = c6.get("geometry", {})
	if String(geometry.get("mesh_sha256", "")) != String(original_geometry.get("mesh_sha256", "")) or int(geometry.get("geometry_triangle_count", -1)) != int(original_geometry.get("triangle_count", -2)):
		_exit_failure("c6_geometry_reproduction_mismatch", {"mesh_sha256": geometry.get("mesh_sha256", ""), "expected_mesh_sha256": original_geometry.get("mesh_sha256", ""), "triangle_count": geometry.get("geometry_triangle_count", -1)})
		return
	var residuals: Array = c6.get("geometry", {}).get("cutoff_rejections", [])
	if residuals.size() != 3 or geometry.get("cutoff_rejections", []).size() != 3:
		_exit_failure("residual_cutoff_count_unexpected", {"artifact": residuals.size(), "reproduced": geometry.get("cutoff_rejections", []).size()})
		return
	var fixture: Dictionary = _build_residual_fixture(c6, topology_fixture, geometry, materialized_values, roi, snapshot_result.get("snapshot", {}), residuals)
	if not bool(fixture.get("valid", false)):
		_exit_failure("residual_fixture_build_failed", fixture)
		return
	var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		_exit_failure("fixture_output_open_failed")
		return
	var output_bytes: PackedByteArray = JSON.stringify(fixture, "\t", false).to_utf8_buffer()
	output.store_buffer(output_bytes)
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK:
		_exit_failure("fixture_output_write_failed", {"error": write_error})
		return
	print("R12CX_FIXTURE_COMPLETE " + JSON.stringify({"status": "PASS", "path": output_path, "sha256": Core.sha256(output_bytes), "residual_count": residuals.size(), "c6_mesh_sha256": geometry.get("mesh_sha256", ""), "topology_reproduced": true, "volume_sha256": volume.get("sha256", "")}))
	quit(0)

func _build_residual_fixture(c6: Dictionary, topology_fixture: Dictionary, geometry: Dictionary, values: PackedFloat32Array, roi: Dictionary, snapshot: Dictionary, residual_rows: Array) -> Dictionary:
	var roots_by_id: Dictionary = {}
	for root_value in geometry.get("root_map", []):
		var root: Dictionary = root_value
		roots_by_id[String(root.get("root_id", ""))] = root
	var faces_by_id: Dictionary = {}
	for face_value in geometry.get("face_map", []):
		var face: Dictionary = face_value
		faces_by_id[String(face.get("polygon_id", ""))] = face
	var triangles: Array[Dictionary] = []
	var ids_by_polygon: Dictionary = {}
	for emitted_value in geometry.get("emitted_triangles", []):
		var emitted: Dictionary = emitted_value
		var polygon_id: String = String(emitted.get("polygon_id", ""))
		var root_ids: Array = emitted.get("root_ids", [])
		if root_ids.size() != 3:
			return {"valid": false, "reason": "emitted_triangle_root_arity_invalid", "polygon_id": polygon_id}
		var points: Array = []
		for root_value in root_ids:
			var root_id: String = String(root_value)
			if not roots_by_id.has(root_id):
				return {"valid": false, "reason": "emitted_triangle_root_missing", "root_id": root_id}
			points.append(_to_vec3(roots_by_id[root_id].get("position", Vector3.ZERO)))
		var face: Dictionary = faces_by_id.get(polygon_id, {})
		var ordinal: int = int(ids_by_polygon.get(polygon_id, 0))
		var geom_ids: Array = face.get("geometry_triangle_ids", [])
		var triangle_id: String = String(geom_ids[ordinal]) if ordinal < geom_ids.size() else ""
		ids_by_polygon[polygon_id] = ordinal + 1
		if triangle_id.is_empty():
			triangle_id = "meshtri|" + _root_triplet_key(root_ids)
		triangles.append(_triangle_record(triangle_id, polygon_id, root_ids, points, String(emitted.get("construction", "")), false))
	for residual_value in residual_rows:
		var residual: Dictionary = residual_value
		var root_ids: Array = residual.get("root_ids", [])
		if root_ids.size() != 3:
			return {"valid": false, "reason": "residual_root_arity_invalid"}
		var points: Array = []
		for root_value in root_ids:
			var root_id: String = String(root_value)
			if not roots_by_id.has(root_id):
				return {"valid": false, "reason": "residual_root_missing", "root_id": root_id}
			points.append(_to_vec3(roots_by_id[root_id].get("position", Vector3.ZERO)))
		var triangle_id: String = String(residual.get("triangle_id", ""))
		var polygon_id: String = triangle_id.get_slice("|c4-source:", 0)
		triangles.append(_triangle_record(triangle_id, polygon_id, root_ids, points, "C6_REJECTED_CUTOFF", true))
	var adjacency: Dictionary = _triangle_adjacency(triangles)
	var cell_dims: Vector3i = Core.cell_counts(roi) + Vector3i.ONE
	var origin_world: Vector3 = Core.world_min(roi)
	var step: float = Core.step(roi)
	var global_origin: Vector3i = Vector3i(roundi(origin_world.x / step), roundi(origin_world.y / step), roundi(origin_world.z / step))
	var residual_fixture_rows: Array[Dictionary] = []
	for residual_value in residual_rows:
		var residual: Dictionary = residual_value
		var tri_id: String = String(residual.get("triangle_id", ""))
		var triangle: Dictionary = _triangle_by_id(triangles, tri_id)
		if triangle.is_empty():
			return {"valid": false, "reason": "residual_triangle_not_reconstructed", "triangle_id": tri_id}
		var source_polygon_id: String = String(residual.get("source_polygon_ids", [triangle.get("polygon_id", "")])[0])
		var face: Dictionary = faces_by_id.get(source_polygon_id, {})
		if face.is_empty():
			return {"valid": false, "reason": "residual_owner_face_missing", "polygon_id": source_polygon_id}
		var ring_rows: Array[Dictionary] = []
		var patch_union: Dictionary = {}
		for level in range(4):
			var ring_ids: Array[String] = _radius_ids(tri_id, adjacency, level)
			for id in ring_ids: patch_union[id] = true
			ring_rows.append(_ring_evidence(level, ring_ids, triangles))
		var source_cell_array: Array = face.get("source_cell", [])
		if source_cell_array.size() != 3:
			return {"valid": false, "reason": "residual_source_cell_missing"}
		var global_cell: Vector3i = Vector3i(int(source_cell_array[0]), int(source_cell_array[1]), int(source_cell_array[2]))
		var local_cell: Vector3i = global_cell - global_origin
		var tetra_index: int = int(face.get("source_tetrahedron", -1))
		if tetra_index < 0 or tetra_index >= Core.TETS.size():
			return {"valid": false, "reason": "residual_source_tetrahedron_invalid"}
		var tetra_values: Array = Core.TETS[tetra_index]
		var tetra_samples: Array[Dictionary] = []
		for corner_value in tetra_values:
			var corner: Vector3i = Core.GRID_CORNERS[int(corner_value)]
			var local_node: Vector3i = local_cell + corner
			tetra_samples.append(_sample_record(local_node, cell_dims, origin_world, step, values, snapshot))
		var triangle_edges: Array[Dictionary] = []
		for edge_index in range(3):
			var a_id: String = String(triangle.root_ids[edge_index])
			var b_id: String = String(triangle.root_ids[(edge_index + 1) % 3])
			triangle_edges.append(_edge_evidence(a_id, b_id, geometry.get("arc_map", []), triangle.get("c6_flips", [])))
		var local_flips: Array[Dictionary] = _local_flips(geometry.get("applied_flips", []), triangle.get("root_ids", []), patch_union.keys())
		var root_rows: Array[Dictionary] = []
		for root_value in triangle.root_ids:
			var root_id: String = String(root_value)
			var root: Dictionary = roots_by_id[root_id]
			root_rows.append(_root_evidence(root, cell_dims, origin_world, step, values, snapshot))
		var local_triangles: Array[Dictionary] = []
		for tri_id_value in patch_union.keys():
			var local_triangle: Dictionary = _triangle_by_id(triangles, String(tri_id_value))
			if not local_triangle.is_empty(): local_triangles.append(local_triangle)
		var signature_payload: Dictionary = {"triangle_ids": _sorted_keys(patch_union), "boundary_edges": _boundary_edges(local_triangles), "source_polygon_id": source_polygon_id, "tetrahedron": tetra_index}
		var signature_bytes: PackedByteArray = JSON.stringify(signature_payload).to_utf8_buffer()
		residual_fixture_rows.append({
			"triangle_id": tri_id,
			"source_polygon_id": source_polygon_id,
			"source_cell_global_lattice": [global_cell.x, global_cell.y, global_cell.z],
			"source_cell_local_volume": [local_cell.x, local_cell.y, local_cell.z],
			"source_tetrahedron": tetra_index,
			"source_owner": face.get("source_row", [null, null, null, null, null, null, null, {}])[7],
			"rejection": residual,
			"triangle_root_ids": triangle.root_ids,
			"triangle_vertices_world": _points_array(triangle.points),
			"triangle_cross_squared_recomputed": triangle.cross_squared,
			"triangle_winding_normal": _vec_array(triangle.normal),
			"root_provenance_and_samples": root_rows,
			"tetrahedron_vertex_samples": tetra_samples,
			"triangle_edges_and_topology_arcs": triangle_edges,
			"adjacent_triangle_ids_by_ring": ring_rows,
			"local_c6_flips": local_flips,
			"local_patch_triangle_records": local_triangles,
			"local_topology_signature_sha256": Core.sha256(signature_bytes)
		})
	return {
		"valid": true,
		"schema": "P3.1.R12CX.ResidualCutoffFixture.v1",
		"hypothesis": "CX_BOUNDED_CAVITY_MICROPATCH",
		"source_c6_sha": EXPECTED_C6_SOURCE_SHA,
		"c6_artifact_sha256": EXPECTED_C6_ARTIFACT_SHA,
		"candidate_domain_sha256": "30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22",
		"topology_fixture_sha256": EXPECTED_FIXTURE_SHA,
		"manifest_sha256": EXPECTED_MANIFEST_SHA,
		"candidate_d_sha256": EXPECTED_CANDIDATE_SHA,
		"topology_authority_sha256": EXPECTED_AUTHORITY_SHA,
		"c6_campaign_sha256": EXPECTED_C6_CAMPAIGN_SHA,
		"c6_realizer_sha256": EXPECTED_C6_REALIZER_SHA,
		"topology_sha256": EXPECTED_TOPOLOGY_SHA,
		"graph_fingerprint_sha256": EXPECTED_GRAPH_SHA,
		"volume_sha256": EXPECTED_VOLUME_SHA,
		"volume_payload_sha256": EXPECTED_PAYLOAD_SHA,
		"target_scenario_id": TARGET_ID,
		"ledger_revision": int(c6.get("target", {}).get("revision", -1)),
		"fixed_cutoff_squared": CUTOFF_SQUARED,
		"c6_mesh_sha256": geometry.get("mesh_sha256", ""),
		"c6_triangle_count": int(geometry.get("geometry_triangle_count", -1)),
		"c6_topology_map": c6.get("topology_map", {}),
		"residual_triangle_count": residual_fixture_rows.size(),
		"residuals": residual_fixture_rows
	}

func _triangle_record(triangle_id: String, polygon_id: String, root_ids: Array, points: Array, construction: String, rejected: bool) -> Dictionary:
	var a: Vector3 = points[0]
	var b: Vector3 = points[1]
	var c: Vector3 = points[2]
	var cross: Vector3 = (b - a).cross(c - a)
	var cross_squared: float = cross.length_squared()
	return {"triangle_id": triangle_id, "polygon_id": polygon_id, "root_ids": root_ids.duplicate(), "points": points.duplicate(), "normal": cross.normalized() if cross_squared > 0.0 else Vector3.ZERO, "cross_squared": cross_squared, "rejected": rejected, "construction": construction}

func _triangle_adjacency(triangles: Array[Dictionary]) -> Dictionary:
	var edge_to_triangles: Dictionary = {}
	for triangle_value in triangles:
		var triangle: Dictionary = triangle_value
		var ids: Array = triangle.root_ids
		for index in range(3):
			var edge: String = _edge_key(String(ids[index]), String(ids[(index + 1) % 3]))
			if not edge_to_triangles.has(edge): edge_to_triangles[edge] = []
			edge_to_triangles[edge].append(String(triangle.triangle_id))
	var adjacency: Dictionary = {}
	for triangle_value in triangles: adjacency[String(triangle_value.triangle_id)] = {}
	for edge_value in edge_to_triangles.values():
		var edge_ids: Array = edge_value
		for i in range(edge_ids.size()):
			for j in range(i + 1, edge_ids.size()):
				adjacency[String(edge_ids[i])][String(edge_ids[j])] = true
				adjacency[String(edge_ids[j])][String(edge_ids[i])] = true
	return adjacency

func _radius_ids(seed_id: String, adjacency: Dictionary, radius: int) -> Array[String]:
	var distances: Dictionary = {seed_id: 0}
	var queue: Array[String] = [seed_id]
	var cursor: int = 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		var distance: int = int(distances[current])
		if distance >= radius: continue
		for neighbor in adjacency.get(current, {}).keys():
			var neighbor_id: String = String(neighbor)
			if distances.has(neighbor_id): continue
			distances[neighbor_id] = distance + 1
			queue.append(neighbor_id)
	return _sorted_keys(distances)

func _ring_evidence(level: int, ids: Array[String], triangles: Array[Dictionary]) -> Dictionary:
	var selected: Array[Dictionary] = []
	for triangle_id in ids:
		var triangle: Dictionary = _triangle_by_id(triangles, triangle_id)
		if not triangle.is_empty(): selected.append(triangle)
	var boundary: Array[String] = _boundary_edges(selected)
	return {"level": level, "triangle_ids": ids, "triangle_count": ids.size(), "boundary_edge_keys": boundary, "boundary_signature_sha256": Core.sha256(JSON.stringify(boundary).to_utf8_buffer())}

func _boundary_edges(triangles: Array[Dictionary]) -> Array[String]:
	var counts: Dictionary = {}
	for triangle in triangles:
		var ids: Array = triangle.get("root_ids", [])
		for index in range(ids.size()):
			var edge: String = _edge_key(String(ids[index]), String(ids[(index + 1) % ids.size()]))
			counts[edge] = int(counts.get(edge, 0)) + 1
	var boundary: Array[String] = []
	for edge in counts.keys():
		if int(counts[edge]) == 1: boundary.append(String(edge))
	boundary.sort()
	return boundary

func _edge_evidence(a_id: String, b_id: String, arcs: Array, _flip_rows: Array) -> Dictionary:
	var key: String = _edge_key(a_id, b_id)
	var matching: Array[Dictionary] = []
	for arc_value in arcs:
		var arc: Dictionary = arc_value
		var ids: Array = arc.get("root_ids", [])
		if ids.size() == 2 and _edge_key(String(ids[0]), String(ids[1])) == key: matching.append(arc)
	return {"root_ids": [a_id, b_id], "edge_key": key, "topology_arc_count": matching.size(), "topology_arcs": matching}

func _root_evidence(root: Dictionary, dims: Vector3i, world_min: Vector3, step: float, values: PackedFloat32Array, snapshot: Dictionary) -> Dictionary:
	var position: Vector3 = _to_vec3(root.get("position", Vector3.ZERO))
	var provenance: Dictionary = root.get("source_row", ["", Vector3.ZERO, Vector3.ZERO, "", {}])[4]
	var endpoint_rows: Array[Dictionary] = []
	var interpolation_t: float = -1.0
	var interpolated_position: Vector3 = Vector3.ZERO
	if provenance.has("node_a") and provenance.has("node_b"):
		var node_a: Vector3i = _vec3i(provenance.node_a)
		var node_b: Vector3i = _vec3i(provenance.node_b)
		var sample_a: Dictionary = _sample_record(node_a, dims, world_min, step, values, snapshot)
		var sample_b: Dictionary = _sample_record(node_b, dims, world_min, step, values, snapshot)
		endpoint_rows = [sample_a, sample_b]
		var da: float = float(sample_a.volume_density_binary32)
		var db: float = float(sample_b.volume_density_binary32)
		if da != db:
			interpolation_t = da / (da - db)
			interpolated_position = Vector3(sample_a.world_position[0], sample_a.world_position[1], sample_a.world_position[2]).lerp(Vector3(sample_b.world_position[0], sample_b.world_position[1], sample_b.world_position[2]), interpolation_t)
	var canonical_density: float = Core.sample(position, snapshot)
	return {"root_id": root.get("root_id", ""), "role": root.get("role", ""), "position_world": _vec_array(position), "position_float64_hex": PackedFloat64Array([position.x, position.y, position.z]).to_byte_array().hex_encode(), "source_row": root.get("source_row", []), "edge_endpoint_samples": endpoint_rows, "edge_interpolation_t_from_binary32_samples": interpolation_t, "edge_interpolated_position_world": _vec_array(interpolated_position) if interpolation_t >= 0.0 else [], "edge_interpolation_position_error": position.distance_to(interpolated_position) if interpolation_t >= 0.0 else -1.0, "canonical_continuous_sdf_density_at_root": canonical_density}

func _sample_record(local_node: Vector3i, dims: Vector3i, world_min: Vector3, step: float, values: PackedFloat32Array, snapshot: Dictionary) -> Dictionary:
	if local_node.x < 0 or local_node.y < 0 or local_node.z < 0 or local_node.x >= dims.x or local_node.y >= dims.y or local_node.z >= dims.z:
		return {"valid": false, "local_node": [local_node.x, local_node.y, local_node.z]}
	var index: int = (local_node.y * dims.z + local_node.z) * dims.x + local_node.x
	var density: float = values[index]
	var world: Vector3 = world_min + Vector3(local_node) * step
	var bytes: PackedByteArray = PackedFloat32Array([density]).to_byte_array()
	return {"valid": true, "local_node": [local_node.x, local_node.y, local_node.z], "linear_index": index, "world_position": _vec_array(world), "volume_density_binary32": density, "volume_density_binary32_hex_little_endian": bytes.hex_encode(), "canonical_continuous_sdf_density": Core.sample(world, snapshot)}

func _local_flips(flips: Array, triangle_root_ids: Array, patch_ids: Array) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	var roots: Dictionary = {}
	for value in triangle_root_ids: roots[String(value)] = true
	for value in patch_ids: roots[String(value)] = true
	for flip_value in flips:
		var flip: Dictionary = flip_value
		var touches: bool = false
		for root_id in flip.get("removed_arc_endpoint_ids", []):
			if roots.has(String(root_id)): touches = true
		for row in flip.get("source_provenance", []):
			if roots.has(String(row.get("source_polygon_id", ""))): touches = true
		if touches: selected.append(flip)
	return selected

func _triangle_by_id(triangles: Array[Dictionary], triangle_id: String) -> Dictionary:
	for triangle in triangles:
		if String(triangle.get("triangle_id", "")) == triangle_id: return triangle
	return {}

func _root_triplet_key(root_ids: Array) -> String:
	var ids: Array[String] = []
	for value in root_ids: ids.append(String(value))
	ids.sort()
	return "|".join(ids)

func _edge_key(a_id: String, b_id: String) -> String:
	return a_id + "\u001f" + b_id if a_id < b_id else b_id + "\u001f" + a_id

func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in values.keys(): result.append(String(value))
	result.sort()
	return result

func _points_array(points: Array) -> Array:
	var result: Array = []
	for value in points: result.append(_vec_array(value))
	return result

func _vec_array(value: Variant) -> Array[float]:
	var v: Vector3 = _to_vec3(value)
	return [v.x, v.y, v.z]

func _to_vec3(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size() == 3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)

func _vec3i(value: Variant) -> Vector3i:
	var a: Array = value
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))

func _exit_failure(reason: String, details: Dictionary = {}) -> void:
	push_error("R12CX_FIXTURE_FAILED " + JSON.stringify({"reason": reason, "details": details}))
	quit(2)
