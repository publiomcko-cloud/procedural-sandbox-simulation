extends SceneTree

const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
const CandidateD := preload("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
const Authority := preload("res://tests/prototypes/p3_1_r10_a_topology_authority.gd")
const MANIFEST_SHA := "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972"
const CANDIDATE_D_SHA := "334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a"
const AUTHORITY_BLOB := "732f143939ac6980e1c7e77703dd7ee549206c0e"
const AUTHORITY_WORKTREE_SHA := "feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216"
const A6_HYPOTHESIS := "R10A6_INTERIOR_ROOT_EDGE_FLIP_OPTIMIZATION"
const EXPECTED_R9_7_D_MESH_SHA := "04c6ceb842b964caba4e254f94c9f4b32881dae79994b961ac01029a48f64553"
const RAY_FIXTURE_RELATIVE_PATH := "docs/reports/P3-1-R10-B-CAMPAIGN/fixtures/ray_reference_fixture_r2.json"

var _problems: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_sha: String = OS.get_environment("R10B_SOURCE_SHA")
	var source_file_sha: String = OS.get_environment("R10B_RAY_SOURCE_SHA256")
	var artifact_root: String = OS.get_environment("R10B_ARTIFACT_DIR")
	var repo_root: String = OS.get_environment("R10B_REPO_ROOT")
	var fixture_sha_expected: String = OS.get_environment("R10B_RAY_FIXTURE_SHA256")
	var manifest: Dictionary = Core.load_manifest()
	var observed_candidate_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r9_2_candidate_impl.gd")
	var observed_manifest_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r9_2_e2e_inputs.jsonl")
	var observed_authority_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r10_a_topology_authority.gd")
	var observed_source_sha: String = _sha_res_file("res://tests/prototypes/p3_1_r10_b_ray_causality.gd")
	if source_sha.length() != 40 or not source_sha.is_valid_hex_number() or artifact_root.is_empty() or not DirAccess.dir_exists_absolute(artifact_root) or repo_root.is_empty() or not DirAccess.dir_exists_absolute(repo_root):
		_emit_blocked("source_or_artifact_identity_invalid", {"source_sha": source_sha, "artifact_root": artifact_root, "repo_root": repo_root})
		return
	if observed_candidate_sha != CANDIDATE_D_SHA or observed_manifest_sha != MANIFEST_SHA or observed_authority_sha != AUTHORITY_WORKTREE_SHA:
		_emit_blocked("frozen_source_pin_mismatch", {"candidate_d": observed_candidate_sha, "manifest": observed_manifest_sha, "authority": observed_authority_sha})
		return
	if observed_source_sha != source_file_sha or not bool(manifest.get("valid", false)) or String(manifest.get("sha256", "")) != MANIFEST_SHA:
		_emit_blocked("r10b_source_or_manifest_pin_mismatch", {"ray_source": observed_source_sha, "expected_ray_source": source_file_sha, "manifest_reason": manifest.get("reason", ""), "manifest_sha": manifest.get("sha256", "")})
		return
	var fixture_path: String = repo_root.path_join(RAY_FIXTURE_RELATIVE_PATH)
	var fixture_file: FileAccess = FileAccess.open(fixture_path, FileAccess.READ)
	if fixture_file == null:
		_emit_blocked("ray_reference_fixture_open_failed", {"fixture_path": fixture_path})
		return
	var fixture_bytes: PackedByteArray = fixture_file.get_buffer(fixture_file.get_length())
	fixture_file.close()
	if Core.sha256(fixture_bytes) != fixture_sha_expected:
		_emit_blocked("ray_reference_fixture_sha_mismatch", {"observed": Core.sha256(fixture_bytes), "expected": fixture_sha_expected})
		return
	var fixture_parse: Variant = JSON.parse_string(fixture_bytes.get_string_from_utf8())
	if not fixture_parse is Dictionary or String(fixture_parse.get("scenario_id", "")) != "R9.2.RAY.CANONICAL_PICKER.v1":
		_emit_blocked("ray_reference_fixture_schema_invalid", {})
		return
	var fixture: Dictionary = fixture_parse
	var historical_d0: Dictionary = fixture.get("historical_r9_7", {})
	var historical_indices: Array = historical_d0.get("full_ray_finite_scan_disagreement_indices", [])
	var expected_historical_indices: Array[int] = [2, 8, 9, 13, 14, 18, 19, 23, 24]
	var indices_match: bool = historical_indices.size() == expected_historical_indices.size()
	if indices_match:
		for index in range(expected_historical_indices.size()):
			if not (historical_indices[index] is float or historical_indices[index] is int):
				indices_match = false
				break
			if float(historical_indices[index]) != float(expected_historical_indices[index]):
				indices_match = false
				break
	var historical_rows: Array = historical_d0.get("roi_scoped_ray_records", [])
	var historical_record_valid: bool = int(historical_d0.get("recorded_ray_count", -1)) == 25 and int(historical_d0.get("roi_scoped_hit_miss_disagreements", -1)) == 0 and int(historical_d0.get("full_ray_finite_scan_hit_miss_disagreements", -1)) == 9 and indices_match and historical_rows.size() == 25 and String(historical_d0.get("candidate_mesh_sha256", "")) == EXPECTED_R9_7_D_MESH_SHA
	if not historical_record_valid:
		_emit_blocked("historical_r9_7_ray_scope_record_invalid", {"recorded_ray_count": historical_d0.get("recorded_ray_count"), "roi_mismatches": historical_d0.get("roi_scoped_hit_miss_disagreements"), "global_mismatches": historical_d0.get("full_ray_finite_scan_hit_miss_disagreements"), "observed_indices": historical_indices, "indices_match": indices_match, "roi_record_count": historical_rows.size(), "candidate_mesh_sha256": historical_d0.get("candidate_mesh_sha256")})
		return
	var row: Dictionary = Core.case_by_id(manifest.get("rows", []), "R9.2.RAY.CANONICAL_PICKER.v1")
	if row.is_empty():
		_emit_blocked("frozen_ray_row_missing", {})
		return
	var setup: Dictionary = Core.make_snapshot(row)
	if not bool(setup.get("valid", false)):
		_emit_blocked("zero_edit_snapshot_creation_failed", {"detail": setup})
		return
	var snapshot: Dictionary = setup.get("snapshot", {})
	var rays: Array[Dictionary] = Core.ray_grid(row.roi, row.ray_grid)
	if rays.size() != 25:
		_emit_blocked("frozen_ray_count_mismatch", {"count": rays.size()})
		return

	var candidate: RefCounted = CandidateD.new()
	candidate.call("configure_roi", row.roi)
	var candidate_result: Dictionary = candidate.call("build", snapshot, row, {})
	if not bool(candidate_result.get("valid", false)):
		_emit_blocked("candidate_d_ray_case_build_failed", {"detail": candidate_result.get("reason", "unknown")})
		return
	var candidate_mesh: Dictionary = candidate_result.get("mesh", Core.new_mesh())
	var candidate_mesh_sha: String = String(candidate_result.get("mesh_sha256", ""))
	if candidate_mesh_sha != EXPECTED_R9_7_D_MESH_SHA:
		_emit_blocked("candidate_d_mesh_differs_from_historical_r9_7_artifact", {"observed": candidate_mesh_sha, "expected": EXPECTED_R9_7_D_MESH_SHA})
		return
	var candidate_maps: Dictionary = _candidate_root_and_polygon_maps(candidate, candidate_result.get("volume", {}).get("values", PackedFloat32Array()), row.roi)
	if not bool(candidate_maps.get("valid", false)):
		_emit_blocked("candidate_root_polygon_mapping_failed", candidate_maps)
		return
	var candidate_meta: Array[Dictionary] = _candidate_triangle_metadata(candidate_mesh, candidate_maps)
	if candidate_meta.size() != int(candidate_mesh.get("positions", PackedVector3Array()).size() / 3):
		_emit_blocked("candidate_triangle_root_mapping_incomplete", {"metadata_count": candidate_meta.size(), "triangle_count": int(candidate_mesh.get("positions", PackedVector3Array()).size() / 3)})
		return
	for metadata in candidate_meta:
		if metadata.get("source_polygon_ids", []).is_empty() or String(metadata.get("component_id", "")) == "UNMAPPED_COMPONENT":
			_emit_blocked("candidate_triangle_source_provenance_incomplete", metadata)
			return
	var d3: Dictionary = _compare_all_rays(rays, candidate_mesh, candidate_meta, snapshot, int(row.get("seed", 131102026)), row.roi, "RAY-D3_CANDIDATE_D_PRE_R10")
	var d0: Dictionary = {
		"source": "R9.7 closeout plus preserved D3.5 Candidate D artifact",
		"roi_scoped_hit_miss_disagreements": historical_d0.get("roi_scoped_hit_miss_disagreements"),
		"full_ray_finite_scan_hit_miss_disagreements": historical_d0.get("full_ray_finite_scan_hit_miss_disagreements"),
		"full_ray_disagreement_indices": historical_d0.get("full_ray_finite_scan_disagreement_indices", []),
		"reported_ray_count": historical_d0.get("recorded_ray_count"),
		"raw_per_ray_outcomes_available": historical_d0.get("raw_per_ray_outcomes_available"),
		"raw_candidate_artifact_sha256": historical_d0.get("raw_candidate_artifact_sha256"),
		"historical_mesh_sha256": historical_d0.get("candidate_mesh_sha256"),
		"historical_claim_grade": "RAW_STDOUT_PER_RAY_ROWS_AND_TWO_SEPARATE_SCOPE_SUMMARIES",
		"roi_scoped_ray_records": historical_d0.get("roi_scoped_ray_records", []),
		"replay": d3,
	}

	var authority: RefCounted = Authority.new()
	authority.call("configure_roi", row.roi)
	var volume: Dictionary = candidate_result.get("volume", {})
	var volume_payload_sha: String = String(candidate_result.get("metrics", {}).get("volume", {}).get("payload_sha256", ""))
	var values: PackedFloat32Array = volume.get("values", PackedFloat32Array())
	var a6: Dictionary = authority.call("realize_topology", values, A6_HYPOTHESIS, snapshot, int(row.get("seed", 131102026)))
	if not bool(a6.get("valid", false)):
		_emit_blocked("a6_ray_geometry_reproduction_execution_invalid", {"reason": a6.get("reason", ""), "geometry": _a6_geometry_summary(a6)})
		return
	var a6_mesh: Dictionary = a6.get("mesh", Core.new_mesh())
	var d1_reference: Dictionary = fixture.get("r10a_a6", {})
	if String(a6.get("mesh_sha256", "")) != String(d1_reference.get("mesh_sha256", "")):
		_emit_blocked("a6_mesh_hash_not_reproducible_from_frozen_source", {"observed": a6.get("mesh_sha256", ""), "expected": d1_reference.get("mesh_sha256", "")})
		return
	if String(volume.get("sha256", "")) != String(d1_reference.get("volume_sha256", "")) or volume_payload_sha != String(d1_reference.get("payload_sha256", "")):
		_emit_blocked("a6_candidate_d_volume_not_reproducible", {"observed_volume": volume.get("sha256", ""), "expected_volume": d1_reference.get("volume_sha256", ""), "observed_payload": volume_payload_sha, "expected_payload": d1_reference.get("payload_sha256", "")})
		return
	var a6_meta: Array[Dictionary] = _a6_triangle_metadata(a6)
	if a6_meta.size() != int(a6_mesh.get("positions", PackedVector3Array()).size() / 3):
		_emit_blocked("a6_triangle_metadata_count_mismatch", {"metadata_count": a6_meta.size(), "triangle_count": int(a6_mesh.get("positions", PackedVector3Array()).size() / 3)})
		return
	var d1: Dictionary = _compare_all_rays(rays, a6_mesh, a6_meta, snapshot, int(row.get("seed", 131102026)), row.roi, "RAY-D1_R10A6_FINAL_EMITTED")
	var historical_d1_outcomes: Array = d1_reference.get("ray_outcomes", [])
	var d1_outcome_match: bool = _outcomes_match(d1, historical_d1_outcomes)
	var historical_d0_records: Array = fixture.get("historical_r9_7", {}).get("roi_scoped_ray_records", [])
	var d0_roi_outcome_match: bool = _outcomes_match_r97_roi(d3, historical_d0_records)
	var unresolved_source_ids: Dictionary = {}
	for raw_patch in a6.get("component_reconstruction", {}).get("patches", []):
		var source_patch: Dictionary = raw_patch
		if String(source_patch.get("status", "")) == "UNRESOLVED":
			for polygon_id in source_patch.get("source_polygon_ids", []): unresolved_source_ids[String(polygon_id)] = true
	_annotate_unresolved_ray_hits(d1, unresolved_source_ids)

	var d2_mesh: Dictionary = a6_mesh.duplicate(true)
	var d2_meta: Array[Dictionary] = []
	var d2_positions: PackedVector3Array = PackedVector3Array()
	var d2_normals: PackedVector3Array = PackedVector3Array()
	var d2_replaced_partial_triangle_count: int = 0
	var a6_positions: PackedVector3Array = a6_mesh.get("positions", PackedVector3Array())
	var a6_normals: PackedVector3Array = a6_mesh.get("normals", PackedVector3Array())
	for triangle_index in range(a6_meta.size()):
		var triangle_meta: Dictionary = a6_meta[triangle_index]
		var remove_for_complete_patch: bool = false
		for polygon_id in triangle_meta.get("source_polygon_ids", []):
			if unresolved_source_ids.has(String(polygon_id)):
				remove_for_complete_patch = true
				break
		if remove_for_complete_patch:
			d2_replaced_partial_triangle_count += 1
			continue
		var position_start: int = triangle_index * 3
		for vertex_offset in range(3):
			d2_positions.append(a6_positions[position_start + vertex_offset])
			if a6_normals.size() == a6_positions.size(): d2_normals.append(a6_normals[position_start + vertex_offset])
		d2_meta.append(triangle_meta.duplicate(true))
	d2_mesh["positions"] = d2_positions
	d2_mesh["normals"] = d2_normals
	var unresolved_patch_summaries: Array[Dictionary] = []
	var component_reconstruction: Dictionary = a6.get("component_reconstruction", {})
	for raw_patch in component_reconstruction.get("patches", []):
		var patch: Dictionary = raw_patch
		if String(patch.get("status", "")) != "UNRESOLVED":
			continue
		var triangulation: Dictionary = patch.get("triangulation", {})
		var patch_triangles: Array = triangulation.get("triangles", [])
		var added: int = 0
		for raw_triangle in patch_triangles:
			var triangle: Dictionary = raw_triangle
			var points: Array = triangle.get("points", [])
			var root_ids: Array = triangle.get("root_ids", [])
			if points.size() != 3 or root_ids.size() != 3:
				_emit_blocked("a6_diagnostic_patch_triangle_invalid", {"component_id": patch.get("component_id", ""), "triangle": triangle})
				return
			var a: Vector3 = points[0]
			var b: Vector3 = points[1]
			var c: Vector3 = points[2]
			var cross: Vector3 = (b - a).cross(c - a)
			var normal: Vector3 = cross.normalized() if cross.length_squared() > 0.0 else Vector3.ZERO
			var positions: PackedVector3Array = d2_mesh.get("positions", PackedVector3Array())
			var normals: PackedVector3Array = d2_mesh.get("normals", PackedVector3Array())
			var start: int = int(positions.size() / 3)
			positions.append(a); positions.append(b); positions.append(c)
			normals.append(normal); normals.append(normal); normals.append(normal)
			d2_mesh["positions"] = positions
			d2_mesh["normals"] = normals
			d2_meta.append({"triangle_index": start, "root_ids": root_ids.duplicate(), "source_polygon_ids": patch.get("source_polygon_ids", []).duplicate(), "patch_id": String(patch.get("component_id", "")), "construction": "DIAGNOSTIC_ONLY_SUBCUTOFF_GEOMETRY_NOT_QUALIFIED", "cross_squared": cross.length_squared()})
			added += 1
		unresolved_patch_summaries.append({"component_id": patch.get("component_id", ""), "source_polygon_ids": patch.get("source_polygon_ids", []), "triangles_added": added, "subcutoff": triangulation.get("remaining_subcutoff_triangles", [])})
	var d2: Dictionary = _compare_all_rays(rays, d2_mesh, d2_meta, snapshot, int(row.get("seed", 131102026)), row.roi, "RAY-D2_DIAGNOSTIC_ONLY_SUBCUTOFF_GEOMETRY_NOT_QUALIFIED")
	_annotate_unresolved_ray_hits(d2, unresolved_source_ids)
	d2["unresolved_patch_summaries"] = unresolved_patch_summaries
	d2["replaced_partial_unresolved_triangle_count"] = d2_replaced_partial_triangle_count
	d2["qualification_status"] = "DIAGNOSTIC_ONLY_SUBCUTOFF_GEOMETRY_NOT_QUALIFIED"

	var classification: String = _classify_ray_regression(d1, d2, d3)
	var summary: Dictionary = {
		"schema": "P3.1.R10B.RayCausalityResult.v1", "source_sha": source_sha,
		"source_physical_hashes": {"ray_script": observed_source_sha, "candidate_d": observed_candidate_sha, "manifest": observed_manifest_sha, "r10a_authority": observed_authority_sha},
		"source_blobs": {"r10a_topology_authority": AUTHORITY_BLOB},
		"manifest_sha256": MANIFEST_SHA, "ray_fixture_sha256": fixture_sha_expected,
		"godot": Engine.get_version_info(), "cutoff_squared": 1.0e-12,
		"volume": {"sha256": volume.get("sha256", ""), "payload_sha256": volume_payload_sha, "revision": volume.get("revision", -1), "identity_preserved": volume.get("sha256", "") == Core.sha256(volume.get("bytes", PackedByteArray())) and volume.get("sha256", "") == candidate_result.get("metrics", {}).get("persisted_reloaded_volume_sha256", "")},
		"historical_r9_7_D0": d0,
		"RAY_D3_candidate_D_replay": d3,
		"RAY_D1_a6_final_emitted": d1,
		"RAY_D1_outcome_match_to_preserved_R10A": d1_outcome_match,
		"RAY_D2_diagnostic_complete_component": d2,
		"classification": classification,
		"ray_geometry_mesh_hashes": {"D3_candidate_D": candidate_mesh_sha, "D1_A6": a6.get("mesh_sha256", ""), "D2_diagnostic": _mesh_sha(d2_mesh)},
		"historical_R9_7_candidate_artifact_mesh_sha256": fixture.get("historical_r9_7", {}).get("candidate_mesh_sha256", ""),
		"historical_R9_7_roi_scoped_mismatches": fixture.get("historical_r9_7", {}).get("roi_scoped_hit_miss_disagreements", -1),
		"historical_R9_7_full_ray_legacy_mismatches": fixture.get("historical_r9_7", {}).get("full_ray_finite_scan_hit_miss_disagreements", -1),
		"RAY_D0_historical_roi_outcomes_match_D3_replay": d0_roi_outcome_match,
		"R10A6_expected_mesh_sha256": d1_reference.get("mesh_sha256", ""),
		"target_gate": "ray causality only; does not qualify geometry",
	}
	for ray_result in [d3, d1, d2]:
		if not bool(ray_result.get("custom_first_hit_matches_core_hit_map", false)):
			_problems.append(String(ray_result.get("label", "ray")) + "_custom_ray_intersection_differs_from_core_oracle")
	if not bool(summary.volume.identity_preserved):
		_problems.append("volume_identity_not_preserved")
	if not _write_json_no_overwrite(artifact_root.path_join("ray_causality.json"), summary):
		_problems.append("ray_artifact_write_failed")
	if not d1_outcome_match: _problems.append("R10A6_full_ray_outcomes_differ_from_exact_source_replay")
	if not d0_roi_outcome_match: _problems.append("R9_7_roi_scoped_outcomes_differ_from_D3_candidate_replay")
	print("R10B_RAY_DIAGNOSTIC_COMPLETE " + JSON.stringify({"status": "PASS" if _problems.is_empty() else "DIAGNOSTIC_MISMATCH", "source_sha": source_sha, "classification": classification, "D0_roi_scoped": d0.get("roi_scoped_hit_miss_disagreements", -1), "D0_full_ray_legacy": d0.get("full_ray_finite_scan_hit_miss_disagreements", -1), "D3_roi_scoped": d3.roi_scoped_hit_miss_disagreements, "D3_full_ray": d3.global_full_ray_hit_miss_disagreements, "D1_roi_scoped": d1.roi_scoped_hit_miss_disagreements, "D1_full_ray": d1.global_full_ray_hit_miss_disagreements, "D2_roi_scoped": d2.roi_scoped_hit_miss_disagreements, "D2_full_ray": d2.global_full_ray_hit_miss_disagreements, "D0_roi_outcomes_match_D3": d0_roi_outcome_match, "D1_historical_full_outcomes_match": d1_outcome_match, "D1_mesh_sha": a6.get("mesh_sha256", ""), "D3_mesh_sha": candidate_mesh_sha, "failures": _problems}))
	quit(0 if _problems.is_empty() else 4)

func _a6_geometry_summary(geometry: Dictionary) -> Dictionary:
	return {"reason": geometry.get("reason", ""), "valid": geometry.get("valid", false), "mesh_sha256": geometry.get("mesh_sha256", ""), "mesh_topology": geometry.get("mesh_topology", {}), "required_adjacency_missing_count": geometry.get("required_adjacency_missing_count", -1), "component_reconstruction": geometry.get("component_reconstruction", {}).get("reason", "")}

func _a6_triangle_metadata(geometry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rows: Array = geometry.get("emitted_triangles", [])
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var patch_id: String = String(row.get("patch_id", ""))
		result.append({"triangle_index": index, "root_ids": row.get("root_ids", []), "source_polygon_ids": row.get("source_polygon_ids", []), "patch_id": patch_id, "component_id": String(row.get("component_id", patch_id)), "construction": row.get("construction", ""), "cross_squared": row.get("cross_squared", null)})
	return result

func _candidate_root_and_polygon_maps(candidate: RefCounted, values: PackedFloat32Array, roi: Dictionary) -> Dictionary:
	var min_point: Vector3 = Core.world_min(roi)
	var cells: Vector3i = Core.cell_counts(roi)
	var step: float = Core.step(roi)
	var dims: Vector3i = cells + Vector3i.ONE
	var root_by_point: Dictionary = {}
	var polygons_by_root: Dictionary = {}
	var cache: Dictionary = {}
	var edge_pairs: Array[Vector2i] = [Vector2i(0,1), Vector2i(0,2), Vector2i(0,3), Vector2i(1,2), Vector2i(1,3), Vector2i(2,3)]
	for y in range(cells.y):
		for z in range(cells.z):
			for x in range(cells.x):
				var cell: Vector3i = Vector3i(x, y, z)
				for tet_index in range(Core.TETS.size()):
					var tet: Array = Core.TETS[tet_index]
					var polygon_roots: Dictionary = {}
					for edge in edge_pairs:
						var ia: int = int(tet[edge.x]); var ib: int = int(tet[edge.y])
						var node_a: Vector3i = cell + Core.GRID_CORNERS[ia]
						var node_b: Vector3i = cell + Core.GRID_CORNERS[ib]
						var va: float = float(values[Core._grid_index(node_a.x, node_a.y, node_a.z, dims)])
						var vb: float = float(values[Core._grid_index(node_b.x, node_b.y, node_b.z, dims)])
						if (va >= 0.0) == (vb >= 0.0): continue
						var pa: Vector3 = min_point + Vector3(node_a) * step
						var pb: Vector3 = min_point + Vector3(node_b) * step
						var root: Dictionary = candidate.call("_canonical_volume_root", cache, node_a, node_b, va, vb, pa, pb)
						if not bool(root.get("valid", false)): continue
						var root_id: String = String(root.root_identity)
						root_by_point[_point_key(root.point)] = root_id
						polygon_roots[root_id] = true
					if polygon_roots.size() >= 3:
						var polygon_id: String = "cell:%d,%d,%d|tet:%d" % [x, y, z, tet_index]
						for root_id in polygon_roots.keys():
							if not polygons_by_root.has(String(root_id)): polygons_by_root[String(root_id)] = []
							polygons_by_root[String(root_id)].append(polygon_id)
	return {"valid": true, "root_ids_by_point": root_by_point, "source_polygons_by_root": polygons_by_root}

func _candidate_triangle_metadata(mesh: Dictionary, maps: Dictionary) -> Array[Dictionary]:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var root_map: Dictionary = maps.get("root_ids_by_point", {})
	var polygon_index: Dictionary = maps.get("source_polygons_by_root", {})
	var components: Array[String] = _mesh_component_ids(mesh)
	var result: Array[Dictionary] = []
	for index in range(0, positions.size(), 3):
		var ids: Array[String] = []
		for offset in range(3):
			var key: String = _point_key(positions[index + offset])
			ids.append(String(root_map.get(key, "UNMAPPED:" + key)))
		var possible: Dictionary = {}
		if not ids.is_empty():
			for polygon_id in polygon_index.get(ids[0], []): possible[String(polygon_id)] = true
			for root_id in ids.slice(1):
				var root_polygons: Dictionary = {}
				for polygon_id in polygon_index.get(root_id, []): root_polygons[String(polygon_id)] = true
				for polygon_id in possible.keys():
					if not root_polygons.has(String(polygon_id)): possible.erase(polygon_id)
		var source_polygon_ids: Array = possible.keys()
		source_polygon_ids.sort()
		result.append({"triangle_index": int(index / 3), "root_ids": ids, "source_polygon_ids": source_polygon_ids, "patch_id": "", "component_id": components[int(index / 3)] if int(index / 3) < components.size() else "UNMAPPED_COMPONENT", "construction": "CANDIDATE_D_MATERIALIZED_VOLUME"})
	return result

func _mesh_component_ids(mesh: Dictionary) -> Array[String]:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var triangle_count: int = int(positions.size() / 3)
	var parent: Array[int] = []
	for triangle_id in range(triangle_count): parent.append(triangle_id)
	var edge_owner: Dictionary = {}
	for triangle_id in range(triangle_count):
		var base: int = triangle_id * 3
		for pair in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 0)]:
			var key_a: String = _point_key(positions[base + pair.x])
			var key_b: String = _point_key(positions[base + pair.y])
			var edge_key: String = key_a + "|" + key_b if key_a < key_b else key_b + "|" + key_a
			if edge_owner.has(edge_key): _union(parent, triangle_id, int(edge_owner[edge_key]))
			else: edge_owner[edge_key] = triangle_id
	var minimum_triangle_by_root: Dictionary = {}
	for triangle_id in range(triangle_count):
		var root: int = _find_root(parent, triangle_id)
		minimum_triangle_by_root[root] = mini(int(minimum_triangle_by_root.get(root, triangle_id)), triangle_id)
	var result: Array[String] = []
	for triangle_id in range(triangle_count):
		var root: int = _find_root(parent, triangle_id)
		result.append("mesh_component_tri:%d" % int(minimum_triangle_by_root[root]))
	return result

func _find_root(parent: Array[int], value: int) -> int:
	var current: int = value
	while parent[current] != current: current = parent[current]
	while parent[value] != value:
		var next_value: int = parent[value]
		parent[value] = current
		value = next_value
	return current

func _union(parent: Array[int], left: int, right: int) -> void:
	var root_left: int = _find_root(parent, left)
	var root_right: int = _find_root(parent, right)
	if root_left == root_right: return
	if root_left < root_right: parent[root_right] = root_left
	else: parent[root_left] = root_right

func _compare_all_rays(rays: Array[Dictionary], mesh: Dictionary, triangle_meta: Array[Dictionary], snapshot: Dictionary, seed: int, roi: Dictionary, label: String) -> Dictionary:
	var rows: Array[Dictionary] = []
	var roi_mismatch_count: int = 0
	var global_mismatch_count: int = 0
	var position_error_abs: Array[float] = []
	for ray_index in range(rays.size()):
		var ray: Dictionary = rays[ray_index]
		var origin: Vector3 = ray.origin
		var direction: Vector3 = ray.direction.normalized()
		var max_distance: float = float(ray.length)
		var canonical: Dictionary = Core.canonical_ray_roots(origin, direction, max_distance, snapshot, seed, 256, 32)
		var first_hit: Dictionary = _first_mesh_hit(origin, direction, max_distance, mesh, triangle_meta)
		if not bool(canonical.get("valid", false)):
			return {"valid": false, "reason": "canonical_ray_failed", "ray_index": ray_index}
		var roots: Array = canonical.get("roots", [])
		var reference_hit: bool = not roots.is_empty()
		var roi_roots: Array[Dictionary] = _roots_inside_roi_excluding_ray_end_faces(roots, roi)
		var roi_reference_hit: bool = not roi_roots.is_empty()
		var mesh_hit: bool = bool(first_hit.get("hit", false))
		var global_disagreement: bool = reference_hit != mesh_hit
		var roi_disagreement: bool = roi_reference_hit != mesh_hit
		if global_disagreement: global_mismatch_count += 1
		if roi_disagreement: roi_mismatch_count += 1
		if roi_reference_hit and mesh_hit:
			var nearest_roi_root_distance: float = INF
			for roi_root in roi_roots: nearest_roi_root_distance = minf(nearest_roi_root_distance, absf(float(first_hit.distance) - float(roi_root.distance)))
			position_error_abs.append(nearest_roi_root_distance)
		var density_at_hit: Variant = null
		var nearest_root_distance: Variant = null
		if mesh_hit:
			var hit_position: Vector3 = first_hit.position
			density_at_hit = Core.sample(hit_position, snapshot, seed)
			var nearest: float = INF
			for root in roots: nearest = minf(nearest, hit_position.distance_to(root.position))
			nearest_root_distance = nearest if nearest < INF else null
		rows.append({"ray_index": ray_index, "origin": [origin.x, origin.y, origin.z], "direction": [direction.x, direction.y, direction.z], "length": max_distance,
			"canonical_hit": reference_hit, "canonical_global_roots": roots.map(func(r: Dictionary) -> Dictionary: return {"distance": r.distance, "position": [r.position.x, r.position.y, r.position.z]}),
			"canonical_roi_roots": roi_roots.map(func(r: Dictionary) -> Dictionary: return {"distance": r.distance, "position": [r.position.x, r.position.y, r.position.z]}), "canonical_roi_hit": roi_reference_hit,
			"mesh_hit": mesh_hit, "mesh_hit_count": first_hit.get("hit_count", 0), "first_hit_triangle": first_hit.get("triangle_index", -1),
			"first_hit_distance": first_hit.get("distance", null), "first_hit_position": first_hit.get("position_array", []), "triangle_root_ids": first_hit.get("root_ids", []),
			"triangle_component_id": first_hit.get("component_id", -1), "source_polygon_ids": first_hit.get("source_polygon_ids", []), "patch_id": first_hit.get("patch_id", ""),
			"construction": first_hit.get("construction", ""), "canonical_density_at_mesh_hit": density_at_hit,
			"distance_to_nearest_canonical_roi_ray_root": nearest_root_distance,
			"global_full_ray_hit_miss_disagreement": global_disagreement,
			"roi_scoped_hit_miss_disagreement": roi_disagreement,
			"hit_miss_disagreement": roi_disagreement})
	position_error_abs.sort()
	var oracle_summary: Dictionary = Core.compare_mesh_rays(rays, mesh, snapshot, seed, 256)
	var oracle_rows: Array = oracle_summary.get("rays", [])
	var oracle_match: bool = bool(oracle_summary.get("valid", false)) and int(oracle_summary.get("ray_count", -1)) == rows.size() and int(oracle_summary.get("hit_miss_disagreements", -2)) == global_mismatch_count and oracle_rows.size() == rows.size()
	for ray_index in range(mini(rows.size(), oracle_rows.size())):
		var observed_row: Dictionary = rows[ray_index]
		var oracle_row: Dictionary = oracle_rows[ray_index]
		var same_hit: bool = bool(observed_row.get("mesh_hit", false)) == bool(oracle_row.get("mesh_hit", false))
		var actual_distance: Variant = observed_row.get("first_hit_distance")
		var expected_distance: Variant = oracle_row.get("mesh_distance")
		var same_distance: bool = (actual_distance == null and expected_distance == null) or (actual_distance != null and expected_distance != null and float(actual_distance) == float(expected_distance))
		observed_row["core_oracle_mesh_hit"] = oracle_row.get("mesh_hit", false)
		observed_row["core_oracle_first_distance"] = expected_distance
		observed_row["custom_core_distance_delta"] = float(actual_distance) - float(expected_distance) if actual_distance != null and expected_distance != null else null
		observed_row["custom_first_hit_matches_core"] = same_hit and same_distance
		if not same_hit or not same_distance: oracle_match = false
	return {"valid": true, "label": label, "ray_count": rows.size(), "hit_miss_disagreements": roi_mismatch_count, "roi_scoped_hit_miss_disagreements": roi_mismatch_count, "global_full_ray_hit_miss_disagreements": global_mismatch_count,
		"position_error_count": position_error_abs.size(), "position_error_abs_p50": _percentile(position_error_abs, 0.50),
		"position_error_abs_p95": _percentile(position_error_abs, 0.95), "position_error_abs_max": position_error_abs.back() if not position_error_abs.is_empty() else null,
		"rays": rows, "core_oracle_summary": oracle_summary, "custom_first_hit_matches_core_hit_map": oracle_match,
		"completeness": "two explicitly separate scopes: full finite 256-step global root scan and ROI-filtered roots excluding Y end-face crop; both inherit finite-scan tangent/sub-step limitations"}

func _roots_inside_roi_excluding_ray_end_faces(roots: Array, roi: Dictionary) -> Array[Dictionary]:
	var minimum: Vector3 = Core.world_min(roi)
	var maximum: Vector3 = minimum + Vector3(Core.cell_counts(roi)) * Core.step(roi)
	var result: Array[Dictionary] = []
	for raw_root in roots:
		var root: Dictionary = raw_root
		var position: Vector3 = root.get("position", Vector3.INF)
		var inside: bool = position.x >= minimum.x - 1.0e-6 and position.x <= maximum.x + 1.0e-6 and position.y >= minimum.y - 1.0e-6 and position.y <= maximum.y + 1.0e-6 and position.z >= minimum.z - 1.0e-6 and position.z <= maximum.z + 1.0e-6
		if not inside: continue
		if absf(position.y - minimum.y) <= 1.0e-6 or absf(position.y - maximum.y) <= 1.0e-6: continue
		result.append(root)
	return result

func _outcomes_match_r97_roi(actual: Dictionary, expected: Array) -> bool:
	if expected.size() != 25 or actual.get("rays", []).size() != 25: return false
	for index in range(25):
		var actual_row: Dictionary = actual.rays[index]
		var expected_row: Dictionary = expected[index]
		if int(actual_row.get("ray_index", -1)) != index or int(expected_row.get("ray_index", -1)) != index: return false
		if bool(expected_row.get("roi_hit_miss_disagrees", true)): return false
		var expected_roi_hit: bool = not expected_row.get("canonical_roots_in_closed_roi_excluding_y_end_faces", []).is_empty()
		if bool(actual_row.get("canonical_roi_hit", false)) != expected_roi_hit or bool(actual_row.get("mesh_hit", false)) != bool(expected_row.get("mesh_two_sided", {}).get("hit", false)):
			return false
	return true

func _first_mesh_hit(origin: Vector3, direction: Vector3, max_distance: float, mesh: Dictionary, meta: Array[Dictionary]) -> Dictionary:
	var positions: PackedVector3Array = mesh.get("positions", PackedVector3Array())
	var best: float = INF
	var best_index: int = -1
	var hit_count: int = 0
	for index in range(0, positions.size(), 3):
		var distance: float = _ray_triangle(origin, direction, positions[index], positions[index + 1], positions[index + 2])
		if distance < 0.0 or distance > max_distance: continue
		hit_count += 1
		if distance < best:
			best = distance
			best_index = int(index / 3)
	if best_index < 0: return {"hit": false, "hit_count": hit_count}
	var triangle: Dictionary = meta[best_index] if best_index < meta.size() else {}
	var hit_position: Vector3 = origin + direction * best
	return {"hit": true, "hit_count": hit_count, "triangle_index": best_index, "distance": best,
		"position": hit_position, "position_array": [hit_position.x, hit_position.y, hit_position.z],
		"root_ids": triangle.get("root_ids", []), "source_polygon_ids": triangle.get("source_polygon_ids", []),
		"patch_id": triangle.get("patch_id", ""), "construction": triangle.get("construction", ""),
		"component_id": triangle.get("component_id", -1)}

func _ray_triangle(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var edge1: Vector3 = b - a
	var edge2: Vector3 = c - a
	var h: Vector3 = direction.cross(edge2)
	var determinant: float = edge1.dot(h)
	if absf(determinant) < 1.0e-10: return -1.0
	var inverse: float = 1.0 / determinant
	var s: Vector3 = origin - a
	var u: float = inverse * s.dot(h)
	if u < 0.0 or u > 1.0: return -1.0
	var q: Vector3 = s.cross(edge1)
	var v: float = inverse * direction.dot(q)
	if v < 0.0 or u + v > 1.0: return -1.0
	var t: float = inverse * edge2.dot(q)
	return t if t >= 0.0 else -1.0

func _point_key(point: Vector3) -> String:
	return PackedVector3Array([point]).to_byte_array().hex_encode()

func _mesh_sha(mesh: Dictionary) -> String:
	var positions: PackedByteArray = mesh.get("positions", PackedVector3Array()).to_byte_array()
	var normals: PackedByteArray = mesh.get("normals", PackedVector3Array()).to_byte_array()
	var hash_context: HashingContext = HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(("%d:%d:" % [positions.size(), normals.size()]).to_utf8_buffer())
	if not positions.is_empty(): hash_context.update(positions)
	if not normals.is_empty(): hash_context.update(normals)
	return hash_context.finish().hex_encode()

func _outcomes_match(actual: Dictionary, expected: Array) -> bool:
	if expected.size() != 25 or actual.get("rays", []).size() != 25: return false
	for index in range(25):
		var actual_row: Dictionary = actual.rays[index]
		var expected_row: Dictionary = expected[index]
		if bool(actual_row.get("canonical_hit", false)) != bool(expected_row.get("reference_hit", false)) or bool(actual_row.get("mesh_hit", false)) != bool(expected_row.get("mesh_hit", false)): return false
		var expected_distance: Variant = expected_row.get("mesh_distance")
		var actual_distance: Variant = actual_row.get("first_hit_distance")
		if expected_distance == null and actual_distance != null: return false
		if expected_distance != null and (actual_distance == null or absf(float(expected_distance) - float(actual_distance)) > 1.0e-6): return false
	return true

func _classify_ray_regression(d1: Dictionary, d2: Dictionary, d3: Dictionary) -> String:
	if not bool(d1.get("valid", false)) or not bool(d2.get("valid", false)) or not bool(d3.get("valid", false)): return "RAY_REGRESSION_CAUSE_UNRESOLVED"
	if int(d1.get("roi_scoped_hit_miss_disagreements", -1)) == 0 and int(d3.get("roi_scoped_hit_miss_disagreements", -1)) == 0:
		if int(d1.get("global_full_ray_hit_miss_disagreements", -1)) > 0 and int(d3.get("global_full_ray_hit_miss_disagreements", -1)) > 0:
			return "RAY_SCOPE_DIFFERENCE_CONFIRMED_ROI_CROPPING_EXPLAINS_GLOBAL_MISMATCHES"
		return "RAY_REGRESSION_NOT_REPRODUCED"
	var d1_rows: Array = d1.get("rays", [])
	var d2_rows: Array = d2.get("rays", [])
	var d3_rows: Array = d3.get("rays", [])
	var d1_unresolved_hits: int = 0
	var d1_resolved_by_d2: int = 0
	for index in range(mini(d1_rows.size(), d2_rows.size())):
		var one: Dictionary = d1_rows[index]; var two: Dictionary = d2_rows[index]
		if not bool(one.get("hit_miss_disagreement", false)): continue
		if bool(one.get("patch_involved", false)): d1_unresolved_hits += 1
		if bool(two.get("canonical_roi_hit", false)) == bool(two.get("mesh_hit", false)): d1_resolved_by_d2 += 1
	if d1_resolved_by_d2 == int(d1.get("hit_miss_disagreements", -1)) and d1_resolved_by_d2 > 0: return "RAY_REGRESSION_CAUSED_BY_UNEMITTED_TOPOLOGY"
	if d1_resolved_by_d2 > 0: return "RAY_REGRESSION_MULTICAUSAL"
	if d1_unresolved_hits == 0 and _same_hit_map(d1_rows, d3_rows): return "RAY_REGRESSION_OUTSIDE_A6_UNRESOLVED_COMPONENT"
	if int(d1.get("hit_miss_disagreements", -1)) == int(d3.get("hit_miss_disagreements", -2)) and _same_hit_map(d1_rows, d3_rows) and d1_unresolved_hits == 0: return "RAY_REGRESSION_OUTSIDE_A6_UNRESOLVED_COMPONENT"
	return "RAY_REGRESSION_CAUSE_UNRESOLVED"

func _annotate_unresolved_ray_hits(result: Dictionary, unresolved_polygon_ids: Dictionary) -> void:
	for ray in result.get("rays", []):
		var row: Dictionary = ray
		var involved: bool = false
		for polygon_id in row.get("source_polygon_ids", []):
			if unresolved_polygon_ids.has(String(polygon_id)):
				involved = true
				break
		row["patch_involved"] = involved

func _same_hit_map(left: Array, right: Array) -> bool:
	if left.size() != right.size(): return false
	for index in range(left.size()):
		if bool(left[index].get("canonical_hit", false)) != bool(right[index].get("canonical_hit", false)) or bool(left[index].get("mesh_hit", false)) != bool(right[index].get("mesh_hit", false)): return false
	return true

func _percentile(sorted_values: Array[float], quantile: float) -> Variant:
	if sorted_values.is_empty(): return null
	return sorted_values[clampi(int(ceil(quantile * float(sorted_values.size()))) - 1, 0, sorted_values.size() - 1)]

func _sha_res_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return Core.sha256(bytes)

func _write_json_no_overwrite(path: String, value: Dictionary) -> bool:
	if FileAccess.file_exists(path): return false
	var json_text: String = JSON.stringify(value, "\t", false)
	json_text = json_text.replace("\u001f", "\\u001f")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(json_text.to_utf8_buffer())
	file.flush()
	var okay: bool = file.get_error() == OK
	file.close()
	return okay

func _emit_blocked(reason: String, detail: Dictionary) -> void:
	print("R10B_RAY_BLOCKED " + JSON.stringify({"reason": reason, "detail": detail}))
	quit(3)
