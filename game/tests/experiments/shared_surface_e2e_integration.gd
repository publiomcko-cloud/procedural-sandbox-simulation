extends SceneTree

## E2E qualification for the shared-surface boundary authority.
##
## Covers:
## - exact R9.2/R6 frozen replay at 0.25
## - production 0.5 region-edge chunk pairs across all X+ z chunks
## - worker-thread execution
## - actual ArrayMesh publication
## - LOD1 interior -> forced-LOD0 boundary collar on both sides
## - schema-v2 persistence, process-style unload/reload and deterministic rebuild
## - a fixed cross-region edit followed by rebuild/save/reload

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const TerrainMeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const BoundaryJob := preload("res://scripts/terrain/shared_surface_boundary_mesh_job.gd")
const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const SaveStore := preload("res://scripts/terrain/terrain_world_save_store_v2.gd")

const SEED := 131102026
const LEFT_REGION := Vector2i.ZERO
const RIGHT_REGION := Vector2i(1, 0)
const SCIENTIFIC_ROI_MIN := Vector3(15.0, 1.0, 6.0)
const SCIENTIFIC_CELLS := Vector3i(8, 8, 8)
const SCIENTIFIC_STEP := 0.25
const REGION_SEAM_X := 16.0
const CROSS_EDIT_CENTER := Vector3(16.0, 1.75, 7.0)
const CROSS_EDIT_RADIUS := 1.25

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := _make_frozen_ledger()
	_check(source.get("valid", false), "frozen R6 ledger constructs")
	if not source.get("valid", false):
		_finish()
		return
	var ledger: RefCounted = source["ledger"]
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	_check(int(snapshot.get("revision", -1)) == 2, "frozen snapshot revision is 2")

	# Scientific replay: same 0.25 ROI that fed the R6 campaign.
	var scientific := Authority.build_x_shared_volume(
		SEED, snapshot, SCIENTIFIC_ROI_MIN, SCIENTIFIC_CELLS,
		SCIENTIFIC_STEP, REGION_SEAM_X
	)
	_check(scientific.get("valid", false), "exact R6 0.25 replay builds through reusable authority")
	if scientific.get("valid", false):
		_check_seam(scientific.get("diagnostics", {}), "scientific R6 seam", true)
		evidence["scientific_signature"] = scientific.get("mesh_signature", "")
		evidence["scientific_triangles"] = scientific.get("triangle_count", 0)
		evidence["scientific_roots"] = scientific.get("unique_root_count", 0)

	# Production 0.5 boundary chunks through worker-compatible pair jobs.
	var production_before := _build_all_boundary_pairs(ledger)
	_check(production_before.get("valid", false), "all four production X+ boundary chunk pairs build")
	if production_before.get("valid", false):
		_check(int(production_before.get("total_seam_edges", 0)) > 0, "production region seam intersects generated surface")
		_check(int(production_before.get("bad_incidence", -1)) == 0, "production region seam has no bad edge incidence")
		_check(int(production_before.get("t_junctions", -1)) == 0, "production region seam has no T-junctions")
		_check(int(production_before.get("cross_owned", -1)) == int(production_before.get("total_seam_edges", -2)), "every production seam edge is owned by both sides")
		evidence["production_before_signature"] = production_before.get("signature", "")
		evidence["production_before_seam_edges"] = production_before.get("total_seam_edges", 0)

	# Real ArrayMesh publication for one pair; publication consumes copies.
	if production_before.get("valid", false):
		var pair0: Dictionary = production_before["pairs"][0]
		var left_publish: Dictionary = (pair0["left"] as Dictionary).duplicate(true)
		var right_publish: Dictionary = (pair0["right"] as Dictionary).duplicate(true)
		var left_mesh := Mesher.mesh_from_cpu_data(left_publish)
		var right_mesh := Mesher.mesh_from_cpu_data(right_publish)
		_check(left_mesh.get("valid", false) and left_mesh.get("mesh", null) is ArrayMesh, "left shared boundary chunk publishes ArrayMesh")
		_check(right_mesh.get("valid", false) and right_mesh.get("mesh", null) is ArrayMesh, "right shared boundary chunk publishes ArrayMesh")
		_check(int(left_mesh.get("triangle_count", 0)) + int(right_mesh.get("triangle_count", 0)) > 0, "published boundary pair is non-empty")

	# Mixed LOD qualification: region edge chunks are forced LOD0; LOD1 begins
	# one chunk inward, where the existing transition mesher has a fine-split face.
	if production_before.get("valid", false):
		var mixed := _qualify_mixed_lod_collars(ledger, production_before["pairs"])
		_check(mixed.get("valid", false), "LOD1 interior to shared LOD0 boundary collar builds on both regions")
		if mixed.get("valid", false):
			_check(int(mixed.get("total_seam_edges", 0)) > 0, "mixed-LOD collar has surface crossings")
			_check(int(mixed.get("bad_incidence", -1)) == 0, "mixed-LOD collar has no bad edge incidence")
			_check(int(mixed.get("t_junctions", -1)) == 0, "mixed-LOD collar has no T-junctions")
			_check(int(mixed.get("cross_owned", -1)) == int(mixed.get("total_seam_edges", -2)), "mixed-LOD collar edges match on both sides")
			evidence["mixed_lod_before"] = mixed

	# Save -> drop objects -> fresh store -> restore ledger -> deterministic rebuild.
	var save_root := ProjectSettings.globalize_path(
		"user://arch-alt-e2e-%d" % Time.get_ticks_usec()
	)
	var legacy_root := save_root + "-legacy"
	var store: RefCounted = SaveStore.new(save_root, legacy_root)
	var saved1: Dictionary = store.save_ledger(SaveStore.WORLD_ID, ledger)
	_check(saved1.get("ok", false), "schema-v2 generation 1 saves")
	var before_signature := String(production_before.get("signature", ""))

	ledger = null
	store = null

	var reloaded1 := _reload_ledger(save_root, legacy_root)
	_check(reloaded1.get("valid", false), "fresh store reloads generation 1")
	if not reloaded1.get("valid", false):
		_cleanup_tree(save_root)
		_cleanup_tree(legacy_root)
		_finish()
		return
	var restored_ledger: RefCounted = reloaded1["ledger"]
	var production_reloaded := _build_all_boundary_pairs(restored_ledger)
	_check(production_reloaded.get("valid", false), "reloaded boundary pairs rebuild")
	_check(String(production_reloaded.get("signature", "")) == before_signature, "save/unload/reload preserves complete boundary signature")
	if production_reloaded.get("valid", false):
		_check(int(production_reloaded.get("bad_incidence", -1)) == 0, "reloaded region seam remains closed")
		_check(int(production_reloaded.get("t_junctions", -1)) == 0, "reloaded region seam remains T-junction free")

	# Fixed edit centered on the regional boundary; this must change both sides.
	var prior_revision := int(restored_ledger.revision)
	var prior_count := int(restored_ledger.get_edit_count())
	var edit_ok: bool = restored_ledger.add_sphere(
		Brush.Mode.FILL, CROSS_EDIT_CENTER, CROSS_EDIT_RADIUS
	)
	_check(edit_ok, "cross-region FILL edit is accepted")
	_check(int(restored_ledger.revision) == prior_revision + 1, "cross-region edit increments revision once")
	_check(int(restored_ledger.get_edit_count()) == prior_count + 1, "cross-region edit appends one ordered command")
	var production_edited := _build_all_boundary_pairs(restored_ledger)
	_check(production_edited.get("valid", false), "boundary pairs rebuild after cross-region edit")
	if production_edited.get("valid", false):
		_check(String(production_edited.get("signature", "")) != before_signature, "cross-region edit changes boundary geometry signature")
		_check(int(production_edited.get("bad_incidence", -1)) == 0, "edited regional seam has no bad edge incidence")
		_check(int(production_edited.get("t_junctions", -1)) == 0, "edited regional seam has no T-junctions")
		_check(int(production_edited.get("cross_owned", -1)) == int(production_edited.get("total_seam_edges", -2)), "edited seam remains shared by both regions")
		var mixed_after := _qualify_mixed_lod_collars(restored_ledger, production_edited["pairs"])
		_check(mixed_after.get("valid", false), "mixed-LOD collars rebuild after cross-region edit")
		if mixed_after.get("valid", false):
			_check(int(mixed_after.get("bad_incidence", -1)) == 0, "edited mixed-LOD collar has no bad edge incidence")
			_check(int(mixed_after.get("t_junctions", -1)) == 0, "edited mixed-LOD collar has no T-junctions")
			_check(int(mixed_after.get("cross_owned", -1)) == int(mixed_after.get("total_seam_edges", -2)), "edited mixed-LOD collar edges match")
			evidence["mixed_lod_after"] = mixed_after

	# Persist the edited generation and prove a second process-style reload is exact.
	var store2: RefCounted = SaveStore.new(save_root, legacy_root)
	var load_existing: Dictionary = store2.load_world(SaveStore.WORLD_ID)
	_check(load_existing.get("ok", false) and load_existing.get("found", false), "second store observes generation 1 before save")
	var saved2: Dictionary = store2.save_ledger(SaveStore.WORLD_ID, restored_ledger)
	_check(saved2.get("ok", false), "schema-v2 edited generation saves")
	var edited_signature := String(production_edited.get("signature", ""))
	restored_ledger = null
	store2 = null

	var reloaded2 := _reload_ledger(save_root, legacy_root)
	_check(reloaded2.get("valid", false), "fresh store reloads edited generation")
	if reloaded2.get("valid", false):
		var final_ledger: RefCounted = reloaded2["ledger"]
		var final_pairs := _build_all_boundary_pairs(final_ledger)
		_check(final_pairs.get("valid", false), "edited generation rebuilds after second unload/reload")
		evidence["final_reloaded_signature"] = String(final_pairs.get("signature", ""))
		_check(String(final_pairs.get("signature", "")) == edited_signature, "edited save/reload preserves complete boundary signature")
		if final_pairs.get("valid", false):
			_check(int(final_pairs.get("bad_incidence", -1)) == 0, "final reloaded seam remains closed")
			_check(int(final_pairs.get("t_junctions", -1)) == 0, "final reloaded seam remains T-junction free")

	evidence["save_root_cleaned"] = _cleanup_tree(save_root)
	_cleanup_tree(legacy_root)
	evidence["final_revision"] = prior_revision + 1
	evidence["final_edit_count"] = prior_count + 1
	evidence["production_edited_signature"] = edited_signature
	_finish()


func _make_frozen_ledger() -> Dictionary:
	var ledger := Brush.new(SEED, Field.GENERATOR_VERSION)
	if not ledger.add_sphere(
		Brush.Mode.FILL,
		Vector3(8.0, 1.17898154258728, 5.10309219360352),
		0.58
	):
		return {"valid": false, "reason": ledger.last_rejection_reason}
	if not ledger.add_sphere(
		Brush.Mode.CARVE,
		Vector3(8.0, 1.17898154258728, 5.92309236526489),
		0.58
	):
		return {"valid": false, "reason": ledger.last_rejection_reason}
	return {"valid": true, "ledger": ledger}


func _build_all_boundary_pairs(ledger: RefCounted) -> Dictionary:
	var jobs: Array = []
	var task_ids: Array[int] = []
	for z_chunk in range(Grid.CHUNK_COUNT_Z):
		var pair_snapshot: Dictionary = Authority.make_x_pair_snapshot(ledger, LEFT_REGION, z_chunk)
		if not pair_snapshot.get("valid", false):
			return {"valid": false, "reason": "pair_snapshot_failed", "z_chunk": z_chunk, "detail": pair_snapshot}
		var job := BoundaryJob.new(SEED, LEFT_REGION, z_chunk, pair_snapshot, Time.get_ticks_usec())
		jobs.append(job)
		task_ids.append(WorkerThreadPool.add_task(
			Callable(job, "run"), false, "shared-surface boundary pair"
		))
	for task_id in task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)

	var pairs: Array[Dictionary] = []
	var signature_rows: Array[String] = []
	var total_edges := 0
	var bad_incidence := 0
	var t_junctions := 0
	var cross_owned := 0
	for job_value in jobs:
		var job = job_value
		var result: Dictionary = job.result
		if not result.get("valid", false):
			return {"valid": false, "reason": result.get("reason", "boundary_job_failed")}
		var diagnostics: Dictionary = result.get("diagnostics", {})
		total_edges += int(diagnostics.get("seam_edge_count", 0))
		bad_incidence += int(diagnostics.get("seam_bad_incidence_count", 0))
		t_junctions += int(diagnostics.get("t_junction_count", 0))
		cross_owned += int(diagnostics.get("seam_cross_owner_count", 0))
		signature_rows.append("%d:%s" % [int(result.get("z_chunk", -1)), String(result.get("mesh_signature", ""))])
		pairs.append(result)
	signature_rows.sort()
	return {
		"valid": true,
		"pairs": pairs,
		"signature": _fnv1a_64("\n".join(signature_rows)),
		"total_seam_edges": total_edges,
		"bad_incidence": bad_incidence,
		"t_junctions": t_junctions,
		"cross_owned": cross_owned,
	}


func _qualify_mixed_lod_collars(ledger: RefCounted, pairs: Array) -> Dictionary:
	var total_edges := 0
	var bad_incidence := 0
	var t_junctions := 0
	var cross_owned := 0
	var valid_pair_count := 0
	var seam_details: Array[Dictionary] = []
	for z_chunk in range(Grid.CHUNK_COUNT_Z):
		var pair: Dictionary = pairs[z_chunk]
		var left_boundary: Dictionary = pair["left"]
		var right_boundary: Dictionary = pair["right"]

		var left_interior_coordinate := Vector2i(Grid.CHUNK_COUNT_X - 2, z_chunk)
		var left_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(LEFT_REGION, left_interior_coordinate)
		if not left_snapshot.get("valid", false):
			return {"valid": false, "reason": "left_lod1_snapshot_failed", "z_chunk": z_chunk, "detail": left_snapshot}
		var left_lod1 := TerrainMeshJob.new(
			SEED, LEFT_REGION, left_interior_coordinate, false,
			left_snapshot, Time.get_ticks_usec(), 1
		)
		left_lod1.run()
		if not left_lod1.result.get("valid", false) or int(left_lod1.result.get("lod_level", -1)) != 1:
			return {"valid": false, "reason": "left_lod1_interior_failed", "z_chunk": z_chunk, "detail": left_lod1.result}
		var left_interior_origin := Spatial.region_origin_world(LEFT_REGION) + Grid.origin_for(left_interior_coordinate)
		var left_boundary_origin := Spatial.region_origin_world(LEFT_REGION) + Grid.origin_for(Vector2i(Grid.CHUNK_COUNT_X - 1, z_chunk))
		var left_plane_x := left_boundary_origin.x
		var z_min := left_boundary_origin.z
		var z_max := z_min + float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
		var left_diag := Authority.analyze_cpu_pair_plane(
			left_lod1.result, left_interior_origin,
			left_boundary, left_boundary_origin,
			left_plane_x, Grid.MIN_BOUND.y, Grid.MAX_BOUND.y, z_min, z_max
		)

		var right_interior_coordinate := Vector2i(1, z_chunk)
		var right_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(RIGHT_REGION, right_interior_coordinate)
		if not right_snapshot.get("valid", false):
			return {"valid": false, "reason": "right_lod1_snapshot_failed", "z_chunk": z_chunk, "detail": right_snapshot}
		var right_lod1 := TerrainMeshJob.new(
			SEED, RIGHT_REGION, right_interior_coordinate, false,
			right_snapshot, Time.get_ticks_usec(), 1
		)
		right_lod1.run()
		if not right_lod1.result.get("valid", false) or int(right_lod1.result.get("lod_level", -1)) != 1:
			return {"valid": false, "reason": "right_lod1_interior_failed", "z_chunk": z_chunk, "detail": right_lod1.result}
		var right_boundary_origin := Spatial.region_origin_world(RIGHT_REGION) + Grid.origin_for(Vector2i(0, z_chunk))
		var right_interior_origin := Spatial.region_origin_world(RIGHT_REGION) + Grid.origin_for(right_interior_coordinate)
		var right_plane_x := right_interior_origin.x
		var right_diag := Authority.analyze_cpu_pair_plane(
			right_boundary, right_boundary_origin,
			right_lod1.result, right_interior_origin,
			right_plane_x, Grid.MIN_BOUND.y, Grid.MAX_BOUND.y, z_min, z_max
		)

		seam_details.append({"z_chunk": z_chunk, "side": "left", "diagnostics": left_diag})
		seam_details.append({"z_chunk": z_chunk, "side": "right", "diagnostics": right_diag})
		total_edges += int(left_diag.get("seam_edge_count", 0)) + int(right_diag.get("seam_edge_count", 0))
		bad_incidence += int(left_diag.get("seam_bad_incidence_count", 0)) + int(right_diag.get("seam_bad_incidence_count", 0))
		t_junctions += int(left_diag.get("t_junction_count", 0)) + int(right_diag.get("t_junction_count", 0))
		cross_owned += int(left_diag.get("seam_cross_owner_count", 0)) + int(right_diag.get("seam_cross_owner_count", 0))
		valid_pair_count += 2
	return {
		"valid": true,
		"qualified_internal_seams": valid_pair_count,
		"grid_chunk_count_z": Grid.CHUNK_COUNT_Z,
		"total_seam_edges": total_edges,
		"bad_incidence": bad_incidence,
		"t_junctions": t_junctions,
		"cross_owned": cross_owned,
		"seam_details": seam_details,
		"policy": "force region-edge chunks to LOD0; transition LOD1 one chunk inward",
	}


func _reload_ledger(save_root: String, legacy_root: String) -> Dictionary:
	var store: RefCounted = SaveStore.new(save_root, legacy_root)
	var loaded: Dictionary = store.load_world(SaveStore.WORLD_ID)
	if not loaded.get("ok", false) or not loaded.get("found", false):
		return {"valid": false, "reason": loaded.get("reason", "load_failed")}
	var payload: Dictionary = loaded.get("payload", {})
	var seed_value: Variant = payload.get("world_seed", null)
	var generator_value: Variant = payload.get("generator_version", null)
	if typeof(seed_value) != TYPE_INT or typeof(generator_value) != TYPE_INT:
		return {"valid": false, "reason": "loaded_identity_invalid"}
	var ledger := Brush.new(int(seed_value), int(generator_value))
	var restore_snapshot := {
		"world_seed": int(seed_value),
		"generator_version": int(generator_value),
		"revision": int(payload.get("ledger_revision", -1)),
		"next_sequence": int(payload.get("next_sequence", -1)),
		"storage_reference": payload.get("storage_reference", {}),
	}
	if not ledger.restore_persistence_snapshot(restore_snapshot):
		return {"valid": false, "reason": ledger.last_restore_rejection_reason}
	return {
		"valid": true,
		"ledger": ledger,
		"store": store,
		"generation": int(loaded.get("generation", -1)),
	}


func _check_seam(diag: Dictionary, label: String, require_edges: bool) -> void:
	if require_edges:
		_check(int(diag.get("seam_edge_count", 0)) > 0, "%s has surface edges" % label)
	_check(int(diag.get("seam_bad_incidence_count", -1)) == 0, "%s has incidence 2" % label)
	_check(int(diag.get("t_junction_count", -1)) == 0, "%s has zero T-junctions" % label)
	_check(int(diag.get("seam_cross_owner_count", -1)) == int(diag.get("seam_edge_count", -2)), "%s is shared by both region sides" % label)
	_check(int(diag.get("duplicate_triangle_count", -1)) == 0, "%s has no duplicate triangles" % label)
	_check(int(diag.get("emitted_degenerate_triangle_count", -1)) == 0, "%s emits no degenerate triangles" % label)
	_check(bool(diag.get("root_identity_consistent", false)), "%s preserves global root identity" % label)


func _cleanup_tree(path: String) -> bool:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return true
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir():
			if not _cleanup_tree(child):
				directory.list_dir_end()
				return false
		else:
			if DirAccess.remove_absolute(child) != OK:
				directory.list_dir_end()
				return false
		name = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


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


func _finish() -> void:
	var payload := {
		"status": "PASS" if failures == 0 else "FAIL",
		"assertions": assertions,
		"failures": failures,
		"evidence": evidence,
	}
	print("SHARED_SURFACE_E2E_RESULT=" + JSON.stringify(payload))
	print("SHARED_SURFACE_E2E_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
