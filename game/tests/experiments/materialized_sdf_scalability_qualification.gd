extends SceneTree

## Scalability + world-fidelity qualification for the materialized SDF candidate.
##
## The oracle keeps the complete ordered brush ledger. The scalable path
## checkpoints the same edits into canonical 0.5 m SDF chunk tiles, archives the
## journal, drops the hot tail, reloads from a fresh store, and must reproduce
## gameplay-lattice geometry without replaying journal history.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const TerrainMeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const ScalableState := preload("res://scripts/terrain/terrain_scalable_sdf_state.gd")
const MaterializedStore := preload("res://scripts/terrain/terrain_materialized_sdf_store.gd")

const SEED := 131102026
const LEFT_REGION := Vector2i.ZERO
const TARGET_CHUNK := Vector2i(3, 2)
const LOD1_CHUNK := Vector2i(2, 2)
const TARGET_Z_CHUNK := 2
const DEFAULT_EDIT_COUNT := 256
const CHECKPOINT_EVERY := ScalableState.CHECKPOINT_TAIL_TARGET
const HOT_LOAD_LIMIT_USEC := 500000
const COLD_CHUNK_SNAPSHOT_LIMIT_USEC := 500000
const WARM_CHUNK_SNAPSHOT_LIMIT_USEC := 100000

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var edit_count := DEFAULT_EDIT_COUNT
	var configured := OS.get_environment("SCALABLE_EDIT_COUNT")
	if not configured.is_empty() and configured.is_valid_int():
		edit_count = maxi(1, int(configured))
	# Keep CI bounded; larger values are intended for explicit local stress runs.
	edit_count = mini(edit_count, 20000)
	evidence["edit_count"] = edit_count
	evidence["checkpoint_every"] = CHECKPOINT_EVERY

	var root := ProjectSettings.globalize_path(
		"user://materialized-sdf-qualification-%d" % Time.get_ticks_usec()
	)
	var oracle := Brush.new(SEED, Field.GENERATOR_VERSION)
	var scalable := ScalableState.new(SEED, Field.GENERATOR_VERSION)
	var store := MaterializedStore.new(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A17C0DE

	var all_edits_accepted := true
	var checkpoint_count := 0
	var checkpoint_usec_total := 0
	for index in range(edit_count):
		var mode := Brush.Mode.FILL if index % 3 != 0 else Brush.Mode.CARVE
		var center := Vector3(
			rng.randf_range(12.5, 17.5),
			rng.randf_range(0.6, 4.4),
			rng.randf_range(4.5, 8.5)
		)
		var radius := rng.randf_range(0.45, 1.35)
		var oracle_ok: bool = oracle.add_sphere(mode, center, radius)
		var scalable_ok: bool = scalable.add_sphere(mode, center, radius)
		if not oracle_ok or not scalable_ok:
			all_edits_accepted = false
			evidence["first_edit_failure"] = {
				"index": index,
				"oracle_reason": oracle.last_rejection_reason,
				"scalable_reason": scalable.last_rejection_reason,
			}
			break
		if scalable.needs_checkpoint(CHECKPOINT_EVERY):
			var checkpoint_started := Time.get_ticks_usec()
			var saved: Dictionary = store.checkpoint_state(
				MaterializedStore.WORLD_ID, scalable
			)
			checkpoint_usec_total += Time.get_ticks_usec() - checkpoint_started
			if not saved.get("ok", false):
				all_edits_accepted = false
				evidence["checkpoint_failure"] = {
					"index": index,
					"detail": saved,
				}
				break
			checkpoint_count += 1

	_check(all_edits_accepted, "all configured edits are accepted by oracle and scalable state")
	if not all_edits_accepted:
		_cleanup_tree(root)
		_finish()
		return

	if scalable.get_tail_edit_count() > 0:
		var checkpoint_started := Time.get_ticks_usec()
		var saved: Dictionary = store.checkpoint_state(
			MaterializedStore.WORLD_ID, scalable
		)
		checkpoint_usec_total += Time.get_ticks_usec() - checkpoint_started
		_check(saved.get("ok", false), "final partial tail checkpoints")
		if not saved.get("ok", false):
			_cleanup_tree(root)
			_finish()
			return
		checkpoint_count += 1

	evidence["checkpoint_count"] = checkpoint_count
	evidence["checkpoint_usec_total"] = checkpoint_usec_total
	evidence["checkpoint_usec_per_edit"] = float(checkpoint_usec_total) / float(edit_count)
	_check(int(oracle.get_edit_count()) == edit_count, "oracle retains complete configured history")
	_check(int(scalable.get_edit_count()) == edit_count, "scalable state retains lifetime edit count")
	_check(int(scalable.get_tail_edit_count()) == 0, "checkpoint removes historical edits from hot tail")
	_check(int(scalable.get_archived_edit_count()) == edit_count, "all edits are archived after checkpoint")

	var regular_oracle := _build_chunk(oracle, LEFT_REGION, TARGET_CHUNK, 0)
	var regular_scalable := _build_chunk(scalable, LEFT_REGION, TARGET_CHUNK, 0)
	_check(regular_oracle.get("valid", false), "oracle LOD0 target chunk builds")
	_check(regular_scalable.get("valid", false), "materialized LOD0 target chunk builds")
	if regular_oracle.get("valid", false) and regular_scalable.get("valid", false):
		var comparison := _compare_cpu_geometry(regular_oracle, regular_scalable)
		evidence["lod0_fidelity"] = comparison
		_check(comparison.get("same_vertex_count", false), "LOD0 materialization preserves vertex count")
		_check(float(comparison.get("max_position_error", INF)) <= 0.000001, "LOD0 materialization preserves surface positions")
		_check(float(comparison.get("average_normal_dot", -1.0)) >= 0.95, "LOD0 reconstructed normals remain visually aligned")

	var lod1_oracle := _build_chunk(oracle, LEFT_REGION, LOD1_CHUNK, 1)
	var lod1_scalable := _build_chunk(scalable, LEFT_REGION, LOD1_CHUNK, 1)
	_check(lod1_oracle.get("valid", false), "oracle LOD1 target chunk builds")
	_check(lod1_scalable.get("valid", false), "materialized LOD1 target chunk builds")
	if lod1_oracle.get("valid", false) and lod1_scalable.get("valid", false):
		var comparison := _compare_cpu_geometry(lod1_oracle, lod1_scalable)
		evidence["lod1_fidelity"] = comparison
		_check(comparison.get("same_vertex_count", false), "LOD1 materialization preserves vertex count")
		_check(float(comparison.get("max_position_error", INF)) <= 0.000001, "LOD1 materialization preserves surface positions")

	var oracle_pair := _build_boundary_pair(oracle)
	var scalable_pair := _build_boundary_pair(scalable)
	_check(oracle_pair.get("valid", false), "oracle shared boundary pair builds")
	_check(scalable_pair.get("valid", false), "materialized shared boundary pair builds")
	if oracle_pair.get("valid", false) and scalable_pair.get("valid", false):
		evidence["oracle_boundary_signature"] = oracle_pair.get("mesh_signature", "")
		evidence["materialized_boundary_signature"] = scalable_pair.get("mesh_signature", "")
		_check(
			String(oracle_pair.get("mesh_signature", "")) 				== String(scalable_pair.get("mesh_signature", "")),
			"materialization preserves shared-boundary geometry signature"
		)
		var diag: Dictionary = scalable_pair.get("diagnostics", {})
		_check(int(diag.get("seam_bad_incidence_count", -1)) == 0, "materialized seam has incidence 2")
		_check(int(diag.get("t_junction_count", -1)) == 0, "materialized seam has no T-junctions")
		_check(
			int(diag.get("seam_cross_owner_count", -1)) 				== int(diag.get("seam_edge_count", -2)),
			"materialized seam remains cross-owned"
		)

	# Fresh-process style hot load. No journal or tile is allowed to be read just
	# to open the world.
	scalable = null
	store = null
	var fresh_store := MaterializedStore.new(root)
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = fresh_store.load_world(MaterializedStore.WORLD_ID)
	var load_usec := Time.get_ticks_usec() - load_started
	evidence["hot_load_usec"] = load_usec
	_check(loaded.get("ok", false) and loaded.get("found", false), "fresh store loads committed world")
	var load_stats := fresh_store.get_hot_stats()
	evidence["hot_load_stats"] = load_stats
	_check(int(load_stats.get("head_read_count", -1)) == 1, "hot load reads one bounded head record")
	_check(int(load_stats.get("journal_read_count", -1)) == 0, "hot load does not read historical journal")
	_check(int(load_stats.get("tile_blob_read_count", -1)) == 0, "hot load does not eagerly read terrain tiles")
	_check(load_usec <= HOT_LOAD_LIMIT_USEC, "hot world-open latency stays within qualification ceiling")
	if not loaded.get("ok", false) or not loaded.get("found", false):
		_cleanup_tree(root)
		_finish()
		return

	var restored: RefCounted = loaded["state"]
	_check(int(restored.get_edit_count()) == edit_count, "fresh state restores lifetime edit count without replay")
	_check(int(restored.get_tail_edit_count()) == 0, "fresh state starts with empty hot edit tail")

	var cold_started := Time.get_ticks_usec()
	var cold_snapshot: Dictionary = restored.get_meshing_snapshot_for_chunk(
		LEFT_REGION, TARGET_CHUNK
	)
	var cold_snapshot_usec := Time.get_ticks_usec() - cold_started
	evidence["cold_chunk_snapshot_usec"] = cold_snapshot_usec
	var cold_stats := fresh_store.get_hot_stats()
	evidence["cold_chunk_stats"] = cold_stats
	_check(cold_snapshot.get("valid", false), "cold chunk snapshot resolves lazily")
	_check(int(cold_stats.get("journal_read_count", -1)) == 0, "cold chunk load still avoids journal replay")
	_check(int(cold_stats.get("pointer_read_count", 999)) <= 9, "cold chunk probes only local 3x3 tile pointers")
	_check(int(cold_stats.get("tile_blob_read_count", 999)) <= 9, "cold chunk reads only local materialized tiles")
	_check(cold_snapshot_usec <= COLD_CHUNK_SNAPSHOT_LIMIT_USEC, "cold chunk snapshot stays within qualification ceiling")

	var warm_started := Time.get_ticks_usec()
	var warm_snapshot: Dictionary = restored.get_meshing_snapshot_for_chunk(
		LEFT_REGION, TARGET_CHUNK
	)
	var warm_snapshot_usec := Time.get_ticks_usec() - warm_started
	evidence["warm_chunk_snapshot_usec"] = warm_snapshot_usec
	_check(warm_snapshot.get("valid", false), "warm chunk snapshot remains valid")
	_check(warm_snapshot_usec <= WARM_CHUNK_SNAPSHOT_LIMIT_USEC, "warm chunk snapshot is gameplay-scale bounded")

	var restored_regular := _build_chunk(restored, LEFT_REGION, TARGET_CHUNK, 0)
	_check(restored_regular.get("valid", false), "reloaded materialized LOD0 chunk builds")
	if regular_oracle.get("valid", false) and restored_regular.get("valid", false):
		var comparison := _compare_cpu_geometry(regular_oracle, restored_regular)
		evidence["reload_lod0_fidelity"] = comparison
		_check(float(comparison.get("max_position_error", INF)) <= 0.000001, "reload preserves LOD0 surface positions")

	var restored_pair := _build_boundary_pair(restored)
	_check(restored_pair.get("valid", false), "reloaded shared boundary pair builds")
	if oracle_pair.get("valid", false) and restored_pair.get("valid", false):
		_check(
			String(oracle_pair.get("mesh_signature", "")) 				== String(restored_pair.get("mesh_signature", "")),
			"reload preserves shared-boundary geometry signature"
		)

	var before_audit_stats := fresh_store.get_hot_stats()
	_check(int(before_audit_stats.get("journal_read_count", -1)) == 0, "all gameplay fidelity checks complete without journal reads")
	var audit := fresh_store.audit_archive()
	evidence["archive_audit"] = audit
	_check(audit.get("ok", false), "optional archive audit verifies complete ordered history")
	_check(int(audit.get("record_count", -1)) == edit_count, "archive audit accounts for every edit")

	# Prove the former 65,536 admission boundary is not a logical limit of the
	# scalable state. This is a metadata-resume test; load stress is covered above.
	var beyond_old_cap := ScalableState.new(SEED, Field.GENERATOR_VERSION)
	var resumed := beyond_old_cap.restore_hot_reference(null, {
		"world_seed": SEED,
		"generator_version": Field.GENERATOR_VERSION,
		"revision": 65536,
		"next_sequence": 65536,
		"lifetime_operation_count": 65536,
		"archived_operation_count": 65536,
	})
	_check(resumed, "scalable state can resume at the former 65,536-edit boundary")
	var accepted_65537 := beyond_old_cap.add_sphere(
		Brush.Mode.FILL, Vector3(15.5, 2.0, 7.0), 0.7
	)
	_check(accepted_65537, "edit 65,537 is admitted without legacy ledger-cap rejection")
	_check(int(beyond_old_cap.get_edit_count()) == 65537, "lifetime counter advances beyond legacy cap")
	_check(ScalableState.MAX_SAFE_SEQUENCE > 65536, "sequence space is bounded only by safe integer representation")

	evidence["world_bytes"] = _directory_bytes(root)
	evidence["final_hot_stats"] = fresh_store.get_hot_stats()
	evidence["cleanup_ok"] = _cleanup_tree(root)
	_finish()


func _build_chunk(
	state: RefCounted,
	region_key: Vector2i,
	coordinate: Vector2i,
	lod_level: int
) -> Dictionary:
	var snapshot: Dictionary = state.get_meshing_snapshot_for_chunk(region_key, coordinate)
	if not snapshot.get("valid", false):
		return snapshot
	var job := TerrainMeshJob.new(
		SEED, region_key, coordinate, false, snapshot, Time.get_ticks_usec(), lod_level
	)
	job.run()
	return job.result


func _build_boundary_pair(state: RefCounted) -> Dictionary:
	var snapshot: Dictionary = Authority.make_x_pair_snapshot(
		state, LEFT_REGION, TARGET_Z_CHUNK
	)
	if not snapshot.get("valid", false):
		return snapshot
	return Authority.build_x_region_boundary_pair(
		SEED, LEFT_REGION, TARGET_Z_CHUNK, snapshot
	)


func _compare_cpu_geometry(a: Dictionary, b: Dictionary) -> Dictionary:
	var pa: PackedVector3Array = a.get("positions", PackedVector3Array())
	var pb: PackedVector3Array = b.get("positions", PackedVector3Array())
	var na: PackedVector3Array = a.get("normals", PackedVector3Array())
	var nb: PackedVector3Array = b.get("normals", PackedVector3Array())
	var same_vertex_count := pa.size() == pb.size()
	var max_position_error := INF
	if same_vertex_count:
		max_position_error = 0.0
		for index in range(pa.size()):
			max_position_error = maxf(
				max_position_error, pa[index].distance_to(pb[index])
			)
	var normal_count := mini(na.size(), nb.size())
	var normal_dot_sum := 0.0
	var normal_samples := 0
	var minimum_normal_dot := 1.0
	for index in range(normal_count):
		if na[index].length_squared() <= 0.000001 or nb[index].length_squared() <= 0.000001:
			continue
		var dot := clampf(na[index].normalized().dot(nb[index].normalized()), -1.0, 1.0)
		normal_dot_sum += dot
		minimum_normal_dot = minf(minimum_normal_dot, dot)
		normal_samples += 1
	return {
		"same_vertex_count": same_vertex_count,
		"vertex_count_a": pa.size(),
		"vertex_count_b": pb.size(),
		"max_position_error": max_position_error,
		"average_normal_dot": normal_dot_sum / float(normal_samples) if normal_samples > 0 else 1.0,
		"minimum_normal_dot": minimum_normal_dot if normal_samples > 0 else 1.0,
		"normal_samples": normal_samples,
	}


func _directory_bytes(path: String) -> int:
	if not DirAccess.dir_exists_absolute(path):
		return 0
	var directory := DirAccess.open(path)
	if directory == null:
		return 0
	var total := 0
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			total += _directory_bytes(child)
		else:
			total += FileAccess.get_file_as_bytes(child).size()
	directory.list_dir_end()
	return total


func _cleanup_tree(path: String) -> bool:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return true
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		var child := path.path_join(name)
		if directory.current_is_dir():
			if not _cleanup_tree(child):
				directory.list_dir_end()
				return false
		else:
			if DirAccess.remove_absolute(child) != OK:
				directory.list_dir_end()
				return false
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


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
	print("MATERIALIZED_SDF_SCALE_RESULT=" + JSON.stringify(payload))
	print("MATERIALIZED_SDF_SCALE_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
