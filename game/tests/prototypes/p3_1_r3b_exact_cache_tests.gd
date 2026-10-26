extends SceneTree

const Brush := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const Field := preload("res://scripts/terrain/sdf_world.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const LodMesher := preload("res://scripts/terrain/lod01_chunk_mesher.gd")
const ExactReplay := preload("res://tests/prototypes/r3b_exact_replay.gd")
const Cache := preload("res://tests/prototypes/r3b_local_mesh_cache.gd")

const SEED := 131102026
var assertions := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var base_root := OS.get_environment("P31_R3B_TEST_ROOT")
	if base_root.is_empty() or not base_root.is_absolute_path() or OS.get_name() != "Windows":
		push_error("P31_R3B_TEST_ROOT must be an absolute disposable Windows TEMP directory")
		quit(2)
		return
	var unique_root := base_root.path_join("fixture-%d-%d" % [Time.get_ticks_usec(), randi()])
	DirAccess.make_dir_recursive_absolute(unique_root)
	_verify_fixture_set()
	_test_replay_algebra()
	_test_fixture_parity()
	_test_cache_locality_and_recovery(unique_root)
	_remove_tree(unique_root)
	if failures == 0:
		print("P31_R3B_TESTS_PASS: assertions=%d failures=0" % assertions)
	else:
		push_error("P31_R3B_TESTS_FAIL: assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_replay_algebra() -> void:
	var ledger: RefCounted = Brush.new(SEED, 1)
	var centers := [Vector3(-16.0, 2.0, -12.0), Vector3(0.0, 1.25, 0.0), Vector3(16.0, 2.5, 12.0)]
	for index in range(48):
		var center: Vector3 = centers[index % centers.size()]
		var mode: int = Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL
		_expect(ledger.add_sphere(mode, center, 0.58), "algebra_command_accepted")
	var ops: Array[Dictionary] = ledger.get_operations_snapshot()
	var snapshot: Dictionary = ledger.get_meshing_snapshot()
	var exact: RefCounted = ExactReplay.new(SEED, snapshot)
	for point in [Vector3(-16.0, 1.75, -12.0), Vector3(-0.0001, 1.15, 5.9), Vector3(0.0, -1.0, 0.0), Vector3(16.0, 2.1, 12.0), Vector3(5.0, 5.5, -5.0)]:
		_expect(_full_replay(point, ops) == exact.sample_density(point), "arbitrary_signed_cave_density_exact")
		_expect(_full_normal(point, ops) == _fast_normal(point, exact), "finite_difference_normal_exact")
	var repeating: Dictionary = _repeating_snapshot(2002, 8192)
	var repeated: RefCounted = ExactReplay.new(SEED, repeating)
	var stats: Dictionary = repeated.stats()
	_expect(int(stats.repeat_period) == 2002 and int(stats.repeat_tail) == 184, "frozen_history_exact_period_detected")
	_expect(int(stats.replay_operations) == 2186 and int(stats.unique_brushes) > 0, "period_collapse_preserves_tail_and_memoizes")
	var point := Vector3(-0.12, 2.1, -0.16)
	var full := _full_replay(point, _period_ops(2002, 8192))
	_expect(full == repeated.sample_density(point), "repeated_minmax_blocks_are_idempotent")
	var nonperiodic := _repeating_snapshot(2002, 2003)
	nonperiodic["centers"][2002] = Vector3(9.0, 9.0, 9.0)
	var fallback: RefCounted = ExactReplay.new(SEED, nonperiodic)
	_expect(int(fallback.stats().repeat_period) == 2003, "one_token_change_disables_period_reduction")
	var radius_ledger: RefCounted = Brush.new(SEED, 1)
	_expect(radius_ledger.add_sphere(Brush.Mode.CARVE, Vector3(2.0, 2.0, 2.0), 0.58), "exact_radius_first_accept")
	_expect(radius_ledger.add_sphere(Brush.Mode.FILL, Vector3(2.0, 2.0, 2.0), 0.5800001), "exact_radius_second_accept")
	var radius_exact: RefCounted = ExactReplay.new(SEED, radius_ledger.get_meshing_snapshot())
	_expect(int(radius_exact.stats().unique_brushes) == 2, "sub_float32_radius_values_do_not_collide")
	_expect(_full_replay(Vector3(2.5, 2.0, 2.0), radius_ledger.get_operations_snapshot()) == radius_exact.sample_density(Vector3(2.5, 2.0, 2.0)), "radius_memoization_density_exact")


func _test_fixture_parity() -> void:
	var filter := OS.get_environment("P31_R3B_TEST_FILTER")
	for layout in ["CONCENTRATED", "DISTRIBUTED"]:
		for count in [256, 640, 2048, 8192]:
			if not filter.is_empty() and filter != "%s-%d" % [layout, count]:
				continue
			var path := "res://tests/fixtures/p3_1_r3b/issue131/P31.EDIT.%s.N%04d.v1.R01.commands.json" % [layout, count]
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			_expect(typeof(parsed) == TYPE_ARRAY and (parsed as Array).size() == count, "frozen_issue131_fixture_present_%s_%d" % [layout, count])
			if typeof(parsed) != TYPE_ARRAY:
				continue
			var ledger: RefCounted = Brush.new(SEED, 1)
			for index in range(count):
				var command: Dictionary = parsed[index]
				var xyz: Array = command.center_mm
				var mode: int = Brush.Mode.CARVE if command.mode == "CARVE" else Brush.Mode.FILL
				_expect(ledger.add_sphere(mode, Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2])) / 1000.0, 0.58), "frozen_operation_accepted")
			var region := Vector2i.ZERO if layout == "CONCENTRATED" else Vector2i(-31, -64)
			var chunk := Vector2i.ZERO if layout == "CONCENTRATED" else Vector2i(2, 2)
			var snap: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
			var exact: RefCounted = ExactReplay.new(SEED, snap, region)
			var exact_world: RefCounted = ExactReplay.new(SEED, snap)
			var exact_full: RefCounted = ExactReplay.new(SEED, ledger.get_meshing_snapshot())
			var ref0: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, snap)
			var opt0: Dictionary = Mesher.build_chunk_cpu_data(SEED, region, chunk, false, {}, Callable(exact, "sample_density"))
			var ref1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region, chunk, snap)
			var opt1: Dictionary = LodMesher.build_chunk_cpu_data(SEED, region, chunk, snap, Callable(exact_world, "sample_density"))
			_expect(_mesh_equal(ref0, opt0), "lod0_exact_mesh_%s_%d" % [layout, count])
			_expect(_mesh_equal(ref1, opt1), "lod1_exact_mesh_%s_%d" % [layout, count])
			var mapped := Spatial.world_to_region_local(Vector3(float(region.x * 16) + 0.125, 1.15, float(region.y * 12) + 5.875))
			var world_point: Vector3 = Spatial.region_local_to_world(mapped.region_key, mapped.local_position)
			var oracle := _full_replay(world_point, ledger.get_operations_snapshot())
			_expect(oracle == exact_full.sample_density(world_point), "history_full_replay_parity_%s_%d" % [layout, count])
			if layout == "CONCENTRATED" and count == 8192:
				var full_exact: RefCounted = ExactReplay.new(SEED, ledger.get_meshing_snapshot())
				var period_stats: Dictionary = full_exact.stats()
				_expect(int(period_stats.repeat_period) == 2002 and int(period_stats.repeat_tail) == 184, "frozen_concentrated_8192_exact_period")
			var reference_picker := _ray_hit(Vector3(world_point.x, 8.0, world_point.z), Vector3.DOWN, ledger.get_operations_snapshot(), Callable())
			var optimized_picker := _ray_hit(Vector3(world_point.x, 8.0, world_point.z), Vector3.DOWN, [], Callable(exact_full, "sample_density"))
			_expect(reference_picker == optimized_picker, "ray_picker_intersection_exact_%s_%d" % [layout, count])


func _test_cache_locality_and_recovery(root: String) -> void:
	var ledger: RefCounted = Brush.new(SEED, 1)
	for index in range(24):
		_expect(ledger.add_sphere(Brush.Mode.CARVE if index % 2 == 0 else Brush.Mode.FILL, Vector3(float(index % 6) * 0.4, 2.0, float(index % 6) * 0.35), 0.58), "cache_fixture_op")
	var region := Vector2i.ZERO
	var chunk := Vector2i.ZERO
	var snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var identity := _cache_identity(snapshot, 0, region, chunk)
	var mesh_builder := func() -> Dictionary: return Mesher.build_chunk_cpu_data(SEED, region, chunk, false, snapshot)
	var cache_root := root.path_join("cache")
	var cache: RefCounted = Cache.new(cache_root)
	var cold: Dictionary = cache.get_or_build(identity, mesh_builder)
	_expect(bool(cold.valid) and not bool(cold.cache_hit), "cache_cold_build")
	var warm: Dictionary = cache.get_or_build(identity, mesh_builder)
	_expect(bool(warm.valid) and bool(warm.cache_hit) and String(warm.cache_layer) == "memory", "cache_memory_hit")
	var disk_cache: RefCounted = Cache.new(cache_root)
	var disk_hit: Dictionary = disk_cache.get_or_build(identity, mesh_builder)
	_expect(bool(disk_hit.valid) and bool(disk_hit.cache_hit) and String(disk_hit.cache_layer) == "disk", "cache_fresh_process_disk_hit")
	var remote_ledger: RefCounted = Brush.new(SEED, 1)
	for operation in ledger.get_operations_snapshot():
		_expect(remote_ledger.add_sphere(int(operation.mode), operation.center_world, float(operation.radius)), "cache_remote_copy")
	_expect(remote_ledger.add_sphere(Brush.Mode.CARVE, Vector3(16000.0, 2.0, -12000.0), 0.58), "cache_remote_edit_accepted")
	var remote_snapshot: Dictionary = remote_ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var remote_identity := _cache_identity(remote_snapshot, 0, region, chunk)
	_expect(remote_identity.key == identity.key, "remote_edit_preserves_dependency_identity")
	var remote_cache: RefCounted = Cache.new(cache_root)
	var remote_hit: Dictionary = remote_cache.get_or_build(remote_identity, mesh_builder)
	_expect(bool(remote_hit.valid) and bool(remote_hit.cache_hit), "provably_remote_edit_cache_hit")
	_expect(remote_ledger.add_sphere(Brush.Mode.FILL, Vector3(0.1, 2.0, 0.1), 0.58), "cache_local_edit_accepted")
	var local_snapshot: Dictionary = remote_ledger.get_meshing_snapshot_for_chunk(region, chunk)
	var local_identity := _cache_identity(local_snapshot, 0, region, chunk)
	_expect(local_identity.key != identity.key, "local_edit_changes_dependency_identity")
	var local_cache: RefCounted = Cache.new(cache_root)
	var local_result: Dictionary = local_cache.get_or_build(local_identity, func() -> Dictionary: return Mesher.build_chunk_cpu_data(SEED, region, chunk, false, local_snapshot))
	_expect(bool(local_result.valid) and not bool(local_result.cache_hit), "local_edit_cache_miss_rebuild")
	var path := cache_root.path_join(_sha256(var_to_bytes(identity)) + ".bin")
	var corrupt_file := FileAccess.open(path, FileAccess.READ_WRITE)
	if corrupt_file != null:
		corrupt_file.seek_end()
		corrupt_file.store_8(0x7f)
		corrupt_file.flush()
		corrupt_file.close()
	var recovery_cache: RefCounted = Cache.new(cache_root)
	var recovered: Dictionary = recovery_cache.get_or_build(identity, mesh_builder)
	_expect(bool(recovered.get("valid", false)) and not bool(recovered.get("cache_hit", true)) and int(recovery_cache.corrupt_count) == 1, "corrupt_cache_falls_back_to_rebuild")
	_expect(_mesh_equal(cold, recovered), "corrupt_rebuild_matches_authority")
	var oversized_file := FileAccess.open(path, FileAccess.WRITE)
	if oversized_file != null:
		oversized_file.seek(Cache.MAX_DISK_BYTES)
		oversized_file.store_8(0)
		oversized_file.flush()
		oversized_file.close()
	var bounded_cache: RefCounted = Cache.new(cache_root)
	var bounded_rebuild: Dictionary = bounded_cache.get_or_build(identity, mesh_builder)
	_expect(bool(bounded_rebuild.get("valid", false)) and not bool(bounded_rebuild.get("cache_hit", true)), "oversized_cache_entry_rebuilds_without_hit")
	_expect(int(bounded_cache.corrupt_count) == 1 and _mesh_equal(cold, bounded_rebuild), "oversized_cache_entry_rejected_before_payload_decode")
	_expect(int(recovery_cache.stats().disk_bytes) <= Cache.MAX_DISK_BYTES, "cache_disk_quota")
	_expect(int(cache.stats().memory_bytes) <= Cache.MAX_MEMORY_BYTES, "cache_memory_quota")


func _verify_fixture_set() -> void:
	var base := "res://tests/fixtures/p3_1_r3b/issue131/"
	var sums := FileAccess.get_file_as_bytes(base + "SHA256SUMS.txt")
	_expect(_sha256(sums) == "ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1", "fixture_sums_pin")
	var names := DirAccess.get_files_at(base)
	_expect(names.size() == 23, "fixture_file_count")
	for name in names:
		if name == "SHA256SUMS.txt":
			continue
		var expected := ""
		for line in sums.get_string_from_utf8().split("\n"):
			var trimmed := String(line).strip_edges()
			if trimmed.length() < 67 or trimmed.get_file() != name:
				continue
			expected = trimmed.substr(0, 64)
			break
		_expect(not expected.is_empty() and _sha256(FileAccess.get_file_as_bytes(base + name)) == expected, "fixture_artifact_sha_" + name)


func _cache_identity(snapshot: Dictionary, lod: int, region: Vector2i, chunk: Vector2i) -> Dictionary:
	var ordered_ops: Array[Dictionary] = []
	var centers: PackedVector3Array = snapshot.get("centers", PackedVector3Array())
	var radii: PackedFloat64Array = snapshot.get("radii", PackedFloat64Array())
	var modes: PackedByteArray = snapshot.get("modes", PackedByteArray())
	var sequences: PackedInt32Array = snapshot.get("sequences", PackedInt32Array())
	for index in range(centers.size()):
		ordered_ops.append({"sequence": sequences[index], "center": centers[index], "radius": radii[index], "mode": modes[index]})
	var content := {"seed": SEED, "generator": 1, "field": "sdf-v1", "lod": lod, "region": region,
		"chunk": chunk, "mesher": "marching-tetrahedra-v1/lod01-transition-v1", "operations": ordered_ops}
	var digest := _sha256(var_to_bytes(content))
	return {"key": digest, "content": content}


func _repeating_snapshot(period: int, count: int) -> Dictionary:
	var centers := PackedVector3Array()
	var radii := PackedFloat64Array()
	var modes := PackedByteArray()
	for index in range(count):
		var source := index % period
		centers.append(Vector3(float(source % 17) * 0.125, float(source % 11) * 0.1, float(source % 7) * 0.15))
		radii.append(0.58 + float(source % 3) * 0.01)
		modes.append(Brush.Mode.CARVE if source % 2 == 0 else Brush.Mode.FILL)
	return {"centers": centers, "radii": radii, "modes": modes}


func _period_ops(period: int, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(count):
		var source := index % period
		result.append({"sequence": index, "center_world": Vector3(float(source % 17) * 0.125, float(source % 11) * 0.1, float(source % 7) * 0.15),
			"radius": 0.58 + float(source % 3) * 0.01, "mode": Brush.Mode.CARVE if source % 2 == 0 else Brush.Mode.FILL})
	return result


func _full_replay(point: Vector3, operations: Array[Dictionary]) -> float:
	var mapped := Spatial.world_to_region_local(point)
	if not bool(mapped.get("valid", false)):
		return NAN
	var region_key: Vector2i = mapped.region_key
	var local_position: Vector3 = mapped.local_position
	var density := Field.sample_density(SEED, region_key, local_position)
	var canonical_world := Spatial.region_local_to_world(region_key, local_position)
	for operation in operations:
		var signed_distance := canonical_world.distance_to(operation.center_world) - float(operation.radius)
		if int(operation.mode) == Brush.Mode.CARVE:
			density = minf(density, signed_distance)
		else:
			density = maxf(density, -signed_distance)
	return density


func _full_normal(point: Vector3, operations: Array[Dictionary]) -> Vector3:
	var e := Grid.SAMPLE_STEP * 0.5
	return Vector3(_full_replay(point + Vector3.RIGHT * e, operations) - _full_replay(point - Vector3.RIGHT * e, operations),
		_full_replay(point + Vector3.UP * e, operations) - _full_replay(point - Vector3.UP * e, operations),
		_full_replay(point + Vector3.BACK * e, operations) - _full_replay(point - Vector3.BACK * e, operations)).normalized()


func _fast_normal(point: Vector3, evaluator: RefCounted) -> Vector3:
	var e := Grid.SAMPLE_STEP * 0.5
	return Vector3(evaluator.sample_density(point + Vector3.RIGHT * e) - evaluator.sample_density(point - Vector3.RIGHT * e),
		evaluator.sample_density(point + Vector3.UP * e) - evaluator.sample_density(point - Vector3.UP * e),
		evaluator.sample_density(point + Vector3.BACK * e) - evaluator.sample_density(point - Vector3.BACK * e)).normalized()


func _ray_hit(origin: Vector3, direction: Vector3, operations: Array[Dictionary], optimized: Callable) -> Vector3:
	var previous_point := origin
	var previous_density := _full_replay(previous_point, operations) if not optimized.is_valid() else float(optimized.call(previous_point))
	for index in range(1, 256):
		var point := origin + direction * (float(index) * Grid.SAMPLE_STEP * 0.5)
		var density := _full_replay(point, operations) if not optimized.is_valid() else float(optimized.call(point))
		if previous_density >= 0.0 and density < 0.0:
			var low := previous_point
			var high := point
			for _iteration in range(20):
				var middle := (low + high) * 0.5
				var value := _full_replay(middle, operations) if not optimized.is_valid() else float(optimized.call(middle))
				if value >= 0.0:
					low = middle
				else:
					high = middle
			return (low + high) * 0.5
		previous_point = point
		previous_density = density
	return Vector3(INF, INF, INF)


func _mesh_equal(left: Dictionary, right: Dictionary) -> bool:
	if not bool(left.get("valid", false)) or not bool(right.get("valid", false)):
		return false
	var equal: bool = var_to_bytes(left.get("positions", PackedVector3Array())) == var_to_bytes(right.get("positions", PackedVector3Array())) \
		and var_to_bytes(left.get("normals", PackedVector3Array())) == var_to_bytes(right.get("normals", PackedVector3Array())) \
		and int(left.get("triangle_count", -1)) == int(right.get("triangle_count", -2)) \
		and int(left.get("sample_count", -1)) == int(right.get("sample_count", -2))
	if not equal:
		var left_positions: PackedVector3Array = left.get("positions", PackedVector3Array())
		var right_positions: PackedVector3Array = right.get("positions", PackedVector3Array())
		var left_normals: PackedVector3Array = left.get("normals", PackedVector3Array())
		var right_normals: PackedVector3Array = right.get("normals", PackedVector3Array())
		var first_mismatch := -1
		for index in range(mini(left_positions.size(), right_positions.size())):
			if left_positions[index] != right_positions[index]:
				first_mismatch = index
				break
		var first_normal := -1
		for index in range(mini(left_normals.size(), right_normals.size())):
			if left_normals[index] != right_normals[index]:
				first_normal = index
				break
		print("MESH_DIFF pos_eq=%s norm_eq=%s left_v=%d right_v=%d left_samples=%d right_samples=%d first_pos=%d left=%s right=%s first_normal=%d nleft=%s nright=%s keys=%s" % [str(left_positions == right_positions), str(left_normals == right_normals), left_positions.size(), right_positions.size(), int(left.get("sample_count", -1)), int(right.get("sample_count", -1)), first_mismatch, str(left_positions[first_mismatch]) if first_mismatch >= 0 else "none", str(right_positions[first_mismatch]) if first_mismatch >= 0 else "none", first_normal, str(left_normals[first_normal]) if first_normal >= 0 else "none", str(right_normals[first_normal]) if first_normal >= 0 else "none", str(left.keys())])
	return equal


func _expect(condition: bool, name: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + name)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
