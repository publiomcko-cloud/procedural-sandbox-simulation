extends SceneTree

## Scalability + fidelity qualification for the materialized SDF candidate.
##
## Default CI load is intentionally moderate; --edits=N can scale the same
## procedure locally without changing the scientific gates.

const Field := preload("res://scripts/terrain/sdf_world.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const Scalable := preload("res://scripts/terrain/terrain_scalable_sdf_state.gd")
const Store := preload("res://scripts/terrain/terrain_materialized_sdf_store.gd")
const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")

const SEED := 131102026
const DEFAULT_EDIT_COUNT := 4096
const CHECKPOINT_INTERVAL := 128
const LEFT_REGION := Vector2i.ZERO
const TEST_CHUNKS := [
	Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(2, 1), Vector2i(3, 1),
	Vector2i(2, 2), Vector2i(3, 2),
	Vector2i(2, 3), Vector2i(3, 3),
]
const LATTICE_PROBES_PER_CHUNK := 12

var assertions := 0
var failures := 0
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var edit_count := _requested_edit_count()
	var root := ProjectSettings.globalize_path(
		"user://scalable-world-qualification-%d" % Time.get_ticks_usec()
	)
	var store := Store.new(root)
	var scalable := Scalable.new(SEED, Field.GENERATOR_VERSION)
	var reference := Brush.new(SEED, Field.GENERATOR_VERSION)
	var checkpoint_count := 0
	var checkpoint_usec_total := 0
	var checkpoint_usec_max := 0
	var admission_started := Time.get_ticks_usec()

	for index in range(edit_count):
		var spec := _operation_spec(index)
		var ok_scalable: bool = scalable.add_sphere(spec["mode"], spec["center"], spec["radius"])
		var ok_reference: bool = reference.add_sphere(spec["mode"], spec["center"], spec["radius"])
		if not ok_scalable or not ok_reference:
			_check(false, "operation %d accepted by both states" % index)
			_cleanup_tree(root)
			_finish()
			return
		if scalable.needs_checkpoint(CHECKPOINT_INTERVAL):
			var started := Time.get_ticks_usec()
			var saved: Dictionary = store.checkpoint_state(Store.WORLD_ID, scalable)
			var elapsed := Time.get_ticks_usec() - started
			checkpoint_usec_total += elapsed
			checkpoint_usec_max = maxi(checkpoint_usec_max, elapsed)
			checkpoint_count += 1
			if not saved.get("ok", false):
				_check(false, "checkpoint %d succeeds: %s" % [checkpoint_count, saved])
				_cleanup_tree(root)
				_finish()
				return
			_check(scalable.get_tail_edit_count() == 0, "checkpoint %d clears live tail" % checkpoint_count)

	if scalable.get_tail_edit_count() > 0:
		var started := Time.get_ticks_usec()
		var saved: Dictionary = store.checkpoint_state(Store.WORLD_ID, scalable)
		var elapsed := Time.get_ticks_usec() - started
		checkpoint_usec_total += elapsed
		checkpoint_usec_max = maxi(checkpoint_usec_max, elapsed)
		checkpoint_count += 1
		_check(saved.get("ok", false), "final partial checkpoint succeeds")
		if not saved.get("ok", false):
			_cleanup_tree(root)
			_finish()
			return

	var admission_usec := Time.get_ticks_usec() - admission_started
	_check(scalable.get_edit_count() == edit_count, "scalable state retains lifetime edit count")
	_check(scalable.get_archived_edit_count() == edit_count, "all edits archived after final checkpoint")
	_check(scalable.get_tail_edit_count() == 0, "live tail is empty after final checkpoint")
	_check(reference.get_edit_count() == edit_count, "reference ledger contains identical edit count")

	# Process-style hot load. Normal gameplay restore is required to read head only.
	scalable = null
	store = null
	var fresh_store := Store.new(root)
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = fresh_store.load_world(Store.WORLD_ID)
	var hot_load_usec := Time.get_ticks_usec() - load_started
	_check(loaded.get("ok", false) and loaded.get("found", false), "fresh materialized world hot-load succeeds")
	if not loaded.get("ok", false) or not loaded.get("found", false):
		_cleanup_tree(root)
		_finish()
		return
	var hot_state: RefCounted = loaded["state"]
	var stats_after_head: Dictionary = fresh_store.get_hot_stats()
	_check(int(stats_after_head.get("journal_read_count", -1)) == 0, "hot world load reads zero journal segments")
	_check(int(stats_after_head.get("pointer_read_count", -1)) == 0, "hot world load eagerly reads zero tile pointers")
	_check(int(stats_after_head.get("tile_blob_read_count", -1)) == 0, "hot world load eagerly reads zero tile blobs")
	_check(hot_state.get_edit_count() == edit_count, "hot state restores lifetime edit count")
	_check(hot_state.get_tail_edit_count() == 0, "hot state restores with bounded empty tail")

	# First-use chunk snapshot is spatial/lazy and must still avoid journal history.
	var first_snapshot_started := Time.get_ticks_usec()
	var first_snapshot: Dictionary = hot_state.get_meshing_snapshot_for_chunk(
		LEFT_REGION, Vector2i(3, 1)
	)
	var first_snapshot_usec := Time.get_ticks_usec() - first_snapshot_started
	_check(first_snapshot.get("valid", false), "first cold chunk snapshot succeeds")
	_check(int(first_snapshot.get("candidate_operation_count", -1)) == 0, "checkpointed chunk has zero historical operations in live candidate tail")
	_check((first_snapshot.get("materialized_tiles", []) as Array).size() > 0, "first cold chunk resolves materialized spatial tiles")
	var stats_after_chunk: Dictionary = fresh_store.get_hot_stats()
	_check(int(stats_after_chunk.get("journal_read_count", -1)) == 0, "cold chunk materialization reads zero journal segments")

	# Fidelity gate 1: canonical gameplay lattice densities must match complete history exactly.
	var density_checks := 0
	for coordinate in TEST_CHUNKS:
		var hot_snapshot: Dictionary = hot_state.get_meshing_snapshot_for_chunk(LEFT_REGION, coordinate)
		var ref_snapshot: Dictionary = reference.get_meshing_snapshot_for_chunk(LEFT_REGION, coordinate)
		_check(hot_snapshot.get("valid", false) and ref_snapshot.get("valid", false), "chunk snapshots valid for %s" % coordinate)
		if not hot_snapshot.get("valid", false) or not ref_snapshot.get("valid", false):
			continue
		var origin := Spatial.region_origin_world(LEFT_REGION) + Grid.origin_for(coordinate)
		for probe_index in range(LATTICE_PROBES_PER_CHUNK):
			var x_cell := (probe_index * 3 + coordinate.x) % (Grid.CELLS_PER_CHUNK_X + 1)
			var z_cell := (probe_index * 5 + coordinate.y) % (Grid.CELLS_PER_CHUNK_Z + 1)
			var y_cell := (probe_index * 7 + coordinate.x + coordinate.y) % (Grid.CELL_COUNT_Y + 1)
			var world := Vector3(
				origin.x + float(x_cell) * Grid.SAMPLE_STEP,
				Grid.MIN_BOUND.y + float(y_cell) * Grid.SAMPLE_STEP,
				origin.z + float(z_cell) * Grid.SAMPLE_STEP
			)
			var mapped: Dictionary = Spatial.world_to_region_local(world)
			var d_hot := Brush.sample_density_snapshot(
				SEED, mapped["region_key"], mapped["local_position"], false, hot_snapshot
			)
			var d_ref := Brush.sample_density_snapshot(
				SEED, mapped["region_key"], mapped["local_position"], false, ref_snapshot
			)
			_check(d_hot == d_ref, "lattice density exact at %s" % world)
			density_checks += 1

	# Fidelity gate 2: current gameplay mesh vertices are exact after compaction/reload.
	var mesh_checks := 0
	var mesh_usec_total := 0
	for coordinate in TEST_CHUNKS:
		var hot_snapshot: Dictionary = hot_state.get_meshing_snapshot_for_chunk(LEFT_REGION, coordinate)
		var ref_snapshot: Dictionary = reference.get_meshing_snapshot_for_chunk(LEFT_REGION, coordinate)
		var started := Time.get_ticks_usec()
		var hot_cpu: Dictionary = Mesher.build_chunk_cpu_data(
			SEED, LEFT_REGION, coordinate, false, hot_snapshot
		)
		mesh_usec_total += Time.get_ticks_usec() - started
		var ref_cpu: Dictionary = Mesher.build_chunk_cpu_data(
			SEED, LEFT_REGION, coordinate, false, ref_snapshot
		)
		_check(hot_cpu.get("valid", false) and ref_cpu.get("valid", false), "mesh builds valid for %s" % coordinate)
		if hot_cpu.get("valid", false) and ref_cpu.get("valid", false):
			_check(
				hot_cpu.get("positions", PackedVector3Array()) == ref_cpu.get("positions", PackedVector3Array()),
				"mesh vertex geometry exact after compaction for %s" % coordinate
			)
			_check(
				int(hot_cpu.get("triangle_count", -1)) == int(ref_cpu.get("triangle_count", -2)),
				"mesh triangle count exact after compaction for %s" % coordinate
			)
			mesh_checks += 1

	# Fidelity gate 3: shared regional seam must be identical to complete ledger.
	var hot_pair_snapshot := Authority.make_x_pair_snapshot(hot_state, LEFT_REGION, 1)
	var ref_pair_snapshot := Authority.make_x_pair_snapshot(reference, LEFT_REGION, 1)
	_check(hot_pair_snapshot.get("valid", false) and ref_pair_snapshot.get("valid", false), "shared-boundary snapshots build for hot and reference state")
	if hot_pair_snapshot.get("valid", false) and ref_pair_snapshot.get("valid", false):
		var hot_pair := Authority.build_x_region_boundary_pair(SEED, LEFT_REGION, 1, hot_pair_snapshot)
		var ref_pair := Authority.build_x_region_boundary_pair(SEED, LEFT_REGION, 1, ref_pair_snapshot)
		_check(hot_pair.get("valid", false) and ref_pair.get("valid", false), "shared-boundary pair builds after long-history reload")
		if hot_pair.get("valid", false) and ref_pair.get("valid", false):
			_check(
				String(hot_pair.get("mesh_signature", "")) == String(ref_pair.get("mesh_signature", "")),
				"shared-boundary geometry signature is exact after compaction"
			)
			var diag: Dictionary = hot_pair.get("diagnostics", {})
			_check(int(diag.get("seam_bad_incidence_count", -1)) == 0, "compacted shared seam has zero bad incidence")
			_check(int(diag.get("t_junction_count", -1)) == 0, "compacted shared seam has zero T-junctions")

	var final_stats := fresh_store.get_hot_stats()
	evidence = {
		"edit_count": edit_count,
		"checkpoint_interval": CHECKPOINT_INTERVAL,
		"checkpoint_count": checkpoint_count,
		"admission_usec_total": admission_usec,
		"checkpoint_usec_total": checkpoint_usec_total,
		"checkpoint_usec_max": checkpoint_usec_max,
		"hot_load_usec": hot_load_usec,
		"first_chunk_snapshot_usec": first_snapshot_usec,
		"mesh_usec_total": mesh_usec_total,
		"density_fidelity_checks": density_checks,
		"mesh_fidelity_checks": mesh_checks,
		"hot_stats": final_stats,
		"journal_reads_on_gameplay_path": int(final_stats.get("journal_read_count", -1)),
		"lifetime_operations": hot_state.get_edit_count(),
		"live_tail_operations": hot_state.get_tail_edit_count(),
		"archived_operations": hot_state.get_archived_edit_count(),
	}
	_check(int(final_stats.get("journal_read_count", -1)) == 0, "entire gameplay qualification path reads zero archived journal segments")
	_check(_cleanup_tree(root), "qualification storage is cleaned")
	_finish()


func _requested_edit_count() -> int:
	var result := DEFAULT_EDIT_COUNT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--edits="):
			result = int(arg.trim_prefix("--edits="))
	return maxi(1, result)


func _operation_spec(index: int) -> Dictionary:
	# Deterministic bounded working set straddling the X=16 regional seam.
	# The world can grow without bound spatially; this fixture intentionally keeps
	# storage locality stable so history length is the independent variable.
	var lane_x := float((index * 37) % 33) * 0.25
	var lane_z := float((index * 19) % 41) * 0.25
	var lane_y := float((index * 11) % 13) * 0.25
	var center := Vector3(12.0 + lane_x, 0.75 + lane_y, 0.75 + lane_z)
	if index % 7 == 0:
		center.x = 15.5 + float(index % 5) * 0.25
	var radius := 0.55 + float(index % 4) * 0.10
	return {
		"mode": Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL,
		"center": center,
		"radius": radius,
	}


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
	print("SCALABLE_WORLD_QUALIFICATION_RESULT=" + JSON.stringify(payload))
	print("SCALABLE_WORLD_QUALIFICATION_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
