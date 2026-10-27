extends SceneTree

const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const ChunkProjection := preload("res://tests/prototypes/r4_chunk_subledger.gd")
const Voxel := preload("res://tests/prototypes/r4_voxel_snapshot.gd")
const DerivedCache := preload("res://tests/prototypes/r4_derived_mesh_cache.gd")
const EntityViews := preload("res://tests/prototypes/r4_entity_snapshot_views.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const BenchmarkMetrics := preload("res://tests/prototypes/r4_benchmark_metrics.gd")

var _assertions := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := "user://p31-r4-test-" + str(Time.get_ticks_usec())
	var absolute_root := ProjectSettings.globalize_path(root)
	DirAccess.make_dir_recursive_absolute(absolute_root)
	var byte_fixture := absolute_root.path_join("bytes")
	DirAccess.make_dir_recursive_absolute(byte_fixture.path_join("nested/deeper"))
	var top_file := FileAccess.open(byte_fixture.path_join("top.bin"), FileAccess.WRITE)
	top_file.store_buffer(PackedByteArray([1, 2, 3]))
	top_file.close()
	var nested_file := FileAccess.open(byte_fixture.path_join("nested/deeper/child.bin"), FileAccess.WRITE)
	nested_file.store_buffer(PackedByteArray([4, 5, 6, 7, 8]))
	nested_file.close()
	_check(BenchmarkMetrics.directory_bytes(byte_fixture) == 8, "recursive_storage_byte_accounting")
	_check(BenchmarkMetrics.directory_bytes(byte_fixture.path_join("absent")) == 0,
		"absent_storage_directory_is_zero")
	var region := Vector2i(-1, -1)
	var chunk := Vector2i(3, 3)
	var ledger: RefCounted = Brush.new(131102026, 1)
	var command_count := 48
	for index in range(command_count):
		var center: Vector3
		if index % 4 == 0:
			center = Spatial.region_origin_world(region) + Vector3(15.8, 2.7, 11.8)
		else:
			center = Spatial.region_origin_world(region) + Vector3(12.5 + float(index % 3) * 0.08,
				2.1 + float(index % 5) * 0.11, 8.0 + float(index % 7) * 0.07)
		var mode := Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
		_check(ledger.add_sphere(mode, center, 0.58), "ledger_append_%d" % index)
	var projection: RefCounted = ChunkProjection.from_ledger(ledger, region, chunk)
	_check(projection != null, "projection_build")
	if projection == null:
		_quit_with_result(absolute_root)
		return
	var projected: Dictionary = projection.as_snapshot()
	var canonical: Dictionary = ledger.get_meshing_snapshot()
	_check(projected.sequences.size() == projected.centers.size(), "projection_sequence_cardinality")
	_check(projected.revision == ledger.revision, "projection_revision_matches_ledger")
	var exact_probe_count := 0
	for index in range(64):
		var local := Vector3(11.8 + float(index % 17) * 0.26,
			-2.2 + float(index % 23) * 0.46, 9.8 + float(index % 19) * 0.13)
		var full_value := Brush.sample_density_snapshot(131102026, region, local, false, canonical)
		var projected_value := Brush.sample_density_snapshot(131102026, region, local, false, projected)
		if full_value == projected_value:
			exact_probe_count += 1
	_check(exact_probe_count == 64, "projection_density_exact_64_probes")
	var saved_projection: Dictionary = projection.save_atomic(absolute_root.path_join("subledgers"))
	_check(bool(saved_projection.get("valid", false)), "projection_atomic_save_and_verify")
	var reloaded: RefCounted = ChunkProjection.new()
	var loaded: bool = reloaded.load_into(String(saved_projection.get("path", "")), projection.identity)
	_check(loaded and reloaded.digest() == projection.digest(), "projection_restart_digest")
	var corrupt_path := String(saved_projection.get("path", ""))
	if FileAccess.file_exists(corrupt_path):
		var corrupt_file := FileAccess.open(corrupt_path, FileAccess.READ_WRITE)
		if corrupt_file != null:
			var corrupt_bytes := corrupt_file.get_buffer(corrupt_file.get_length())
			if not corrupt_bytes.is_empty():
				corrupt_bytes[corrupt_bytes.size() - 1] = corrupt_bytes[-1] ^ 0x40
				corrupt_file.seek(0)
				corrupt_file.store_buffer(corrupt_bytes)
			corrupt_file.close()
		_check(not reloaded.load_into(corrupt_path, projection.identity), "projection_corruption_rejected")
	else:
		_check(false, "projection_corruption_fixture_exists")
	var semantic_projection_save: Dictionary = projection.save_atomic(absolute_root.path_join("subledgers-semantic"))
	var semantic_projection_path := String(semantic_projection_save.get("path", ""))
	var semantic_projection_envelope: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(semantic_projection_path))
	var semantic_projection_payload: PackedByteArray = semantic_projection_envelope.payload
	var semantic_projection_data: Dictionary = bytes_to_var(semantic_projection_payload)
	var semantic_modes: PackedByteArray = semantic_projection_data.modes
	semantic_modes[0] = 2
	semantic_projection_data.modes = semantic_modes
	semantic_projection_payload = var_to_bytes(semantic_projection_data)
	semantic_projection_envelope.payload = semantic_projection_payload
	semantic_projection_envelope.payload_sha256 = _sha256(semantic_projection_payload)
	var semantic_projection_file := FileAccess.open(semantic_projection_path, FileAccess.WRITE)
	semantic_projection_file.store_buffer(var_to_bytes(semantic_projection_envelope))
	semantic_projection_file.close()
	var semantic_projection_reject: RefCounted = ChunkProjection.new()
	_check(not semantic_projection_reject.load_into(semantic_projection_path, projection.identity)
		and String(semantic_projection_reject.last_reason) == "projection_operation_invalid",
		"projection_rehashed_invalid_mode_rejected")
	var before_revision: int = ledger.revision
	_check(ledger.add_sphere(Brush.Mode.CARVE,
		Spatial.region_origin_world(region) + Vector3(13.1, 1.8, 9.2), 0.58), "append_delta_accept")
	var updated_projection_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var old_projection_count: int = projected.centers.size()
	var append_ok: bool = projection.append_snapshot(updated_projection_snapshot)
	_check(append_ok and projection.revision == before_revision + 1, "projection_incremental_revision")
	var rebuilt_projection: RefCounted = ChunkProjection.from_ledger(ledger, region, chunk)
	_check(rebuilt_projection != null and projection.digest() == rebuilt_projection.digest(), "projection_incremental_equals_rebuild")
	var projection_digest_before_reject: String = projection.digest()
	var tampered_prefix: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var tampered_centers: PackedVector3Array = tampered_prefix.get("centers", PackedVector3Array())
	if not tampered_centers.is_empty():
		tampered_centers[0] += Vector3(0.001, 0.0, 0.0)
		tampered_prefix["centers"] = tampered_centers
		tampered_prefix["revision"] = projection.revision + 1
		_check(not projection.append_snapshot(tampered_prefix)
			and projection.digest() == projection_digest_before_reject,
			"projection_mutated_prefix_rejected_atomically")
	else:
		_check(false, "projection_mutated_prefix_fixture_exists")
	var invalid_delta_snapshot: Dictionary = projection.as_snapshot()
	var invalid_delta_centers: PackedVector3Array = invalid_delta_snapshot.centers.duplicate()
	var invalid_delta_radii: PackedFloat64Array = invalid_delta_snapshot.radii.duplicate()
	var invalid_delta_modes: PackedByteArray = invalid_delta_snapshot.modes.duplicate()
	var invalid_delta_sequences: PackedInt32Array = invalid_delta_snapshot.sequences.duplicate()
	var next_sequence := int(invalid_delta_sequences[-1]) + 1 if not invalid_delta_sequences.is_empty() else 0
	invalid_delta_centers.append(Vector3(-2.0, 1.0, -2.0))
	invalid_delta_centers.append(Vector3(-2.1, 1.0, -2.0))
	invalid_delta_radii.append(0.58)
	invalid_delta_radii.append(0.58)
	invalid_delta_modes.append(0)
	invalid_delta_modes.append(2)
	invalid_delta_sequences.append(next_sequence)
	invalid_delta_sequences.append(next_sequence + 1)
	invalid_delta_snapshot["centers"] = invalid_delta_centers
	invalid_delta_snapshot["radii"] = invalid_delta_radii
	invalid_delta_snapshot["modes"] = invalid_delta_modes
	invalid_delta_snapshot["sequences"] = invalid_delta_sequences
	invalid_delta_snapshot["candidate_operation_count"] = invalid_delta_centers.size()
	invalid_delta_snapshot["revision"] = projection.revision + 3
	var digest_before_invalid_append: String = projection.digest()
	_check(not projection.append_snapshot(invalid_delta_snapshot)
		and projection.digest() == digest_before_invalid_append,
		"projection_invalid_suffix_rejected_without_partial_append")
	var full_after: Dictionary = ledger.get_meshing_snapshot()
	var inc_after: Dictionary = projection.as_snapshot()
	var parity_after := 0
	for index in range(64):
		var local := Vector3(11.8 + float(index % 17) * 0.26,
			-2.2 + float(index % 23) * 0.46, 9.8 + float(index % 19) * 0.13)
		if Brush.sample_density_snapshot(131102026, region, local, false, full_after) \
			== Brush.sample_density_snapshot(131102026, region, local, false, inc_after):
			parity_after += 1
	_check(parity_after == 64, "projection_post_append_exact")
	var sequence_replay := _verify_incremental_sequence_replay()
	_check(bool(sequence_replay.get("valid", false)), "multi_revision_snapshot_and_subledger_replay")
	var c_tail_capture := _verify_combined_tail_snapshot_capture()
	if not bool(c_tail_capture.get("valid", false)):
		print("P31_R4_C_TAIL_DIAGNOSTIC ", JSON.stringify(c_tail_capture))
	_check(bool(c_tail_capture.get("valid", false)), "combined_c_tail_uses_pre_append_snapshot_once")

	# Snapshot materialization is intentionally approximate: float32 storage and
	# trilinear sampling are measured against the canonical continuous oracle.
	var base_ledger: RefCounted = Brush.new(131102026, 1)
	for index in range(command_count):
		var op: Dictionary = ledger.get_persistence_page(index, 1)[0]
		var base_mode: int = int(op.mode)
		_check(base_ledger.add_sphere(base_mode, op.center_world, float(op.radius)), "base_ledger_restore_%d" % index)
	var base_projection: Dictionary = base_ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var voxel := Voxel.new()
	var built := voxel.materialize(131102026, region, chunk, base_projection, 0.5)
	_check(built, "voxel_snapshot_materialize")
	var last_operation: Dictionary = ledger.get_last_operation_snapshot()
	var delta_ok := voxel.apply_operation(last_operation)
	_check(delta_ok, "voxel_snapshot_incremental_delta")
	var densities_before_rejected_delta: PackedFloat32Array = voxel.densities.duplicate()
	_check(not voxel.apply_operation(last_operation) and voxel.densities == densities_before_rejected_delta,
		"voxel_duplicate_delta_rejected_without_mutation")
	_check(not voxel.advance_revision_without_geometry(voxel.revision + 2),
		"voxel_revision_gap_rejected")
	_check(voxel.advance_revision_without_geometry(voxel.revision + 1),
		"voxel_remote_revision_advance_contiguous")
	var voxel_stats := voxel.statistics()
	_check(int(voxel_stats.voxel_count) > 0 and int(voxel_stats.payload_bytes) == int(voxel_stats.voxel_count) * 4,
		"voxel_float32_accounting")
	var max_node_error := 0.0
	var total_node_error := 0.0
	var compared_nodes := 0
	for y in range(voxel.ny):
		for z in range(voxel.nz):
			for x in range(voxel.nx):
				var point := voxel.world_min + Vector3(x, y, z) * voxel.spacing
				var local := point - Spatial.region_origin_world(region)
				var expected := Brush.sample_density_snapshot(131102026, region, local, false, full_after)
				var error := absf(float(voxel.densities[voxel._index(x, y, z)]) - expected)
				max_node_error = maxf(max_node_error, error)
				total_node_error += error
				compared_nodes += 1
	_check(max_node_error < 0.00001, "voxel_grid_node_float32_error_bounded")
	var voxel_path: Dictionary = voxel.save_atomic(absolute_root.path_join("voxels"))
	_check(bool(voxel_path.get("valid", false)), "voxel_snapshot_atomic_save")
	var voxel_reload := Voxel.new()
	_check(voxel_reload.load_file(String(voxel_path.get("path", "")), region, chunk,
		0.5, 131102026, 1), "voxel_snapshot_restart_integrity")
	var voxel_file := FileAccess.open(String(voxel_path.get("path", "")), FileAccess.READ_WRITE)
	if voxel_file != null:
		var voxel_bytes := voxel_file.get_buffer(voxel_file.get_length())
		if not voxel_bytes.is_empty():
			voxel_bytes[voxel_bytes.size() - 1] = voxel_bytes[-1] ^ 0x20
			voxel_file.seek(0)
			voxel_file.store_buffer(voxel_bytes)
		voxel_file.close()
	_check(not voxel_reload.load_file(String(voxel_path.get("path", "")), region, chunk,
		0.5, 131102026, 1), "voxel_corruption_rejected")
	var semantic_voxel_save: Dictionary = voxel.save_atomic(absolute_root.path_join("voxel-semantic"))
	var semantic_voxel_path := String(semantic_voxel_save.get("path", ""))
	var semantic_voxel_envelope: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(semantic_voxel_path))
	var semantic_voxel_data: Dictionary = bytes_to_var(semantic_voxel_envelope.payload)
	var semantic_densities: PackedFloat32Array = semantic_voxel_data.densities
	semantic_densities[0] = NAN
	semantic_voxel_data.densities = semantic_densities
	var semantic_voxel_payload := var_to_bytes(semantic_voxel_data)
	semantic_voxel_envelope.payload = semantic_voxel_payload
	semantic_voxel_envelope.payload_sha256 = _sha256(semantic_voxel_payload)
	var semantic_voxel_file := FileAccess.open(semantic_voxel_path, FileAccess.WRITE)
	semantic_voxel_file.store_buffer(var_to_bytes(semantic_voxel_envelope))
	semantic_voxel_file.close()
	var semantic_voxel_reload: RefCounted = Voxel.new()
	_check(not semantic_voxel_reload.load_file(semantic_voxel_path, region, chunk, 0.5, 131102026, 1)
		and String(semantic_voxel_reload.last_reason) == "voxel_density_nonfinite"
		and int(semantic_voxel_reload.revision) == -1,
		"voxel_rehashed_nonfinite_payload_rejected_atomically")

	# Bounded logical entity-sharing model: terrain snapshot bytes are shared by
	# content identity while every entity retains independently revisioned state.
	var entity_views: RefCounted = EntityViews.new()
	var shared_terrain_hash: String = entity_views.register_terrain(voxel)
	_check(not shared_terrain_hash.is_empty(), "entity_shared_terrain_snapshot_registered")
	_check(entity_views.attach_entity("entity-a", shared_terrain_hash, {"health": 1, "label": "a"}),
		"entity_view_a_attached")
	_check(entity_views.attach_entity("entity-b", shared_terrain_hash, {"health": 1, "label": "b"}),
		"entity_view_b_attached")
	var terrain_revision := int(voxel.revision)
	_check(entity_views.update_entity("entity-a", 0, terrain_revision, "health", 7),
		"entity_a_revision_update")
	var entity_a_state: Dictionary = entity_views.entity_snapshot("entity-a")
	var entity_b_state: Dictionary = entity_views.entity_snapshot("entity-b")
	_check(int(entity_a_state.revision) == 1 and int(entity_a_state.state.health) == 7,
		"entity_a_state_revisioned")
	_check(int(entity_b_state.revision) == 0 and int(entity_b_state.state.health) == 1,
		"entity_b_state_remains_separate")
	_check(not entity_views.update_entity("entity-a", 0, terrain_revision, "health", 9)
		and String(entity_views.last_reason) == "stale_entity_or_terrain_revision",
		"entity_stale_writer_rejected")
	_check(not entity_views.update_entity("entity-b", 0, terrain_revision + 1, "health", 9)
		and String(entity_views.last_reason) == "stale_entity_or_terrain_revision",
		"entity_stale_terrain_revision_rejected")
	var entity_view_stats: Dictionary = entity_views.stats()
	_check(int(entity_view_stats.unique_terrain_snapshots) == 1 and int(entity_view_stats.entity_views) == 2,
		"entity_terrain_payload_shared_once")
	_check(int(entity_view_stats.total_bytes) <= int(entity_view_stats.quota_bytes)
		and int(entity_view_stats.density_payload_bytes_once) == int(voxel.densities.size()) * 4,
		"entity_view_storage_bounded_and_separated")
	_check(entity_views.register_terrain(voxel) == shared_terrain_hash,
		"entity_update_does_not_change_terrain_identity")
	var oversized_state := PackedByteArray()
	oversized_state.resize(EntityViews.MAX_BYTES + 1)
	_check(not entity_views.attach_entity("entity-oversize", shared_terrain_hash,
		{"blob": oversized_state}) and entity_views.entity_snapshot("entity-oversize").is_empty(),
		"entity_view_quota_rejects_without_partial_publication")

	# A single accepted brush crosses the signed region seam. Independent chunk
	# projections must publish the same source revision and agree with full replay
	# at the shared world-space face sample.
	var seam_ledger: RefCounted = Brush.new(131102026, 1)
	_check(seam_ledger.add_sphere(Brush.Mode.CARVE, Vector3(-0.08, 2.0, -0.08), 0.58),
		"cross_region_seam_command_accepted")
	var seam_full: Dictionary = seam_ledger.get_meshing_snapshot()
	var seam_left: Dictionary = seam_ledger.get_meshing_snapshot_for_chunk(Vector2i(-1, -1), Vector2i(3, 3))
	var seam_right: Dictionary = seam_ledger.get_meshing_snapshot_for_chunk(Vector2i(0, -1), Vector2i(0, 3))
	_check(bool(seam_left.get("valid", false)) and bool(seam_right.get("valid", false)),
		"cross_region_seam_projections_valid")
	_check(int(seam_left.revision) == int(seam_right.revision) and int(seam_left.revision) == seam_ledger.revision,
		"cross_region_chunks_share_ledger_revision")
	var seam_world_point := Vector3(0.0, 2.0, -0.08)
	var seam_left_local := seam_world_point - Spatial.region_origin_world(Vector2i(-1, -1))
	var seam_right_local: Dictionary = Spatial.world_to_region_local(seam_world_point)
	var seam_left_density := Brush.sample_density_snapshot(131102026, Vector2i(-1, -1),
		seam_left_local, false, seam_left)
	var seam_right_density := Brush.sample_density_snapshot(131102026, Vector2i(0, -1),
		seam_right_local.local_position, false, seam_right)
	var seam_full_density := Brush.sample_density_snapshot(131102026, Vector2i(-1, -1),
		seam_left_local, false, seam_full)
	var seam_full_right_density := Brush.sample_density_snapshot(131102026, Vector2i(0, -1),
		seam_right_local.local_position, false, seam_full)
	_check(seam_left_density == seam_full_density and seam_right_density == seam_full_right_density
		and seam_full_density == seam_full_right_density,
		"cross_region_shared_face_density_matches_canonical")

	var callback := Callable(voxel, "sample_world")
	var canonical_mesh0 := Mesher.build_chunk_cpu_data(131102026, region, chunk, false, full_after)
	var snapshot_mesh0 := Mesher.build_chunk_cpu_data(131102026, region, chunk, false, full_after, callback)
	var canonical_mesh1 := LodMesher.build_chunk_cpu_data(131102026, region, chunk, full_after)
	var snapshot_mesh1 := LodMesher.build_chunk_cpu_data(131102026, region, chunk, inc_after, callback)
	_check(bool(canonical_mesh0.get("valid", false)) and bool(snapshot_mesh0.get("valid", false)), "lod0_meshes_valid")
	_check(bool(canonical_mesh1.get("valid", false)) and bool(snapshot_mesh1.get("valid", false)), "lod1_meshes_valid")
	var mesh_identity := {"world_seed": 131102026, "generator_version": 1, "region": region,
		"chunk": chunk, "lod": 0,
		"projection_sha256": projection.digest(),
		"voxel_snapshot_sha256": _sha256(var_to_bytes(voxel.densities)),
		"snapshot_resolution": voxel.spacing,
		"halo_contract": "production-mesh-query-v1", "mesher": "marching-tetrahedra-v1"}
	var mesh_cache_root := absolute_root.path_join("mesh-cache")
	var mesh_cache: RefCounted = DerivedCache.new(mesh_cache_root)
	var cold_cache_result: Dictionary = mesh_cache.get_or_build(mesh_identity, func() -> Dictionary: return snapshot_mesh0)
	_check(bool(cold_cache_result.get("valid", false)) and _mesh_equal(cold_cache_result, snapshot_mesh0), "combined_cache_cold_exact")
	var warm_cache_result: Dictionary = mesh_cache.get_or_build(mesh_identity, func() -> Dictionary: return {})
	_check(bool(warm_cache_result.get("cache_hit", false)) and _mesh_equal(warm_cache_result, snapshot_mesh0), "combined_cache_memory_hit")
	var disk_cache: RefCounted = DerivedCache.new(mesh_cache_root)
	var disk_cache_result: Dictionary = disk_cache.get_or_build(mesh_identity, func() -> Dictionary: return {})
	_check(bool(disk_cache_result.get("cache_hit", false)) and String(disk_cache_result.get("cache_layer", "")) == "disk",
		"combined_cache_restart_hit")
	var remote_ledger: RefCounted = Brush.new(131102026, 1)
	for index in range(ledger.get_edit_count()):
		var remote_op: Dictionary = ledger.get_persistence_page(index, 1)[0]
		_check(remote_ledger.add_sphere(int(remote_op.mode), remote_op.center_world, float(remote_op.radius)), "remote_copy_%d" % index)
	_check(remote_ledger.add_sphere(Brush.Mode.CARVE, Vector3(20000.0, 2.0, -20000.0), 0.58), "remote_edit_add")
	var remote_projection: RefCounted = ChunkProjection.from_ledger(remote_ledger, region, chunk)
	_check(remote_projection != null and remote_projection.digest() == projection.digest(), "remote_edit_projection_stable")
	var remote_identity := mesh_identity.duplicate(true)
	remote_identity["projection_sha256"] = remote_projection.digest()
	var remote_cache: RefCounted = DerivedCache.new(mesh_cache_root)
	var remote_cache_result: Dictionary = remote_cache.get_or_build(remote_identity, func() -> Dictionary: return {})
	_check(bool(remote_cache_result.get("cache_hit", false)), "remote_edit_cache_hit")
	var local_identity := mesh_identity.duplicate(true)
	local_identity["projection_sha256"] = projection.digest() + "-local-change"
	var local_cache: RefCounted = DerivedCache.new(mesh_cache_root)
	var local_cache_result: Dictionary = local_cache.get_or_build(local_identity, func() -> Dictionary: return snapshot_mesh0)
	_check(bool(local_cache_result.get("valid", false)) and not bool(local_cache_result.get("cache_hit", true)),
		"local_edit_cache_miss_rebuild")
	var canonical_cache_path := mesh_cache_root.path_join(_sha256(var_to_bytes(mesh_identity)) + ".bin")
	var cache_corrupted := false
	var cache_file := FileAccess.open(canonical_cache_path, FileAccess.READ_WRITE)
	if cache_file != null:
		var cache_bytes := cache_file.get_buffer(cache_file.get_length())
		if not cache_bytes.is_empty():
			cache_bytes[cache_bytes.size() - 1] = cache_bytes[-1] ^ 0x08
			cache_file.seek(0)
			cache_file.store_buffer(cache_bytes)
			cache_corrupted = true
		cache_file.close()
	_check(cache_corrupted, "combined_cache_corruption_fixture_created")
	var fallback_cache: RefCounted = DerivedCache.new(mesh_cache_root)
	var fallback_result: Dictionary = fallback_cache.get_or_build(mesh_identity, func() -> Dictionary: return snapshot_mesh0)
	_check(bool(fallback_result.get("valid", false)) and not bool(fallback_result.get("cache_hit", true))
		and int(fallback_cache.corrupt_count) == 1 and _mesh_equal(fallback_result, snapshot_mesh0),
		"combined_cache_corruption_fallback_exact")
	var report := {"status": "PASS" if _failures.is_empty() else "FAIL", "assertions": _assertions,
		"failures": _failures, "source_sha": OS.get_environment("P31_R4_SOURCE_SHA"),
		"projection_exact_probes": exact_probe_count, "projection_post_append_exact_probes": parity_after,
		"projection_candidates": projected.centers.size(), "projection_count_before_append": old_projection_count,
		"incremental_sequence_replay": sequence_replay,
		"voxel_stats": voxel_stats, "voxel_compared_nodes": compared_nodes,
		"voxel_max_node_error": max_node_error,
		"entity_snapshot_sharing_model": entity_view_stats,
		"voxel_mean_node_error": total_node_error / float(maxi(1, compared_nodes)),
		"lod0_canonical_vertices": int(canonical_mesh0.get("vertex_count", 0)),
		"lod0_snapshot_vertices": int(snapshot_mesh0.get("vertex_count", 0)),
		"lod1_canonical_vertices": int(canonical_mesh1.get("vertex_count", 0)),
		"lod1_snapshot_vertices": int(snapshot_mesh1.get("vertex_count", 0)),
		"lod1_snapshot_reason": String(snapshot_mesh1.get("reason", "")),
		"lod1_snapshot_sample_count": int(snapshot_mesh1.get("sample_count", -1)),
		"mesh_cache": mesh_cache.stats()}
	var result := FileAccess.open(absolute_root.path_join("focused-result.json"), FileAccess.WRITE)
	if result != null:
		result.store_string(JSON.stringify(report, "\t", true) + "\n")
		result.close()
	print("P31_R4_ARCH_TESTS_%s assertions=%d failures=%d" % [report.status, _assertions, _failures.size()])
	if not _failures.is_empty():
		push_error("p31_r4_architecture_test_failures: " + ",".join(_failures))
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func _mesh_equal(a: Dictionary, b: Dictionary) -> bool:
	return a.get("positions", PackedVector3Array()) == b.get("positions", PackedVector3Array()) \
		and a.get("normals", PackedVector3Array()) == b.get("normals", PackedVector3Array()) \
		and int(a.get("triangle_count", -1)) == int(b.get("triangle_count", -2))


func _verify_incremental_sequence_replay() -> Dictionary:
	var region := Vector2i(-1, -1)
	var chunk := Vector2i(3, 3)
	var ledger: RefCounted = Brush.new(131102026, 1)
	var initial_projected: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var projection: RefCounted = ChunkProjection.from_ledger(ledger, region, chunk)
	var voxel_b: RefCounted = Voxel.new()
	var voxel_c: RefCounted = Voxel.new()
	if projection == null or not voxel_b.materialize(131102026, region, chunk, initial_projected, 0.5) \
		or not voxel_c.materialize(131102026, region, chunk, projection.as_snapshot(), 0.5):
		return {"valid": false, "reason": "initial_snapshot_materialization_failed"}
	var projection_fallbacks := 0
	var max_b_error := 0.0
	var max_c_error := 0.0
	var remote_count := 0
	for index in range(6):
		var mode := Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
		var center := Spatial.region_origin_world(region) + Vector3(15.72 + float(index % 2) * 0.05,
			1.4 + float(index % 3) * 0.17, 11.72 - float(index % 2) * 0.04)
		if index == 5: center = Vector3(20000.0, 2.0, -20000.0)
		if not ledger.add_sphere(mode, center, 0.58): return {"valid": false, "reason": "ledger_reject_%d" % index}
		var operation: Dictionary = ledger.get_last_operation_snapshot()
		if not voxel_b.apply_operation(operation): return {"valid": false, "reason": "B_delta_reject_%d" % index}
		var next_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
		var included: bool = next_snapshot.sequences.has(int(operation.sequence))
		if included:
			if not voxel_c.apply_operation(operation): return {"valid": false, "reason": "C_delta_reject_%d" % index}
		else:
			remote_count += 1
			if not voxel_c.advance_revision_without_geometry(int(operation.revision)):
				return {"valid": false, "reason": "C_revision_advance_reject_%d" % index}
		if not projection.append_snapshot(next_snapshot):
			projection_fallbacks += 1
			projection = ChunkProjection.from_ledger(ledger, region, chunk)
			if projection == null: return {"valid": false, "reason": "projection_rebuild_failed_%d" % index}
		var rebuilt: RefCounted = ChunkProjection.from_ledger(ledger, region, chunk)
		if rebuilt == null or projection.digest() != rebuilt.digest():
			return {"valid": false, "reason": "projection_replay_mismatch_%d" % index}
		var full: Dictionary = ledger.get_meshing_snapshot()
		var error_b := _voxel_max_node_error(voxel_b, full, region)
		var error_c := _voxel_max_node_error(voxel_c, full, region)
		max_b_error = maxf(max_b_error, error_b)
		max_c_error = maxf(max_c_error, error_c)
		if error_b > 0.00001 or error_c > 0.00001 \
			or int(voxel_b.revision) != int(operation.revision) or int(voxel_c.revision) != int(operation.revision):
			return {"valid": false, "reason": "snapshot_parity_or_revision_failed_%d" % index}
	return {"valid": true, "commands": 6, "remote_commands": remote_count,
		"projection_rebuild_fallbacks": projection_fallbacks,
		"B_max_node_error": max_b_error, "C_max_node_error": max_c_error,
		"final_revision": int(ledger.revision), "signed_region": [region.x, region.y]}


func _verify_combined_tail_snapshot_capture() -> Dictionary:
	var region := Vector2i(-1, -1)
	var chunk := Vector2i(3, 3)
	var ledger: RefCounted = Brush.new(131102026, 1)
	var center := Spatial.region_origin_world(region) + Vector3(15.78, 2.3, 11.74)
	if not ledger.add_sphere(Brush.Mode.CARVE, center, 0.58):
		return {"valid": false, "reason": "tail_ledger_append_failed"}
	var tail_operation: Dictionary = ledger.get_last_operation_snapshot()
	var base_ledger: RefCounted = Brush.new(131102026, 1)
	var base_projection: RefCounted = ChunkProjection.from_ledger(base_ledger, region, chunk)
	if base_projection == null:
		return {"valid": false, "reason": "base_projection_build_failed"}
	var pre_append_snapshot: Dictionary = base_projection.as_snapshot()
	var complete_projection: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	if not base_projection.append_snapshot(complete_projection):
		return {"valid": false, "reason": "projection_append_failed"}
	if int(pre_append_snapshot.revision) != 0 or not pre_append_snapshot.centers.is_empty() \
		or int(base_projection.revision) != 1 or base_projection.centers.size() != 1:
		return {"valid": false, "reason": "captured_projection_not_pre_append_state",
			"captured_revision": int(pre_append_snapshot.revision), "captured_count": pre_append_snapshot.centers.size(),
			"projection_revision": int(base_projection.revision), "projection_count": base_projection.centers.size(),
			"sequence": int(tail_operation.sequence), "ledger_revision": int(ledger.revision)}
	var c_incremental: RefCounted = Voxel.new()
	if not c_incremental.materialize(131102026, region, chunk, pre_append_snapshot, 0.5) \
		or not c_incremental.apply_operation(tail_operation):
		return {"valid": false, "reason": "combined_tail_delta_failed"}
	var c_rebuilt: RefCounted = Voxel.new()
	if not c_rebuilt.materialize(131102026, region, chunk, complete_projection, 0.5):
		return {"valid": false, "reason": "combined_complete_materialization_failed"}
	if int(c_incremental.revision) != int(ledger.revision) \
		or c_incremental.densities != c_rebuilt.densities:
		return {"valid": false, "reason": "combined_tail_not_exactly_once"}
	return {"valid": true, "base_revision": int(pre_append_snapshot.revision),
		"published_projection_revision": int(base_projection.revision), "final_revision": int(ledger.revision),
		"voxel_count": c_incremental.densities.size()}


func _voxel_max_node_error(voxel: RefCounted, full_snapshot: Dictionary, region: Vector2i) -> float:
	var maximum_error := 0.0
	for y in range(voxel.ny):
		for z in range(voxel.nz):
			for x in range(voxel.nx):
				var world_point: Vector3 = voxel.world_min + Vector3(x, y, z) * voxel.spacing
				var local_point := world_point - Spatial.region_origin_world(region)
				var expected := Brush.sample_density_snapshot(131102026, region, local_point, false, full_snapshot)
				maximum_error = maxf(maximum_error, absf(float(voxel.densities[voxel._index(x, y, z)]) - expected))
	return maximum_error


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _quit_with_result(root: String) -> void:
	print("P31_R4_ARCH_TESTS_FAIL assertions=%d failures=%s" % [_assertions, JSON.stringify(_failures)])
	quit(1)
