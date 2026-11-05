extends SceneTree

const Authority := preload("res://scripts/terrain/shared_surface_boundary_authority.gd")
const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Scalable := preload("res://scripts/terrain/terrain_scalable_sdf_state.gd")
const Store := preload("res://scripts/terrain/terrain_materialized_sdf_store.gd")
const MeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")

const SEED := 424242
const BASE_REGION := Vector2i.ZERO
const X_PAIR_Z_CHUNK := 1
const Z_PAIR_X_CHUNK := 1

var assertions := 0
var failures := 0
var evidence: Dictionary = {}
var _root := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_root = ProjectSettings.globalize_path(
		"user://global-shared-surface-%d" % Time.get_ticks_usec()
	)
	var oracle := Brush.new(SEED, Field.GENERATOR_VERSION)
	var scalable := Scalable.new(SEED, Field.GENERATOR_VERSION)
	var specs := _initial_edits()
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		_check(
			oracle.add_sphere(spec["mode"], spec["center"], spec["radius"])
				and scalable.add_sphere(spec["mode"], spec["center"], spec["radius"]),
			"initial edit %d accepted by oracle and scalable state" % index
		)
	if failures > 0:
		_cleanup_and_finish()
		return

	var store := Store.new(_root)
	var saved1: Dictionary = store.checkpoint_state(Store.WORLD_ID, scalable)
	_check(saved1.get("ok", false), "generation 1 materializes all initial edits")
	if not saved1.get("ok", false):
		_cleanup_and_finish()
		return

	store = null
	scalable = null
	var fresh_store := Store.new(_root)
	var loaded1: Dictionary = fresh_store.load_world(Store.WORLD_ID)
	_check(loaded1.get("ok", false) and loaded1.get("found", false), "fresh store loads generation 1")
	if not loaded1.get("ok", false) or not loaded1.get("found", false):
		_cleanup_and_finish()
		return
	var hot: RefCounted = loaded1["state"]
	_check(hot.get_tail_edit_count() == 0, "generation 1 reload has empty hot tail")
	_check(int(fresh_store.get_hot_stats().get("journal_read_count", -1)) == 0, "generation 1 hot load replays zero journal segments")

	var oracle_global := _build_global_geometry(oracle)
	var hot_global := _build_global_geometry(hot)
	_qualify_global_geometry("generation1", oracle_global, hot_global)

	var mixed := _qualify_mixed_lod(hot, hot_global)
	_check(mixed.get("valid", false), "mixed LOD collars build on X and Z")
	if mixed.get("valid", false):
		_check(int(mixed.get("bad_incidence", -1)) == 0, "mixed LOD has zero bad incidence")
		_check(int(mixed.get("t_junctions", -1)) == 0, "mixed LOD has zero T-junctions")
		_check(int(mixed.get("crossing_mismatch", -1)) == 0, "mixed LOD crossing edges are cross-owned")
		evidence["mixed_lod"] = mixed

	# A second generation proves new edits over a materialized base remain exact.
	var second_specs := [
		{"mode": Brush.Mode.CARVE, "center": Vector3(16.0, 2.1, 12.0), "radius": 1.15},
		{"mode": Brush.Mode.FILL, "center": Vector3(16.0, 1.4, 6.0), "radius": 0.85},
		{"mode": Brush.Mode.CARVE, "center": Vector3(8.0, 1.8, 12.0), "radius": 0.75},
	]
	for index in range(second_specs.size()):
		var spec: Dictionary = second_specs[index]
		_check(
			oracle.add_sphere(spec["mode"], spec["center"], spec["radius"])
				and hot.add_sphere(spec["mode"], spec["center"], spec["radius"]),
			"post-materialization edit %d accepted" % index
		)
	var edited_before_save := _build_global_geometry(hot)
	_check(
		String(edited_before_save.get("combined_signature", ""))
			!= String(hot_global.get("combined_signature", "")),
		"post-materialization edits change global boundary signature"
	)

	var saved2: Dictionary = fresh_store.checkpoint_state(Store.WORLD_ID, hot)
	_check(saved2.get("ok", false), "generation 2 materializes post-reload edits")
	if not saved2.get("ok", false):
		_cleanup_and_finish()
		return
	hot = null
	fresh_store = null
	var final_store := Store.new(_root)
	var loaded2: Dictionary = final_store.load_world(Store.WORLD_ID)
	_check(loaded2.get("ok", false) and loaded2.get("found", false), "fresh store loads generation 2")
	if loaded2.get("ok", false) and loaded2.get("found", false):
		var final_state: RefCounted = loaded2["state"]
		var oracle_final := _build_global_geometry(oracle)
		var final_global := _build_global_geometry(final_state)
		_qualify_global_geometry("generation2", oracle_final, final_global)
		_check(
			String(final_global.get("combined_signature", ""))
				== String(edited_before_save.get("combined_signature", "")),
			"generation 2 unload/reload preserves global boundary signature"
		)
		_check(final_state.get_tail_edit_count() == 0, "generation 2 reload has empty hot tail")
		_check(int(final_store.get_hot_stats().get("journal_read_count", -1)) == 0, "generation 2 hot load replays zero journal segments")
		evidence["final_signature"] = final_global.get("combined_signature", "")
		evidence["final_edit_count"] = final_state.get_edit_count()

	_cleanup_and_finish()


func _initial_edits() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"mode": Brush.Mode.FILL, "center": Vector3(16.0, 1.7, 12.0), "radius": 1.8},
		{"mode": Brush.Mode.CARVE, "center": Vector3(16.0, 1.7, 12.0), "radius": 0.8},
		{"mode": Brush.Mode.FILL, "center": Vector3(16.0, 1.9, 5.0), "radius": 1.4},
		{"mode": Brush.Mode.CARVE, "center": Vector3(16.0, 1.9, 5.4), "radius": 0.75},
		{"mode": Brush.Mode.FILL, "center": Vector3(5.0, 1.8, 12.0), "radius": 1.4},
		{"mode": Brush.Mode.CARVE, "center": Vector3(5.4, 1.8, 12.0), "radius": 0.75},
	]
	for index in range(90):
		var lane := index % 3
		var center: Vector3
		if lane == 0:
			center = Vector3(15.3 + float(index % 7) * 0.22, 0.8 + float(index % 11) * 0.18, 2.0 + float((index * 5) % 32) * 0.25)
		elif lane == 1:
			center = Vector3(2.0 + float((index * 7) % 48) * 0.25, 0.8 + float(index % 9) * 0.2, 11.3 + float(index % 7) * 0.22)
		else:
			center = Vector3(15.3 + float(index % 7) * 0.22, 0.8 + float(index % 10) * 0.19, 11.3 + float((index * 3) % 7) * 0.22)
		result.append({
			"mode": Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL,
			"center": center,
			"radius": 0.55 + float(index % 4) * 0.1,
		})
	return result


func _build_global_geometry(ledger: RefCounted) -> Dictionary:
	var x_snapshot := Authority.make_x_pair_snapshot(ledger, BASE_REGION, X_PAIR_Z_CHUNK)
	var z_snapshot := Authority.make_z_pair_snapshot(ledger, BASE_REGION, Z_PAIR_X_CHUNK)
	var corner_snapshot := Authority.make_xz_corner_snapshot(ledger, BASE_REGION)
	if not x_snapshot.get("valid", false) or not z_snapshot.get("valid", false) or not corner_snapshot.get("valid", false):
		return {
			"valid": false,
			"reason": "global_snapshot_failed",
			"x_snapshot": x_snapshot,
			"z_snapshot": z_snapshot,
			"corner_snapshot": corner_snapshot,
		}
	var x_pair := Authority.build_x_region_boundary_pair(SEED, BASE_REGION, X_PAIR_Z_CHUNK, x_snapshot)
	var z_pair := Authority.build_z_region_boundary_pair(SEED, BASE_REGION, Z_PAIR_X_CHUNK, z_snapshot)
	var corner := Authority.build_xz_corner_quad(SEED, BASE_REGION, corner_snapshot)
	if not x_pair.get("valid", false) or not z_pair.get("valid", false) or not corner.get("valid", false):
		return {
			"valid": false,
			"reason": "global_geometry_build_failed",
			"x": x_pair,
			"z": z_pair,
			"corner": corner,
		}
	return {
		"valid": true,
		"x": x_pair,
		"z": z_pair,
		"corner": corner,
		"combined_signature": "%s|%s|%s" % [
			String(x_pair.get("mesh_signature", "")),
			String(z_pair.get("mesh_signature", "")),
			String(corner.get("mesh_signature", "")),
		],
	}


func _qualify_global_geometry(label: String, oracle: Dictionary, candidate: Dictionary) -> void:
	_check(oracle.get("valid", false) and candidate.get("valid", false), "%s global X/Z/corner geometry builds" % label)
	if not oracle.get("valid", false) or not candidate.get("valid", false):
		return
	_check(
		String(candidate.get("combined_signature", "")) == String(oracle.get("combined_signature", "")),
		"%s materialized global geometry matches complete-ledger oracle" % label
	)
	var x_diag: Dictionary = candidate["x"].get("diagnostics", {})
	_check(int(x_diag.get("seam_edge_count", 0)) > 0, "%s X seam is non-empty" % label)
	_check(int(x_diag.get("seam_bad_incidence_count", -1)) == 0, "%s X seam has zero bad incidence" % label)
	_check(int(x_diag.get("t_junction_count", -1)) == 0, "%s X seam has zero T-junctions" % label)
	_check(int(x_diag.get("duplicate_triangle_count", -1)) == 0, "%s X seam has zero duplicate triangles" % label)
	_check(
		int(x_diag.get("seam_cross_owner_count", -1)) == int(x_diag.get("seam_crossing_edge_count", -2)),
		"%s X crossing edges are cross-owned" % label
	)
	var z_diag: Dictionary = candidate["z"].get("diagnostics", {})
	_check(int(z_diag.get("seam_edge_count", 0)) > 0, "%s Z seam is non-empty" % label)
	_check(int(z_diag.get("seam_bad_incidence_count", -1)) == 0, "%s Z seam has zero bad incidence" % label)
	_check(int(z_diag.get("t_junction_count", -1)) == 0, "%s Z seam has zero T-junctions" % label)
	_check(int(z_diag.get("duplicate_triangle_count", -1)) == 0, "%s Z seam has zero duplicate triangles" % label)
	_check(
		int(z_diag.get("seam_cross_owner_count", -1)) == int(z_diag.get("seam_crossing_edge_count", -2)),
		"%s Z crossing edges are cross-owned" % label
	)
	var corner_diag: Dictionary = candidate["corner"].get("diagnostics", {})
	_check(int(corner_diag.get("x_seam_bad_incidence_count", -1)) == 0, "%s corner X plane has zero bad incidence" % label)
	_check(int(corner_diag.get("z_seam_bad_incidence_count", -1)) == 0, "%s corner Z plane has zero bad incidence" % label)
	_check(int(corner_diag.get("x_t_junction_count", -1)) == 0, "%s corner X plane has zero T-junctions" % label)
	_check(int(corner_diag.get("z_t_junction_count", -1)) == 0, "%s corner Z plane has zero T-junctions" % label)
	_check(int(corner_diag.get("junction_bad_incidence_count", -1)) == 0, "%s four-region junction has zero bad incidence" % label)
	_check(int(corner_diag.get("junction_t_junction_count", -1)) == 0, "%s four-region junction has zero T-junctions" % label)
	_check(int(corner_diag.get("duplicate_triangle_count", -1)) == 0, "%s corner authority has zero duplicate triangles" % label)
	var corner_x: Dictionary = corner_diag.get("x", {})
	var corner_z: Dictionary = corner_diag.get("z", {})
	_check(int(corner_x.get("seam_edge_count", 0)) > 0, "%s corner volume intersects X seam" % label)
	_check(int(corner_z.get("seam_edge_count", 0)) > 0, "%s corner volume intersects Z seam" % label)
	_check(
		int(corner_x.get("seam_cross_owner_count", -1)) == int(corner_x.get("seam_crossing_edge_count", -2)),
		"%s corner X crossings are cross-owned" % label
	)
	_check(
		int(corner_z.get("seam_cross_owner_count", -1)) == int(corner_z.get("seam_crossing_edge_count", -2)),
		"%s corner Z crossings are cross-owned" % label
	)
	evidence[label] = {
		"signature": candidate.get("combined_signature", ""),
		"x": x_diag,
		"z": z_diag,
		"corner": corner_diag,
	}


func _qualify_mixed_lod(ledger: RefCounted, global_geometry: Dictionary) -> Dictionary:
	if not global_geometry.get("valid", false):
		return {"valid": false, "reason": "global_geometry_invalid"}
	var bad_incidence := 0
	var t_junctions := 0
	var crossing_mismatch := 0
	var edge_count := 0

	var x_pair: Dictionary = global_geometry["x"]
	var left_region := BASE_REGION
	var right_region := BASE_REGION + Vector2i(1, 0)
	var left_inner := Vector2i(Grid.CHUNK_COUNT_X - 2, X_PAIR_Z_CHUNK)
	var right_inner := Vector2i(1, X_PAIR_Z_CHUNK)
	var left_lod1 := _build_lod1(ledger, left_region, left_inner)
	var right_lod1 := _build_lod1(ledger, right_region, right_inner)
	if not left_lod1.get("valid", false) or not right_lod1.get("valid", false):
		return {"valid": false, "reason": "x_lod1_build_failed"}
	var left_boundary_origin := Spatial.region_origin_world(left_region) + Grid.origin_for(Vector2i(Grid.CHUNK_COUNT_X - 1, X_PAIR_Z_CHUNK))
	var left_inner_origin := Spatial.region_origin_world(left_region) + Grid.origin_for(left_inner)
	var right_boundary_origin := Spatial.region_origin_world(right_region) + Grid.origin_for(Vector2i(0, X_PAIR_Z_CHUNK))
	var right_inner_origin := Spatial.region_origin_world(right_region) + Grid.origin_for(right_inner)
	var z_min := left_boundary_origin.z
	var z_max := z_min + float(Grid.CELLS_PER_CHUNK_Z) * Grid.SAMPLE_STEP
	var x_left_diag := Authority.analyze_cpu_pair_plane(
		left_lod1, left_inner_origin, x_pair["left"], left_boundary_origin,
		left_boundary_origin.x, Grid.MIN_BOUND.y, Grid.MAX_BOUND.y, z_min, z_max
	)
	var x_right_diag := Authority.analyze_cpu_pair_plane(
		x_pair["right"], right_boundary_origin, right_lod1, right_inner_origin,
		right_inner_origin.x, Grid.MIN_BOUND.y, Grid.MAX_BOUND.y, z_min, z_max
	)
	for diag_value in [x_left_diag, x_right_diag]:
		var diag: Dictionary = diag_value
		edge_count += int(diag.get("seam_edge_count", 0))
		bad_incidence += int(diag.get("seam_bad_incidence_count", 0))
		t_junctions += int(diag.get("t_junction_count", 0))
		crossing_mismatch += int(diag.get("seam_crossing_edge_count", 0)) - int(diag.get("seam_cross_owner_count", 0))

	var z_pair: Dictionary = global_geometry["z"]
	var low_region := BASE_REGION
	var high_region := BASE_REGION + Vector2i(0, 1)
	var low_inner := Vector2i(Z_PAIR_X_CHUNK, Grid.CHUNK_COUNT_Z - 2)
	var high_inner := Vector2i(Z_PAIR_X_CHUNK, 1)
	var low_lod1 := _build_lod1(ledger, low_region, low_inner)
	var high_lod1 := _build_lod1(ledger, high_region, high_inner)
	if not low_lod1.get("valid", false) or not high_lod1.get("valid", false):
		return {"valid": false, "reason": "z_lod1_build_failed"}
	var low_boundary_origin := Spatial.region_origin_world(low_region) + Grid.origin_for(Vector2i(Z_PAIR_X_CHUNK, Grid.CHUNK_COUNT_Z - 1))
	var low_inner_origin := Spatial.region_origin_world(low_region) + Grid.origin_for(low_inner)
	var high_boundary_origin := Spatial.region_origin_world(high_region) + Grid.origin_for(Vector2i(Z_PAIR_X_CHUNK, 0))
	var high_inner_origin := Spatial.region_origin_world(high_region) + Grid.origin_for(high_inner)
	var x_min := low_boundary_origin.x
	var x_max := x_min + float(Grid.CELLS_PER_CHUNK_X) * Grid.SAMPLE_STEP
	var z_low_diag := Authority.analyze_cpu_pair_plane_z(
		low_lod1, low_inner_origin, z_pair["low"], low_boundary_origin,
		low_boundary_origin.z, Grid.MIN_BOUND.y, Grid.MAX_BOUND.y, x_min, x_max
	)
	var z_high_diag := Authority.analyze_cpu_pair_plane_z(
		z_pair["high"], high_boundary_origin, high_lod1, high_inner_origin,
		high_inner_origin.z, Grid.MIN_BOUND.y, Grid.MAX_BOUND.y, x_min, x_max
	)
	for diag_value in [z_low_diag, z_high_diag]:
		var diag: Dictionary = diag_value
		edge_count += int(diag.get("seam_edge_count", 0))
		bad_incidence += int(diag.get("seam_bad_incidence_count", 0))
		t_junctions += int(diag.get("t_junction_count", 0))
		crossing_mismatch += int(diag.get("seam_crossing_edge_count", 0)) - int(diag.get("seam_cross_owner_count", 0))
	return {
		"valid": true,
		"edge_count": edge_count,
		"bad_incidence": bad_incidence,
		"t_junctions": t_junctions,
		"crossing_mismatch": crossing_mismatch,
		"x_left": x_left_diag,
		"x_right": x_right_diag,
		"z_low": z_low_diag,
		"z_high": z_high_diag,
	}


func _build_lod1(ledger: RefCounted, region_key: Vector2i, coordinate: Vector2i) -> Dictionary:
	var snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region_key, coordinate)
	if not snapshot.get("valid", false):
		return {"valid": false, "reason": "snapshot_failed"}
	var job := MeshJob.new(
		SEED, region_key, coordinate, false, snapshot, Time.get_ticks_usec(), 1
	)
	job.run()
	return job.result


func _cleanup_and_finish() -> void:
	evidence["storage_cleaned"] = _cleanup_tree(_root)
	_finish()


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
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	var payload := {
		"status": "PASS" if failures == 0 else "FAIL",
		"assertions": assertions,
		"failures": failures,
		"evidence": evidence,
	}
	print("GLOBAL_SHARED_SURFACE_RESULT=" + JSON.stringify(payload))
	print("GLOBAL_SHARED_SURFACE_%s: assertions=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", assertions, failures
	])
	quit(0 if failures == 0 else 1)
