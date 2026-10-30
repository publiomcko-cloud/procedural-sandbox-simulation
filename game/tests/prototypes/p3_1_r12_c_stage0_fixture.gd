extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Authority := preload("res://tests/prototypes/p3_1_r10_a_topology_authority.gd")
const MANIFEST_SHA := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const DOMAIN_SHA := "30c89e9ca26c5c6550b6662fc6ccb46f566cfff7eb29b9e740f8ec1b1b7c9c22"
const DOMAIN_IDENTITY_SHA := "b3c5de9786a078a6568650ef62e2150524f1b387e9e979cba5a060723d990feb"
const B1R_REALIZER_SHA := "31fc01c78e273aede396a7596c3827f4520f45259d2c7e0f2ef9663d73ebcb5e"
const B1R_SOURCE_SHA := "6f28273d0113f93678034b9e482140e73e765721"
const TOPOLOGY_SHA := "4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95"
const VOLUME_SHA := "ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2"
const PAYLOAD_SHA := "2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0"
const A6_MESH_SHA := "de53e9fa326e451ac202beb49c0ef1e56b70500ce1ca3dd9c43565d85e7c5f74"
const COMPONENT := "60,8,25|tet:0"
const FIXTURE_FILE := "r12c_stage0_topology_fixture.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_sha: String = OS.get_environment("R12C_SOURCE_SHA")
	var artifact_root: String = OS.get_environment("R12C_ARTIFACT_DIR")
	var domain_path: String = OS.get_environment("R12C_DOMAIN_PATH")
	if source_sha.length() != 40 or artifact_root.is_empty() or not DirAccess.dir_exists_absolute(artifact_root) or domain_path.is_empty():
		_fail("environment_invalid", {})
		return
	var domain_bytes: PackedByteArray = FileAccess.get_file_as_bytes(domain_path)
	if domain_bytes.is_empty() or Core.sha256(domain_bytes) != DOMAIN_SHA:
		_fail("domain_hash_mismatch", {"observed": Core.sha256(domain_bytes)})
		return
	var parsed_domain: Variant = JSON.parse_string(domain_bytes.get_string_from_utf8())
	if typeof(parsed_domain) != TYPE_DICTIONARY:
		_fail("domain_json_invalid", {})
		return
	var domain: Dictionary = parsed_domain
	if String(domain.get("component_id", "")) != COMPONENT or int(domain.get("candidate_count", -1)) != 7608:
		_fail("domain_identity_mismatch", {})
		return
	var identity: Dictionary = domain.get("identity", {})
	if _domain_identity_sha(domain) != DOMAIN_IDENTITY_SHA or String(identity.get("source_sha", "")) != B1R_SOURCE_SHA or String(identity.get("b1r_realizer_sha256", "")) != B1R_REALIZER_SHA or String(identity.get("candidate_d_sha256", "")) != "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a" or String(identity.get("manifest_sha256", "")) != MANIFEST_SHA or String(identity.get("volume_sha256", "")) != VOLUME_SHA or String(identity.get("payload_sha256", "")) != PAYLOAD_SHA or int(identity.get("revision", -1)) != 2 or String(identity.get("source_topology_sha256", "")) != TOPOLOGY_SHA or String(identity.get("component_id", "")) != COMPONENT or not is_equal_approx(float(identity.get("cross_squared_cutoff", -1.0)), 1.0e-12):
		_fail("domain_identity_hash_or_frozen_inputs_mismatch", {"identity_sha256": _domain_identity_sha(domain), "identity": identity})
		return
	var manifest: Dictionary = Core.load_manifest()
	if not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != MANIFEST_SHA:
		_fail("manifest_invalid", {"reason": manifest.get("reason", "")})
		return
	var row: Dictionary = Core.case_by_id(manifest.rows, "R9.2.SEAM.XPLUS_EQUAL.v1")
	if row.is_empty():
		_fail("frozen_equal_case_missing", {})
		return
	var setup: Dictionary = Core.make_snapshot(row)
	if not bool(setup.get("valid", false)):
		_fail("snapshot_invalid", {"reason": setup.get("reason", "")})
		return
	var snapshot: Dictionary = setup.get("snapshot", {})
	var candidate: RefCounted = CandidateD.new()
	candidate.call("configure_roi", row.roi)
	var materialized: Dictionary = candidate.call("build", snapshot, row, {"id": "R12C_STAGE0"})
	if not bool(materialized.get("valid", false)):
		_fail("candidate_d_volume_failed", {"reason": materialized.get("reason", "")})
		return
	var volume: Dictionary = materialized.get("volume", {})
	var values: PackedFloat32Array = volume.get("values", PackedFloat32Array())
	var volume_sha: String = String(volume.get("sha256", ""))
	var payload_sha: String = String(materialized.get("metrics", {}).get("volume", {}).get("payload_sha256", ""))
	if volume_sha != VOLUME_SHA or payload_sha != PAYLOAD_SHA or values.is_empty():
		_fail("volume_identity_mismatch", {"volume_sha": volume_sha, "payload_sha": payload_sha})
		return
	var authority: RefCounted = Authority.new()
	authority.call("configure_roi", row.roi)
	var a1: Dictionary = authority.call("realize_topology", values, "R10A1_ALT_DIAGONAL_MAX_MIN_AREA", snapshot, int(row.get("seed", 131102026)))
	var source_graph: Dictionary = a1.get("topology_graph", {})
	if not bool(source_graph.get("valid", false)) or String(source_graph.get("topology_sha256", "")) != TOPOLOGY_SHA:
		_fail("source_topology_not_reproduced", {"valid": source_graph.get("valid", false), "topology_sha": source_graph.get("topology_sha256", ""), "roots": source_graph.get("root_count", -1), "polygons": source_graph.get("polygon_count", -1), "arcs": source_graph.get("arc_count", -1)})
		return
	var a6_result: Dictionary = authority.call("realize_topology", values, "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION", snapshot, int(row.get("seed", 131102026)))
	var a6: Dictionary = _historical_a6_result(a6_result, source_graph)
	if not bool(a6.get("valid", false)):
		_fail("historical_a6_mismatch", a6)
		return
	var component: Dictionary = _target_patch(a6_result.get("component_reconstruction", {}).get("patches", []))
	if component.is_empty():
		_fail("target_component_missing", {"target_component_id": COMPONENT, "available_patches": _patch_diagnostics(a6_result.get("component_reconstruction", {}).get("patches", []))})
		return
	var canonical: Dictionary = source_graph.get("canonical", {})
	var polygon_ids: Array[String] = _strings(component.get("source_polygon_ids", []))
	var root_set: Dictionary = {}
	for polygon in _filter_polygons(canonical.get("polygons", []), polygon_ids):
		for root_id in polygon[3]:
			root_set[String(root_id)] = true
	var root_ids: Array[String] = _strings(root_set.keys())
	root_ids.sort()
	var roots: Array = _filter_roots(canonical.get("roots", []), root_ids)
	var polygons: Array = _filter_polygons(canonical.get("polygons", []), polygon_ids)
	var arcs: Array = _component_arcs(polygons, canonical.get("arcs", []))
	if root_ids.size() != 73 or roots.size() != 73 or polygon_ids.size() != 84 or polygons.size() != 84:
		_fail("component_counts_mismatch", {"root_ids": root_ids.size(), "roots": roots.size(), "polygon_ids": polygon_ids.size(), "polygons": polygons.size()})
		return
	var domain_roots: Array = domain.get("root_rows", [])
	if not _coordinates_match(roots, domain_roots):
		_fail("domain_root_coordinates_mismatch", {})
		return
	var domain_root_by_index: Dictionary = {}
	for root in domain_roots:
		if typeof(root) != TYPE_DICTIONARY:
			_fail("domain_root_row_invalid", {})
			return
		var root_index: int = int(root.get("index", -1))
		if root_index < 0 or domain_root_by_index.has(root_index):
			_fail("domain_root_index_invalid_or_duplicate", {"index": root_index})
			return
		domain_root_by_index[root_index] = String(root.get("id", ""))
	var boundary_cycle: Array = domain.get("boundary_cycle", [])
	if boundary_cycle.size() != 34:
		_fail("boundary_cycle_count_mismatch", {"count": boundary_cycle.size()})
		return
	var ordered_boundary: Array[String] = []
	var boundary_set: Dictionary = {}
	for index_value in boundary_cycle:
		var index: int = int(index_value)
		if not domain_root_by_index.has(index):
			_fail("boundary_root_index_missing", {"index": index})
			return
		var id: String = String(domain_root_by_index[index])
		if boundary_set.has(id):
			_fail("boundary_root_duplicate", {"id": id})
			return
		boundary_set[id] = true
		ordered_boundary.append(id)
	var boundary_arcs: Array[Dictionary] = _boundary_arcs(arcs)
	if boundary_arcs.size() != 34 or not _boundary_matches(domain.get("required_boundary_edges", []), boundary_cycle, domain_root_by_index, boundary_arcs):
		_fail("boundary_arc_mismatch", {"arcs": boundary_arcs.size()})
		return
	var degrees: Array[Dictionary] = _degrees(roots, arcs, boundary_set)
	var ownership: Array[Dictionary] = _ownership_transitions(arcs, polygons)
	var all_roots: Array = canonical.get("roots", [])
	var all_polygons: Array = canonical.get("polygons", [])
	var all_arcs: Array = canonical.get("arcs", [])
	var all_boundary_roots: Dictionary = _global_boundary_roots(all_arcs)
	var all_degrees: Array[Dictionary] = _degrees(all_roots, all_arcs, all_boundary_roots)
	var all_ownership: Array[Dictionary] = _ownership_transitions(all_arcs, all_polygons)
	var transition_roots: Dictionary = {}
	for entry in ownership:
		for id in entry.get("roots", []):
			transition_roots[String(id)] = true
	var junctions: Array[String] = []
	var transit: Array[String] = []
	for entry in degrees:
		var id: String = String(entry.root_id)
		var degree: int = int(entry.degree)
		if not bool(entry.boundary) and degree != 2:
			junctions.append(id)
		if not bool(entry.boundary) and degree == 2 and not transition_roots.has(id):
			transit.append(id)
	var component_signature_payload: Dictionary = {"schema": canonical.get("schema", ""), "component_id": COMPONENT, "root_ids": root_ids, "polygon_ids": polygon_ids, "roots": roots, "polygons": polygons, "arcs": arcs}
	var component_signature_sha: String = Core.sha256(JSON.stringify(component_signature_payload).to_utf8_buffer())
	var fixture: Dictionary = {
		"schema": "P3.1.R12C.TopologyRealizationFixture.v1",
		"fixture_id": "R12C.XPLUS_EQUAL.COMPONENT_60_8_25_TET0.v1",
		"source_sha": source_sha,
		"source_topology_sha256": TOPOLOGY_SHA,
		"topology_signature": {"sha256": TOPOLOGY_SHA, "payload": canonical},
		"target_component_signature": {"sha256": component_signature_sha, "payload": component_signature_payload},
		"component_id": COMPONENT,
		"counts": {"topology_roots": all_roots.size(), "topology_polygons": all_polygons.size(), "topology_arcs": all_arcs.size(), "target_roots": 73, "boundary_roots": 34, "interior_roots": 39, "target_polygons": 84, "target_arcs": arcs.size(), "boundary_arcs": 34},
		"topology_authority": canonical,
		"all_root_degrees": all_degrees,
		"all_ownership_transitions": all_ownership,
		"topology_roots": roots,
		"root_degrees": degrees,
		"topology_arcs": arcs,
		"arc_orientation_contract": "authoritative ordered root pair plus polygon and tetra-face provenance",
		"component_membership": {"root_ids": root_ids, "polygon_ids": polygon_ids},
		"boundary": {"ordered_root_cycle": ordered_boundary, "boundary_arcs": boundary_arcs, "domain_edge_indices": domain.get("required_boundary_edges", [])},
		"source_provenance": {"all_polygons": all_polygons, "component_polygons": polygons, "ownership": canonical.get("ownership", {}), "neighbor_region_relations": canonical.get("neighbor_region_relations", []), "lod_relations": canonical.get("lod_relations", [])},
		"ownership_transitions": ownership,
		"junction_roots": junctions,
		"degree2_transit_candidates": transit,
		"historical_a6_realization": a6,
		"volume": {"sha256": volume_sha, "payload_sha256": payload_sha, "revision": int(volume.get("revision", -1)), "grid_step": float(domain.get("grid_step", 0.0)), "roi_id": String(domain.get("identity", {}).get("roi_id", "")), "roi_min": domain.get("identity", {}).get("roi_min", []), "roi_cells": domain.get("identity", {}).get("roi_cells", []), "cutoff_squared": float(domain.get("identity", {}).get("cross_squared_cutoff", -1.0)), "manifest_sha256": MANIFEST_SHA, "domain_sha256": DOMAIN_SHA},
		"candidate_domain_identity": domain.get("identity", {})
	}
	var output_path: String = artifact_root.path_join(FIXTURE_FILE)
	if FileAccess.file_exists(output_path):
		_fail("fixture_overwrite_refused", {"path": output_path})
		return
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("fixture_open_failed", {"path": output_path})
		return
	file.store_buffer(JSON.stringify(fixture).to_utf8_buffer())
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_fail("fixture_write_failed", {"error": error_string(write_error)})
		return
	print("R12C_STAGE0_COMPLETE " + JSON.stringify({"status": "PASS", "source_sha": source_sha, "fixture_sha256": Core.sha256(FileAccess.get_file_as_bytes(output_path)), "topology_sha256": TOPOLOGY_SHA, "component_roots": 73, "component_polygons": 84, "component_arcs": arcs.size(), "boundary_roots": 34, "interior_roots": 39, "junction_roots": junctions.size(), "degree2_transit_candidates": transit.size(), "a6_mesh_sha256": a6.mesh_sha256, "a6_internal_open_edges": a6.mesh_topology.internal_open_edges}))
	quit(0)

func _target_patch(patches: Array) -> Dictionary:
	for value in patches:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = value
		if String(candidate.get("component_id", "")) == COMPONENT:
			return candidate
	return {}

func _patch_diagnostics(patches: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in patches:
		if typeof(value) == TYPE_DICTIONARY:
			var patch: Dictionary = value
			result.append({"component_id": String(patch.get("component_id", "")), "root_count": patch.get("source_root_count", -1), "boundary_root_count": patch.get("boundary_root_count", -1), "polygon_count": patch.get("source_polygon_ids", []).size(), "status": String(patch.get("status", "")), "reason": String(patch.get("reason", ""))})
	return result

func _strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			result.append(String(item))
	return result

func _filter_roots(rows: Array, ids: Array[String]) -> Array:
	var allowed: Dictionary = {}
	for id in ids:
		allowed[id] = true
	var result: Array = []
	for row in rows:
		if row is Array and row.size() >= 5 and allowed.has(String(row[0])):
			result.append(row)
	return result

func _filter_polygons(rows: Array, ids: Array[String]) -> Array:
	var allowed: Dictionary = {}
	for id in ids:
		allowed[id] = true
	var result: Array = []
	for row in rows:
		if row is Array and row.size() >= 9 and allowed.has(String(row[0])):
			result.append(row)
	return result

func _filter_arcs(rows: Array, polygon_ids: Array[String]) -> Array:
	var allowed: Dictionary = {}
	for id in polygon_ids:
		allowed[id] = true
	var result: Array = []
	for row in rows:
		if not (row is Array) or row.size() < 8:
			continue
		for owner in row[3]:
			if allowed.has(String(owner)):
				result.append(row)
				break
	return result

func _component_arcs(polygons: Array, authority_arcs: Array) -> Array:
	var authority_by_pair: Dictionary = {}
	for arc in authority_arcs:
		if not (arc is Array) or arc.size() < 8 or not (arc[1] is Array) or arc[1].size() != 2:
			return []
		authority_by_pair[_edge_key(String(arc[1][0]), String(arc[1][1]))] = arc
	var occurrences: Dictionary = {}
	for polygon in polygons:
		if not (polygon is Array) or polygon.size() < 9 or not (polygon[3] is Array) or not (polygon[4] is Array) or polygon[3].size() != polygon[4].size():
			return []
		var root_ids: Array = polygon[3]
		var face_ids: Array = polygon[4]
		for index in range(root_ids.size()):
			var left: String = String(root_ids[index])
			var right: String = String(root_ids[(index + 1) % root_ids.size()])
			var key: String = _edge_key(left, right)
			if not occurrences.has(key):
				occurrences[key] = {"roots": [left, right], "polygon_ids": [], "face_ids": []}
			occurrences[key].polygon_ids.append(String(polygon[0]))
			occurrences[key].face_ids.append(String(face_ids[index]))
	var keys: Array = occurrences.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		if not authority_by_pair.has(String(key)):
			return []
		var local: Dictionary = occurrences[String(key)]
		var authority: Array = authority_by_pair[String(key)]
		local.polygon_ids.sort()
		local.face_ids.sort()
		result.append([authority[0], local.roots, local.polygon_ids.size(), local.polygon_ids, local.face_ids, local.polygon_ids.size() == 1, authority[6], authority[7], int(authority[2]), bool(authority[5])])
	return result

func _global_boundary_roots(arcs: Array) -> Dictionary:
	var result: Dictionary = {}
	for arc in arcs:
		if arc is Array and arc.size() >= 6 and bool(arc[5]) and arc[1] is Array:
			for root_id in arc[1]:
				result[String(root_id)] = true
	return result

func _boundary_arcs(arcs: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in arcs:
		if row is Array and row.size() >= 8 and bool(row[5]):
			result.append({"edge_key": String(row[0]), "roots": row[1], "incidence": row[2], "polygon_ids": row[3], "face_ids": row[4], "boundary_faces": row[6], "owner_polygon": row[7]})
	return result

func _boundary_matches(required_edges: Array, cycle: Array, index_to_id: Dictionary, boundary_arcs: Array[Dictionary]) -> bool:
	var required: Dictionary = {}
	for edge in required_edges:
		if not (edge is Array) or edge.size() != 2:
			return false
		var a_index: int = int(edge[0])
		var b_index: int = int(edge[1])
		if not index_to_id.has(a_index) or not index_to_id.has(b_index):
			return false
		var a: String = String(index_to_id[a_index])
		var b: String = String(index_to_id[b_index])
		required[_edge_key(a, b)] = true
	var cycle_edges: Dictionary = {}
	for i in range(cycle.size()):
		cycle_edges[_edge_key(String(index_to_id[int(cycle[i])]), String(index_to_id[int(cycle[(i + 1) % cycle.size()])]))] = true
	if required.size() != 34 or cycle_edges.size() != 34:
		return false
	for key in required:
		if not cycle_edges.has(key):
			return false
	var actual: Dictionary = {}
	for arc in boundary_arcs:
		var roots: Array = arc.get("roots", [])
		if roots.size() != 2:
			return false
		var key: String = _edge_key(String(roots[0]), String(roots[1]))
		if actual.has(key):
			return false
		actual[key] = true
	if actual.size() != 34:
		return false
	for key in required:
		if not actual.has(key):
			return false
	return true

func _edge_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func _domain_identity_sha(domain: Dictionary) -> String:
	var identity: Dictionary = {"schema": domain.schema, "identity": domain.identity, "component_id": domain.component_id, "source_polygon_ids": domain.source_polygon_ids, "source_polygon_count": domain.source_polygon_count, "orientation_sample_count": domain.orientation_sample_count, "source_cell_owners": domain.source_cell_owners, "grid_step": domain.grid_step, "source_root_count": domain.source_root_count, "source_boundary_root_count": domain.source_boundary_root_count, "source_interior_root_count": domain.source_interior_root_count, "projection_axis_dropped": domain.projection_axis_dropped, "projection_orientation_sign": domain.projection_orientation_sign, "orientation_toward_empty": domain.orientation_toward_empty, "root_rows": domain.root_rows, "boundary_cycle": domain.boundary_cycle, "required_boundary_edges": domain.required_boundary_edges, "prohibited_edges": domain.prohibited_edges, "candidate_count": domain.candidate_count, "candidate_triplets_oriented": domain.candidate_triplets_oriented, "candidate_owner_cells": domain.candidate_owner_cells, "rejection_counts": domain.rejection_counts, "edge_rejection_counts": domain.edge_rejection_counts, "limits": domain.limits, "search_contract": domain.search_contract}
	return Core.sha256(JSON.stringify(identity).to_utf8_buffer())

func _coordinates_match(topology_roots: Array, domain_roots: Array) -> bool:
	if topology_roots.size() != domain_roots.size():
		return false
	var domain_by_id: Dictionary = {}
	for value in domain_roots:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var row: Dictionary = value
		var id: String = String(row.get("id", ""))
		if id.is_empty() or domain_by_id.has(id):
			return false
		domain_by_id[id] = row.get("xyz", [])
	for value in topology_roots:
		if not (value is Array) or value.size() < 4:
			return false
		var id: String = String(value[0])
		var xyz: Array = domain_by_id.get(id, [])
		if xyz.size() != 3:
			return false
		if absf(float(value[1]) - float(xyz[0])) > 1.0e-7 or absf(float(value[2]) - float(xyz[1])) > 1.0e-7 or absf(float(value[3]) - float(xyz[2])) > 1.0e-7:
			return false
	return true

func _degrees(roots: Array, arcs: Array, boundary: Dictionary) -> Array[Dictionary]:
	var incident: Dictionary = {}
	for root in roots:
		if root is Array and not root.is_empty():
			incident[String(root[0])] = {}
	for arc in arcs:
		if not (arc is Array) or arc.size() < 2 or not (arc[1] is Array) or arc[1].size() != 2:
			continue
		incident[String(arc[1][0])][String(arc[0])] = true
		incident[String(arc[1][1])][String(arc[0])] = true
	var ids: Array = incident.keys()
	ids.sort()
	var result: Array[Dictionary] = []
	for id in ids:
		var arc_keys: Array = incident[id].keys()
		arc_keys.sort()
		result.append({"root_id": String(id), "degree": incident[id].size(), "boundary": boundary.has(String(id)), "incident_arc_keys": arc_keys})
	return result

func _ownership_transitions(arcs: Array, polygons: Array) -> Array[Dictionary]:
	var owners_by_id: Dictionary = {}
	for polygon in polygons:
		if polygon is Array and polygon.size() > 7:
			owners_by_id[String(polygon[0])] = polygon[7]
	var result: Array[Dictionary] = []
	for arc in arcs:
		if not (arc is Array) or arc.size() < 4 or arc[3].size() < 2:
			continue
		var region_keys: Array[String] = []
		var lods: Array[float] = []
		for polygon_id in arc[3]:
			var owner: Dictionary = owners_by_id.get(String(polygon_id), {})
			region_keys.append(JSON.stringify(owner.get("region_key", [])))
			lods.append(float(owner.get("lod_step", -1.0)))
		var region_change: bool = false
		var lod_change: bool = false
		for index in range(1, region_keys.size()):
			if region_keys[index] != region_keys[0]:
				region_change = true
			if not is_equal_approx(lods[index], lods[0]):
				lod_change = true
		if region_change or lod_change:
			result.append({"arc_key": String(arc[0]), "roots": arc[1], "polygon_ids": arc[3], "region_transition": region_change, "lod_transition": lod_change, "region_keys": region_keys, "lod_steps": lods})
	return result

func _historical_a6_result(result: Dictionary, source_graph: Dictionary) -> Dictionary:
	var proof: Dictionary = result.get("source_topology_graph_proof", {})
	var valid: bool = bool(proof.get("valid", false)) and String(proof.get("topology_sha256", "")) == String(source_graph.get("topology_sha256", "")) and String(result.get("mesh_sha256", "")) == A6_MESH_SHA
	var metrics: Dictionary = result.get("metrics", {})
	var mesh_topology: Dictionary = result.get("mesh_topology", {})
	valid = valid and int(metrics.get("emitted_triangle_count", -1)) == 655 and int(mesh_topology.get("internal_open_edges", -1)) == 10 and int(result.get("required_adjacency_missing_count", -1)) == 21 and int(mesh_topology.get("nonmanifold_edges", -1)) == 0 and int(mesh_topology.get("winding_inconsistencies", -1)) == 0 and result.get("cutoff_rejections", []).size() == 7
	var patches: Array = result.get("component_reconstruction", {}).get("patches", [])
	var target_patch: Dictionary = _target_patch(patches)
	return {"valid": valid, "hypothesis": "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION", "source_topology_proof": proof, "mesh_sha256": result.get("mesh_sha256", ""), "triangle_count": metrics.get("emitted_triangle_count", -1), "mesh_topology": mesh_topology, "required_adjacency_missing_count": result.get("required_adjacency_missing_count", -1), "unresolved_obligation_count": result.get("unresolved_obligations", []).size(), "cutoff_rejection_count": result.get("cutoff_rejections", []).size(), "target_patch": target_patch, "patch_summaries": _patch_diagnostics(patches), "metrics": metrics}

func _fail(reason: String, details: Dictionary) -> void:
	var root: String = OS.get_environment("R12C_ARTIFACT_DIR")
	var attempt_id: String = OS.get_environment("R12C_ATTEMPT_ID")
	if attempt_id.is_empty():
		attempt_id = str(Time.get_ticks_usec())
	var path: String = root.path_join("r12c_stage0_failure_" + attempt_id + ".json")
	var failure: Dictionary = {"schema": "P3.1.R12C.Stage0Failure.v1", "attempt_id": attempt_id, "reason": reason, "source_sha": OS.get_environment("R12C_SOURCE_SHA"), "details": details}
	var marker_details: Dictionary = details.duplicate()
	if marker_details.has("a6") and typeof(marker_details.a6) == TYPE_DICTIONARY:
		var marker_a6: Dictionary = marker_details.a6
		marker_details["a6"] = {"valid": marker_a6.get("valid", false), "mesh_sha256": marker_a6.get("mesh_sha256", ""), "triangle_count": marker_a6.get("triangle_count", -1), "mesh_topology": marker_a6.get("mesh_topology", {}), "required_adjacency_missing_count": marker_a6.get("required_adjacency_missing_count", -1), "cutoff_rejection_count": marker_a6.get("cutoff_rejection_count", marker_a6.get("cutoff_rejections", []).size()), "target_patch": marker_a6.get("target_patch", {}), "patch_summaries": marker_a6.get("patch_summaries", [])}
	print("R12C_STAGE0_COMPLETE " + JSON.stringify({"status": "BLOCKED", "attempt_id": attempt_id, "reason": reason, "source_sha": OS.get_environment("R12C_SOURCE_SHA"), "details": marker_details}))
	if not FileAccess.file_exists(path):
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(failure))
			file.flush()
			file.close()
	quit(2)
