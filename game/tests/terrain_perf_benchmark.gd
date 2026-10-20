extends SceneTree

const Mesher := preload("res://scripts/terrain/marching_tetrahedra.gd")
const BrushState := preload("res://scripts/terrain/sdf_brush_edit_state.gd")
const WorldState := preload("res://scripts/terrain/terrain_world_state.gd")
const Grid := preload("res://scripts/terrain/terrain_chunk_grid.gd")
const MeshJob := preload("res://scripts/terrain/terrain_mesh_job.gd")
const Spatial := preload("res://scripts/terrain/terrain_spatial_ownership.gd")
const SEED := 424242
const REPEATS := 5
const REGION_KEYS := [
	Vector2i(-2, -2), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2),
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-2, -1),
	Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-2, 1),
]
var assertion_count := 0
var failure_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("TERRAIN_PERF_BENCH: godot=%s seed=%d repeats=%d chunk=(1,1) levels=0,32,64,128,256" % [Engine.get_version_info().string, SEED, REPEATS])
	for edit_count in [0, 32, 64, 128, 256]:
		var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var ledger := BrushState.new(SEED)
		for index in range(edit_count):
			var mode := BrushState.Mode.CARVE if index % 2 == 0 else BrushState.Mode.FILL
			var key: Vector2i = REGION_KEYS[index % REGION_KEYS.size()]
			var origin := Spatial.region_origin_world(key)
			var lane := float((index / REGION_KEYS.size()) % 4) * 0.22
			var center := origin + Vector3(7.2 + lane, 3.2, 5.2 + lane)
			if index % 8 == 0:
				center = origin + Vector3(15.35, 3.2, 11.35)
			var accepted: bool = ledger.add_sphere(mode, center, 1.25)
			if not accepted:
				push_error("PERF_BENCH_SETUP_FAIL: operation %d rejected" % index)
				quit(1)
		var memory_after_ledger := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var elapsed_accelerated := PackedInt64Array()
		var elapsed_full := PackedInt64Array()
		var pool_wait := PackedInt64Array()
		var worker_cpu := PackedInt64Array()
		var stage_samples: Dictionary = {
			"sdf_and_ledger": PackedInt64Array(),
			"triangulation_and_face_normals": PackedInt64Array(),
			"shared_gradient_normals": PackedInt64Array(),
			"array_mesh_build": PackedInt64Array(),
		}
		var filtered_snapshot: Dictionary = ledger.get_meshing_snapshot_for_chunk(Vector2i.ZERO, Vector2i(1, 1))
		var payload_bytes := int(filtered_snapshot["centers"].size()) * 24 \
			+ int(filtered_snapshot["radii"].size()) * 8 \
			+ int(filtered_snapshot["modes"].size()) \
			+ int(filtered_snapshot["sequences"].size()) * 4
		for repetition in range(REPEATS + 1):
			var reference_started := Time.get_ticks_usec()
			var reference: Dictionary = Mesher.build_chunk_mesh(
				SEED, Vector2i.ZERO, Vector2i(1, 1), false, ledger if edit_count > 0 else null
			)
			var reference_usec := Time.get_ticks_usec() - reference_started
			if not reference.get("valid", false):
				push_error("PERF_BENCH_REFERENCE_FAIL: edit_count=%d" % edit_count)
				quit(1)
				return
			var accelerated_started := Time.get_ticks_usec()
			var cpu_result: Dictionary = Mesher.build_chunk_cpu_data(
				SEED, Vector2i.ZERO, Vector2i(1, 1), false,
				filtered_snapshot if edit_count > 0 else null
			)
			var accelerated_usec := Time.get_ticks_usec() - accelerated_started
			var mesh_result: Dictionary = Mesher.mesh_from_cpu_data(cpu_result)
			accelerated_usec += int(cpu_result.get("timings_usec", {}).get("array_mesh_build", 0))
			if not mesh_result.get("valid", false):
				push_error("PERF_BENCH_FILTERED_BUILD_FAIL: edit_count=%d" % edit_count)
				quit(1)
				return
			if not _meshes_exactly_equal(reference["mesh"], mesh_result["mesh"]):
				push_error("PERF_BENCH_GEOMETRY_MISMATCH: edit_count=%d candidates=%d" % [edit_count, filtered_snapshot["candidate_operation_count"]])
				quit(1)
				return
			var job := MeshJob.new(SEED, Vector2i.ZERO, Vector2i(1, 1), false, filtered_snapshot if edit_count > 0 else null, Time.get_ticks_usec())
			var submitted_usec := Time.get_ticks_usec()
			var task_id := WorkerThreadPool.add_task(Callable(job, "run"), true, "terrain history benchmark")
			await _wait_for_tasks([task_id])
			if task_id < 0 or not job.result.get("valid", false):
				push_error("PERF_BENCH_WORKER_FAIL: edit_count=%d" % edit_count)
				quit(1)
				return
			var worker_mesh: Dictionary = Mesher.mesh_from_cpu_data(job.result)
			if not _meshes_exactly_equal(reference["mesh"], worker_mesh["mesh"]):
				push_error("PERF_BENCH_WORKER_GEOMETRY_MISMATCH: edit_count=%d" % edit_count)
				quit(1)
				return
			if repetition == 0:
				continue # warm-up is excluded from reported distributions
			elapsed_full.append(reference_usec)
			elapsed_accelerated.append(accelerated_usec)
			pool_wait.append(maxi(0, job.worker_started_usec - submitted_usec))
			worker_cpu.append(job.worker_finished_usec - job.worker_started_usec)
			for key in stage_samples:
				stage_samples[key].append(int(cpu_result.get("timings_usec", {}).get(key, 0)))
		print("TERRAIN_PERF_HISTORY: ops=%d samples=%d candidates=%d snapshot_bytes=%d static_memory_before/ledger/delta=%d/%d/%d full_p50/p95_ms=%.3f/%.3f accelerated_p50/p95_ms=%.3f/%.3f worker_cpu_p50/p95_ms=%.3f/%.3f pool_wait_p50/p95_ms=%.3f/%.3f sdf_p50_ms=%.3f triangulation_p50_ms=%.3f normals_p50_ms=%.3f mesh_cpu_p50_ms=%.3f" % [
			edit_count, REPEATS, filtered_snapshot["candidate_operation_count"], payload_bytes,
			memory_before, memory_after_ledger, memory_after_ledger - memory_before,
			_percentile(_sorted(elapsed_full), 0.50) / 1000.0, _percentile(_sorted(elapsed_full), 0.95) / 1000.0,
			_percentile(_sorted(elapsed_accelerated), 0.50) / 1000.0, _percentile(_sorted(elapsed_accelerated), 0.95) / 1000.0,
			_percentile(_sorted(worker_cpu), 0.50) / 1000.0, _percentile(_sorted(worker_cpu), 0.95) / 1000.0,
			_percentile(_sorted(pool_wait), 0.50) / 1000.0, _percentile(_sorted(pool_wait), 0.95) / 1000.0,
			_percentile(_sorted(stage_samples["sdf_and_ledger"]), 0.50) / 1000.0,
			_percentile(_sorted(stage_samples["triangulation_and_face_normals"]), 0.50) / 1000.0,
			_percentile(_sorted(stage_samples["shared_gradient_normals"]), 0.50) / 1000.0,
			_percentile(_sorted(stage_samples["array_mesh_build"]), 0.50) / 1000.0,
		])
		_check(true, "full and spatially filtered geometry/normals are identical for %d operations" % edit_count)
	var parallel_jobs: Array[MeshJob] = []
	var parallel_task_ids: Array[int] = []
	var parallel_coords: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]
	for coordinate in parallel_coords:
		var job: MeshJob = MeshJob.new(SEED, Vector2i(-1, 0), coordinate, false, null, Time.get_ticks_usec())
		parallel_jobs.append(job)
		parallel_task_ids.append(WorkerThreadPool.add_task(Callable(job, "run"), false, "terrain parallel equivalence"))
	await _wait_for_tasks(parallel_task_ids)
	var worker_threads: Dictionary = {}
	for index in range(parallel_jobs.size()):
		var job := parallel_jobs[index]
		worker_threads[job.worker_thread_id] = true
		var threaded_mesh: Dictionary = Mesher.mesh_from_cpu_data(job.result)
		var serial_mesh: Dictionary = Mesher.build_chunk_mesh(SEED, Vector2i(-1, 0), parallel_coords[index])
		_check(_meshes_exactly_equal(threaded_mesh["mesh"], serial_mesh["mesh"]), "parallel task preserves exact chunk geometry %s" % parallel_coords[index])
	_check(parallel_task_ids.all(func(task_id: int) -> bool: return task_id >= 0), "four CPU mesh tasks are accepted by the worker pool")
	_check(worker_threads.size() >= 2, "worker mesh calculations execute concurrently on multiple worker threads")
	if failure_count == 0:
		print("TERRAIN_PERF_BENCH_PASS: assertions=%d failures=0" % assertion_count)
		quit(0)
	else:
		push_error("TERRAIN_PERF_BENCH_FAIL: assertions=%d failures=%d" % [assertion_count, failure_count])
		quit(1)


func _sorted(values: PackedInt64Array) -> PackedInt64Array:
	var result := values.duplicate()
	result.sort()
	return result


func _percentile(values: PackedInt64Array, fraction: float) -> int:
	if values.is_empty():
		return 0
	var index := clampi(ceili(float(values.size()) * fraction) - 1, 0, values.size() - 1)
	return values[index]


func _wait_for_tasks(task_ids: Array[int]) -> void:
	while true:
		var all_complete := true
		for task_id in task_ids:
			if task_id >= 0 and not WorkerThreadPool.is_task_completed(task_id):
				all_complete = false
				break
		if all_complete:
			break
		await process_frame
	for task_id in task_ids:
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)


func _meshes_exactly_equal(left: ArrayMesh, right: ArrayMesh) -> bool:
	if left.get_surface_count() != right.get_surface_count():
		return false
	if left.get_surface_count() == 0:
		return true
	var left_arrays: Array = left.surface_get_arrays(0)
	var right_arrays: Array = right.surface_get_arrays(0)
	return left_arrays[Mesh.ARRAY_VERTEX] == right_arrays[Mesh.ARRAY_VERTEX] \
		and left_arrays[Mesh.ARRAY_NORMAL] == right_arrays[Mesh.ARRAY_NORMAL]


func _check(condition: bool, message: String) -> void:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error("PERF_BENCH_ASSERTION_FAILED: " + message)
