extends RefCounted

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")

static func resolve_face_registry(all_triangles: Array[Dictionary], face_ids: Array) -> Dictionary:
	if face_ids.size() != 7:
		return {"valid": false, "reason": "r6d_authoritative_face_count_invalid", "expected": 7, "observed": face_ids.size()}
	var triangles_by_id: Dictionary = {}
	for triangle in all_triangles:
		var triangle_id: String = String(triangle.get("triangle_id", ""))
		if triangle_id.is_empty() or triangles_by_id.has(triangle_id):
			return {"valid": false, "reason": "r6d_complete_triangle_registry_invalid", "triangle_id": triangle_id, "duplicate": triangles_by_id.has(triangle_id)}
		triangles_by_id[triangle_id] = triangle
	var normalized_ids: Array[String] = []
	var seen_ids: Dictionary = {}
	for face_id_value in face_ids:
		var face_id: String = String(face_id_value)
		if face_id.is_empty() or seen_ids.has(face_id):
			return {"valid": false, "reason": "r6d_authoritative_face_id_invalid", "face_id": face_id, "duplicate": seen_ids.has(face_id)}
		seen_ids[face_id] = true
		normalized_ids.append(face_id)
	normalized_ids.sort()
	var missing_ids: Array[String] = []
	var patch: Array[Dictionary] = []
	for face_id in normalized_ids:
		if not triangles_by_id.has(face_id):
			missing_ids.append(face_id)
		else:
			patch.append(triangles_by_id[face_id])
	if not missing_ids.is_empty():
		return {"valid": false, "reason": "r6d_authoritative_faces_missing_from_complete_triangles", "missing_face_ids": missing_ids, "resolved_count": patch.size(), "expected_count": 7}
	return {"valid": true, "face_ids": normalized_ids, "patch": patch, "resolved_count": patch.size(), "registry_triangle_count": all_triangles.size(), "registry_identity_sha256": _triangle_registry_identity(all_triangles)}

static func reconstruct_cavity(realizer: RefCounted, all_triangles: Array[Dictionary], face_ids: Array, expected_signature: String = "") -> Dictionary:
	var registry: Dictionary = resolve_face_registry(all_triangles, face_ids)
	if not bool(registry.get("valid", false)):
		return registry
	var patch: Array[Dictionary] = registry.patch
	var connectivity: Dictionary = realizer.call("_r3_patch_connectivity", patch)
	if not bool(connectivity.get("valid", false)):
		return {"valid": false, "reason": "r6d_authoritative_patch_disconnected", "registry": registry, "connectivity": connectivity}
	var boundary: Dictionary = realizer.call("_r3_derive_remaining_boundary", all_triangles, registry.face_ids)
	if not bool(boundary.get("valid", false)):
		return {"valid": false, "reason": "r6d_authoritative_boundary_invalid", "registry": registry, "connectivity": connectivity, "boundary": boundary}
	var cycles: Dictionary = realizer.call("_r4_boundary_cycle_set", boundary)
	if not bool(cycles.get("valid", false)) or int(cycles.get("component_count", 0)) != 1 or cycles.get("cycles", []).size() != 1:
		return {"valid": false, "reason": "r6d_authoritative_boundary_not_single_cycle", "registry": registry, "connectivity": connectivity, "boundary": boundary, "cycles": cycles}
	var signature: String = String(boundary.get("signature", ""))
	if signature.is_empty() or (not expected_signature.is_empty() and signature != expected_signature):
		return {"valid": false, "reason": "r6d_authoritative_boundary_signature_mismatch", "observed_signature": signature, "expected_signature": expected_signature, "registry": registry, "connectivity": connectivity, "boundary": boundary, "cycles": cycles}
	var reversed_ids: Array = registry.face_ids.duplicate()
	reversed_ids.reverse()
	var reverse_registry: Dictionary = resolve_face_registry(all_triangles, reversed_ids)
	var reverse_boundary: Dictionary = realizer.call("_r3_derive_remaining_boundary", all_triangles, reverse_registry.get("face_ids", []))
	if not bool(reverse_registry.get("valid", false)) or String(reverse_boundary.get("signature", "")) != signature:
		return {"valid": false, "reason": "r6d_face_order_changed_cavity_identity", "forward_signature": signature, "reverse_signature": reverse_boundary.get("signature", "")}
	return {"valid": true, "face_ids": registry.face_ids, "patch": patch, "connectivity": connectivity, "boundary": boundary, "cycles": cycles, "boundary_signature": signature, "registry_triangle_count": all_triangles.size(), "registry_identity_sha256": registry.registry_identity_sha256}

static func build_causal_topology_map(realizer: RefCounted, all_triangles: Array[Dictionary], cavity: Dictionary, p1_pair: Array, blocker_arc_ids: Array, residual_region_ids: Array, root_positions: Dictionary, canonical_arc_rows: Array = []) -> Dictionary:
	if not bool(cavity.get("valid", false)) or p1_pair.size() != 2:
		return {"valid": false, "reason": "r6d_causal_map_input_invalid"}
	var face_ids: Array[String] = cavity.face_ids.duplicate()
	var selected: Dictionary = {}
	for face_id in face_ids: selected[face_id] = true
	var edge_faces: Dictionary = {}
	var face_neighbors: Dictionary = {}
	var triangle_ids: Array[String] = []
	for triangle in all_triangles:
		var triangle_id: String = String(triangle.get("triangle_id", ""))
		triangle_ids.append(triangle_id)
		face_neighbors[triangle_id] = {}
		var roots: Array = triangle.get("root_ids", [])
		for edge_index in range(3):
			var edge_key: String = String(realizer.call("_edge_key", String(roots[edge_index]), String(roots[(edge_index + 1) % 3])))
			if not edge_faces.has(edge_key): edge_faces[edge_key] = []
			edge_faces[edge_key].append(triangle_id)
	for edge_key in edge_faces:
		var incident: Array = edge_faces[edge_key]
		incident.sort()
		for left_index in range(incident.size()):
			for right_index in range(left_index + 1, incident.size()):
				face_neighbors[String(incident[left_index])][String(incident[right_index])] = true
				face_neighbors[String(incident[right_index])][String(incident[left_index])] = true
	var p1_edge_key: String = String(realizer.call("_edge_key", String(p1_pair[0]), String(p1_pair[1])))
	var cavity_faces_at_p1: Array[String] = []
	var outside_faces_at_p1: Array[String] = []
	for face_id_value in edge_faces.get(p1_edge_key, []):
		var face_id: String = String(face_id_value)
		if selected.has(face_id): cavity_faces_at_p1.append(face_id)
		else: outside_faces_at_p1.append(face_id)
	cavity_faces_at_p1.sort(); outside_faces_at_p1.sort()
	if cavity_faces_at_p1.is_empty():
		return {"valid": false, "reason": "r6d_p1_not_incident_to_authoritative_cavity", "p1_edge_key": p1_edge_key, "edge_faces": edge_faces.get(p1_edge_key, [])}
	var arc_incident_faces: Dictionary = {}
	var missing_arc_roots: Array[String] = []
	var arc_rows: Array[Dictionary] = []
	for arc_id_value in blocker_arc_ids:
		var arc_id: String = String(arc_id_value)
		var parts: PackedStringArray = arc_id.split("\u001f")
		if parts.size() != 2:
			return {"valid": false, "reason": "r6d_blocking_arc_id_invalid", "arc_id": arc_id}
		var arc_edge_key: String = String(realizer.call("_edge_key", String(parts[0]), String(parts[1])))
		var arc_faces: Array[String] = []
		for face_id_value in edge_faces.get(arc_edge_key, []):
			var face_id: String = String(face_id_value)
			arc_faces.append(face_id)
			arc_incident_faces[face_id] = true
		arc_faces.sort()
		if not root_positions.has(String(parts[0])): missing_arc_roots.append(String(parts[0]))
		if not root_positions.has(String(parts[1])): missing_arc_roots.append(String(parts[1]))
		arc_rows.append({"arc_id": arc_id, "edge_key": arc_edge_key, "root_ids": [String(parts[0]), String(parts[1])], "incident_triangle_ids": arc_faces, "incident_triangle_count": arc_faces.size()})
	if not missing_arc_roots.is_empty():
		missing_arc_roots.sort()
		return {"valid": false, "reason": "r6d_blocking_arc_root_not_in_frozen_root_registry", "missing_root_ids": missing_arc_roots}
	arc_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.arc_id) < String(b.arc_id))
	var p1_boundary_root_ids: Dictionary = {}
	for face_id in cavity_faces_at_p1:
		var face: Dictionary = {}
		for row in cavity.patch:
			if String(row.get("triangle_id", "")) == face_id: face = row; break
		for root_id_value in face.get("root_ids", []): p1_boundary_root_ids[String(root_id_value)] = true
	var causal_seeds: Dictionary = {}
	for face_id in cavity_faces_at_p1: causal_seeds[face_id] = true
	for face_id in outside_faces_at_p1: causal_seeds[face_id] = true
	for face_id in arc_incident_faces: causal_seeds[String(face_id)] = true
	var d1_universe: Dictionary = causal_seeds.duplicate()
	for seed_id_value in causal_seeds.keys():
		for neighbor_id_value in face_neighbors.get(String(seed_id_value), {}).keys(): d1_universe[String(neighbor_id_value)] = true
	var d1_face_ids: Array[String] = []
	for face_id_value in d1_universe.keys(): d1_face_ids.append(String(face_id_value))
	d1_face_ids.sort()
	var d1_additions: Dictionary = {}
	for boundary_edge_value in cavity.boundary.get("directed_edges", []):
		var directed: PackedStringArray = String(boundary_edge_value).split("->")
		if directed.size() != 2: continue
		var edge_key: String = String(realizer.call("_edge_key", String(directed[0]), String(directed[1])))
		var endpoint_is_causal: bool = p1_boundary_root_ids.has(String(directed[0])) or p1_boundary_root_ids.has(String(directed[1]))
		for arc_row in arc_rows:
			var arc_roots: Array = arc_row.get("root_ids", [])
			if arc_roots.has(String(directed[0])) or arc_roots.has(String(directed[1])): endpoint_is_causal = true
		if not endpoint_is_causal: continue
		for incident_face_value in edge_faces.get(edge_key, []):
			var incident_face: String = String(incident_face_value)
			if not selected.has(incident_face) and d1_universe.has(incident_face): d1_additions[incident_face] = true
	var d1_addition_face_ids: Array[String] = _sorted_keys(d1_additions)
	var p1_boundary_edges: Array[String] = [p1_edge_key]
	var p1_shared_root_boundary_edges: Array[String] = []
	for boundary_edge_value in cavity.boundary.get("incidence_diagnostics", []):
		var incidence: Dictionary = boundary_edge_value
		var roots: Array = String(incidence.get("edge_key", "")).split("\u001f")
		if roots.size() == 2 and p1_boundary_root_ids.has(String(roots[0])) and p1_boundary_root_ids.has(String(roots[1])):
			p1_shared_root_boundary_edges.append(String(incidence.edge_key))
	p1_shared_root_boundary_edges.sort()
	var all_arcs_valid: bool = true
	for arc_value in canonical_arc_rows:
		var arc: Dictionary = arc_value
		var roots: Array = arc.get("root_ids", [])
		if roots.size() != 2 or not root_positions.has(String(roots[0])) or not root_positions.has(String(roots[1])):
			all_arcs_valid = false
			break
	return {
		"valid": all_arcs_valid,
		"reason": "" if all_arcs_valid else "r6d_frozen_required_arc_root_mapping_invalid",
		"cavity_face_ids": face_ids,
		"cavity_boundary_signature": cavity.boundary_signature,
		"cavity_boundary_cycle": cavity.cycles.cycles[0].get("root_ids", []),
		"p1_pair": [String(p1_pair[0]), String(p1_pair[1])],
		"p1_edge_key": p1_edge_key,
		"p1_cavity_incident_face_ids": cavity_faces_at_p1,
		"p1_outside_face_ids": outside_faces_at_p1,
		"p1_boundary_edges_sharing_causal_roots": p1_shared_root_boundary_edges,
		"blocking_arcs": arc_rows,
		"residual_region_ids": residual_region_ids.duplicate(),
		"causal_seed_face_ids": _sorted_keys(causal_seeds),
		"d1_face_universe": d1_face_ids,
		"d1_addition_face_ids": d1_addition_face_ids,
		"d1_face_universe_sha256": Core.sha256("\n".join(d1_face_ids).to_utf8_buffer()),
		"complete_triangles_count": all_triangles.size(),
		"triangle_registry_sha256": _triangle_registry_identity(all_triangles),
		"frozen_required_arc_root_mapping_valid": all_arcs_valid
	}

static func generate_d1_additions(topology_map: Dictionary) -> Array[Dictionary]:
	var cavity_ids: Array = topology_map.get("cavity_face_ids", [])
	var p1_faces: Dictionary = {}
	for face_id_value in topology_map.get("p1_cavity_incident_face_ids", []): p1_faces[String(face_id_value)] = true
	var outside_faces: Dictionary = {}
	for face_id_value in topology_map.get("d1_addition_face_ids", []): outside_faces[String(face_id_value)] = true
	var rows: Array[Dictionary] = []
	var outside_ids: Array[String] = _sorted_keys(outside_faces)
	for face_id in outside_ids:
		var transformation: String = "EXPAND_ACROSS_P1" if topology_map.get("p1_outside_face_ids", []).has(face_id) else "LOCAL_CAUSAL_EXPANSION"
		var candidate_ids: Array[String] = []
		for cavity_face_id in cavity_ids: candidate_ids.append(String(cavity_face_id))
		candidate_ids.append(face_id)
		candidate_ids.sort()
		rows.append({"transformation": transformation, "face_ids": candidate_ids, "added_face_ids": [face_id], "removed_face_ids": [], "symmetric_difference_count": 1})
	for remove_face_id_value in topology_map.get("p1_cavity_incident_face_ids", []):
		var remove_face_id: String = String(remove_face_id_value)
		for add_face_id in outside_ids:
			if not p1_faces.has(remove_face_id): continue
			var shifted: Array[String] = []
			for cavity_face_id in cavity_ids:
				if String(cavity_face_id) != remove_face_id: shifted.append(String(cavity_face_id))
			shifted.append(add_face_id); shifted.sort()
			rows.append({"transformation": "SHIFT_P1_BOUNDARY", "face_ids": shifted, "added_face_ids": [add_face_id], "removed_face_ids": [remove_face_id], "symmetric_difference_count": 2})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_causal: int = 0 if String(a.transformation) == "EXPAND_ACROSS_P1" else 1
		var b_causal: int = 0 if String(b.transformation) == "EXPAND_ACROSS_P1" else 1
		if a_causal != b_causal: return a_causal < b_causal
		if int(a.symmetric_difference_count) != int(b.symmetric_difference_count): return int(a.symmetric_difference_count) < int(b.symmetric_difference_count)
		if a.face_ids.size() != b.face_ids.size(): return a.face_ids.size() < b.face_ids.size()
		return "|".join(a.face_ids) < "|".join(b.face_ids)
	)
	return rows

static func prequalify_topology(realizer: RefCounted, all_triangles: Array[Dictionary], candidate_ids: Array, root_positions: Dictionary) -> Dictionary:
	var registry: Dictionary = _resolve_any_face_registry(all_triangles, candidate_ids)
	if not bool(registry.get("valid", false)): return registry
	var patch: Array[Dictionary] = registry.patch
	var connectivity: Dictionary = realizer.call("_r3_patch_connectivity", patch)
	if not bool(connectivity.get("valid", false)): return {"valid": false, "reason": "r6d_candidate_disconnected", "connectivity": connectivity}
	var boundary: Dictionary = realizer.call("_r3_derive_remaining_boundary", all_triangles, registry.face_ids)
	if not bool(boundary.get("valid", false)): return {"valid": false, "reason": "r6d_candidate_boundary_invalid", "boundary": boundary}
	var cycles: Dictionary = realizer.call("_r4_boundary_cycle_set", boundary)
	if not bool(cycles.get("valid", false)) or int(cycles.get("component_count", 0)) != 1 or cycles.get("cycles", []).size() != 1:
		return {"valid": false, "reason": "r6d_candidate_not_single_boundary_cycle", "cycles": cycles}
	var cycle: Array = cycles.cycles[0].get("root_ids", [])
	var seen_positions: Dictionary = {}
	for root_id_value in cycle:
		var root_id: String = String(root_id_value)
		if not root_positions.has(root_id): return {"valid": false, "reason": "r6d_candidate_boundary_root_missing", "root_id": root_id}
		var position: Vector3 = Vector3(root_positions[root_id])
		var position_key: String = PackedFloat32Array([position.x, position.y, position.z]).to_byte_array().hex_encode()
		if seen_positions.has(position_key): return {"valid": false, "reason": "r6d_candidate_duplicate_boundary_position", "root_ids": [String(seen_positions[position_key]), root_id]}
		seen_positions[position_key] = root_id
	return {"valid": true, "face_ids": registry.face_ids, "patch": patch, "connectivity": connectivity, "boundary": boundary, "cycles": cycles, "boundary_signature": boundary.get("signature", ""), "boundary_cycle": cycle, "boundary_edge_count": boundary.get("boundary_edge_count", -1)}

static func _resolve_any_face_registry(all_triangles: Array[Dictionary], face_ids: Array) -> Dictionary:
	if face_ids.is_empty(): return {"valid": false, "reason": "r6d_candidate_face_ids_empty"}
	var triangles_by_id: Dictionary = {}
	for triangle in all_triangles:
		var triangle_id: String = String(triangle.get("triangle_id", ""))
		if triangle_id.is_empty() or triangles_by_id.has(triangle_id): return {"valid": false, "reason": "r6d_complete_triangle_registry_invalid", "triangle_id": triangle_id}
		triangles_by_id[triangle_id] = triangle
	var ids: Array[String] = []
	var seen: Dictionary = {}
	for value in face_ids:
		var face_id: String = String(value)
		if face_id.is_empty() or seen.has(face_id): return {"valid": false, "reason": "r6d_candidate_face_id_invalid", "face_id": face_id}
		seen[face_id] = true; ids.append(face_id)
	ids.sort()
	var missing: Array[String] = []
	var patch: Array[Dictionary] = []
	for face_id in ids:
		if not triangles_by_id.has(face_id): missing.append(face_id)
		else: patch.append(triangles_by_id[face_id])
	if not missing.is_empty(): return {"valid": false, "reason": "r6d_candidate_face_missing", "missing_face_ids": missing}
	return {"valid": true, "face_ids": ids, "patch": patch, "registry_triangle_count": all_triangles.size()}

static func _triangle_registry_identity(all_triangles: Array[Dictionary]) -> String:
	var identities: Array[String] = []
	for triangle in all_triangles:
		var roots: Array[String] = []
		for root in triangle.get("root_ids", []): roots.append(String(root))
		identities.append(String(triangle.get("triangle_id", "")) + "\u001f" + "|".join(roots))
	identities.sort()
	return Core.sha256("\n".join(identities).to_utf8_buffer())

static func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in values.keys(): result.append(String(value))
	result.sort()
	return result
